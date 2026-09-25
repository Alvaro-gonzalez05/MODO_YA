// mp-webhook
//
// Recibe los avisos de Mercado Pago (Webhooks) y los guarda tal como llegaron
// en `mp_notificaciones`. Por ahora **solo guarda**: no toca el pedido.
//
// Por que solo guardar: el cuerpo del aviso cambia segun la aplicacion de
// Mercado Pago sea de Orders o de Payments, y todavia no tenemos credenciales
// para ver avisos de verdad. Guardando desde el dia uno, cuando se agregue el
// procesamiento se puede reprocesar lo que ya llego en vez de haberlo perdido.
//
// Reglas de Mercado Pago que importan aca:
//   * Hay que contestar 200 o 201 en menos de 22 segundos. Si no, reintenta
//     cada 15 minutos. Por eso esto no hace nada lento ni llama a nadie.
//   * El aviso viene firmado en el header `x-signature`
//     (`ts=1704908010,v1=<hmac>`). La firma es un HMAC-SHA256 del texto
//     `id:<data.id>;request-id:<x-request-id>;ts:<ts>;` con la clave secreta
//     que Mercado Pago muestra al configurar la notificacion.
//
// Sin `MP_WEBHOOK_SECRET` configurado no se valida nada y se guarda igual, con
// `firma_valida` en null. Es a proposito: deja probar el simulador de
// notificaciones de Mercado Pago antes de tener la clave. Mientras solo se
// guarde no hay riesgo; **antes de actuar sobre un pedido hay que exigir que la
// firma sea valida**, porque si no cualquiera podria darnos un pago por bueno.

import { createClient } from 'npm:@supabase/supabase-js@2';

const SECRETO = Deno.env.get('MP_WEBHOOK_SECRET') ?? '';

/** Compara la firma que vino con la que deberia ser. */
async function firmaValida(
  firma: string | null,
  requestId: string | null,
  dataId: string | null,
): Promise<boolean | null> {
  if (!SECRETO) return null;
  if (!firma) return false;

  // "ts=1704908010,v1=abc..." -> { ts, v1 }
  const partes = Object.fromEntries(
    firma.split(',').map((p) => {
      const [k, ...v] = p.split('=');
      return [k.trim(), v.join('=').trim()];
    }),
  );
  const ts = partes.ts;
  const v1 = partes.v1;
  if (!ts || !v1) return false;

  // Mercado Pago arma el texto siempre igual, salteando lo que no vino. Si el
  // id es alfanumerico va en minuscula.
  let texto = '';
  if (dataId) texto += `id:${dataId.toLowerCase()};`;
  if (requestId) texto += `request-id:${requestId};`;
  texto += `ts:${ts};`;

  const clave = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(SECRETO),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const firmado = await crypto.subtle.sign('HMAC', clave, new TextEncoder().encode(texto));
  const esperado = Array.from(new Uint8Array(firmado))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');

  return esperado === v1.toLowerCase();
}

Deno.serve(async (req) => {
  // Mercado Pago pega de servidor a servidor: no hay navegador ni CORS.
  if (req.method !== 'POST') {
    return new Response('ok', { status: 200 });
  }

  const url = new URL(req.url);
  const cuerpo = (await req.json().catch(() => null)) as Record<string, unknown> | null;
  if (!cuerpo) {
    // Un aviso que no es JSON no lo vamos a poder usar nunca: se acepta para
    // que Mercado Pago no lo reintente para siempre, y queda en el log.
    console.error('mp-webhook: cuerpo ilegible');
    return new Response('ok', { status: 200 });
  }

  const datos = (cuerpo.data ?? {}) as Record<string, unknown>;
  // El id viene en la URL y tambien en el cuerpo; la firma se arma con el de
  // la URL, asi que ese manda.
  const dataId = url.searchParams.get('data.id') ?? url.searchParams.get('id') ??
    (datos.id != null ? String(datos.id) : null);
  const requestId = req.headers.get('x-request-id');

  const valida = await firmaValida(req.headers.get('x-signature'), requestId, dataId);

  const servicio = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  const { error } = await servicio.from('mp_notificaciones').insert({
    tipo: (cuerpo.type ?? cuerpo.topic ?? null) as string | null,
    accion: (cuerpo.action ?? null) as string | null,
    recurso_id: dataId,
    request_id: requestId,
    firma_valida: valida,
    cuerpo,
  });

  if (error) {
    // 23505 = ya lo teniamos. Es un reintento de Mercado Pago: se le contesta
    // que si, para que deje de mandarlo.
    if (error.code === '23505') {
      return new Response('ok', { status: 200 });
    }
    // Cualquier otro error si conviene que lo reintente dentro de 15 minutos.
    console.error('mp-webhook: no se pudo guardar', error);
    return new Response('error', { status: 500 });
  }

  console.log(`mp-webhook: ${cuerpo.type ?? cuerpo.topic} ${cuerpo.action ?? ''} ${dataId ?? ''} firma=${valida}`);
  return new Response('ok', { status: 200 });
});
