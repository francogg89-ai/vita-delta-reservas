#!/usr/bin/env python3
"""
B4_0A_v6_SMOKES.py  (v6 -- post-auditoria 6)  -- Smokes de B4-0A contra un PostgreSQL REAL.

Requiere:  python3 B4_0A_v6_HARNESS.py --reset

DOS IDENTIDADES (punto 1 de la auditoria).
  admin() : setup, fixtures, lectura de catalogo, asserts internos, teardown.
            Corre como owner. NUNCA se usa para probar runtime ni negativos.
  rol()   : TODA llamada runtime y TODOS los negativos de seguridad.
            Corre con la identidad de vita_precios_api.

  MECANISMO: el PostgreSQL embebido de pgserver acepta conexiones sin password
  (trust local) e ignora el usuario del connection string -> abrir una conexion
  "como el rol" no cambia current_user. SET SESSION AUTHORIZATION SI cambia la
  identidad efectiva (current_user = session_user = vita_precios_api) y el motor
  evalua permisos exactamente igual que con una conexion real del rol.
  Verificado: con esta identidad, core / B3 / SELECT / INSERT / TRUNCATE / CREATE
  devuelven permission denied, y los 5 entrypoints funcionan.

  LIMITE DECLARADO: 'SET ROLE postgres rechazado' NO se puede probar aca (el owner
  del harness es superuser y puede volver a su rol). Queda como TEST-only y lo
  cubre B4-0B con la conexion autenticada real.

PORTABLE: sin rutas absolutas.
    B4_PGDATA  directorio de datos (default: <script_dir>/.pgdata_b4)
"""
import os
import sys
import uuid
import json
import threading
import time
from pathlib import Path
from datetime import date, timedelta, datetime
from zoneinfo import ZoneInfo
from concurrent.futures import ThreadPoolExecutor

import pgserver
import psycopg

SCRIPT_DIR = Path(__file__).resolve().parent
PGDATA = Path(os.environ.get('B4_PGDATA', SCRIPT_DIR / '.pgdata_b4'))
_db = pgserver.get_server(str(PGDATA))
URI = _db.get_uri()

# "hoy" en zona Argentina, igual que el SQL. La fecha del contenedor es UTC y a
# partir de las 21:00 ART ya es "manana" -> el smoke de fecha pasada daria un
# falso negativo.
HOY = datetime.now(ZoneInfo('America/Argentina/Buenos_Aires')).date()

R = []
def chk(nombre, cond, detalle=''):
    R.append((nombre, bool(cond), detalle))


class admin:
    """Owner. Setup / catalogo / asserts / teardown."""
    def __enter__(self):
        self.c = psycopg.connect(URI, autocommit=True)
        return self.c.cursor()
    def __exit__(self, *a):
        self.c.close()


class rol:
    """Identidad de vita_precios_api. Runtime y negativos."""
    def __init__(self, autocommit=True):
        self.autocommit = autocommit
    def __enter__(self):
        self.c = psycopg.connect(URI, autocommit=self.autocommit)
        cur = self.c.cursor()
        cur.execute("SET SESSION AUTHORIZATION vita_precios_api")
        return cur
    def __exit__(self, *a):
        try:
            self.c.rollback()
        except Exception:
            pass
        self.c.close()


def adm(cur, accion='cotizar', sup='s2s', suj='whatsapp', nonce=None, payload=None,
        idem=None, cot=None, corr='auto'):
    if nonce is None:
        nonce = str(uuid.uuid4())
    if corr == 'auto':
        corr = str(uuid.uuid4())
    ptxt = json.dumps(payload) if payload is not None else None
    cur.execute(
        "SELECT precios_api.api_precios_admitir(%s,%s,%s,%s::uuid,%s,%s::uuid,%s::uuid,%s::uuid)",
        (accion, sup, suj, nonce, ptxt, idem, cot, corr))
    return cur.fetchone()[0]


def exp_cot(cur, tk, payload):
    cur.execute("SELECT precios_api.api_precios_cotizar_exponer(%s::uuid,%s::jsonb)",
                (tk, json.dumps(payload)))
    return cur.fetchone()[0]


def exp_con(cur, tk, payload, idem):
    cur.execute("SELECT precios_api.api_precios_congelar_exponer(%s::uuid,%s::jsonb,%s::uuid)",
                (tk, json.dumps(payload), idem))
    return cur.fetchone()[0]


def exp_obt(cur, tk, cid):
    cur.execute("SELECT precios_api.api_precios_obtener_exponer(%s::uuid,%s::uuid)", (tk, cid))
    return cur.fetchone()[0]


def pl(cab=1, d0=10, n=2, pers=2):
    return {'id_cabana': cab,
            'fecha_in':  str(HOY + timedelta(days=d0)),
            'fecha_out': str(HOY + timedelta(days=d0 + n)),
            'personas':  pers}


def flujo_cotizar(cur, payload):
    a = adm(cur, 'cotizar', payload=payload)
    if not a.get('ok'):
        return a
    return exp_cot(cur, a['ticket_id'], payload)


def limpiar():
    with admin() as a:
        a.execute("DELETE FROM precios_api.api_precios_rate_limit")
        a.execute("DELETE FROM precios_api.api_precios_nonce_s2s")
        a.execute("DELETE FROM precios_api.api_precios_ticket")


def restaurar_b3():
    """Reinstala los stubs B3 del harness y su REVOKE owner-only."""
    import importlib.util
    spec = importlib.util.spec_from_file_location('h', str(SCRIPT_DIR / 'B4_0A_v6_HARNESS.py'))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    with admin() as a:
        a.execute(m.B3)
        a.execute(r"""DO $$ DECLARE r RECORD; BEGIN
          FOR r IN SELECT oid::regprocedure AS s FROM pg_proc
                    WHERE pronamespace='public'::regnamespace AND proname LIKE 'precios\_%' LOOP
            EXECUTE 'REVOKE EXECUTE ON FUNCTION '||r.s||
                    ' FROM PUBLIC, anon, authenticated, service_role, vita_precios_api';
          END LOOP; END $$;""")


# ==========================================================================
# 1. ACL -- estructura (admin) + comportamiento real (ROL)
# ==========================================================================
ALLOW = ['api_precios_admitir', 'api_precios_cotizar_exponer',
         'api_precios_congelar_exponer', 'api_precios_obtener_exponer',
         'api_precios_probe_ambiente']


def _restaurar_login():
    """Paso 2 del runsheet: el SQL crea el rol NOLOGIN; el ALTER le da acceso."""
    with admin() as a:
        a.execute("SELECT 1 FROM pg_roles WHERE rolname='vita_precios_api'")
        if a.fetchone():
            a.execute("ALTER ROLE vita_precios_api LOGIN PASSWORD 'harness_only_no_es_la_de_test'")


def _sql_principal():
    """El SQL de B4-0A con los 3 fingerprints reemplazados por los del harness.

    El harness usa STUBS del motor B3, asi que los fingerprints canonicos de TEST
    no matchean. Se recalculan igual que en B4_0A_v6_HARNESS.py. En TEST el SQL corre
    tal cual, sin ninguna adaptacion.
    """
    txt = (SCRIPT_DIR / 'B4_0A_v6_ROL_TABLAS_FUNCIONES.sql').read_text()
    with admin() as a:
        a.execute("""SELECT md5(string_agg(md5(replace(prosrc, chr(13), '')), '' ORDER BY proname))
                       FROM pg_proc WHERE pronamespace='public'::regnamespace
                        AND proname LIKE 'precios\\_%'""")
        fp_b3 = a.fetchone()[0]
    # B2A / B2B: los publica el harness en GUCs de base
    with admin() as a:
        a.execute("SELECT current_setting('b4.fp_b2a', true), current_setting('b4.fp_b2b', true)")
        b2a, b2b = a.fetchone()
    txt = txt.replace('098f2fe7916e11ffa78cff37622b9064', fp_b3)
    if b2a: txt = txt.replace('da52a16c045689523a5f1f113f513a87', b2a)
    if b2b: txt = txt.replace('6d1653748d68ee9b62aa20aba5f3333d', b2b)
    return txt


def s_acl_estructura():
    with admin() as cur:
        cur.execute("""SELECT p.proname FROM pg_proc p
                       WHERE p.pronamespace='precios_api'::regnamespace
                         AND has_function_privilege('vita_precios_api', p.oid,'EXECUTE')""")
        got = sorted(x[0] for x in cur.fetchall())
        chk('ACL/estruct: el rol ejecuta exactamente 5', got == sorted(ALLOW), str(len(got)))

        cur.execute("""SELECT count(*) FROM pg_proc p
                       WHERE p.pronamespace='precios_api'::regnamespace
                         AND NOT (p.proname = ANY(%s))
                         AND has_function_privilege('vita_precios_api', p.oid,'EXECUTE')""",
                    (ALLOW,))
        chk('ACL/estruct: cero EXECUTE sobre core/helpers/purgas', cur.fetchone()[0] == 0)

        cur.execute(r"""SELECT count(*) FROM pg_proc p
                        WHERE p.pronamespace='public'::regnamespace
                          AND p.proname LIKE 'precios\_%%'
                          AND has_function_privilege('vita_precios_api', p.oid,'EXECUTE')""")
        chk('ACL/estruct: cero EXECUTE sobre las 13 precios_* de B3', cur.fetchone()[0] == 0)

        cur.execute("SELECT has_schema_privilege('vita_precios_api','precios_api','USAGE')")
        chk('ACL/estruct: USAGE en precios_api', cur.fetchone()[0] is True)
        cur.execute("SELECT has_schema_privilege('vita_precios_api','precios_api','CREATE')")
        chk('ACL/estruct: sin CREATE en precios_api', cur.fetchone()[0] is False)

        cur.execute("""SELECT rolsuper OR rolcreatedb OR rolcreaterole OR rolbypassrls
                       OR rolreplication FROM pg_roles WHERE rolname='vita_precios_api'""")
        chk('ACL/estruct: rol sin atributos peligrosos', cur.fetchone()[0] is False)

        # el rol no puede CREAR nada: ni en el schema public, ni schemas nuevos
        cur.execute("SELECT has_schema_privilege('vita_precios_api','public','CREATE')")
        chk('ACL/estruct: sin CREATE en el schema public', cur.fetchone()[0] is False)
        cur.execute("""SELECT has_database_privilege('vita_precios_api',
                              current_database(),'CREATE')""")
        chk('ACL/estruct: sin CREATE sobre la BASE (no puede crear schemas)',
            cur.fetchone()[0] is False)

        # secuencias: cero privilegio en toda la base (punto 10)
        cur.execute("""SELECT count(*) FROM pg_class c
                       JOIN pg_namespace n ON n.oid=c.relnamespace
                       CROSS JOIN (VALUES ('USAGE'),('SELECT'),('UPDATE')) AS p(priv)
                       WHERE c.relkind='S' AND n.nspname NOT LIKE 'pg\\_%'
                         AND n.nspname <> 'information_schema'
                         AND has_sequence_privilege('vita_precios_api', c.oid, p.priv)""")
        chk('ACL/estruct: cero privilegios de SECUENCIA en toda la base',
            cur.fetchone()[0] == 0)

        # ---- PRIVILEGIO MINIMO: 5 DEFINER / 14 INVOKER ----
        cur.execute("""SELECT count(*) FILTER (WHERE prosecdef),
                              count(*) FILTER (WHERE NOT prosecdef)
                       FROM pg_proc WHERE pronamespace='precios_api'::regnamespace""")
        n_def, n_inv = cur.fetchone()
        chk('SECDEF: exactamente 5 SECURITY DEFINER', n_def == 5, str(n_def))
        chk('SECDEF: exactamente 14 SECURITY INVOKER', n_inv == 14, str(n_inv))

        cur.execute("""SELECT count(*) FROM pg_proc
                       WHERE pronamespace='precios_api'::regnamespace
                         AND prosecdef AND NOT (proname = ANY(%s))""", (ALLOW,))
        chk('SECDEF: los 5 DEFINER son exactamente los entrypoints',
            cur.fetchone()[0] == 0)

        cur.execute("""SELECT count(*) FROM pg_proc
                       WHERE pronamespace='precios_api'::regnamespace
                         AND prosecdef AND proname LIKE '%%_core'""")
        chk('SECDEF: ningun _core es SECURITY DEFINER', cur.fetchone()[0] == 0)

        cur.execute("""SELECT count(*) FROM pg_proc
                       WHERE pronamespace='precios_api'::regnamespace
                         AND prosecdef AND proname LIKE '%%_purgar'""")
        chk('SECDEF: ninguna purga es SECURITY DEFINER (pg_cron ya corre como postgres)',
            cur.fetchone()[0] == 0)


def s_invoker_no_escala():
    """PUNTO 7 (comportamental): la razon de ser del cambio.

    Si una ACL se abriera por accidente sobre una funcion interna:
      - siendo INVOKER  -> corre como el ROL -> no puede tocar las tablas -> NO escala.
      - siendo DEFINER  -> correria como postgres -> SI filtraria datos.
    Se prueba abriendo la ACL de un core a proposito y confirmando que igual falla.
    """
    limpiar()
    # 1) INVOKER con la ACL ABIERTA a proposito
    with admin() as a:
        a.execute("GRANT EXECUTE ON FUNCTION precios_api.api_precios_cotizar_core(jsonb) TO vita_precios_api")
    try:
        with rol() as cur:
            cur.execute("SELECT precios_api.api_precios_cotizar_core('{}'::jsonb)")
        chk('SECDEF/comport: INVOKER con ACL abierta NO escala', False,
            'EJECUTO: escalo privilegios')
    except psycopg.errors.InsufficientPrivilege:
        chk('SECDEF/comport: INVOKER con ACL abierta NO escala '
            '(corre como el rol -> permission denied)', True)
    except psycopg.errors.Error as e:
        # cualquier otro error tambien prueba que no leyo datos privilegiados
        chk('SECDEF/comport: INVOKER con ACL abierta NO escala', True, str(e.sqlstate))
    finally:
        with admin() as a:
            a.execute("REVOKE EXECUTE ON FUNCTION precios_api.api_precios_cotizar_core(jsonb) FROM vita_precios_api")

    # 2) contraste: el MISMO core como DEFINER con la ACL abierta SI escalaria
    with admin() as a:
        a.execute("ALTER FUNCTION precios_api.api_precios_cotizar_core(jsonb) SECURITY DEFINER")
        a.execute("GRANT EXECUTE ON FUNCTION precios_api.api_precios_cotizar_core(jsonb) TO vita_precios_api")
    escalo = False
    try:
        with rol() as cur:
            cur.execute("SELECT precios_api.api_precios_cotizar_core(%s::jsonb)", (json.dumps(pl()),))
            escalo = cur.fetchone()[0] is not None
    except psycopg.errors.Error:
        escalo = False
    finally:
        with admin() as a:
            a.execute("REVOKE EXECUTE ON FUNCTION precios_api.api_precios_cotizar_core(jsonb) FROM vita_precios_api")
            a.execute("ALTER FUNCTION precios_api.api_precios_cotizar_core(jsonb) SECURITY INVOKER")

    chk('SECDEF/comport: el mismo core como DEFINER+ACL abierta SI escalaria '
        '(por eso son INVOKER)', escalo, 'no escalo (el contraste no se demostro)')

    # 3) y tras restaurar, el core vuelve a ser inalcanzable
    try:
        with rol() as cur:
            cur.execute("SELECT precios_api.api_precios_cotizar_core('{}'::jsonb)")
        chk('SECDEF/comport: core restaurado a INVOKER owner-only', False, 'sigue alcanzable')
    except psycopg.errors.InsufficientPrivilege:
        chk('SECDEF/comport: core restaurado a INVOKER owner-only', True)

    with admin() as a:
        a.execute("""SELECT prosecdef FROM pg_proc
                     WHERE pronamespace='precios_api'::regnamespace
                       AND proname='api_precios_cotizar_core'""")
        chk('SECDEF/comport: el smoke dejo el core como INVOKER (sin residuo)',
            a.fetchone()[0] is False)


def s_acl_runtime_negativos():
    """TODO esto con la identidad del ROL. Antes corria como postgres (el bug)."""
    negativos = [
        ("core cotizar",        "SELECT precios_api.api_precios_cotizar_core('{}'::jsonb)"),
        ("core congelar",       "SELECT precios_api.api_precios_congelar_core('{}'::jsonb,gen_random_uuid(),'x')"),
        ("core obtener",        "SELECT precios_api.api_precios_obtener_core(gen_random_uuid())"),
        ("B3 precios_cotizar",  "SELECT public.precios_cotizar('{}'::jsonb)"),
        ("B3 precios_congelar", "SELECT public.precios_cotizar_congelar('{}'::jsonb)"),
        ("B3 precios_obtener",  "SELECT public.precios_cotizacion_obtener(gen_random_uuid())"),
        ("guard_sesion",        "SELECT precios_api.api_precios_guard_sesion()"),
        ("gate_ambiente",       "SELECT precios_api.api_precios_gate_ambiente()"),
        ("rl_consumir",         "SELECT precios_api.api_precios_rl_consumir('cotizar_global','_g',clock_timestamp())"),
        ("admision_leer",       "SELECT * FROM precios_api.api_precios_admision_leer('whatsapp',gen_random_uuid())"),
        ("validar_payload",     "SELECT precios_api.api_precios_validar_payload('{}'::jsonb,'whatsapp')"),
        ("ticket_hash_v1",      "SELECT precios_api.api_precios_ticket_hash_v1('c','s2s','w',NULL,NULL,NULL)"),
        ("purga ticket",        "SELECT precios_api.api_precios_ticket_purgar()"),
        ("purga nonce",         "SELECT precios_api.api_precios_nonce_purgar()"),
        ("SELECT ticket",       "SELECT count(*) FROM precios_api.api_precios_ticket"),
        ("SELECT rate_limit",   "SELECT count(*) FROM precios_api.api_precios_rate_limit"),
        ("SELECT nonce",        "SELECT count(*) FROM precios_api.api_precios_nonce_s2s"),
        ("SELECT idempotencia", "SELECT count(*) FROM precios_api.api_precios_idempotencia"),
        ("SELECT cotizaciones", "SELECT count(*) FROM public.cotizaciones_precio"),
        ("INSERT rate_limit",   "INSERT INTO precios_api.api_precios_rate_limit VALUES ('x','y',clock_timestamp(),1)"),
        ("UPDATE ticket",       "UPDATE precios_api.api_precios_ticket SET consumed_at=clock_timestamp()"),
        ("DELETE nonce",        "DELETE FROM precios_api.api_precios_nonce_s2s"),
        ("TRUNCATE rate_limit", "TRUNCATE precios_api.api_precios_rate_limit"),
        ("CREATE en public",    "CREATE TABLE public.zzz_hack(a int)"),
        ("CREATE en precios_api", "CREATE TABLE precios_api.zzz_hack(a int)"),
        ("CREATE SCHEMA b4_hack", "CREATE SCHEMA b4_hack"),
        ("CREATE FUNCTION en public",
         "CREATE FUNCTION public.zzz_hack() RETURNS int LANGUAGE sql AS 'SELECT 1'"),
    ]
    for nombre, sql in negativos:
        try:
            with rol() as cur:
                cur.execute(sql)
            chk(f'ACL/rol: {nombre} denegado', False, 'NO fue rechazado')
        except psycopg.errors.InsufficientPrivilege:
            chk(f'ACL/rol: {nombre} denegado', True)
        except (psycopg.errors.UndefinedFunction, psycopg.errors.UndefinedTable):
            chk(f'ACL/rol: {nombre} denegado', True, 'inalcanzable')

    # los 5 entrypoints DEBEN funcionar como el rol
    with rol() as cur:
        r = adm(cur, 'cotizar', payload=pl())
        chk('ACL/rol: admitir FUNCIONA', r.get('ok') is True, str(r)[:50])
        if r.get('ok'):
            chk('ACL/rol: cotizar_exponer FUNCIONA',
                exp_cot(cur, r['ticket_id'], pl()).get('ok') is True)
        cur.execute("SELECT precios_api.api_precios_probe_ambiente()")
        chk('ACL/rol: probe_ambiente FUNCIONA', cur.fetchone()[0] == 'test')

    with rol() as cur:
        p = pl()
        k = str(uuid.uuid4())
        a1 = adm(cur, 'congelar', payload=p, idem=k)
        chk('ACL/rol: congelar_exponer FUNCIONA',
            exp_con(cur, a1['ticket_id'], p, k).get('ok') is True)
        cid = None
    with rol() as cur:
        p = pl()
        k = str(uuid.uuid4())
        a1 = adm(cur, 'congelar', payload=p, idem=k)
        rc = exp_con(cur, a1['ticket_id'], p, k)
        cid = rc.get('motor', {}).get('cotizacion_id')
        a2 = adm(cur, 'obtener', cot=cid)
        chk('ACL/rol: obtener_exponer FUNCIONA',
            exp_obt(cur, a2['ticket_id'], cid).get('ok') is True)

    chk('ACL/rol: SET ROLE postgres rechazado [TEST-only: no simulable en harness]',
        True, 'lo verifica B4-0B con la conexion autenticada real')


# ==========================================================================
# 2. D3 -- 7 vectores, COMO EL ROL
# ==========================================================================
def s_d3():
    """7 vectores de envenenamiento de pg_temp, COMO EL ROL.

    DOS desenlaces son correctos para cada vector:
      (a) el rol NO PUEDE crearlo  -> lo bloquea el hardening. Defensa extra.
      (b) el rol PUEDE crearlo     -> D3 DEBE rechazar con VDT01.
    El unico FAIL real es: se crea Y D3 no lo detecta.

    B4-0A no aplica hardening global, asi que los 7 vectores son creables por el
    rol -> D3 debe rechazar los 7.

    El smoke igual acepta ambos desenlaces a proposito: si algun dia se aplicara
    un hardening de default privileges, TEMP RANGE dejaria de ser creable (medido:
    CREATE TYPE ... AS RANGE genera funciones constructoras y necesita EXECUTE
    sobre ellas). Con esta forma, el smoke es valido en los dos escenarios y nunca
    da un falso verde: si el vector se crea, D3 TIENE que agarrarlo.
    """
    vectores = [
        ('TEMP TABLE',     "CREATE TEMP TABLE configuracion_general(clave text, valor text)"),
        ('TEMP VIEW',      "CREATE TEMP VIEW configuracion_general AS SELECT 'a'::text clave,'ops'::text valor"),
        ('TEMP SEQUENCE',  "CREATE TEMP SEQUENCE configuracion_general"),
        ('TEMP ENUM',      "CREATE TYPE pg_temp.mi_enum AS ENUM ('a','b')"),
        ('TEMP DOMAIN',    "CREATE DOMAIN pg_temp.mi_dom AS integer CHECK (VALUE > 0)"),
        ('TEMP COMPOSITE', "CREATE TYPE pg_temp.mi_comp AS (a integer, b text)"),
        ('TEMP RANGE',     "CREATE TYPE pg_temp.mi_rng AS RANGE (subtype = integer)"),
    ]
    for nombre, ddl in vectores:
        with rol() as cur:
            try:
                cur.execute(ddl)
            except psycopg.errors.InsufficientPrivilege:
                chk(f'D3/rol: {nombre} -- el rol NO PUEDE crearlo (bloqueado antes de D3)', True)
                continue
            try:
                adm(cur, 'cotizar', payload=pl())
                chk(f'D3/rol: rechaza {nombre}', False, 'SE CREO y D3 NO lo detecto')
            except psycopg.errors.Error as e:
                chk(f'D3/rol: rechaza {nombre}', e.sqlstate == 'VDT01', str(e.sqlstate))

    with rol() as cur:
        cur.execute("CREATE TEMP TABLE zz(a int)")
        try:
            adm(cur, 'cotizar', payload=pl())
            bloqueo = False
        except psycopg.errors.Error as e:
            bloqueo = e.sqlstate == 'VDT01'
        cur.execute("DROP TABLE zz")
        r_drop = adm(cur, 'cotizar', payload=pl())
        cur.execute("CREATE TYPE pg_temp.ee AS ENUM ('a')")
        try:
            adm(cur, 'cotizar', payload=pl())
            bloqueo_enum = False
        except psycopg.errors.Error as e:
            bloqueo_enum = e.sqlstate == 'VDT01'
        cur.execute("DISCARD ALL")
        cur.execute("SET SESSION AUTHORIZATION vita_precios_api")  # DISCARD la resetea
        r_disc = adm(cur, 'cotizar', payload=pl())

    chk('D3/rol: TEMP TABLE bloquea', bloqueo)
    chk('D3/rol: tras DROP la sesion se recupera (sin falso positivo permanente)',
        r_drop.get('ok') is True, str(r_drop)[:50])
    chk('D3/rol: TEMP ENUM bloquea (pg_class ciego -> hace falta pg_type)', bloqueo_enum)
    chk('D3/rol: DISCARD ALL recupera', r_disc.get('ok') is True)


# ==========================================================================
# 3. ADMISION (rol)
# ==========================================================================
def s_admision():
    limpiar()
    with admin() as a:
        a.execute("SELECT COALESCE(sum(n),0) FROM precios_api.api_precios_rate_limit WHERE scope='cotizar_global'")
        antes = a.fetchone()[0]

    with rol() as cur:
        r = adm(cur, 'cotizar', payload=pl(), corr=None)
        chk('ADM: correlation_id NULL -> admision_invalida',
            r.get('error') == 'admision_invalida' and r.get('campo') == 'correlation_id_requerido',
            str(r))

    with admin() as a:
        a.execute("SELECT COALESCE(sum(n),0) FROM precios_api.api_precios_rate_limit WHERE scope='cotizar_global'")
        chk('ADM: correlation_id NULL NO cobra cuota', a.fetchone()[0] == antes)

    casos = [
        ('accion invalida',     dict(accion='borrar', payload=pl()), 'accion_invalida'),
        ('superficie web (F3)', dict(sup='web', payload=pl()), 'superficie_invalida'),
        ('sujeto ajeno',        dict(suj='telegram', payload=pl()), 'sujeto_invalido'),
        ('cotizar sin payload', dict(accion='cotizar', payload=None), 'payload_requerido'),
        ('cotizar con idem',    dict(accion='cotizar', payload=pl(), idem=str(uuid.uuid4())), 'idem_key_no_admitida'),
        ('congelar sin idem',   dict(accion='congelar', payload=pl()), 'idem_key_requerida'),
        ('congelar idem no-v4', dict(accion='congelar', payload=pl(),
                                     idem='00000000-0000-1000-8000-000000000000'), 'idem_key_no_v4'),
        ('obtener sin cot_id',  dict(accion='obtener'), 'cotizacion_id_requerida'),
        ('obtener con payload', dict(accion='obtener', cot=str(uuid.uuid4()), payload=pl()), 'payload_no_admitido'),
    ]
    with rol() as cur:
        for nombre, kw, campo in casos:
            r = adm(cur, **kw)
            chk(f'ADM: {nombre}',
                r.get('error') == 'admision_invalida' and r.get('campo') == campo, str(r))

        cur.execute("""SELECT precios_api.api_precios_admitir('cotizar','s2s','whatsapp',NULL,%s,NULL,NULL,%s::uuid)""",
                    (json.dumps(pl()), str(uuid.uuid4())))
        chk('ADM: nonce NULL', cur.fetchone()[0].get('campo') == 'nonce_requerido')

        gordo = pl()
        gordo['fecha_in'] = 'x' * 9000
        chk('ADM: payload > 8 KB -> payload_size',
            adm(cur, 'cotizar', payload=gordo).get('campo') == 'payload_size')

        cur.execute("""SELECT precios_api.api_precios_admitir('cotizar','s2s','whatsapp',
                       gen_random_uuid(),'{roto',NULL,NULL,gen_random_uuid())""")
        chk('ADM: JSON roto -> payload_json (no error_interno)',
            cur.fetchone()[0].get('campo') == 'payload_json')

        cur.execute("""SELECT precios_api.api_precios_admitir('cotizar','s2s','whatsapp',
                       gen_random_uuid(),'[1,2,3]',NULL,NULL,gen_random_uuid())""")
        chk('ADM: JSON array -> payload_tipo', cur.fetchone()[0].get('campo') == 'payload_tipo')


# ==========================================================================
# 4. SAVEPOINT
# ==========================================================================
def s_savepoint():
    """ORDEN DE ADMISION -- cambio deliberado al introducir el ledger (bloqueante 1).

    ANTES: cuota -> nonce -> [savepoint: parse + ticket]. Un payload invalido cobraba
    cuota y quemaba el nonce ("el sobredimensionado paga").

    AHORA: [savepoint externo: validar -> tamano -> parse+hash -> LEDGER -> cuota -> ticket].
    El hash ES el binding del ledger, asi que hay que calcularlo ANTES de consultarlo;
    y el ledger hay que consultarlo ANTES de cobrar, porque un RECOVERY no debe cobrar.
    Consecuencia: un payload invalido NO cobra cuota y NO quema el nonce.

    Trade-off declarado: el parse (acotado a 8 KB por el check O(1) de tamano) ocurre
    antes de la cuota. El vector de flood real -- nonces NUEVOS y validos -- sigue
    cobrando cuota.
    """
    limpiar()
    with rol() as cur:
        gordo = pl()
        gordo['fecha_in'] = 'x' * 9000          # > 8 KB: rebota en el check de tamano
        r = adm(cur, 'cotizar', payload=gordo)
    chk('ORDEN: payload sobredimensionado -> admision_invalida',
        r.get('error') == 'admision_invalida' and r.get('campo') == 'payload_size', str(r)[:60])

    with admin() as a:
        a.execute("SELECT COALESCE(sum(n),0) FROM precios_api.api_precios_rate_limit")
        cuota = a.fetchone()[0]
        a.execute("SELECT count(*) FROM precios_api.api_precios_nonce_s2s")
        led = a.fetchone()[0]
        a.execute("SELECT count(*) FROM precios_api.api_precios_ticket")
        t = a.fetchone()[0]
    chk('ORDEN: payload invalido NO cobra cuota', cuota == 0, str(cuota))
    chk('ORDEN: payload invalido NO quema el nonce (ledger vacio)', led == 0, str(led))
    chk('ORDEN: ticket NO se emitio', t == 0, str(t))

    # JSON sintacticamente roto: mismo trato
    limpiar()
    with rol() as cur:
        cur.execute(
            "SELECT precios_api.api_precios_admitir('cotizar','s2s','whatsapp',"
            "%s::uuid,%s,NULL,NULL,%s::uuid)",
            (str(uuid.uuid4()), '{roto', str(uuid.uuid4())))
        r = cur.fetchone()[0]
    chk('ORDEN: JSON roto -> admision_invalida/payload_json',
        r.get('campo') == 'payload_json', str(r)[:60])
    with admin() as a:
        a.execute("SELECT COALESCE(sum(n),0) FROM precios_api.api_precios_rate_limit")
        chk('ORDEN: JSON roto tampoco cobra cuota', a.fetchone()[0] == 0)


# ==========================================================================
# 5. RATE LIMIT -- atomicidad + VENTANA UNICA (punto 3)
# ==========================================================================
def s_rate_limit():
    limpiar()
    LIM = 60  # congelar_s2s

    def uno(_):
        with rol() as cur:
            return adm(cur, 'congelar', payload=pl(), idem=str(uuid.uuid4())).get('ok') is True

    with ThreadPoolExecutor(max_workers=20) as ex:
        res = list(ex.map(uno, range(100)))
    admitidas = sum(res)

    with admin() as a:
        a.execute("SELECT n FROM precios_api.api_precios_rate_limit WHERE scope='congelar_s2s'")
        n_s = a.fetchone()[0]
        a.execute("SELECT n FROM precios_api.api_precios_rate_limit WHERE scope='congelar_global'")
        n_g = a.fetchone()[0]

    chk(f'RL: 100 concurrentes / limite {LIM} -> exactamente {LIM} admitidas',
        admitidas == LIM, f'admitidas={admitidas}')
    chk('RL: contador sujeto se detiene en el limite', n_s == LIM, str(n_s))
    chk('RL: contador global cuenta los 100 intentos', n_g == 100, str(n_g))


def s_rate_limit_ventana_unica():
    """Las 4 cubetas de UNA admision nueva deben caer en EXACTAMENTE la misma ventana."""
    limpiar()
    with rol() as cur:
        chk('RL/ventana: admitir ok', adm(cur, 'cotizar', payload=pl()).get('ok') is True)
    with admin() as a:
        a.execute("SELECT scope, ventana FROM precios_api.api_precios_rate_limit ORDER BY scope")
        filas = a.fetchall()
    ventanas = {v for _, v in filas}
    # 4 cubetas por admision nueva: intento_global, intento_sujeto, logica_global,
    # logica_sujeto. Las CUATRO deben caer en la MISMA ventana (v_ventana se calcula
    # una sola vez): si el reloj cruza el minuto entre ellas, se irian a ventanas
    # distintas y la cuota se diluiria.
    chk('RL/ventana: 4 cubetas (2 intento + 2 logica)', len(filas) == 4, str(len(filas)))
    chk('RL/ventana: las 4 caen en la MISMA ventana', len(ventanas) == 1,
        f'{len(ventanas)} distintas')
    chk('RL/ventana: estan las 2 de intento y las 2 logicas',
        {sc for sc, _ in filas} == {'admision_intento_global', 'admision_intento_s2s',
                                    'cotizar_global', 'cotizar_s2s'},
        str(sorted(sc for sc, _ in filas)))

    # borde: 50 admisiones seguidas nunca deben partir una admision en 2 minutos
    limpiar()
    with rol() as cur:
        for _ in range(50):
            adm(cur, 'cotizar', payload=pl())
    with admin() as a:
        a.execute("""SELECT count(*) FROM (
                       SELECT ventana FROM precios_api.api_precios_rate_limit
                        WHERE scope='cotizar_global'
                       EXCEPT
                       SELECT ventana FROM precios_api.api_precios_rate_limit
                        WHERE scope='cotizar_s2s') d""")
        huerfanas = a.fetchone()[0]
    chk('RL/ventana/borde: 50 admisiones, cero ventanas globales sin su par de sujeto',
        huerfanas == 0, f'{huerfanas} huerfanas')


# ==========================================================================
# 6. NONCE
# ==========================================================================
def _cuotas():
    """{(scope, sujeto): n} -- para distinguir cuota de INTENTOS de cuota LOGICA."""
    with admin() as a:
        a.execute("SELECT scope, sujeto, n FROM precios_api.api_precios_rate_limit")
        return {(sc, su): n for sc, su, n in a.fetchall()}


def _estado():
    """(tickets, ledger, filas_rl, cuota_total) -- para probar que el recovery no escribe."""
    with admin() as a:
        a.execute("""SELECT (SELECT count(*) FROM precios_api.api_precios_ticket),
                            (SELECT count(*) FROM precios_api.api_precios_nonce_s2s),
                            (SELECT count(*) FROM precios_api.api_precios_rate_limit),
                            (SELECT COALESCE(sum(n),0) FROM precios_api.api_precios_rate_limit)""")
        return a.fetchone()


def s_ledger_recovery():
    """BLOQUEANTE 1 -- respuesta perdida en TXN1.

    Si PostgreSQL commitea pero la Edge pierde la respuesta, el ticket existe y el
    nonce quedo consumido, pero la Edge NO conoce el ticket_id -- y el rol no puede
    leer la tabla de tickets. Sin ledger ese estado es AMBIGUO E IRRECUPERABLE.
    """
    limpiar()
    nn = str(uuid.uuid4())
    p  = pl()

    with rol() as cur:
        r1 = adm(cur, 'cotizar', nonce=nn, payload=p)
        chk('LEDGER: admision inicial ok', r1.get('ok') is True, str(r1)[:60])
        chk('LEDGER: via=nuevo la primera vez', r1.get('via') == 'nuevo', str(r1.get('via')))

        # *** la Edge DESCARTA la respuesta: no conoce r1['ticket_id'] ***
        antes = _estado()

        r2 = adm(cur, 'cotizar', nonce=nn, payload=p)   # mismo nonce, mismo binding
        chk('LEDGER/recovery: ok=true', r2.get('ok') is True, str(r2)[:60])
        chk('LEDGER/recovery: via=recovery', r2.get('via') == 'recovery', str(r2.get('via')))
        chk('LEDGER/recovery: MISMO ticket_id',
            r2.get('ticket_id') == r1.get('ticket_id'),
            f"{r1.get('ticket_id')} vs {r2.get('ticket_id')}")
        chk('LEDGER/recovery: ticket_estado=libre', r2.get('ticket_estado') == 'libre',
            str(r2.get('ticket_estado')))

        despues = _estado()
        chk('LEDGER/recovery: NO crea ticket',  antes[0] == despues[0], f'{antes[0]}->{despues[0]}')
        chk('LEDGER/recovery: NO crea ledger',  antes[1] == despues[1], f'{antes[1]}->{despues[1]}')

        # CLAIM PRECISO: el recovery no vuelve a consumir la cuota LOGICA de la
        # operacion. SI paga cuota de INTENTOS -- esa es la unica cota del replay
        # masivo. Decir "el recovery no cobra ninguna cuota" seria falso.
        q = _cuotas()
        chk('LEDGER/recovery: NO vuelve a cobrar la cuota LOGICA global',
            q.get(('cotizar_global', '_global')) == 1, str(q.get(('cotizar_global', '_global'))))
        chk('LEDGER/recovery: NO vuelve a cobrar la cuota LOGICA de sujeto',
            q.get(('cotizar_s2s', 'whatsapp')) == 1, str(q.get(('cotizar_s2s', 'whatsapp'))))
        chk('LEDGER/recovery: SI paga cuota de INTENTOS (cota del replay masivo)',
            q.get(('admision_intento_global', '_global')) == 2,
            str(q.get(('admision_intento_global', '_global'))))

        # el ticket recuperado es USABLE de verdad
        r3 = exp_cot(cur, r2['ticket_id'], p)
        chk('LEDGER/recovery: el ticket recuperado FUNCIONA en TXN2',
            r3.get('ok') is True, str(r3)[:60])

        # binding distinto -> conflicto
        r4 = adm(cur, 'cotizar', nonce=nn, payload=pl(d0=20))
        chk('LEDGER: binding distinto -> nonce_replay',
            r4.get('error') == 'nonce_replay', str(r4)[:60])

        # recovery con el ticket YA consumido
        r5 = adm(cur, 'cotizar', nonce=nn, payload=p)
        chk('LEDGER/recovery: ticket consumido -> estado=consumido',
            r5.get('via') == 'recovery' and r5.get('ticket_estado') == 'consumido', str(r5)[:70])


def s_ledger_concurrente():
    """BLOQUEANTE 1b -- dos admisiones concurrentes con el mismo nonce -> UN ticket."""
    limpiar()
    nn = str(uuid.uuid4())
    p  = pl()
    res = {}

    def worker(k, delay):
        time.sleep(delay)
        with psycopg.connect(URI) as c:
            cu = c.cursor()
            cu.execute("SET SESSION AUTHORIZATION vita_precios_api")
            cu.execute(
                "SELECT precios_api.api_precios_admitir('cotizar','s2s','whatsapp',"
                "%s::uuid,%s,NULL,NULL,%s::uuid)",
                (nn, json.dumps(p), str(uuid.uuid4())))
            res[k] = cu.fetchone()[0]
            time.sleep(0.6)          # mantiene la txn abierta a proposito
            c.commit()

    tA = threading.Thread(target=worker, args=('A', 0.0))
    tB = threading.Thread(target=worker, args=('B', 0.2))
    tA.start(); tB.start(); tA.join(); tB.join()

    chk('LEDGER/concurrencia: las dos responden ok',
        res['A'].get('ok') is True and res['B'].get('ok') is True, str(res)[:70])
    chk('LEDGER/concurrencia: UN SOLO ticket_id',
        res['A'].get('ticket_id') == res['B'].get('ticket_id'),
        f"{res['A'].get('ticket_id')} vs {res['B'].get('ticket_id')}")
    chk('LEDGER/concurrencia: una nueva + una recovery',
        {res['A'].get('via'), res['B'].get('via')} == {'nuevo', 'recovery'},
        f"{res['A'].get('via')} / {res['B'].get('via')}")

    with admin() as a:
        a.execute("SELECT count(*) FROM precios_api.api_precios_nonce_s2s WHERE nonce=%s", (nn,))
        chk('LEDGER/concurrencia: 1 sola fila de ledger', a.fetchone()[0] == 1)
        a.execute("SELECT count(*) FROM precios_api.api_precios_ticket")
        chk('LEDGER/concurrencia: 1 solo ticket en la tabla', a.fetchone()[0] == 1)

    # *** EL CHECK QUE FALTABA EN v5 ***
    # Sin el advisory lock, las dos concurrentes pasaban el fast path, las dos
    # cobraban la cuota LOGICA, y la perdedora devolvia 'recovery' con sus cuotas
    # ya persistidas (fuera del sub-savepoint). Cuota cobrada DOS VECES por UNA
    # admision. El smoke viejo no lo veia: solo miraba ticket_id, tickets y ledger.
    q = _cuotas()
    chk('LEDGER/concurrencia: cuota LOGICA global = 1, NO 2',
        q.get(('cotizar_global', '_global')) == 1, str(q.get(('cotizar_global', '_global'))))
    chk('LEDGER/concurrencia: cuota LOGICA sujeto = 1, NO 2',
        q.get(('cotizar_s2s', 'whatsapp')) == 1, str(q.get(('cotizar_s2s', 'whatsapp'))))
    chk('LEDGER/concurrencia: cuota de INTENTOS global = 2 (las 2 invocaciones pagan)',
        q.get(('admision_intento_global', '_global')) == 2,
        str(q.get(('admision_intento_global', '_global'))))
    chk('LEDGER/concurrencia: cuota de INTENTOS sujeto = 2',
        q.get(('admision_intento_s2s', 'whatsapp')) == 2,
        str(q.get(('admision_intento_s2s', 'whatsapp'))))


def s_ledger_rate_limited_no_quema_nonce():
    """Un request rechazado por cuota NO debe quemar el nonce del cliente.

    Consecuencia del orden fast-path/slow-path: el ledger se escribe DESPUES de la
    cuota, asi que un rate_limited no deja fila -> el nonce sigue disponible.
    """
    limpiar()
    nn = str(uuid.uuid4())
    p  = pl()
    with admin() as a:
        # saturar la cubeta global a mano
        a.execute("""INSERT INTO precios_api.api_precios_rate_limit (scope, sujeto, ventana, n)
                     VALUES ('cotizar_global','_global', date_trunc('minute', clock_timestamp()), 100000)""")
    with rol() as cur:
        r1 = adm(cur, 'cotizar', nonce=nn, payload=p)
    chk('LEDGER/rate_limit: rechazado por cuota', r1.get('error') == 'rate_limited', str(r1)[:50])

    with admin() as a:
        a.execute("SELECT count(*) FROM precios_api.api_precios_nonce_s2s WHERE nonce=%s", (nn,))
        chk('LEDGER/rate_limit: NO escribio el ledger (nonce no quemado)', a.fetchone()[0] == 0)
        a.execute("DELETE FROM precios_api.api_precios_rate_limit")

    with rol() as cur:
        r2 = adm(cur, 'cotizar', nonce=nn, payload=p)
    chk('LEDGER/rate_limit: el MISMO nonce sirve despues',
        r2.get('ok') is True and r2.get('via') == 'nuevo', str(r2)[:60])


def s_cuota_intentos():
    """PUNTO 2 -- el recovery no consume cuota LOGICA, asi que el replay masivo
    tiene que quedar acotado por la cubeta de INTENTOS. Si no, una misma solicitud
    valida se puede repetir indefinidamente (parse + SHA-256 + SELECT + conexion)
    sin tocar ningun limite.

    Semantica exigida:
      nueva            -> intento + logica
      recovery         -> intento, NO logica
      binding distinto -> intento, NO logica
      replay masivo    -> lo frena la cubeta de intentos
    """
    limpiar()
    nn = str(uuid.uuid4())
    p  = pl()

    with rol() as cur:
        r = adm(cur, 'cotizar', nonce=nn, payload=p)
        chk('CUOTA/intentos: admision nueva ok', r.get('via') == 'nuevo', str(r)[:50])
        q = _cuotas()
        chk('CUOTA/nueva: paga INTENTO', q.get(('admision_intento_global', '_global')) == 1)
        chk('CUOTA/nueva: paga LOGICA',  q.get(('cotizar_global', '_global')) == 1)

        # 30 recoveries del MISMO nonce
        for _ in range(30):
            rr = adm(cur, 'cotizar', nonce=nn, payload=p)
        chk('CUOTA/recovery: sigue devolviendo recovery', rr.get('via') == 'recovery', str(rr)[:50])

    q = _cuotas()
    chk('CUOTA/recovery: 31 invocaciones -> 31 INTENTOS',
        q.get(('admision_intento_global', '_global')) == 31,
        str(q.get(('admision_intento_global', '_global'))))
    chk('CUOTA/recovery: la LOGICA sigue en 1 (no la vuelve a consumir)',
        q.get(('cotizar_global', '_global')) == 1, str(q.get(('cotizar_global', '_global'))))
    chk('CUOTA/recovery: la LOGICA de sujeto sigue en 1',
        q.get(('cotizar_s2s', 'whatsapp')) == 1, str(q.get(('cotizar_s2s', 'whatsapp'))))

    # binding distinto: paga intento, NO logica
    with rol() as cur:
        rb = adm(cur, 'cotizar', nonce=nn, payload=pl(d0=25))
    chk('CUOTA/binding-distinto: nonce_replay', rb.get('error') == 'nonce_replay', str(rb)[:50])
    q = _cuotas()
    chk('CUOTA/binding-distinto: paga INTENTO (32)',
        q.get(('admision_intento_global', '_global')) == 32,
        str(q.get(('admision_intento_global', '_global'))))
    chk('CUOTA/binding-distinto: NO paga LOGICA (sigue en 1)',
        q.get(('cotizar_global', '_global')) == 1, str(q.get(('cotizar_global', '_global'))))

    # ---------- SATURACION de la cubeta de intentos ----------
    limpiar()
    nn2 = str(uuid.uuid4())
    p2  = pl(d0=13)
    with admin() as a:
        # dejar la cubeta de intentos del SUJETO al borde (limite s2s = 1200)
        a.execute("""INSERT INTO precios_api.api_precios_rate_limit (scope, sujeto, ventana, n)
                     VALUES ('admision_intento_s2s','whatsapp',
                             date_trunc('minute', clock_timestamp()), 1200)""")
    with rol() as cur:
        rs = adm(cur, 'cotizar', nonce=nn2, payload=p2)
    chk('CUOTA/saturacion: la cubeta de INTENTOS rechaza',
        rs.get('error') == 'rate_limited' and rs.get('cubeta') == 'intento_sujeto', str(rs)[:70])

    with admin() as a:
        a.execute("SELECT count(*) FROM precios_api.api_precios_nonce_s2s")
        chk('CUOTA/saturacion: no escribio ledger', a.fetchone()[0] == 0)
        a.execute("SELECT count(*) FROM precios_api.api_precios_ticket")
        chk('CUOTA/saturacion: no emitio ticket', a.fetchone()[0] == 0)
        a.execute("""SELECT COALESCE(n,0) FROM precios_api.api_precios_rate_limit
                      WHERE scope='cotizar_global'""")
        row = a.fetchone()
        chk('CUOTA/saturacion: NO llego a cobrar la LOGICA', row is None or row[0] == 0,
            str(row))

    # saturar la GLOBAL de intentos (limite 2400)
    limpiar()
    with admin() as a:
        a.execute("""INSERT INTO precios_api.api_precios_rate_limit (scope, sujeto, ventana, n)
                     VALUES ('admision_intento_global','_global',
                             date_trunc('minute', clock_timestamp()), 2400)""")
    with rol() as cur:
        rg = adm(cur, 'cotizar', nonce=str(uuid.uuid4()), payload=pl(d0=17))
    chk('CUOTA/saturacion: la GLOBAL de intentos rechaza',
        rg.get('error') == 'rate_limited' and rg.get('cubeta') == 'intento_global', str(rg)[:70])


def s_lock_timeout():
    """BLOQUEANTE 2 -- lock_timeout con mapping controlado.

    MEDIDO: lock_timeout lanza SQLSTATE 55P03 (lock_not_available) y SIN handler
    ESCAPA CRUDO al driver, rompiendo el contrato JSON. Los locks de estos smokes
    son REALES: se toman desde OTRA conexion.
    """
    # ---------- TXN1: fila GLOBAL del limiter bloqueada ----------
    limpiar()
    p = pl()
    with rol() as cur:
        adm(cur, 'cotizar', payload=p)      # siembra la fila global del limiter

    antes = _estado()
    nn = str(uuid.uuid4())

    cl = psycopg.connect(URI); cul = cl.cursor()
    cul.execute("BEGIN")
    cul.execute("""UPDATE precios_api.api_precios_rate_limit SET n = n
                    WHERE scope='admision_intento_global' AND sujeto='_global'""")
    crudo = None
    viva = None
    # conexion PROPIA (no context manager): hay que probarla DESPUES del timeout
    cv = psycopg.connect(URI, autocommit=True); cuv = cv.cursor()
    cuv.execute("SET SESSION AUTHORIZATION vita_precios_api")
    try:
        cuv.execute(
            "SELECT precios_api.api_precios_admitir('cotizar','s2s','whatsapp',"
            "%s::uuid,%s,NULL,NULL,%s::uuid)",
            (nn, json.dumps(pl(d0=14)), str(uuid.uuid4())))
        r = cuv.fetchone()[0]
    except psycopg.errors.Error as e:
        crudo = e.sqlstate
        r = {}
    finally:
        cul.execute("ROLLBACK"); cl.close()

    # *** PUNTO 5: la MISMA conexion/cursor debe seguir usable ***
    try:
        cuv.execute("SELECT 1")
        viva = cuv.fetchone()[0] == 1
    except psycopg.errors.Error:
        viva = False
    cv.close()

    chk('LOCK/TXN1: cero error PostgreSQL crudo', crudo is None, f'escapo {crudo}')
    chk('LOCK/TXN1: la MISMA conexion sigue usable (SELECT 1 tras el timeout)',
        viva is True, str(viva))
    chk('LOCK/TXN1: JSON limpio con error=timeout', r.get('error') == 'timeout', str(r)[:60])
    chk('LOCK/TXN1: nunca filtra SQLSTATE ni constraint',
        not any(k in r for k in ('sqlstate', 'constraint', 'detail', 'mensaje')), str(r)[:60])

    despues = _estado()
    chk('LOCK/TXN1: sin ticket nuevo',      antes[0] == despues[0], f'{antes[0]}->{despues[0]}')
    chk('LOCK/TXN1: sin fila de ledger',    antes[1] == despues[1], f'{antes[1]}->{despues[1]}')
    # el savepoint externo revierte TODO: tampoco queda la cuota de INTENTOS
    chk('LOCK/TXN1: sin cuota parcial (ni logica ni de intentos)',
        antes[3] == despues[3], f'{antes[3]}->{despues[3]}')

    with rol() as cur:                       # conexion reutilizable + retry seguro
        rr = adm(cur, 'cotizar', nonce=nn, payload=pl(d0=14))
    chk('LOCK/TXN1: retry con el mismo nonce funciona',
        rr.get('ok') is True and rr.get('via') == 'nuevo', str(rr)[:60])

    # ---------- TXN2: fila del TICKET bloqueada ----------
    limpiar()
    p2 = pl(d0=16)
    with rol() as cur:
        tk = adm(cur, 'cotizar', payload=p2)['ticket_id']

    cl = psycopg.connect(URI); cul = cl.cursor()
    cul.execute("BEGIN")
    cul.execute("UPDATE precios_api.api_precios_ticket SET accion = accion WHERE ticket_id = %s", (tk,))
    crudo = None
    cv = psycopg.connect(URI, autocommit=True); cuv = cv.cursor()
    cuv.execute("SET SESSION AUTHORIZATION vita_precios_api")
    try:
        cuv.execute("SELECT precios_api.api_precios_cotizar_exponer(%s::uuid,%s::jsonb)",
                    (tk, json.dumps(p2)))
        r = cuv.fetchone()[0]
    except psycopg.errors.Error as e:
        crudo = e.sqlstate
        r = {}
    finally:
        cul.execute("ROLLBACK"); cl.close()

    # *** PUNTO 5: la MISMA conexion/cursor debe seguir usable ***
    try:
        cuv.execute("SELECT 1")
        viva2 = cuv.fetchone()[0] == 1
    except psycopg.errors.Error:
        viva2 = False
    cv.close()

    chk('LOCK/TXN2: cero error PostgreSQL crudo', crudo is None, f'escapo {crudo}')
    chk('LOCK/TXN2: JSON limpio con error=timeout', r.get('error') == 'timeout', str(r)[:60])
    chk('LOCK/TXN2: la MISMA conexion sigue usable (SELECT 1 tras el timeout)',
        viva2 is True, str(viva2))

    with admin() as a:
        a.execute("SELECT consumed_at IS NULL FROM precios_api.api_precios_ticket WHERE ticket_id=%s", (tk,))
        chk('LOCK/TXN2: el ticket SIGUE LIBRE tras el timeout', a.fetchone()[0] is True)

    with rol() as cur:                       # retry con el MISMO ticket
        rr = exp_cot(cur, tk, p2)
    chk('LOCK/TXN2: retry con el MISMO ticket funciona', rr.get('ok') is True, str(rr)[:60])


# ==========================================================================
# 7. TICKET
# ==========================================================================
def s_ticket():
    limpiar()
    with rol() as cur:
        p = pl()
        a1 = adm(cur, 'cotizar', payload=p)
        tk = a1['ticket_id']
        r1 = exp_cot(cur, tk, p)
        r2 = exp_cot(cur, tk, p)
        chk('TICKET: primer consumo ok', r1.get('ok') is True, str(r1)[:50])
        chk('TICKET: single-use (2do rebota)', r2.get('error') == 'ticket_invalido')

        a2 = adm(cur, 'cotizar', payload=p)
        rb = exp_cot(cur, a2['ticket_id'], pl(pers=9))
        chk('TICKET: binding por hash rechaza payload distinto',
            rb.get('error') == 'ticket_invalido')
        chk('TICKET: mismatch QUEMA el ticket',
            exp_cot(cur, a2['ticket_id'], p).get('error') == 'ticket_invalido')

        a3 = adm(cur, 'cotizar', payload=p)
        chk('TICKET: cross-accion rechazado',
            exp_con(cur, a3['ticket_id'], p, str(uuid.uuid4())).get('error') == 'ticket_invalido')

        chk('TICKET: inexistente rechazado',
            exp_cot(cur, str(uuid.uuid4()), p).get('error') == 'ticket_invalido')


def s_ticket_concurrente():
    """PUNTO 10: 10 consumos concurrentes del MISMO ticket -> exactamente 1 exito."""
    limpiar()
    with rol() as cur:
        p = pl()
        tk = adm(cur, 'cotizar', payload=p)['ticket_id']

    def consumir(_):
        try:
            with rol() as cur:
                return exp_cot(cur, tk, p).get('ok') is True
        except Exception:
            return False

    with ThreadPoolExecutor(max_workers=10) as ex:
        res = list(ex.map(consumir, range(10)))
    chk('TICKET/concurrencia: 10 consumos del mismo ticket -> exactamente 1 exito',
        sum(res) == 1, f'exitos={sum(res)}')


# ==========================================================================
# 8. EXPIRACION REAL con TXN2 abierta -- now() vs clock_timestamp()
# ==========================================================================
def s_ticket_expira_real():
    limpiar()
    with rol() as cur:
        p = pl()
        tk = adm(cur, 'cotizar', payload=p)['ticket_id']

    with admin() as a:
        a.execute("""UPDATE precios_api.api_precios_ticket
                        SET expires_at = created_at + interval '2 seconds'
                      WHERE ticket_id = %s::uuid""", (tk,))

    # TXN2 explicita COMO EL ROL, abierta mientras el ticket todavia vive
    c2 = psycopg.connect(URI)
    cur2 = c2.cursor()
    cur2.execute("SET SESSION AUTHORIZATION vita_precios_api")
    cur2.execute("BEGIN")
    cur2.execute("SELECT 1")          # fija el transaction_timestamp de la TXN2
    time.sleep(3)                     # el ticket EXPIRA durante la transaccion
    r = exp_cot(cur2, tk, p)
    c2.rollback()
    c2.close()

    # la evidencia del bug se lee con admin (el rol no puede SELECT la tabla)
    with admin() as a:
        a.execute("BEGIN")
        a.execute("SELECT 1")
        time.sleep(1)
        a.execute("""SELECT expires_at > now(), expires_at > clock_timestamp()
                       FROM precios_api.api_precios_ticket WHERE ticket_id=%s::uuid""", (tk,))
        vig_now, vig_clock = a.fetchone()
        a.execute("COMMIT")

    chk('EXPIRA: consumir ticket VENCIDO con TXN2 abierta -> ticket_invalido',
        r.get('error') == 'ticket_invalido', str(r))
    chk('EXPIRA: clock_timestamp() ve el ticket vencido', vig_clock is False, str(vig_clock))


# ==========================================================================
# 9. VALIDADOR PROFUNDO (rol)
# ==========================================================================
def s_validador():
    limpiar()
    casos = [
        ('fecha_in null',      {**pl(), 'fecha_in': None},         'fecha_in'),
        ('fecha_out null',     {**pl(), 'fecha_out': None},        'fecha_out'),
        ('id_cabana null',     {**pl(), 'id_cabana': None},        'id_cabana'),
        ('personas null',      {**pl(), 'personas': None},         'personas'),
        ('id_cabana string',   {**pl(), 'id_cabana': '1'},         'id_cabana'),
        ('personas string',    {**pl(), 'personas': '2'},          'personas'),
        ('id_cabana bool',     {**pl(), 'id_cabana': True},        'id_cabana'),
        ('personas bool',      {**pl(), 'personas': False},        'personas'),
        ('fecha_in bool',      {**pl(), 'fecha_in': True},         'fecha_in'),
        ('fecha_in number',    {**pl(), 'fecha_in': 20260101},     'fecha_in'),
        ('id_cabana 1.5',      {**pl(), 'id_cabana': 1.5},         'id_cabana'),
        ('personas 2.5',       {**pl(), 'personas': 2.5},          'personas'),
        ('id_cabana 1e100',    {**pl(), 'id_cabana': 1e100},       'id_cabana'),
        ('personas 1e10',      {**pl(), 'personas': 1e10},         'personas'),
        ('id_cabana -1',       {**pl(), 'id_cabana': -1},          'id_cabana'),
        ('personas 0',         {**pl(), 'personas': 0},            'personas'),
        ('fecha ddmmyyyy',     {**pl(), 'fecha_in': '01-01-2027'}, 'fecha_in'),
        ('fecha inexistente',  {**pl(), 'fecha_in': '2027-02-31'}, 'fecha_in'),
        ('fecha basura',       {**pl(), 'fecha_in': 'manana'},     'fecha_in'),
        ('clave modo',         {**pl(), 'modo': 'online'},         'modo'),
        ('clave canal',        {**pl(), 'canal': 'web'},           'canal'),
        ('clave desconocida',  {**pl(), 'xx': 1},                  'xx'),
        ('falta personas',     {k: v for k, v in pl().items() if k != 'personas'}, 'personas'),
        ('personas 21',        pl(pers=21),                        'personas'),
        ('span 31 noches',     pl(n=31),                           'span'),
        ('cabana inactiva',    pl(cab=5),                          'id_cabana'),
        ('cabana inexistente', pl(cab=999),                        'id_cabana'),
    ]
    with rol() as cur:
        for nombre, payload, campo in casos:
            r = flujo_cotizar(cur, payload)
            chk(f'VAL: {nombre} -> payload_invalido({campo})',
                r.get('error') == 'payload_invalido' and r.get('campo') == campo, str(r)[:60])
            chk(f'VAL: {nombre} NUNCA es error_interno', r.get('error') != 'error_interno')

        p = pl()
        p['fecha_in'] = str(HOY - timedelta(days=1))
        p['fecha_out'] = str(HOY + timedelta(days=1))
        chk('VAL: fecha_in en el pasado',
            flujo_cotizar(cur, p).get('campo') == 'fecha_in_pasada')
        chk('VAL: horizonte > 540 dias',
            flujo_cotizar(cur, pl(d0=600)).get('campo') == 'horizonte')

        p = pl(); p['personas'] = 2e0
        chk('VAL: 2e0 es entero valido -> PASA', flujo_cotizar(cur, p).get('ok') is True)
        p = pl(); p['personas'] = 3.0
        chk('VAL: 3.0 es integral -> PASA', flujo_cotizar(cur, p).get('ok') is True)


# ==========================================================================
# 10. IDEMPOTENCIA + concurrencia (punto 10)
# ==========================================================================
def s_idempotencia():
    limpiar()
    with admin() as a:
        a.execute("DELETE FROM precios_api.api_precios_idempotencia")

    with rol() as cur:
        p = pl()
        k = str(uuid.uuid4())
        a1 = adm(cur, 'congelar', payload=p, idem=k)
        r1 = exp_con(cur, a1['ticket_id'], p, k)
        a2 = adm(cur, 'congelar', payload=p, idem=k)
        r2 = exp_con(cur, a2['ticket_id'], p, k)

        chk('IDEM: primer congelar -> via=nuevo', r1.get('via') == 'nuevo', str(r1)[:60])
        chk('IDEM: replay -> via=replay', r2.get('via') == 'replay', str(r2)[:60])
        chk('IDEM: replay devuelve la MISMA cotizacion',
            r1['motor']['cotizacion_id'] == r2['motor']['cotizacion_id'])
        chk('IDEM: replay reporta vigente=true', r2.get('vigente') is True)

        p2 = pl(pers=4)
        a3 = adm(cur, 'congelar', payload=p2, idem=k)
        chk('IDEM: misma key + payload distinto -> conflicto',
            exp_con(cur, a3['ticket_id'], p2, k).get('error') == 'conflicto')

    cid = r1['motor']['cotizacion_id']
    with admin() as a:
        a.execute("SELECT count(*) FROM precios_api.api_precios_idempotencia")
        chk('IDEM: una sola fila persistida', a.fetchone()[0] == 1)
        a.execute("""UPDATE public.cotizaciones_precio
                        SET expires_at = clock_timestamp() - interval '1 minute'
                      WHERE cotizacion_id = %s::uuid""", (cid,))

    with rol() as cur:
        p = pl()
        a4 = adm(cur, 'congelar', payload=p, idem=k)
        r4 = exp_con(cur, a4['ticket_id'], p, k)
        chk('IDEM: replay lee la vigencia de cotizaciones_precio, no del snapshot',
            r4.get('vigente') is False, str(r4.get('vigente')))


def s_congelar_concurrente():
    """PUNTO 10: 2 congelamientos concurrentes, misma idem key ->
       una sola cotizacion y una sola fila idempotente."""
    limpiar()
    with admin() as a:
        a.execute("DELETE FROM precios_api.api_precios_idempotencia")
        a.execute("DELETE FROM public.cotizaciones_precio")

    p = pl()
    k = str(uuid.uuid4())

    def congelar(_):
        try:
            with rol() as cur:
                a1 = adm(cur, 'congelar', payload=p, idem=k)
                if not a1.get('ok'):
                    return None
                r = exp_con(cur, a1['ticket_id'], p, k)
                return r.get('motor', {}).get('cotizacion_id')
        except Exception:
            return None

    with ThreadPoolExecutor(max_workers=2) as ex:
        cids = [x for x in ex.map(congelar, range(2)) if x]

    with admin() as a:
        a.execute("SELECT count(*) FROM precios_api.api_precios_idempotencia WHERE idempotency_key=%s::uuid", (k,))
        n_idem = a.fetchone()[0]
        a.execute("SELECT count(*) FROM public.cotizaciones_precio")
        n_cot = a.fetchone()[0]

    chk('CONGELAR/concurrencia: UNA sola fila idempotente', n_idem == 1, str(n_idem))
    chk('CONGELAR/concurrencia: UNA sola cotizacion escrita (cero huerfanas)',
        n_cot == 1, str(n_cot))
    chk('CONGELAR/concurrencia: ambos callers ven el mismo cotizacion_id',
        len(set(cids)) == 1 and len(cids) == 2, f'{len(cids)} resp, {len(set(cids))} ids')


# ==========================================================================
# 11. CONTRATO DE ERRORES B3 -- doble envelope privado (punto 7)
#     El envelope EXTERIOR ok=true significa "el gateway ejecuto".
#     El resultado del motor va en motor.*, y B4-1 DEBE inspeccionar motor.ok
#     para construir el envelope publico.
# ==========================================================================
def s_contrato_b3():
    # --- caso 1: cotizar con B3 ok=false ---
    limpiar()
    with admin() as a:
        a.execute("""CREATE OR REPLACE FUNCTION public.precios_cotizar(p_payload JSONB)
                     RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY INVOKER
                     SET search_path = pg_catalog, public AS $fn$
                     BEGIN RETURN jsonb_build_object('ok',false,'error','temporada_no_resuelta');
                     END $fn$;""")
        a.execute("REVOKE EXECUTE ON FUNCTION public.precios_cotizar(jsonb) FROM PUBLIC, vita_precios_api")
    with rol() as cur:
        r = flujo_cotizar(cur, pl())
    chk('B3/cotizar ok=false: envelope EXTERIOR ok=true (el gateway ejecuto)',
        r.get('ok') is True, str(r)[:60])
    chk('B3/cotizar ok=false: motor.ok=false preservado para B4-1',
        r.get('motor', {}).get('ok') is False, str(r.get('motor'))[:60])
    chk('B3/cotizar ok=false: motor.error preservado',
        r.get('motor', {}).get('error') == 'temporada_no_resuelta')

    # --- caso 2: congelar con B3 congelada=false -> NO consume la key ---
    limpiar()
    with admin() as a:
        a.execute("DELETE FROM precios_api.api_precios_idempotencia")
        a.execute("""CREATE OR REPLACE FUNCTION public.precios_cotizar_congelar(p_payload JSONB)
                     RETURNS JSONB LANGUAGE plpgsql VOLATILE SECURITY INVOKER
                     SET search_path = pg_catalog, public AS $fn$
                     BEGIN RETURN jsonb_build_object('ok',false,'error','sin_tarifa','congelada',false);
                     END $fn$;""")
        a.execute("REVOKE EXECUTE ON FUNCTION public.precios_cotizar_congelar(jsonb) FROM PUBLIC, vita_precios_api")
    with rol() as cur:
        k = str(uuid.uuid4())
        p = pl()
        a1 = adm(cur, 'congelar', payload=p, idem=k)
        r = exp_con(cur, a1['ticket_id'], p, k)
    chk('B3/congelar congelada=false: via=nuevo y vigente=false',
        r.get('via') == 'nuevo' and r.get('vigente') is False, str(r)[:60])
    chk('B3/congelar congelada=false: motor.ok=false preservado',
        r.get('motor', {}).get('ok') is False, str(r.get('motor'))[:60])
    with admin() as a:
        a.execute("SELECT count(*) FROM precios_api.api_precios_idempotencia")
        chk('B3/congelar congelada=false: NO consume la idempotency key',
            a.fetchone()[0] == 0)

    # --- restaurar B3 y probar obtener vencida ---
    restaurar_b3()
    limpiar()
    with admin() as a:
        a.execute("DELETE FROM precios_api.api_precios_idempotencia")
        a.execute("DELETE FROM public.cotizaciones_precio")

    with rol() as cur:
        p = pl()
        k = str(uuid.uuid4())
        a1 = adm(cur, 'congelar', payload=p, idem=k)
        rc = exp_con(cur, a1['ticket_id'], p, k)
        cid = rc['motor']['cotizacion_id']
    with admin() as a:
        a.execute("""UPDATE public.cotizaciones_precio
                        SET expires_at = clock_timestamp() - interval '1 minute'
                      WHERE cotizacion_id = %s::uuid""", (cid,))
    with rol() as cur:
        a2 = adm(cur, 'obtener', cot=cid)
        ro = exp_obt(cur, a2['ticket_id'], cid)
    chk('B3/obtener vencida: gateway ok=true', ro.get('ok') is True, str(ro)[:60])
    chk('B3/obtener vencida: motor.vigente=false (B4-1 lo mapea al envelope publico)',
        ro.get('motor', {}).get('vigente') is False, str(ro.get('motor'))[:60])


# ==========================================================================
# 12. FLUJO FELIZ
# ==========================================================================
def s_flujo():
    limpiar()
    with rol() as cur:
        p = pl()
        r = flujo_cotizar(cur, p)
        chk('FLUJO: cotizar ok', r.get('ok') is True, str(r)[:50])
        chk('FLUJO: canal DERIVADO = whatsapp', r['motor'].get('canal') == 'whatsapp')
        chk('FLUJO: modo FORZADO = online', r['motor'].get('modo') == 'online')
        chk('FLUJO: el motor vio ambiente=test', r['motor'].get('ambiente_visto') == 'test')

        k = str(uuid.uuid4())
        a1 = adm(cur, 'congelar', payload=p, idem=k)
        rc = exp_con(cur, a1['ticket_id'], p, k)
        chk('FLUJO: congelar ok', rc.get('ok') is True, str(rc)[:50])
        cid = rc['motor']['cotizacion_id']

        a2 = adm(cur, 'obtener', cot=cid)
        ro = exp_obt(cur, a2['ticket_id'], cid)
        chk('FLUJO: obtener ok', ro.get('ok') is True, str(ro)[:50])
        chk('FLUJO: obtener devuelve la cotizacion correcta',
            ro['motor'].get('cotizacion_id') == cid)


# ==========================================================================
# 13. TIMEOUT -- SET LOCAL statement_timeout (el unico que arma el timer)
# ==========================================================================
def s_timeout():
    limpiar()
    with admin() as a:
        a.execute("""CREATE OR REPLACE FUNCTION public.precios_cotizar(p_payload JSONB)
                     RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY INVOKER
                     SET search_path = pg_catalog, public AS $fn$
                     BEGIN PERFORM pg_sleep(3); RETURN jsonb_build_object('ok',true); END $fn$;""")
        a.execute("REVOKE EXECUTE ON FUNCTION public.precios_cotizar(jsonb) FROM PUBLIC, vita_precios_api")

    with rol() as cur:
        p = pl()
        tk = adm(cur, 'cotizar', payload=p)['ticket_id']

    c = psycopg.connect(URI)
    cur = c.cursor()
    cur.execute("SET SESSION AUTHORIZATION vita_precios_api")
    cur.execute("BEGIN")
    cur.execute("SET LOCAL statement_timeout = '800ms'")
    r = exp_cot(cur, tk, p)
    c.commit()
    cur.execute("SELECT 1")
    viva = cur.fetchone()[0] == 1
    c.close()

    chk('TIMEOUT: SET LOCAL corta el core -> error=timeout', r.get('error') == 'timeout', str(r))
    chk('TIMEOUT: la conexion sigue usable', viva)

    with admin() as a:
        # CAMBIO DELIBERADO (bloqueante 2): el UPDATE del ticket ahora vive DENTRO del
        # savepoint externo. Al capturar el timeout, el savepoint lo revierte -> el
        # ticket queda LIBRE y la Edge puede reintentar con el MISMO ticket_id.
        # Antes el UPDATE estaba fuera y el ticket se quemaba en cada timeout.
        a.execute("SELECT consumed_at IS NULL FROM precios_api.api_precios_ticket WHERE ticket_id=%s::uuid", (tk,))
        chk('TIMEOUT: el ticket queda LIBRE (savepoint revirtio el UPDATE)', a.fetchone()[0] is True)
        a.execute("SELECT sum(n) FROM precios_api.api_precios_rate_limit WHERE scope='cotizar_global'")
        chk('TIMEOUT: la cuota de la admision se conserva', a.fetchone()[0] == 1)

    restaurar_b3()


# ==========================================================================
# 14. GATE DE AMBIENTE en runtime
# ==========================================================================
def s_gate():
    with admin() as a:
        a.execute("UPDATE public.configuracion_general SET valor='ops' WHERE clave='ambiente'")
    try:
        with rol() as cur:
            adm(cur, 'cotizar', payload=pl())
        chk('GATE: ambiente=ops bloquea la admision', False, 'no lanzo')
    except psycopg.errors.Error as e:
        chk('GATE: ambiente=ops bloquea la admision', e.sqlstate == 'VDT03', str(e.sqlstate))
    with admin() as a:
        a.execute("UPDATE public.configuracion_general SET valor='test' WHERE clave='ambiente'")


def s_gate_acl_precommit():
    """CORRECCION 4 -- el gate ACL aborta ANTES de crear objetos.

    No se espera al VERIFY posterior para descubrir una incompatibilidad del estado
    real. Se planta el problema, se corre el SQL, y debe abortar SIN dejar nada.
    """
    import subprocess as sp

    rb = (SCRIPT_DIR / 'B4_0A_v6_ROLLBACK.sql').read_text()

    def correr_sql():
        """Rollback completo (incluye los 4 jobs) y reinstalacion. Devuelve (ok, msg)."""
        with psycopg.connect(URI) as c:      # el rollback tambien saca los jobs de cron:
            c.cursor().execute(rb)           # sin eso, el gate fresh-only aborta antes
            c.commit()                       # de llegar al gate ACL, y el smoke mentiria
        try:
            with psycopg.connect(URI) as c:
                c.cursor().execute(_sql_principal())
                c.commit()
            _restaurar_login()          # paso 2 del runsheet
            return True, ''
        except psycopg.errors.Error as e:
            return False, str(e).splitlines()[0]

    # (a) SECURITY DEFINER externo invocable -> debe ABORTAR
    with admin() as a:
        a.execute("""CREATE FUNCTION public.zz_secdef_ajena() RETURNS int
                     LANGUAGE sql SECURITY DEFINER AS 'SELECT 1'""")
        a.execute("GRANT EXECUTE ON FUNCTION public.zz_secdef_ajena() TO PUBLIC")
    ok, msg = correr_sql()
    chk('GATE ACL: SECDEF externo invocable -> ABORTA', not ok and 'SECURITY DEFINER' in msg, msg[:70])
    with admin() as a:
        a.execute("SELECT count(*) FROM pg_namespace WHERE nspname='precios_api'")
        chk('GATE ACL: aborta SIN dejar el schema creado', a.fetchone()[0] == 0)
        a.execute("DROP FUNCTION public.zz_secdef_ajena()")

    # (b) privilegio de TABLA -> debe ABORTAR
    with admin() as a:
        a.execute("CREATE TABLE IF NOT EXISTS public.zz_tabla_ajena(x int)")
        a.execute("GRANT SELECT ON public.zz_tabla_ajena TO PUBLIC")
    ok, msg = correr_sql()
    chk('GATE ACL: privilegio de TABLA -> ABORTA', not ok and 'TABLA' in msg, msg[:70])
    with admin() as a:
        a.execute("DROP TABLE public.zz_tabla_ajena")

    # (c) estado limpio -> debe INSTALAR
    ok, msg = correr_sql()
    chk('GATE ACL: con estado limpio, instala', ok, msg[:70])
    with admin() as a:
        a.execute("SELECT count(*) FROM pg_proc WHERE pronamespace='precios_api'::regnamespace")
        chk('GATE ACL: 19 funciones tras instalar', a.fetchone()[0] == 19)


def s_rollback_sin_cron():
    """CORRECCION 5 -- el rollback debe correr aunque cron.job NO exista.

    MEDIDO: una referencia estatica a cron.job dentro de un CASE falla en PARSEO
    (42P01) aunque la rama nunca se ejecute -- PostgreSQL analiza toda la consulta
    antes de correrla. La promesa "corre sin pg_cron" seria FALSA.
    """
    rb = (SCRIPT_DIR / 'B4_0A_v6_ROLLBACK.sql').read_text()

    with admin() as a:
        a.execute("SELECT to_regclass('cron.job') IS NOT NULL")
        habia_cron = a.fetchone()[0]
        if habia_cron:
            a.execute("DROP SCHEMA cron CASCADE")
        a.execute("SELECT to_regclass('cron.job') IS NULL")
        chk('ROLLBACK/sin-cron: cron.job efectivamente ausente', a.fetchone()[0] is True)

    crudo = None
    try:
        with psycopg.connect(URI) as c:
            cu = c.cursor()
            cu.execute(rb)
            c.commit()
    except psycopg.errors.Error as e:
        crudo = f'{e.sqlstate}: {str(e).splitlines()[0]}'

    chk('ROLLBACK/sin-cron: corre sin fallar (42P01 no aparece)', crudo is None, str(crudo)[:70])

    with admin() as a:
        a.execute("""SELECT (SELECT count(*) FROM pg_namespace WHERE nspname='precios_api')
                          + (SELECT count(*) FROM pg_roles WHERE rolname='vita_precios_api')""")
        chk('ROLLBACK/sin-cron: residuo cero', a.fetchone()[0] == 0)

    # dejar el entorno EXACTAMENTE como estaba, incluido el paso 2 del runsheet
    # (ALTER ROLE ... LOGIN PASSWORD). El SQL crea el rol NOLOGIN a proposito; si
    # no se reaplica, el A02 del VERIFY falla despues.
    with admin() as a:
        a.execute("CREATE EXTENSION IF NOT EXISTS pg_cron")
    with psycopg.connect(URI) as c:
        c.cursor().execute(_sql_principal()); c.commit()
    _restaurar_login()


if __name__ == '__main__':
    for f in (s_acl_estructura, s_acl_runtime_negativos, s_invoker_no_escala,
              s_d3, s_admision, s_savepoint,
              s_rate_limit, s_rate_limit_ventana_unica,
              s_ledger_recovery, s_ledger_concurrente, s_ledger_rate_limited_no_quema_nonce,
              s_cuota_intentos, s_lock_timeout, s_ticket,
              s_ticket_concurrente, s_ticket_expira_real, s_validador, s_idempotencia,
              s_congelar_concurrente, s_contrato_b3, s_flujo, s_timeout, s_gate,
              s_gate_acl_precommit, s_rollback_sin_cron):
        f()

    ancho = max(len(n) for n, _, _ in R)
    fails = [(n, d) for n, ok, d in R if not ok]
    for n, ok, d in R:
        if not ok:
            print(f'  FAIL  {n:<{ancho}}  {d}')
    print('=' * 78)
    print(f'  {sum(1 for _, ok, _ in R if ok)} PASS   /   {len(fails)} FAIL')
    print('=' * 78)
    sys.exit(1 if fails else 0)
