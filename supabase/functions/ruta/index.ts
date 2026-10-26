// ruta
//
// El camino manejando entre dos puntos, para dibujarlo en el seguimiento.
//
// Por que pasa por aca y no va directo desde la app: el servidor publico de
// OSRM que se usaba no admite uso productivo, y cualquier alternativa seria
// pide una clave. Si la clave viviera en la app, cambiar de proveedor (o de
// clave) obligaria a sacar una version nueva y esperar a que todos actualicen.
// Aca es un secreto de Supabase: se cambia en un minuto y la app no se entera.
//
// Proveedor, segun los secretos que esten cargados:
//   * RUTAS_GEOAPIFY_KEY: Geoapify (https://www.geoapify.com/routing-api).
//   * RUTAS_OSRM_URL: un OSRM propio, por ejemplo levantado con el extracto de
//     Cuyo en un servidor chico.
//   * ninguno: el OSRM publico, como antes. Sirve para desarrollar.
//
// Nunca contesta un error por el proveedor: si no hay ruta, la app dibuja la
// recta. Solo rechaza a quien no inicio sesion, para que nadie use la clave de
// MODO YA de afuera.

import { createClient } from 'npm:@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const GEOAPIFY = Deno.env.get('RUTAS_GEOAPIFY_KEY') ?? '';
const OSRM = (Deno.env.get('RUTAS_OSRM_URL') ?? 'https://router.project-osrm.org').replace(/\/$/, '');

type Punto = { lat: number; lng: number };
type Ruta = { puntos: [number, number][]; segundos: number | null };

function responder(cuerpo: unknown, status = 200) {
  return new Response(JSON.stringify(cuerpo), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
}

// deno-lint-ignore no-explicit-any
function punto(p: any): Punto | null {
  const lat = Number(p?.lat);
  const lng = Number(p?.lng);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  if (Math.abs(lat) > 90 || Math.abs(lng) > 180) return null;
  return { lat, lng };
}

async function conTiempo(url: string): Promise<Response> {
  // La app espera 8 s; se le deja margen para contestar la recta.
  return await fetch(url, { signal: AbortSignal.timeout(6000) });
}

async function geoapify(a: Punto, b: Punto): Promise<Ruta | null> {
  const url = `https://api.geoapify.com/v1/routing?waypoints=${a.lat},${a.lng}|${b.lat},${b.lng}` +
    `&mode=drive&apiKey=${encodeURIComponent(GEOAPIFY)}`;
  const r = await conTiempo(url);
  if (!r.ok) {
    console.error('geoapify', r.status, (await r.text()).slice(0, 300));
    return null;
  }
  const cuerpo = await r.json();
  const tramo = cuerpo?.features?.[0];
  const geo = tramo?.geometry;
  // Geoapify devuelve MultiLineString (una linea por tramo entre waypoints).
  const lineas: number[][][] = geo?.type === 'MultiLineString'
    ? geo.coordinates
    : geo?.type === 'LineString'
      ? [geo.coordinates]
      : [];
  const puntos = lineas.flat().map((c) => [c[1], c[0]] as [number, number]);
  const segundos = Number(tramo?.properties?.time);
  return { puntos, segundos: Number.isFinite(segundos) ? Math.round(segundos) : null };
}

async function osrm(a: Punto, b: Punto): Promise<Ruta | null> {
  const url = `${OSRM}/route/v1/driving/${a.lng},${a.lat};${b.lng},${b.lat}?overview=full&geometries=geojson`;
  const r = await conTiempo(url);
  if (!r.ok) {
    console.error('osrm', r.status);
    return null;
  }
  const cuerpo = await r.json();
  if (cuerpo?.code !== 'Ok') return null;
  const tramo = cuerpo.routes?.[0];
  // GeoJSON escribe [lng, lat]; la app recibe [lat, lng].
  const puntos = (tramo?.geometry?.coordinates ?? []).map((c: number[]) => [c[1], c[0]] as [number, number]);
  const segundos = Number(tramo?.duration);
  return { puntos, segundos: Number.isFinite(segundos) ? Math.round(segundos) : null };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });

  const url = Deno.env.get('SUPABASE_URL')!;
  const jwt = req.headers.get('Authorization')?.replace('Bearer ', '') ?? '';
  const { data: { user } } = await createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
  }).auth.getUser();
  if (!user) return responder({ error: 'Iniciá sesión.' }, 401);

  const cuerpo = await req.json().catch(() => ({}));
  const desde = punto(cuerpo?.desde);
  const hasta = punto(cuerpo?.hasta);
  if (!desde || !hasta) return responder({ error: 'Faltan los dos puntos.' }, 400);

  try {
    const ruta = GEOAPIFY ? await geoapify(desde, hasta) : await osrm(desde, hasta);
    if (ruta && ruta.puntos.length >= 2) {
      return responder({ ...ruta, proveedor: GEOAPIFY ? 'geoapify' : 'osrm' });
    }
  } catch (e) {
    console.error('ruta', e instanceof Error ? e.message : String(e));
  }
  // Sin ruta: la app dibuja la recta. No es un error para el que mira el mapa.
  return responder({ puntos: [], segundos: null, proveedor: 'ninguno' });
});
