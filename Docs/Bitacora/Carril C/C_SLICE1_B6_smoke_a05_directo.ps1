# ============================================================================
# C_SLICE1_B6_smoke_a05_directo.ps1
# Carril C / Portal Operativo Interno - Slice 1, Bloque 6 (wrapper de A05).
# Smoke DIRECTO al wrapper n8n "portal-a05-detalle" (TEST). Defensa en profundidad:
# prueba el wrapper SIN pasar por el gateway (el cableado en portal-api es el bloque siguiente).
#
# Replica lo que hace portal-api: arma el sobre { action, payload, rol, ambiente_esperado,
# ts, nonce }, firma HMAC-SHA256 sobre los BYTES EXACTOS que envia, y postea al webhook.
# n8n recomputa el HMAC sobre el raw body recibido (D-C-29). A05 es la PRIMERA accion con
# payload: la 5ta dimension (id_reserva) se revalida en el wrapper (2da defensa, D-C-39/40).
#
# 14 casos: vicky OK, socio OK, jenny->rol_no_permitido, intruso->rol_no_permitido,
#           firma invalida, ts viejo, ambiente cruzado (ops), action incorrecta,
#           id inexistente->no_encontrado, y 5 de payload invalido directo al wrapper
#           (ausente / string / negativo / decimal / no-safe-integer).
#
# NO toca OPS. NO escribe en Supabase. Solo postea al webhook de n8n TEST.
# El secreto NO se commitea: se pega abajo en $Secret y se borra antes de guardar al repo.
# Debe ser el MISMO valor pegado en el nodo validar_firma_ts_rol (Modo B).
# $IdReservaOk / $IdReservaInexistente: ver queries read-only en el runsheet B6.
# ============================================================================

[Net.ServicePointManager]::SecurityProtocol = `
  [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# ====== CONFIG (editar) ======
$BaseUrl              = "https://federicosecchi.app.n8n.cloud"   # base de n8n Cloud (sin /webhook)
$Webhook             = "portal-a05-detalle"                      # path del Webhook del wrapper
$Secret              = "Aca_va_el_secreto"         # == secreto del nodo; NO commitear
$IdReservaOk         = x                                         # id_reserva REAL de TEST (runsheet B6, query 1)
$IdReservaInexistente = 1000013                                        # id calculado (runsheet B6, query 2)
# =============================

$WebhookUrl = "$($BaseUrl.TrimEnd('/'))/webhook/$Webhook"

function New-Body {
  param([string]$Action, [string]$Rol, [string]$AmbienteEsperado, [long]$Ts, [string]$Nonce, [string]$PayloadJson)
  # JSON armado a mano para controlar los bytes EXACTOS que se firman y se envian.
  return "{`"action`":`"$Action`",`"payload`":$PayloadJson,`"rol`":`"$Rol`",`"ambiente_esperado`":`"$AmbienteEsperado`",`"ts`":$Ts,`"nonce`":`"$Nonce`"}"
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
        $idr = $j.data.reserva.id_reserva
        $np  = 0; if ($j.data.pagos) { $np = @($j.data.pagos).Count }
        $sr  = $j.data.reserva.saldo_real
        Write-Host ("    HTTP $code | ok:true | id_reserva=$idr | pagos=$np | saldo_real=$sr") -ForegroundColor Green
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
  Write-Host "Falta pegar el secreto en `$Secret (debe ser igual al del nodo validar_firma_ts_rol)." -ForegroundColor Red
  return
}
if ($IdReservaOk -le 0 -or $IdReservaInexistente -le 0) {
  Write-Host "Falta completar `$IdReservaOk y `$IdReservaInexistente (ver queries read-only en el runsheet B6)." -ForegroundColor Red
  return
}

Write-Host "Wrapper: $WebhookUrl" -ForegroundColor Magenta
$now = [long][DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$ACT = "reserva.detalle"            # EXPECTED_ACTION del wrapper
$P_OK   = "{`"id_reserva`":$IdReservaOk}"
$P_NX   = "{`"id_reserva`":$IdReservaInexistente}"

# --- 1: vicky, firma valida, ambiente test, id valido  ->  ok:true ---
$b = New-Body -Action $ACT -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce ([guid]::NewGuid().ToString()) -PayloadJson $P_OK
Send-Probe -Caso "1. vicky OK (id valido)" -Body $b -Signature (Get-Signature -Body $b -Key $Secret) `
  -Esperado "ok:true, id_reserva=$IdReservaOk, pagos>=0, saldo_real numerico"

# --- 2: socio, firma valida, ambiente test, id valido  ->  ok:true ---
$b = New-Body -Action $ACT -Rol "socio" -AmbienteEsperado "test" -Ts $now -Nonce ([guid]::NewGuid().ToString()) -PayloadJson $P_OK
Send-Probe -Caso "2. socio OK (id valido)" -Body $b -Signature (Get-Signature -Body $b -Key $Secret) `
  -Esperado "ok:true, id_reserva=$IdReservaOk"

# --- 3: jenny (rol valido del portal, NO habilitado para A05)  ->  rol_no_permitido ---
$b = New-Body -Action $ACT -Rol "jenny" -AmbienteEsperado "test" -Ts $now -Nonce ([guid]::NewGuid().ToString()) -PayloadJson $P_OK
Send-Probe -Caso "3. jenny directo al wrapper" -Body $b -Signature (Get-Signature -Body $b -Key $Secret) `
  -Esperado "ok:false, rol_no_permitido"

# --- 4: intruso (rol inexistente)  ->  rol_no_permitido ---
$b = New-Body -Action $ACT -Rol "intruso" -AmbienteEsperado "test" -Ts $now -Nonce ([guid]::NewGuid().ToString()) -PayloadJson $P_OK
Send-Probe -Caso "4. intruso (rol basura)" -Body $b -Signature (Get-Signature -Body $b -Key $Secret) `
  -Esperado "ok:false, rol_no_permitido"

# --- 5: firma invalida (firmamos con secreto equivocado)  ->  firma_invalida ---
$b = New-Body -Action $ACT -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce ([guid]::NewGuid().ToString()) -PayloadJson $P_OK
Send-Probe -Caso "5. firma invalida" -Body $b -Signature (Get-Signature -Body $b -Key "SECRETO_EQUIVOCADO") `
  -Esperado "ok:false, firma_invalida"

# --- 6: ts viejo (10 min atras)  ->  ts_fuera_de_ventana ---
$b = New-Body -Action $ACT -Rol "vicky" -AmbienteEsperado "test" -Ts ($now - 600000) -Nonce ([guid]::NewGuid().ToString()) -PayloadJson $P_OK
Send-Probe -Caso "6. ts viejo (-10min)" -Body $b -Signature (Get-Signature -Body $b -Key $Secret) `
  -Esperado "ok:false, ts_fuera_de_ventana"

# --- 7: ambiente cruzado, ambiente_esperado='ops' contra wrapper TEST  ->  ambiente_incorrecto ---
$b = New-Body -Action $ACT -Rol "vicky" -AmbienteEsperado "ops" -Ts $now -Nonce ([guid]::NewGuid().ToString()) -PayloadJson $P_OK
Send-Probe -Caso "7. ambiente cruzado (ops->test)" -Body $b -Signature (Get-Signature -Body $b -Key $Secret) `
  -Esperado "ok:false, ambiente_incorrecto (detail esperado=ops real=test)"

# --- 8: action incorrecta (sobre bien firmado, action ajena)  ->  accion_desconocida ---
#       Falla en action binding ANTES del check de payload (por eso el payload es valido).
$b = New-Body -Action "calendario.operativo" -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce ([guid]::NewGuid().ToString()) -PayloadJson $P_OK
Send-Probe -Caso "8. action incorrecta (calendario.operativo)" -Body $b -Signature (Get-Signature -Body $b -Key $Secret) `
  -Esperado "ok:false, accion_desconocida"

# --- 9: spine OK pero id_reserva inexistente  ->  no_encontrado ---
$b = New-Body -Action $ACT -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce ([guid]::NewGuid().ToString()) -PayloadJson $P_NX
Send-Probe -Caso "9. id inexistente ($IdReservaInexistente)" -Body $b -Signature (Get-Signature -Body $b -Key $Secret) `
  -Esperado "ok:false, no_encontrado"

# --- 10: payload sin id_reserva (objeto vacio)  ->  payload_invalido ---
$b = New-Body -Action $ACT -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce ([guid]::NewGuid().ToString()) -PayloadJson "{}"
Send-Probe -Caso "10. payload {} (id ausente)" -Body $b -Signature (Get-Signature -Body $b -Key $Secret) `
  -Esperado "ok:false, payload_invalido"

# --- 11: id_reserva como string  ->  payload_invalido ---
$b = New-Body -Action $ACT -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce ([guid]::NewGuid().ToString()) -PayloadJson "{`"id_reserva`":`"42`"}"
Send-Probe -Caso "11. id_reserva string (`"42`")" -Body $b -Signature (Get-Signature -Body $b -Key $Secret) `
  -Esperado "ok:false, payload_invalido"

# --- 12: id_reserva negativo  ->  payload_invalido ---
$b = New-Body -Action $ACT -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce ([guid]::NewGuid().ToString()) -PayloadJson "{`"id_reserva`":-5}"
Send-Probe -Caso "12. id_reserva negativo (-5)" -Body $b -Signature (Get-Signature -Body $b -Key $Secret) `
  -Esperado "ok:false, payload_invalido"

# --- 13: id_reserva decimal  ->  payload_invalido ---
$b = New-Body -Action $ACT -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce ([guid]::NewGuid().ToString()) -PayloadJson "{`"id_reserva`":4.5}"
Send-Probe -Caso "13. id_reserva decimal (4.5)" -Body $b -Signature (Get-Signature -Body $b -Key $Secret) `
  -Esperado "ok:false, payload_invalido"

# --- 14: id_reserva no-safe-integer (1e20)  ->  payload_invalido ---
$b = New-Body -Action $ACT -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce ([guid]::NewGuid().ToString()) -PayloadJson "{`"id_reserva`":100000000000000000000}"
Send-Probe -Caso "14. id_reserva no-safe (1e20)" -Body $b -Signature (Get-Signature -Body $b -Key $Secret) `
  -Esperado "ok:false, payload_invalido"

Write-Host "`nListo. 14 casos. Compara cada veredicto con su 'esperado' (criterios en el runsheet B6)." -ForegroundColor Green
