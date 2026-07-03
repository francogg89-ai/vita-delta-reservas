# HORARIOS_A07UX_smoke_e2e_TEST.ps1
# Mini-bloque UX A07: un override corrupto (dejado por el [SETUP] del SQL de
# fixtures) debe viajar como payload_invalido con el message
# 'datos de reserva rechazados: override_hora_invalido'.
#
# SOLO TEST. Firma HMAC sobre el raw body (Modo B). A07 NO usa nonce.
# El HARD del resolver corta en el bloque 3.5, antes de upsert_huesped/INSERT:
# este smoke NO consume secuencias y no crea pre-reserva ni huesped.
#
# ORDEN: HORARIOS_A07UX_SETUP_TEST.sql -> este smoke -> HORARIOS_A07UX_TEARDOWN_TEST.sql (SIEMPRE, pase o falle).

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ---- Parametros (EDITAR) ----
$BaseUrl  = 'https://federicosecchi.app.n8n.cloud'   # base de n8n TEST
$Secret   = 'NO_COMMIT'                 # mismo VITA_HMAC_SECRET del wrapper A07 TEST
$IdCabana = 1                                        # <-- id_cabana impreso por el [SETUP]
$FechaIn  = '2027-06-15'
$FechaOut = '2027-06-17'

if ($Secret -like '__PEGAR_*') { throw 'Configura $Secret con el VITA_HMAC_SECRET de A07 TEST.' }
if ($IdCabana -le 0)           { throw 'Configura $IdCabana con el id impreso por el [SETUP].' }

# ---- Body firmado. Payload SOLO con claves PERMITIDAS por el wrapper A07
#      (sin canal_origen/source_event/idempotency_key: los deriva el wrapper).
#      medio_pago es requerido; ambiente_esperado debe ser 'test'. ----
$ts = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$json = '{"ts":' + $ts + ',"rol":"vicky","action":"reserva.crear_manual","actor":"vicky","ambiente_esperado":"test","payload":{"id_cabana":' + $IdCabana + ',"fecha_in":"' + $FechaIn + '","fecha_out":"' + $FechaOut + '","personas":2,"monto_total":100000,"monto_sena":30000,"canal_pago_esperado":"efectivo","medio_pago":"efectivo","huesped":{"nombre":"SMOKE_A07_OVR","telefono":"1177777777"}}}'

$bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
$hmac = New-Object System.Security.Cryptography.HMACSHA256
$hmac.Key = [System.Text.Encoding]::UTF8.GetBytes($Secret)
$sig = 'sha256=' + (($hmac.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '')

$url = $BaseUrl.TrimEnd('/') + '/webhook/portal-a07-crear-reserva__TEST'
$headers = @{ 'x-vita-signature' = $sig }

Write-Host ('POST ' + $url)
Write-Host ('body: ' + $json)

try {
  $resp = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -ContentType 'application/json' -Body $bytes
} catch {
  Write-Host ('ERROR HTTP: ' + $_.Exception.Message) -ForegroundColor Red
  Write-Host 'Corre HORARIOS_A07UX_TEARDOWN_TEST.sql igual.' -ForegroundColor Yellow
  exit 2
}

$respJson = $resp | ConvertTo-Json -Depth 8 -Compress
Write-Host ('respuesta: ' + $respJson)

# ---- Asercion: ok=false, code=payload_invalido, message contiene override_hora_invalido ----
$okFalse = ($resp.ok -eq $false)
$code = ''
$msg  = ''
if ($resp.error) { $code = [string]$resp.error.code; $msg = [string]$resp.error.message }
$codeOk = ($code -eq 'payload_invalido')
$msgOk  = ($msg -like '*override_hora_invalido*')

if ($okFalse -and $codeOk -and $msgOk) {
  Write-Host 'PASS: override_hora_invalido -> payload_invalido' -ForegroundColor Green
  Write-Host 'Recorda: corre HORARIOS_A07UX_TEARDOWN_TEST.sql para borrar el override del fixture.' -ForegroundColor Yellow
  exit 0
} else {
  Write-Host ('FAIL: ok=' + [string]$resp.ok + ' code=' + $code + ' msg=' + $msg) -ForegroundColor Red
  Write-Host 'Corre HORARIOS_A07UX_TEARDOWN_TEST.sql igual.' -ForegroundColor Yellow
  exit 1
}
