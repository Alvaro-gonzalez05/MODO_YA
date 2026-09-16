// Servidor estatico minimo para probar las builds web en la PC:
//   node tools/servir.mjs apps/modo_ya/build/web 5051
// Cualquier ruta que no sea un archivo devuelve index.html (la app enruta sola).

import { createServer } from 'node:http';
import { createReadStream, existsSync, statSync } from 'node:fs';
import { extname, join, normalize, resolve } from 'node:path';

const raiz = resolve(process.argv[2] ?? '.');
const puerto = Number(process.argv[3] ?? 5051);

const tipos = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript',
  '.mjs': 'text/javascript',
  '.css': 'text/css',
  '.json': 'application/json',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.wasm': 'application/wasm',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
  '.woff2': 'font/woff2',
};

createServer((req, res) => {
  const ruta = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  let archivo = normalize(join(raiz, ruta));
  if (!archivo.startsWith(raiz)) archivo = join(raiz, 'index.html');
  if (!existsSync(archivo) || statSync(archivo).isDirectory()) archivo = join(raiz, 'index.html');
  res.writeHead(200, {
    'Content-Type': tipos[extname(archivo)] ?? 'application/octet-stream',
    'Cache-Control': 'no-store',
  });
  createReadStream(archivo).pipe(res);
}).listen(puerto, () => console.log(`Sirviendo ${raiz} en http://localhost:${puerto}`));
