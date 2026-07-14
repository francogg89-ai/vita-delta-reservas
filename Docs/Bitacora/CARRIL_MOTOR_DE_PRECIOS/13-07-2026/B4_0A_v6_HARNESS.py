#!/usr/bin/env python3
"""
B4_0A_v6_HARNESS.py  (v6 -- post-auditoria 6)  -- Levanta un PostgreSQL REAL y lo deja en el estado de
TEST justo ANTES de B4-0A. Base para B4_0A_v6_SMOKES.py, el VERIFY y el ROLLBACK.

PORTABLE: no hay rutas absolutas. Todo cuelga de la carpeta del script o de
variables de entorno:
    B4_PGDATA   directorio de datos    (default: <script_dir>/.pgdata_b4)
    B4_URI_FILE archivo con la URI     (default: <script_dir>/.b4_uri)

DEPENDENCIAS (ver B4_0A_v6_requirements.txt):
    pgserver >= 0.1.4
    psycopg[binary] >= 3.1

pg_cron: el PostgreSQL embebido de pgserver NO trae pg_cron. Este harness
registra un STUB COMPATIBLE como extension real: reproduce el esquema de
cron.job y las firmas de cron.schedule / cron.unschedule con semantica
transaccional (INSERT normal), suficiente para ejercitar el preflight, el
scheduling dentro de la transaccion y el VERIFY de jobs. NO es la implementacion
real de pg_cron; el comportamiento del bgworker no se simula.

btree_gist tampoco esta -> las 13 precios_* son STUBS. El fingerprint real
098f2fe7... solo puede matchear en TEST.

Uso:  python3 B4_0A_v6_HARNESS.py [--reset]
"""
import os
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
PGDATA   = Path(os.environ.get('B4_PGDATA',   SCRIPT_DIR / '.pgdata_b4'))
URI_FILE = Path(os.environ.get('B4_URI_FILE', SCRIPT_DIR / '.b4_uri'))
SQL_B4   = SCRIPT_DIR / 'B4_0A_v6_ROL_TABLAS_FUNCIONES.sql'

# Password del harness. NO es la de TEST. Solo sirve para que exista un secreto
# en la fila del rol; los smokes usan SET SESSION AUTHORIZATION, no esta clave.
HARNESS_PWD = 'harness_only_no_es_la_de_test'

PGCRON_CONTROL = """comment = 'B4 harness -- stub compatible de pg_cron (no es la implementacion real)'
default_version = '1.6'
relocatable = false
schema = 'cron'
"""

PGCRON_SQL = r"""
CREATE TABLE cron.job (
  jobid    BIGSERIAL PRIMARY KEY,
  schedule TEXT    NOT NULL,
  command  TEXT    NOT NULL,
  nodename TEXT    NOT NULL DEFAULT 'localhost',
  nodeport INTEGER NOT NULL DEFAULT 5432,
  database TEXT    NOT NULL DEFAULT current_database(),
  username TEXT    NOT NULL DEFAULT CURRENT_USER,
  active   BOOLEAN NOT NULL DEFAULT true,
  jobname  TEXT
);
CREATE UNIQUE INDEX job_jobname_username_idx ON cron.job (jobname, username);

CREATE FUNCTION cron.schedule(job_name TEXT, schedule TEXT, command TEXT)
RETURNS BIGINT LANGUAGE plpgsql AS $fn$
DECLARE v_id BIGINT;
BEGIN
  INSERT INTO cron.job (jobname, schedule, command)
  VALUES (job_name, schedule, command)
  ON CONFLICT (jobname, username) DO UPDATE
     SET schedule = EXCLUDED.schedule, command = EXCLUDED.command, active = true
  RETURNING jobid INTO v_id;
  RETURN v_id;
END $fn$;

CREATE FUNCTION cron.unschedule(job_name TEXT)
RETURNS BOOLEAN LANGUAGE plpgsql AS $fn$
DECLARE v_n INTEGER;
BEGIN
  DELETE FROM cron.job WHERE jobname = job_name;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n = 0 THEN
    RAISE EXCEPTION 'could not find valid entry for job "%"', job_name;
  END IF;
  RETURN true;
END $fn$;

REVOKE ALL ON SCHEMA cron FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA cron FROM PUBLIC;
REVOKE ALL ON FUNCTION cron.schedule(TEXT,TEXT,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION cron.unschedule(TEXT) FROM PUBLIC;
"""

BASE = r"""
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon')          THEN CREATE ROLE anon NOLOGIN;          END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='service_role')  THEN CREATE ROLE service_role NOLOGIN;  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticator') THEN CREATE ROLE authenticator NOLOGIN; END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.configuracion_general (
  clave TEXT PRIMARY KEY, valor TEXT NOT NULL
);
INSERT INTO public.configuracion_general (clave, valor) VALUES ('ambiente','test')
  ON CONFLICT (clave) DO UPDATE SET valor = 'test';

CREATE TABLE IF NOT EXISTS public.cabanas (
  id_cabana BIGSERIAL PRIMARY KEY, nombre TEXT NOT NULL, activa BOOLEAN NOT NULL DEFAULT true
);
INSERT INTO public.cabanas (id_cabana, nombre, activa) VALUES
  (1,'Bamboo',true), (2,'Madre Selva',true), (3,'Arrebol',true),
  (4,'Guatemala',true), (5,'Tokio',false)
ON CONFLICT (id_cabana) DO UPDATE SET activa = EXCLUDED.activa;
SELECT setval('public.cabanas_id_cabana_seq', 5, true);

CREATE TABLE IF NOT EXISTS public.cotizaciones_precio (
  cotizacion_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  id_cabana BIGINT NOT NULL, fecha_in DATE NOT NULL, fecha_out DATE NOT NULL,
  personas INTEGER NOT NULL, canal TEXT NOT NULL, total NUMERIC(14,2) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
  expires_at TIMESTAMPTZ NOT NULL
);

-- Tablas B2A con las columnas que USAN los fingerprints canonicos. NO reproducen
-- la estructura real de TEST (los hashes canonicos solo matchean alla), pero
-- permiten EJERCITAR el algoritmo de preflight localmente.
CREATE TABLE IF NOT EXISTS public.perfiles_tarifarios (clave TEXT PRIMARY KEY);
CREATE TABLE IF NOT EXISTS public.tarifas_motor (
  id BIGSERIAL PRIMARY KEY,
  perfil          TEXT NOT NULL,
  temporada_clave TEXT NOT NULL,
  concepto        TEXT NOT NULL,
  precio          NUMERIC(14,2) NOT NULL,
  vigente_hasta   TIMESTAMPTZ);
CREATE TABLE IF NOT EXISTS public.temporada_vigencia (
  temporada_clave TEXT, anio INTEGER, fecha_in DATE, fecha_out_excl DATE);
CREATE TABLE IF NOT EXISTS public.noches_alta_demanda (fecha DATE PRIMARY KEY);
CREATE TABLE IF NOT EXISTS public.overrides_precio (id BIGSERIAL PRIMARY KEY);
CREATE TABLE IF NOT EXISTS public.precios_auditoria (id BIGSERIAL PRIMARY KEY);

-- 32 tarifas vigentes: 2 perfiles x 4 temporadas x 4 conceptos
TRUNCATE public.tarifas_motor;
INSERT INTO public.tarifas_motor (perfil, temporada_clave, concepto, precio, vigente_hasta)
SELECT p, t, c, (100000 + row_number() OVER ())::NUMERIC, NULL
  FROM unnest(ARRAY['grande','chica'])           AS p,
       unnest(ARRAY['baja','media','alta','pico']) AS t,
       unnest(ARRAY['semana_1','finde_completo','semana_completa','extra_persona_noche']) AS c;

-- 8 temporadas CONTINUAS (el preflight las exige sin huecos)
TRUNCATE public.temporada_vigencia;
INSERT INTO public.temporada_vigencia VALUES
  ('baja',2026,'2026-03-15','2026-07-01'), ('media',2026,'2026-07-01','2026-12-15'),
  ('alta',2027,'2026-12-15','2027-03-15'), ('baja',2027,'2027-03-15','2027-12-15'),
  ('alta',2028,'2027-12-15','2028-03-15'), ('baja',2028,'2028-03-15','2028-12-15'),
  ('alta',2029,'2028-12-15','2029-03-15'), ('baja',2029,'2029-03-15','2030-03-15');
"""

B3 = r"""
CREATE OR REPLACE FUNCTION public.precios_cotizar(p_payload JSONB)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path = pg_catalog, public
AS $fn$
DECLARE v_n INTEGER; v_tot NUMERIC; v_amb TEXT;
BEGIN
  SELECT valor INTO v_amb FROM configuracion_general WHERE clave = 'ambiente';
  v_n   := (p_payload->>'fecha_out')::DATE - (p_payload->>'fecha_in')::DATE;
  v_tot := v_n * 50000 + (p_payload->>'personas')::INTEGER * 1000;
  RETURN jsonb_build_object('ok', true, 'ambiente_visto', v_amb, 'noches', v_n,
    'total', v_tot, 'id_cabana', (p_payload->>'id_cabana')::BIGINT,
    'canal', p_payload->>'canal', 'modo', p_payload->>'modo');
END $fn$;

CREATE OR REPLACE FUNCTION public.precios_cotizar_congelar(p_payload JSONB)
RETURNS JSONB LANGUAGE plpgsql VOLATILE SECURITY INVOKER
SET search_path = pg_catalog, public
AS $fn$
DECLARE v_q JSONB; v_id UUID; v_exp TIMESTAMPTZ;
BEGIN
  v_q := precios_cotizar(p_payload);
  v_exp := clock_timestamp() + INTERVAL '15 minutes';
  INSERT INTO cotizaciones_precio (id_cabana, fecha_in, fecha_out, personas, canal, total, expires_at)
  VALUES ((p_payload->>'id_cabana')::BIGINT, (p_payload->>'fecha_in')::DATE,
          (p_payload->>'fecha_out')::DATE, (p_payload->>'personas')::INTEGER,
          p_payload->>'canal', (v_q->>'total')::NUMERIC, v_exp)
  RETURNING cotizacion_id INTO v_id;
  RETURN v_q || jsonb_build_object('congelada', true, 'cotizacion_id', v_id, 'expires_at', v_exp);
END $fn$;

CREATE OR REPLACE FUNCTION public.precios_cotizacion_obtener(p_cotizacion_id UUID)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY INVOKER
SET search_path = pg_catalog, public
AS $fn$
DECLARE r RECORD;
BEGIN
  SELECT * INTO r FROM cotizaciones_precio WHERE cotizacion_id = p_cotizacion_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', 'no_encontrada'); END IF;
  RETURN jsonb_build_object('ok', true, 'cotizacion_id', r.cotizacion_id, 'total', r.total,
    'expires_at', r.expires_at, 'vigente', r.expires_at > clock_timestamp());
END $fn$;
"""


def find_extension_dir(pgserver_mod):
    import glob
    cands = [Path(pgserver_mod.__file__).resolve().parent /
             'pginstall' / 'share' / 'postgresql' / 'extension']
    cands += [Path(p) for p in glob.glob('/usr/**/share/postgresql/**/extension', recursive=True)]
    for c in cands:
        if c.is_dir():
            return c
    raise RuntimeError('no encontre share/extension de pgserver')


def main():
    import shutil
    if '--reset' in sys.argv and PGDATA.exists():
        shutil.rmtree(PGDATA)

    import pgserver
    db = pgserver.get_server(str(PGDATA))
    uri = db.get_uri()

    ext_dir = find_extension_dir(pgserver)
    (ext_dir / 'pg_cron.control').write_text(PGCRON_CONTROL)
    (ext_dir / 'pg_cron--1.6.sql').write_text(PGCRON_SQL)

    import psycopg
    with psycopg.connect(uri, autocommit=True) as c:
        cur = c.cursor()
        cur.execute("CREATE EXTENSION IF NOT EXISTS pg_cron")
        cur.execute(BASE)
        cur.execute(B3)
        for i in range(1, 11):
            cur.execute(f"""CREATE OR REPLACE FUNCTION public.precios_aux_{i:02d}() RETURNS INTEGER
                            LANGUAGE sql STABLE SECURITY INVOKER
                            SET search_path = pg_catalog, public AS $x$ SELECT {i} $x$;""")
        cur.execute(r"""DO $$ DECLARE r RECORD; BEGIN
          FOR r IN SELECT oid::regprocedure AS s FROM pg_proc
                    WHERE pronamespace='public'::regnamespace AND proname LIKE 'precios\_%' LOOP
            EXECUTE 'REVOKE EXECUTE ON FUNCTION '||r.s||' FROM PUBLIC, anon, authenticated, service_role';
          END LOOP; END $$;""")
        # Los TRES fingerprints, con los MISMOS algoritmos del preflight de B4-0A.
        # En el harness dan valores LOCALES (las tablas y las funciones son stubs);
        # los canonicos solo pueden matchear en TEST. Se adaptan para que el
        # preflight sea EJERCITABLE localmente, sin cambiar su logica.
        cur.execute("SET search_path = public, pg_catalog")

        cur.execute(r"""SELECT md5(string_agg(md5(replace(prosrc, chr(13), '')), '' ORDER BY proname))
                        FROM pg_proc WHERE pronamespace='public'::regnamespace AND proname LIKE 'precios\_%'""")
        fp_b3 = cur.fetchone()[0]

        cur.execute(r"""
          WITH cols AS (
            SELECT 'C|'||table_name||'|'||column_name||'|'||data_type||'|'||is_nullable||'|'||COALESCE(column_default,'') AS line
            FROM information_schema.columns
            WHERE table_name IN ('perfiles_tarifarios','tarifas_motor','temporada_vigencia','noches_alta_demanda',
                                 'overrides_precio','cotizaciones_precio','precios_auditoria')
               OR (table_name='cabanas'      AND column_name='perfil_tarifario')
               OR (table_name='reservas'     AND column_name IN ('precio_source','precio_motivo','precio_snapshot','capacidad_override','cotizacion_id'))
               OR (table_name='pre_reservas' AND column_name='cotizacion_id')),
          cons AS (
            SELECT 'K|'||conrelid::regclass::text||'|'||conname||'|'||pg_get_constraintdef(oid) AS line
            FROM pg_constraint
            WHERE conrelid::regclass::text IN ('perfiles_tarifarios','tarifas_motor','temporada_vigencia','noches_alta_demanda',
                                               'overrides_precio','cotizaciones_precio','precios_auditoria')
               OR conname IN ('cabanas_perfil_tarifario_fkey','chk_reservas_precio_source',
                              'reservas_cotizacion_id_fkey','pre_reservas_cotizacion_id_fkey')),
          idx AS (
            SELECT 'I|'||tablename||'|'||indexname||'|'||indexdef AS line
            FROM pg_indexes
            WHERE tablename IN ('perfiles_tarifarios','tarifas_motor','temporada_vigencia','noches_alta_demanda',
                                'overrides_precio','cotizaciones_precio','precios_auditoria')
               OR indexname='idx_paquetes_evento_id_evento'),
          todo AS (SELECT line FROM cols UNION ALL SELECT line FROM cons UNION ALL SELECT line FROM idx)
          SELECT md5(string_agg(line, E'\n' ORDER BY line)), COUNT(*) FROM todo""")
        fp_b2a, n_b2a = cur.fetchone()

        cur.execute(r"""
          WITH tar AS (
            SELECT 'T|'||perfil||'|'||temporada_clave||'|'||concepto||'|'||precio::TEXT AS line
            FROM tarifas_motor WHERE vigente_hasta IS NULL),
          tmp AS (
            SELECT 'S|'||temporada_clave||'|'||anio::TEXT||'|'||fecha_in::TEXT||'|'||fecha_out_excl::TEXT AS line
            FROM temporada_vigencia),
          todo AS (SELECT line FROM tar UNION ALL SELECT line FROM tmp)
          SELECT md5(string_agg(line, E'\n' ORDER BY line)), COUNT(*) FROM todo""")
        fp_b2b, n_b2b = cur.fetchone()

    print('  base + pg_cron(stub) + 13 stubs precios_* (owner-only): OK')
    print(f'  fingerprints LOCALES del harness (NO son los de TEST):')
    print(f'    B3  {fp_b3}')
    print(f'    B2A {fp_b2a}  ({n_b2a} lineas)')
    print(f'    B2B {fp_b2b}  ({n_b2b} lineas)')

    sql = SQL_B4.read_text()
    sql_harness = (sql
      .replace('098f2fe7916e11ffa78cff37622b9064', fp_b3)
      .replace('da52a16c045689523a5f1f113f513a87', fp_b2a)
      .replace('6d1653748d68ee9b62aa20aba5f3333d', fp_b2b))
    if sql_harness == sql:
        print('  AVISO: no se encontraron los fingerprints canonicos para adaptar al harness')
    with psycopg.connect(uri, autocommit=True) as c:
        c.execute(sql_harness)
    # dejar los fingerprints del harness en GUCs de base, para que los smokes que
    # necesitan RE-EJECUTAR el SQL (gate ACL, rollback sin cron) los reusen sin
    # recalcularlos y sin duplicar la logica.
    with psycopg.connect(uri, autocommit=True) as c:
        c.execute(f"ALTER DATABASE {c.info.dbname} SET b4.fp_b2a = '{fp_b2a}'")
        c.execute(f"ALTER DATABASE {c.info.dbname} SET b4.fp_b2b = '{fp_b2b}'")
    print('  B4_0A_v6_ROL_TABLAS_FUNCIONES.sql: EJECUTADO OK (fingerprint adaptado al harness)')

    with psycopg.connect(uri, autocommit=True) as c:
        c.execute(f"ALTER ROLE vita_precios_api LOGIN PASSWORD '{HARNESS_PWD}'")

    URI_FILE.write_text(uri)
    return uri


if __name__ == '__main__':
    main()
