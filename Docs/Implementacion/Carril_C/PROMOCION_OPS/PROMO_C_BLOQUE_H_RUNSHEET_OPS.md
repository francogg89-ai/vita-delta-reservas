# PROMO_C — Bloque H — Runsheet de ejecución y comparación TEST↔OPS

**Etapa:** Promoción del Carril C (Portal Operativo Interno) a OPS — **Bloque H**: verificación de paridad estructural TEST↔OPS y smokes read-only end-to-end del portal en OPS.

**Naturaleza:** 100% **read-only**. Nada en este bloque escribe en el dominio de negocio. Es la red de seguridad previa al Bloque I (canónico v1.9.0) y al cierre final con satélites.

**Artefactos del bloque:**

- `PROMO_C_BLOQUE_H_FINGERPRINT.sql` — huella estructural simétrica (H.1).
- `PROMO_C_BLOQUE_H_SMOKES_READONLY_OPS.ps1` — smokes por rol contra el gateway OPS (H.2).
- Este runsheet.

**H.3 (alta + aviso) se cierra por referencia**, sin nueva escritura ni teardown — ver §3.

---

## 0. Pre-requisitos

- Acceso al **SQL Editor** de Supabase en los **dos** proyectos: TEST (`bdskhhbmcksskkzqkcdp`) y OPS (`lpiatqztudxiwdlcoasv`).
- PowerShell **5.1+** en tu máquina.
- Las credenciales de los tres roles de OPS (jenny / vicky / socio) ya sembradas en Auth (Bloque C) y el gateway `portal-api` desplegado en OPS (Bloque D).
- **Ningún secreto se pasa por línea de comando ni se imprime.** El smoke los lee de variables de entorno locales o los pide con prompt seguro (ver §2.1).

> **Nota de EOL.** Los artefactos se entregan con fin de línea **LF**, consistente con el repo real (`.gitattributes` ausente; los 42 `.ps1` y todos los `.md`/`.sql` de promoción están en `i/lf`). Si preferís CRLF para los `.ps1`, avisá y se regenera; no cambia ninguna lógica.

---

## 1. H.1 — Fingerprint estructural TEST↔OPS

### Qué prueba

Que la infra del portal en OPS es **estructuralmente idéntica** a la de TEST. Compara, por los 3 objetos del portal (`portal_usuarios`, `portal_idempotencia`, `portal_cargar_gasto_interno(jsonb)`): columnas, constraints, índices, triggers no internos, ACL, estado RLS y policies, comentarios de tabla y de cada columna, y para la función el cuerpo completo + ACL + comentario.

**Nunca toca datos**: no entra al hash ninguna fila, secreto, email, uuid, valor de secuencia, marcador de ambiente, fecha/hora ni ref del proyecto. El script es **simétrico** (el mismo en ambos entornos) y la comparación es externa: corrés las dos salidas y mirás si la fila `TOTAL_PORTAL` coincide.

**Dos garantías de robustez** (v2): la función se resuelve por **firma exacta** vía `to_regprocedure('public.portal_cargar_gasto_interno(jsonb)')` —no por nombre—, así un overload con otra firma no matchea; si la firma exacta no existe en un entorno, su huella es `<<AUSENTE>>` (el script no lanza, la comparación localiza la ausencia). Y los **ACL** (de tablas y de la función) se serializan con los `aclitem` **desarmados y ordenados por texto**, para que el mismo conjunto de grants en distinto orden de array no produzca un falso rojo.

### Paso 1 — Correr en TEST

1. Abrí el SQL Editor del proyecto **TEST**.
2. Pegá el contenido de `PROMO_C_BLOQUE_H_FINGERPRINT.sql`.
3. **Asegurate de NO tener texto seleccionado** (L-8A-01: el editor de Supabase ejecuta solo lo seleccionado; con nada seleccionado corre el script entero).
4. Ejecutá (Run).
5. Guardá la salida completa (las 3 filas por objeto + la fila `TOTAL_PORTAL`). Copiá el valor del hash de `TOTAL_PORTAL`.

### Paso 2 — Correr en OPS

Repetí exactamente lo mismo en el proyecto **OPS**, con el **mismo** archivo, nada seleccionado.

### Paso 3 — Comparar

- **Caso verde:** el hash de la fila `TOTAL_PORTAL` de TEST es **idéntico** al de OPS. Paridad estructural exacta. H.1 ✅.
- **Caso rojo:** los `TOTAL_PORTAL` difieren. Entonces compará las **filas por objeto** (`tabla:portal_usuarios`, `tabla:portal_idempotencia`, `func:portal_cargar_gasto_interno(...)`): la(s) que difiera(n) localiza(n) el objeto desincronizado. A partir de ahí, inspeccioná ese objeto en ambos entornos (columna, constraint, comentario, grant o cuerpo de función) y resolvé antes de seguir.

> Si querés, podés pegar las dos salidas una al lado de la otra; el hash por objeto te dice cuál mirar sin tener que leer las definiciones completas.

### Criterio de cierre H.1

`TOTAL_PORTAL` de TEST == `TOTAL_PORTAL` de OPS.

---

## 2. H.2 — Smokes read-only end-to-end por rol (OPS)

### Qué prueba

Contra el gateway `portal-api` de **OPS**, recorre la cadena completa (gateway → allowlist → firma HMAC → wrapper n8n → motor OPS):

- **Guard de entorno (previo a todo):** antes de pedir credenciales o autenticar, exige que `SupabaseUrl` y `GatewayUrl` contengan el ref de OPS (`lpiatqztudxiwdlcoasv`) y que `GatewayUrl` apunte a `/functions/v1/portal-api`. Si no, **FRENAR con exit 3 sin intentar login**: evita generar evidencia inválida por correr accidentalmente contra TEST u otro entorno.
- **B1 — `sesion.contexto` por rol:** que cada rol recibe el menú correcto.
  - **jenny:** exactamente `{sesion.contexto, calendario.limpieza}`.
  - **vicky / socio:** **allowlist estricta** — deben estar las **13 acciones productivas** y **nada fuera** del universo aceptable `{13 productivas + W10}`. Cualquier acción extra inesperada → **FRENAR** (las extras se listan por nombre para diagnóstico).
- **B2 — una lectura por acción:** ejercita los 8 wrappers de lectura (`calendario.limpieza`, `calendario.operativo`, `reserva.detalle`, `prereservas.activas`, `cobranza.saldos`, `historico.reservas`, `ingresos.cobrados_periodo`, `gastos.listado`).
- **B3 — allowlist:** que jenny **rebota** en las acciones económicas con `rol_no_permitido`.

### Alcance y garantías (read-only del negocio)

- El smoke **no escribe** reservas, pagos, gastos, bloqueos ni idempotencia, y **no consume secuencias** (`nextval`) del negocio. No invoca ninguna de las 5 escrituras.
- Las acciones económicas (`historico.reservas`, `ingresos.cobrados_periodo`, `gastos.listado`) se llaman con payload vacío `{}`; el gateway aplica por defecto el **piso contable 2026-07-01** (D-NEG-02). Hoy eso devuelve resultados vacíos, lo cual es una **respuesta válida**: el smoke verifica forma (status/ok/estructura), no contenido.
- **Login y Auth:** el smoke hace login real de los tres roles vía Supabase Auth para obtener cada JWT. Ese login **puede dejar traza/sesión del lado de Auth** (es inherente a autenticarse), pero **no ensucia datos operativos ni secuencias del negocio**. Es la única huella que deja, y vive en Auth, no en las tablas del portal.
- **W10 (`cobranza.registrar_saldo`):** **nunca se invoca.** Si `sesion.contexto` la lista, el smoke la reporta como **catálogo técnico legado/deprecated** (línea `B1-info`, marcada `INFO`), y **no** la cuenta como acción productiva ni afecta el veredicto. El gate verifica acciones productivas requeridas + allowlist; no reactiva W10.
- **PII:** el smoke **no imprime bodies**. Solo loguea acción, rol, status, `ok`, `error.code`, conteos y **nombres** de claves top-level. Nunca teléfono, email, DNI, notas ni valores.

### 2.1 — Credenciales (sin CLI, sin hardcode, sin impresión)

El smoke resuelve cada secreto en este orden: **variable de entorno local** → si falta, **prompt** (`Read-Host -AsSecureString` para los sensibles). Variables esperadas:

| Variable | Contenido |
|---|---|
| `VITA_OPS_SUPABASE_URL` | URL del proyecto OPS (ej. `https://lpiatqztudxiwdlcoasv.supabase.co`) |
| `VITA_OPS_GATEWAY_URL` | URL del `portal-api` OPS (ej. `https://<ref>.supabase.co/functions/v1/portal-api`) |
| `VITA_OPS_ANON` | anon key de OPS (no se imprime) |
| `VITA_OPS_JENNY_EMAIL` / `VITA_OPS_JENNY_PASS` | credenciales jenny |
| `VITA_OPS_VICKY_EMAIL` / `VITA_OPS_VICKY_PASS` | credenciales vicky |
| `VITA_OPS_SOCIO_EMAIL` / `VITA_OPS_SOCIO_PASS` | credenciales socio (franco / rodrigo / remo) |

`VITA_OPS_SUPABASE_URL` y `VITA_OPS_GATEWAY_URL` también se pueden pasar como `-SupabaseUrl` / `-GatewayUrl` (son públicas, no secretas). Las passwords y la anon **solo** por env var o prompt — **nunca** como argumento.

**Modo env var (no interactivo).** En la misma sesión de PowerShell, por ejemplo:

```powershell
$env:VITA_OPS_SUPABASE_URL = 'https://lpiatqztudxiwdlcoasv.supabase.co'
$env:VITA_OPS_GATEWAY_URL  = 'https://lpiatqztudxiwdlcoasv.supabase.co/functions/v1/portal-api'
$env:VITA_OPS_ANON         = '<anon-key-ops>'
$env:VITA_OPS_JENNY_EMAIL  = '<email-jenny>'
$env:VITA_OPS_JENNY_PASS   = '<password-jenny>'
# ...vicky y socio igual...
```

> Estas asignaciones quedan en el entorno del proceso. Si no querés dejarlas pegadas en el historial de la consola, omitilas y dejá que el script las pida con prompt seguro.

**Modo interactivo.** Si no seteás las env vars, el script pide cada valor; los sensibles con eco oculto (`Read-Host -AsSecureString`).

### 2.2 — Correr

**Cobertura plena de A05** (recomendado): pasá el id de una reserva real de OPS. El smoke valida la forma del detalle **sin imprimir PII** (solo nombres de claves):

```powershell
.\PROMO_C_BLOQUE_H_SMOKES_READONLY_OPS.ps1 -IdReservaProbe <id_real_ops>
```

**Cobertura parcial de A05** (sin id): el smoke ejercita A05 con un id sintético improbable y acepta `no_encontrado` bien formado. Prueba menos cobertura funcional (no valida la forma del detalle poblado), pero igual verifica que la cadena responde correctamente:

```powershell
.\PROMO_C_BLOQUE_H_SMOKES_READONLY_OPS.ps1
```

### 2.3 — Leer el veredicto

Cada chequeo imprime una línea `[Bloque] accion rol | detalle | VEREDICTO`. Al final:

- **`RESULTADO: VERDE`** — todos los chequeos críticos en verde. Si A05 corrió en parcial, dice `VERDE (con A05 en cobertura parcial; pasar -IdReservaProbe para cobertura plena)`. Exit code `0`.
- **`RESULTADO: FRENAR`** — hay al menos un chequeo crítico en rojo. Exit code `1`. Revisá las filas marcadas `FRENAR`.
- Error de login (credenciales/anon/url) → mensaje sin exponer secretos y exit code `2`.
- **Guard de entorno fallido** (URLs no apuntan a OPS / gateway incorrecto) → `FRENAR` sin intentar login y exit code `3`.

> Recordá: el rebote de jenny (B3) es **HTTP 200 con `error.code = rol_no_permitido`**, no un 403. El smoke verifica el código, no el status HTTP.

### Criterio de cierre H.2

`RESULTADO: VERDE` (parcial aceptable si no se dispone de un id real; plena es lo ideal).

---

## 3. H.3 — Alta controlada + aviso 8C-bis (Opción A: por referencia)

**No se ejecuta ninguna escritura nueva ni teardown en este bloque.** La evidencia ya existe y quedó registrada en la sesión del Bloque E.

**Evidencia referenciada** (ver `PROMO_C_BLOQUE_E_CIERRE.md` §4 y la tabla de bloques):

- El **alta real #11** vía A07 se creó correctamente end-to-end en OPS.
- Esa alta **disparó el aviso 8C-bis** por rama lateral **no bloqueante** (Call a `vita_w8cbis_alerta__OPS`, id `fHzMFj7pGMKuYEOb`), con `entorno` autoresuelto desde `leer_ambiente.valor` (no hardcodeado) → **`entorno=ops`**. El sub-workflow es **solo-lectura** (manda mail; no escribe DB).
- El **teardown de la reserva #11** (`TEARDOWN_reserva_11_OPS.sql`) **ya fue ejecutado**. No queda dato de prueba abierto por este concepto.

Por lo tanto H.3 **no repite A07** ni genera un nuevo teardown: formaliza la evidencia existente como parte del cierre del Bloque H.

### Criterio de cierre H.3

Evidencia de #11 + aviso `entorno=ops` registrada (Bloque E §4) y reserva de prueba ya removida.

---

## 4. Gate del Bloque H (cierre)

El Bloque H queda **cerrado** cuando:

1. **H.1 ✅** — `TOTAL_PORTAL` idéntico TEST↔OPS.
2. **H.2 ✅** — smokes en `RESULTADO: VERDE` (parcial o plena en A05).
3. **H.3 ✅** — evidencia de #11 + aviso `entorno=ops` referenciada; teardown ya hecho.

**Qué sigue (no es parte de H):**

- **Bloque I** — bump canónico a `6B_SCHEMA_SQL.md v1.9.0` y regeneración del bootstrap kit pineado.
- **Cierre final** — recién ahí se propagan a los 6 satélites las decisiones/lecciones con IDs formales `D-PROMO-C-XX` / `L-PROMO-C-XX`, en un único bloque coordinado. **No se tocan satélites ni se acuñan esos IDs en este bloque.**

---

## Apéndice — Notas de validación de los artefactos

- **Fingerprint (`.sql`):** parseado con `pglast` (un único `SelectStmt`, read-only confirmado); sin DDL, sin tablas temporales, sin comandos psql-meta; sin ambiente/ref/fecha en el código ejecutable. La función se resuelve por **firma exacta** (`to_regprocedure`) con manejo de `<<AUSENTE>>`; los **ACL** (tabla y función) van con los `aclitem` **ordenados por texto**. Cuerpo de función y comentarios normalizados quitando `\r` (de hecho se normaliza el blob completo de cada objeto antes del `md5`, para que ninguna diferencia de EOL produzca falso rojo); ASCII, LF.
- **Smoke (`.ps1`):** ASCII puro (0 bytes no-ASCII), LF; delimitadores balanceados en código real (paréntesis, llaves y corchetes); funciones con verbos aprobados; backticks de continuación sin espacios en blanco; sin trailing whitespace. El **guard de entorno** (exit 3 antes de login) y la **allowlist estricta** de B1 se verificaron con un test de la lógica de conjuntos en todos los casos límite (entorno OPS/TEST/gateway incorrecto; faltantes, extras, W10 informativo, rol equivocado). (No se pudo correr un parser de PowerShell en el entorno de generación —el release de `pwsh` redirige fuera de la allowlist de red—; la validación de sintaxis fue por inspección estructural.)
