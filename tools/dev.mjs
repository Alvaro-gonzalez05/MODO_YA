// Servidor de desarrollo liviano:
//   node tools/dev.mjs modo_ya 5051
//   node tools/dev.mjs repartidor 5052
//
// El disco C: de esta PC se llena y la RAM es justa. El modo debug de Flutter
// (`flutter run -d web-server`) deja un compilador residente de mas de 1 GB y
// el navegador con la version debug se come otro tanto: Windows agranda la
// paginacion en C: hasta dejarlo en cero. Por eso esto:
//
//   * Copia el codigo a D:\dev\modoya-dev y compila ahi: .dart_tool, build y
//     los temporales de Flutter quedan en D:, nada en C:.
//   * Compila la version release (liviana en el navegador) solo cuando cambia
//     algo, y el compilador se cierra al terminar. Tarda ~1 minuto por cambio.
//   * Sirve el resultado en http://localhost:<puerto> conectado a la base
//     (env/dev.json) y avisa al navegador para que recargue solo (canal SSE en
//     puerto + 1000, lo escucha web/index.html).
//   * Escucha en todas las interfaces: se puede abrir desde el celular en la
//     misma wifi.

import { spawn, spawnSync } from 'node:child_process';
import { createReadStream, existsSync, mkdirSync, readdirSync, rmSync, statSync, watch } from 'node:fs';
import { createServer } from 'node:http';
import { networkInterfaces } from 'node:os';
import { extname, join, normalize, resolve } from 'node:path';

const app = process.argv[2] ?? 'modo_ya';
const puerto = Number(process.argv[3] ?? 5051);
const origen = resolve(import.meta.dirname, '..');
const copia = 'D:/dev/modoya-dev';
const temporales = 'D:/dev/tmp';
const web = normalize(join(copia, 'apps', app, 'build', 'web'));

mkdirSync(temporales, { recursive: true });
// Flutter deja una carpeta flutter_tools.* por cada corrida y no la borra.
const limpiarTemporales = () => {
  for (const d of readdirSync(temporales)) {
    if (d.startsWith('flutter_tools.')) {
      try { rmSync(join(temporales, d), { recursive: true, force: true }); } catch { /* en uso */ }
    }
  }
};

// ---- Copia a D: -------------------------------------------------------------

function sincronizar() {
  // robocopy /MIR: solo copia lo que cambio. Codigos < 8 son exito.
  const r = spawnSync('robocopy', [
    origen, copia, '/MIR', '/NFL', '/NDL', '/NJH', '/NJS', '/NP', '/R:1', '/W:1',
    '/XD', '.dart_tool', 'build', '.git', 'node_modules', 'ephemeral', '.gradle', '.kotlin',
  ], { encoding: 'utf8' });
  if (r.status >= 8) console.error('>> robocopy fallo:', r.stdout, r.stderr);
}

// ---- Compilacion -------------------------------------------------------------

let compilando = false;
let pendiente = false;

function compilar() {
  if (compilando) { pendiente = true; return; }
  compilando = true;
  pendiente = false;
  limpiarTemporales();
  sincronizar();
  const inicio = Date.now();
  console.log(`\n>> Compilando ${app}...`);
  const f = spawn('flutter', ['build', 'web', '--release', '--dart-define-from-file=../../env/dev.json'], {
    cwd: join(copia, 'apps', app),
    shell: true,
    stdio: ['ignore', 'pipe', 'pipe'],
    env: { ...process.env, TEMP: temporales, TMP: temporales },
  });
  let salida = '';
  f.stdout.on('data', (b) => { salida += b; });
  f.stderr.on('data', (b) => { salida += b; });
  f.on('exit', (code) => {
    compilando = false;
    const s = ((Date.now() - inicio) / 1000).toFixed(0);
    if (code === 0) {
      console.log(`>> Listo en ${s} s: recargando el navegador`);
      avisarRecarga();
    } else {
      const errores = salida.split('\n').filter((l) => /error/i.test(l)).slice(0, 20).join('\n');
      console.error(`>> Error de compilacion (${s} s):\n${errores || salida.slice(-2000)}`);
    }
    limpiarTemporales();
    if (pendiente) compilar();
  });
}

// ---- Servidor estatico + aviso de recarga -----------------------------------

const tipos = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.mjs': 'text/javascript',
  '.css': 'text/css', '.json': 'application/json', '.png': 'image/png', '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml', '.ico': 'image/x-icon', '.wasm': 'application/wasm', '.ttf': 'font/ttf',
  '.otf': 'font/otf', '.woff2': 'font/woff2', '.mp3': 'audio/mpeg', '.wav': 'audio/wav',
};

createServer((req, res) => {
  const ruta = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  let archivo = normalize(join(web, ruta));
  if (!archivo.startsWith(web) || !existsSync(archivo) || statSync(archivo).isDirectory()) {
    archivo = join(web, 'index.html');
  }
  if (!existsSync(archivo)) {
    res.writeHead(503, { 'Content-Type': 'text/html; charset=utf-8' });
    res.end('<meta http-equiv="refresh" content="5"><p style="font-family:sans-serif">Compilando la primera vez, un minuto...</p>');
    return;
  }
  res.writeHead(200, { 'Content-Type': tipos[extname(archivo)] ?? 'application/octet-stream', 'Cache-Control': 'no-store' });
  createReadStream(archivo).pipe(res);
}).listen(puerto, '0.0.0.0');

const navegadores = new Set();
createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-store', 'Access-Control-Allow-Origin': '*' });
  res.write(': conectado\n\n');
  navegadores.add(res);
  req.on('close', () => navegadores.delete(res));
}).listen(puerto + 1000, '0.0.0.0');
const avisarRecarga = () => { for (const r of navegadores) r.write('data: recargar\n\n'); };

// ---- Arranque y cambios -----------------------------------------------------

const ips = Object.values(networkInterfaces()).flat().filter((i) => i && i.family === 'IPv4' && !i.internal).map((i) => i.address);
console.log(`>> MODO YA (${app}) en http://localhost:${puerto}`);
for (const ip of ips) console.log(`>> Desde el celular (misma wifi): http://${ip}:${puerto}`);
console.log('>> Compila en D:\\dev\\modoya-dev. Cada cambio tarda ~1 minuto en verse.');

compilar();

let espera;
const alCambiar = (archivo) => {
  if (!archivo || /(^|[\\/])(\.dart_tool|build)([\\/]|$)/.test(archivo)) return;
  if (!/\.(dart|yaml|json|png|jpg|mp3|wav|html|ttf)$/.test(archivo)) return;
  clearTimeout(espera);
  // Espera a que dejen de cambiar archivos (se guardan varios juntos).
  espera = setTimeout(compilar, 1500);
};
for (const dir of [join(origen, 'apps', app, 'lib'), join(origen, 'apps', app, 'web'), join(origen, 'packages'), join(origen, 'env')]) {
  if (existsSync(dir)) watch(dir, { recursive: true }, (_, a) => alCambiar(a));
}
