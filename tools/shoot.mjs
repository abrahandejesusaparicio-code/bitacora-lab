// Captura la galería de animaciones con Playwright.
// node tools/shoot.mjs
import fs from 'fs';
import path from 'path';
import os from 'os';
import { createRequire } from 'module';
import { fileURLToPath } from 'url';

// Playwright vive en el caché de npx; lo localizamos en tiempo de ejecución.
const require = createRequire(import.meta.url);
function findPlaywright() {
  try { return require('playwright'); } catch (_) {}
  const npx = path.join(os.homedir(), 'AppData', 'Local', 'npm-cache', '_npx');
  for (const d of fs.readdirSync(npx)) {
    const p = path.join(npx, d, 'node_modules', 'playwright');
    if (fs.existsSync(p)) return require(p);
  }
  throw new Error('No se encontró playwright');
}
const { chromium } = findPlaywright();

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const indexHtml = fs.readFileSync(path.join(ROOT, 'index.html'), 'utf8');
const style = (indexHtml.match(/<style>[\s\S]*?<\/style>/) || [''])[0];
const body = fs.readFileSync(path.join(ROOT, 'tools', 'gallery-body.html'), 'utf8');

const full = `<!doctype html><html lang="es"><head><meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1.0"/>${style}</head>
<body>${body}</body></html>`;

const tmp = path.join(os.tmpdir(), 'lab-anim-gallery.html');
fs.writeFileSync(tmp, full, 'utf8');

const shotsDir = path.join(ROOT, 'tools', 'shots');
fs.mkdirSync(shotsDir, { recursive: true });

const browser = await chromium.launch();
const page = await browser.newPage({
  viewport: { width: 1240, height: 900 },
  deviceScaleFactor: 2,
  reducedMotion: 'no-preference',
});
await page.goto('file://' + tmp.replace(/\\/g, '/'));
await page.waitForFunction(() => window.__galReady === true, { timeout: 8000 }).catch(() => {});
await page.waitForTimeout(1300); // deja que matraz/canasta/volcán/tablilla lleguen a un buen cuadro
await page.evaluate(() => window.__fireConfetti && window.__fireConfetti()); // confeti fresco
await page.waitForTimeout(300);  // a media explosión

// 1) Vista general (todas las animaciones)
await page.screenshot({ path: path.join(shotsDir, '00-galeria-completa.png'), fullPage: true });

// 2) Cada panel por separado
const panels = await page.$$('.panel');
for (const panel of panels) {
  const name = await panel.getAttribute('data-name');
  await panel.screenshot({ path: path.join(shotsDir, `${name}.png`) });
}

console.log('OK · capturas en tools/shots');
await browser.close();
