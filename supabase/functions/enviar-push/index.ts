// enviar-push
//
// Empuja al celular las notificaciones que todavia no salieron. La llama el
// cron `empujar-notificaciones` una vez por minuto (ver 0053).
//
// **Firebase entra solo como el cano.** Los datos siguen enteros en Supabase:
// aca se lee que hay que mandar y a quien, y FCM se usa unicamente porque es lo
// unico que despierta un Android con la app cerrada (el sistema operativo
// mantiene una sola conexion para todas las apps, no una por app).
//
// Por que por cron y no al insertar la fila: si el push falla —el celular sin
// senal, el token vencido, Google caido— la fila queda pendiente y se reintenta
// sola en la proxima vuelta. Colgado del insert, un fallo se perderia sin que
// nadie se entere.
//
// El texto sale de `v_notificaciones`, que es la misma vista que lee la app:
// asi el `{nombre}` se reemplaza en un solo lugar y el push dice exactamente lo
// mismo que la campanita.
//
// Un token que FCM rechaza por UNREGISTERED (la persona desinstalo la app o
// limpio los datos) **se borra**. Si no, la tabla se llena de celulares muertos
// y cada vuelta se gastan llamadas en ellos.

import { createClient } from 'npm:@supabase/supabase-js@2';

const CUENTA = Deno.env.get('FCM_SERVICE_ACCOUNT') ?? '';

/** Cuantos envios se procesan por vuelta. El cron pasa cada un minuto. */
const POR_VUELTA = 200;

type Cuenta = { client_email: string; private_key: string; project_id: string };

// ---------------------------------------------------------------------------
// Token de Google
// ---------------------------------------------------------------------------
//
// FCM v1 no toma la clave de servicio directamente: hay que firmar un JWT con
// ella y canjearlo por un access token, que dura una hora. Como esta funcion
// corre cada minuto, se guarda en memoria mientras el contenedor siga vivo.

let cacheToken: { valor: string; vence: number } | null = null;

function pemABinario(pem: string): ArrayBuffer {
  const limpio = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s/g, '');
  const bin = atob(limpio);
  const buf = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);
  return buf.buffer;
}

function base64url(datos: string | Uint8Array): string {
  const bin = typeof datos === 'string'
    ? datos
    : String.fromCharCode(...datos);
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

async function accessToken(cuenta: Cuenta): Promise<string> {
  const ahora = Math.floor(Date.now() / 1000);
  // Se renueva un minuto antes de vencer, para no usar uno que expire a mitad
  // de la tanda.
  if (cacheToken && cacheToken.vence > ahora + 60) return cacheToken.valor;

  const cabecera = base64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const cuerpo = base64url(JSON.stringify({
    iss: cuenta.client_email,
    scope: 'https://www.googleapis.com/auth/firebase.messaging',
    aud: 'https://oauth2.googleapis.com/token',
    iat: ahora,
    exp: ahora + 3600,
  }));

  const clave = await crypto.subtle.importKey(
    'pkcs8',
    pemABinario(cuenta.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const firma = new Uint8Array(await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    clave,
    new TextEncoder().encode(`${cabecera}.${cuerpo}`),
  ));

  const jwt = `${cabecera}.${cuerpo}.${base64url(firma)}`;

  const r = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });
  const j = await r.json();
  if (!r.ok) throw new Error(`Google no dio token: ${JSON.stringify(j)}`);

  cacheToken = { valor: j.access_token, vence: ahora + (j.expires_in ?? 3600) };
  return cacheToken.valor;
}

// ---------------------------------------------------------------------------
// Mandar uno
// ---------------------------------------------------------------------------

/** Devuelve 'ok', 'token_muerto' (hay que borrarlo) o 'error'. */
async function mandar(
  proyecto: string,
  token: string,
  titulo: string,
  cuerpo: string,
  datos: Record<string, string>,
): Promise<'ok' | 'token_muerto' | 'error'> {
  const r = await fetch(
    `https://fcm.googleapis.com/v1/projects/${proyecto}/messages:send`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${await accessToken(JSON.parse(CUENTA))}`,
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title: titulo, body: cuerpo },
          // Los datos viajan aparte del texto: con la app abierta no se muestra
          // la notificacion del sistema y la app decide que hacer con esto.
          data: datos,
          android: { priority: 'high', notification: { sound: 'default' } },
        },
      }),
    },
  );

  if (r.ok) return 'ok';

  const detalle = await r.text();
  // 404 UNREGISTERED: desinstalo la app o limpio los datos.
  // 400 INVALID_ARGUMENT sobre el token: quedo mal guardado.
  if (r.status === 404 || detalle.includes('UNREGISTERED')) return 'token_muerto';
  console.error(`FCM ${r.status}: ${detalle.slice(0, 300)}`);
  return 'error';
}

// ---------------------------------------------------------------------------
// La vuelta
// ---------------------------------------------------------------------------

Deno.serve(async () => {
  if (!CUENTA) {
    console.error('Falta FCM_SERVICE_ACCOUNT');
    return new Response('sin credenciales', { status: 200 });
  }

  const cuenta: Cuenta = JSON.parse(CUENTA);
  const db = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  // Lo que quedo sin empujar, de las ultimas horas. Una notificacion de
  // anteayer que no salio ya no sirve empujarla.
  const { data: pendientes, error } = await db
    .from('notificacion_envios')
    .select('id, perfil_id')
    .is('push_enviado_en', null)
    .gt('creado_en', new Date(Date.now() - 6 * 3600 * 1000).toISOString())
    .order('creado_en', { ascending: true })
    .limit(POR_VUELTA);

  if (error) throw error;
  if (!pendientes?.length) return Response.json({ empujados: 0 });

  // El texto ya personalizado, de la misma vista que lee la app.
  const { data: textos } = await db
    .from('v_notificaciones')
    .select('envio_id, titulo, cuerpo, destino, destino_id, pedido_id')
    .in('envio_id', pendientes.map((p) => p.id));

  const porEnvio = new Map((textos ?? []).map((t) => [t.envio_id, t]));

  const { data: tokens } = await db
    .from('push_tokens')
    .select('perfil_id, token')
    .in('perfil_id', [...new Set(pendientes.map((p) => p.perfil_id))]);

  const porPerfil = new Map<string, string[]>();
  for (const t of tokens ?? []) {
    porPerfil.set(t.perfil_id, [...(porPerfil.get(t.perfil_id) ?? []), t.token]);
  }

  const muertos: string[] = [];
  const empujados: string[] = [];

  for (const p of pendientes) {
    const texto = porEnvio.get(p.id);
    // Sin texto (un borrador, o se borro la notificacion) no hay nada que
    // mandar; se marca igual para no volver a mirarlo cada minuto.
    if (!texto) {
      empujados.push(p.id);
      continue;
    }

    const suyos = porPerfil.get(p.perfil_id) ?? [];
    // Sin celular registrado tampoco hay nada que hacer: lo va a ver en la
    // campanita cuando abra la app.
    if (!suyos.length) {
      empujados.push(p.id);
      continue;
    }

    // Si con algun celular fallo por algo pasajero (Google caido, sin red) y no
    // llego a ninguno, la fila queda pendiente y se reintenta en la proxima
    // vuelta: marcarla igual la perderia, que es justo lo que el cron evita.
    let reintentar = false;
    let llego = false;
    for (const token of suyos) {
      const r = await mandar(cuenta.project_id, token, texto.titulo, texto.cuerpo, {
        envio_id: p.id,
        destino: texto.destino ?? 'ninguno',
        destino_id: texto.destino_id ?? '',
        pedido_id: texto.pedido_id ?? '',
      });
      if (r === 'token_muerto') muertos.push(token);
      if (r === 'error') reintentar = true;
      if (r === 'ok') llego = true;
    }
    if (llego || !reintentar) empujados.push(p.id);
  }

  if (empujados.length) {
    await db
      .from('notificacion_envios')
      .update({ push_enviado_en: new Date().toISOString() })
      .in('id', empujados);
  }

  if (muertos.length) {
    await db.from('push_tokens').delete().in('token', muertos);
  }

  return Response.json({ empujados: empujados.length, tokens_borrados: muertos.length });
});
