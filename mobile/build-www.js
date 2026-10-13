/* Prepara mobile/www (lo que va dentro de la app de Android) a partir del juego ya construido.
 *   node tools/build.js        (en la raíz: index.html + js/app.min.js)
 *   cd mobile && npm run apk   (este script + cap sync + gradle)
 * - Sólo se copia lo que usa el juego: nada de páginas web, herramientas ni servidores.
 * - index.html: window.PS_APP = true (un jugador, sin conexión: ver css/style.css .ps-app)
 *   y shell.js (botón Atrás y vibración, cosas que una web no puede hacer).
 */
const fs = require('fs'), path = require('path');
const ROOT = path.join(__dirname, '..');
const OUT = path.join(__dirname, 'www');

const COPY = ['css', 'js/app.min.js', 'assets/pokemon', 'assets/icons', 'assets/fonts', 'favicon.ico'];

fs.rmSync(OUT, { recursive: true, force: true });
for (const rel of COPY) {
  const src = path.join(ROOT, rel);
  if (!fs.existsSync(src)) throw new Error('Falta ' + rel + ' (¿has hecho node tools/build.js?)');
  fs.cpSync(src, path.join(OUT, rel), { recursive: true });
}
fs.copyFileSync(path.join(__dirname, 'shell.js'), path.join(OUT, 'shell.js'));

let html = fs.readFileSync(path.join(ROOT, 'index.html'), 'utf8');
const flag = '<script>window.PS_PAGES = true;</script>';
if (!html.includes(flag)) throw new Error('index.html no tiene ' + flag);
html = html.replace(flag, '<script>window.PS_APP = true; window.PS_PAGES = false;</script>');
// Fuera lo que sólo sirve en la web: manifiesto de PWA y datos para buscadores.
html = html.replace(/\s*<link rel="manifest"[^>]*>/, '');
html = html.replace(/\s*<script type="application\/ld\+json">[\s\S]*?<\/script>/g, '');
// shell.js después del juego (defer: en orden), para poder engancharse a G.
html = html.replace(/(<script defer src="js\/app\.min\.js[^"]*"><\/script>)/, '$1\n<script defer src="shell.js"></script>');
if (!html.includes('src="shell.js"')) throw new Error('no se pudo añadir shell.js a index.html');
fs.writeFileSync(path.join(OUT, 'index.html'), html);

let n = 0, bytes = 0;
(function walk(d) { for (const e of fs.readdirSync(d, { withFileTypes: true })) { const p = path.join(d, e.name); if (e.isDirectory()) walk(p); else { n++; bytes += fs.statSync(p).size; } } })(OUT);
console.log(`www: ${n} archivos · ${(bytes / 1048576).toFixed(1)} MB`);
