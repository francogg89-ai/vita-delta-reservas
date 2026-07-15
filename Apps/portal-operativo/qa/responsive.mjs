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
 * HALLAZGO CONOCIDO: bug REAL, medido, pendiente de decision de Franco. No cuenta como falla de la
 * suite (si no, la suite deja de servir de gate de regresion), pero se lista SIEMPRE y bien fuerte.
 * Cuando se decida el fix, esto pasa a ser un `ok()` duro.
 */
const hallazgo = (c, id, m) => {
  console.log(`      ${c ? 'ok   ' : '·HALL'} ${m}`);
  // Se deduplica por ID: el mismo hallazgo (p.ej. H-1) se evalua en varios viewports, pero es UN
  // solo hallazgo. Antes se empujaba una entrada por evaluacion y el conteo daba "3 hallazgos"
  // aunque solo se imprimian H-1 y H-2. Se guarda el primer mensaje visto para cada ID.
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

// =============================================================================================
// H-2 -- FILAS INUTILIZABLES EN MOBILE. Medido aca, no contado de memoria en un .md.
// Selecciona F20 (peor caso: gastos con TODOS los opcionales), abre el detalle fino, localiza
// Gastos congelados y mide alto de fila, ancho total/visible y % oculto. Guarda screenshot.
// =============================================================================================
{
  console.log('\n' + '='.repeat(92));
  console.log('H-2 -- ¿las filas densas inutilizan la tabla en mobile? (F20, 375px)');
  console.log('='.repeat(92));

  const p = await b.newPage({ viewport: { width: 375, height: 812 }, hasTouch: true, isMobile: true });
  await p.goto(BASE, { waitUntil: 'networkidle' });
  await p.waitForSelector('main');
  await p.selectOption('[data-qa-barra] select', 'F20');
  await p.waitForTimeout(200);
  await p.locator('main details').first().locator('summary').click();
  await p.waitForTimeout(300);

  const m = await p.evaluate(() => {
    const h = [...document.querySelectorAll('main p')].find((e) => /Gastos congelados/i.test(e.textContent ?? ''));
    const tabla = h?.closest('section')?.querySelector('table');
    if (!tabla) return null;
    const sc = tabla.closest('.overflow-x-auto');
    const sr = sc.getBoundingClientRect();

    // Solapamiento horizontal UTIL de un rectangulo con la franja visible del scroller. El filtro
    // anterior (`rect.right > sr.left+2 && rect.left < sr.right-2`) aceptaba cualquier asomo minimo:
    // si la 4a celda entraba unos pocos pixeles, TODAS sus lineas contaban como visibles y se sumaba
    // su altura completa. Por eso informaba 17px vacios donde la captura muestra un bloque blanco
    // enorme.
    const overlapX = (r) => Math.max(0, Math.min(r.right, sr.right - 2) - Math.max(r.left, sr.left + 2));
    // Una linea es LEGIBLE si asoma al menos 16px de ancho Y al menos el 25% de su propio ancho. Un
    // sliver marginal (pocos pixeles de una celda de 160px) no habilita a contar toda esa linea.
    const legible = (r) => {
      const vis = overlapX(r);
      return vis >= 16 && r.width > 0 && vis / r.width >= 0.25;
    };

    const filas = [...tabla.querySelectorAll('tbody tr')].map((tr) => {
      const tds = [...tr.querySelectorAll('td')];
      const alto = Math.round(tr.getBoundingClientRect().height);

      // columnas cuyo contenido asoma LEGIBLEMENTE en la franja visible
      let columnasVisibles = 0;
      let altoContenido = 0;
      for (const td of tds) {
        const rg = document.createRange();
        rg.selectNodeContents(td);
        const rects = [...rg.getClientRects()].filter(legible);
        if (rects.length === 0) continue; // esta celda no aporta una sola linea legible
        columnasVisibles++;
        const h = Math.round(Math.max(...rects.map((r) => r.bottom)) - Math.min(...rects.map((r) => r.top)));
        if (h > altoContenido) altoContenido = h; // la fila es tan alta como su celda visible mas alta
      }
      return {
        alto,
        altoContenido,
        vacio: alto - altoContenido,
        pct: alto > 0 ? Math.round(((alto - altoContenido) / alto) * 100) : 0,
        columnasVisibles,
        total: tds.length,
      };
    });
    return {
      anchoTabla: tabla.scrollWidth,
      anchoVisible: sc.clientWidth,
      oculto: tabla.scrollWidth - sc.clientWidth,
      filas,
    };
  });

  if (!m) {
    ok(false, 'H-2: no se encontro la tabla Gastos congelados');
  } else {
    // El % horizontal oculto se informa APARTE: por si solo no declara "fila inutilizable".
    const pctOculto = Math.round((m.oculto / m.anchoTabla) * 100);
    console.log(`\n    tabla ${m.anchoTabla}px | visible ${m.anchoVisible}px | oculto horizontalmente ${m.oculto}px (${pctOculto}%)`);
    console.log('    (el % horizontal se informa aparte; H-2 se decide por el desperdicio VERTICAL)\n');
    console.log('    fila | altura | contenido visible | ESPACIO VERTICAL VACIO | columnas visibles');
    console.log('    ' + '-'.repeat(70));
    for (const [i, f] of m.filas.entries()) {
      console.log(
        `    #${i + 1}   | ${String(f.alto).padStart(5)}px| ${String(f.altoContenido).padStart(14)}px| ` +
          `${String(f.vacio).padStart(9)}px (${String(f.pct).padStart(2)}%) | ${f.columnasVisibles} de ${f.total}`
      );
    }

    // Tres criterios, informados por separado. NO se elige "la de mayor proporcion": una fila baja
    // puede ser 90% vacia y aun asi ser el caso menos grave. Lo que decide es el desperdicio
    // VERTICAL concreto (pixeles), no la proporcion.
    const masAlta = m.filas.reduce((a, f) => (f.alto > a.alto ? f : a), m.filas[0]);
    const masVacia = m.filas.reduce((a, f) => (f.vacio > a.vacio ? f : a), m.filas[0]);
    const mayorPct = m.filas.reduce((a, f) => (f.pct > a.pct ? f : a), m.filas[0]);
    const idx = (f) => m.filas.indexOf(f) + 1;
    console.log('');
    console.log(`    fila mas alta:         #${idx(masAlta)}  (${masAlta.alto}px, ${masAlta.vacio}px vacios, ${masAlta.pct}%)`);
    console.log(`    fila con mas px vacios: #${idx(masVacia)}  (${masVacia.vacio}px vacios de ${masVacia.alto}px, ${masVacia.pct}%)`);
    console.log(`    fila con mayor % vacio: #${idx(mayorPct)}  (${mayorPct.pct}%, ${mayorPct.vacio}px de ${mayorPct.alto}px)`);
    console.log('');

    // VEREDICTO. Dos umbrales EXPLICITOS, y NO se decide solo por porcentaje:
    //   - la fila mas desperdiciada tiene que ser suficientemente ALTA (si es baja, aunque sea 90%
    //     vacia, no inutiliza nada);
    //   - y su desperdicio VERTICAL en PIXELES tiene que superar el umbral.
    const ALTO_MIN = 120; // px: por debajo de esto una fila no "ocupa pantalla" aunque este vacia
    const VACIO_MIN = 100; // px: desperdicio vertical concreto que vuelve la fila inutilizable
    const inutilizable = masVacia.alto >= ALTO_MIN && masVacia.vacio >= VACIO_MIN;

    console.log(`    umbrales: alto >= ${ALTO_MIN}px  Y  desperdicio vertical >= ${VACIO_MIN}px  (no se decide por %)`);
    console.log(
      `    fila #${idx(masVacia)}: alto ${masVacia.alto}px (${masVacia.alto >= ALTO_MIN ? 'OK' : 'baja'}), ` +
        `desperdicio ${masVacia.vacio}px (${masVacia.vacio >= VACIO_MIN ? 'supera' : 'no supera'} el umbral)\n`
    );

    // `hallazgo(cond, ...)` imprime `ok <msg>` cuando cond es true. Por eso el mensaje que se le pasa
    // describe el ESTADO BUENO (filas compactas), y el estado roto se reporta aparte con su propio
    // texto. Antes se le pasaba "filas inutilizables..." con la condicion invertida: cuando H-2 NO
    // se detectaba imprimia "ok filas inutilizables", que es contradictorio.
    if (inutilizable) {
      // estado ROTO: se registra el hallazgo con la descripcion del problema.
      hallazgo(
        false,
        'H-2',
        `filas inutilizables en mobile: la fila mas desperdiciada (#${idx(masVacia)}) mide ${masVacia.alto}px ` +
          `con solo ${masVacia.altoContenido}px de contenido legible -> ${masVacia.vacio}px verticales vacios (${masVacia.pct}%), ` +
          `${masVacia.columnasVisibles} de ${masVacia.total} columnas legibles; ademas ${pctOculto}% de la tabla oculto a lo ancho`
      );
    } else {
      // estado BUENO: el mensaje positivo describe filas compactas, no el problema.
      hallazgo(
        true,
        'H-2',
        `filas compactas en mobile: la fila mas desperdiciada (#${idx(masVacia)}) desperdicia solo ${masVacia.vacio}px ` +
          `verticales (umbral ${VACIO_MIN}px)`
      );
    }

    // scrollIntoView ANTES de la captura: sin esto, la tabla que se pretende documentar puede estar
    // fuera del viewport y la imagen no muestra nada de lo que se acaba de medir.
    await p.evaluate(() => {
      const h = [...document.querySelectorAll('main p')].find((e) => /Gastos congelados/i.test(e.textContent ?? ''));
      h?.closest('section')?.scrollIntoView({ block: 'center' });
    });
    await p.waitForTimeout(200);
    await p.screenshot({ path: 'qa/screenshots/H2-gastos-densos-375.png' });
    console.log('    screenshot -> qa/screenshots/H2-gastos-densos-375.png (con la tabla en el viewport)');
  }
  await p.close();
}

await b.close();
console.log(fallos === 0 ? '\n  RESPONSIVE OK (aserciones duras)' : `\n  ${fallos} FALLAS`);
if (hallazgos.length) {
  console.log(`\n  ${hallazgos.length} HALLAZGO(S) ABIERTO(S) -- medidos, pendientes de decision:`);
  for (const h of hallazgos) console.log(`    ${h.msg}`);
}

// GATE DE HALLAZGOS. H-1 y H-2 son bugs CONOCIDOS y medibles (drawer que empuja, filas
// inutilizables en F20/375). Que la suite los siga detectando es parte de su trabajo: si dejan de
// aparecer, o el medidor se rompio (como el falso negativo de H-2 que motivo SB-UI-6-FIX3), o
// alguien "arreglo" el sintoma sin pasar por el sub-bloque productivo. En cualquier caso hay que
// mirar. Se exige EXACTAMENTE el set {H-1, H-2}: ni menos (regresion del harness) ni mas (apareceria
// algo no documentado que hay que revisar antes de seguir).
const ESPERADOS = ['H-1', 'H-2'];
const ids = hallazgos.map((h) => h.id).sort();
const setOk = ids.length === ESPERADOS.length && ESPERADOS.every((e, i) => ids[i] === e);

if (!setOk) {
  const faltan = ESPERADOS.filter((e) => !ids.includes(e));
  const sobran = ids.filter((i) => !ESPERADOS.includes(i));
  console.log('\n  GATE DE HALLAZGOS -- FALLA: se esperaba exactamente {H-1, H-2}.');
  if (faltan.length) console.log(`    FALTAN: ${faltan.join(', ')} -> el medidor dejo de detectarlos (revisar el harness o si se "arreglo" el sintoma)`);
  if (sobran.length) console.log(`    SOBRAN: ${sobran.join(', ')} -> hallazgo no documentado, revisar antes de seguir`);
} else {
  console.log('\n  gate de hallazgos OK -- exactamente {H-1, H-2}, ambos medidos.');
}

console.log('');
process.exit(fallos === 0 && setOk ? 0 : 1);
