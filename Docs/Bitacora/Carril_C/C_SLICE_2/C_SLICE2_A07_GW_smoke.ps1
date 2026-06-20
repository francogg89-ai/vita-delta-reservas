# ============================================================================
# C_SLICE2_A07_GW - SMOKE VIA GATEWAY (portal-api -> wrapper A07)
# Corre los casos end-to-end a traves del gateway con JWT real. ASCII puro
# (PS 5.1 lee .ps1 como Windows-1252; sin acentos ni em-dash). Compatible 5.1/7.
#
# Casos:
#   a) vicky  + reserva.crear_manual + payload valido -> ok (crea; actor=vicky)
#   b) franco + reserva.crear_manual + payload valido -> ok (crea; actor=franco)
#   c) jenny  + reserva.crear_manual                  -> rol_no_permitido (gateway)
#   d) SIN JWT + reserva.crear_manual                 -> no_autorizado
#   e) vicky  + payload invalido (sena>total)         -> payload_invalido (gateway)
#   f) vicky  + actor DENTRO del payload (spoof)       -> payload_invalido (reject-unknown)
#   g) vicky  + action inexistente                    -> accion_desconocida
#
# El actor lo inyecta el gateway desde el JWT (el smoke NO lo manda): los casos a/b
# prueban la inyeccion server-side; el verif SQL confirma validado_por/created_by.
#
# Requisitos (mismas env vars del precheck): VITA_SUPABASE_URL_TEST,
# VITA_SUPABASE_ANON_TEST, VITA_PW_VICKY, VITA_PW_FRANCO, VITA_PW_JENNY.
# Correr DESPUES del precheck en verde y del gate residual = 0. Workflow A07 ACTIVO.
# Uso:  powershell -ExecutionPolicy Bypass -File .\C_SLICE2_A07_GW_smoke.ps1
# ============================================================================
param(
  [string]$SupabaseUrl = $env:VITA_SUPABASE_URL_TEST,
  [string]$AnonKey     = $env:VITA_SUPABASE_ANON_TEST
)
$ErrorActionPreference = "Stop"
if (-not $SupabaseUrl) { Write-Host "FALTA: setea `$env:VITA_SUPABASE_URL_TEST" -ForegroundColor Red; exit 1 }
if (-not $AnonKey)     { Write-Host "FALTA: setea `$env:VITA_SUPABASE_ANON_TEST" -ForegroundColor Red; exit 1 }
$SupabaseUrl = $SupabaseUrl.TrimEnd('/')
$fnUrl = "$SupabaseUrl/functions/v1/portal-api"

function Get-Jwt {
  param($email, $pw)
  if (-not $pw) { return $null }
  $body = @{ email=$email; password=$pw } | ConvertTo-Json -Compress
  try {
    $r = Invoke-RestMethod -Uri "$SupabaseUrl/auth/v1/token?grant_type=password" -Method Post `
                           -Headers @{ apikey=$AnonKey } -ContentType "application/json" -Body $body
    return $r.access_token
  } catch { return $null }
}
function Invoke-Gw {
  param($jwt, $action, $payload)
  $body = @{ action=$action; payload=$payload } | ConvertTo-Json -Compress -Depth 8
  $headers = @{ apikey=$AnonKey }
  if ($jwt) { $headers['Authorization'] = "Bearer $jwt" }
  try {
    return Invoke-RestMethod -Uri $fnUrl -Method Post -Headers $headers -ContentType "application/json" -Body $body
  } catch {
    $resp = $_.Exception.Response
    if ($resp) { $sr = New-Object System.IO.StreamReader($resp.GetResponseStream()); $t = $sr.ReadToEnd()
                 try { return ($t | ConvertFrom-Json) } catch { return @{ ok=$false; error=@{ code='_http'; message=$t } } } }
    return @{ ok=$false; error=@{ code='_neterr'; message=$_.Exception.Message } }
  }
}

# JWTs (deberian existir: el precheck paso en verde).
$jwtVicky  = Get-Jwt 'vicky@vitadelta.test'  $env:VITA_PW_VICKY
$jwtFranco = Get-Jwt 'franco@vitadelta.test' $env:VITA_PW_FRANCO
$jwtJenny  = Get-Jwt 'jenny@vitadelta.test'  $env:VITA_PW_JENNY
if (-not $jwtVicky -or -not $jwtFranco -or -not $jwtJenny) {
  Write-Host "FALLO: no se pudieron obtener los 3 JWT. Corre primero el precheck y resolve Auth." -ForegroundColor Red
  exit 1
}

# Fixtures de negocio (SIN actor: el gateway lo inyecta). Huespedes 'PORTAL TEST A07 GW *'.
$pVicky = [ordered]@{ id_cabana=4; fecha_in='2027-07-01'; fecha_out='2027-07-03'; personas=2; monto_total=100000; monto_sena=50000; canal_pago_esperado='transferencia_mp'; medio_pago='transferencia_mp'; huesped=[ordered]@{ nombre='PORTAL TEST A07 GW VICKY'; telefono='+5490000000801' } }
$pSocio = [ordered]@{ id_cabana=5; fecha_in='2027-07-01'; fecha_out='2027-07-03'; personas=2; monto_total=80000;  monto_sena=40000; canal_pago_esperado='transferencia_mp'; medio_pago='transferencia_mp'; huesped=[ordered]@{ nombre='PORTAL TEST A07 GW SOCIO'; telefono='+5490000000802' } }
# Invalido (sena > total) para el caso e.
$pInval = [ordered]@{ id_cabana=4; fecha_in='2027-07-10'; fecha_out='2027-07-12'; personas=2; monto_total=50000; monto_sena=99999; canal_pago_esperado='transferencia_mp'; medio_pago='transferencia_mp'; huesped=[ordered]@{ nombre='PORTAL TEST A07 GW INVAL'; telefono='+5490000000803' } }
# Spoof: actor DENTRO del payload (clave no permitida) para el caso f.
$pSpoof = [ordered]@{ id_cabana=4; fecha_in='2027-07-20'; fecha_out='2027-07-22'; personas=2; monto_total=50000; monto_sena=25000; canal_pago_esperado='transferencia_mp'; medio_pago='transferencia_mp'; actor='franco'; huesped=[ordered]@{ nombre='PORTAL TEST A07 GW SPOOF'; telefono='+5490000000804' } }

Write-Host "`n=== SMOKE VIA GATEWAY A07 (portal-api) ===" -ForegroundColor Cyan
Write-Host "URL: $fnUrl`n"
$pass = 0; $total = 7

# a) vicky feliz
$r = Invoke-Gw $jwtVicky 'reserva.crear_manual' $pVicky
$okc = ([bool]$r.ok -eq $true) -and ($r.data.id_reserva)
if ($okc) { $pass++; Write-Host ("  [PASS] a vicky feliz  -> id_reserva={0} idempotent={1}" -f $r.data.id_reserva, $r.data.idempotent_match) -ForegroundColor Green }
else { Write-Host ("  [FAIL] a vicky feliz  -> {0}" -f ($r | ConvertTo-Json -Compress -Depth 6)) -ForegroundColor Red }

# b) franco (socio) feliz
$r = Invoke-Gw $jwtFranco 'reserva.crear_manual' $pSocio
$okc = ([bool]$r.ok -eq $true) -and ($r.data.id_reserva)
if ($okc) { $pass++; Write-Host ("  [PASS] b socio feliz   -> id_reserva={0} idempotent={1}" -f $r.data.id_reserva, $r.data.idempotent_match) -ForegroundColor Green }
else { Write-Host ("  [FAIL] b socio feliz   -> {0}" -f ($r | ConvertTo-Json -Compress -Depth 6)) -ForegroundColor Red }

# c) jenny -> rol_no_permitido
$r = Invoke-Gw $jwtJenny 'reserva.crear_manual' $pVicky
$okc = ([bool]$r.ok -eq $false) -and ($r.error.code -eq 'rol_no_permitido')
if ($okc) { $pass++; Write-Host "  [PASS] c jenny          -> rol_no_permitido" -ForegroundColor Green }
else { Write-Host ("  [FAIL] c jenny          -> {0}" -f ($r | ConvertTo-Json -Compress -Depth 6)) -ForegroundColor Red }

# d) sin JWT -> no_autorizado
$r = Invoke-Gw $null 'reserva.crear_manual' $pVicky
$okc = ([bool]$r.ok -eq $false) -and ($r.error.code -eq 'no_autorizado')
if ($okc) { $pass++; Write-Host "  [PASS] d sin JWT        -> no_autorizado" -ForegroundColor Green }
else { Write-Host ("  [FAIL] d sin JWT        -> {0}" -f ($r | ConvertTo-Json -Compress -Depth 6)) -ForegroundColor Red }

# e) payload invalido (sena>total) -> payload_invalido
$r = Invoke-Gw $jwtVicky 'reserva.crear_manual' $pInval
$okc = ([bool]$r.ok -eq $false) -and ($r.error.code -eq 'payload_invalido')
if ($okc) { $pass++; Write-Host "  [PASS] e payload invalido -> payload_invalido" -ForegroundColor Green }
else { Write-Host ("  [FAIL] e payload invalido -> {0}" -f ($r | ConvertTo-Json -Compress -Depth 6)) -ForegroundColor Red }

# f) actor en payload (spoof) -> payload_invalido (reject-unknown; el frontend no inyecta actor)
$r = Invoke-Gw $jwtVicky 'reserva.crear_manual' $pSpoof
$okc = ([bool]$r.ok -eq $false) -and ($r.error.code -eq 'payload_invalido')
if ($okc) { $pass++; Write-Host "  [PASS] f actor en payload -> payload_invalido (spoof rechazado)" -ForegroundColor Green }
else { Write-Host ("  [FAIL] f actor en payload -> {0}" -f ($r | ConvertTo-Json -Compress -Depth 6)) -ForegroundColor Red }

# g) action inexistente -> accion_desconocida
$r = Invoke-Gw $jwtVicky 'reserva.inexistente' @{}
$okc = ([bool]$r.ok -eq $false) -and ($r.error.code -eq 'accion_desconocida')
if ($okc) { $pass++; Write-Host "  [PASS] g action inexistente -> accion_desconocida" -ForegroundColor Green }
else { Write-Host ("  [FAIL] g action inexistente -> {0}" -f ($r | ConvertTo-Json -Compress -Depth 6)) -ForegroundColor Red }

Write-Host ""
$col = if ($pass -eq $total) { "Green" } else { "Red" }
Write-Host ("RESULTADO: {0}/{1} PASS" -f $pass, $total) -ForegroundColor $col
Write-Host "Ahora corre C_SLICE2_A07_GW_verif.sql (GW_VICKY 1/1 actor=vicky; GW_SOCIO 1/1 actor=franco)." 
if ($pass -ne $total) { exit 1 }
