# ============================================================================
# C_SLICE3B_A11_GW_smoke.ps1 -- smoke GATEWAY de A11 (cargar.gasto_interno) por JWT.
# ASCII puro (PS 5.1 / CP1252). Sin -Parallel. Compatible 5.1/7.
#
# A11 es la PRIMERA ESCRITURA NO-IDEMPOTENTE cableada al gateway portal-api. Este
# smoke se autentica con JWT de Supabase y POSTea a la Edge Function portal-api; el
# gateway firma HMAC hacia n8n server-side (este harness NUNCA ve el secreto HMAC).
#
# Capa HTTP/auth/asserts REUTILIZADA del helper congelado C_SLICE2_A10_GW_common.ps1
# (Get-PortalJwt, Assert-Code, Assert-OkData, Assert-Code-NotIncierto, Assert-AllowlistMeta,
# Summary). Aca se agregan helpers locales para A11 porque el request lleva idempotency_key
# como SIBLING de payload (D-C-57): { action, payload, idempotency_key }.
#
# NOTA sobre nonce_replay (Q4): NO es alcanzable de forma representativa via gateway. El
# gateway RE-FIRMA cada request (ts/nonce nuevos en buildSignedEnvelope) y el wrapper DERIVA
# su nonce de la firma esperada recomputada (D-C-56); dos requests del frontend con la misma
# idempotency_key generan firmas distintas -> nonce distinto. nonce_replay queda cubierto por
# el smoke DIRECTO (re-POST byte-identico del sobre). Aca se cubren los otros dos mismatches
# (payload_mismatch / actor_mismatch -> conflicto, NUNCA estado_incierto) y la idempotencia.
#
# ESCRITURAS: la seccion FUNCIONAL hace UNA alta nueva (F1). F2/F3/F4 NO insertan (hit
# idempotente / conflicto). Limpieza por SQL aparte: C_SLICE3B_A11_GW_teardown.sql
# (marcador idempotency_key LIKE 'smoke-a11gw-%'). El runid se imprime al final.
#
# Variables de entorno requeridas:
#   VITA_SUPABASE_URL_TEST   base del proyecto Supabase TEST (https://<ref>.supabase.co)
#   VITA_SUPABASE_ANON_TEST  anon key de TEST (header apikey)
#   VITA_PW_VICKY / VITA_PW_FRANCO / VITA_PW_JENNY   passwords de los 3 usuarios portal
# ============================================================================

$ErrorActionPreference = 'Stop'

# Dot-source del helper congelado (debe estar en el mismo directorio).
. (Join-Path $PSScriptRoot 'C_SLICE2_A10_GW_common.ps1')

$ACTION = 'cargar.gasto_interno'

# Marcador unico por corrida (cumple ^[A-Za-z0-9_-]{8,64}$).
$runid  = "$(Get-Date -Format 'yyyyMMddHHmmss')$(Get-Random -Minimum 100 -Maximum 999)"
$K1     = "smoke-a11gw-$runid-1"     # clave de la alta funcional (la unica que escribe)
$KSEC   = "smoke-a11gw-$runid-sec"   # clave valida para casos de seguridad (no escriben)

# ---------------------------------------------------------------------------
# Helper local: POST crudo de un body arbitrario al gateway (mismo manejo de error
# que Invoke-Gateway del common). Permite mandar idempotency_key sibling y, para la
# regresion de spoof TOP-LEVEL, claves de control extra al tope del request.
# ---------------------------------------------------------------------------
function Invoke-GwRaw {
  param([hashtable]$Body, $Jwt = $null)
  $cfg = Get-GwEnv
  $fnUrl = "$($cfg.url)/functions/v1/portal-api"
  $json = $Body | ConvertTo-Json -Compress -Depth 10
  $headers = @{ apikey = $cfg.anon }
  if ($Jwt) { $headers['Authorization'] = "Bearer $Jwt" }
  try {
    return Invoke-RestMethod -Uri $fnUrl -Method Post -Headers $headers -ContentType 'application/json' -Body $json
  } catch {
    $resp = $_.Exception.Response
    if ($resp) {
      $sr = New-Object System.IO.StreamReader($resp.GetResponseStream())
      $t = $sr.ReadToEnd(); $sr.Close()
      try { return ($t | ConvertFrom-Json) } catch { return [pscustomobject]@{ ok = $false; error = [pscustomobject]@{ code = '__http_error__'; message = $t } } }
    }
    return [pscustomobject]@{ ok = $false; error = [pscustomobject]@{ code = '__network_error__'; message = $_.Exception.Message } }
  }
}

# Body A11 estandar { action, payload, idempotency_key } (idempotency_key SIBLING, D-C-57).
function New-A11Body {
  param([hashtable]$Payload, [string]$Key)
  return @{ action = $ACTION; payload = $Payload; idempotency_key = $Key }
}

# Payload de negocio VALIDO (clase A / caja): sin zona/cabana, sin id_socio, periodo dia 1
# (sintetico 2099 para no contaminar el bootstrap contable de julio 2026), comentario presente.
function New-PayloadValido {
  return @{
    fecha       = '2099-01-15'
    periodo     = '2099-01-01'
    clase       = 'A'
    etiqueta    = 'luz gateway smoke'
    monto       = 1234.50
    pagador_tipo = 'caja'
    comentario  = 'smoke gateway A11'
  }
}

# ---------------------------------------------------------------------------
# JWTs (identidades hardcoded, igual que A08/A10/A25).
# ---------------------------------------------------------------------------
$jwtVicky  = Get-PortalJwt -Identity 'vicky@vitadelta.test'  -Password $env:VITA_PW_VICKY
$jwtFranco = Get-PortalJwt -Identity 'franco@vitadelta.test' -Password $env:VITA_PW_FRANCO
$jwtJenny  = Get-PortalJwt -Identity 'jenny@vitadelta.test'  -Password $env:VITA_PW_JENNY

if (-not $jwtVicky)  { Write-Host 'ADVERTENCIA: sin JWT de vicky (VITA_PW_VICKY). Los casos de vicky fallaran.'  -ForegroundColor Yellow }
if (-not $jwtFranco) { Write-Host 'ADVERTENCIA: sin JWT de franco (VITA_PW_FRANCO). El caso actor_mismatch fallara.' -ForegroundColor Yellow }
if (-not $jwtJenny)  { Write-Host 'ADVERTENCIA: sin JWT de jenny (VITA_PW_JENNY). El caso rol_no_permitido fallara.' -ForegroundColor Yellow }

Write-Host ''
Write-Host '=== SMOKE GATEWAY A11 (cargar.gasto_interno) ==='
Write-Host "runid = $runid   marcador teardown = smoke-a11gw-$runid-%"
Write-Host ''

# ===========================================================================
# SEGURIDAD / TRANSPORTE (0 escrituras: todo rebota antes del dispatch).
# ===========================================================================
Write-Host '--- SEGURIDAD / TRANSPORTE ---'

# S1: jenny (no habilitada, D-C-03) -> rol_no_permitido EN EL GATEWAY (antes de firmar).
Assert-Code (Invoke-GwRaw -Body (New-A11Body -Payload (New-PayloadValido) -Key $KSEC) -Jwt $jwtJenny) `
  'S1 jenny -> rol_no_permitido' 'rol_no_permitido'

# S2: sin JWT -> no_autorizado.
Assert-Code (Invoke-GwRaw -Body (New-A11Body -Payload (New-PayloadValido) -Key $KSEC) -Jwt $null) `
  'S2 sin JWT -> no_autorizado' 'no_autorizado'

# S3: action inexistente -> accion_desconocida.
Assert-Code (Invoke-GwRaw -Body @{ action = 'cargar.gasto_fantasma'; payload = (New-PayloadValido); idempotency_key = $KSEC } -Jwt $jwtVicky) `
  'S3 action inexistente -> accion_desconocida' 'accion_desconocida'

# S4: payload invalido (clase fuera de enum) -> payload_invalido.
$pBadClase = New-PayloadValido; $pBadClase['clase'] = 'B'
Assert-Code (Invoke-GwRaw -Body (New-A11Body -Payload $pBadClase -Key $KSEC) -Jwt $jwtVicky) `
  'S4 clase invalida -> payload_invalido' 'payload_invalido'

# S5: payload no-objeto (string) -> payload_invalido.
Assert-Code (Invoke-GwRaw -Body @{ action = $ACTION; payload = 'no-soy-objeto'; idempotency_key = $KSEC } -Jwt $jwtVicky) `
  'S5 payload string -> payload_invalido' 'payload_invalido'

# S6: idempotency_key AUSENTE (omitida del request) -> payload_invalido (needsIdempotencyKey).
Assert-Code (Invoke-GwRaw -Body @{ action = $ACTION; payload = (New-PayloadValido) } -Jwt $jwtVicky) `
  'S6 idempotency_key ausente -> payload_invalido' 'payload_invalido'

# S7: idempotency_key corta (<8) -> payload_invalido.
Assert-Code (Invoke-GwRaw -Body (New-A11Body -Payload (New-PayloadValido) -Key 'abc123') -Jwt $jwtVicky) `
  'S7 idempotency_key corta -> payload_invalido' 'payload_invalido'

# S8: idempotency_key con simbolos -> payload_invalido.
Assert-Code (Invoke-GwRaw -Body (New-A11Body -Payload (New-PayloadValido) -Key 'clave!@#invalida') -Jwt $jwtVicky) `
  'S8 idempotency_key con simbolos -> payload_invalido' 'payload_invalido'

# S9: idempotency_key vacia -> payload_invalido.
Assert-Code (Invoke-GwRaw -Body (New-A11Body -Payload (New-PayloadValido) -Key '') -Jwt $jwtVicky) `
  'S9 idempotency_key vacia -> payload_invalido' 'payload_invalido'

# ===========================================================================
# SPOOF de campos de control DENTRO del payload de negocio -> payload_invalido
# (reject-unknown + rechazo explicito del validador A11; ajuste D-C / microcorr).
# ===========================================================================
Write-Host '--- SPOOF control EN payload ---'
foreach ($ck in @('actor','rol','nonce','source_event','creado_por','request_ts','idempotency_key')) {
  $pSpoof = New-PayloadValido
  $pSpoof[$ck] = 'spoofed'
  Assert-Code (Invoke-GwRaw -Body (New-A11Body -Payload $pSpoof -Key $KSEC) -Jwt $jwtVicky) `
    "SP-payload $ck -> payload_invalido" 'payload_invalido'
}

# ===========================================================================
# SPOOF de campos de control TOP-LEVEL del request (microcorreccion obligatoria):
# el frontend NO puede inyectar control al tope. -> payload_invalido (guard global).
# ===========================================================================
Write-Host '--- SPOOF control TOP-LEVEL (microcorreccion) ---'

# ST1: combo de TODOS los control al tope (uno o varios, como permite Franco).
$bodyComboSpoof = New-A11Body -Payload (New-PayloadValido) -Key $KSEC
$bodyComboSpoof['actor']        = 'franco'
$bodyComboSpoof['rol']          = 'socio'
$bodyComboSpoof['nonce']        = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
$bodyComboSpoof['source_event'] = 'portal_a11_spoof'
$bodyComboSpoof['creado_por']   = 'franco'
$bodyComboSpoof['request_ts']   = 1700000000000
Assert-Code (Invoke-GwRaw -Body $bodyComboSpoof -Jwt $jwtVicky) `
  'ST1 spoof combo top-level -> payload_invalido' 'payload_invalido'

# ST2: solo actor al tope -> payload_invalido (actor lo inyecta el gateway desde el JWT).
$bodyActorSpoof = New-A11Body -Payload (New-PayloadValido) -Key $KSEC
$bodyActorSpoof['actor'] = 'rodrigo'
Assert-Code (Invoke-GwRaw -Body $bodyActorSpoof -Jwt $jwtVicky) `
  'ST2 spoof actor top-level -> payload_invalido' 'payload_invalido'

# ST3: solo nonce al tope -> payload_invalido (el nonce lo deriva el wrapper, D-C-56).
$bodyNonceSpoof = New-A11Body -Payload (New-PayloadValido) -Key $KSEC
$bodyNonceSpoof['nonce'] = 'deadbeef'
Assert-Code (Invoke-GwRaw -Body $bodyNonceSpoof -Jwt $jwtVicky) `
  'ST3 spoof nonce top-level -> payload_invalido' 'payload_invalido'

# ===========================================================================
# FUNCIONAL (escribe F1; F2/F3/F4 no insertan). Asserts Q4 con Assert-Code-NotIncierto.
# ===========================================================================
Write-Host '--- FUNCIONAL ---'

# F1: alta NUEVA (vicky, K1) -> ok + data.id_gasto. Captura el id para F2/F4.
$payloadF1 = New-PayloadValido
$r1 = Invoke-GwRaw -Body (New-A11Body -Payload $payloadF1 -Key $K1) -Jwt $jwtVicky
Assert-OkData $r1 'F1 alta nueva (vicky, K1) -> ok + id_gasto' { param($d) ($null -ne $d.id_gasto) -and ([double]$d.id_gasto -gt 0) }
$id1 = $null
if ($r1 -and $r1.ok -eq $true -and $r1.data) { $id1 = $r1.data.id_gasto }
Write-Host ("    id_gasto F1 = {0}" -f $id1)

# F2: retry idempotente (vicky, K1, MISMO payload) -> ok, idempotente:true, MISMO id_gasto.
$payloadF2 = New-PayloadValido   # identico a F1 -> payload_norm coincide
$r2 = Invoke-GwRaw -Body (New-A11Body -Payload $payloadF2 -Key $K1) -Jwt $jwtVicky
Assert-OkData $r2 'F2 retry idempotente (vicky, K1) -> ok + idempotente:true + mismo id' {
  param($d) ($d.idempotente -eq $true) -and ($null -ne $id1) -and ([double]$d.id_gasto -eq [double]$id1)
}

# F3: misma key, payload DISTINTO (monto distinto, vicky) -> conflicto/payload_mismatch.
#     Q4: NUNCA estado_incierto (que el gateway no enmascare un write).
$payloadF3 = New-PayloadValido; $payloadF3['monto'] = 9999.99
Assert-Code-NotIncierto (Invoke-GwRaw -Body (New-A11Body -Payload $payloadF3 -Key $K1) -Jwt $jwtVicky) `
  'F3 payload_mismatch (vicky, K1, monto distinto) -> conflicto' 'conflicto'

# F4: misma key + MISMO payload, OTRO actor (franco) -> conflicto/actor_mismatch.
#     Tambien valida injectActor: el actor sale del JWT (franco), no del payload; difiere del
#     vicky registrado en F1. Q4: NUNCA estado_incierto.
$payloadF4 = New-PayloadValido   # identico a F1 -> aisla actor_mismatch (no payload_mismatch)
Assert-Code-NotIncierto (Invoke-GwRaw -Body (New-A11Body -Payload $payloadF4 -Key $K1) -Jwt $jwtFranco) `
  'F4 actor_mismatch (franco, K1, mismo payload) -> conflicto' 'conflicto'

# ===========================================================================
# META + cierre.
# ===========================================================================
Write-Host '--- META ---'
Assert-AllowlistMeta

Summary

Write-Host ''
Write-Host '=== TEARDOWN PENDIENTE ==='
Write-Host "F1 escribio UNA alta (id_gasto=$id1). Limpiar con C_SLICE3B_A11_GW_teardown.sql"
Write-Host "Marcador: idempotency_key LIKE 'smoke-a11gw-%' (esta corrida: 'smoke-a11gw-$runid-%')."
