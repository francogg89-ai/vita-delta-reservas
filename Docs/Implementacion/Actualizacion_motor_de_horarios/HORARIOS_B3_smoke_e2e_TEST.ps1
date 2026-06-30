# ============================================================================
# HORARIOS_B3_smoke_e2e_TEST.ps1
# Bloque 3 (UX wrappers) - Smoke E2E via gateway (portal-api -> wrapper A07/A08).
# Verifica que, tras agregar 'fecha_in_pasada'/'rango_pasado' a payloadInv, el
# error nuevo del guard SQL llega al wrapper y se mapea a payload_invalido (no
# error_interno), con mensaje especifico.
#
# AJUSTE OBLIGATORIO 1: payload VALIDO salvo el defecto que probamos.
#   A07: id_cabana real, fecha_in PASADA, fecha_out>fecha_in, huesped valido,
#        montos/personas/canal validos. Lo unico mal es la fecha pasada.
#   A08: id_cabana real (no NULL), rango COMPLETAMENTE pasado, motivo valido.
#   El actor/source_event los inyecta el gateway desde el JWT (NO van en payload).
#
# SIN CONSUMO: el guard SQL corta antes de cualquier INSERT/nextval -> no crea
# filas ni consume secuencias.
#
# ASCII puro (PS 5.1 lee .ps1 como Windows-1252; sin acentos ni em-dash). 5.1/7.
# Requisitos: VITA_SUPABASE_URL_TEST, VITA_SUPABASE_ANON_TEST, VITA_PW_VICKY.
#   Workflows A07 y A08 ACTIVOS y con el cambio de payloadInv ya guardado.
# Uso: powershell -ExecutionPolicy Bypass -File .\HORARIOS_B3_smoke_e2e_TEST.ps1 -IdCabana 4
# Exit: 0 = todo PASS | 1 = algun FAIL | 2 = falta env var
# ============================================================================
param(
  [string]$SupabaseUrl = $env:VITA_SUPABASE_URL_TEST,
  [string]$AnonKey     = $env:VITA_SUPABASE_ANON_TEST,
  [int]$IdCabana       = 4
)
$ErrorActionPreference = "Stop"
if (-not $SupabaseUrl) { Write-Host "FALTA: setea `$env:VITA_SUPABASE_URL_TEST" -ForegroundColor Red; exit 2 }
if (-not $AnonKey)     { Write-Host "FALTA: setea `$env:VITA_SUPABASE_ANON_TEST" -ForegroundColor Red; exit 2 }
if (-not $env:VITA_PW_VICKY) { Write-Host "FALTA: setea `$env:VITA_PW_VICKY" -ForegroundColor Red; exit 2 }
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

$jwtVicky = Get-Jwt 'vicky@vitadelta.test' $env:VITA_PW_VICKY
if (-not $jwtVicky) { Write-Host "FALLO: no se pudo obtener JWT de vicky." -ForegroundColor Red; exit 1 }

# Fechas PASADAS (margen de 8-10 dias: seguro pasado en AR sin importar UTC).
$past_in   = (Get-Date).Date.AddDays(-10).ToString('yyyy-MM-dd')
$past_out  = (Get-Date).Date.AddDays(-8).ToString('yyyy-MM-dd')

# Payload A07: VALIDO salvo fecha_in pasada (id_cabana real, huesped con telefono).
$pA07 = [ordered]@{
  id_cabana=$IdCabana; fecha_in=$past_in; fecha_out=$past_out; personas=2;
  monto_total=100000; monto_sena=50000;
  canal_pago_esperado='efectivo'; medio_pago='efectivo';
  huesped=[ordered]@{ nombre='SMOKE B3 A07'; telefono='+5490000000901' }
}
# Payload A08: VALIDO salvo rango completamente pasado (id_cabana real, motivo valido).
$pA08 = [ordered]@{
  id_cabana=$IdCabana; fecha_desde=$past_in; fecha_hasta=$past_out; motivo='mantenimiento'
}

Write-Host "`n=== SMOKE E2E B3 (gateway portal-api) ===" -ForegroundColor Cyan
Write-Host "URL: $fnUrl   id_cabana: $IdCabana   fecha_in/desde: $past_in   fecha_out/hasta: $past_out`n"
$pass = 0; $total = 2

# A07) reserva.crear_manual, fecha_in pasada -> payload_invalido con 'fecha_in_pasada'
$r = Invoke-Gw $jwtVicky 'reserva.crear_manual' $pA07
$okc = ([bool]$r.ok -eq $false) -and ($r.error.code -eq 'payload_invalido') -and ([string]$r.error.message -match 'fecha_in_pasada')
if ($okc) { $pass++; Write-Host ("  [PASS] A07 fecha_in pasada -> code={0} msg='{1}'" -f $r.error.code, $r.error.message) -ForegroundColor Green }
else { Write-Host ("  [FAIL] A07 fecha_in pasada -> {0}" -f ($r | ConvertTo-Json -Compress -Depth 6)) -ForegroundColor Red }

# A08) bloqueo.crear_manual, rango pasado -> payload_invalido con 'rango_pasado'
$r = Invoke-Gw $jwtVicky 'bloqueo.crear_manual' $pA08
$okc = ([bool]$r.ok -eq $false) -and ($r.error.code -eq 'payload_invalido') -and ([string]$r.error.message -match 'rango_pasado')
if ($okc) { $pass++; Write-Host ("  [PASS] A08 rango pasado    -> code={0} msg='{1}'" -f $r.error.code, $r.error.message) -ForegroundColor Green }
else { Write-Host ("  [FAIL] A08 rango pasado    -> {0}" -f ($r | ConvertTo-Json -Compress -Depth 6)) -ForegroundColor Red }

$col = if ($pass -eq $total) { 'Green' } else { 'Red' }
Write-Host ("`nResultado: {0}/{1} PASS" -f $pass, $total) -ForegroundColor $col
if ($pass -ne $total) { exit 1 }
Write-Host "B3 E2E verde: el guard SQL llega al wrapper y se mapea a payload_invalido." -ForegroundColor Green
exit 0
