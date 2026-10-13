// reembolsar
//
// Devuelve la plata de los pedidos que el local rechazó después de cobrados.
// La dispara el cron `reembolsar-pedidos` (0060), no una persona: el cliente no
// tiene por qué esperar a que alguien de la administración se entere.
//
// Se devuelve el **100%**: productos y envío. El que falló fue el local, el
// cliente no hizo nada mal, y el envío ni siquiera se hizo. Al local se le cobra
// la penalidad del lado de la base, al rechazar.
//
// Por qué va por cron y no colgado del rechazo: si Mercado Pago no contesta, el
// rechazo igual tiene que quedar registrado, y la devolución reintentarse sola.
// Colgada del rechazo, un fallo dejaría al cliente sin su plata y sin que nadie
// se entere.

import { createClient } from 'npm:@supabase/supabase-js@2';

const MP = 'https://api.mercadopago.com';
const MP_TOKEN = Deno.env.get('MP_ACCESS_TOKEN') ?? '';

function responder(cuerpo: unknown, status = 200) {
  return new Response(JSON.stringify(cuerpo), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  const servicioKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const jwt = req.headers.get('Authorization')?.replace('Bearer ', '') ?? '';
  if (jwt !== servicioKey) return responder({ error: 'No autorizado.' }, 401);

  const servicio = createClient(Deno.env.get('SUPABASE_URL')!, servicioKey);

  const { data: pendientes, error } = await servicio.rpc('reembolsos_pendientes');
  if (error) {
    console.error('reembolsos_pendientes', error);
    return responder({ error: 'No se pudo leer qué devolver.' }, 500);
  }

  let devueltos = 0;
  let fallidos = 0;

  for (const r of (pendientes ?? [])) {
    try {
      let refundId: string;

      // Un pago simulado (sin credenciales, o de una app vieja sin clave
      // pública) no tiene nada que devolver en Mercado Pago: se cierra acá para
      // que no quede reintentándose para siempre.
      if (!MP_TOKEN || !r.mp_order_id || String(r.mp_order_id).startsWith('simulado')) {
        refundId = `simulado-refund-${crypto.randomUUID()}`;
      } else {
        // Sin cuerpo = devolución total. La clave de idempotencia evita que un
        // reintento del cron devuelva dos veces.
        const resp = await fetch(`${MP}/v1/orders/${r.mp_order_id}/refund`, {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${MP_TOKEN}`,
            'Content-Type': 'application/json',
            'X-Idempotency-Key': `refund-${r.pago_id}`,
          },
        });
        const cuerpo = await resp.json().catch(() => ({}));
        if (!resp.ok) {
          console.error('mercado pago refund', r.mp_order_id, resp.status, JSON.stringify(cuerpo));
          throw new Error(cuerpo?.errors?.[0]?.message ?? cuerpo?.message ?? `respondió ${resp.status}`);
        }
        refundId = String(
          cuerpo?.transactions?.refunds?.[0]?.id ?? cuerpo?.id ?? r.mp_order_id,
        );
      }

      const { error: cerrar } = await servicio.rpc('confirmar_reembolso', {
        p_pago: r.pago_id,
        p_mp_refund: refundId,
        p_monto: r.monto,
      });
      if (cerrar) throw new Error(cerrar.message);

      devueltos++;
      console.log(`reembolsado ${r.codigo}: $${r.monto}`);
    } catch (e) {
      fallidos++;
      console.error('reembolsar', r.codigo, e instanceof Error ? e.message : String(e));
    }
  }

  return responder({ devueltos, fallidos });
});
