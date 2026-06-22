# ============================================================================
# C_SLICE3B_A13_GW_smoke.ps1 -- smoke GATEWAY de A13 (gastos.listado) via JWT.
# Carril C / Portal Operativo Interno - Slice 3b, cableado de A13 en portal-api.
#
# Se autentica con JWT de Supabase y POSTea { action, payload } a la Edge Function
# portal-api. El gateway valida (payloadGastosListado), firma HMAC server-side hacia
# n8n, y el wrapper portal-a13-gastos-listado revalida (2da defensa). Este harness
# NUNCA ve el secreto HMAC.
#
# Reutiliza el helper comun C_SLICE2_A10_GW_common.ps1 (Get-PortalJwt / Invoke-Gateway /
# Assert-* / Get-GwEnv / Record / Summary). ASCII puro (PS 5.1). Sin -Parallel.
# Capa de asserts funcionales = misma estructura/IDs que el smoke directo
# C_SLICE3B_A13_smoke_directo.ps1, ahora por JWT (se accede $r.data directo, sin .json).
#
# CRUCE AL CENTAVO (end-to-end, contra C_SLICE3B_A13_smoke_expected.sql):
#   - universo (periodo_hasta=2099-12-01, limit 200): total_gastos=335000.00, n_filas=5.
#   - particiones (G5/G6): sum(clase A+C+D+E) = sum(pagador socio+caja) = total_gastos.
#
# PARIDAD GATEWAY<->WRAPPER DIRECTO A13 (la verdad de referencia de A13 es el wrapper directo):
#   - GP. PARIDAD MENSUAL (D-C-60): mismo mes con dia de hasta < dia de desde NO es inversion a
#     nivel mes. {desde=2026-08-15, hasta=2026-08-10} truncan ambos a 2026-08-01 -> agosto (180000),
#     ok:true. Sin el truncado del gateway esto rebotaria payload_invalido -> divergencia. ok:true lo prueba.
#   - P-null. PARIDAD null == omitido: el wrapper directo trata periodo_hasta:null como omitido; el
#     gateway hace lo mismo (ni omitido ni null entran en value). Request omitido y request null deben
#     dar ok:true y el MISMO resultado. Cierra 24/24 (precision de D-C-60 / paridad A13).
#   - {} default vacio hoy por floor futuro (total_gastos=0, ok:true) -> PASS.
#
# Variables de entorno: VITA_SUPABASE_URL_TEST, VITA_SUPABASE_ANON_TEST,
# VITA_PW_VICKY / VITA_PW_FRANCO / VITA_PW_JENNY.  TEST exclusivamente. No toca OPS.
# ============================================================================

# Ruta al helper comun. EDITAR si esta en otra carpeta (p.ej. ..\C_SLICE_2\).
$CommonPath = Join-Path $PSScriptRoot 'C_SLICE2_A10_GW_common.ps1'
if (-not (Test-Path $CommonPath)) {
  throw "No encuentro C_SLICE2_A10_GW_common.ps1 en '$CommonPath'. Edita la variable `$CommonPath con la ruta correcta."
}
. $CommonPath

$ACT   = 'gastos.listado'
$FLOOR = '2026-07-01'
$HASTA = '2099-12-01'   # cota amplia (captura el fixture 2026 + sinteticos); ya es dia 1

# Valores esperados del universo (E1/E2 de C_SLICE3B_A13_smoke_expected.sql) -> cruce al centavo.
$EXP_TOTAL  = 335000      # E2 total_gastos del universo
$EXP_NFILAS = 5           # E1 n_filas del universo
$EXP_AGO    = 180000      # total_gastos de agosto 2026 (1 fila); lo usa la paridad GP (D-C-60)

# Helpers locales de montos/filas.
function Filas    { param($d); if ($d -and $d.filas) { return @($d.filas) } ; return @() }
function SumMonto { param($arr); if (-not $arr) { return [double]0 } ; return [double]((@($arr) | Measure-Object -Property monto -Sum).Sum) }
function Eq2      { param($a, $b); if ($null -eq $a -or $null -eq $b) { return $false } ; return ([math]::Abs([double]$a - [double]$b) -lt 0.01) }

# Total de gastos de una consulta (via gateway con JWT de vicky), o $null si error.
function Get-Total {
  param($payload)
  $r = Invoke-Gateway -Action $ACT -Payload $payload -Jwt $jwtVicky
  if ($r -and ($r.ok -eq $true) -and ($null -ne $r.data)) { return [double]$r.data.total_gastos }
  return $null
}

# ---- JWTs ----
$jwtVicky  = Get-PortalJwt -Identity 'vicky@vitadelta.test'  -Password $env:VITA_PW_VICKY
$jwtFranco = Get-PortalJwt -Identity 'franco@vitadelta.test' -Password $env:VITA_PW_FRANCO
$jwtJenny  = Get-PortalJwt -Identity 'jenny@vitadelta.test'  -Password $env:VITA_PW_JENNY

if (-not $jwtVicky) {
  Write-Host "No se pudo obtener JWT de vicky. Revisa VITA_SUPABASE_URL_TEST / VITA_SUPABASE_ANON_TEST / VITA_PW_VICKY." -ForegroundColor Red
  return
}

$cfg = Get-GwEnv
Write-Host "Gateway: $($cfg.url)/functions/v1/portal-api" -ForegroundColor Magenta
Write-Host "Action: $ACT | Floor: $FLOOR | Cota con datos: $HASTA" -ForegroundColor DarkGray

# ============================ SEGURIDAD ============================
Write-Host "`n----- SEGURIDAD (gateway) -----" -ForegroundColor Magenta

# 1. vicky OK (lectura permitida). Default {} -> hoy<floor -> vacio OK, ok:true.
$r = Invoke-Gateway -Action $ACT -Payload @{} -Jwt $jwtVicky
Assert-OkData $r "1. vicky OK (default {})" { param($d) $null -ne $d.total_gastos }

# 2. socio (franco) OK.
if ($jwtFranco) {
  $r = Invoke-Gateway -Action $ACT -Payload @{} -Jwt $jwtFranco
  Assert-OkData $r "2. socio (franco) OK (default {})" { param($d) $null -ne $d.total_gastos }
} else {
  Record "2. socio (franco) OK" $false "no se obtuvo JWT de franco (revisa VITA_PW_FRANCO)"
}

# 3. jenny -> rol_no_permitido (contenido economico; rebota en el gateway antes de firmar).
if ($jwtJenny) {
  $r = Invoke-Gateway -Action $ACT -Payload @{} -Jwt $jwtJenny
  Assert-Code $r "3. jenny -> rol_no_permitido" "rol_no_permitido"
} else {
  Record "3. jenny -> rol_no_permitido" $false "no se obtuvo JWT de jenny (revisa VITA_PW_JENNY)"
}

# 4. sin JWT -> no_autorizado.
$r = Invoke-Gateway -Action $ACT -Jwt $null
Assert-Code $r "4. sin JWT -> no_autorizado" "no_autorizado"

# 5. accion desconocida -> accion_desconocida.
$r = Invoke-Gateway -Action 'gastos.inexistente' -Jwt $jwtVicky
Assert-Code $r "5. accion desconocida -> accion_desconocida" "accion_desconocida"

# ============================ FUNCIONALES (vicky) ============================
Write-Host "`n----- FUNCIONALES (cruce al centavo + particiones) -----" -ForegroundColor Magenta

# Universo de la ventana (limit 200 para traer todas las filas y poder cuadrar).
$rFull = Invoke-Gateway -Action $ACT -Payload @{ periodo_hasta = $HASTA; limit = [int]200 } -Jwt $jwtVicky
$totFull = $null
if ($rFull -and ($rFull.ok -eq $true) -and ($null -ne $rFull.data)) {
  $d = $rFull.data
  $nFull = @(Filas $d).Count
  $totFull = [double]$d.total_gastos
  Write-Host ("    total_gastos=" + $d.total_gastos + " filas=" + $nFull + " por_clase=" + (@($d.por_clase | ForEach-Object { $_.clase + ':' + $_.monto + '(' + $_.n + ')' }) -join ' ')) -ForegroundColor DarkGray
  if ($nFull -ge 200) { Write-Host "    AVISO: universo >= 200; subir limit/ajustar ventana para cuadre completo." -ForegroundColor Yellow }
} else {
  Write-Host "    No se pudo traer el universo (revisar gateway/datos)." -ForegroundColor Red
}

# G0a. cruce al centavo: total_gastos == EXP_TOTAL.
Assert-OkData $rFull "G0a. total_gastos == $EXP_TOTAL (cruce al centavo)" { param($d) Eq2 $d.total_gastos $EXP_TOTAL }

# G0b. cruce al centavo: n_filas == EXP_NFILAS.
Assert-OkData $rFull "G0b. n_filas == $EXP_NFILAS" { param($d) (@(Filas $d).Count) -eq [int]$EXP_NFILAS }

# G1. cuadre interno: sum(por_clase.monto) == total_gastos == sum(filas.monto) [universo en pagina].
Assert-OkData $rFull "G1. cuadre por_clase == total_gastos == filas" {
  param($d)
  (Eq2 (SumMonto $d.por_clase) $d.total_gastos) -and
  ((@(Filas $d).Count) -ge 200 -or (Eq2 (SumMonto $d.filas) $d.total_gastos))
}

# G2. por_clase: solo clases validas {A,C,D,E} y sum(n) == filas (si universo en pagina).
Assert-OkData $rFull "G2. por_clase en {A,C,D,E} y n cuadra" {
  param($d)
  $fueraEnum = @($d.por_clase | Where-Object { @('A','C','D','E') -notcontains $_.clase }).Count
  $sumN = [int]((@($d.por_clase) | Measure-Object -Property n -Sum).Sum)
  ($fueraEnum -eq 0) -and ((@(Filas $d).Count) -ge 200 -or ($sumN -eq @(Filas $d).Count))
}

# G3. default {} (hoy<floor) -> total_gastos=0, por_clase=[], filas=[], ok:true.
$r = Invoke-Gateway -Action $ACT -Payload @{} -Jwt $jwtVicky
Assert-OkData $r "G3. default vacio (total=0, por_clase vacio, filas=[])" {
  param($d) (Eq2 $d.total_gastos 0) -and ((SumMonto $d.por_clase) -eq 0) -and (@(Filas $d).Count -eq 0)
}

# G4. periodo_desde<floor recortado (clamp) -> mismo total que el universo (junio no agrega).
$r = Invoke-Gateway -Action $ACT -Payload @{ periodo_desde = "2026-06-01"; periodo_hasta = $HASTA; limit = [int]200 } -Jwt $jwtVicky
Assert-OkData $r "G4. periodo_desde<floor recortado (== universo)" { param($d) Eq2 $d.total_gastos $totFull }

# G5. PARTICION por clase: sum(A,C,D,E) == universo [independiente de los datos].
$tA = Get-Total @{ periodo_hasta = $HASTA; clase = "A"; limit = [int]200 }
$tC = Get-Total @{ periodo_hasta = $HASTA; clase = "C"; limit = [int]200 }
$tD = Get-Total @{ periodo_hasta = $HASTA; clase = "D"; limit = [int]200 }
$tE = Get-Total @{ periodo_hasta = $HASTA; clase = "E"; limit = [int]200 }
$okPart = ($null -ne $tA) -and ($null -ne $tC) -and ($null -ne $tD) -and ($null -ne $tE) -and ($null -ne $totFull) -and (Eq2 ($tA + $tC + $tD + $tE) $totFull)
Record "G5. particion por clase A+C+D+E == universo" $okPart ("A=$tA C=$tC D=$tD E=$tE suma=$($tA+$tC+$tD+$tE) full=$totFull")

# G6. PARTICION por pagador: sum(socio,caja) == universo.
$tSoc = Get-Total @{ periodo_hasta = $HASTA; pagador_tipo = "socio"; limit = [int]200 }
$tCaj = Get-Total @{ periodo_hasta = $HASTA; pagador_tipo = "caja"; limit = [int]200 }
$okPag = ($null -ne $tSoc) -and ($null -ne $tCaj) -and ($null -ne $totFull) -and (Eq2 ($tSoc + $tCaj) $totFull)
Record "G6. particion por pagador socio+caja == universo" $okPag ("socio=$tSoc caja=$tCaj suma=$($tSoc+$tCaj) full=$totFull")

# G7. monotonia: total(clase=A) <= universo.
$okMono = ($null -ne $tA) -and ($null -ne $totFull) -and (($tA - $totFull) -le 0.01)
Record "G7. monotonia clase=A <= universo" $okMono ("A=$tA full=$totFull")

# G8. q sin match -> vacio (total=0, filas=[]).
$r = Invoke-Gateway -Action $ACT -Payload @{ periodo_hasta = $HASTA; q = "zzz_nomatch_vd_zzz"; limit = [int]200 } -Jwt $jwtVicky
Assert-OkData $r "G8. q sin match -> vacio (total=0, filas=[])" { param($d) (Eq2 $d.total_gastos 0) -and (@(Filas $d).Count -eq 0) }

# G9. paginacion limit=1 -> <=1 fila; total_gastos NO cambia (agregado del universo); limit=1.
$rG9 = Invoke-Gateway -Action $ACT -Payload @{ periodo_hasta = $HASTA; limit = [int]1; offset = [int]0 } -Jwt $jwtVicky
Assert-OkData $rG9 "G9. limit=1 (<=1 fila, total==universo, limit=1)" {
  param($d) (@(Filas $d).Count -le 1) -and (Eq2 $d.total_gastos $totFull) -and ($d.limit -eq 1)
}

# G10. paginacion offset -> pagina distinta (sin solape de id_gasto).
$rG10 = Invoke-Gateway -Action $ACT -Payload @{ periodo_hasta = $HASTA; limit = [int]2; offset = [int]2 } -Jwt $jwtVicky
Assert-OkData $rG10 "G10. limit=2 offset=2 (pagina distinta)" {
  param($d)
  $idsA = @(Filas $rG9.data | ForEach-Object { $_.id_gasto })
  $idsB = @(Filas $d | ForEach-Object { $_.id_gasto })
  $solapan = @($idsB | Where-Object { $idsA -contains $_ }).Count
  ($d.offset -eq 2) -and ($solapan -eq 0 -or @($idsB).Count -eq 0)
}

# ============================ PARIDAD (D-C-60 + null==omitido) ============================
Write-Host "`n----- PARIDAD gateway<->wrapper directo A13 -----" -ForegroundColor Magenta

# GP. mismo mes con dia de hasta < dia de desde: NO es inversion a nivel mes. Ambos truncan a
#     2026-08-01 -> agosto. DEBE devolver ok:true con el total de agosto (EXP_AGO), NUNCA
#     payload_invalido. Sin el truncado del gateway (Q2 descartado) esto rebotaria payload_invalido
#     -> divergencia con el wrapper directo. ok:true (Assert-OkData) lo prueba.
$rGP = Invoke-Gateway -Action $ACT -Payload @{ periodo_desde = "2026-08-15"; periodo_hasta = "2026-08-10"; limit = [int]200 } -Jwt $jwtVicky
Assert-OkData $rGP "GP. paridad mensual (mismo mes, hasta<desde dia) -> agosto, NO payload_invalido" {
  param($d) Eq2 $d.total_gastos $EXP_AGO
}

# P-null. PARIDAD null == omitido: para A13 la verdad de referencia es el wrapper directo, que trata
#         periodo_hasta:null como OMITIDO (defaultea al mes actual, sin check de inversion). El gateway
#         hace lo mismo: ni omitido ni null entran en value. Request A (omitido) y B (null) deben dar
#         ok:true y el MISMO resultado (total_gastos, n_filas y periodo_hasta resuelto). Cierra 24/24.
$rOmit = Invoke-Gateway -Action $ACT -Payload @{ limit = [int]200 } -Jwt $jwtVicky
$rNull = Invoke-Gateway -Action $ACT -Payload @{ periodo_hasta = $null; limit = [int]200 } -Jwt $jwtVicky
$okPnull = (
  ($rOmit -and ($rOmit.ok -eq $true) -and ($null -ne $rOmit.data)) -and
  ($rNull -and ($rNull.ok -eq $true) -and ($null -ne $rNull.data)) -and
  (Eq2 $rOmit.data.total_gastos $rNull.data.total_gastos) -and
  (@(Filas $rOmit.data).Count -eq @(Filas $rNull.data).Count) -and
  ($rOmit.data.periodo_hasta -eq $rNull.data.periodo_hasta)
)
$detPnull = "omit: ok=$($rOmit.ok) total=$($rOmit.data.total_gastos) hasta=$($rOmit.data.periodo_hasta) | null: ok=$($rNull.ok) total=$($rNull.data.total_gastos) hasta=$($rNull.data.periodo_hasta)"
Record "P-null. periodo_hasta null == omitido (paridad: ambos ok:true, mismo resultado)" $okPnull $detPnull

# ============================ PAYLOAD INVALIDO (vicky) ============================
Write-Host "`n----- PAYLOAD INVALIDO (gateway) -----" -ForegroundColor Magenta

# P1. clave no permitida.
$r = Invoke-Gateway -Action $ACT -Payload @{ foo = "bar" } -Jwt $jwtVicky
Assert-Code $r "P1. clave no permitida -> payload_invalido" "payload_invalido"

# P2. periodo_desde mal formado.
$r = Invoke-Gateway -Action $ACT -Payload @{ periodo_desde = "2026-13-01" } -Jwt $jwtVicky
Assert-Code $r "P2. periodo_desde mal formado -> payload_invalido" "payload_invalido"

# P3. inversion EXPLICITA a nivel mes (cross-month): desde=2026-08-15, hasta=2026-07-20 -> 08 > 07.
$r = Invoke-Gateway -Action $ACT -Payload @{ periodo_desde = "2026-08-15"; periodo_hasta = "2026-07-20" } -Jwt $jwtVicky
Assert-Code $r "P3. inversion cross-month -> payload_invalido" "payload_invalido"

# P4. periodo_hasta mal formado (string no-YMD).
$r = Invoke-Gateway -Action $ACT -Payload @{ periodo_hasta = "2026-02-31" } -Jwt $jwtVicky
Assert-Code $r "P4. periodo_hasta mal formado -> payload_invalido" "payload_invalido"

# P4b. periodo_hasta de otro tipo (numero; no-string y no-null) -> payload_invalido.
$r = Invoke-Gateway -Action $ACT -Payload @{ periodo_hasta = [int]20260801 } -Jwt $jwtVicky
Assert-Code $r "P4b. periodo_hasta otro tipo (numero) -> payload_invalido" "payload_invalido"

# P5. limit no entero.
$r = Invoke-Gateway -Action $ACT -Payload @{ limit = "x" } -Jwt $jwtVicky
Assert-Code $r "P5. limit no entero -> payload_invalido" "payload_invalido"

# P6. clase invalida.
$r = Invoke-Gateway -Action $ACT -Payload @{ clase = "Z" } -Jwt $jwtVicky
Assert-Code $r "P6. clase invalida -> payload_invalido" "payload_invalido"

# P7. pagador_tipo invalido.
$r = Invoke-Gateway -Action $ACT -Payload @{ pagador_tipo = "foo" } -Jwt $jwtVicky
Assert-Code $r "P7. pagador_tipo invalido -> payload_invalido" "payload_invalido"

# P8. id_zona <= 0.
$r = Invoke-Gateway -Action $ACT -Payload @{ id_zona = [int]0 } -Jwt $jwtVicky
Assert-Code $r "P8. id_zona=0 -> payload_invalido" "payload_invalido"

# P8b. id_cabana no entero.
$r = Invoke-Gateway -Action $ACT -Payload @{ id_cabana = "x" } -Jwt $jwtVicky
Assert-Code $r "P8b. id_cabana no entero -> payload_invalido" "payload_invalido"

# P9. q vacio (trim -> vacio).
$r = Invoke-Gateway -Action $ACT -Payload @{ q = "   " } -Jwt $jwtVicky
Assert-Code $r "P9. q vacio -> payload_invalido" "payload_invalido"

# P10. q oversized (>120).
$bigQ = ("a" * 121)
$r = Invoke-Gateway -Action $ACT -Payload @{ q = $bigQ } -Jwt $jwtVicky
Assert-Code $r "P10. q oversized (>120) -> payload_invalido" "payload_invalido"

# P11a. payload string -> payload_invalido (no se coerciona a {}).
$r = Invoke-Gateway -Action $ACT -Payload "soy_un_string" -Jwt $jwtVicky
Assert-Code $r "P11a. payload string -> payload_invalido" "payload_invalido"

# P11b. payload array -> payload_invalido.
$r = Invoke-Gateway -Action $ACT -Payload @(1, 2, 3) -Jwt $jwtVicky
Assert-Code $r "P11b. payload array -> payload_invalido" "payload_invalido"

# ============================ META ============================
Write-Host "`n----- META -----" -ForegroundColor Magenta
Assert-AllowlistMeta

Summary
Write-Host ""
Write-Host "Nota: el default {} hoy da total_gastos=0 (floor en el futuro) y es PASS." -ForegroundColor DarkGray
Write-Host "Cruce al centavo: total_gastos/n_filas del universo vs E1/E2 de C_SLICE3B_A13_smoke_expected.sql." -ForegroundColor DarkGray
Write-Host "Paridad A13: GP (mismo mes no rebota, D-C-60) y P-null (null==omitido) cierran 24/24 vs el wrapper directo." -ForegroundColor DarkGray
