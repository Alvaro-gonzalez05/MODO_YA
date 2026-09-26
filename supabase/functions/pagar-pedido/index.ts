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
// MODO SIMULADO: sin MP_ACCESS_TOKEN configurado, no se llama a Mercado Pago y
// se responde como si la tarjeta hubiera sido aprobada (rechazada si el nombre
// del titular es "RECHAZADA", para poder probar ese camino). Sirve para mostrar
// la pantalla antes de tener la cuenta; nunca cobra plata de verdad.

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

/** Llama a Mercado Pago y devuelve el JSON, con el error legible si falla. */
async function mp(ruta: string, init: RequestInit = {}) {
  const r = await fetch(`${MP}${ruta}`, {
    ...init,
    headers: {
      Authorization: `Bearer ${MP_TOKEN}`,
      'Content-Type': 'application/json',
      ...(init.headers ?? {}),
    },
  });
  const cuerpo = await r.json().catch(() => ({}));
  if (!r.ok) {
    console.error('mercado pago', ruta, r.status, JSON.stringify(cuerpo));
    throw new Error(cuerpo?.message ?? `Mercado Pago respondio ${r.status}`);
  }
  return cuerpo;
}

/** Los importes de Orders viajan como texto con dos decimales ("10500.00"). */
function importe(pesos: number): string {
  return pesos.toFixed(2);
}

/** Crea una orden y devuelve lo unico que nos importa de la respuesta. */
async function crearOrden(cuerpo: unknown, idempotencia: string) {
  const orden = await mp('/v1/orders', {
    method: 'POST',
    headers: { 'X-Idempotency-Key': idempotencia },
    body: JSON.stringify(cuerpo),
  });

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
 */
// deno-lint-ignore no-explicit-any
async function renovarPlus(servicio: any) {
  const { data: pendientes, error } = await servicio.rpc('plus_por_renovar');
  if (error) {
    console.error('plus_por_renovar', error);
    return responder({ error: 'No se pudo leer a quien renovarle.' }, 500);
  }

  let renovadas = 0;
  let fallidas = 0;

  for (const s of (pendientes ?? [])) {
    // Se distingue "la tarjeta rebotó" de "cobramos y algo fallo despues": lo
    // primero se le cuenta como intento, lo segundo no (seria contarle un
    // rechazo que no existio, y encima ya pago).
    let cobrado = false;
    try {
      let mpId: string;

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
          external_reference: `plus-renovacion-${s.suscripcion_id}`,
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
        }, `plus-renovacion-${s.suscripcion_id}`);

        if (r.estado !== 'acreditado') throw new Error(motivo(r.detalleMp));
        mpId = r.pagoId ?? r.ordenId ?? '';
      }
      cobrado = true;

      const { data: pago } = await servicio
        .from('pagos')
        .insert({
          metodo: 'mercado_pago', estado: 'acreditado', monto: s.precio,
          mp_payment_id: mpId, cuotas: 1, acreditado_en: new Date().toISOString(),
        })
        .select().single();

      const { error: alta } = await servicio.rpc('activar_plus', {
        p_cliente: s.cliente_id,
        p_precio: s.precio,
        p_pago: pago?.id ?? null,
      });
      if (alta) throw new Error(alta.message);

      renovadas++;
    } catch (e) {
      fallidas++;
      const texto = e instanceof Error ? e.message : String(e);
      if (cobrado) {
        // Se le cobro y no se le pudo dar el mes: hay que arreglarlo a mano.
        console.error('RENOVACION COBRADA SIN ACTIVAR', s.suscripcion_id, texto);
      } else {
        console.error('renovar plus', s.suscripcion_id, texto);
        await servicio.rpc('plus_renovacion_fallo', {
          p_suscripcion: s.suscripcion_id,
          p_error: texto.slice(0, 300),
        });
      }
    }
  }

  console.log(`renovar_plus: ${renovadas} renovadas, ${fallidas} fallidas`);
  return responder({ renovadas, fallidas, simulado: SIMULADO });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });

  const url = Deno.env.get('SUPABASE_URL')!;
  const servicioKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const servicio = createClient(url, servicioKey);

  const jwt = req.headers.get('Authorization')?.replace('Bearer ', '') ?? '';
  const c = (await req.json().catch(() => ({}))) as Cuerpo;
  const accion = c.accion ?? 'pagar';

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
    if (!SIMULADO && cliente.mp_customer_id) {
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
    let estado: 'acreditado' | 'rechazado' = 'acreditado';
    let detalle: string | null = null;
    let mpId: string | null = null;

    if (SIMULADO) {
      const rechazar = (c.titular ?? '').trim().toUpperCase() === 'RECHAZADA';
      estado = rechazar ? 'rechazado' : 'acreditado';
      detalle = rechazar ? motivo('insufficient_amount') : null;
      mpId = `simulado-plus-${crypto.randomUUID()}`;
    } else {
      const r = await crearOrden({
        type: 'online',
        processing_mode: 'automatic',
        total_amount: importe(monto),
        external_reference: `plus-${cliente.id}`,
        payer: { email: user.email },
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
      // Plus se cobra o no se cobra: si queda en revision no se le da el mes.
      estado = r.estado === 'acreditado' ? 'acreditado' : 'rechazado';
      detalle = estado === 'acreditado' ? null : motivo(r.detalleMp);
    }

    if (estado !== 'acreditado') {
      return responder({ aprobado: false, detalle, simulado: SIMULADO });
    }

    const { data: pago } = await servicio
      .from('pagos')
      .insert({
        metodo: 'mercado_pago', estado: 'acreditado', monto,
        mp_payment_id: mpId, cuotas: 1, acreditado_en: new Date().toISOString(),
      })
      .select().single();

    const { data: sus, error } = await servicio.rpc('activar_plus', {
      p_cliente: cliente.id,
      p_precio: monto,
      p_pago: pago?.id ?? null,
    });
    if (error) {
      console.error('activar_plus', error);
      return responder({ error: 'Se cobró la suscripción pero no se pudo activar. Escribinos.' }, 500);
    }

    return responder({ aprobado: true, simulado: SIMULADO, suscripcion: sus });
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

  const cuotas = Math.min(Math.max(c.cuotas ?? 1, 1), 24);
  let estado: 'acreditado' | 'rechazado' | 'pendiente' = 'acreditado';
  let detalle: string | null = null;
  let mpPaymentId: string | null = null;
  let mpOrderId: string | null = null;

  if (SIMULADO) {
    // Sin credenciales: se responde sin cobrar nada.
    const rechazar = (c.titular ?? '').trim().toUpperCase() === 'RECHAZADA';
    estado = rechazar ? 'rechazado' : 'acreditado';
    detalle = rechazar ? motivo('insufficient_amount') : 'Pago simulado (sin credenciales de Mercado Pago)';
    mpPaymentId = `simulado-${crypto.randomUUID()}`;
    mpOrderId = `simulado-orden-${crypto.randomUUID()}`;
  } else {
    // Cliente de Mercado Pago (para poder guardar tarjetas).
    let customerId = cliente.mp_customer_id as string | null;
    if (!customerId && c.guardar) {
      const buscado = await mp(`/v1/customers/search?email=${encodeURIComponent(user.email ?? '')}`);
      customerId = buscado?.results?.[0]?.id ??
        (await mp('/v1/customers', {
          method: 'POST',
          body: JSON.stringify({ email: user.email, first_name: cliente.nombre }),
        })).id;
      await servicio.from('clientes').update({ mp_customer_id: customerId }).eq('id', cliente.id);
    }

    // Si el cliente toca "Pagar" dos veces con la misma tarjeta, Mercado Pago
    // cobra una sola vez. Con otra tarjeta el token cambia, asi que el
    // reintento si se procesa.
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
    }, `pedido-${pedido.id}-${c.token.slice(-16)}`);

    mpOrderId = r.ordenId;
    mpPaymentId = r.pagoId ?? r.ordenId;
    estado = r.estado;
    detalle = estado === 'acreditado' ? null : motivo(r.detalleMp);

    // Guardar la tarjeta para la proxima (Mercado Pago la guarda, nosotros solo
    // la referencia y los ultimos cuatro numeros).
    if (estado === 'acreditado' && c.guardar && customerId && !c.card_id) {
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
        console.error('guardar tarjeta', e); // el pago ya salio: no se cae por esto
      }
    }
  }

  if (SIMULADO && c.guardar && estado === 'acreditado' && c.ultimos4) {
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
    simulado: SIMULADO,
    pedido: ped,
  });
});
