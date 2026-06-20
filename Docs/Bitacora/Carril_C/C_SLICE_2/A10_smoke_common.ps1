# ============================================================================
# A10_smoke_common.ps1  -- helper comun para smokes directos del wrapper A10.
# ASCII puro (PS 5.1 / CP1252). Sin -Parallel. Sin if inline en -ForegroundColor.
# Firma HMAC-SHA256 hex sobre los BYTES UTF-8 del body (igual que buildSignedEnvelope
# del gateway). Envia EXACTAMENTE los bytes firmados (el wrapper recomputa sobre el raw).
#
# Variables de entorno requeridas:
#   VITA_A10_WEBHOOK_URL     URL completa del webhook (prod: .../webhook/portal-a10-registrar-saldo__TEST)
#   VITA_HMAC_SECRET_TEST    secreto HMAC de TEST (NUNCA hardcodear)
# ============================================================================

$script:passed = 0
$script:failed = 0
$script:failsList = @()
$script:codesSeen = @{}

# PS 5.1 + HttpWebRequest sobre HTTPS: forzar TLS 1.2 (si no, la conexion a n8n Cloud puede fallar).
try { [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 } catch {}

function Get-A10Env {
  $secret = $env:VITA_HMAC_SECRET_TEST
  $url = $env:VITA_A10_WEBHOOK_URL
  if ([string]::IsNullOrEmpty($secret)) { throw 'Falta VITA_HMAC_SECRET_TEST' }
  if ([string]::IsNullOrEmpty($url)) { throw 'Falta VITA_A10_WEBHOOK_URL' }
  return @{ secret = $secret; url = $url }
}

function Invoke-A10 {
  param(
    [System.Collections.IDictionary]$Payload,
    [string]$Rol = 'vicky',
    [string]$Actor = 'vicky',
    [object]$TsOverride = $null,
    [object]$NonceOverride = $null,
    [string]$AmbienteEsperado = 'test',
    [object]$SigOverride = $null,
    [object]$RawOverride = $null,
    [string[]]$DropEnvelopeKeys = @(),
    [hashtable]$ExtraEnvelope = $null
  )
  $cfg = Get-A10Env
  $ts = $TsOverride
  if ($null -eq $ts) { $ts = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() }
  if ($null -eq $NonceOverride) { $nonce = [guid]::NewGuid().ToString() } else { $nonce = [string]$NonceOverride }

  $env_ht = [ordered]@{
    action = 'cobranza.registrar_saldo'
    payload = $Payload
    rol = $Rol
    ambiente_esperado = $AmbienteEsperado
    ts = $ts
    nonce = $nonce
    actor = $Actor
  }
  if ($ExtraEnvelope) { foreach ($k in $ExtraEnvelope.Keys) { $env_ht[$k] = $ExtraEnvelope[$k] } }
  foreach ($k in $DropEnvelopeKeys) { if ($env_ht.Contains($k)) { $env_ht.Remove($k) } }

  if ($null -eq $RawOverride) {
    $bodyString = ($env_ht | ConvertTo-Json -Compress -Depth 12)
  } else {
    $bodyString = [string]$RawOverride
  }
  $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($bodyString)

  if ($null -eq $SigOverride) {
    $hmac = New-Object System.Security.Cryptography.HMACSHA256
    $hmac.Key = [System.Text.Encoding]::UTF8.GetBytes($cfg.secret)
    $hash = $hmac.ComputeHash($bodyBytes)
    $hex = -join ($hash | ForEach-Object { $_.ToString('x2') })
    $sig = "sha256=$hex"
  } else {
    $sig = [string]$SigOverride
  }

  # Envio por HttpWebRequest: escribe los BYTES EXACTOS al request stream con Content-Length
  # explicito (+ TLS 1.2 forzado arriba). Los cmdlets de alto nivel con -Body byte[] en PS 5.1
  # pueden dejar el raw body vacio en n8n; por eso se usa la API .NET explicita.
  try {
    $req = [System.Net.HttpWebRequest]::Create($cfg.url)
    $req.Method = 'POST'
    $req.ContentType = 'application/json'
    $req.Accept = 'application/json'
    [void]$req.Headers.Add('X-Vita-Signature', $sig)
    $req.ContentLength = $bodyBytes.Length
    $rs = $req.GetRequestStream()
    $rs.Write($bodyBytes, 0, $bodyBytes.Length)
    $rs.Close()
    $resp = $req.GetResponse()
    $sr = New-Object System.IO.StreamReader($resp.GetResponseStream())
    $content = $sr.ReadToEnd()
    $sr.Close(); $resp.Close()
    return ($content | ConvertFrom-Json)
  } catch [System.Net.WebException] {
    $r = $_.Exception.Response
    if ($r) {
      $sr = New-Object System.IO.StreamReader($r.GetResponseStream())
      $content = $sr.ReadToEnd(); $sr.Close()
      try { return ($content | ConvertFrom-Json) } catch { return [pscustomobject]@{ ok = $false; error = [pscustomobject]@{ code = '__http_error__'; message = $content } } }
    }
    return [pscustomobject]@{ ok = $false; error = [pscustomobject]@{ code = '__network_error__'; message = $_.Exception.Message } }
  } catch {
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
