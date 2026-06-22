# ============================================================================
# C_SLICE2_A10_GW_common.ps1 -- helper comun para smokes GATEWAY de A10.
# ASCII puro (PS 5.1 / CP1252). Sin -Parallel. Sin if inline en -ForegroundColor.
# Compatible 5.1/7.
#
# A DIFERENCIA del harness directo (A10_smoke_common.ps1, que firma HMAC y pega al
# webhook de n8n), el smoke GATEWAY se autentica con JWT de Supabase y POSTea
# { action, payload } a la Edge Function portal-api. El gateway firma HMAC hacia n8n
# server-side: este harness NUNCA ve el secreto HMAC.
#
# Capa HTTP/auth RECONCILIADA con C_SLICE2_A08_GW_smoke.ps1 (Get-Jwt / Invoke-Gw):
# email+password grant via Invoke-RestMethod, header apikey. Identidades
# <nombre>@vitadelta.test se hardcodean en el precheck y el smoke (igual que A08).
#
# Variables de entorno requeridas:
#   VITA_SUPABASE_URL_TEST   base del proyecto Supabase TEST (https://<ref>.supabase.co)
#   VITA_SUPABASE_ANON_TEST  anon key de TEST (header apikey)
#   VITA_PW_VICKY / VITA_PW_FRANCO / VITA_PW_JENNY   passwords de los 3 usuarios portal
# ============================================================================

$script:passed = 0
$script:failed = 0
$script:failsList = @()
$script:codesSeen = @{}

function Get-GwEnv {
  $url = $env:VITA_SUPABASE_URL_TEST
  $anon = $env:VITA_SUPABASE_ANON_TEST
  if ([string]::IsNullOrEmpty($url)) { throw 'Falta VITA_SUPABASE_URL_TEST' }
  if ([string]::IsNullOrEmpty($anon)) { throw 'Falta VITA_SUPABASE_ANON_TEST' }
  return @{ url = $url.TrimEnd('/'); anon = $anon }
}

# Auth: grant estandar de Supabase (BLOQUE RECONCILIADO con A08 / Get-Jwt). email+password
# -> access_token. Devuelve $null si falla (igual que A08; el caller chequea null).
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

# POST { action, payload } al gateway portal-api (mismo patron que Invoke-Gw de A08). Si $Jwt
# no esta vacio agrega Authorization: Bearer; el header apikey (anon) va SIEMPRE. Para el caso
# 'sin JWT' pasar $Jwt = $null (el gateway debe responder no_autorizado).
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

function Get-Code {
  param($resp)
  if ($resp -and ($resp.ok -eq $false) -and $resp.error) { return $resp.error.code }
  return $null
}

function Track-Code {
  param($resp)
  $c = Get-Code $resp
  if ($null -ne $c) { $script:codesSeen[$c] = $true }
}

function Record {
  param($name, $ok, $detail)
  if ($ok) {
    $script:passed++
    Write-Host "PASS  $name" -ForegroundColor Green
  } else {
    $script:failed++
    $script:failsList += "$name :: $detail"
    Write-Host "FAIL  $name  ($detail)" -ForegroundColor Red
  }
}

function Assert-Code {
  param($resp, $name, $expectedCode)
  Track-Code $resp
  $code = Get-Code $resp
  $ok = ($resp.ok -eq $false) -and ($code -eq $expectedCode)
  Record $name $ok "esperaba ok:false code=$expectedCode; obtuve ok=$($resp.ok) code=$code"
}

function Assert-OkData {
  param($resp, $name, [scriptblock]$Check = $null)
  Track-Code $resp
  $ok = ($resp.ok -eq $true) -and ($null -ne $resp.data)
  if ($ok -and $Check) { $ok = [bool](& $Check $resp.data) }
  Record $name $ok "esperaba ok:true + data valida; obtuve ok=$($resp.ok) code=$(Get-Code $resp)"
}

# Assert de REGRESION (cierre A10 seccion 7 / D-C-51): el codigo DEBE ser $expectedCode
# (conflicto) y JAMAS estado_incierto. Si aparece estado_incierto significa que el gateway
# enmascaro un write -> revisar que el wrapper devuelva HTTP 200 en la rama de error
# (Respond responseCode 200) y que el codigo este en la allowlist.
function Assert-Code-NotIncierto {
  param($resp, $name, $expectedCode)
  Track-Code $resp
  $code = Get-Code $resp
  $isIncierto = ($code -eq 'estado_incierto')
  $ok = ($resp.ok -eq $false) -and ($code -eq $expectedCode) -and (-not $isIncierto)
  $extra = ''
  if ($isIncierto) { $extra = ' [REGRESION ROTA: gateway enmascaro un write con estado_incierto -> revisar responseCode 200 del wrapper y allowlist]' }
  Record $name $ok ("esperaba ok:false code=$expectedCode (NUNCA estado_incierto); obtuve ok=$($resp.ok) code=$code$extra")
}

# Allowlist EXACTA del gateway (D-C-18). Codigos internos como __http_error__ NO pertenecen.
$script:ALLOWLIST = @('payload_invalido','no_autorizado','rol_no_permitido','accion_desconocida','no_encontrado','conflicto','error_entorno','error_interno','estado_incierto','firma_invalida','ts_fuera_de_ventana','raw_body_ausente','ambiente_incorrecto')

function Assert-AllowlistMeta {
  $bad = @()
  foreach ($c in $script:codesSeen.Keys) { if ($script:ALLOWLIST -notcontains $c) { $bad += $c } }
  $ok = ($bad.Count -eq 0)
  Record "META allowlist (todos los error.code en la allowlist del gateway)" $ok ("codigos fuera de allowlist: " + ($bad -join ', '))
}

function Summary {
  Write-Host ""
  Write-Host "==================================================="
  Write-Host ("RESULTADO: {0} PASS / {1} FAIL" -f $script:passed, $script:failed)
  if ($script:failed -gt 0) {
    Write-Host "Fallos:"
    $script:failsList | ForEach-Object { Write-Host "  - $_" }
  }
  Write-Host "Codigos de error vistos: $((@($script:codesSeen.Keys) | Sort-Object) -join ', ')"
}
