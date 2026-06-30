# ============================================================================
# A26_GW_smoke.ps1 -- smoke GATEWAY de A26 (disponibilidad.cabana) via JWT.
# Carril C / Portal Operativo Interno - Bloque B (cableado de A26 en portal-api).
#
# Se autentica con JWT de Supabase y POSTea { action, payload } a la Edge Function
# portal-api. El gateway valida (payloadDisponibilidadCabana), firma HMAC server-side
# hacia n8n, y el wrapper revalida (2da defensa). Este harness NUNCA ve el secreto HMAC.
#
# Reutiliza el helper comun C_SLICE2_A10_GW_common.ps1 (Get-PortalJwt / Invoke-Gateway /
# Assert-* / Get-GwEnv / Record / Summary). ASCII puro (PS 5.1). Sin -Parallel. Sin if
# inline en -ForegroundColor.
#
# 100% TEST. LECTURA pura: no consume secuencias, no escribe nada.
#
# Variables de entorno (las de A08/A10/A25): VITA_SUPABASE_URL_TEST, VITA_SUPABASE_ANON_TEST,
# VITA_PW_VICKY / VITA_PW_FRANCO / VITA_PW_JENNY.  TEST exclusivamente. No toca OPS.
# ============================================================================

# Ruta al helper comun. EDITAR si esta en otra carpeta (p.ej. ..\C_SLICE_2\).
$CommonPath = Join-Path $PSScriptRoot 'C_SLICE2_A10_GW_common.ps1'
if (-not (Test-Path $CommonPath)) {
  throw "No encuentro C_SLICE2_A10_GW_common.ps1 en '$CommonPath'. Edita la variable `$CommonPath con la ruta correcta."
}
. $CommonPath

$ACT = 'disponibilidad.cabana'

# ---- Parametros TEST (de la corrida del oraculo en Bloque A) ----
$CabValida    = 5              # Tokio (activa). Ajustar si en TEST otra.
$CabInvalida  = 999999         # id positivo sin cabana activa -> no_encontrado
$CabOcup      = 5              # cabana de la ventana con ocupacion (oraculo)
$OcupDesde    = '2026-07-08'   # inclusive
$OcupHasta    = '2026-07-16'   # exclusive  -> 8 noches
$OcupCount    = 8
$DiaBloqueada = '2026-07-08'   # esperado 'bloqueada' (oraculo)
$DiaCheckout  = '2026-07-15'   # esperado 'checkout_disponible' (oraculo)
# Ventana presuntamente LIBRE (lejos): para los OK de seguridad sin depender de ocupacion.
$LibreDesde   = (Get-Date).Date.AddDays(400).ToString('yyyy-MM-dd')
$LibreHasta   = (Get-Date).Date.AddDays(405).ToString('yyyy-MM-dd')

# ---- Helpers locales de dias/estados ----
function Dias { param($d); if ($d -and $d.dias) { return @($d.dias) } ; return @() }
function EstadoDe {
  param($arr, $fecha)
  $e = @($arr | Where-Object { $_.fecha -eq $fecha })
  if ($e.Count -eq 0) { return $null }
  return $e[0].estado
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
Write-Host "Action: $ACT | cabana valida: $CabValida | ventana ocup: $OcupDesde..$OcupHasta" -ForegroundColor DarkGray

# ============================ SEGURIDAD ============================
Write-Host "`n----- SEGURIDAD (gateway) -----" -ForegroundColor Magenta

# 1. vicky OK (ventana libre): ok:true + data.dias no vacio
$r = Invoke-Gateway -Action $ACT -Payload @{ id_cabana = $CabValida; fecha_desde = $LibreDesde; fecha_hasta = $LibreHasta } -Jwt $jwtVicky
Assert-OkData $r "1. vicky OK (ventana libre)" { param($d) (@($d.dias).Count -gt 0) }

# 2. socio (franco) OK
if ($jwtFranco) {
  $r = Invoke-Gateway -Action $ACT -Payload @{ id_cabana = $CabValida; fecha_desde = $LibreDesde; fecha_hasta = $LibreHasta } -Jwt $jwtFranco
  Assert-OkData $r "2. socio (franco) OK" { param($d) (@($d.dias).Count -gt 0) }
} else {
  Record "2. socio (franco) OK" $false "no se obtuvo JWT de franco (revisa VITA_PW_FRANCO)"
}

# 3. jenny -> rol_no_permitido (rebota en el gateway antes de firmar)
if ($jwtJenny) {
  $r = Invoke-Gateway -Action $ACT -Payload @{ id_cabana = $CabValida; fecha_desde = $LibreDesde; fecha_hasta = $LibreHasta } -Jwt $jwtJenny
  Assert-Code $r "3. jenny -> rol_no_permitido" "rol_no_permitido"
} else {
  Record "3. jenny -> rol_no_permitido" $false "no se obtuvo JWT de jenny (revisa VITA_PW_JENNY)"
}

# 4. sin JWT -> no_autorizado
$r = Invoke-Gateway -Action $ACT -Jwt $null
Assert-Code $r "4. sin JWT -> no_autorizado" "no_autorizado"

# 5. action desconocida -> accion_desconocida
$r = Invoke-Gateway -Action 'disponibilidad.inexistente' -Jwt $jwtVicky
Assert-Code $r "5. action desconocida -> accion_desconocida" "accion_desconocida"

# ============================ FUNCIONALES (vicky) ============================
Write-Host "`n----- FUNCIONALES (gateway) -----" -ForegroundColor Magenta

# 6. ventana con ocupacion -> paridad con el oraculo (count + estados clave)
$r = Invoke-Gateway -Action $ACT -Payload @{ id_cabana = $CabOcup; fecha_desde = $OcupDesde; fecha_hasta = $OcupHasta } -Jwt $jwtVicky
Assert-OkData $r "6. ventana ocupacion (count=$OcupCount + bloqueada/checkout)" {
  param($d)
  $dias = @($d.dias)
  if ($dias.Count -ne $OcupCount) { return $false }
  if ((EstadoDe $dias $DiaBloqueada) -ne 'bloqueada') { return $false }
  if ((EstadoDe $dias $DiaCheckout) -ne 'checkout_disponible') { return $false }
  return $true
}

# 7. cabana inexistente/inactiva -> no_encontrado (la funcion NO se evalua, Bloque A)
$r = Invoke-Gateway -Action $ACT -Payload @{ id_cabana = $CabInvalida; fecha_desde = $LibreDesde; fecha_hasta = $LibreHasta } -Jwt $jwtVicky
Assert-Code $r "7. cabana inexistente -> no_encontrado" "no_encontrado"

# 8. rango invertido (hasta <= desde) -> payload_invalido (rebota en el gateway)
$r = Invoke-Gateway -Action $ACT -Payload @{ id_cabana = $CabValida; fecha_desde = '2026-07-20'; fecha_hasta = '2026-07-10' } -Jwt $jwtVicky
Assert-Code $r "8. rango invertido -> payload_invalido" "payload_invalido"

# 9. span > 366 -> payload_invalido
$r = Invoke-Gateway -Action $ACT -Payload @{ id_cabana = $CabValida; fecha_desde = '2026-07-01'; fecha_hasta = '2027-08-01' } -Jwt $jwtVicky
Assert-Code $r "9. span > 366 -> payload_invalido" "payload_invalido"

# 10. id_cabana = 0 -> payload_invalido
$r = Invoke-Gateway -Action $ACT -Payload @{ id_cabana = 0; fecha_desde = $LibreDesde; fecha_hasta = $LibreHasta } -Jwt $jwtVicky
Assert-Code $r "10. id_cabana=0 -> payload_invalido" "payload_invalido"

# 11. id_cabana negativo -> payload_invalido
$r = Invoke-Gateway -Action $ACT -Payload @{ id_cabana = -3; fecha_desde = $LibreDesde; fecha_hasta = $LibreHasta } -Jwt $jwtVicky
Assert-Code $r "11. id_cabana negativo -> payload_invalido" "payload_invalido"

# 12. id_cabana string -> payload_invalido (tipo estricto: number, no '5')
$r = Invoke-Gateway -Action $ACT -Payload @{ id_cabana = '5'; fecha_desde = $LibreDesde; fecha_hasta = $LibreHasta } -Jwt $jwtVicky
Assert-Code $r "12. id_cabana string -> payload_invalido" "payload_invalido"

# 13. clave desconocida en payload -> payload_invalido (reject-unknown)
$r = Invoke-Gateway -Action $ACT -Payload @{ id_cabana = $CabValida; fecha_desde = $LibreDesde; fecha_hasta = $LibreHasta; extra = 'x' } -Jwt $jwtVicky
Assert-Code $r "13. clave desconocida -> payload_invalido" "payload_invalido"

# 14. falta fecha_hasta -> payload_invalido
$r = Invoke-Gateway -Action $ACT -Payload @{ id_cabana = $CabValida; fecha_desde = $LibreDesde } -Jwt $jwtVicky
Assert-Code $r "14. falta fecha_hasta -> payload_invalido" "payload_invalido"

# 15. payload array -> payload_invalido
$r = Invoke-Gateway -Action $ACT -Payload @(1, 2, 3) -Jwt $jwtVicky
Assert-Code $r "15. payload array -> payload_invalido" "payload_invalido"

# ============================ META ============================
Write-Host "`n----- META -----" -ForegroundColor Magenta
Assert-AllowlistMeta

Summary
Write-Host ""
Write-Host "Nota: el caso 6 confirma paridad gateway<->oraculo (Tokio id=5, ventana de Bloque A)." -ForegroundColor DarkGray
