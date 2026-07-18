// SB-UI-6 -- Responsive REAL en Chromium. No es una simulacion: levanta el harness
// (`npm run qa`), abre el AppShell de verdad y mide el layout que ve el socio.
//
//   npm run qa            # en una terminal (ocupa el 5173)
//   npm run qa:responsive # en otra
//
// OJO: `npm run dev` y `npm run qa` PELEAN POR EL PUERTO 5173 (strictPort). Si el server de
// control esta levantado, `npm run qa` no arranca. Bajarlo primero.
//
// Requiere playwright, que YA es devDependency directa (desde SB-UI-6-FIX). No entra al bundle ni
// al deploy: es solo para correr esta suite. Tras `npm ci`, solo falta bajar el binario:
//   npx playwright install chromium

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
    '\n  Falta el binario de Chromium (playwright ya esta instalado).\n' +
      '    npx playwright install chromium\n'
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
 * REGISTRO DE HALLAZGO (infraestructura de tripwire). Un hallazgo es un bug REAL y medido que se
 * lista pero no cuenta como falla dura. Tras SB-UI-6.1 NO quedan hallazgos abiertos: H-1 y H-2 son
 * ASERCIONES DURAS (`ok()`). Esta funcion se conserva a proposito, sin invocar, para que un hallazgo
 * NUEVO se pueda registrar y el gate lo detecte como "SOBRAN" (set esperado {}).
 */
const hallazgo = (c, id, m) => {
  console.log(`      ${c ? 'ok   ' : '·HALL'} ${m}`);
  // Se deduplica por ID: el mismo hallazgo se evaluaria en varios viewports pero es UN solo
  // hallazgo. Se guarda el primer mensaje visto para cada ID.
  if (!c && !hallazgos.some((h) => h.id === id)) hallazgos.push({ id, msg: `${id} -- ${m}` });
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
      .map((t) => {
        const cs = getComputedStyle(t);
        const masAncha = t.scrollWidth > t.clientWidth + 1;
        // NO alcanza con `scrollWidth > clientWidth`: eso solo dice que el contenido no entra.
        // Se DESPLAZA de verdad y se comprueba que `scrollLeft` se movio. Un wrapper con
        // `overflow-x: hidden` (o con el scroll bloqueado) tiene scrollWidth mayor y NO se mueve:
        // ahi es donde el chequeo viejo mentia.
        const antes = t.scrollLeft;
        t.scrollLeft = 40;
        const desplazable = t.scrollLeft > antes;
        t.scrollLeft = antes; // se restaura: la medicion no puede dejar la pantalla movida
        const restaurado = t.scrollLeft === antes;
        return {
          overflowX: cs.overflowX,
          masAncha,
          desplazable,
          restaurado,
          sw: t.scrollWidth,
          cw: t.clientWidth,
        };
      }),
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

/**
 * `QA_CHROME` permite apuntar a un Chromium ya instalado (util en CI o si `npx playwright install`
 * no puede bajar el binario). Sin esa variable, Playwright usa el suyo, que es el camino normal:
 *   npx playwright install chromium
 */
const lanzar = () =>
  chromium.launch({
    args: ['--no-sandbox'],
    ...(process.env.QA_CHROME ? { executablePath: process.env.QA_CHROME } : {}),
  });

const b = await lanzar();

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

    const anchas = r.tablas.filter((t) => t.masAncha);
    ok(r.tablas.length > 0, `hay ${r.tablas.length} tabla(s) visible(s); ${anchas.length} no entran a lo ancho`);
    ok(
      r.tablas.every((t) => t.overflowX === 'auto' || t.overflowX === 'scroll'),
      `todos los wrappers tienen overflow-x desplazable (${[...new Set(r.tablas.map((t) => t.overflowX))].join(', ')})`
    );
    ok(
      anchas.every((t) => t.desplazable),
      `las ${anchas.length} tabla(s) anchas SE DESPLAZAN de verdad (scrollLeft cambia al asignarlo)`
    );
    ok(
      r.tablas.every((t) => t.restaurado),
      'y la medicion restauro el scrollLeft: no deja la pantalla movida'
    );

    if (r.select) ok(r.select.dentro && r.select.h >= 32, `select usable: ${r.select.w}x${r.select.h}px, dentro del viewport`);
    if (r.boton) ok(r.boton.dentro && r.boton.h >= 32, `boton Consultar usable: ${r.boton.w}x${r.boton.h}px, dentro del viewport`);

    // menu mobile
    const esMobile = v.w < 768;
    ok(
      esMobile ? r.aside?.visible === false : r.aside?.visible === true,
      esMobile ? 'menu mobile CERRADO por defecto (aside oculto)' : `menu lateral visible (${r.aside?.w}px)`
    );

    // Screenshot del estado medido ANTES de tocar el drawer (el test de drawer navega y muta la
    // vista, asi que se captura primero, en un estado conocido).
    if (!abierto) {
      await p.screenshot({ path: `qa/screenshots/${v.nombre}-${v.w}.png`, fullPage: false });
    } else if (esMobile) {
      await p.screenshot({ path: `qa/screenshots/mobile-${v.w}-detalle-abierto.png`, fullPage: false });
    }

    if (esMobile) {
      // Estado del drawer (una lectura reutilizable). aria-expanded vive en la hamburguesa.
      const leerDrawer = () =>
        p.evaluate(() => {
          const a = document.querySelector('aside');
          const cs = getComputedStyle(a);
          const btn = document.querySelector('button[aria-label="Abrir o cerrar menu"]');
          return {
            display: cs.display,
            position: cs.position,
            rects: a.getClientRects().length,
            expanded: btn?.getAttribute('aria-expanded'),
            links: a.querySelectorAll('a').length,
            desborda: document.documentElement.scrollWidth > document.documentElement.clientWidth,
            mainW: document.querySelector('main')?.offsetWidth ?? 0,
          };
        });
      const mainCerrado = r.main; // ancho del <main> con el drawer cerrado (medido arriba)
      const hamburguesa = p.locator('button[aria-label="Abrir o cerrar menu"]');

      // 1) ABRIR con la hamburguesa.
      await hamburguesa.click();
      await p.waitForTimeout(150);
      const ab = await leerDrawer();
      ok(ab.display !== 'none', 'el drawer se ABRE al tocar la hamburguesa');
      ok(ab.expanded === 'true', 'aria-expanded="true" con el drawer abierto');
      ok(ab.links > 0, `el drawer abierto tiene ${ab.links} enlaces`);
      // H-1 (ASERCION DURA): overlay fuera del flujo -> el <main> NO cambia de ancho (ni se angosta ni
      // se ensancha, |dif| acotada en ambos sentidos) y la pagina no desborda a lo ancho.
      const TOL_MAIN = 1;
      ok(
        Math.abs(ab.mainW - mainCerrado) <= TOL_MAIN,
        `el <main> no cambia de ancho al abrir el drawer: ${ab.mainW}px abierto vs ${mainCerrado}px cerrado (|dif| <= ${TOL_MAIN}px)`
      );
      ok(!ab.desborda, 'con el drawer abierto la pagina NO desborda a lo ancho (scrollWidth === clientWidth)');
      ok(
        ab.position === 'fixed' || ab.position === 'absolute',
        `el drawer abierto es overlay fuera del flujo (position: ${ab.position})`
      );

      // SCREENSHOT con el drawer REALMENTE ABIERTO, antes de cerrarlo (una vez, con detalle cerrado).
      if (!abierto) {
        await p.screenshot({ path: `qa/screenshots/mobile-${v.w}-drawer-abierto.png`, fullPage: false });
      }

      // 2) CERRAR con el MISMO control visible: la hamburguesa sigue accesible porque el drawer se
      //    ancla al AREA DE CONTENIDO (no tapa el header). Es el punto exacto que fallaba antes.
      await hamburguesa.click();
      await p.waitForTimeout(150);
      const ce = await leerDrawer();
      ok(
        ce.display === 'none' && ce.rects === 0,
        'el drawer se CIERRA con el mismo control (display:none, sin geometria)'
      );
      ok(ce.expanded === 'false', 'aria-expanded="false" con el drawer cerrado');

      // 3) NAVEGAR tambien cierra: reabrir y clickear un enlace del menu.
      await hamburguesa.click();
      await p.waitForTimeout(120);
      await p.locator('aside a').first().click();
      await p.waitForTimeout(150);
      const nav = await leerDrawer();
      ok(
        nav.display === 'none' && nav.rects === 0,
        'al navegar, el drawer queda oculto y no interactuable (display:none, sin geometria)'
      );
      ok(nav.expanded === 'false', 'y aria-expanded vuelve a "false" tras navegar');
    } else {
      // Tablet/desktop: el aside es columna estatica de 256px. Tolerancia explicita por borde/subpixel.
      const TOL_ASIDE = 2;
      ok(
        r.aside != null && Math.abs((r.aside.w ?? 0) - 256) <= TOL_ASIDE,
        `aside lateral de 256px en ${v.nombre} (medido ${r.aside?.w}px, tolerancia ${TOL_ASIDE}px)`
      );
    }
    await p.close();
  }
}

// =============================================================================================
// H-2 -- GASTOS CONGELADOS: EXACTAMENTE UNA representacion por breakpoint (card en mobile, tabla en
// tablet/desktop), medida sobre el DOM productivo real. Medido aca, no contado de memoria en un .md.
//
// En cada viewport (mobile 375, tablet 768, desktop 1280):
//   1) se localiza la seccion "Gastos congelados";
//   2) EXCLUSIVIDAD (asercion dura): tablaVis !== cardsVis. En mobile: cards visibles y tabla NO
//      visible; en tablet/desktop: tabla visible y CERO cards visibles. Que ambas esten visibles a
//      la vez es una FALLA (antes se "priorizaban" las cards y eso ocultaba el defecto);
//   3) la representacion visible debe ser la ESPERADA por breakpoint (card/tabla);
//   4) CARDINALIDAD (mobile): la fuente de verdad de que gastos existen es la tabla (en el DOM aunque
//      este display:none). Se exige: cantidad de cards == cantidad de filas; conjunto de IDs de card
//      (data-qa-gasto-id) == conjunto de IDs de fila; sin faltantes; sin duplicados; una card por
//      id_gasto. Una mutacion que renderice solo el primer gasto FALLA. (m.n > 0 no alcanza.);
//   5) VACIO VERTICAL REAL por UNION de intervalos: se juntan los intervalos verticales de todos los
//      rectangulos de texto legibles, se ordenan, se fusionan SOLO los solapados/contiguos y se suma
//      la union. vacio = alto total - union. Un hueco grande entre dos lineas NO cuenta como
//      contenido (a diferencia de bot-top). Una card alta con un gran hueco FALLA;
//   6) veredicto: inutilizable si (alto >= ALTO_MIN Y vacio >= VACIO_MIN) -> asercion dura;
//   7) F20 / desborde: documentElement.scrollWidth === clientWidth SIEMPRE. Ademas, segun la
//      representacion: CARDS -> cada card queda completa dentro del viewport (izq y der); TABLA ->
//      NO se exige que las filas entren (la tabla puede ser mas ancha y desplazarse dentro de su
//      wrapper); se exige que el WRAPPER quede dentro del viewport y que el scroll horizontal
//      interno funcione (no tautologico);
//   8) screenshot de la representacion EFECTIVAMENTE MEDIDA en cada viewport.
// H-2 es ASERCION DURA (ok), no un hallazgo.
// =============================================================================================
{
  console.log('\n' + '='.repeat(92));
  console.log('H-2 -- Gastos congelados: 1 representacion por breakpoint, sin desperdicio (F20)');
  console.log('='.repeat(92));

  const ALTO_MIN = 120; // px: por debajo de esto una unidad no "ocupa pantalla" aunque este vacia
  const VACIO_MIN = 100; // px: desperdicio vertical concreto que vuelve la unidad inutilizable
  const TOL_VP = 1; // px de tolerancia para "no excede el viewport"

  for (const vp of [
    { nombre: 'mobile', w: 375, h: 812, mobile: true, esperado: 'card' },
    { nombre: 'tablet', w: 768, h: 1024, mobile: false, esperado: 'tabla' },
    { nombre: 'desktop', w: 1280, h: 900, mobile: false, esperado: 'tabla' },
  ]) {
    const p = await b.newPage({
      viewport: { width: vp.w, height: vp.h },
      ...(vp.mobile ? { hasTouch: true, isMobile: true } : {}),
    });
    await p.goto(BASE, { waitUntil: 'networkidle' });
    await p.waitForSelector('main');
    await p.selectOption('[data-qa-barra] select', 'F20');
    await p.waitForTimeout(200);
    await p.locator('main details').first().locator('summary').click();
    await p.waitForTimeout(300);

    const m = await p.evaluate(() => {
      const visible = (el) =>
        !!el &&
        el.getClientRects().length > 0 &&
        getComputedStyle(el).display !== 'none' &&
        getComputedStyle(el).visibility !== 'hidden';

      const h = [...document.querySelectorAll('main p')].find((e) =>
        /Gastos congelados/i.test(e.textContent ?? '')
      );
      const sec = h?.closest('section');
      if (!sec) return { rep: 'none', motivo: 'no se encontro la seccion Gastos congelados' };

      const tabla = sec.querySelector('table'); // en el DOM aunque en mobile este display:none
      const cardsEls = [...sec.querySelectorAll('[data-qa="gasto-card"]')].filter(visible);
      const tablaVis = visible(tabla);
      const cardsVis = cardsEls.length > 0;
      if (!tablaVis && !cardsVis)
        return { rep: 'none', motivo: 'no hay NI tabla NI cards de gastos VISIBLES', tablaVis, cardsVis };

      const vw = document.documentElement.clientWidth;
      const franja = (el) => {
        const r = el.getBoundingClientRect();
        return { left: Math.max(0, r.left), right: Math.min(vw, r.right) };
      };
      const overlapX = (r, fr) =>
        Math.max(0, Math.min(r.right, fr.right - 2) - Math.max(r.left, fr.left + 2));
      const legible = (r, fr) => {
        const vis = overlapX(r, fr);
        return vis >= 16 && r.width > 0 && vis / r.width >= 0.25;
      };
      // Mide una unidad: alto total, y contenido legible por UNION de intervalos verticales
      // fusionados (los huecos NO cuentan). Devuelve tambien el borde derecho (para "no excede vp").
      const medirBloque = (el, fr) => {
        const rect = el.getBoundingClientRect();
        const alto = Math.round(rect.height);
        const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
        const iv = [];
        for (let n = walker.nextNode(); n; n = walker.nextNode()) {
          if (!(n.textContent ?? '').trim()) continue;
          const rg = document.createRange();
          rg.selectNodeContents(n);
          for (const r of rg.getClientRects()) {
            if (!legible(r, fr)) continue;
            iv.push([r.top, r.bottom]);
          }
        }
        iv.sort((a, bb) => a[0] - bb[0]);
        let union = 0;
        let ct = null;
        let cb = null;
        for (const [t, btm] of iv) {
          if (ct === null) {
            ct = t;
            cb = btm;
            continue;
          }
          if (t <= cb) {
            // solapan o se tocan -> mismo bloque de contenido
            if (btm > cb) cb = btm;
          } else {
            // HUECO -> el intervalo previo cierra; el hueco es vacio
            union += cb - ct;
            ct = t;
            cb = btm;
          }
        }
        if (ct !== null) union += cb - ct;
        const altoContenido = Math.round(union);
        return {
          alto,
          altoContenido,
          vacio: alto - altoContenido,
          pct: alto > 0 ? Math.round(((alto - altoContenido) / alto) * 100) : 0,
          left: Math.round(rect.left),
          right: Math.round(rect.right),
        };
      };

      // IDs de las filas de la tabla (fuente de verdad; la tabla existe en el DOM en todo viewport).
      const idsFilas = tabla
        ? [...tabla.querySelectorAll('tbody tr')].map((tr) => {
            const t = (tr.querySelector('td')?.textContent ?? '').trim();
            const mm = t.match(/#(\d+)/);
            return mm ? Number(mm[1]) : null;
          })
        : [];

      let rep;
      let unidades;
      let idsCards = [];
      let wrapper = null;
      if (cardsVis) {
        rep = 'card';
        unidades = cardsEls.map((c) => medirBloque(c, franja(c)));
        idsCards = cardsEls.map((c) => Number(c.getAttribute('data-qa-gasto-id')));
      } else {
        rep = 'tabla';
        const sc = tabla.closest('.overflow-x-auto') ?? tabla.parentElement;
        const fr = franja(sc);
        unidades = [...tabla.querySelectorAll('tbody tr')].map((tr) => medirBloque(tr, fr));
        // WRAPPER (no las filas): la tabla PUEDE ser mas ancha que el area visible y desplazarse
        // DENTRO de su wrapper (comportamiento productivo de DataTable). Se mide el wrapper y el
        // scroll horizontal interno NO tautologico: asignar scrollLeft, ver que cambio, restaurar.
        const wr = sc.getBoundingClientRect();
        const cs = getComputedStyle(sc);
        const scrollWidth = sc.scrollWidth;
        const clientWidth = sc.clientWidth;
        const excede = scrollWidth > clientWidth + 1;
        let desplazable = null;
        let restaurado = null;
        if (excede) {
          const orig = sc.scrollLeft;
          sc.scrollLeft = orig + 40;
          desplazable = sc.scrollLeft !== orig;
          sc.scrollLeft = orig;
          restaurado = sc.scrollLeft === orig;
        }
        wrapper = {
          left: Math.round(wr.left),
          right: Math.round(wr.right),
          overflowX: cs.overflowX,
          scrollWidth,
          clientWidth,
          excede,
          desplazable,
          restaurado,
        };
      }
      return {
        rep,
        tablaVis,
        cardsVis,
        n: unidades.length,
        unidades,
        idsCards,
        idsFilas,
        wrapper,
        vw,
        pageScrollW: document.documentElement.scrollWidth,
        pageClientW: document.documentElement.clientWidth,
      };
    });

    console.log(`\n  ${vp.nombre} (${vp.w}px) -- representacion esperada: ${vp.esperado}`);

    // (2') fail-closed: nada visible que medir NUNCA es exito.
    if (m.rep === 'none') {
      ok(false, `H-2 @${vp.nombre}: ${m.motivo}`);
      await p.close();
      continue;
    }
    // (2) EXCLUSIVIDAD dura: exactamente una representacion visible.
    ok(
      m.tablaVis !== m.cardsVis,
      `H-2 @${vp.nombre}: exactamente UNA representacion visible (tablaVis=${m.tablaVis}, cardsVis=${m.cardsVis})`
    );
    // (3) la representacion visible es la esperada por breakpoint.
    ok(
      m.rep === vp.esperado,
      `la representacion visible en ${vp.nombre} es «${m.rep}» (esperada «${vp.esperado}»)`
    );
    // (5-basico) cero unidades = falla. Fail-closed limpio: si no hay unidades, NO seguir hacia el
    // reduce (m.unidades[0] seria undefined y romperia). Se corta este viewport.
    ok(
      m.n > 0,
      `hay ${m.n} ${m.rep === 'card' ? 'card(s)' : 'fila(s)'} de gasto (F20 trae gastos; cero = falla)`
    );
    if (m.n === 0) {
      await p.close();
      continue;
    }

    // (7) DESBORDE. La PAGINA nunca debe desbordar a lo ancho (ambas representaciones).
    ok(
      m.pageScrollW === m.pageClientW,
      `sin scroll horizontal de pagina en ${vp.nombre} (documentElement.scrollWidth ${m.pageScrollW} === clientWidth ${m.pageClientW})`
    );
    if (m.rep === 'card') {
      // CARDS: cada card queda COMPLETA dentro del viewport (izquierda Y derecha). Una card no se
      // desplaza; si sobresale a izquierda o derecha, es un bug.
      const fuera = m.unidades.filter((u) => u.left < -TOL_VP || u.right > m.vw + TOL_VP).length;
      ok(
        fuera === 0,
        `ninguna card excede el viewport a lo ancho en ${vp.nombre} (todas dentro de [0, ${m.vw}]px${fuera ? `, ${fuera} fuera` : ''})`
      );
    } else {
      // TABLA: DataTable esta disenada para que la tabla pueda ser MAS ANCHA que el area visible y
      // se desplace DENTRO de su wrapper overflow-x-auto. Por eso NO se exige que las filas o la
      // tabla terminen dentro del viewport (en tablet 768 la tabla de 9 columnas excede
      // legitimamente). Se exige: el WRAPPER queda dentro del viewport; su overflowX es auto|scroll;
      // y si la tabla excede el wrapper, el scroll horizontal INTERNO funciona (no tautologico: se
      // asigno scrollLeft, cambio, y se restauro al valor original).
      const w = m.wrapper;
      ok(
        w != null && w.left >= -TOL_VP && w.right <= m.vw + TOL_VP,
        `el wrapper overflow-x-auto queda dentro del viewport en ${vp.nombre} (left ${w?.left}, right ${w?.right}, vw ${m.vw})`
      );
      ok(
        w.overflowX === 'auto' || w.overflowX === 'scroll',
        `el wrapper tiene overflow-x desplazable en ${vp.nombre} (overflowX: ${w.overflowX})`
      );
      if (w.excede) {
        ok(
          w.desplazable === true,
          `la tabla excede el wrapper y el scroll horizontal INTERNO funciona en ${vp.nombre} (scrollWidth ${w.scrollWidth} > clientWidth ${w.clientWidth}; scrollLeft cambia)`
        );
        ok(
          w.restaurado === true,
          `y la medicion restauro el scrollLeft en ${vp.nombre} (no deja la tabla movida)`
        );
        console.log(`    tabla ${w.scrollWidth}px se desplaza dentro del wrapper ${w.clientWidth}px -> scroll interno OK (no tautologico)`);
      } else {
        console.log(`    tabla ${w.scrollWidth}px entra en el wrapper ${w.clientWidth}px (no requiere scroll interno)`);
      }
    }

    // (4) CARDINALIDAD en mobile: cards == filas fuente, mismos IDs, sin faltantes ni duplicados.
    if (m.rep === 'card') {
      const filas = m.idsFilas.filter((x) => x != null);
      const cards = m.idsCards.filter((x) => x != null);
      const setF = new Set(filas);
      const setC = new Set(cards);
      const faltan = [...setF].filter((x) => !setC.has(x));
      const sobran = [...setC].filter((x) => !setF.has(x));
      const dup = cards.length !== setC.size;
      console.log(`    fuente (filas de tabla): [${[...setF].join(', ')}]  |  cards: [${cards.join(', ')}]`);
      ok(
        cards.length === filas.length && faltan.length === 0 && sobran.length === 0 && !dup && setF.size > 0,
        `una card por gasto: ${cards.length} cards == ${filas.length} filas, mismos IDs, sin faltantes` +
          `${faltan.length ? ` (faltan ${faltan.join(',')})` : ''}${sobran.length ? ` (sobran ${sobran.join(',')})` : ''}` +
          `${dup ? ' (HAY DUPLICADOS)' : ''}`
      );
    }

    console.log('    unidad | altura | contenido legible (union) | ESPACIO VERTICAL VACIO');
    console.log('    ' + '-'.repeat(66));
    for (const [i, f] of m.unidades.entries()) {
      console.log(
        `    #${String(i + 1).padStart(3)} | ${String(f.alto).padStart(5)}px| ${String(f.altoContenido).padStart(20)}px| ` +
          `${String(f.vacio).padStart(9)}px (${String(f.pct).padStart(2)}%)`
      );
    }

    // (6) VEREDICTO por la unidad mas desperdiciada, umbrales EXPLICITOS, vacio por UNION.
    const masVacia = m.unidades.reduce((a, f) => (f.vacio > a.vacio ? f : a), m.unidades[0]);
    const idx = m.unidades.indexOf(masVacia) + 1;
    const inutilizable = masVacia.alto >= ALTO_MIN && masVacia.vacio >= VACIO_MIN;
    console.log('');
    console.log(`    umbrales: alto >= ${ALTO_MIN}px  Y  desperdicio vertical (union) >= ${VACIO_MIN}px`);
    console.log(
      `    unidad mas desperdiciada #${idx}: alto ${masVacia.alto}px (${masVacia.alto >= ALTO_MIN ? 'alta' : 'baja'}), ` +
        `desperdicio ${masVacia.vacio}px (${masVacia.vacio >= VACIO_MIN ? 'supera' : 'no supera'} el umbral)\n`
    );

    ok(
      !inutilizable,
      `H-2 @${vp.nombre}: ${m.rep === 'card' ? 'cards' : 'filas'} compactas -- la unidad mas ` +
        `desperdiciada (#${idx}) mide ${masVacia.alto}px con ${masVacia.altoContenido}px legibles (union) -> ` +
        `${masVacia.vacio}px vacios (${masVacia.pct}%) [umbral alto>=${ALTO_MIN} Y vacio>=${VACIO_MIN}]`
    );

    // (8) screenshot de la representacion MEDIDA (se trae la seccion al viewport antes).
    await p.evaluate(() => {
      const h = [...document.querySelectorAll('main p')].find((e) =>
        /Gastos congelados/i.test(e.textContent ?? '')
      );
      h?.closest('section')?.scrollIntoView({ block: 'center' });
    });
    await p.waitForTimeout(200);
    await p.screenshot({ path: `qa/screenshots/H2-gastos-${vp.nombre}-${vp.w}.png` });
    console.log(`    screenshot -> qa/screenshots/H2-gastos-${vp.nombre}-${vp.w}.png (representacion medida: ${m.rep})`);
    await p.close();
  }
}
await b.close();
console.log(fallos === 0 ? '\n  RESPONSIVE OK (aserciones duras)' : `\n  ${fallos} FALLAS`);
if (hallazgos.length) {
  console.log(`\n  ${hallazgos.length} HALLAZGO(S) ABIERTO(S) -- medidos, pendientes de decision:`);
  for (const h of hallazgos) console.log(`    ${h.msg}`);
} else {
  console.log('\n  0 HALLAZGO(S) ABIERTO(S)');
}

// GATE DE HALLAZGOS. Tras SB-UI-6.1, H-1 y H-2 pasaron a ASERCIONES DURAS (arriba, cuentan en
// `fallos`): el drawer es un overlay que NO comprime el <main>, y Gastos congelados usa card
// compacta en mobile. Por eso el set de hallazgos abiertos esperado es VACIO: {}. La maquinaria de
// hallazgos NO se elimina: se conserva como tripwire para que cualquier hallazgo NUEVO e inesperado
// (o un medidor que vuelva a registrar) rompa el gate por "SOBRAN". No se sacan H-1/H-2 del gate sin
// reemplazo: se reemplazan por comprobaciones duras y se exige explicitamente {}.
const ESPERADOS = [];
const ids = hallazgos.map((h) => h.id).sort();
const setOk = ids.length === ESPERADOS.length && ESPERADOS.every((e, i) => ids[i] === e);

if (!setOk) {
  const sobran = ids.filter((i) => !ESPERADOS.includes(i));
  console.log('\n  GATE DE HALLAZGOS -- FALLA: se esperaba el set vacio {}.');
  if (sobran.length) console.log(`    SOBRAN: ${sobran.join(', ')} -> hallazgo no esperado, revisar antes de seguir`);
} else {
  console.log('\n  gate de hallazgos OK -- sin hallazgos abiertos ({}).');
}

console.log('');
process.exit(fallos === 0 && setOk ? 0 : 1);
