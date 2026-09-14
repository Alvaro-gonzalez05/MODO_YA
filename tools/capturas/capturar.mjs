// Capturas de la app web con Chrome headless, para revisar el diseno sin
// abrir la app a mano.
//
//   node tools/capturas/capturar.mjs abrir               # levanta Chrome (queda corriendo)
//   node tools/capturas/capturar.mjs pasos pasos.json    # ejecuta pasos sobre la pestana
//   node tools/capturas/capturar.mjs cerrar
//
// pasos.json es una lista de objetos, por ejemplo:
//   [{"tamano": [1440, 900]}, {"ir": "http://localhost:8791/"}, {"esperar": 4000},
//    {"click": [720, 400]}, {"escribir": "hola"}, {"tecla": "Enter"},
//    {"captura": "salida/login.png"}]
//
// Flutter web dibuja en un canvas: se hace click por coordenadas y se escribe
// con Input.insertText, que llega al campo que tiene el foco.

import { spawn } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';

const PUERTO = 9333;
const CHROME = process.env.CHROME ?? 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const PERFIL = process.env.PERFIL_CHROME ?? 'D:/dev/tmp/chrome-capturas';

const dormir = (ms) => new Promise((r) => setTimeout(r, ms));

async function pestana() {
  const lista = await (await fetch(`http://127.0.0.1:${PUERTO}/json/list`)).json();
  let p = lista.find((t) => t.type === 'page');
  if (!p) p = await (await fetch(`http://127.0.0.1:${PUERTO}/json/new?about:blank`, { method: 'PUT' })).json();
  return p.webSocketDebuggerUrl;
}

async function conectar() {
  const ws = new WebSocket(await pestana());
  await new Promise((ok, mal) => { ws.onopen = ok; ws.onerror = mal; });
  let id = 0;
  const pendientes = new Map();
  const consola = [];
  ws.onmessage = (m) => {
    const d = JSON.parse(m.data);
    if (d.id && pendientes.has(d.id)) {
      const { ok, mal } = pendientes.get(d.id);
      pendientes.delete(d.id);
      d.error ? mal(new Error(JSON.stringify(d.error))) : ok(d.result);
    } else if (d.method === 'Runtime.consoleAPICalled') {
      consola.push(d.params.args.map((a) => a.value ?? a.description).join(' '));
    } else if (d.method === 'Runtime.exceptionThrown') {
      consola.push('EXCEPCION: ' + (d.params.exceptionDetails.exception?.description ?? d.params.exceptionDetails.text));
    }
  };
  const cmd = (method, params = {}) => new Promise((ok, mal) => {
    const n = ++id;
    pendientes.set(n, { ok, mal });
    ws.send(JSON.stringify({ id: n, method, params }));
  });
  await cmd('Runtime.enable');
  await cmd('Page.enable');
  return { ws, cmd, consola };
}

async function click(cmd, x, y) {
  for (const type of ['mouseMoved', 'mousePressed', 'mouseReleased']) {
    await cmd('Input.dispatchMouseEvent', { type, x, y, button: 'left', clickCount: 1, pointerType: 'mouse' });
    await dormir(40);
  }
}

const TECLAS = {
  Enter: { key: 'Enter', code: 'Enter', windowsVirtualKeyCode: 13 },
  Tab: { key: 'Tab', code: 'Tab', windowsVirtualKeyCode: 9 },
  Escape: { key: 'Escape', code: 'Escape', windowsVirtualKeyCode: 27 },
  Backspace: { key: 'Backspace', code: 'Backspace', windowsVirtualKeyCode: 8 },
};

async function pasos(archivo) {
  const lista = JSON.parse(readFileSync(archivo, 'utf8'));
  const { ws, cmd, consola } = await conectar();
  for (const p of lista) {
    if (p.tamano) {
      const [width, height, movil] = p.tamano;
      await cmd('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: 1, mobile: !!movil });
    } else if (p.ir) {
      await cmd('Page.navigate', { url: p.ir });
    } else if (p.esperar) {
      await dormir(p.esperar);
    } else if (p.click) {
      await click(cmd, ...p.click);
    } else if (p.escribir !== undefined) {
      await cmd('Input.insertText', { text: p.escribir });
    } else if (p.tecla) {
      const t = TECLAS[p.tecla];
      await cmd('Input.dispatchKeyEvent', { type: 'keyDown', ...t });
      await cmd('Input.dispatchKeyEvent', { type: 'keyUp', ...t });
    } else if (p.rueda) {
      const [x, y, dy] = p.rueda;
      await cmd('Input.dispatchMouseEvent', { type: 'mouseWheel', x, y, deltaX: 0, deltaY: dy });
    } else if (p.js) {
      const r = await cmd('Runtime.evaluate', { expression: p.js, awaitPromise: true, returnByValue: true });
      console.log('js:', JSON.stringify(r.result?.value));
    } else if (p.captura) {
      const r = await cmd('Page.captureScreenshot', { format: 'png' });
      mkdirSync(dirname(p.captura), { recursive: true });
      writeFileSync(p.captura, Buffer.from(r.data, 'base64'));
      console.log('captura:', p.captura);
    }
  }
  if (consola.length) console.log('consola:\n  ' + consola.slice(-30).join('\n  '));
  ws.close();
}

const [, , accion, arg] = process.argv;
if (accion === 'abrir') {
  const hijo = spawn(CHROME, [
    '--headless=new', `--remote-debugging-port=${PUERTO}`, `--user-data-dir=${PERFIL}`,
    '--hide-scrollbars', '--window-size=1440,900', '--no-first-run', '--no-default-browser-check',
    'about:blank',
  ], { detached: true, stdio: 'ignore' });
  hijo.unref();
  for (let i = 0; i < 40; i++) {
    try { await fetch(`http://127.0.0.1:${PUERTO}/json/version`); console.log('chrome listo'); process.exit(0); } catch { await dormir(250); }
  }
  console.error('chrome no respondio'); process.exit(1);
} else if (accion === 'pasos') {
  await pasos(arg);
} else if (accion === 'cerrar') {
  const { cmd } = await conectar();
  await cmd('Browser.close').catch(() => {});
  console.log('cerrado');
} else {
  console.error('uso: abrir | pasos <archivo.json> | cerrar');
  process.exit(1);
}
