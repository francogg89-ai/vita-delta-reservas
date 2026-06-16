# ============================================================================
# C_SLICE0_C_probe.ps1
# Carril C / Portal Operativo Interno - Slice 0, Fase C.
# Probe del workflow n8n "portal-probe-ambiente" (TEST).
#
# Replica lo que hace portal-api: arma el sobre, firma HMAC-SHA256 sobre los
# BYTES EXACTOS que envia, y postea al webhook. n8n recomputa el HMAC sobre el
# raw body recibido; si validan, queda probada la fidelidad byte a byte (D-C-29).
#
# Casos: (1) firma valida + ambiente test, (2) firma invalida, (3) ts viejo,
#        (4) cruce de ambiente: ambiente_esperado='ops' contra workflow TEST.
#
# NO toca OPS. NO escribe en Supabase. Solo postea al webhook de n8n TEST.
# El secreto NO se commitea; se pega abajo y se borra antes de guardar al repo.
# ============================================================================

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# ====== CONFIG (editar estos dos) ======
$WebhookUrl = "https://federicosecchi.app.n8n.cloud/webhook/portal-probe-ambiente"
$Secret     = "9baecccda47449510bf22370f85775a6f2c3b3bfe06fcd2b94fedccdece5c37b"   # mismo valor que en Supabase y n8n; NO commitear
# =======================================

function New-Body {
  param([string]$Rol, [string]$AmbienteEsperado, [long]$Ts, [string]$Nonce)
  # JSON armado a mano para controlar los bytes EXACTOS que se firman y se envian.
  return "{`"action`":`"sesion.contexto`",`"payload`":{},`"rol`":`"$Rol`",`"ambiente_esperado`":`"$AmbienteEsperado`",`"ts`":$Ts,`"nonce`":`"$Nonce`"}"
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
  param([string]$Caso, [string]$Body, [string]$Signature)
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)   # los MISMOS bytes que se firmaron
  Write-Host "`n=== $Caso ===" -ForegroundColor Cyan
  try {
    $resp = Invoke-WebRequest -Method Post -Uri $WebhookUrl `
      -Headers @{ "X-Vita-Signature" = $Signature } `
      -ContentType "application/json" -Body $bytes -UseBasicParsing
    Write-Host ("HTTP " + [int]$resp.StatusCode)
    Write-Host $resp.Content
  } catch {
    $r = $_.Exception.Response
    if ($r) {
      $sr = New-Object System.IO.StreamReader($r.GetResponseStream())
      Write-Host ("HTTP " + [int]$r.StatusCode) -ForegroundColor Yellow
      Write-Host $sr.ReadToEnd()
    } else {
      Write-Host $_.Exception.Message -ForegroundColor Red
    }
  }
}

if ($Secret -eq "PEGAR_EL_MISMO_VITA_HMAC_SECRET") {
  Write-Host "Falta pegar el secreto en `$Secret (linea CONFIG)." -ForegroundColor Red
  return
}

$now = [long][DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()

# --- Caso 1: firma valida + ambiente_esperado='test'  ->  ok:true ---
$b1 = New-Body -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce ([guid]::NewGuid().ToString())
Send-Probe -Caso "1. Firma valida + ambiente test  (esperado: ok:true, ambiente=test)" -Body $b1 -Signature (Get-Signature -Body $b1 -Key $Secret)

# --- Caso 2: firma invalida (firmamos con secreto equivocado)  ->  firma_invalida ---
$b2 = New-Body -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce ([guid]::NewGuid().ToString())
Send-Probe -Caso "2. Firma invalida  (esperado: ok:false, firma_invalida)" -Body $b2 -Signature (Get-Signature -Body $b2 -Key "SECRETO_EQUIVOCADO")

# --- Caso 3: ts viejo (10 min atras)  ->  ts_fuera_de_ventana ---
$b3 = New-Body -Rol "vicky" -AmbienteEsperado "test" -Ts ($now - 600000) -Nonce ([guid]::NewGuid().ToString())
Send-Probe -Caso "3. ts viejo  (esperado: ok:false, ts_fuera_de_ventana)" -Body $b3 -Signature (Get-Signature -Body $b3 -Key $Secret)

# --- Caso 4: cruce de ambiente, ambiente_esperado='ops' contra workflow TEST  ->  ambiente_incorrecto ---
$b4 = New-Body -Rol "vicky" -AmbienteEsperado "ops" -Ts $now -Nonce ([guid]::NewGuid().ToString())
Send-Probe -Caso "4. Cruce ops->test  (esperado: ok:false, ambiente_incorrecto, detail esperado=ops real=test)" -Body $b4 -Signature (Get-Signature -Body $b4 -Key $Secret)

Write-Host "`nListo. Compara cada caso con su esperado (ver runsheet, criterios de exito)." -ForegroundColor Green
