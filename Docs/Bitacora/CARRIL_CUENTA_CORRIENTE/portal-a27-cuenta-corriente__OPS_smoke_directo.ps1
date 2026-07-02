# ============================================================================
# CC_L1_A27_smoke_directo.ps1
# Frente Cuenta corriente de socios / L1 - A27 (cuenta_corriente.al_dia).
# Smoke DIRECTO al wrapper n8n "portal-a27-cuenta-corriente" (OPS), SIN gateway.
#
# Arma el sobre { action, payload, rol, ambiente_esperado, ts, nonce }, firma HMAC-SHA256
# sobre los BYTES EXACTOS que envia, y POSTea al webhook. n8n recomputa el HMAC (D-C-29).
#
# ENTORNO: OPS. Guard: frena si el webhook no termina en __OPS o el ambiente != ops.
# ASCII PURO (PS 5.1 / CP1252). Sin -Parallel. Sin if inline en -ForegroundColor.
# HttpWebRequest con ContentLength + TLS 1.2 (L-C-17b). Contadores $script: (L-C-17d).
#
# LECTURA socio-only. Diferencia clave con A25/A12: el caso feliz usa rol "socio" y
# "vicky" DEBE REBOTAR con rol_no_permitido (cuenta corriente es reparto de socios).
# Payload VACIO (payloadVacio). El pct 0.25 lo hardcodea el wrapper (no viaja en el sobre).
#
# NO toca OPS. NO escribe. NO consume secuencias. El secreto NO se commitea: se pega en
# $Secret y se borra antes de guardar. Debe ser el MISMO valor del nodo validar_firma_ts_rol
# (Modo B, L-C-10).
# ============================================================================

[Net.ServicePointManager]::SecurityProtocol = `
  [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# ====== CONFIG (editar) ======
$BaseUrl = "https://federicosecchi.app.n8n.cloud"
$Webhook = "portal-a27-cuenta-corriente__OPS"
$Secret  = "Secreto_no_subir"
# =============================

$WebhookUrl = "$($BaseUrl.TrimEnd('/'))/webhook/$Webhook"
$ACT = "cuenta_corriente.al_dia"
$Ambiente = "ops"   # ambiente_esperado correcto en OPS

# GUARD OPS: este smoke SOLO le pega al wrapper OPS. Si el webhook no termina en __OPS
# o el ambiente no es ops, FRENA (exit 3) antes de firmar o enviar.
if (-not $Webhook.EndsWith('__OPS')) { Write-Host 'GUARD OPS: $Webhook no termina en __OPS. FRENO.' -ForegroundColor Red; exit 3 }
if ($Ambiente -ne 'ops')             { Write-Host 'GUARD OPS: ambiente != ops. FRENO.' -ForegroundColor Red; exit 3 }

$script:passed = 0
$script:failed = 0
$script:failsList = @()
$script:codesSeen = @{}
$script:ALLOWLIST = @('payload_invalido','no_autorizado','rol_no_permitido','accion_desconocida','no_encontrado','conflicto','error_entorno','error_interno','estado_incierto','firma_invalida','ts_fuera_de_ventana','raw_body_ausente','ambiente_incorrecto')

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

function Send-Probe {
  param([string]$Body, [string]$Signature)
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
  $req = [System.Net.HttpWebRequest]::Create($WebhookUrl)
  $req.Method = 'POST'
  $req.ContentType = 'application/json'
  $req.Headers.Add('X-Vita-Signature', $Signature)
  $req.ContentLength = $bytes.Length
  $code = 0; $content = ''
  try {
    $rs = $req.GetRequestStream(); $rs.Write($bytes, 0, $bytes.Length); $rs.Close()
    $resp = $req.GetResponse()
    $code = [int]$resp.StatusCode
    $sr = New-Object System.IO.StreamReader($resp.GetResponseStream())
    $content = $sr.ReadToEnd(); $sr.Close(); $resp.Close()
  } catch [System.Net.WebException] {
    $r = $_.Exception.Response
    if ($r) {
      $code = [int]$r.StatusCode
      $sr = New-Object System.IO.StreamReader($r.GetResponseStream())
      $content = $sr.ReadToEnd(); $sr.Close()
    } else {
      $content = '{"ok":false,"error":{"code":"__network_error__","message":"' + $_.Exception.Message + '"}}'
    }
  }
  $j = $null
  try { $j = $content | ConvertFrom-Json } catch { }
  return [pscustomobject]@{ code = $code; json = $j; raw = $content }
}

function Track-Code { param($resp); if ($resp.json -and ($resp.json.ok -eq $false) -and $resp.json.error) { $script:codesSeen[$resp.json.error.code] = $true } }

function Record {
  param([string]$name, [bool]$ok, [string]$detail)
  if ($ok) { $script:passed++; Write-Host "PASS  $name" -ForegroundColor Green }
  else { $script:failed++; $script:failsList += "$name :: $detail"; Write-Host "FAIL  $name  ($detail)" -ForegroundColor Red }
}

function Assert-OkData {
  param([string]$name, $resp, [scriptblock]$Check = $null)
  Track-Code $resp
  $ok = ($resp.json -and ($resp.json.ok -eq $true) -and ($null -ne $resp.json.data))
  if ($ok -and $Check) { $ok = [bool](& $Check $resp.json.data) }
  $code = ''
  if ($resp.json -and $resp.json.error) { $code = $resp.json.error.code }
  Record $name $ok "HTTP $($resp.code); ok=$($resp.json.ok) code=$code"
}

function Assert-Code {
  param([string]$name, $resp, [string]$expected)
  Track-Code $resp
  $code = $null
  if ($resp.json -and ($resp.json.ok -eq $false) -and $resp.json.error) { $code = $resp.json.error.code }
  $ok = ($code -eq $expected)
  Record $name $ok "esperaba ok:false code=$expected; HTTP $($resp.code) ok=$($resp.json.ok) code=$code"
}

function Assert-AllowlistMeta {
  $bad = @()
  foreach ($c in $script:codesSeen.Keys) { if ($script:ALLOWLIST -notcontains $c) { $bad += $c } }
  $ok = (@($bad).Count -eq 0)
  Record "META allowlist (todos los error.code en la allowlist)" $ok ("fuera de allowlist: " + ($bad -join ', '))
}

# ---- helpers ----
function Filas { param($d); if ($d -and $d.filas) { return @($d.filas) } ; return @() }
function Eq2 { param($a, $b); if ($null -eq $a -or $null -eq $b) { return $false } ; return ([math]::Abs([double]$a - [double]$b) -lt 0.01) }

if ($Secret.StartsWith("__PEGAR_")) {
  Write-Host "Falta pegar el secreto en `$Secret (igual al del nodo validar_firma_ts_rol)." -ForegroundColor Red
  return
}

Write-Host "Wrapper: $WebhookUrl" -ForegroundColor Magenta
$now = [long][DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
function NG { return [guid]::NewGuid().ToString() }

# ============================ SEGURIDAD (8) ============================
Write-Host "`n----- SEGURIDAD -----" -ForegroundColor Magenta

# 1. socio OK (caso feliz; payload vacio)
$b = New-Body -Action $ACT -Payload @{} -Rol "socio" -AmbienteEsperado $Ambiente -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-OkData "1. socio OK (ok:true, data.filas presente)" $r { param($d) $null -ne (Filas $d) }

# 2. vicky RECHAZADO -> rol_no_permitido (socio-only: la diferencia con A25/A12)
$b = New-Body -Action $ACT -Payload @{} -Rol "vicky" -AmbienteEsperado $Ambiente -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-Code "2. vicky -> rol_no_permitido (socio-only)" $r "rol_no_permitido"

# 3. jenny -> rol_no_permitido
$b = New-Body -Action $ACT -Payload @{} -Rol "jenny" -AmbienteEsperado $Ambiente -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-Code "3. jenny -> rol_no_permitido" $r "rol_no_permitido"

# 4. intruso -> rol_no_permitido
$b = New-Body -Action $ACT -Payload @{} -Rol "intruso" -AmbienteEsperado $Ambiente -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-Code "4. intruso -> rol_no_permitido" $r "rol_no_permitido"

# 5. firma invalida (secreto equivocado; rol socio) -> firma_invalida
$b = New-Body -Action $ACT -Payload @{} -Rol "socio" -AmbienteEsperado $Ambiente -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key "SECRETO_EQUIVOCADO")
Assert-Code "5. firma equivocada -> firma_invalida" $r "firma_invalida"

# 6. ts viejo (10 min) -> ts_fuera_de_ventana
$b = New-Body -Action $ACT -Payload @{} -Rol "socio" -AmbienteEsperado $Ambiente -Ts ($now - 600000) -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-Code "6. ts viejo -> ts_fuera_de_ventana" $r "ts_fuera_de_ventana"

# 7. ambiente cruzado (manda test en OPS) -> ambiente_incorrecto
$b = New-Body -Action $ACT -Payload @{} -Rol "socio" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-Code "7. ambiente cruzado -> ambiente_incorrecto" $r "ambiente_incorrecto"

# 8. accion equivocada (sobre para otra accion) -> accion_desconocida
$b = New-Body -Action "cobranza.saldos" -Payload @{} -Rol "socio" -AmbienteEsperado $Ambiente -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-Code "8. accion equivocada -> accion_desconocida" $r "accion_desconocida"

# ============================ FUNCIONAL ============================
Write-Host "`n----- FUNCIONAL -----" -ForegroundColor Magenta

# socio OK con datos: imprime saldos y chequea consistencia interna por fila
$b = New-Body -Action $ACT -Payload @{} -Rol "socio" -AmbienteEsperado $Ambiente -Ts $now -Nonce (NG)
$rF = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
if ($rF.json -and $rF.json.ok) {
  $fs = Filas $rF.json.data
  Write-Host ("    filas=" + @($fs).Count) -ForegroundColor DarkGray
  foreach ($f in $fs) {
    Write-Host ("      " + $f.socio + " saldo_al_dia=" + $f.saldo_al_dia) -ForegroundColor DarkGray
  }
}

# F1. contrato: cada fila trae las columnas esperadas
Assert-OkData "F1. filas con columnas (id_socio, socio, saldo_al_dia)" $rF {
  param($d)
  $fs = Filas $d
  if (@($fs).Count -eq 0) { return $true }
  $allok = $true
  foreach ($f in $fs) {
    if ($null -eq $f.id_socio -or $null -eq $f.socio -or $null -eq $f.saldo_al_dia) { $allok = $false }
  }
  return $allok
}

# F2. consistencia interna: saldo_al_dia = previos + en_curso + reembolsos + movimientos
Assert-OkData "F2. saldo_al_dia = suma de las 4 columnas (por fila)" $rF {
  param($d)
  $fs = Filas $d
  if (@($fs).Count -eq 0) { return $true }
  $allok = $true
  foreach ($f in $fs) {
    $suma = [double]$f.liquidacion_meses_previos + [double]$f.liquidacion_mes_en_curso + [double]$f.reembolsos_acumulados + [double]$f.movimientos
    if (-not (Eq2 $suma $f.saldo_al_dia)) { $allok = $false }
  }
  return $allok
}

# ============================ META ============================
Assert-AllowlistMeta

Write-Host "`n===== RESUMEN =====" -ForegroundColor Magenta
Write-Host ("PASSED: " + $script:passed) -ForegroundColor Green
Write-Host ("FAILED: " + $script:failed) -ForegroundColor Red
if ($script:failed -gt 0) {
  Write-Host "`nFallos:" -ForegroundColor Red
  foreach ($f in $script:failsList) { Write-Host ("  - " + $f) -ForegroundColor Red }
}
