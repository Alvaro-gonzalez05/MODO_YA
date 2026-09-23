// pagar-pedido
//
// Cobra un pedido con tarjeta a traves de Mercado Pago (Checkout API) y, si el
// pago sale aprobado, lo manda al local.
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
  accion?: 'pagar' | 'tarjetas' | 'borrar_tarjeta';
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

/** Mensajes de Mercado Pago traducidos a algo que entienda el cliente. */
function motivo(detalle: string): string {
  const mapa: Record<string, string> = {
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

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });

  const url = Deno.env.get('SUPABASE_URL')!;
  const servicio = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);

  // Identidad: se verifica aca adentro (la funcion se publica con
  // --no-verify-jwt para que funcione con claves nuevas y viejas).
  const jwt = req.headers.get('Authorization')?.replace('Bearer ', '') ?? '';
  const { data: { user } } = await createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
  }).auth.getUser();
  if (!user) return responder({ error: 'Iniciá sesión para pagar.' }, 401);

  const { data: cliente } = await servicio
    .from('clientes').select('id, nombre, mp_customer_id').eq('perfil_id', user.id).maybeSingle();
  if (!cliente) return responder({ error: 'Solo un cliente puede pagar un pedido.' }, 403);

  const c = (await req.json().catch(() => ({}))) as Cuerpo;
  const accion = c.accion ?? 'pagar';

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

  if (SIMULADO) {
    // Sin credenciales: se responde sin cobrar nada.
    const rechazar = (c.titular ?? '').trim().toUpperCase() === 'RECHAZADA';
    estado = rechazar ? 'rechazado' : 'acreditado';
    detalle = rechazar ? motivo('cc_rejected_insufficient_amount') : 'Pago simulado (sin credenciales de Mercado Pago)';
    mpPaymentId = `simulado-${crypto.randomUUID()}`;
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

    const pago = await mp('/v1/payments', {
      method: 'POST',
      // Si el cliente toca "Pagar" dos veces con la misma tarjeta, Mercado
      // Pago cobra una sola vez. Con otra tarjeta el token cambia, asi que el
      // reintento si se procesa.
      headers: { 'X-Idempotency-Key': `pedido-${pedido.id}-${c.token.slice(-16)}` },
      body: JSON.stringify({
        transaction_amount: pedido.total,
        token: c.token,
        installments: cuotas,
        payment_method_id: c.metodo_pago_id,
        description: `MODO YA pedido ${pedido.codigo}`,
        external_reference: pedido.id,
        statement_descriptor: 'MODO YA',
        payer: { email: user.email, type: customerId ? 'customer' : undefined, id: customerId ?? undefined },
        metadata: { pedido_id: pedido.id, comercio_id: pedido.comercio_id },
      }),
    });

    mpPaymentId = String(pago.id);
    estado = pago.status === 'approved' ? 'acreditado' : pago.status === 'in_process' ? 'pendiente' : 'rechazado';
    detalle = estado === 'acreditado' ? null : motivo(pago.status_detail ?? '');

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
