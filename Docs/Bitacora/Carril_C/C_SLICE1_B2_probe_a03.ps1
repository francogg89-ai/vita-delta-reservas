# =============================================================================
# C_SLICE1_B2_probe_a03.ps1  (ASCII puro)
# Pruebas DIRECTAS del wrapper n8n "portal-a03-limpieza" (TEST), sin pasar por
# portal-api. Replica lo que hace el gateway: arma el sobre, firma HMAC-SHA256
# sobre los BYTES EXACTOS que envia, y postea al webhook con X-Vita-Signature.
#
# Se prueba directo al wrapper porque las firmas invalidas / ts viejo / ambiente
# cruzado / rol arbitrario no se pueden generar via portal-api (el gateway nunca
# los produce). Esto valida la segunda defensa del wrapper (D-C-39).
#
# Casos: (1) firma valida + rol jenny + test -> ok:true html
#        (2) firma invalida -> firma_invalida
#        (3) ts viejo -> ts_fuera_de_ventana
#        (4) ambiente cruzado (ops) -> ambiente_incorrecto
#        (5) rol permitido vicky + test -> ok:true html
#        (6) rol NO permitido (intruso) + test -> rol_no_permitido
#
# NO toca OPS. NO escribe en Supabase. Solo postea al webhook de n8n TEST.
# El secreto NO se commitea: se pega abajo y se borra antes de guardar al repo.
# =============================================================================

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# ====== CONFIG (editar) ======
$WebhookUrl = "https://federicosecchi.app.n8n.cloud/webhook/portal-a03-limpieza"
$Secret     = "Secreto_pegar_nocommitear"   # mismo valor que en Supabase y en la Variable de n8n; NO commitear
# =============================

function New-Body {
  param([string]$Rol, [string]$AmbienteEsperado, [long]$Ts, [string]$Nonce, [string]$Action = "calendario.limpieza")
  # JSON armado a mano para controlar los bytes EXACTOS que se firman y se envian.
  return "{`"action`":`"$Action`",`"payload`":{},`"rol`":`"$Rol`",`"ambiente_esperado`":`"$AmbienteEsperado`",`"ts`":$Ts,`"nonce`":`"$Nonce`"}"
}

function Get-Signature {
  param([string]$Body, [string]$Key)
  $h = New-Object System.Security.Cryptography.HMACSHA256
  $h.Key = [System.Text.Encoding]::UTF8.GetBytes($Key)
  $hash = $h.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Body))
  return "sha256=" + (($hash | ForEach-Object { $_.ToString('x2') }) -join '')
}

function Send-Probe {
  param([string]$Caso, [string]$Body, [string]$Signature)
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)   # los MISMOS bytes que se firmaron
  Write-Host "`n=== $Caso ===" -ForegroundColor Cyan
  try {
    $resp = Invoke-WebRequest -Method Post -Uri $WebhookUrl -Headers @{ "X-Vita-Signature" = $Signature } -ContentType "application/json" -Body $bytes -UseBasicParsing
    $code = [int]$resp.StatusCode
    Show-Envelope -Http $code -Content $resp.Content
  } catch {
    $r = $_.Exception.Response
    if ($r) {
      $sr = New-Object System.IO.StreamReader($r.GetResponseStream())
      Show-Envelope -Http ([int]$r.StatusCode) -Content $sr.ReadToEnd()
    } else {
      Write-Host $_.Exception.Message -ForegroundColor Red
    }
  }
}

function Show-Envelope {
  param([int]$Http, [string]$Content)
  Write-Host ("HTTP " + $Http)
  $p = $null
  try { $p = $Content | ConvertFrom-Json } catch {}
  if ($p -ne $null -and $p.PSObject.Properties.Name -contains 'ok') {
    if ($p.ok -eq $true) {
      $fmt = if ($p.data) { $p.data.formato } else { '' }
      $len = if ($p.data -and $p.data.html) { $p.data.html.Length } else { 0 }
      Write-Host ("ok:true  formato=" + $fmt + "  html_len=" + $len) -ForegroundColor Green
    } else {
      Write-Host ("ok:false  code=" + $p.error.code + "  detail=" + (ConvertTo-Json $p.error.detail -Compress)) -ForegroundColor Yellow
    }
  } else {
    if ($Content.Length -gt 400) { Write-Host ($Content.Substring(0,400) + " ...[trunc]") }
    else { Write-Host $Content }
  }
}

if ($Secret -eq "PEGAR_EL_MISMO_VITA_HMAC_SECRET") {
  Write-Host "Falta pegar el secreto en `$Secret (linea CONFIG)." -ForegroundColor Red
  return
}

$now = [long][DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()

# 1) firma valida + rol jenny + test -> ok:true html
$b1 = New-Body -Rol "jenny" -AmbienteEsperado "test" -Ts $now -Nonce ([guid]::NewGuid().ToString())
Send-Probe -Caso "1. Firma valida + rol jenny + test  (esperado: ok:true, formato=html)" -Body $b1 -Signature (Get-Signature -Body $b1 -Key $Secret)

# 2) firma invalida -> firma_invalida
$b2 = New-Body -Rol "jenny" -AmbienteEsperado "test" -Ts $now -Nonce ([guid]::NewGuid().ToString())
Send-Probe -Caso "2. Firma invalida  (esperado: ok:false, firma_invalida)" -Body $b2 -Signature (Get-Signature -Body $b2 -Key "SECRETO_EQUIVOCADO")

# 3) ts viejo -> ts_fuera_de_ventana
$b3 = New-Body -Rol "jenny" -AmbienteEsperado "test" -Ts ($now - 600000) -Nonce ([guid]::NewGuid().ToString())
Send-Probe -Caso "3. ts viejo (10 min)  (esperado: ok:false, ts_fuera_de_ventana)" -Body $b3 -Signature (Get-Signature -Body $b3 -Key $Secret)

# 4) ambiente cruzado (ops) -> ambiente_incorrecto
$b4 = New-Body -Rol "jenny" -AmbienteEsperado "ops" -Ts $now -Nonce ([guid]::NewGuid().ToString())
Send-Probe -Caso "4. Cruce ops->test  (esperado: ok:false, ambiente_incorrecto, detail esperado=ops real=test)" -Body $b4 -Signature (Get-Signature -Body $b4 -Key $Secret)

# 5) rol permitido vicky + test -> ok:true html
$b5 = New-Body -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce ([guid]::NewGuid().ToString())
Send-Probe -Caso "5. Rol permitido vicky + test  (esperado: ok:true, formato=html)" -Body $b5 -Signature (Get-Signature -Body $b5 -Key $Secret)

# 6) rol NO permitido (intruso) + test -> rol_no_permitido
$b6 = New-Body -Rol "intruso" -AmbienteEsperado "test" -Ts $now -Nonce ([guid]::NewGuid().ToString())
Send-Probe -Caso "6. Rol NO permitido (intruso) directo al wrapper  (esperado: ok:false, rol_no_permitido)" -Body $b6 -Signature (Get-Signature -Body $b6 -Key $Secret)

# 7) action incorrecta (sobre bien firmado, rol valido, ambiente test) -> accion_desconocida
$b7 = New-Body -Rol "jenny" -AmbienteEsperado "test" -Ts $now -Nonce ([guid]::NewGuid().ToString()) -Action "otra.accion"
Send-Probe -Caso "7. Action incorrecta + firma valida  (esperado: ok:false, accion_desconocida)" -Body $b7 -Signature (Get-Signature -Body $b7 -Key $Secret)

Write-Host "`nListo. Compara cada caso con su esperado (ver runsheet)." -ForegroundColor Green
