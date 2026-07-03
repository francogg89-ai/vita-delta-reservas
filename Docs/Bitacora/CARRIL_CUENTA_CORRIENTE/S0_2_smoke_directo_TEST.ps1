# ============================================================================
# S0_2_smoke_directo_TEST.ps1  --  Sub-bloque 0.2 (Ajuste B: read pre/post)
#
# Lee A27 (cuenta_corriente.al_dia) y A28 (cuenta_corriente.detalle) DIRECTO a los
# wrappers n8n de TEST (SIN gateway), firma HMAC-SHA256 sobre los bytes exactos, y
# emite un HASH SHA256 deterministico de la salida (data de A27 + detalle de A28).
#
# USO pre/post: correr ANTES del parche (anotar el HASH), aplicar el patcher, re-importar
# los wrappers en TEST, correr DESPUES. Si el HASH es identico -> el cambio a
# pct_operativo_vigente() fue output-neutral end-to-end.
#
# ENTORNO: TEST. Lecturas TEST => webhooks SIN sufijo (L-CC-06). GUARD anti-OPS:
# frena (exit 3) si algun webhook termina en __OPS o si ambiente != test.
# ASCII PURO (PS 5.1 / CP1252). HttpWebRequest + ContentLength + TLS 1.2.
# LECTURA socio-only (rol 'socio'). No escribe. El secreto NO se commitea.
# ============================================================================

[Net.ServicePointManager]::SecurityProtocol = `
  [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# ====== CONFIG (editar) ======
$BaseUrl   = "https://federicosecchi.app.n8n.cloud"
$Webhook27 = "portal-a27-cuenta-corriente"
$Webhook28 = "portal-a28-cuenta-corriente-detalle"
$Secret    = "d3cb37c88b688c6e104f133d08990312134ee5df6775e2dff267e0deac16c3f4"
$Ambiente  = "test"
$Mes       = (Get-Date).ToString("yyyy-MM-01")   # mes para A28 (primer dia del mes actual)
# =============================

# GUARD anti-OPS: este smoke SOLO le pega a wrappers de TEST.
if ($Webhook27.EndsWith('__OPS') -or $Webhook28.EndsWith('__OPS')) {
  Write-Host 'GUARD: un webhook termina en __OPS. FRENO.' -ForegroundColor Red; exit 3
}
if ($Ambiente -ne 'test') {
  Write-Host 'GUARD: ambiente != test. FRENO.' -ForegroundColor Red; exit 3
}

function New-Body {
  param([string]$Action, [hashtable]$Payload, [string]$Rol, [string]$AmbienteEsperado, [long]$Ts, [string]$Nonce)
  $obj = [ordered]@{ action = $Action; payload = $Payload; rol = $Rol; ambiente_esperado = $AmbienteEsperado; ts = $Ts; nonce = $Nonce }
  return ($obj | ConvertTo-Json -Compress -Depth 8)
}

function Get-Signature {
  param([string]$Body, [string]$Key)
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
  $h = New-Object System.Security.Cryptography.HMACSHA256
  $h.Key = [System.Text.Encoding]::UTF8.GetBytes($Key)
  $hash = $h.ComputeHash($bytes)
  return "sha256=" + (($hash | ForEach-Object { $_.ToString('x2') }) -join '')
}

function Invoke-Read {
  param([string]$Webhook, [string]$Action, [hashtable]$Payload)
  $url = "$($BaseUrl.TrimEnd('/'))/webhook/$Webhook"
  $ts = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $nonce = [guid]::NewGuid().ToString()
  $body = New-Body -Action $Action -Payload $Payload -Rol 'socio' -AmbienteEsperado $Ambiente -Ts $ts -Nonce $nonce
  $sig = Get-Signature -Body $body -Key $Secret
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
  $req = [System.Net.HttpWebRequest]::Create($url)
  $req.Method = 'POST'
  $req.ContentType = 'application/json'
  $req.Accept = 'application/json'
  [void]$req.Headers.Add('X-Vita-Signature', $sig)
  $req.ContentLength = $bytes.Length
  $content = ''
  try {
    $rs = $req.GetRequestStream(); $rs.Write($bytes, 0, $bytes.Length); $rs.Close()
    $resp = $req.GetResponse()
    $sr = New-Object System.IO.StreamReader($resp.GetResponseStream())
    $content = $sr.ReadToEnd(); $sr.Close(); $resp.Close()
  } catch [System.Net.WebException] {
    $r = $_.Exception.Response
    if ($r) { $sr = New-Object System.IO.StreamReader($r.GetResponseStream()); $content = $sr.ReadToEnd(); $sr.Close() }
  }
  try { return ($content | ConvertFrom-Json) } catch { return $null }
}

function Hash-Text {
  param([string]$Text)
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  $h = $sha.ComputeHash($bytes)
  return (($h | ForEach-Object { $_.ToString('x2') }) -join '')
}

Write-Host "== S0.2 smoke directo TEST (mes A28 = $Mes) ==" -ForegroundColor Cyan

# --- A27 (falla dura si no ok:true; NO se emite hash sobre lecturas fallidas) ---
$r27 = Invoke-Read -Webhook $Webhook27 -Action 'cuenta_corriente.al_dia' -Payload @{}
if ($null -eq $r27 -or $r27.ok -ne $true) {
  $code = if ($null -ne $r27 -and $r27.error) { $r27.error.code } else { 'sin_respuesta' }
  Write-Host "A27 ok=false code=$code -- SMOKE ABORTADO (no se emite HASH)" -ForegroundColor Red
  $Secret = $null
  exit 1
}
$d27 = ($r27.data | ConvertTo-Json -Compress -Depth 12)
Write-Host "A27 ok=true" -ForegroundColor Green
Write-Host "  data: $d27"

# --- A28 (falla dura si no ok:true) ---
$r28 = Invoke-Read -Webhook $Webhook28 -Action 'cuenta_corriente.detalle' -Payload @{ mes = $Mes }
if ($null -eq $r28 -or $r28.ok -ne $true) {
  $code = if ($null -ne $r28 -and $r28.error) { $r28.error.code } else { 'sin_respuesta' }
  Write-Host "A28 ok=false code=$code -- SMOKE ABORTADO (no se emite HASH)" -ForegroundColor Red
  $Secret = $null
  exit 1
}
$d28 = ($r28.data | ConvertTo-Json -Compress -Depth 20)
Write-Host "A28 ok=true (detalle capturado)" -ForegroundColor Green

# --- Ambas ok:true: RECIEN ahora el HASH deterministico (para comparar pre vs post) ---
$combined = "$d27|$d28"
$hash = Hash-Text -Text $combined
Write-Host ""
Write-Host "HASH_S0.2 = $hash" -ForegroundColor Yellow
Write-Host "(anota este hash; debe ser IDENTICO antes y despues del parche de A27/A28)"
Write-Host "SMOKE_S0.2_OK" -ForegroundColor Green

$Secret = $null
