# ============================================================================
# A10MP_B4_smoke_directo.ps1
# Carril C / Portal Operativo Interno - A10-MP (cobranza.registrar_cobro).
# Smoke DIRECTO al wrapper n8n "portal-a10mp-registrar-cobro__TEST", SIN gateway.
#
# Sobre A10-MP (estilo W10): { action, payload, rol, ambiente_esperado, ts, nonce, actor }
#   con idempotency_key DENTRO de payload. Firma HMAC-SHA256 sobre los BYTES EXACTOS.
# Dedup por source_event = derivado de (id_reserva + idempotency_key). Replay byte-identico
#   NO es nonce_replay (A10-MP no dedup por nonce): es idempotente por source_event (B3.1).
#
# REQUIERE: fixtures de A10MP_B4_setup.sql (reservas 9910001..9910016 con saldo).
# SEGURIDAD = 0 escrituras (todo rebota antes de escribir). FUNCIONAL/IDEMP/NOTAS escriben.
# Marcador teardown: los cobros quedan con source_event 'portal_test_a10mp_res%'.
#
# ASCII PURO (PS 5.1 / CP1252). Sin -Parallel. HttpWebRequest + ContentLength + TLS 1.2.
# Contadores $script: . El secreto NO se commitea: pegarlo en $Secret (= nodo validar_firma_ts_rol).
# ============================================================================

[Net.ServicePointManager]::SecurityProtocol = `
  [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# ====== CONFIG (editar) ======
$BaseUrl = "https://federicosecchi.app.n8n.cloud"
$Webhook = "portal-a10mp-registrar-cobro__TEST"
$Secret  = "d3cb37c88b688c6e104f133d08990312134ee5df6775e2dff267e0deac16c3f4"
# =============================

$WebhookUrl = "$($BaseUrl.TrimEnd('/'))/webhook/$Webhook"
$ACT = "cobranza.registrar_cobro"

$script:passed = 0
$script:failed = 0
$script:failsList = @()
$script:codesSeen = @{}
$script:secWrites = 0
$script:ALLOWLIST = @('payload_invalido','no_autorizado','rol_no_permitido','accion_desconocida','no_encontrado','conflicto','error_entorno','error_interno','estado_incierto','firma_invalida','ts_fuera_de_ventana','raw_body_ausente','ambiente_incorrecto')

# ---- Sobre A10-MP (CON nonce; idempotency_key va en el payload) ----
function New-Env {
  param([string]$Action, [object]$Payload, [string]$Actor, [string]$Rol, [string]$Amb, [long]$Ts, [string]$Nonce)
  $o = [ordered]@{ action = $Action; payload = $Payload; rol = $Rol; ambiente_esperado = $Amb; ts = $Ts; nonce = $Nonce; actor = $Actor }
  return ($o | ConvertTo-Json -Compress -Depth 8)
}

function Get-Signature {
  param([string]$Body, [string]$Key)
  $h = New-Object System.Security.Cryptography.HMACSHA256
  $h.Key = [System.Text.Encoding]::UTF8.GetBytes($Key)
  $hash = $h.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Body))
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

# Payload de cobro multi-porcion. Solo incluye las porciones > 0 (las ausentes -> 0 en el validador).
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

function NewNonce { return ([guid]::NewGuid().ToString('N')) }
function NowMs { return [long][DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() }

# Atajo: arma sobre vicky valido, firma y postea. $Actor/$Rol por defecto vicky/vicky.
function Cobrar {
  param([object]$Payload, [string]$Actor = 'vicky', [string]$Rol = 'vicky', [string]$Amb = 'test', $Ts = $null, [string]$Nonce = $null)
  if ($null -eq $Ts) { $Ts = NowMs }
  if (-not $Nonce) { $Nonce = NewNonce }
  $b = New-Env -Action $ACT -Payload $Payload -Actor $Actor -Rol $Rol -Amb $Amb -Ts $Ts -Nonce $Nonce
  return (Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret))
}

function Track-Code { param($resp); if ($resp.json -and ($resp.json.ok -eq $false) -and $resp.json.error) { $script:codesSeen[$resp.json.error.code] = $true } }
function Record {
  param([string]$name, [bool]$ok, [string]$detail)
  if ($ok) { $script:passed++; Write-Host "PASS  $name" -ForegroundColor Green }
  else { $script:failed++; $script:failsList += "$name :: $detail"; Write-Host "FAIL  $name  ($detail)" -ForegroundColor Red }
}
# Seguridad: espera ok:false code concreto. Si llega ok:true con data -> escritura indebida.
function Assert-Code {
  param([string]$name, $resp, [string]$expected)
  Track-Code $resp
  if ($resp.json -and ($resp.json.ok -eq $true) -and $resp.json.data) { $script:secWrites++ }
  $code = $null
  if ($resp.json -and ($resp.json.ok -eq $false) -and $resp.json.error) { $code = $resp.json.error.code }
  Record $name ($code -eq $expected) "esperaba ok:false code=$expected; HTTP $($resp.code) ok=$($resp.json.ok) code=$code"
}
# Alta nueva: ok:true, data.idempotent_match=false. Devuelve data.
function Assert-OkNew {
  param([string]$name, $resp, [scriptblock]$Check = $null)
  Track-Code $resp
  $d = $null; if ($resp.json) { $d = $resp.json.data }
  $ok = ($resp.json -and ($resp.json.ok -eq $true) -and $d -and ($d.idempotent_match -eq $false))
  if ($ok -and $Check) { $ok = [bool](& $Check $d) }
  $code = ''; if ($resp.json -and $resp.json.error) { $code = $resp.json.error.code }
  Record $name $ok "esperaba ok nuevo; HTTP $($resp.code) ok=$($resp.json.ok) code=$code"
  if ($ok) { return $d }
  return $null
}
# Idempotente: ok:true, data.idempotent_match=true.
function Assert-OkIdemp {
  param([string]$name, $resp)
  Track-Code $resp
  $d = $null; if ($resp.json) { $d = $resp.json.data }
  $ok = ($resp.json -and ($resp.json.ok -eq $true) -and $d -and ($d.idempotent_match -eq $true))
  Record $name $ok "esperaba idempotent_match; HTTP $($resp.code) ok=$($resp.json.ok)"
}
function Assert-AllowlistMeta {
  $bad = @()
  foreach ($c in $script:codesSeen.Keys) { if ($script:ALLOWLIST -notcontains $c) { $bad += $c } }
  Record "META allowlist (todos los error.code en la allowlist)" (@($bad).Count -eq 0) ("fuera de allowlist: " + ($bad -join ', '))
}
function Near { param($a, $b) return ([math]::Abs([double]$a - [double]$b) -lt 0.01) }

if ($Secret.StartsWith("__PEGAR_")) {
  Write-Host "Falta pegar el secreto en `$Secret (igual al del nodo validar_firma_ts_rol)." -ForegroundColor Red
  return
}

Write-Host "Wrapper: $WebhookUrl" -ForegroundColor Magenta
$now = NowMs

# ============================ SEGURIDAD (0 escrituras) ============================
Write-Host "`n----- SEGURIDAD (0 escrituras) -----" -ForegroundColor Magenta

# 1. firma invalida
$b = New-Env -Action $ACT -Payload (P-Cobro 9910001 -ef 1000 -key 'segfirma00001') -Actor 'vicky' -Rol 'vicky' -Amb 'test' -Ts $now -Nonce (NewNonce)
Assert-Code "1. firma invalida -> firma_invalida" (Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key 'SECRETO_EQUIVOCADO')) "firma_invalida"

# 2. ts viejo / 3. ts futuro
Assert-Code "2. ts viejo -> ts_fuera_de_ventana" (Cobrar -Payload (P-Cobro 9910001 -ef 1000 -key 'segts0000001') -Ts ($now - 600000)) "ts_fuera_de_ventana"
Assert-Code "3. ts futuro -> ts_fuera_de_ventana" (Cobrar -Payload (P-Cobro 9910001 -ef 1000 -key 'segts0000002') -Ts ($now + 600000)) "ts_fuera_de_ventana"

# 4. rol jenny / 5. rol vacio
Assert-Code "4. rol jenny -> rol_no_permitido" (Cobrar -Payload (P-Cobro 9910001 -ef 1000 -key 'segrol0000001') -Rol 'jenny') "rol_no_permitido"
Assert-Code "5. rol vacio -> rol_no_permitido" (Cobrar -Payload (P-Cobro 9910001 -ef 1000 -key 'segrol0000002') -Rol '') "rol_no_permitido"

# 6. action incorrecta
$b = New-Env -Action 'cobranza.registrar_saldo' -Payload (P-Cobro 9910001 -ef 1000 -key 'segact0000001') -Actor 'vicky' -Rol 'vicky' -Amb 'test' -Ts $now -Nonce (NewNonce)
Assert-Code "6. action incorrecta -> payload_invalido" (Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)) "payload_invalido"

# 7. ambiente ops (cruzado)
Assert-Code "7. ambiente ops -> ambiente_incorrecto" (Cobrar -Payload (P-Cobro 9910001 -ef 1000 -key 'segamb0000001') -Amb 'ops') "ambiente_incorrecto"

# 8. actor desconocido
Assert-Code "8. actor desconocido -> payload_invalido" (Cobrar -Payload (P-Cobro 9910001 -ef 1000 -key 'segactor00001') -Actor 'mengano') "payload_invalido"

# 9. suma 0 (sin porciones)
$p = [ordered]@{ id_reserva = 9910001; idempotency_key = 'segsuma000001' }
Assert-Code "9. suma 0 (sin porciones) -> payload_invalido" (Cobrar -Payload $p) "payload_invalido"

# 10. otros > 0 sin origen
$p = [ordered]@{ id_reserva = 9910001; monto_otros = 5000; descripcion_otros = 'x'; idempotency_key = 'segotros00001' }
Assert-Code "10. otros sin origen -> payload_invalido" (Cobrar -Payload $p) "payload_invalido"

# 11. monto con 3 decimales
$p = [ordered]@{ id_reserva = 9910001; monto_efectivo = 100.123; idempotency_key = 'segdec000001' }
Assert-Code "11. monto 3 decimales -> payload_invalido" (Cobrar -Payload $p) "payload_invalido"

# 12. idempotency_key corta
Assert-Code "12. idempotency_key corta -> payload_invalido" (Cobrar -Payload (P-Cobro 9910001 -ef 1000 -key 'abc')) "payload_invalido"

# 13. clave de control en payload (actor) -> reject-unknown
$p = [ordered]@{ id_reserva = 9910001; monto_efectivo = 1000; idempotency_key = 'segctrl00001'; actor = 'franco' }
Assert-Code "13. control 'actor' en payload -> payload_invalido" (Cobrar -Payload $p) "payload_invalido"

# 14. subtipo invalido
$p = [ordered]@{ id_reserva = 9910001; monto_transferencia = 1000; subtipo_transferencia = 'paypal'; idempotency_key = 'segsub000001' }
Assert-Code "14. subtipo invalido -> payload_invalido" (Cobrar -Payload $p) "payload_invalido"

Write-Host ("Escrituras detectadas en SEGURIDAD: " + $script:secWrites + " (debe ser 0)") -ForegroundColor DarkGray
Record "META seguridad 0 escrituras" ($script:secWrites -eq 0) ("secWrites=" + $script:secWrites)

# ============================ FUNCIONAL (escribe) ============================
Write-Host "`n----- FUNCIONAL (escribe cobros) -----" -ForegroundColor Magenta

# D1 efectivo 60000 en 9910001 (saldo 60000 -> 0).
Assert-OkNew "D1. efectivo 60000 (9910001) -> ok, saldada" (Cobrar -Payload (P-Cobro 9910001 -ef 60000 -key 'a10mpD1ef00001')) { param($d) (Near $d.suma_saldo 60000) -and (Near $d.suma_extra 0) -and ($d.saldada -eq $true) } | Out-Null

# D2 transferencia bancaria 40000 en 9910002 -> recargo 2000 (extra), saldo baja 40000.
Assert-OkNew "D2. transf bancaria 40000 (9910002) -> recargo 2000" (Cobrar -Payload (P-Cobro 9910002 -tr 40000 -subtipo 'bancaria' -key 'a10mpD2tb00001')) { param($d) (Near $d.suma_saldo 40000) -and (Near $d.suma_extra 2000) -and (Near $d.total_cobrado 42000) } | Out-Null

# D3 transferencia mp 40000 en 9910003 -> recargo 2000.
Assert-OkNew "D3. transf mp 40000 (9910003) -> recargo 2000" (Cobrar -Payload (P-Cobro 9910003 -tr 40000 -subtipo 'mp' -key 'a10mpD3tm00001')) { param($d) (Near $d.suma_saldo 40000) -and (Near $d.suma_extra 2000) } | Out-Null

# D4 mixto efectivo 50000 + transferencia 30000 en 9910004 -> recargo 1500.
Assert-OkNew "D4. mixto ef50k+transf30k (9910004) -> recargo 1500" (Cobrar -Payload (P-Cobro 9910004 -ef 50000 -tr 30000 -subtipo 'bancaria' -key 'a10mpD4mx00001')) { param($d) (Near $d.suma_saldo 80000) -and (Near $d.suma_extra 1500) } | Out-Null

# D5 efectivo 50000 + transferencia 30000 + otros 20000 en 9910005 -> recargo 1500, saldo 100000.
Assert-OkNew "D5. ef50k+transf30k+otros20k (9910005) -> saldada" (Cobrar -Payload (P-Cobro 9910005 -ef 50000 -tr 30000 -subtipo 'mp' -ot 20000 -origen 'USDT' -desc 'equivalente ARS' -key 'a10mpD5tr00001')) { param($d) (Near $d.suma_saldo 100000) -and (Near $d.suma_extra 1500) -and ($d.saldada -eq $true) } | Out-Null

# D6 otros 20000 (sin recargo) en 9910006.
Assert-OkNew "D6. otros 20000 sin recargo (9910006)" (Cobrar -Payload (P-Cobro 9910006 -ot 20000 -origen 'cripto' -desc 'pago en especie' -key 'a10mpD6ot00001')) { param($d) (Near $d.suma_saldo 20000) -and (Near $d.suma_extra 0) } | Out-Null

# ============================ IDEMPOTENCIA (firma canonica B3.1) ============================
Write-Host "`n----- IDEMPOTENCIA (firma canonica) -----" -ForegroundColor Magenta

# A. misma key + mismo payload exacto -> match.
$kA = 'a10mpAidem0001'
Assert-OkNew "A.1 alta efectivo 100000 (9910007)" (Cobrar -Payload (P-Cobro 9910007 -ef 100000 -key $kA)) | Out-Null
Assert-OkIdemp "A.2 replay mismo payload -> idempotent_match" (Cobrar -Payload (P-Cobro 9910007 -ef 100000 -key $kA))

# B. misma key + efectivo vs transferencia -> conflicto.
$kB = 'a10mpBconf0001'
Assert-OkNew "B.1 alta efectivo 100000 (9910008)" (Cobrar -Payload (P-Cobro 9910008 -ef 100000 -key $kB)) | Out-Null
Assert-Code "B.2 misma key, transferencia 100000 -> conflicto" (Cobrar -Payload (P-Cobro 9910008 -tr 100000 -subtipo 'bancaria' -key $kB)) "conflicto"

# C. misma key + transferencia bancaria vs mp -> conflicto.
$kC = 'a10mpCconf0001'
Assert-OkNew "C.1 alta transf bancaria 100000 (9910009)" (Cobrar -Payload (P-Cobro 9910009 -tr 100000 -subtipo 'bancaria' -key $kC)) | Out-Null
Assert-Code "C.2 misma key, transf mp 100000 -> conflicto" (Cobrar -Payload (P-Cobro 9910009 -tr 100000 -subtipo 'mp' -key $kC)) "conflicto"

# D. misma key + efectivo vs otros -> conflicto.
$kD = 'a10mpDconf0001'
Assert-OkNew "D.1 alta efectivo 100000 (9910010)" (Cobrar -Payload (P-Cobro 9910010 -ef 100000 -key $kD)) | Out-Null
Assert-Code "D.2 misma key, otros 100000 -> conflicto" (Cobrar -Payload (P-Cobro 9910010 -ot 100000 -origen 'USDT' -desc 'equiv' -key $kD)) "conflicto"

# E. misma key + otros, misma plata, descripcion distinta -> conflicto.
$kE = 'a10mpEconf0001'
Assert-OkNew "E.1 alta otros 100000 desc-A (9910011)" (Cobrar -Payload (P-Cobro 9910011 -ot 100000 -origen 'USDT' -desc 'pago A' -key $kE)) | Out-Null
Assert-Code "E.2 misma key, otros desc-B -> conflicto" (Cobrar -Payload (P-Cobro 9910011 -ot 100000 -origen 'USDT' -desc 'pago B' -key $kE)) "conflicto"

# ============================ NOTAS DEL OPERADOR (B3.2) ============================
Write-Host "`n----- NOTAS DEL OPERADOR -----" -ForegroundColor Magenta

# F-notas. cobro con nota (verificar persistencia con A10MP_B4_verif.sql en 9910012).
Assert-OkNew "F. transf 100000 + nota (9910012) -> ok (verif SQL confirma nota_operador)" (Cobrar -Payload (P-Cobro 9910012 -tr 100000 -subtipo 'bancaria' -key 'a10mpFnota0001' -notas 'pago en recepcion')) | Out-Null

# G. misma key + mismas notas -> match.
$kG = 'a10mpGnota0001'
Assert-OkNew "G.1 alta efectivo 100000 + nota (9910013)" (Cobrar -Payload (P-Cobro 9910013 -ef 100000 -key $kG -notas 'nota igual')) | Out-Null
Assert-OkIdemp "G.2 misma key + misma nota -> idempotent_match" (Cobrar -Payload (P-Cobro 9910013 -ef 100000 -key $kG -notas 'nota igual'))

# H. misma key + nota distinta -> conflicto.
$kH = 'a10mpHnota0001'
Assert-OkNew "H.1 alta efectivo 100000 + nota (9910014)" (Cobrar -Payload (P-Cobro 9910014 -ef 100000 -key $kH -notas 'nota original')) | Out-Null
Assert-Code "H.2 misma key + nota distinta -> conflicto" (Cobrar -Payload (P-Cobro 9910014 -ef 100000 -key $kH -notas 'nota cambiada')) "conflicto"

# I. misma key + con-nota vs sin-nota -> conflicto.
$kI = 'a10mpInota0001'
Assert-OkNew "I.1 alta efectivo 100000 + nota (9910015)" (Cobrar -Payload (P-Cobro 9910015 -ef 100000 -key $kI -notas 'con nota')) | Out-Null
Assert-Code "I.2 misma key + sin nota -> conflicto" (Cobrar -Payload (P-Cobro 9910015 -ef 100000 -key $kI)) "conflicto"

# ============================ SOBREPAGO ============================
Write-Host "`n----- SOBREPAGO (rebota sin escribir) -----" -ForegroundColor Magenta
# 9910016 saldo 70000, intenta efectivo 80000 -> excede_saldo -> conflicto (0 pagos de cobro).
Assert-Code "R. sobrepago 80000 > 70000 (9910016) -> conflicto" (Cobrar -Payload (P-Cobro 9910016 -ef 80000 -key 'a10mpRsobre001')) "conflicto"

# ============================ META + RESUMEN ============================
Write-Host "`n----- META -----" -ForegroundColor Magenta
Assert-AllowlistMeta

Write-Host ""
Write-Host "==================================================="
Write-Host ("RESULTADO: {0} PASS / {1} FAIL" -f $script:passed, $script:failed)
if ($script:failed -gt 0) { Write-Host "Fallos:"; $script:failsList | ForEach-Object { Write-Host "  - $_" } }
Write-Host ("Codigos de error vistos: " + ((@($script:codesSeen.Keys) | Sort-Object) -join ', '))
Write-Host ""
Write-Host "Despues: correr A10MP_B4_verif.sql (lineas por caso + separacion contable 9910002 + rollback)." -ForegroundColor DarkGray
Write-Host "Luego: A10MP_B4_teardown.sql para limpiar." -ForegroundColor DarkGray
