// pagar-pedido
//
// Cobra un pedido con tarjeta a traves de Mercado Pago (Checkout API, **API de
// Orders**) y, si el pago sale aprobado, lo manda al local.
//
// Se usa Orders y no la vieja API de Payments porque Mercado Pago dejo Payments
// en mantenimiento (solo correcciones de seguridad) y Orders es la que sostiene
// de ahora en mas. Un cobro genera dos ids: la orden (ORD01...) y adentro el
// pago (PAY01...). El de la orden es el que viaja en los webhooks, por eso se
// guardan los dos.
//
// Los datos de la tarjeta NO pasan por aca: la app se los manda directo a
// Mercado Pago, que devuelve un `token` de un solo uso. Aca llega ese token.
// Es el mismo esquema que usan las apps grandes de delivery.
//
// Acciones (campo `accion`):
//   * pagar (por defecto): cobra el pedido con un token (tarjeta nueva) o con
//     una tarjeta guardada (card_id + token con el codigo de seguridad).
//   * tarjetas: lista las tarjetas guardadas del cliente.
//   * borrar_tarjeta: la saca de Mercado Pago y de la base.
//   * plus: cobra un mes de MODO YA Plus y activa la suscripcion.
//   * renovar_plus: la llama el cron de la base (service_role, no un usuario)
//     para volver a cobrarle a los que se les vence hoy.
//
// Por que es una Edge Function y no una RPC: cobrar necesita el access token de
// Mercado Pago, que no puede vivir dentro de una app que se instala. Aca existe
// solo en el servidor (secreto MP_ACCESS_TOKEN).
//
// Si la tarjeta rebota el pedido NO se cancela: queda esperando para que el
// cliente pruebe con otra (lo cierra cerrar_pagos_vencidos a la media hora).
//
// Quien puede cobrar y con que clave de idempotencia lo decide la base
// (`tomar_el_cobro`, 0068). La clave no sale del token de la tarjeta: la app
// pide un token nuevo en cada intento, asi que dos toques de "Pagar" daban dos
// claves y Mercado Pago cobraba dos veces.
//
// MODO SIMULADO: sin MP_ACCESS_TOKEN configurado —o cuando la app manda un
// token simulado porque se compilo sin clave publica— no se llama a Mercado
// Pago y se responde como si la tarjeta hubiera sido aprobada. El nombre del
// titular elige el camino, para poder probarlos todos: "RECHAZADA" rebota y
// "REVISION" deja el pago esperando al banco. Sirve para mostrar la pantalla
// antes de tener la cuenta; nunca cobra plata de verdad.

import { createClient } from 'npm:@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const MP = 'https://api.mercadopago.com';
const MP_TOKEN = Deno.env.get('MP_ACCESS_TOKEN') ?? '';
const SIMULADO = MP_TOKEN === '';

interface Cuerpo {
  accion?: 'pagar' | 'tarjetas' | 'borrar_tarjeta' | 'plus' | 'renovar_plus';
  pedido_id?: string;
  /** Token de un solo uso que devuelve Mercado Pago en la app. */
  token?: string;
  /** Tarjeta guardada con la que paga (si no es una nueva). */
  card_id?: string;
  cuotas?: number;
  /** "visa", "master"... lo dice Mercado Pago al tokenizar. */
  metodo_pago_id?: string;
  guardar?: boolean;
  /** Para mostrar "Visa ••••4218" sin volver a preguntarle a Mercado Pago. */
  marca?: string;
  ultimos4?: string;
  vence_mes?: number;
  vence_anio?: number;
  titular?: string;
  tarjeta_id?: string;
}

function responder(cuerpo: unknown, status = 200) {
  return new Response(JSON.stringify(cuerpo), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
}

/** Llama a Mercado Pago y devuelve la respuesta cruda, sin juzgarla. */
async function mpCrudo(ruta: string, init: RequestInit = {}) {
  const r = await fetch(`${MP}${ruta}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${MP_TOKEN}`,
      'Content-Type': 'application/json',
      ...(init.headers ?? {}),
    },
  });
  const cuerpo = await r.json().catch(() => ({}));
  if (!r.ok) console.error('mercado pago', ruta, r.status, JSON.stringify(cuerpo));
  return { ok: r.ok, status: r.status, cuerpo };
}

/** Llama a Mercado Pago y devuelve el JSON, con el error legible si falla. */
async function mp(ruta: string, init: RequestInit = {}) {
  const r = await mpCrudo(ruta, init);
  if (!r.ok) {
    throw new Error(r.cuerpo?.message ?? `Mercado Pago respondio ${r.status}`);
  }
  return r.cuerpo;
}

/** Los importes de Orders viajan como texto con dos decimales ("10500.00"). */
function importe(pesos: number): string {
  return pesos.toFixed(2);
}

/** Crea una orden y devuelve lo unico que nos importa de la respuesta.
 *
 * Ojo con los codigos HTTP: una tarjeta rechazada vuelve como **402**, no como
 * 200, pero con la orden entera adentro de `data`. Eso no es un error nuestro,
 * es un "no" del banco y hay que contarselo al cliente. Si en cambio viene un
 * 4xx **sin** orden (token vencido, credenciales mal, importe invalido), ahi si
 * rompimos nosotros: se lanza para que quede en el log y no se le mienta al
 * cliente diciendole que la tarjeta fallo.
 */
async function crearOrden(cuerpo: unknown, idempotencia: string) {
  const r = await mpCrudo('/v1/orders', {
    method: 'POST',
    headers: { 'X-Idempotency-Key': idempotencia },
    body: JSON.stringify(cuerpo),
  });

  // En el caso feliz la orden viene en la raiz; cuando rebota, adentro de data.
  const orden = r.ok ? r.cuerpo : (r.cuerpo?.data ?? null);
  if (!orden) {
    const detalle = r.cuerpo?.errors?.[0]?.message ?? r.cuerpo?.message;
    throw new Error(detalle ?? `Mercado Pago respondio ${r.status}`);
  }

  // El estado que vale es el del pago; el de la orden lo acompaña.
  const pago = orden?.transactions?.payments?.[0] ?? {};
  const estadoMp = String(pago.status ?? orden?.status ?? '');
  const detalleMp = String(pago.status_detail ?? orden?.status_detail ?? '');

  return {
    ordenId: orden?.id ? String(orden.id) : null,
    pagoId: pago?.id ? String(pago.id) : null,
    // processed = aprobado. processing / action_required / created = todavia no
    // se sabe (revision manual, 3DS). El resto es que no entro.
    estado: estadoMp === 'processed'
      ? 'acreditado' as const
      : ['processing', 'action_required', 'created'].includes(estadoMp)
        ? 'pendiente' as const
        : 'rechazado' as const,
    detalleMp,
  };
}

/** El cliente como "customer" de Mercado Pago, que es lo que permite guardar
 *  tarjetas. Si ya lo era, se reusa.
 *
 * **Nunca frena el cobro.** Si Mercado Pago no deja crear el customer, se
 * devuelve null y se cobra igual, sin guardar la tarjeta: quedarse sin la
 * comodidad de la proxima vez es molesto, no poder pagar es perder la venta.
 * (Pasa, por ejemplo, con credenciales de cuenta de prueba: la API de
 * customers las rechaza con "Unauthorized use of live credentials".)
 */
// deno-lint-ignore no-explicit-any
async function customerDe(servicio: any, cliente: any, email: string | undefined) {
  if (cliente.mp_customer_id) return cliente.mp_customer_id as string;

  try {
    const buscado = await mp(`/v1/customers/search?email=${encodeURIComponent(email ?? '')}`);
    const id = buscado?.results?.[0]?.id ??
      (await mp('/v1/customers', {
        method: 'POST',
        body: JSON.stringify({ email, first_name: cliente.nombre }),
      })).id;

    await servicio.from('clientes').update({ mp_customer_id: id }).eq('id', cliente.id);
    cliente.mp_customer_id = id;
    return id as string;
  } catch (e) {
    console.error('no se pudo crear el customer (se cobra igual)', e);
    return null;
  }
}

/** Guarda la tarjeta en Mercado Pago y deja la referencia en la base.
 *
 * Nunca frena el flujo: el cobro ya salio, y quedarse sin la tarjeta guardada
 * es una molestia para la proxima, no un problema de plata.
 */
// deno-lint-ignore no-explicit-any
async function guardarTarjeta(servicio: any, cliente: any, customerId: string, c: Cuerpo) {
  try {
    const tarjeta = await mp(`/v1/customers/${customerId}/cards`, {
      method: 'POST',
      body: JSON.stringify({ token: c.token }),
    });
    await servicio.from('tarjetas_guardadas').insert({
      cliente_id: cliente.id,
      mp_card_id: tarjeta.id,
      marca: tarjeta.payment_method?.id ?? c.marca ?? 'tarjeta',
      ultimos4: tarjeta.last_four_digits ?? c.ultimos4,
      vence_mes: tarjeta.expiration_month ?? c.vence_mes,
      vence_anio: tarjeta.expiration_year ?? c.vence_anio,
      titular: tarjeta.cardholder?.name ?? c.titular,
      predeterminada: true,
    });
  } catch (e) {
    console.error('guardar tarjeta', e);
  }
}

/** Mensajes de Mercado Pago traducidos a algo que entienda el cliente. */
function motivo(detalle: string): string {
  const mapa: Record<string, string> = {
    // Nombres de la API de Orders.
    insufficient_amount: 'La tarjeta no tiene fondos suficientes.',
    card_insufficient_amount: 'La tarjeta no tiene fondos suficientes.',
    amount_limit_exceeded: 'El monto supera el límite de la tarjeta.',
    bad_filled_card_data: 'Revisá los datos de la tarjeta.',
    invalid_card_token: 'No se pudo leer la tarjeta. Cargala de nuevo.',
    card_disabled: 'La tarjeta está inhabilitada. Llamá a tu banco.',
    high_risk: 'El banco no autorizó el pago. Probá con otra tarjeta.',
    required_call_for_authorize: 'Tenés que autorizar este pago con tu banco.',
    max_attempts_exceeded: 'Demasiados intentos. Probá con otra tarjeta.',
    rejected_by_issuer: 'El banco rechazó el pago. Probá con otra tarjeta.',
    invalid_installments: 'Esa cantidad de cuotas no está disponible.',
    processing_error: 'No se pudo procesar la tarjeta. Probá de nuevo.',
    '3ds_challenge_expired': 'Se venció el tiempo para validar con tu banco.',
    failed: 'El pago fue rechazado. Probá con otra tarjeta.',
    invalid_users_involved: 'No se pudo procesar el pago. Probá con otra tarjeta.',
    cc_amount_rate_limit_exceeded: 'El monto supera el límite permitido.',

    // Nombres de la API vieja (Payments), por si alguno sigue llegando.
    cc_rejected_insufficient_amount: 'La tarjeta no tiene fondos suficientes.',
    cc_rejected_bad_filled_card_number: 'Revisá el número de la tarjeta.',
    cc_rejected_bad_filled_date: 'Revisá la fecha de vencimiento.',
    cc_rejected_bad_filled_security_code: 'Revisá el código de seguridad.',
    cc_rejected_bad_filled_other: 'Revisá los datos de la tarjeta.',
    cc_rejected_high_risk: 'El banco no autorizó el pago. Probá con otra tarjeta.',
    cc_rejected_max_attempts: 'Demasiados intentos. Probá con otra tarjeta.',
    cc_rejected_call_for_authorize: 'Tenés que autorizar este pago con tu banco.',
    cc_rejected_card_disabled: 'La tarjeta está inhabilitada. Llamá a tu banco.',
    cc_rejected_duplicated_payment: 'Ya hiciste un pago igual hace un momento.',
    cc_rejected_card_error: 'No se pudo procesar la tarjeta. Probá de nuevo.',
  };
  return mapa[detalle] ?? 'El pago fue rechazado. Probá con otra tarjeta.';
}

/** Vuelve a cobrarle Plus a todos los que se les vence hoy.
 *
 * Con la tarjeta guardada no hay codigo de seguridad para pedir: Mercado Pago
 * da un token a partir del `card_id`, que es como se cobran las suscripciones.
 * Si la tarjeta rebota se anota el motivo; al tercer intento la base deja de
 * incluirla y el cliente renueva a mano.
 *
 * **La clave de idempotencia identifica el periodo, no la suscripcion**
 * (hallazgo A2). Antes era `plus-renovacion-<suscripcion>`, la misma todos los
 * dias: con la ventana de idempotencia de Mercado Pago vencida —las corridas
 * estan a 24 h— era un cobro nuevo cada dia, y sin vencer era la respuesta
 * cacheada y la renovacion no se activaba nunca.
 *
 * Y si el cobro sale bien pero no se puede dar el mes, la suscripcion **sale de
 * la cola** (`plus_renovacion_trabada`): dejarla vencida es lo que hacia que el
 * cron la devolviera al dia siguiente.
 */
// deno-lint-ignore no-explicit-any
async function renovarPlus(servicio: any) {
  const { data: pendientes, error } = await servicio.rpc('plus_por_renovar');
  if (error) {
    console.error('plus_por_renovar', error);
    return responder({ error: 'No se pudo leer a quien renovarle.' }, 500);
  }

  // El `hasta` de la suscripcion ES el periodo que se esta cobrando, y es lo
  // que hace unica la clave. `plus_por_renovar` no lo devuelve y agregarle una
  // columna pedia borrar la funcion (0068 es aditiva), asi que se lee aca de
  // una sola vez para todas.
  // deno-lint-ignore no-explicit-any
  const ids = (pendientes ?? []).map((s: any) => s.suscripcion_id);
  const periodoDe = new Map<string, string>();
  if (ids.length > 0) {
    const { data: filas, error: errPeriodos } = await servicio
      .from('suscripciones_plus').select('id, hasta').in('id', ids);
    if (errPeriodos) {
      console.error('periodo de las suscripciones', errPeriodos);
      return responder({ error: 'No se pudo leer el período a cobrar.' }, 500);
    }
    for (const f of (filas ?? [])) periodoDe.set(f.id, String(f.hasta));
  }

  let renovadas = 0;
  let fallidas = 0;
  let trabadas = 0;

  for (const s of (pendientes ?? [])) {
    const periodo = periodoDe.get(s.suscripcion_id);
    if (!periodo) {
      // Sin periodo no hay clave que distinga este mes del que viene. Antes de
      // arriesgar un cobro repetido, no se cobra.
      fallidas++;
      console.error('renovar plus: no se pudo leer el período', s.suscripcion_id);
      continue;
    }
    const referencia = `plus-renovacion-${s.suscripcion_id}-${periodo}`;

    // Se distingue "la tarjeta rebotó" de "cobramos y algo fallo despues": lo
    // primero se le cuenta como intento, lo segundo no (seria contarle un
    // rechazo que no existio, y encima ya pago) pero traba la suscripcion.
    let cobrado = false;
    let mpId = '';
    let mpOrden: string | null = null;
    try {
      if (SIMULADO) {
        mpId = `simulado-renovacion-${crypto.randomUUID()}`;
      } else {
        // Token a partir de la tarjeta guardada (pago recurrente, sin CVV).
        const token = await mp('/v1/card_tokens', {
          method: 'POST',
          body: JSON.stringify({ card_id: s.mp_card_id }),
        });
        const r = await crearOrden({
          type: 'online',
          processing_mode: 'automatic',
          total_amount: importe(s.precio),
          external_reference: referencia,
          transactions: {
            payments: [{
              amount: importe(s.precio),
              payment_method: {
                type: 'credit_card',
                token: token.id,
                installments: 1,
                statement_descriptor: 'MODO YA PLUS',
              },
            }],
          },
        }, referencia);

        if (r.estado !== 'acreditado') throw new Error(motivo(r.detalleMp));
        mpId = r.pagoId ?? r.ordenId ?? '';
        mpOrden = r.ordenId;
      }
      cobrado = true;

      // El pago y la activacion van en una sola transaccion de la base: antes
      // el insert en `pagos` descartaba su error y `activar_plus` se llamaba
      // con `p_pago: null`, asi que el cliente podia recibir el mes sin que
      // quedara registro del cobro.
      const { error: alta } = await servicio.rpc('plus_cobrado', {
        p_cliente: s.cliente_id,
        p_precio: s.precio,
        p_mp_payment: mpId,
        p_mp_order: mpOrden,
      });
      if (alta) throw new Error(alta.message);

      renovadas++;
    } catch (e) {
      const texto = e instanceof Error ? e.message : String(e);
      if (cobrado) {
        trabadas++;
        // Se le cobro y no se le pudo dar el mes. Lo grave no es el mes que
        // falta: es que la suscripcion sigue vencida y manana el cron la
        // devuelve. Queda trabada, con el id del pago para encontrarlo en el
        // panel de Mercado Pago, hasta que una persona lo arregle.
        console.error('RENOVACION COBRADA SIN ACTIVAR', s.suscripcion_id, mpId, texto);
        const { error: trabar } = await servicio.rpc('plus_renovacion_trabada', {
          p_suscripcion: s.suscripcion_id,
          p_mp_payment: mpId,
          p_error: texto.slice(0, 300),
        });
        if (trabar) console.error('NO SE PUDO TRABAR LA RENOVACION', s.suscripcion_id, trabar);
      } else {
        fallidas++;
        console.error('renovar plus', s.suscripcion_id, texto);
        await servicio.rpc('plus_renovacion_fallo', {
          p_suscripcion: s.suscripcion_id,
          p_error: texto.slice(0, 300),
        });
      }
    }
  }

  console.log(`renovar_plus: ${renovadas} renovadas, ${fallidas} fallidas, ${trabadas} trabadas`);
  return responder({ renovadas, fallidas, trabadas, simulado: SIMULADO });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });

  const url = Deno.env.get('SUPABASE_URL')!;
  const servicioKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const servicio = createClient(url, servicioKey);

  const jwt = req.headers.get('Authorization')?.replace('Bearer ', '') ?? '';
  const c = (await req.json().catch(() => ({}))) as Cuerpo;
  const accion = c.accion ?? 'pagar';

  // Se simula si no hay credenciales **o si la app no las tenia cuando armo el
  // token**. Una version instalada sin clave publica manda "token-simulado-…";
  // si el servidor intentara cobrar eso contra Mercado Pago, fallaria y el
  // cliente se quedaria sin poder pagar por una actualizacion que no hizo.
  const simulado = SIMULADO || (c.token ?? '').startsWith('token-simulado');

  // ---- Renovacion automatica (la dispara el cron, no una persona) ----------

  if (accion === 'renovar_plus') {
    if (jwt !== servicioKey) return responder({ error: 'No autorizado.' }, 401);
    return await renovarPlus(servicio);
  }

  // Identidad: se verifica aca adentro (la funcion se publica con
  // --no-verify-jwt para que funcione con claves nuevas y viejas).
  const { data: { user } } = await createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
  }).auth.getUser();
  if (!user) return responder({ error: 'Iniciá sesión para pagar.' }, 401);

  const { data: cliente } = await servicio
    .from('clientes').select('id, nombre, mp_customer_id').eq('perfil_id', user.id).maybeSingle();
  if (!cliente) return responder({ error: 'Solo un cliente puede pagar un pedido.' }, 403);

  // ---- Tarjetas guardadas ---------------------------------------------------

  if (accion === 'tarjetas') {
    const { data } = await servicio
      .from('tarjetas_guardadas').select('*').eq('cliente_id', cliente.id).order('creado_en');
    return responder({ tarjetas: data ?? [] });
  }

  if (accion === 'borrar_tarjeta') {
    const { data: t } = await servicio
      .from('tarjetas_guardadas').select('*').eq('id', c.tarjeta_id!).eq('cliente_id', cliente.id).maybeSingle();
    if (!t) return responder({ error: 'La tarjeta no existe.' }, 404);
    if (!simulado && cliente.mp_customer_id) {
      await mp(`/v1/customers/${cliente.mp_customer_id}/cards/${t.mp_card_id}`, { method: 'DELETE' })
        .catch((e) => console.error('borrar tarjeta', e));
    }
    await servicio.from('tarjetas_guardadas').delete().eq('id', t.id);
    return responder({ ok: true });
  }

  // ---- MODO YA Plus: un mes -------------------------------------------------

  if (accion === 'plus') {
    if (!c.token) return responder({ error: 'Faltan los datos de la tarjeta.' }, 400);

    const { data: precio } = await servicio.rpc('precio_plus');
    const monto = Number(precio ?? 2500);
    let estado: 'acreditado' | 'rechazado' | 'pendiente' = 'acreditado';
    let detalle: string | null = null;
    let mpId: string | null = null;
    let mpOrden: string | null = null;

    if (simulado) {
      const rechazar = (c.titular ?? '').trim().toUpperCase() === 'RECHAZADA';
      estado = rechazar ? 'rechazado' : 'acreditado';
      detalle = rechazar ? motivo('insufficient_amount') : null;
      mpId = `simulado-plus-${crypto.randomUUID()}`;
    } else {
      // La suscripcion se renueva sola todos los meses, asi que la tarjeta
      // tiene que quedar guardada: sin eso `plus_por_renovar()` no la ve y la
      // renovacion no se puede cobrar nunca. Por eso se hace siempre, no solo
      // si el cliente lo pide (suscribirse ES autorizar el cobro mensual).
      const customerId = c.card_id ? null : await customerDe(servicio, cliente, user.email);

      const r = await crearOrden({
        type: 'online',
        processing_mode: 'automatic',
        total_amount: importe(monto),
        external_reference: `plus-${cliente.id}`,
        payer: customerId ? { email: user.email, customer_id: customerId } : { email: user.email },
        transactions: {
          payments: [{
            amount: importe(monto),
            payment_method: {
              id: c.metodo_pago_id,
              type: 'credit_card',
              token: c.token,
              installments: 1,
              statement_descriptor: 'MODO YA PLUS',
            },
          }],
        },
      }, `plus-${cliente.id}-${c.token.slice(-16)}`);

      mpId = r.pagoId ?? r.ordenId;
      mpOrden = r.ordenId;
      // Plus se cobra o no se cobra: si queda en revision no se le da el mes.
      estado = r.estado;
      detalle = estado === 'acreditado'
        ? null
        : estado === 'pendiente'
          // No se le dice "probá de nuevo": el cobro esta hecho y volver a
          // intentarlo es pagar dos veces el mismo mes.
          ? 'El banco está revisando el pago. Si lo aprueba te activamos Plus; no lo intentes de nuevo.'
          : motivo(r.detalleMp);

      if (estado === 'acreditado' && customerId) {
        await guardarTarjeta(servicio, cliente, customerId, c);
      }
    }

    if (estado === 'pendiente') {
      // Queda el rastro del cobro, que antes no quedaba: si Mercado Pago lo
      // aprueba despues, sin esta fila el aviso no tiene con que pago
      // emparejarlo y la plata se pierde de vista. Activar el mes sigue siendo
      // de una persona (ver el informe de 0068).
      const { error: rastro } = await servicio.from('pagos').insert({
        metodo: 'mercado_pago', estado: 'pendiente', monto,
        mp_payment_id: mpId, mp_order_id: mpOrden, cuotas: 1, detalle,
      });
      if (rastro) console.error('PLUS EN REVISION SIN RASTRO', mpId, rastro);
    }

    if (estado !== 'acreditado') {
      return responder({ estado, aprobado: false, detalle, simulado });
    }

    // El pago y la activacion en una sola transaccion: antes el insert en
    // `pagos` descartaba su error y `activar_plus` se llamaba con
    // `p_pago: null`, asi que el cliente podia recibir el mes sin que quedara
    // registro del cobro.
    const { data: sus, error } = await servicio.rpc('plus_cobrado', {
      p_cliente: cliente.id,
      p_precio: monto,
      p_mp_payment: mpId,
      p_mp_order: mpOrden,
    });
    if (error) {
      console.error('plus_cobrado', mpId, error);
      return responder({ error: 'Se cobró la suscripción pero no se pudo activar. Escribinos.' }, 500);
    }

    return responder({ estado, aprobado: true, simulado, suscripcion: sus });
  }

  // ---- Pagar ----------------------------------------------------------------

  const { data: pedido } = await servicio
    .from('pedidos').select('*').eq('id', c.pedido_id!).maybeSingle();
  if (!pedido || pedido.cliente_id !== cliente.id) {
    return responder({ error: 'El pedido no existe.' }, 404);
  }
  if (pedido.estado !== 'pendiente_pago') {
    return responder({ error: 'Este pedido ya no está esperando el pago.' }, 409);
  }
  if (!c.token) return responder({ error: 'Faltan los datos de la tarjeta.' }, 400);

  // La base dice si se puede cobrar y con que clave de idempotencia (0068).
  //
  // La clave la da ella y no el token de la tarjeta: la app pide un token nuevo
  // en cada intento, asi que dos toques de "Pagar" daban dos claves distintas y
  // Mercado Pago cobraba dos veces (hallazgo A3). Ahora la clave cuenta el
  // intento del pedido, y un cobro que el banco todavia esta revisando no deja
  // arrancar otro.
  const { data: toma, error: errToma } = await servicio.rpc('tomar_el_cobro', {
    p_pedido: pedido.id,
  });
  if (errToma) {
    console.error('tomar_el_cobro', errToma);
    return responder({ error: 'No se pudo empezar el cobro. Probá de nuevo.' }, 500);
  }
  const t = (Array.isArray(toma) ? toma[0] : toma) ?? {};
  if (!t.clave) {
    // "En revision" y "en curso" NO son errores: hay un cobro hecho o en
    // vuelo. Se contestan como pago pendiente para que la app los muestre como
    // informacion y no en la tarjeta roja — que es justamente lo que hacia que
    // el cliente lo leyera como un fallo y volviera a tocar "Pagar".
    if (t.motivo === 'en_revision' || t.motivo === 'en_curso') {
      return responder({ estado: 'pendiente', aprobado: false, detalle: t.mensaje, simulado });
    }
    return responder({ error: t.mensaje ?? 'Este pedido ya no está esperando el pago.' }, 409);
  }
  const claveDelCobro = t.clave as string;

  const cuotas = Math.min(Math.max(c.cuotas ?? 1, 1), 24);
  let estado: 'acreditado' | 'rechazado' | 'pendiente' = 'acreditado';
  let detalle: string | null = null;
  let mpPaymentId: string | null = null;
  let mpOrderId: string | null = null;

  if (simulado) {
    // Sin credenciales: se responde sin cobrar nada. El nombre del titular
    // elige el camino, igual que las tarjetas de prueba de Mercado Pago:
    // "RECHAZADA" rebota y "REVISION" deja el pago en revision, que es el
    // unico modo de ejercitar los hallazgos A1 y A3 sin tocar la API real.
    const comoSalio = (c.titular ?? '').trim().toUpperCase();
    estado = comoSalio === 'RECHAZADA'
      ? 'rechazado'
      : comoSalio === 'REVISION'
        ? 'pendiente'
        : 'acreditado';
    detalle = estado === 'rechazado'
      ? motivo('insufficient_amount')
      : estado === 'pendiente'
        ? 'El banco está revisando el pago. Te avisamos apenas se confirme.'
        : 'Pago simulado (sin credenciales de Mercado Pago)';
    mpPaymentId = `simulado-${crypto.randomUUID()}`;
    mpOrderId = `simulado-orden-${crypto.randomUUID()}`;
  } else {
    // Cliente de Mercado Pago (para poder guardar tarjetas).
    const customerId = c.guardar ? await customerDe(servicio, cliente, user.email) : null;

    const r = await crearOrden({
      type: 'online',
      processing_mode: 'automatic',
      total_amount: importe(pedido.total),
      external_reference: pedido.id,
      description: `MODO YA pedido ${pedido.codigo}`,
      payer: customerId ? { email: user.email, customer_id: customerId } : { email: user.email },
      transactions: {
        payments: [{
          amount: importe(pedido.total),
          payment_method: {
            id: c.metodo_pago_id,
            type: 'credit_card',
            token: c.token,
            installments: cuotas,
            statement_descriptor: 'MODO YA',
          },
        }],
      },
    }, claveDelCobro);

    mpOrderId = r.ordenId;
    mpPaymentId = r.pagoId ?? r.ordenId;
    estado = r.estado;
    detalle = estado === 'acreditado'
      ? null
      : estado === 'pendiente'
        // El banco lo esta revisando: no fallo nada, hay que esperar. Decirle
        // "rechazado" lo manda a pagar de nuevo y termina pagando dos veces.
        ? 'El banco está revisando el pago. Te avisamos apenas se confirme.'
        : motivo(r.detalleMp);

    // Guardar la tarjeta para la proxima (Mercado Pago la guarda, nosotros solo
    // la referencia y los ultimos cuatro numeros).
    if (estado === 'acreditado' && c.guardar && customerId && !c.card_id) {
      await guardarTarjeta(servicio, cliente, customerId, c);
    }
  }

  if (simulado && c.guardar && estado === 'acreditado' && c.ultimos4) {
    await servicio.from('tarjetas_guardadas').insert({
      cliente_id: cliente.id,
      mp_card_id: `simulada-${c.ultimos4}-${Date.now()}`,
      marca: c.marca ?? 'tarjeta',
      ultimos4: c.ultimos4,
      vence_mes: c.vence_mes ?? 12,
      vence_anio: c.vence_anio ?? 2030,
      titular: c.titular,
      predeterminada: true,
    });
  }

  const { data: ped, error } = await servicio.rpc('confirmar_pago_online', {
    p_pedido: pedido.id,
    p_mp_payment: mpPaymentId,
    p_estado: estado,
    p_cuotas: cuotas,
    p_detalle: detalle,
    p_mp_order: mpOrderId,
  });
  if (error) {
    console.error('confirmar_pago_online', error);
    return responder({ error: 'El pago se procesó pero no se pudo actualizar el pedido.' }, 500);
  }

  return responder({
    estado,
    detalle,
    aprobado: estado === 'acreditado',
    simulado,
    pedido: ped,
  });
});
