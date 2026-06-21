# ============================================================================
# C_SLICE3A_A25_GW_smoke.ps1 -- smoke GATEWAY de A25 (ingresos.cobrados_periodo) via JWT.
# Carril C / Portal Operativo Interno - Slice 3a, cableado de A25 en portal-api.
#
# Se autentica con JWT de Supabase y POSTea { action, payload } a la Edge Function portal-api.
# El gateway valida (payloadIngresosPeriodo), firma HMAC server-side hacia n8n, y el wrapper
# revalida (2da defensa). Este harness NUNCA ve el secreto HMAC.
#
# Reutiliza el helper comun C_SLICE2_A10_GW_common.ps1 (Get-PortalJwt / Invoke-Gateway /
# Assert-* / Get-GwEnv / Record). ASCII puro (PS 5.1). Sin -Parallel. Sin if inline en
# -ForegroundColor.
#
# REGRESIONES ESPECIFICAS DEL HIBRIDO (pedidas):
#   - {} default vacio hoy por floor futuro (total_cobrado=0).
#   - periodo_hasta OMITIDO preservado: {} NO debe rebotar payload_invalido (si el gateway
#     rellenara hoy, el wrapper veria explicito<floor -> payload_invalido). ok:true lo prueba.
#   - rango explicitamente invertido -> payload_invalido (rebota en el gateway).
#   - periodo_hasta null explicito -> payload_invalido.
#   - S8/S9/cuadre via gateway (periodo_hasta=2026-12-31, limit=200).
#
# Variables de entorno (las de A08/A10): VITA_SUPABASE_URL_TEST, VITA_SUPABASE_ANON_TEST,
# VITA_PW_VICKY / VITA_PW_FRANCO / VITA_PW_JENNY.  TEST exclusivamente. No toca OPS.
# ============================================================================

# Ruta al helper comun. EDITAR si esta en otra carpeta (p.ej. ..\C_SLICE_2\).
$CommonPath = Join-Path $PSScriptRoot 'C_SLICE2_A10_GW_common.ps1'
if (-not (Test-Path $CommonPath)) {
  throw "No encuentro C_SLICE2_A10_GW_common.ps1 en '$CommonPath'. Edita la variable `$CommonPath con la ruta correcta."
}
. $CommonPath

$ACT   = 'ingresos.cobrados_periodo'
$FLOOR = '2026-07-01'
$HASTA = '2026-12-31'

# Helpers locales de montos/filas.
function Filas { param($d); if ($d -and $d.filas) { return @($d.filas) } ; return @() }
function SumMonto { param($arr); if (-not $arr) { return [double]0 } ; return [double]((@($arr) | Measure-Object -Property monto -Sum).Sum) }
function FindMonto { param($arr, $keyName, $keyVal); $e = @($arr | Where-Object { $_.$keyName -eq $keyVal }); if ($e.Count -eq 0) { return $null } ; return $e[0].monto }
function Eq2 { param($a, $b); if ($null -eq $a -or $null -eq $b) { return $false } ; return ([math]::Abs([double]$a - [double]$b) -lt 0.01) }

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

# 1. vicky OK (default {}; hoy<floor -> vacio OK)
$r = Invoke-Gateway -Action $ACT -Payload @{} -Jwt $jwtVicky
Assert-OkData $r "1. vicky OK (default {})" { param($d) $null -ne $d.total_cobrado }

# 2. socio (franco) OK
if ($jwtFranco) {
  $r = Invoke-Gateway -Action $ACT -Payload @{} -Jwt $jwtFranco
  Assert-OkData $r "2. socio (franco) OK" { param($d) $null -ne $d.total_cobrado }
} else {
  Record "2. socio (franco) OK" $false "no se obtuvo JWT de franco (revisa VITA_PW_FRANCO)"
}

# 3. jenny -> rol_no_permitido (rebota en el gateway antes de firmar)
if ($jwtJenny) {
  $r = Invoke-Gateway -Action $ACT -Payload @{} -Jwt $jwtJenny
  Assert-Code $r "3. jenny -> rol_no_permitido" "rol_no_permitido"
} else {
  Record "3. jenny -> rol_no_permitido" $false "no se obtuvo JWT de jenny (revisa VITA_PW_JENNY)"
}

# 4. sin JWT -> no_autorizado
$r = Invoke-Gateway -Action $ACT -Jwt $null
Assert-Code $r "4. sin JWT -> no_autorizado" "no_autorizado"

# 5. action desconocida -> accion_desconocida
$r = Invoke-Gateway -Action 'ingresos.inexistente' -Jwt $jwtVicky
Assert-Code $r "5. action desconocida -> accion_desconocida" "accion_desconocida"

# ============================ FUNCIONALES (vicky) ============================
Write-Host "`n----- FUNCIONALES (gateway) -----" -ForegroundColor Magenta

# Periodo con datos (limit 200 para cuadrar).
$rFull = Invoke-Gateway -Action $ACT -Payload @{ periodo_hasta = $HASTA; limit = [int]200 } -Jwt $jwtVicky
if ($rFull.ok) {
  $d = $rFull.data
  Write-Host ("    total_cobrado=" + $d.total_cobrado + " total=" + $d.total + " filas=" + @(Filas $d).Count) -ForegroundColor DarkGray
}

# G1. total_cobrado=921200, total=4
Assert-OkData $rFull "G1. total_cobrado=921200, total=4" { param($d) (Eq2 $d.total_cobrado 921200) -and ($d.total -eq 4) }

# G2. cuadre (limit=200): Sum(por_medio)=Sum(por_tipo)=Sum(filas)=total_cobrado
Assert-OkData $rFull "G2. cuadre por_medio=por_tipo=filas=total_cobrado" {
  param($d)
  (Eq2 (SumMonto $d.por_medio) $d.total_cobrado) -and
  (Eq2 (SumMonto $d.por_tipo) $d.total_cobrado) -and
  (Eq2 (SumMonto $d.filas) $d.total_cobrado)
}

# G3. por_mes julio 670200, noviembre 251000
Assert-OkData $rFull "G3. por_mes julio=670200, nov=251000" {
  param($d) (Eq2 (FindMonto $d.por_mes 'mes' '2026-07') 670200) -and (Eq2 (FindMonto $d.por_mes 'mes' '2026-11') 251000)
}

# G4. por_medio efectivo 300200, transferencia 621000
Assert-OkData $rFull "G4. por_medio efectivo=300200, transf=621000" {
  param($d) (Eq2 (FindMonto $d.por_medio 'medio_pago' 'efectivo') 300200) -and (Eq2 (FindMonto $d.por_medio 'medio_pago' 'transferencia_bancaria') 621000)
}

# G5. otros_movimientos extra 8500, NO sumado al headline
Assert-OkData $rFull "G5. otros extra=8500 NO sumado (total sigue 921200)" {
  param($d) (Eq2 (FindMonto $d.otros_movimientos.por_tipo 'tipo' 'extra') 8500) -and (Eq2 $d.total_cobrado 921200)
}

# G8. headline solo sena/saldo
Assert-OkData $rFull "G8. por_tipo solo sena/saldo" {
  param($d) @($d.por_tipo | Where-Object { @('sena','saldo') -notcontains $_.tipo }).Count -eq 0
}

# G6. REGRESION: default {} -> vacio OK hoy (floor futuro) Y periodo_hasta OMITIDO preservado.
#     Si el gateway rellenara hoy en value, el wrapper veria explicito<floor -> payload_invalido.
#     Que devuelva ok:true con total_cobrado=0 prueba que la ausencia se preservo.
$r = Invoke-Gateway -Action $ACT -Payload @{} -Jwt $jwtVicky
Assert-OkData $r "G6. default {} vacio + periodo_hasta omitido preservado (ok:true, total=0)" {
  param($d) (Eq2 $d.total_cobrado 0) -and (@(Filas $d).Count -eq 0)
}

# G7. periodo_desde<floor recortado -> 921200
$r = Invoke-Gateway -Action $ACT -Payload @{ periodo_desde = "2026-06-01"; periodo_hasta = $HASTA; limit = [int]200 } -Jwt $jwtVicky
Assert-OkData $r "G7. periodo_desde<floor recortado (total=921200)" { param($d) Eq2 $d.total_cobrado 921200 }

# G9. paginacion limit=1 -> 1 fila, total=4
$rG9 = Invoke-Gateway -Action $ACT -Payload @{ periodo_hasta = $HASTA; limit = [int]1; offset = [int]0 } -Jwt $jwtVicky
Assert-OkData $rG9 "G9. limit=1 (1 fila, total=4)" { param($d) (@(Filas $d).Count -le 1) -and ($d.total -eq 4) -and ($d.limit -eq 1) }

# G10. paginacion offset -> pagina distinta
$rG10 = Invoke-Gateway -Action $ACT -Payload @{ periodo_hasta = $HASTA; limit = [int]2; offset = [int]2 } -Jwt $jwtVicky
Assert-OkData $rG10 "G10. limit=2 offset=2 (pagina distinta)" {
  param($d)
  $idsA = @(Filas $rG9.data | ForEach-Object { $_.id_pago })
  $idsB = @(Filas $d | ForEach-Object { $_.id_pago })
  $solapan = @($idsB | Where-Object { $idsA -contains $_ }).Count
  ($d.offset -eq 2) -and ($solapan -eq 0 -or @($idsB).Count -eq 0)
}

# ============================ PAYLOAD INVALIDO (vicky) ============================
Write-Host "`n----- PAYLOAD INVALIDO (gateway) -----" -ForegroundColor Magenta

# P1. clave no permitida
$r = Invoke-Gateway -Action $ACT -Payload @{ foo = 1 } -Jwt $jwtVicky
Assert-Code $r "P1. clave no permitida -> payload_invalido" "payload_invalido"

# P2. periodo_desde mal formado
$r = Invoke-Gateway -Action $ACT -Payload @{ periodo_desde = "2026-13-01" } -Jwt $jwtVicky
Assert-Code $r "P2. periodo_desde mal formado -> payload_invalido" "payload_invalido"

# P3. REGRESION: rango explicitamente invertido -> payload_invalido (rebota en el gateway)
$r = Invoke-Gateway -Action $ACT -Payload @{ periodo_desde = "2026-08-01"; periodo_hasta = "2026-07-01" } -Jwt $jwtVicky
Assert-Code $r "P3. inversion explicita -> payload_invalido" "payload_invalido"

# P4. periodo_hasta mal formado
$r = Invoke-Gateway -Action $ACT -Payload @{ periodo_hasta = "2026-02-31" } -Jwt $jwtVicky
Assert-Code $r "P4. periodo_hasta mal formado -> payload_invalido" "payload_invalido"

# P5. REGRESION: periodo_hasta null EXPLICITO -> payload_invalido (no se trata como omitido)
$r = Invoke-Gateway -Action $ACT -Payload @{ periodo_hasta = $null } -Jwt $jwtVicky
Assert-Code $r "P5. periodo_hasta null explicito -> payload_invalido" "payload_invalido"

# P6. limit no entero
$r = Invoke-Gateway -Action $ACT -Payload @{ limit = "x" } -Jwt $jwtVicky
Assert-Code $r "P6. limit no entero -> payload_invalido" "payload_invalido"

# P7a. payload string -> payload_invalido
$r = Invoke-Gateway -Action $ACT -Payload "soy_un_string" -Jwt $jwtVicky
Assert-Code $r "P7a. payload string -> payload_invalido" "payload_invalido"

# P7b. payload array -> payload_invalido
$r = Invoke-Gateway -Action $ACT -Payload @(1, 2, 3) -Jwt $jwtVicky
Assert-Code $r "P7b. payload array -> payload_invalido" "payload_invalido"

# ============================ META ============================
Write-Host "`n----- META -----" -ForegroundColor Magenta
Assert-AllowlistMeta

Summary
Write-Host ""
Write-Host "Nota: el default {} hoy da total_cobrado=0 (floor futuro) y es PASS." -ForegroundColor DarkGray
