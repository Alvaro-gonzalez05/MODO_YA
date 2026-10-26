// mp-procesar-avisos
//
// El consumidor que faltaba. `mp-webhook` recibe los avisos de Mercado Pago y
// los guarda en `mp_notificaciones`; hasta 0068 nadie los leia, asi que un pago
// que el banco dejaba en revision y se aprobaba diez minutos tarde no movia
// nada: el cliente quedaba cobrado, sin pedido y sin devolucion (hallazgo A1 de
// docs/hallazgos-de-la-auditoria-2.md).
//
// La dispara el cron `procesar-avisos-mp` cada minuto, no una persona.
//
// Por que una funcion aparte y no esto dentro de `mp-webhook`:
//
//   * Mercado Pago exige un 200 en menos de 22 segundos y reintenta cada 15
//     minutos si no llega. Preguntarle por la orden desde adentro del webhook
//     arriesga el timeout, y un timeout es un aviso repetido.
//   * `mp-webhook` es un endpoint publico (lo llama Mercado Pago, sin JWT).
//     Esta funcion pide la clave de servicio, igual que `reembolsar`.
//
// Por que se le vuelve a preguntar a Mercado Pago en vez de creerle al cuerpo
// del aviso: la firma del webhook cubre `data.id`, el `x-request-id` y el `ts`,
// **no el cuerpo**. Preguntar por la orden con nuestro access token es la unica
// fuente que no depende de lo que vino por la red. Ademas los avisos de la API
// vieja (Payments) no traen el estado en el cuerpo: solo el id.
//
// Sin `MP_ACCESS_TOKEN` no hay a quien preguntarle y se le cree al cuerpo del
// aviso, que en los de Orders trae la orden entera. Es el camino que ejercitan
// las pruebas; con credenciales se pregunta siempre.
//
// La decision sobre el pedido NO esta aca: esta en `resolver_pago_de_mp()`, del
// lado de la base, que es donde vive la logica de negocio en este proyecto. Aca
// solo se traduce "como termino la orden" a uno de los estados de `pagos`.

import { createClient } from 'npm:@supabase/supabase-js@2';

const MP = 'https://api.mercadopago.com';
const MP_TOKEN = Deno.env.get('MP_ACCESS_TOKEN') ?? '';

type Estado = 'acreditado' | 'pendiente' | 'rechazado' | 'reembolsado';

function responder(cuerpo: unknown, status = 200) {
  return new Response(JSON.stringify(cuerpo), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

/** Lo que dijo Mercado Pago, traducido a uno de nuestros estados de pago.
 *
 * Los nombres de Orders (`processed`, `processing`, `action_required`) y los de
 * la API vieja de Payments (`approved`, `in_process`, `pending`) conviven a
 * proposito: segun como este configurada la aplicacion de Mercado Pago, los
 * avisos llegan de una API o de la otra.
 *
 * `null` = el aviso no dice nada del estado y no hay nada que resolver.
 */
function estadoDelPago(estadoMp: string): Estado | null {
  const e = estadoMp.toLowerCase();
  if (e === '') return null;
  // Una devolucion o un contracargo manda antes que cualquier otra cosa: la
  // plata ya no esta, y la liquidacion del local la estaria contando.
  if (['refunded', 'partially_refunded', 'reversed', 'charged_back'].includes(e)) {
    return 'reembolsado';
  }
  if (['processed', 'approved'].includes(e)) return 'acreditado';
  // Todavia no se sabe: revision manual, 3DS, la orden recien creada.
  if (['processing', 'action_required', 'created', 'in_process', 'pending', 'authorized'].includes(e)) {
    return 'pendiente';
  }
  return 'rechazado';
}

/** Error de Mercado Pago que no tiene sentido reintentar (4xx). */
class NoReintentar extends Error {}

async function mpGet(ruta: string) {
  const r = await fetch(`${MP}${ruta}`, {
    headers: { Authorization: `Bearer ${MP_TOKEN}` },
  });
  const cuerpo = await r.json().catch(() => ({}));
  if (r.ok) return cuerpo;

  // 4xx = Mercado Pago no conoce ese recurso o no nos deja verlo. Reintentarlo
  // cada minuto para siempre no lo va a arreglar: se tacha el aviso con la
  // nota, que es lo que despues se ve en la pantalla de la administracion.
  if (r.status >= 400 && r.status < 500) {
    throw new NoReintentar(
      `Mercado Pago contestó ${r.status}: ${cuerpo?.message ?? cuerpo?.errors?.[0]?.message ?? 'sin detalle'}`,
    );
  }
  throw new Error(`Mercado Pago contestó ${r.status}`);
}

/** Los tres datos que `resolver_pago_de_mp` necesita de una orden. */
// deno-lint-ignore no-explicit-any
function deLaOrden(orden: any, recursoId: string) {
  const pago = orden?.transactions?.payments?.[0] ?? {};
  const reembolsos = orden?.transactions?.refunds ?? [];
  return {
    ordenId: orden?.id ? String(orden.id) : recursoId,
    pagoId: pago?.id ? String(pago.id) : null,
    // Una devolucion hecha desde el panel no siempre cambia el `status` del
    // pago, pero siempre deja el refund en la orden.
    estadoMp: reembolsos.length > 0
      ? 'refunded'
      : String(pago?.status ?? orden?.status ?? ''),
    detalleMp: String(pago?.status_detail ?? orden?.status_detail ?? ''),
  };
}

// deno-lint-ignore no-explicit-any
function delPago(pago: any, recursoId: string) {
  return {
    ordenId: pago?.order?.id ? String(pago.order.id) : null,
    pagoId: pago?.id ? String(pago.id) : recursoId,
    estadoMp: String(pago?.status ?? ''),
    detalleMp: String(pago?.status_detail ?? ''),
  };
}

Deno.serve(async (req) => {
  const servicioKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const jwt = req.headers.get('Authorization')?.replace('Bearer ', '') ?? '';
  if (jwt !== servicioKey) return responder({ error: 'No autorizado.' }, 401);

  const servicio = createClient(Deno.env.get('SUPABASE_URL')!, servicioKey);

  const { data: avisos, error } = await servicio.rpc('mp_avisos_por_procesar');
  if (error) {
    console.error('mp_avisos_por_procesar', error);
    return responder({ error: 'No se pudo leer el buzón de avisos.' }, 500);
  }

  let resueltos = 0;
  let sinEfecto = 0;
  let fallidos = 0;

  for (const a of (avisos ?? [])) {
    const tipo = String(a.tipo ?? '').toLowerCase();
    const recurso = String(a.recurso_id);

    try {
      let datos: { ordenId: string | null; pagoId: string | null; estadoMp: string; detalleMp: string };

      if (!MP_TOKEN) {
        // Sin credenciales se le cree al cuerpo del aviso. Es el unico camino
        // que se puede ejercitar sin tocar la API real.
        datos = deLaOrden((a.cuerpo ?? {}).data, recurso);
      } else if (tipo.startsWith('order')) {
        datos = deLaOrden(await mpGet(`/v1/orders/${recurso}`), recurso);
      } else if (tipo.startsWith('payment')) {
        datos = delPago(await mpGet(`/v1/payments/${recurso}`), recurso);
      } else {
        // "merchant_order", "subscription"... no hablan de un cobro nuestro.
        await servicio.rpc('mp_aviso_procesado', {
          p_aviso: a.aviso_id,
          p_nota: `tipo "${a.tipo ?? '?'}": no habla de un pago`,
        });
        sinEfecto++;
        continue;
      }

      const estado = estadoDelPago(datos.estadoMp);

      if (estado === null || estado === 'pendiente') {
        // El banco todavia no se decidio. Este aviso no agrega nada y Mercado
        // Pago va a mandar otro cuando resuelva; se tacha para no releerlo.
        await servicio.rpc('mp_aviso_procesado', {
          p_aviso: a.aviso_id,
          p_nota: estado === null
            ? 'el aviso no dice en qué estado quedó el pago'
            : `sigue sin resolverse (${datos.estadoMp})`,
        });
        sinEfecto++;
        continue;
      }

      const { data: nota, error: errResolver } = await servicio.rpc('resolver_pago_de_mp', {
        p_mp_order: datos.ordenId,
        p_mp_payment: datos.pagoId,
        p_estado: estado,
        // El detalle de Mercado Pago va crudo: `pagos.detalle` lo lee la
        // administracion, no el cliente, y ahi el nombre original vale mas que
        // una traduccion.
        p_detalle: datos.detalleMp || null,
      });
      if (errResolver) throw new Error(errResolver.message);

      await servicio.rpc('mp_aviso_procesado', {
        p_aviso: a.aviso_id,
        p_nota: `${estado}: ${nota ?? 'sin nota'}`,
      });
      resueltos++;
      console.log(`aviso ${a.accion ?? a.tipo} ${recurso} -> ${estado}: ${nota}`);
    } catch (e) {
      const texto = e instanceof Error ? e.message : String(e);
      if (e instanceof NoReintentar) {
        await servicio.rpc('mp_aviso_procesado', { p_aviso: a.aviso_id, p_nota: texto });
        sinEfecto++;
        console.error('aviso descartado', recurso, texto);
      } else {
        // Se deja sin tachar: el cron vuelve en un minuto.
        fallidos++;
        console.error('procesar aviso', recurso, texto);
      }
    }
  }

  return responder({ resueltos, sinEfecto, fallidos, simulado: MP_TOKEN === '' });
});
