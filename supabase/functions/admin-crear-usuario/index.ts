// admin-crear-usuario
//
// La administracion da de alta locales y cadetes desde la app. Los clientes no
// pasan por aca: se registran solos.
//
// Por que es una Edge Function y no una RPC: crear un usuario de Auth requiere
// la service_role key, que saltea RLS por completo y por eso no puede vivir
// dentro de una app. Aca existe solo en el servidor.
//
// Seguridad:
//   * Se despliega con --no-verify-jwt y la identidad se verifica ADENTRO, con
//     auth.getUser(). Asi funciona igual con claves legacy o con las nuevas.
//   * El rol del que llama se lee de `perfiles`, no del token: un JWT viejo de
//     alguien que dejo de ser admin no sirve.
//   * El rol de la cuenta nueva va en app_metadata. El trigger alta_usuario
//     (migracion 0017) solo confia en app_metadata, que el usuario no puede
//     escribir.

import { createClient } from 'npm:@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

type Vehiculo = 'moto' | 'bicicleta' | 'auto' | 'a_pie';

interface Alta {
  rol: 'comercio' | 'repartidor';
  email: string;
  nombre: string;
  telefono: string;
  /** Si no viene, se genera una y se devuelve una sola vez. */
  password?: string;

  // Solo comercio
  rubro_id?: string;
  calle?: string;
  referencia?: string;
  lat?: number;
  lng?: number;

  // Solo repartidor
  vehiculo?: Vehiculo;
}

function responder(status: number, cuerpo: unknown) {
  return new Response(JSON.stringify(cuerpo), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
}

function error(status: number, codigo: string, mensaje: string) {
  return responder(status, { error: { codigo, mensaje } });
}

/**
 * Contrasena temporal legible: sin 0/O ni 1/l/I, que por telefono o escrita a
 * mano se confunden. 10 caracteres de un alfabeto de 55 son ~58 bits.
 */
function passwordTemporal(largo = 10): string {
  const alfabeto = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  const bytes = new Uint8Array(largo);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => alfabeto[b % alfabeto.length]).join('');
}

const emailValido = (e: string) => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(e);

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return error(405, 'metodo', 'Usa POST');

  const url = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !serviceKey) {
    return error(500, 'config', 'La funcion no tiene configuradas las claves del servidor');
  }

  const admin = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // ---- 1. Quien llama tiene que ser admin -----------------------------------
  const jwt = req.headers.get('Authorization')?.replace(/^Bearer\s+/i, '');
  if (!jwt) return error(401, 'sin_sesion', 'Falta iniciar sesion');

  const { data: sesion, error: errSesion } = await admin.auth.getUser(jwt);
  if (errSesion || !sesion?.user) return error(401, 'sin_sesion', 'Sesion invalida o vencida');

  const { data: perfil } = await admin
    .from('perfiles')
    .select('rol')
    .eq('id', sesion.user.id)
    .maybeSingle();

  if (perfil?.rol !== 'admin') {
    return error(403, 'no_admin', 'Solo la administracion puede crear cuentas');
  }

  // ---- 2. Validar lo que llega ----------------------------------------------
  let alta: Alta;
  try {
    alta = await req.json();
  } catch {
    return error(400, 'json', 'El cuerpo no es JSON valido');
  }

  const email = (alta.email ?? '').trim().toLowerCase();
  const nombre = (alta.nombre ?? '').trim();
  const telefono = (alta.telefono ?? '').trim();

  if (alta.rol !== 'comercio' && alta.rol !== 'repartidor') {
    return error(400, 'rol', 'El rol tiene que ser comercio o repartidor');
  }
  if (!emailValido(email)) return error(400, 'email', 'El email no es valido');
  if (!nombre) return error(400, 'nombre', 'Falta el nombre');
  if (!telefono) return error(400, 'telefono', 'Falta el telefono');
  if (alta.password && alta.password.length < 8) {
    return error(400, 'password', 'La contrasena tiene que tener al menos 8 caracteres');
  }

  if (alta.rol === 'comercio') {
    if (!alta.calle?.trim()) return error(400, 'calle', 'Falta la direccion del local');
    // Sin ubicacion el local no puede cotizar envios: se exige desde el alta.
    if (typeof alta.lat !== 'number' || typeof alta.lng !== 'number') {
      return error(400, 'ubicacion', 'Falta marcar la ubicacion del local en el mapa');
    }
  } else {
    const vehiculos: Vehiculo[] = ['moto', 'bicicleta', 'auto', 'a_pie'];
    if (!alta.vehiculo || !vehiculos.includes(alta.vehiculo)) {
      return error(400, 'vehiculo', 'Falta el vehiculo del cadete');
    }
  }

  const { data: ciudad } = await admin
    .from('ciudades')
    .select('id')
    .eq('activa', true)
    .order('creado_en')
    .limit(1)
    .maybeSingle();
  if (!ciudad) return error(500, 'ciudad', 'No hay ninguna ciudad activa configurada');

  // ---- 3. Crear el usuario de Auth ------------------------------------------
  const generada = !alta.password;
  const password = alta.password ?? passwordTemporal();

  const { data: creado, error: errAlta } = await admin.auth.admin.createUser({
    email,
    password,
    // La administracion ya verifico al local o al cadete en persona: no se le
    // pide confirmar el email (y sin SMTP propio el mail no llegaria).
    email_confirm: true,
    app_metadata: { rol: alta.rol },
    user_metadata: { nombre, telefono },
  });

  if (errAlta || !creado?.user) {
    const yaExiste = /already|registered|exists/i.test(errAlta?.message ?? '');
    return yaExiste
      ? error(409, 'email_existente', 'Ya hay una cuenta con ese email')
      : error(500, 'auth', errAlta?.message ?? 'No se pudo crear el usuario');
  }

  const usuarioId = creado.user.id;

  // ---- 4. Crear la ficha del local o del cadete -----------------------------
  // Si esto falla, se borra el usuario recien creado: una cuenta sin ficha no
  // puede operar y ademas bloquea el email para un segundo intento.
  try {
    if (alta.rol === 'comercio') {
      let rubroNombre = 'General';
      if (alta.rubro_id) {
        const { data: rubro } = await admin
          .from('rubros').select('nombre').eq('id', alta.rubro_id).maybeSingle();
        if (rubro) rubroNombre = rubro.nombre;
      }

      const { data: comercio, error: errCom } = await admin
        .from('comercios')
        .insert({
          perfil_id: usuarioId,
          ciudad_id: ciudad.id,
          nombre,
          telefono,
          rubro: rubroNombre,
          rubro_id: alta.rubro_id ?? null,
          calle: alta.calle!.trim(),
          referencia: alta.referencia?.trim() || null,
          // PostGIS acepta EWKT como texto en columnas geography.
          ubicacion: `SRID=4326;POINT(${alta.lng} ${alta.lat})`,
          // Lo crea la administracion: queda aprobado desde el alta.
          estado_aprobacion: 'aprobado',
          aprobado_en: new Date().toISOString(),
          aprobado_por: sesion.user.id,
        })
        .select('id')
        .single();
      if (errCom) throw errCom;

      return responder(201, {
        usuario_id: usuarioId,
        comercio_id: comercio.id,
        email,
        password_temporal: generada ? password : null,
      });
    }

    const { data: rep, error: errRep } = await admin
      .from('repartidores')
      .insert({
        perfil_id: usuarioId,
        ciudad_id: ciudad.id,
        nombre,
        telefono,
        vehiculo: alta.vehiculo,
        estado_aprobacion: 'aprobado',
        aprobado_en: new Date().toISOString(),
        aprobado_por: sesion.user.id,
      })
      .select('id')
      .single();
    if (errRep) throw errRep;

    return responder(201, {
      usuario_id: usuarioId,
      repartidor_id: rep.id,
      email,
      password_temporal: generada ? password : null,
    });
  } catch (e) {
    await admin.auth.admin.deleteUser(usuarioId);
    const mensaje = e instanceof Error ? e.message : String((e as { message?: string })?.message ?? e);
    return error(500, 'ficha', `No se pudo crear la ficha: ${mensaje}`);
  }
});
