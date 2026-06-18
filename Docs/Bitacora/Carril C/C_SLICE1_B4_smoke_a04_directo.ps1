# ============================================================================
# C_SLICE1_B4_smoke_a04_directo.ps1
# Carril C / Portal Operativo Interno - Slice 1, Bloque 4.
# Smoke DIRECTO al wrapper n8n "portal-a04-operativo" (TEST). Defensa en profundidad:
# prueba el wrapper sin pasar por el gateway (el cableado en portal-api es el Bloque 5).
#
# Replica lo que hace portal-api: arma el sobre { action, payload, rol, ambiente_esperado,
# ts, nonce }, firma HMAC-SHA256 sobre los BYTES EXACTOS que envia, y postea al webhook.
# n8n recomputa el HMAC sobre el raw body recibido (D-C-29). Imprime el veredicto parseando
# el envelope: ok:true -> formato + html_len ; ok:false -> error.code (tu punto 9).
#
# 8 casos: vicky OK, socio OK, jenny->rol_no_permitido, intruso->rol_no_permitido,
#          firma invalida, ts viejo, ambiente cruzado (ops), action incorrecta.
#
# NO toca OPS. NO escribe en Supabase. Solo postea al webhook de n8n TEST.
# El secreto NO se commitea: se pega abajo en $Secret y se borra antes de guardar al repo.
# Debe ser el MISMO valor que la Variable de n8n VITA_HMAC_SECRET (si no coinciden, los
# casos de firma valida daran firma_invalida).
# ============================================================================

[Net.ServicePointManager]::SecurityProtocol = `
  [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# ====== CONFIG (editar) ======
$BaseUrl = "https://federicosecchi.app.n8n.cloud"     # base de n8n Cloud (sin /webhook)
$Webhook = "portal-a04-operativo"                     # path del Webhook del wrapper
$Secret  = "PEGAR_EL_MISMO_VITA_HMAC_SECRET"          # == Variable n8n VITA_HMAC_SECRET; NO commitear
# =============================

$WebhookUrl = "$($BaseUrl.TrimEnd('/'))/webhook/$Webhook"

function New-Body {
  param([string]$Action, [string]$Rol, [string]$AmbienteEsperado, [long]$Ts, [string]$Nonce)
  # JSON armado a mano para controlar los bytes EXACTOS que se firman y se envian.
  return "{`"action`":`"$Action`",`"payload`":{},`"rol`":`"$Rol`",`"ambiente_esperado`":`"$AmbienteEsperado`",`"ts`":$Ts,`"nonce`":`"$Nonce`"}"
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
  param([string]$Caso, [string]$Body, [string]$Signature, [string]$Esperado)
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)   # los MISMOS bytes que se firmaron
  Write-Host "`n=== $Caso ===" -ForegroundColor Cyan
  Write-Host "    esperado: $Esperado" -ForegroundColor DarkGray
  try {
    $resp = Invoke-WebRequest -Method Post -Uri $WebhookUrl `
      -Headers @{ "X-Vita-Signature" = $Signature } `
      -ContentType "application/json" -Body $bytes -UseBasicParsing
    $code = [int]$resp.StatusCode
    $j = $null
    try { $j = $resp.Content | ConvertFrom-Json } catch { }
    if ($null -ne $j) {
      if ($j.ok -eq $true) {
        $fmt = $j.data.formato
        $len = 0; if ($j.data.html) { $len = $j.data.html.Length }
        Write-Host ("    HTTP $code | ok:true | formato=$fmt | html_len=$len") -ForegroundColor Green
      } else {
        $ec  = $j.error.code
        $det = ""; if ($j.error.detail) { $det = " | detail=" + ($j.error.detail | ConvertTo-Json -Compress) }
        Write-Host ("    HTTP $code | ok:false | error.code=$ec$det") -ForegroundColor Yellow
      }
    } else {
      Write-Host ("    HTTP $code | (respuesta NO es JSON)") -ForegroundColor Red
      Write-Host $resp.Content
    }
  } catch {
    $r = $_.Exception.Response
    if ($r) {
      $sc = [int]$r.StatusCode
      $sr = New-Object System.IO.StreamReader($r.GetResponseStream())
      Write-Host ("    HTTP $sc | (error inesperado)") -ForegroundColor Red
      Write-Host $sr.ReadToEnd()
    } else {
      Write-Host ("    " + $_.Exception.Message) -ForegroundColor Red
    }
  }
}

if ($Secret -eq "PEGAR_EL_MISMO_VITA_HMAC_SECRET") {
  Write-Host "Falta pegar el secreto en `$Secret (debe ser igual a la Variable n8n VITA_HMAC_SECRET)." -ForegroundColor Red
  return
}

Write-Host "Wrapper: $WebhookUrl" -ForegroundColor Magenta
$now   = [long][DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$ACT   = "calendario.operativo"   # EXPECTED_ACTION del wrapper

# --- 1: vicky, firma valida, ambiente test  ->  ok:true formato=html ---
$b = New-Body -Action $ACT -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce ([guid]::NewGuid().ToString())
Send-Probe -Caso "1. vicky OK" -Body $b -Signature (Get-Signature -Body $b -Key $Secret) `
  -Esperado "ok:true, formato=html, html_len>0"

# --- 2: socio, firma valida, ambiente test  ->  ok:true formato=html ---
$b = New-Body -Action $ACT -Rol "socio" -AmbienteEsperado "test" -Ts $now -Nonce ([guid]::NewGuid().ToString())
Send-Probe -Caso "2. socio OK" -Body $b -Signature (Get-Signature -Body $b -Key $Secret) `
  -Esperado "ok:true, formato=html, html_len>0"

# --- 3: jenny (rol valido del portal, NO habilitado para A04)  ->  rol_no_permitido ---
$b = New-Body -Action $ACT -Rol "jenny" -AmbienteEsperado "test" -Ts $now -Nonce ([guid]::NewGuid().ToString())
Send-Probe -Caso "3. jenny directo al wrapper" -Body $b -Signature (Get-Signature -Body $b -Key $Secret) `
  -Esperado "ok:false, rol_no_permitido"

# --- 4: intruso (rol inexistente)  ->  rol_no_permitido ---
$b = New-Body -Action $ACT -Rol "intruso" -AmbienteEsperado "test" -Ts $now -Nonce ([guid]::NewGuid().ToString())
Send-Probe -Caso "4. intruso (rol basura)" -Body $b -Signature (Get-Signature -Body $b -Key $Secret) `
  -Esperado "ok:false, rol_no_permitido"

# --- 5: firma invalida (firmamos con secreto equivocado)  ->  firma_invalida ---
$b = New-Body -Action $ACT -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce ([guid]::NewGuid().ToString())
Send-Probe -Caso "5. firma invalida" -Body $b -Signature (Get-Signature -Body $b -Key "SECRETO_EQUIVOCADO") `
  -Esperado "ok:false, firma_invalida"

# --- 6: ts viejo (10 min atras)  ->  ts_fuera_de_ventana ---
$b = New-Body -Action $ACT -Rol "vicky" -AmbienteEsperado "test" -Ts ($now - 600000) -Nonce ([guid]::NewGuid().ToString())
Send-Probe -Caso "6. ts viejo (-10min)" -Body $b -Signature (Get-Signature -Body $b -Key $Secret) `
  -Esperado "ok:false, ts_fuera_de_ventana"

# --- 7: ambiente cruzado, ambiente_esperado='ops' contra wrapper TEST  ->  ambiente_incorrecto ---
$b = New-Body -Action $ACT -Rol "vicky" -AmbienteEsperado "ops" -Ts $now -Nonce ([guid]::NewGuid().ToString())
Send-Probe -Caso "7. ambiente cruzado (ops->test)" -Body $b -Signature (Get-Signature -Body $b -Key $Secret) `
  -Esperado "ok:false, ambiente_incorrecto (detail esperado=ops real=test)"

# --- 8: action incorrecta (sobre bien firmado, action ajena)  ->  accion_desconocida ---
$b = New-Body -Action "calendario.limpieza" -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce ([guid]::NewGuid().ToString())
Send-Probe -Caso "8. action incorrecta (calendario.limpieza)" -Body $b -Signature (Get-Signature -Body $b -Key $Secret) `
  -Esperado "ok:false, accion_desconocida"

Write-Host "`nListo. 8 casos. Compara cada veredicto con su 'esperado' (criterios en el runsheet B4)." -ForegroundColor Green
