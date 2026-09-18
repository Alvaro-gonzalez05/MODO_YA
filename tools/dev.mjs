// Servidor de desarrollo con recarga automática:
//   node tools/dev.mjs modo_ya 5051
//   node tools/dev.mjs repartidor 5052
//
// Corre `flutter run -d web-server` conectado a la base (env/dev.json) y,
// cada vez que cambia un .dart de la app o de packages/, le manda "R" (hot
// restart: recompila lo cambiado y recarga la página en todos los navegadores
// abiertos) sin que nadie tenga que tocar la terminal. Escucha en todas las interfaces ("any") para
// poder abrirla también desde el celular en la misma red wifi.

import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { watch } from 'node:fs';
import { networkInterfaces } from 'node:os';
import { join, resolve } from 'node:path';

const app = process.argv[2] ?? 'modo_ya';
const puerto = process.argv[3] ?? '5051';
const raiz = resolve(import.meta.dirname, '..');
const dirApp = join(raiz, 'apps', app);

const flutter = spawn(
  'flutter',
  [
    'run', '-d', 'web-server',
    '--web-port', puerto,
    '--web-hostname', 'any',
    // Con WebSockets el cliente de depuración no conecta y la app queda en la
    // pantalla de carga para siempre.
    '--web-server-debug-injected-client-protocol=sse',
    '--web-server-debug-backend-protocol=sse',
    '--web-server-debug-protocol=sse',
    // El formato de módulos nuevo (hot reload) exige WebSockets y en esta PC
    // no conectan; con el anterior se usa hot restart, que tarda unos segundos.
    '--no-web-experimental-hot-reload',
    '--dart-define-from-file=../../env/dev.json',
  ],
  { cwd: dirApp, shell: true, stdio: ['pipe', 'pipe', 'inherit'] },
);

// Aviso de recarga para el navegador: el cliente de depuración de Flutter no
// conecta desde navegadores comunes, así que web/index.html escucha este canal
// (puerto + 1000) y recarga la página cuando termina de recompilar.
const navegadores = new Set();
createServer((req, res) => {
  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-store',
    'Access-Control-Allow-Origin': '*',
  });
  res.write(': conectado\n\n');
  navegadores.add(res);
  req.on('close', () => navegadores.delete(res));
}).listen(Number(puerto) + 1000);
const avisarRecarga = () => { for (const r of navegadores) r.write('data: recargar\n\n'); };

let listo = false;
flutter.stdout.on('data', (b) => {
  const texto = b.toString();
  process.stdout.write(texto);
  if (/Recompile complete|Restarted application/.test(texto)) avisarRecarga();
  if (!listo && /is being served at|lib[\\/]main\.dart is being served/.test(texto)) {
    listo = true;
    const ips = Object.values(networkInterfaces()).flat()
      .filter((i) => i && i.family === 'IPv4' && !i.internal).map((i) => i.address);
    console.log(`\n>> Listo: http://localhost:${puerto}`);
    for (const ip of ips) console.log(`>> Desde el celular (misma wifi): http://${ip}:${puerto}`);
  }
});
flutter.on('exit', (code) => process.exit(code ?? 0));

// Recarga al guardar: espera a que dejen de cambiar archivos 400 ms.
let espera;
const recargar = (archivo) => {
  if (!listo || !archivo?.endsWith('.dart')) return;
  clearTimeout(espera);
  espera = setTimeout(() => {
    console.log(`>> Cambió ${archivo}: recargando`);
    flutter.stdin.write('R');
  }, 400);
};
for (const dir of [join(dirApp, 'lib'), join(raiz, 'packages')]) {
  watch(dir, { recursive: true }, (_, archivo) => recargar(archivo));
}

for (const s of ['SIGINT', 'SIGTERM']) {
  process.on(s, () => { flutter.stdin.write('q'); setTimeout(() => process.exit(0), 1500); });
}
