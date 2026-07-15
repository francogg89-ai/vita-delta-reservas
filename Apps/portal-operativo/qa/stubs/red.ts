// SB-UI-6-FIX2 -- Stub de TRANSPORTE, no de modulos.
// __VITA_QA_FIXTURE_DO_NOT_SHIP__
//
// Se intercepta UNICAMENTE `window.fetch`. Todo lo demas corre de verdad:
//   HistoricoCuentaCorriente REAL  (token PeticionFoto.seq, anti-doble-request, `enabled`)
//   useAction REAL                 (reqId, cleanup de unmount)
//   callPortal REAL                (envelope ok/error, PortalApiError)
//
// SNAPSHOT AL RECIBIR (SB-UI-6-FIX2). La version anterior leia el fixture DESPUES del `await` de la
// latencia, desde un control global mutable. Con eso, una peticion que salio pidiendo el fixture A y
// tardo 600ms terminaba devolviendo el fixture B si alguien cambiaba el control mientras volaba: el
// stub se "auto-corregia" y tapaba justo el bug que hay que cazar (una respuesta vieja pisando a una
// nueva). Ahora cada request CAPTURA lo suyo en el momento en que entra y no vuelve a mirar el
// control nunca mas.
import type { HistoricoMesData } from '../../src/lib/contratos';
import { CATALOGO_A30, CATALOGO_A31 } from '../fixtures';

/** Lo que se sirve a UNA peticion. Se resuelve al recibirla y queda congelado. */
export interface Respuesta {
  fixture: string;
  latencia: number;
  falla: boolean;
}

export interface ControlRed {
  /** Valor por defecto de cada accion, si no hay nada encolado. */
  a30: Respuesta;
  a31: Respuesta;
  /**
   * COLA por accion. Cada peticion consume el primer elemento. Sirve para guionar secuencias:
   * "la 1a request devuelve el fixture anomalo en 600ms; la 2a el normal en 50ms".
   */
  colaA30: Respuesta[];
  colaA31: Respuesta[];
  /** Registro de todo lo que salio, con lo que CADA request capturo al entrar. */
  llamadas: { action: string; payload: Record<string, unknown>; sirvio: Respuesta; t: number }[];
}

declare global {
  interface Window {
    __QA_RED__: ControlRed;
    /** Inyectado por Playwright con `addInitScript`, ANTES del bundle: sobrevive a un reload. */
    __QA_PRECONF__?: Partial<ControlRed>;
  }
}

const A30 = 'cuenta_corriente.historico';
const A31 = 'cuenta_corriente.historico_acumulados';

export const resp = (fixture: string, latencia = 0, falla = false): Respuesta => ({
  fixture,
  latencia,
  falla,
});

export function instalarRedFalsa() {
  window.__QA_RED__ = {
    a30: resp('F1'),
    a31: resp('F10'),
    colaA30: [],
    colaA31: [],
    llamadas: [],
    ...(window.__QA_PRECONF__ ?? {}),
  };

  window.fetch = (async (_url: string, init?: RequestInit) => {
    const c = window.__QA_RED__;
    const body = JSON.parse(String(init?.body ?? '{}')) as {
      action: string;
      payload: Record<string, unknown>;
    };
    const esA30 = body.action === A30;
    const esA31 = body.action === A31;

    // ---- SNAPSHOT: se resuelve TODO aca, al recibir. Despues de esta linea, el control global no
    // ---- vuelve a consultarse. Lo que esta request devuelva ya esta decidido.
    const cola = esA30 ? c.colaA30 : esA31 ? c.colaA31 : [];
    const sirvio: Respuesta = cola.shift() ?? (esA30 ? c.a30 : esA31 ? c.a31 : resp('-'));
    const payload = body.payload;
    c.llamadas.push({ action: body.action, payload, sirvio, t: Date.now() });

    if (!esA30 && !esA31) return respuesta({ ok: true, data: {} });

    if (sirvio.latencia > 0) await new Promise((r) => setTimeout(r, sirvio.latencia));

    if (sirvio.falla) {
      // El gateway responde 200 con ok:false -> callPortal REAL lo vuelve PortalApiError.
      return respuesta({
        ok: false,
        error: { code: 'error_interno', message: 'Fallo simulado por el harness.', detail: null },
      });
    }

    if (esA31) {
      const f = CATALOGO_A31.find((x) => x.id === sirvio.fixture);
      return respuesta(
        f
          ? { ok: true, data: f.data }
          : { ok: false, error: { code: 'no_encontrado', message: 'fixture inexistente', detail: null } }
      );
    }

    const f = CATALOGO_A30.find((x) => x.id === sirvio.fixture);
    if (!f) {
      return respuesta({ ok: false, error: { code: 'no_encontrado', message: 'fixture inexistente', detail: null } });
    }
    // El contenedor manda `{ mes: 'YYYY-MM-01' }` (primerDiaMes), NO `{ periodo }`.
    //
    // Reproyectar la foto al mes pedido hay que hacerlo COHERENTE: `data.periodo` (T1),
    // `cabecera.periodo` (T3) y `retribucion_operativo.periodo` (T5) se mueven JUNTOS. Mover solo
    // `data.periodo` deja una foto que el clasificador rechaza -- y con razon.
    const periodo = typeof payload.mes === 'string' ? payload.mes : f.data.periodo;
    const d: HistoricoMesData = f.data;
    return respuesta({
      ok: true,
      data: {
        ...d,
        periodo,
        cabecera: d.cabecera === null ? null : { ...d.cabecera, periodo },
        retribucion_operativo:
          d.retribucion_operativo === null ? null : { ...d.retribucion_operativo, periodo },
      },
    });
  }) as typeof fetch;
}

function respuesta(envelope: unknown): Response {
  return new Response(JSON.stringify(envelope), {
    status: 200,
    headers: { 'Content-Type': 'application/json' },
  });
}
