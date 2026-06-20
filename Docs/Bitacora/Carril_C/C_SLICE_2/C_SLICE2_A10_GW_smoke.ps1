# ============================================================================
# C_SLICE2_A10_GW_smoke.ps1 -- Smoke GATEWAY de A10 (8 casos a-g + R) + META allowlist.
#
# End-to-end por el gateway portal-api -> wrapper A10 firmado. El actor NO lo manda el
# smoke: lo inyecta el gateway desde el JWT (portal_usuarios.nombre). TEST only.
#
# PRE-CONDICIONES (ver C_SLICE2_A10_GW_RUNSHEET.md):
#   - portal-api PARCHEADO (con cobranza.registrar_saldo) desplegado en TEST.
#   - Wrapper A10 portal-a10-registrar-saldo__TEST ACTIVO (el gateway despacha a su webhook).
#   - W09 (vita_w09_cobranza_posterior) INACTIVO.
#   - A10_setup.sql corrido FRESCO (fixtures 9900001..9900007; self-cleaning).
#
# Casos a/b ESCRIBEN (pagos de saldo). R (sobrepago) NO escribe. c/d/e/f/g rebotan en el gateway.
#
# Requiere: VITA_SUPABASE_URL_TEST, VITA_SUPABASE_ANON_TEST,
#           VITA_PW_VICKY, VITA_PW_FRANCO, VITA_PW_JENNY.
# Identidades hardcodeadas (reconciliadas con C_SLICE2_A08_GW_smoke.ps1).
# ============================================================================
. "$PSScriptRoot\C_SLICE2_A10_GW_common.ps1"

function Near { param($a, $b) return ([math]::Abs([double]$a - [double]$b) -lt 0.01) }
function P {
  param($res, $monto, $key, $medio = 'transferencia_mp')
  return [ordered]@{ id_reserva = $res; monto = $monto; medio_pago = $medio; idempotency_key = $key; notas = 'gw smoke' }
}

$EMAIL_VICKY  = 'vicky@vitadelta.test'
$EMAIL_FRANCO = 'franco@vitadelta.test'
$EMAIL_JENNY  = 'jenny@vitadelta.test'
foreach ($pair in @(
    @('VITA_PW_VICKY',$env:VITA_PW_VICKY), @('VITA_PW_FRANCO',$env:VITA_PW_FRANCO), @('VITA_PW_JENNY',$env:VITA_PW_JENNY))) {
  if ([string]::IsNullOrEmpty($pair[1])) { throw ('Falta ' + $pair[0]) }
}

Write-Host "=== A10 GW smoke ==="
$jwtVicky  = Get-PortalJwt -Identity $EMAIL_VICKY  -Password $env:VITA_PW_VICKY
$jwtFranco = Get-PortalJwt -Identity $EMAIL_FRANCO -Password $env:VITA_PW_FRANCO
$jwtJenny  = Get-PortalJwt -Identity $EMAIL_JENNY  -Password $env:VITA_PW_JENNY
if (-not $jwtVicky -or -not $jwtFranco -or -not $jwtJenny) {
  Write-Host "FALTA algun JWT (corre el precheck primero)." -ForegroundColor Red
  exit 1
}

$ACTION = 'cobranza.registrar_saldo'

# a FELIZ vicky: 9900001 saldo 70000, paga 50000 -> ok, nuevo, saldo 20000 (validado_por=vicky en verif SQL).
$ra = Invoke-Gateway -Action $ACTION -Payload (P 9900001 50000 'a10gwAvicky00001') -Jwt $jwtVicky
Assert-OkData $ra 'a FELIZ vicky (9900001, 50000 -> 20000)' { param($d) (-not $d.idempotent_match) -and (Near $d.saldo_real_actual 20000) }

# b FELIZ socio/franco: 9900002 saldo 70000, paga 70000 -> ok, saldo 0 (validado_por=franco en verif SQL).
$rb = Invoke-Gateway -Action $ACTION -Payload (P 9900002 70000 'a10gwBsocio00001') -Jwt $jwtFranco
Assert-OkData $rb 'b FELIZ socio/franco (9900002, 70000 -> 0)' { param($d) (Near $d.saldo_real_actual 0) }

# c jenny -> rol_no_permitido (allowlist del gateway, ANTES de firmar; no toca n8n).
$rc = Invoke-Gateway -Action $ACTION -Payload (P 9900001 10000 'a10gwCjenny00001') -Jwt $jwtJenny
Assert-Code $rc 'c jenny -> rol_no_permitido' 'rol_no_permitido'

# d sin JWT -> no_autorizado.
$rd = Invoke-Gateway -Action $ACTION -Payload (P 9900001 10000 'a10gwDnojwt00001') -Jwt $null
Assert-Code $rd 'd sin JWT -> no_autorizado' 'no_autorizado'

# e payload invalido (medio_pago mp_link, NO expuesto por A10) -> payload_invalido (gateway, antes de firmar).
$ePayload = [ordered]@{ id_reserva = 9900001; monto = 10000; medio_pago = 'mp_link'; idempotency_key = 'a10gwEinval00001'; notas = 'gw smoke' }
$re = Invoke-Gateway -Action $ACTION -Payload $ePayload -Jwt $jwtVicky
Assert-Code $re 'e payload invalido (mp_link) -> payload_invalido' 'payload_invalido'

# f spoof actor en payload (clave extra 'actor') -> payload_invalido (reject-unknown).
# Demuestra que el frontend NO puede inyectar el actor: viaja en el sobre, server-side.
$fPayload = [ordered]@{ id_reserva = 9900001; monto = 10000; medio_pago = 'transferencia_mp'; idempotency_key = 'a10gwFspoof00001'; notas = 'gw smoke'; actor = 'franco' }
$rf = Invoke-Gateway -Action $ACTION -Payload $fPayload -Jwt $jwtVicky
Assert-Code $rf 'f spoof actor en payload -> payload_invalido (reject-unknown)' 'payload_invalido'

# g action inexistente -> accion_desconocida.
$rg = Invoke-Gateway -Action 'cobranza.registrar_saldo_X' -Payload (P 9900001 10000 'a10gwGactionX0001') -Jwt $jwtVicky
Assert-Code $rg 'g action inexistente -> accion_desconocida' 'accion_desconocida'

# R REGRESION SOBREPAGO (obligatoria): 9900006 saldo 70000, paga 80000 (> saldo) ->
# conflicto, NUNCA estado_incierto, sin escritura. Prueba end-to-end que dispatchN8n/noConfiable
# no enmascara un write con estado_incierto (el wrapper devuelve excede_saldo->conflicto, 200).
$rR = Invoke-Gateway -Action $ACTION -Payload (P 9900006 80000 'a10gwRsobrepg0001') -Jwt $jwtVicky
Assert-Code-NotIncierto $rR 'R SOBREPAGO regresion (9900006, 80000 > 70000) -> conflicto' 'conflicto'

Write-Host ""
Write-Host "=== meta-check allowlist ==="
Assert-AllowlistMeta

Summary
Write-Host ""
Write-Host "NOTA: verificar con C_SLICE2_A10_GW_verif.sql ->"
Write-Host "      a: 9900001 1 pago saldo 50000 validado_por=vicky ; b: 9900002 1 pago saldo 70000 validado_por=franco ;"
Write-Host "      R: 9900006 SIN pago de saldo (la regresion no escribe). c/d/e/f/g no escriben."
