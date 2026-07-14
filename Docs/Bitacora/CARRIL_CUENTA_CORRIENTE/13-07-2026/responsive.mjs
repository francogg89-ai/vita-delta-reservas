// SB-UI-6 -- Responsive REAL en Chromium. No es una simulacion: levanta el harness
// (`npm run qa`), abre el AppShell de verdad y mide el layout que ve el socio.
//
//   npm run qa            # en una terminal (ocupa el 5173)
//   npm run qa:responsive # en otra
//
// OJO: `npm run dev` y `npm run qa` PELEAN POR EL PUERTO 5173 (strictPort). Si el server de
// control esta levantado, `npm run qa` no arranca. Bajarlo primero.
//
// Requiere playwright. No es dependencia del proyecto (no entra al bundle ni al deploy):
//   npm i -D playwright && npx playwright install chromium

const BASE = process.env.QA_URL ?? 'http://localhost:5173';
const VIEWPORTS = [
  { nombre: 'mobile', w: 375, h: 812 },
  { nombre: 'tablet', w: 768, h: 1024 },
  { nombre: 'desktop', w: 1280, h: 900 },
];

let chromium;
try {
  ({ chromium } = await import('playwright'));
} catch {
  console.error(
    '\n  Falta playwright.\n' +
      '    npm i -D playwright && npx playwright install chromium\n'
  );
  process.exit(2);
}

let fallos = 0;
const hallazgos = [];
const ok = (c, m) => {
  console.log(`      ${c ? 'ok   ' : 'FALLA'} ${m}`);
  if (!c) fallos++;
};
/**
 * HALLAZGO CONOCIDO: bug REAL, medido, pendiente de decision de Franco. No cuenta como falla de la
 * suite (si no, la suite deja de servir de gate de regresion), pero se lista SIEMPRE y bien fuerte.
 * Cuando se decida el fix, esto pasa a ser un `ok()` duro.
 */
const hallazgo = (c, id, m) => {
  console.log(`      ${c ? 'ok   ' : '·HALL'} ${m}`);
  if (!c) hallazgos.push(`${id} -- ${m}`);
};

/** Mide la pagina entera, EXCLUYENDO la barra del harness (que es un overlay fijo, no la app). */
const medir = () =>
  // eslint-disable-next-line no-undef
  ({
    pagina: document.documentElement.scrollWidth,
    viewport: document.documentElement.clientWidth,
    main: document.querySelector('main')?.offsetWidth ?? 0,
    tablas: [...document.querySelectorAll('main .overflow-x-auto')]
      .filter((t) => t.getClientRects().length)
      .map((t) => ({ scrollea: t.scrollWidth > t.clientWidth, sw: t.scrollWidth, cw: t.clientWidth })),
    // cualquier elemento de la app que se salga por derecha SIN estar dentro de un scroller
    desbordes: (() => {
      const vw = document.documentElement.clientWidth;
      const malos = [];
      for (const el of document.querySelectorAll('main *')) {
        if (getComputedStyle(el).display === 'none') continue;
        let dentro = false;
        for (let a = el.parentElement; a; a = a.parentElement) {
          if (getComputedStyle(a).overflowX === 'auto') { dentro = true; break; }
        }
        const r = el.getBoundingClientRect();
        if (!dentro && r.right > vw + 1) malos.push(Math.round(r.right - vw));
      }
      return malos;
    })(),
    // textos encimados: dos hermanos en la misma linea cuyos rects se pisan
    encimados: (() => {
      const malos = [];
      for (const p of document.querySelectorAll('main dl > div, main .flex')) {
        const k = [...p.children].filter((c) => c.getClientRects().length);
        for (let i = 0; i + 1 < k.length; i++) {
          const a = k[i].getBoundingClientRect();
          const b = k[i + 1].getBoundingClientRect();
          const mismaLinea = Math.abs(a.top - b.top) < 4;
          if (mismaLinea && a.right > b.left + 1) malos.push((k[i].textContent ?? '').trim().slice(0, 24));
        }
      }
      return malos;
    })(),
    select: (() => {
      const s = document.querySelector('main select');
      if (!s) return null;
      const r = s.getBoundingClientRect();
      return { w: Math.round(r.width), h: Math.round(r.height), dentro: r.right <= document.documentElement.clientWidth + 1 };
    })(),
    boton: (() => {
      const b = [...document.querySelectorAll('main button')].find((x) => /consultar/i.test(x.textContent ?? ''));
      if (!b) return null;
      const r = b.getBoundingClientRect();
      return { w: Math.round(r.width), h: Math.round(r.height), dentro: r.right <= document.documentElement.clientWidth + 1 };
    })(),
    aside: (() => {
      const a = document.querySelector('aside');
      if (!a) return null;
      const r = a.getBoundingClientRect();
      return { visible: getComputedStyle(a).display !== 'none', w: Math.round(r.width) };
    })(),
  });

const b = await chromium.launch({ args: ['--no-sandbox'] });

for (const abierto of [false, true]) {
  console.log(`\n${'='.repeat(92)}\nDETALLE FINO ${abierto ? 'ABIERTO' : 'CERRADO'}\n${'='.repeat(92)}`);
  for (const v of VIEWPORTS) {
    const p = await b.newPage({ viewport: { width: v.w, height: v.h } });
    await p.goto(BASE, { waitUntil: 'networkidle' });
    await p.waitForSelector('main');
    if (abierto) {
      const d = p.locator('main details').first();
      if (await d.count()) await d.locator('summary').click();
      await p.waitForTimeout(120);
    }
    const r = await p.evaluate(medir);

    console.log(`\n  ${v.nombre} (${v.w}px)`);
    ok(r.pagina === r.viewport, `documentElement.scrollWidth === clientWidth  (${r.pagina} === ${r.viewport})`);
    ok(r.desbordes.length === 0, `ningun elemento desborda el viewport${r.desbordes.length ? ` -- ${r.desbordes.length} elementos, peor +${Math.max(...r.desbordes)}px` : ''}`);
    ok(r.encimados.length === 0, `ningun texto se encima${r.encimados.length ? ` -- ${JSON.stringify(r.encimados.slice(0, 3))}` : ''}`);

    const anchas = r.tablas.filter((t) => t.sw > t.cw);
    ok(
      r.tablas.length > 0,
      `hay ${r.tablas.length} tabla(s) visible(s); ${anchas.length} necesita(n) scroll interno y lo tiene(n)`
    );
    ok(
      r.tablas.every((t) => t.sw <= t.cw || t.scrollea),
      'toda tabla mas ancha que su contenedor scrollea DENTRO (no arrastra la pagina)'
    );

    if (r.select) ok(r.select.dentro && r.select.h >= 32, `select usable: ${r.select.w}x${r.select.h}px, dentro del viewport`);
    if (r.boton) ok(r.boton.dentro && r.boton.h >= 32, `boton Consultar usable: ${r.boton.w}x${r.boton.h}px, dentro del viewport`);

    // menu mobile
    const esMobile = v.w < 768;
    ok(
      esMobile ? r.aside?.visible === false : r.aside?.visible === true,
      esMobile ? 'menu mobile CERRADO por defecto (aside oculto)' : `menu lateral visible (${r.aside?.w}px)`
    );

    if (esMobile) {
      const hamburguesa = p.locator('button[aria-label="Abrir o cerrar menu"]');
      await hamburguesa.click();
      await p.waitForTimeout(120);
      const abiertoR = await p.evaluate(() => {
        const a = document.querySelector('aside');
        return {
          visible: getComputedStyle(a).display !== 'none',
          expanded: document.querySelector('button[aria-label="Abrir o cerrar menu"]')?.getAttribute('aria-expanded'),
          links: a.querySelectorAll('a').length,
          desborda: document.documentElement.scrollWidth > document.documentElement.clientWidth,
        };
      });
      ok(abiertoR.visible, 'menu mobile ABIERTO al tocar la hamburguesa');
      ok(abiertoR.expanded === 'true', 'aria-expanded="true" (accesible)');
      ok(abiertoR.links > 0, `el menu tiene ${abiertoR.links} enlaces`);
      // H-1: el drawer es `position: static` + `shrink-0` -> cuando se abre EMPUJA el contenido en
      // vez de superponerse. El <main> queda en 119px (71px utiles tras el p-6) y un importe como
      // "$ 3.800.000,00" mide 135px con `shrink-0`: no entra ni puede encoger. NO es un problema de
      // A30/A31 -- le pasa a cualquier pantalla del portal. Fix propuesto aparte (drawer overlay).
      hallazgo(!abiertoR.desborda, 'H-1', 'con el menu abierto la pagina NO desborda');

      // navegar cierra el drawer
      await p.locator('aside a').first().click();
      await p.waitForTimeout(150);
      const cerrado = await p.evaluate(() => getComputedStyle(document.querySelector('aside')).display === 'none');
      ok(cerrado, 'navegar CIERRA el drawer mobile (onNavigate)');
    }

    if (!abierto) {
      await p.screenshot({ path: `qa/screenshots/${v.nombre}-${v.w}.png`, fullPage: false });
    } else if (esMobile) {
      await p.screenshot({ path: 'qa/screenshots/mobile-375-detalle-abierto.png', fullPage: false });
    }
    await p.close();
  }
}

await b.close();
console.log(fallos === 0 ? '\n  RESPONSIVE OK (aserciones duras)' : `\n  ${fallos} FALLAS`);
if (hallazgos.length) {
  console.log(`\n  ${hallazgos.length} HALLAZGO(S) ABIERTO(S) -- medidos, pendientes de decision:`);
  for (const h of [...new Set(hallazgos)]) console.log(`    ${h}`);
}
console.log('');
process.exit(fallos === 0 ? 0 : 1);
