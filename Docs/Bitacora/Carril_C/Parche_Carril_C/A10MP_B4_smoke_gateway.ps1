# ============================================================================
# A10MP_B4_smoke_gateway.ps1
# Carril C / Portal Operativo Interno - A10-MP (cobranza.registrar_cobro).
# Smoke GATEWAY (end-to-end): JWT de Supabase -> Edge Function portal-api -> wrapper firmado.
# El actor NO lo manda el smoke: lo inyecta el gateway desde el JWT (portal_usuarios.nombre).
#
# PRE-CONDICIONES:
#   - portal-api PARCHEADO (bloque 2, con cobranza.registrar_cobro) desplegado en TEST.
#   - Wrapper portal-a10mp-registrar-cobro__TEST ACTIVO.
#   - Fixtures de A10MP_B4_setup.sql (reservas 9910051..9910055).
#
# Verifica el CHAIN gateway->wrapper: 2 altas felices, recargo, idempotencia (match + mismatch),
# rol/payload/sobrepago rebotados, y que el sobrepago da conflicto y NUNCA estado_incierto.
#
# Requiere env: VITA_SUPABASE_URL_TEST, VITA_SUPABASE_ANON_TEST, VITA_PW_VICKY, VITA_PW_FRANCO, VITA_PW_JENNY.
# Identidades <nombre>@vitadelta.test (reconciliadas con A08/A10 GW). ASCII PURO (PS 5.1).
# ============================================================================

$script:passed = 0
$script:failed = 0
$script:failsList = @()
$script:codesSeen = @{}
$script:ALLOWLIST = @('payload_invalido','no_autorizado','rol_no_permitido','accion_desconocida','no_encontrado','conflicto','error_entorno','error_interno','estado_incierto','firma_invalida','ts_fuera_de_ventana','raw_body_ausente','ambiente_incorrecto')

function Get-GwEnv {
  $url = $env:VITA_SUPABASE_URL_TEST
  $anon = $env:VITA_SUPABASE_ANON_TEST
  if ([string]::IsNullOrEmpty($url)) { throw 'Falta VITA_SUPABASE_URL_TEST' }
  if ([string]::IsNullOrEmpty($anon)) { throw 'Falta VITA_SUPABASE_ANON_TEST' }
  return @{ url = $url.TrimEnd('/'); anon = $anon }
}

function Get-PortalJwt {
  param($Identity, $Password)
  if (-not $Password) { return $null }
  $cfg = Get-GwEnv
  $body = @{ email = $Identity; password = $Password } | ConvertTo-Json -Compress
  try {
    $r = Invoke-RestMethod -Uri "$($cfg.url)/auth/v1/token?grant_type=password" -Method Post -Headers @{ apikey = $cfg.anon } -ContentType 'application/json' -Body $body
    return $r.access_token
  } catch { return $null }
}

function Invoke-Gateway {
  param($Action, $Payload = $null, $Jwt = $null)
  $cfg = Get-GwEnv
  $fnUrl = "$($cfg.url)/functions/v1/portal-api"
  $body = @{ action = $Action; payload = $Payload } | ConvertTo-Json -Compress -Depth 8
  $headers = @{ apikey = $cfg.anon }
  if ($Jwt) { $headers['Authorization'] = "Bearer $Jwt" }
  try {
    return Invoke-RestMethod -Uri $fnUrl -Method Post -Headers $headers -ContentType 'application/json' -Body $body
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

function P-Cobro {
  param($res, $ef = 0, $tr = 0, $subtipo = $null, $ot = 0, $origen = $null, $desc = $null, [string]$key, $notas = $null)
  $p = [ordered]@{ id_reserva = $res }
  if ($ef -gt 0) { $p['monto_efectivo'] = $ef }
  if ($tr -gt 0) { $p['monto_transferencia'] = $tr }
  if ($subtipo) { $p['subtipo_transferencia'] = $subtipo }
  if ($ot -gt 0) { $p['monto_otros'] = $ot }
  if ($origen) { $p['origen_otros'] = $origen }
  if ($desc)   { $p['descripcion_otros'] = $desc }
  $p['idempotency_key'] = $key
  if ($notas) { $p['notas'] = $notas }
  return $p
}

function Get-Code { param($resp); if ($resp -and ($resp.ok -eq $false) -and $resp.error) { return $resp.error.code }; return $null }
function Track-Code { param($resp); $c = Get-Code $resp; if ($null -ne $c) { $script:codesSeen[$c] = $true } }
function Record {
  param($name, $ok, $detail)
  if ($ok) { $script:passed++; Write-Host "PASS  $name" -ForegroundColor Green }
  else { $script:failed++; $script:failsList += "$name :: $detail"; Write-Host "FAIL  $name  ($detail)" -ForegroundColor Red }
}
function Assert-Code {
  param($resp, $name, $expectedCode)
  Track-Code $resp
  $code = Get-Code $resp
  Record $name (($resp.ok -eq $false) -and ($code -eq $expectedCode)) "esperaba ok:false code=$expectedCode; obtuve ok=$($resp.ok) code=$code"
}
function Assert-OkData {
  param($resp, $name, [scriptblock]$Check = $null)
  Track-Code $resp
  $ok = ($resp.ok -eq $true) -and ($null -ne $resp.data)
  if ($ok -and $Check) { $ok = [bool](& $Check $resp.data) }
  Record $name $ok "esperaba ok:true + data; obtuve ok=$($resp.ok) code=$(Get-Code $resp)"
}
function Assert-Code-NotIncierto {
  param($resp, $name, $expectedCode)
  Track-Code $resp
  $code = Get-Code $resp
  $isIncierto = ($code -eq 'estado_incierto')
  $ok = ($resp.ok -eq $false) -and ($code -eq $expectedCode) -and (-not $isIncierto)
  $extra = ''
  if ($isIncierto) { $extra = ' [REGRESION: gateway enmascaro un write con estado_incierto -> revisar responseCode 200 del wrapper y allowlist]' }
  Record $name $ok ("esperaba ok:false code=$expectedCode (NUNCA estado_incierto); obtuve ok=$($resp.ok) code=$code$extra")
}
function Assert-AllowlistMeta {
  $bad = @()
  foreach ($c in $script:codesSeen.Keys) { if ($script:ALLOWLIST -notcontains $c) { $bad += $c } }
  Record "META allowlist (todos los error.code en la allowlist del gateway)" (@($bad).Count -eq 0) ("fuera de allowlist: " + ($bad -join ', '))
}
function Near { param($a, $b) return ([math]::Abs([double]$a - [double]$b) -lt 0.01) }

$EMAIL_VICKY  = 'vicky@vitadelta.test'
$EMAIL_FRANCO = 'franco@vitadelta.test'
$EMAIL_JENNY  = 'jenny@vitadelta.test'
foreach ($pair in @(@('VITA_PW_VICKY',$env:VITA_PW_VICKY), @('VITA_PW_FRANCO',$env:VITA_PW_FRANCO), @('VITA_PW_JENNY',$env:VITA_PW_JENNY))) {
  if ([string]::IsNullOrEmpty($pair[1])) { throw ('Falta ' + $pair[0]) }
}

Write-Host "=== A10-MP GW smoke ===" -ForegroundColor Magenta
$jwtVicky  = Get-PortalJwt -Identity $EMAIL_VICKY  -Password $env:VITA_PW_VICKY
$jwtFranco = Get-PortalJwt -Identity $EMAIL_FRANCO -Password $env:VITA_PW_FRANCO
$jwtJenny  = Get-PortalJwt -Identity $EMAIL_JENNY  -Password $env:VITA_PW_JENNY
if (-not $jwtVicky -or -not $jwtFranco -or -not $jwtJenny) {
  Write-Host "FALTA algun JWT (corre el precheck de credenciales primero)." -ForegroundColor Red
  exit 1
}
$ACTION = 'cobranza.registrar_cobro'

# 1. FELIZ vicky: 9910051 efectivo 50000 -> ok.
$r = Invoke-Gateway -Action $ACTION -Payload (P-Cobro 9910051 -ef 50000 -key 'a10mpgwFef0001') -Jwt $jwtVicky
Assert-OkData $r '1. FELIZ vicky efectivo 50000 (9910051)' { param($d) (Near $d.suma_saldo 50000) -and (Near $d.suma_extra 0) }

# 2. FELIZ socio/franco: 9910052 transferencia mp 40000 -> recargo 2000.
$r = Invoke-Gateway -Action $ACTION -Payload (P-Cobro 9910052 -tr 40000 -subtipo 'mp' -key 'a10mpgwFtm0001') -Jwt $jwtFranco
Assert-OkData $r '2. FELIZ franco transf mp 40000 + recargo 2000 (9910052)' { param($d) (Near $d.suma_saldo 40000) -and (Near $d.suma_extra 2000) }

# 3. jenny -> rol_no_permitido (gateway, antes de firmar).
$r = Invoke-Gateway -Action $ACTION -Payload (P-Cobro 9910051 -ef 1000 -key 'a10mpgwjenny01') -Jwt $jwtJenny
Assert-Code $r '3. jenny -> rol_no_permitido' 'rol_no_permitido'

# 4. sin JWT -> no_autorizado.
$r = Invoke-Gateway -Action $ACTION -Payload (P-Cobro 9910051 -ef 1000 -key 'a10mpgwnojwt01') -Jwt $null
Assert-Code $r '4. sin JWT -> no_autorizado' 'no_autorizado'

# 5. payload invalido (otros sin origen) -> payload_invalido (gateway).
$p = [ordered]@{ id_reserva = 9910051; monto_otros = 5000; descripcion_otros = 'x'; idempotency_key = 'a10mpgwinval01' }
$r = Invoke-Gateway -Action $ACTION -Payload $p -Jwt $jwtVicky
Assert-Code $r '5. otros sin origen -> payload_invalido' 'payload_invalido'

# 6. spoof actor en payload -> payload_invalido (reject-unknown). El actor viaja server-side.
$p = [ordered]@{ id_reserva = 9910051; monto_efectivo = 1000; idempotency_key = 'a10mpgwspoof01'; actor = 'franco' }
$r = Invoke-Gateway -Action $ACTION -Payload $p -Jwt $jwtVicky
Assert-Code $r '6. spoof actor en payload -> payload_invalido' 'payload_invalido'

# 7. action inexistente -> accion_desconocida.
$r = Invoke-Gateway -Action 'cobranza.registrar_cobro_X' -Payload (P-Cobro 9910051 -ef 1000 -key 'a10mpgwactX001') -Jwt $jwtVicky
Assert-Code $r '7. action inexistente -> accion_desconocida' 'accion_desconocida'

# 8. SOBREPAGO regresion: 9910053 saldo 70000, paga 80000 -> conflicto, NUNCA estado_incierto.
$r = Invoke-Gateway -Action $ACTION -Payload (P-Cobro 9910053 -ef 80000 -key 'a10mpgwsobre01') -Jwt $jwtVicky
Assert-Code-NotIncierto $r '8. sobrepago 80000 > 70000 (9910053) -> conflicto' 'conflicto'

# 9. IDEMPOTENCIA match: 9910054 efectivo 100000, replay mismo payload -> idempotent_match.
$kM = 'a10mpgwidem001'
$r = Invoke-Gateway -Action $ACTION -Payload (P-Cobro 9910054 -ef 100000 -key $kM) -Jwt $jwtVicky
Assert-OkData $r '9.1 alta efectivo 100000 (9910054)' { param($d) ($d.idempotent_match -eq $false) }
$r = Invoke-Gateway -Action $ACTION -Payload (P-Cobro 9910054 -ef 100000 -key $kM) -Jwt $jwtVicky
Assert-OkData $r '9.2 replay mismo payload -> idempotent_match' { param($d) ($d.idempotent_match -eq $true) }

# 10. IDEMPOTENCIA mismatch: 9910055 efectivo 100000, replay transferencia 100000 -> conflicto.
$kX = 'a10mpgwmis0001'
$r = Invoke-Gateway -Action $ACTION -Payload (P-Cobro 9910055 -ef 100000 -key $kX) -Jwt $jwtVicky
Assert-OkData $r '10.1 alta efectivo 100000 (9910055)' { param($d) ($d.idempotent_match -eq $false) }
$r = Invoke-Gateway -Action $ACTION -Payload (P-Cobro 9910055 -tr 100000 -subtipo 'bancaria' -key $kX) -Jwt $jwtVicky
Assert-Code $r '10.2 misma key, transferencia -> conflicto' 'conflicto'

Write-Host "`n=== meta-check allowlist ===" -ForegroundColor Magenta
Assert-AllowlistMeta

Write-Host ""
Write-Host "==================================================="
Write-Host ("RESULTADO: {0} PASS / {1} FAIL" -f $script:passed, $script:failed)
if ($script:failed -gt 0) { Write-Host "Fallos:"; $script:failsList | ForEach-Object { Write-Host "  - $_" } }
Write-Host ("Codigos de error vistos: " + ((@($script:codesSeen.Keys) | Sort-Object) -join ', '))
Write-Host ""
Write-Host "NOTA: 1,2,9.1,10.1 escriben cobros; 9.2 es idempotente (no escribe); el resto rebota." -ForegroundColor DarkGray
Write-Host "Verificar/limpiar con A10MP_B4_verif.sql y A10MP_B4_teardown.sql." -ForegroundColor DarkGray
