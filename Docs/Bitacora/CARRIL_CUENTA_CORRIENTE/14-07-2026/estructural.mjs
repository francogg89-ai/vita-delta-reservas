// =============================================================================================
// SB-UI-6-FIX -- Punto 3, parte B: el CONTENEDOR REAL.
//
// Las reglas que viven en `HistoricoCuentaCorriente` -- token de peticion, anti-doble-request y
// `enabled` de los hooks -- NO se pueden probar con `renderToStaticMarkup`: viven en `useEffect`
// y en callbacks, que en SSR no corren. Probar `clasificarFoto` y decir que estan cubiertas seria
// mentir (fue exactamente el error de SB-UI-6).
//
// Asi que se montan DE VERDAD, en Chromium, contra el harness en modo `?contenedor=1`:
//
//   HistoricoCuentaCorriente REAL   <- token de peticion, anti-doble-request, enabled
//   useAction REAL                  <- reqId, cleanup de unmount, descarte de respuestas viejas
//   callPortal REAL                 <- envelope ok/error, PortalApiError
//   window.fetch                    <- LO UNICO falso (stubs/red.ts)
//
// Stubbear `useAction` habria tirado a la basura justamente la logica a probar.
//
//   npm run qa            (en una terminal)
//   npm run qa:estructural (en otra)
// =============================================================================================

const BASE = process.env.QA_URL ?? 'http://localhost:5173';
const URL_CONTENEDOR = `${BASE}/?contenedor=1`;

let chromium;
try {
  ({ chromium } = await import('playwright'));
} catch {
  console.error('\n  Falta playwright.  npx playwright install chromium\n');
  process.exit(2);
}

let fallos = 0;
const ok = (c, m) => {
  console.log(`    ${c ? 'ok   ' : 'FALLA'} ${m}`);
  if (!c) fallos++;
};
const caso = (t) => console.log(`\n  ${t}`);
/** ICU (es-AR) mete un NBSP entre "$" y el numero. Sin normalizar, `includes('$ 1.000')` falla. */
const texto = async (p) => (await p.locator('main').textContent()).replace(/\u00a0/g, ' ');

const A30 = 'cuenta_corriente.historico';
const A31 = 'cuenta_corriente.historico_acumulados';

const llamadas = (p, action) =>
  p.evaluate((a) => window.__QA_RED__.llamadas.filter((l) => l.action === a), action);
const reset = (p, cfg = {}) =>
  p.evaluate((c) => {
    Object.assign(window.__QA_RED__, c);
    window.__QA_RED__.llamadas = [];
  }, cfg);
/** Cada respuesta se resuelve AL RECIBIR la peticion, no despues del await. */
const R = (fixture, latencia = 0, falla = false) => ({ fixture, latencia, falla });

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

console.log('\n' + '='.repeat(92));
console.log('CONTENEDOR REAL -- HistoricoCuentaCorriente + useAction + callPortal (solo fetch stubbeado)');
console.log('='.repeat(92));

// ---------------------------------------------------------------------------------------------
caso('F1 · `enabled` de los hooks: A30 NO sale mientras A31 esta en vuelo');
// ---------------------------------------------------------------------------------------------
{
  // La especificacion real (verificada contra el codigo, no supuesta): `enabled: ambas && mesApplied
  // !== null`, y `mesApplied` sale del token de peticion, que arranca en null. Cuando A31 responde,
  // el contenedor AUTO-APLICA el mes por defecto -> recien ahi sale A30. O sea: el `enabled` protege
  // la ventana en que todavia no se sabe cual es el piso.
  //
  // OJO con StrictMode: en DEV React monta, desmonta y remonta, asi que los efectos corren DOS veces
  // y A31 sale x2. En el build de produccion sale x1. No es un bug: es dev.
  const p = await b.newPage({ viewport: { width: 1280, height: 900 } });
  await p.addInitScript(() => {
    window.__QA_PRECONF__ = { a31: { fixture: 'F10', latencia: 800, falla: false } };
  });
  await p.goto(URL_CONTENEDOR);
  await p.waitForSelector('main');
  await p.waitForTimeout(250); // A31 sigue en vuelo

  const enVuelo30 = await llamadas(p, A30);
  const enVuelo31 = await llamadas(p, A31);
  ok(enVuelo31.length >= 1, `A31 se pide al montar (${enVuelo31.length}; x2 por StrictMode en dev, x1 en produccion)`);
  ok(enVuelo30.length === 0, `A30 NO sale mientras A31 esta en vuelo -- \`enabled:false\` (${enVuelo30.length} llamadas)`);
  ok(
    (await p.locator('main').textContent()).includes('Cargando acumulados'),
    'y la pantalla lo dice: "Cargando acumulados..."'
  );

  await p.waitForTimeout(1000); // A31 responde
  const despues30 = await llamadas(p, A30);
  ok(despues30.length === 1, `cuando A31 responde, el mes por defecto se auto-aplica y A30 sale UNA vez (${despues30.length})`);
  ok(
    despues30[0]?.payload?.mes === '2026-07-01',
    `y el payload lleva el mes por defecto: ${JSON.stringify(despues30[0]?.payload)}`
  );
  ok(
    (await p.locator('main').textContent()).includes('Cabecera de la foto'),
    'y la foto se muestra sin que el socio tenga que tocar nada'
  );
  await p.close();
}

// ---------------------------------------------------------------------------------------------
caso('F2 · ANTI-DOBLE-REQUEST: el boton se deshabilita durante la peticion');
// ---------------------------------------------------------------------------------------------
{
  const p = await b.newPage({ viewport: { width: 1280, height: 900 } });
  await p.goto(URL_CONTENEDOR, { waitUntil: 'networkidle' });
  await p.waitForSelector('main');
  await reset(p, { a30: R('F1', 600) });

  const boton = p.locator('button', { hasText: /Consultar|Consultando/ }).first();
  await boton.click();
  await p.waitForTimeout(100);

  const desactivado = await boton.isDisabled();
  ok(desactivado, 'con la peticion en vuelo el boton queda DESHABILITADO');
  ok((await boton.textContent()).includes('Consultando'), 'y avisa "Consultando..."');

  // martilleo: 5 clicks mientras esta en vuelo
  for (let i = 0; i < 5; i++) await boton.click({ force: true }).catch(() => {});
  await p.waitForTimeout(900);

  const a30 = await llamadas(p, A30);
  ok(a30.length === 1, `5 clicks durante la peticion -> UNA sola llamada a A30 (${a30.length})`);
  ok(!(await boton.isDisabled()), 'al llegar la respuesta el boton se vuelve a habilitar');
  await p.close();
}

// ---------------------------------------------------------------------------------------------
caso('F3 · CLEANUP de StrictMode/unmount: la respuesta de una instancia MUERTA no se aplica');
// ---------------------------------------------------------------------------------------------
{
  // ESTE CASO NO PRUEBA `reqId`. Lo probaba de mentira hasta SB-UI-6-FIX.
  //
  // StrictMode monta, DESMONTA y REMONTA. Las dos peticiones A31 que salen pertenecen a DOS
  // INSTANCIAS distintas del hook. Cada instancia tiene su PROPIO `reqId` (es un `useRef`, no se
  // comparte), asi que `myId !== reqId.current` ni se entera: lo que descarta la respuesta de la
  // instancia muerta es el `activo = false` de SU cleanup.
  //
  // Lo que se prueba aca, entonces, es el CLEANUP. El `reqId` se prueba en F7, en una MISMA
  // instancia, y el token del contenedor en F1/F8.
  const p = await b.newPage({ viewport: { width: 1280, height: 900 } });
  await p.addInitScript(() => {
    window.__QA_PRECONF__ = { a31: { fixture: 'F10', latencia: 500, falla: false } };
  });
  await p.goto(URL_CONTENEDOR);
  await p.waitForSelector('main');
  await p.waitForTimeout(1400);

  const a31 = await llamadas(p, A31);
  ok(a31.length >= 2, `${a31.length} peticiones A31 en vuelo a la vez (StrictMode + 500ms de latencia)`);

  const txt = await texto(p);
  ok(txt.includes('Totales acumulados'), 'la pantalla quedo asentada con la respuesta buena');
  ok(txt.includes('$ 5.000.000,00'), 'y con las cifras correctas de F10');
  ok(!txt.includes('Cargando acumulados'), 'ninguna peticion quedo colgada');
  ok(!/respuesta histórica inconsistente/i.test(txt), 'ni una respuesta huerfana provoco una inconsistencia falsa');
  await p.close();
}

// ---------------------------------------------------------------------------------------------
caso('F7 · useAction.reqId: descarte OUT-OF-ORDER en UNA MISMA instancia');
// ---------------------------------------------------------------------------------------------
{
  // Host `?host=requid`: UNA sola instancia de `useAction`, SIN StrictMode (si no, el remount crea
  // una segunda instancia y el cleanup tapa el escenario). Dos corridas del efecto en esa misma
  // instancia, con fixtures DISTINGUIBLES:
  //
  //   request 1 -> F2 (detalle_motivo: 'foto_pre_extension')  600ms   <- VIEJA, llega TARDE
  //     refetch() en pleno vuelo
  //   request 2 -> F1 (detalle_motivo: null)                    50ms   <- NUEVA, llega ANTES
  //
  // Si la vieja pisara a la nueva, al final se veria 'foto_pre_extension'.
  //
  // OJO CON LO QUE ESTO PRUEBA: prueba el DESCARTE, no que lo haga `reqId`. `npm run qa:mutacion`
  // demuestra que `!activo` y `myId !== reqId.current` son REDUNDANTES entre si -- cualquiera de
  // las dos alcanza; solo borrando LAS DOS la respuesta vieja pisa a la nueva.
  const p = await b.newPage({ viewport: { width: 900, height: 600 } });
  await p.addInitScript(() => {
    window.__QA_PRECONF__ = {
      colaA30: [
        { fixture: 'F2', latencia: 600, falla: false },
        { fixture: 'F1', latencia: 50, falla: false },
      ],
    };
  });
  await p.goto(`${BASE}/?host=requid`);
  await p.waitForSelector('[data-qa-host="requid"]');

  await p.waitForTimeout(150); // la request 1 (600ms) sigue en vuelo
  await p.evaluate(() => window.__QA_REFETCH__?.());
  await p.waitForTimeout(1200); // vuelven las DOS

  const servidos = await p.evaluate(() => window.__QA_RED__.llamadas.map((l) => l.sirvio.fixture));
  const motivo = await p.locator('[data-qa="motivo"]').textContent();

  ok(servidos.length === 2, `salieron exactamente 2 peticiones desde UNA instancia: ${JSON.stringify(servidos)}`);
  ok(servidos[0] === 'F2' && servidos[1] === 'F1', 'la 1a se sirvio con el fixture anomalo (600ms) y la 2a con el normal (50ms)');
  ok(motivo === 'null', `la respuesta VIEJA (F2, 'foto_pre_extension') NO piso a la nueva -- quedo "${motivo}"`);
  await p.close();
}

// ---------------------------------------------------------------------------------------------
caso('F4 · el par (loading:true, fotoPendiente:false) es INALCANZABLE desde el contenedor');
// ---------------------------------------------------------------------------------------------
{
  // En la vista pura ese par no muestra ni "Cargando" ni la foto. Habria sido un hueco... si el
  // contenedor pudiera producirlo. Se comprueba que NUNCA lo produce: mientras hay una peticion
  // A30 en vuelo, la vista SIEMPRE muestra "Cargando la foto".
  const p = await b.newPage({ viewport: { width: 1280, height: 900 } });
  await p.goto(URL_CONTENEDOR, { waitUntil: 'networkidle' });
  await p.waitForSelector('main');
  await reset(p, { a30: R('F1', 700) });

  await p.locator('button', { hasText: /Consultar|Consultando/ }).first().click();

  // se muestrea la pantalla durante todo el vuelo
  let huecos = 0;
  let muestras = 0;
  for (let i = 0; i < 12; i++) {
    await p.waitForTimeout(50);
    const t = await p.locator('main').textContent();
    const enVuelo = await p.locator('button', { hasText: 'Consultando' }).count();
    if (enVuelo > 0) {
      muestras++;
      if (!t.includes('Cargando la foto')) huecos++;
    }
  }
  ok(muestras > 0, `se muestreo la pantalla ${muestras} veces con la peticion en vuelo`);
  ok(huecos === 0, `en NINGUNA muestra la seccion Foto quedo en blanco (${huecos} huecos)`);
  await p.waitForTimeout(800);
  ok((await p.locator('main').textContent()).includes('Cabecera de la foto'), 'y al volver, la foto se muestra');
  await p.close();
}

// ---------------------------------------------------------------------------------------------
caso('F5 · RETRY: el boton Reintentar dispara una peticion NUEVA de verdad');
// ---------------------------------------------------------------------------------------------
{
  const p = await b.newPage({ viewport: { width: 1280, height: 900 } });
  await p.goto(URL_CONTENEDOR, { waitUntil: 'networkidle' });
  await p.waitForSelector('main');

  // A31 falla -> ErrorCard con Reintentar.
  // OJO: un `location.reload()` vuelve a correr main.tsx y REINSTALA la red falsa, perdiendo el
  // flag. `addInitScript` corre ANTES del bundle en cada navegacion: por eso la preconfiguracion
  // se pasa por ahi y `instalarRedFalsa` la respeta.
  await p.addInitScript(() => {
    window.__QA_PRECONF__ = { a31: { fixture: 'F10', latencia: 0, falla: true } };
  });
  await p.goto(URL_CONTENEDOR);
  await p.waitForSelector('main');
  await p.waitForTimeout(400);

  const txt1 = await p.locator('main').textContent();
  ok(/Reintentar/.test(txt1), 'A31 caida -> aparece Reintentar');

  await reset(p, { a31: R('F10') }); // el servidor "se recupera"
  const antes = (await llamadas(p, A31)).length;
  await p.locator('button', { hasText: 'Reintentar' }).first().click();
  await p.waitForTimeout(400);
  const despues = (await llamadas(p, A31)).length;

  ok(despues === antes + 1, `Reintentar disparo UNA peticion nueva (${antes} -> ${despues})`);
  const txt2 = await p.locator('main').textContent();
  ok(txt2.includes('Totales acumulados'), 'y al recuperarse, los acumulados se muestran');
  ok(!/Reintentar/.test(txt2.split('Cabecera')[0] ?? ''), 'el ErrorCard de A31 desaparece');
  await p.close();
}

// ---------------------------------------------------------------------------------------------
caso('F6 · MODO DEGRADADO: con A31 caida el selector SIGUE usable (piso local)');
// ---------------------------------------------------------------------------------------------
{
  const p = await b.newPage({ viewport: { width: 1280, height: 900 } });
  await p.goto(URL_CONTENEDOR, { waitUntil: 'networkidle' });
  await p.waitForSelector('main');
  await p.addInitScript(() => {
    window.__QA_PRECONF__ = { a31: { fixture: 'F10', latencia: 0, falla: true } };
  });
  await p.goto(URL_CONTENEDOR);
  await p.waitForSelector('main');
  await p.waitForTimeout(400);

  const sel = p.locator('#mes-historico');
  ok((await sel.count()) === 1, 'el selector existe pese a la caida de A31');
  ok(!(await sel.isDisabled()), 'y NO esta deshabilitado: el plan sale del fallback local');
  const opciones = await sel.locator('option').count();
  ok(opciones > 0, `el selector tiene ${opciones} opciones (piso = FLOOR_CONTABLE)`);

  // y la foto se puede consultar igual
  await p.locator('button', { hasText: /Consultar|Consultando/ }).first().click();
  await p.waitForTimeout(400);
  ok(
    (await p.locator('main').textContent()).includes('Cabecera de la foto'),
    'A30 funciona igual con A31 caida: las dos lecturas son independientes'
  );
  await p.close();
}

// ---------------------------------------------------------------------------------------------
caso('F8 · FAIL-CLOSED en el CONTENEDOR REAL: se le saca la accion a la sesion');
// ---------------------------------------------------------------------------------------------
{
  // Renderizar `HistoricoVista` con `faltaAccion:true` es asumir la conclusion: se le esta DICIENDO
  // a la vista que falta el permiso. La pregunta real es si el CONTENEDOR lo deduce solo a partir de
  // la sesion, y sobre todo si SE ABSTIENE DE SALIR A LA RED. Eso es lo que se mide aca: las
  // acciones de la sesion QA ahora son configurables (`?acciones=`).
  const ESCENARIOS = [
    ['solo-a31', 'falta A30'],
    ['solo-a30', 'falta A31'],
    ['ninguna', 'faltan las DOS'],
  ];

  for (const [perfil, desc] of ESCENARIOS) {
    const p = await b.newPage({ viewport: { width: 1280, height: 900 } });
    await p.goto(`${BASE}/?contenedor=1&acciones=${perfil}`);
    await p.waitForSelector('main');
    await p.waitForTimeout(400);

    const t = await texto(p);
    const a30 = await llamadas(p, A30);
    const a31 = await llamadas(p, A31);
    const selector = await p.locator('#mes-historico').count();
    const cifras = /\$\s?\d/.test(t);

    const limpio =
      t.includes('No se pudo habilitar toda la información necesaria') &&
      selector === 0 &&
      !cifras &&
      a30.length === 0 &&
      a31.length === 0;

    ok(
      limpio,
      `${desc.padEnd(16)} -> banner fail-closed, selector ausente (${selector}), cero cifras (${!cifras}), ` +
        `cero llamadas A30 (${a30.length}) y A31 (${a31.length})`
    );
    await p.close();
  }

  // Y el control: con las DOS acciones, la pantalla funciona.
  {
    const p = await b.newPage({ viewport: { width: 1280, height: 900 } });
    await p.goto(`${BASE}/?contenedor=1&acciones=ambas`);
    await p.waitForSelector('main');
    await p.waitForTimeout(500);
    const t = await texto(p);
    const a30 = await llamadas(p, A30);
    const a31 = await llamadas(p, A31);
    ok(
      !t.includes('No se pudo habilitar') &&
        (await p.locator('#mes-historico').count()) === 1 &&
        /\$\s?\d/.test(t) &&
        a30.length >= 1 &&
        a31.length >= 1,
      `estan las dos      -> sin banner, selector presente, cifras, A30 (${a30.length}) y A31 (${a31.length}) salieron`
    );
    await p.close();
  }
}

// ---------------------------------------------------------------------------------------------
caso('F9 · RETRY DE A30 con CLIC en el boton real');
// ---------------------------------------------------------------------------------------------
{
  // El bloque E4 de `qa:probes` invoca `foto.refetch()` a mano: eso prueba que el callback existe,
  // no que el BOTON este cableado. Aca se hace clic en el boton de verdad y se cuenta la red.
  const p = await b.newPage({ viewport: { width: 1280, height: 900 } });
  await p.addInitScript(() => {
    // A31 OK; A30 devuelve ok:false -> callPortal REAL lo vuelve PortalApiError.
    window.__QA_PRECONF__ = { a30: { fixture: 'F1', latencia: 0, falla: true } };
  });
  await p.goto(URL_CONTENEDOR);
  await p.waitForSelector('main');
  await p.waitForTimeout(500);

  const t1 = await texto(p);
  ok(t1.includes('Totales acumulados'), 'A31 respondio bien: los acumulados estan');
  const foto1 = t1.slice(t1.lastIndexOf('Consultar'));
  ok(/No se pudo cargar la informacion/.test(foto1), 'A30 caida -> ErrorCard en la seccion Foto');
  ok(!t1.includes('Cabecera de la foto'), 'y ninguna seccion de la foto');

  // el servidor "se recupera"
  await p.evaluate(() => {
    window.__QA_RED__.a30 = { fixture: 'F1', latencia: 0, falla: false };
  });
  const antes = (await llamadas(p, A30)).length;

  // El Reintentar de la FOTO es el ultimo de la pagina (A31 esta OK, asi que no tiene el suyo).
  const botones = p.locator('button', { hasText: 'Reintentar' });
  ok((await botones.count()) === 1, 'hay UN solo Reintentar: el de la foto (A31 esta sana)');
  await botones.last().click();
  await p.waitForTimeout(600);

  const despues = (await llamadas(p, A30)).length;
  ok(despues === antes + 1, `el CLIC disparo exactamente UNA peticion A30 adicional (${antes} -> ${despues})`);

  const t2 = await texto(p);
  ok(t2.includes('Cabecera de la foto'), 'y la foto aparece');
  ok(!/No se pudo cargar la informacion/.test(t2.slice(t2.lastIndexOf('Consultar'))), 'el ErrorCard de la foto desaparecio');
  ok((await p.locator('button', { hasText: 'Reintentar' }).count()) === 0, 'no quedo ningun boton de reintento');
  await p.close();
}

await b.close();
console.log(fallos === 0 ? '\n  CONTENEDOR OK\n' : `\n  ${fallos} FALLAS\n`);
process.exit(fallos === 0 ? 0 : 1);
