# ============================================================================
# C_SLICE3B_A11_smoke_directo.ps1
# Carril C / Portal Operativo Interno - Slice 3b, A11 (cargar.gasto_interno).
# Smoke DIRECTO al wrapper n8n "portal-a11-cargar-gasto-interno__TEST", SIN gateway.
#
# A11 es ESCRITURA (primera no-idempotente del portal). El smoke arma el sobre
#   { action, actor, rol, ambiente_esperado, ts, idempotency_key, payload }
#   y lo firma HMAC-SHA256 sobre los BYTES EXACTOS que envia.
#
# D-C-56: el sobre NO lleva nonce. El smoke firma; el wrapper deriva
#   nonce = HMAC esperado (hex, lowercase). Mismo sobre byte-identico -> misma
#   firma -> mismo nonce -> conflicto/nonce_replay. Sobre con ts nuevo + misma
#   idempotency_key -> nonce distinto pero respuesta idempotente (mismo id_gasto).
#
# ASCII PURO (PS 5.1 / CP1252). Sin -Parallel. Sin if inline en -ForegroundColor.
# HttpWebRequest con ContentLength + TLS 1.2 (L-C-17b). Contadores $script: (L-C-17d).
# Parametros opcionales [object]=$null, NO [string] (L-C-17a). @(...).Count (L-C-17c).
#
# SEGURIDAD = 0 escrituras: todos los casos rebotan (wrapper) o revierten
#   (constraint en la funcion, savepoint). El contador $script:secWrites debe
#   quedar en 0; si algun caso de seguridad devolviera ok:true con id_gasto, falla.
# FUNCIONAL = 5 escrituras netas (altas A/C/D/E + 1 alta en la key de replay).
#
# MARCADOR de teardown: idempotency_key con prefijo "smoke-a11-<runid>-". El
#   <runid> es unico por corrida (no colisiona entre runs). Limpieza:
#   C_SLICE3B_A11_teardown.sql borra todo 'smoke-a11-%' FK-safe (traza -> gasto),
#   sin tocar el fixture 9F (ids 30-34, creado_por='seed_9f_validacion').
#
# GATE RESIDUAL de seguridad (opcional, a correr en el SQL Editor de TEST tras la
#   fase de seguridad y antes de aceptar la funcional; reemplazar <runid>):
#     SELECT count(*) AS gastos_sec
#     FROM gastos_internos g
#     WHERE g.id_gasto IN (SELECT id_gasto FROM portal_idempotencia
#                          WHERE idempotency_key LIKE 'smoke-a11-<runid>-sec-%');
#   Debe dar 0. (El smoke ya lo verifica por respuesta con $script:secWrites.)
#
# NO toca OPS. El secreto NO se commitea: se pega en $Secret y se borra antes de
#   guardar. Debe ser el MISMO valor del nodo validar_firma_ts_rol (Modo B, L-C-10).
# ============================================================================

[Net.ServicePointManager]::SecurityProtocol = `
  [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# ====== CONFIG (editar) ======
$BaseUrl = "https://federicosecchi.app.n8n.cloud"
$Webhook = "portal-a11-cargar-gasto-interno__TEST"
$Secret  = "Secreto_no_pegar"
# =============================

$WebhookUrl = "$($BaseUrl.TrimEnd('/'))/webhook/$Webhook"
$ACT = "cargar.gasto_interno"

# runid unico por corrida -> idempotency_key sin colisiones entre runs.
$RUNID = (Get-Date -Format "yyyyMMddHHmmss") + "-" + ([guid]::NewGuid().ToString("N").Substring(0,6))

$script:passed = 0
$script:failed = 0
$script:failsList = @()
$script:codesSeen = @{}
$script:secWrites = 0
$script:ALLOWLIST = @('payload_invalido','no_autorizado','rol_no_permitido','accion_desconocida','no_encontrado','conflicto','error_entorno','error_interno','estado_incierto','firma_invalida','ts_fuera_de_ventana','raw_body_ausente','ambiente_incorrecto')

# Sobre A11 (SIN nonce). $Payload acepta hashtable/string/array (para C1).
# $OmitIdem=$true -> no incluye la clave idempotency_key (caso "ausente").
function New-Env {
  param([string]$Action, [object]$Payload, [string]$Actor, [string]$Rol, [string]$Amb, [long]$Ts, [object]$IdemKey = $null, [bool]$OmitIdem = $false)
  $o = [ordered]@{ action = $Action; actor = $Actor; rol = $Rol; ambiente_esperado = $Amb; ts = $Ts }
  if (-not $OmitIdem) { $o['idempotency_key'] = $IdemKey }
  $o['payload'] = $Payload
  return ($o | ConvertTo-Json -Compress -Depth 8)
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

# Espera ok:false con un code concreto. Usado SOLO en seguridad: si llega ok:true
# con id_gasto, lo cuenta como escritura indebida ($script:secWrites).
function Assert-Code {
  param([string]$name, $resp, [string]$expected)
  Track-Code $resp
  if ($resp.json -and ($resp.json.ok -eq $true) -and $resp.json.data -and ($null -ne $resp.json.data.id_gasto)) { $script:secWrites++ }
  $code = $null
  if ($resp.json -and ($resp.json.ok -eq $false) -and $resp.json.error) { $code = $resp.json.error.code }
  $ok = ($code -eq $expected)
  Record $name $ok "esperaba ok:false code=$expected; HTTP $($resp.code) ok=$($resp.json.ok) code=$code"
}

# Alta nueva: ok:true, data.idempotente=false, data.id_gasto presente. Devuelve el id.
function Assert-OkNew {
  param([string]$name, $resp)
  Track-Code $resp
  $d = $null; if ($resp.json) { $d = $resp.json.data }
  $ok = ($resp.json -and ($resp.json.ok -eq $true) -and $d -and ($d.idempotente -eq $false) -and ($null -ne $d.id_gasto))
  $code = ''; if ($resp.json -and $resp.json.error) { $code = $resp.json.error.code }
  Record $name $ok "esperaba ok nuevo con id_gasto; HTTP $($resp.code) ok=$($resp.json.ok) code=$code"
  if ($ok) { return $d.id_gasto }
  return $null
}

# Idempotente: ok:true, data.idempotente=true, mismo id_gasto que el alta.
function Assert-OkIdemp {
  param([string]$name, $resp, $expectedId)
  Track-Code $resp
  $d = $null; if ($resp.json) { $d = $resp.json.data }
  $ok = ($resp.json -and ($resp.json.ok -eq $true) -and $d -and ($d.idempotente -eq $true) -and ($d.id_gasto -eq $expectedId))
  $got = ''; if ($d) { $got = $d.id_gasto }
  Record $name $ok "esperaba ok idempotente id=$expectedId; HTTP $($resp.code) ok=$($resp.json.ok) id=$got"
}

# Conflicto con detail.reason concreto (nonce_replay / payload_mismatch / actor_mismatch).
function Assert-CodeReason {
  param([string]$name, $resp, [string]$expCode, [string]$expReason)
  Track-Code $resp
  $code = $null; $reason = $null
  if ($resp.json -and ($resp.json.ok -eq $false) -and $resp.json.error) {
    $code = $resp.json.error.code
    if ($resp.json.error.detail) { $reason = $resp.json.error.detail.reason }
  }
  $ok = (($code -eq $expCode) -and ($reason -eq $expReason))
  Record $name $ok "esperaba code=$expCode reason=$expReason; HTTP $($resp.code) code=$code reason=$reason"
}

function Assert-AllowlistMeta {
  $bad = @()
  foreach ($c in $script:codesSeen.Keys) { if ($script:ALLOWLIST -notcontains $c) { $bad += $c } }
  $ok = (@($bad).Count -eq 0)
  Record "META allowlist (todos los error.code en la allowlist)" $ok ("fuera de allowlist: " + ($bad -join ', '))
}

if ($Secret.StartsWith("__PEGAR_")) {
  Write-Host "Falta pegar el secreto en `$Secret (igual al del nodo validar_firma_ts_rol)." -ForegroundColor Red
  return
}

Write-Host "Wrapper: $WebhookUrl" -ForegroundColor Magenta
Write-Host "RunID:   $RUNID" -ForegroundColor DarkGray
$now = [long][DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()

# Helpers de payload de negocio valido por clase (con comentario para satisfacer
# chk_gi_comentario). caja => sin id_socio_pagador.
function PA { param($et = "luz"); return @{ fecha = "2026-07-15"; clase = "A"; etiqueta = $et; monto = 1500; pagador_tipo = "caja"; comentario = "gasto operativo A" } }
function PC { return @{ fecha = "2026-07-16"; clase = "C"; etiqueta = "insumos"; monto = 2200; pagador_tipo = "caja"; comentario = "gasto operativo C" } }
function PD { return @{ fecha = "2026-07-17"; clase = "D"; etiqueta = "mantenimiento zona"; monto = 3100; id_zona = [int]1; pagador_tipo = "caja"; comentario = "gasto zona D" } }
function PE { return @{ fecha = "2026-07-18"; clase = "E"; etiqueta = "arreglo cabana"; monto = 4300; id_cabana = [int]1; pagador_tipo = "caja"; comentario = "gasto cabana E" } }

# Atajo: firma y postea en un paso.
function Probe { param([string]$Body); return (Send-Probe -Body $Body -Signature (Get-Signature -Body $Body -Key $Secret)) }
function K { param([string]$suf); return "smoke-a11-$RUNID-$suf" }

# ============================ SEGURIDAD (26, 0 escrituras) ============================
Write-Host "`n----- SEGURIDAD (0 escrituras) -----" -ForegroundColor Magenta

# -- Transporte / auth (8) --
# 1. firma invalida (secreto equivocado)
$b = New-Env -Action $ACT -Payload (PA) -Actor "vicky" -Rol "vicky" -Amb "test" -Ts $now -IdemKey (K "sec-01")
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key "SECRETO_EQUIVOCADO")
Assert-Code "1. firma invalida -> firma_invalida" $r "firma_invalida"

# 2. ts viejo
$b = New-Env -Action $ACT -Payload (PA) -Actor "vicky" -Rol "vicky" -Amb "test" -Ts ($now - 600000) -IdemKey (K "sec-02")
Assert-Code "2. ts viejo -> ts_fuera_de_ventana" (Probe $b) "ts_fuera_de_ventana"

# 3. ts futuro
$b = New-Env -Action $ACT -Payload (PA) -Actor "vicky" -Rol "vicky" -Amb "test" -Ts ($now + 600000) -IdemKey (K "sec-03")
Assert-Code "3. ts futuro -> ts_fuera_de_ventana" (Probe $b) "ts_fuera_de_ventana"

# 4. rol jenny
$b = New-Env -Action $ACT -Payload (PA) -Actor "vicky" -Rol "jenny" -Amb "test" -Ts $now -IdemKey (K "sec-04")
Assert-Code "4. rol jenny -> rol_no_permitido" (Probe $b) "rol_no_permitido"

# 5. rol vacio
$b = New-Env -Action $ACT -Payload (PA) -Actor "vicky" -Rol "" -Amb "test" -Ts $now -IdemKey (K "sec-05")
Assert-Code "5. rol vacio -> rol_no_permitido" (Probe $b) "rol_no_permitido"

# 6. action incorrecta
$b = New-Env -Action "cobranza.saldos" -Payload (PA) -Actor "vicky" -Rol "vicky" -Amb "test" -Ts $now -IdemKey (K "sec-06")
Assert-Code "6. action incorrecta -> accion_desconocida" (Probe $b) "accion_desconocida"

# 7. ambiente cruzado (ops)
$b = New-Env -Action $ACT -Payload (PA) -Actor "vicky" -Rol "vicky" -Amb "ops" -Ts $now -IdemKey (K "sec-07")
Assert-Code "7. ambiente ops -> ambiente_incorrecto" (Probe $b) "ambiente_incorrecto"

# 8. actor desconocido
$b = New-Env -Action $ACT -Payload (PA) -Actor "mengano" -Rol "vicky" -Amb "test" -Ts $now -IdemKey (K "sec-08")
Assert-Code "8. actor desconocido -> payload_invalido" (Probe $b) "payload_invalido"

# -- Payload rechazado por el wrapper (10) --
# 9. idempotency_key ausente
$b = New-Env -Action $ACT -Payload (PA) -Actor "vicky" -Rol "vicky" -Amb "test" -Ts $now -OmitIdem $true
Assert-Code "9. idempotency_key ausente -> payload_invalido" (Probe $b) "payload_invalido"

# 10. idempotency_key corta (<8)
$b = New-Env -Action $ACT -Payload (PA) -Actor "vicky" -Rol "vicky" -Amb "test" -Ts $now -IdemKey "abc123"
Assert-Code "10. idempotency_key corta -> payload_invalido" (Probe $b) "payload_invalido"

# 11. idempotency_key con simbolos
$b = New-Env -Action $ACT -Payload (PA) -Actor "vicky" -Rol "vicky" -Amb "test" -Ts $now -IdemKey "clave!@#invalida"
Assert-Code "11. idempotency_key simbolos -> payload_invalido" (Probe $b) "payload_invalido"

# 12. payload string (C1: no se coerciona a {})
$b = New-Env -Action $ACT -Payload "soy_un_string" -Actor "vicky" -Rol "vicky" -Amb "test" -Ts $now -IdemKey (K "sec-12")
Assert-Code "12. payload string -> payload_invalido" (Probe $b) "payload_invalido"

# 13. payload array
$b = New-Env -Action $ACT -Payload @(1, 2, 3) -Actor "vicky" -Rol "vicky" -Amb "test" -Ts $now -IdemKey (K "sec-13")
Assert-Code "13. payload array -> payload_invalido" (Probe $b) "payload_invalido"

# 14. clave de negocio desconocida (creado_por en el payload)
$p = PA; $p['creado_por'] = "intruso"
$b = New-Env -Action $ACT -Payload $p -Actor "vicky" -Rol "vicky" -Amb "test" -Ts $now -IdemKey (K "sec-14")
Assert-Code "14. clave desconocida (creado_por) -> payload_invalido" (Probe $b) "payload_invalido"

# 15. clase invalida
$p = PA; $p['clase'] = "X"
$b = New-Env -Action $ACT -Payload $p -Actor "vicky" -Rol "vicky" -Amb "test" -Ts $now -IdemKey (K "sec-15")
Assert-Code "15. clase invalida -> payload_invalido" (Probe $b) "payload_invalido"

# 16. monto <= 0
$p = PA; $p['monto'] = 0
$b = New-Env -Action $ACT -Payload $p -Actor "vicky" -Rol "vicky" -Amb "test" -Ts $now -IdemKey (K "sec-16")
Assert-Code "16. monto<=0 -> payload_invalido" (Probe $b) "payload_invalido"

# 17. fecha invalida
$p = PA; $p['fecha'] = "2026-13-01"
$b = New-Env -Action $ACT -Payload $p -Actor "vicky" -Rol "vicky" -Amb "test" -Ts $now -IdemKey (K "sec-17")
Assert-Code "17. fecha invalida -> payload_invalido" (Probe $b) "payload_invalido"

# 18. pagador_tipo invalido
$p = PA; $p['pagador_tipo'] = "tarjeta"
$b = New-Env -Action $ACT -Payload $p -Actor "vicky" -Rol "vicky" -Amb "test" -Ts $now -IdemKey (K "sec-18")
Assert-Code "18. pagador_tipo invalido -> payload_invalido" (Probe $b) "payload_invalido"

# -- Coherencia que llega a la funcion y REVIERTE (8, savepoint, 0 escrituras) --
# 19. clase D sin zona
$p = @{ fecha = "2026-07-15"; clase = "D"; etiqueta = "zona sin id"; monto = 1000; pagador_tipo = "caja"; comentario = "x" }
$b = New-Env -Action $ACT -Payload $p -Actor "vicky" -Rol "vicky" -Amb "test" -Ts $now -IdemKey (K "sec-19")
Assert-Code "19. clase D sin zona -> payload_invalido" (Probe $b) "payload_invalido"

# 20. clase E sin cabana
$p = @{ fecha = "2026-07-15"; clase = "E"; etiqueta = "cabana sin id"; monto = 1000; pagador_tipo = "caja"; comentario = "x" }
$b = New-Env -Action $ACT -Payload $p -Actor "vicky" -Rol "vicky" -Amb "test" -Ts $now -IdemKey (K "sec-20")
Assert-Code "20. clase E sin cabana -> payload_invalido" (Probe $b) "payload_invalido"

# 21. clase A con zona (no debe llevar)
$p = @{ fecha = "2026-07-15"; clase = "A"; etiqueta = "a con zona"; monto = 1000; id_zona = [int]1; pagador_tipo = "caja"; comentario = "x" }
$b = New-Env -Action $ACT -Payload $p -Actor "vicky" -Rol "vicky" -Amb "test" -Ts $now -IdemKey (K "sec-21")
Assert-Code "21. clase A con zona -> payload_invalido" (Probe $b) "payload_invalido"

# 22. pagador socio sin id_socio
$p = @{ fecha = "2026-07-15"; clase = "A"; etiqueta = "socio sin id"; monto = 1000; pagador_tipo = "socio"; comentario = "x" }
$b = New-Env -Action $ACT -Payload $p -Actor "vicky" -Rol "vicky" -Amb "test" -Ts $now -IdemKey (K "sec-22")
Assert-Code "22. pagador socio sin id_socio -> payload_invalido" (Probe $b) "payload_invalido"

# 23. pagador caja con id_socio
$p = @{ fecha = "2026-07-15"; clase = "A"; etiqueta = "caja con socio"; monto = 1000; pagador_tipo = "caja"; id_socio_pagador = [int]1; comentario = "x" }
$b = New-Env -Action $ACT -Payload $p -Actor "vicky" -Rol "vicky" -Amb "test" -Ts $now -IdemKey (K "sec-23")
Assert-Code "23. pagador caja con id_socio -> payload_invalido" (Probe $b) "payload_invalido"

# 24. override sin comentario (clase != clase_sugerida y sin comentario)
$p = @{ fecha = "2026-07-15"; clase = "A"; clase_sugerida = "C"; etiqueta = "override"; monto = 1000; pagador_tipo = "caja" }
$b = New-Env -Action $ACT -Payload $p -Actor "vicky" -Rol "vicky" -Amb "test" -Ts $now -IdemKey (K "sec-24")
Assert-Code "24. override sin comentario -> payload_invalido" (Probe $b) "payload_invalido"

# 25. horas de trabajo con caja (debe ser socio)
$p = @{ fecha = "2026-07-15"; clase = "A"; etiqueta = "horas de trabajo"; monto = 1000; pagador_tipo = "caja"; comentario = "x" }
$b = New-Env -Action $ACT -Payload $p -Actor "vicky" -Rol "vicky" -Amb "test" -Ts $now -IdemKey (K "sec-25")
Assert-Code "25. horas de trabajo + caja -> payload_invalido" (Probe $b) "payload_invalido"

# 26. periodo explicito dia != 1
$p = PA; $p['periodo'] = "2026-07-15"
$b = New-Env -Action $ACT -Payload $p -Actor "vicky" -Rol "vicky" -Amb "test" -Ts $now -IdemKey (K "sec-26")
Assert-Code "26. periodo dia!=1 -> payload_invalido" (Probe $b) "payload_invalido"

Write-Host ("Escrituras detectadas en SEGURIDAD: " + $script:secWrites + " (debe ser 0)") -ForegroundColor DarkGray
Record "META seguridad 0 escrituras" ($script:secWrites -eq 0) ("secWrites=" + $script:secWrites)

# ============================ FUNCIONAL (5 escrituras) ============================
Write-Host "`n----- FUNCIONAL (escribe 5 gastos) -----" -ForegroundColor Magenta

# F1-F4: altas felices por clase (4 escrituras)
$now = [long][DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$b = New-Env -Action $ACT -Payload (PA) -Actor "vicky" -Rol "vicky" -Amb "test" -Ts $now -IdemKey (K "fn-A")
$idA = Assert-OkNew "F1. alta clase A (caja) -> ok nuevo" (Probe $b)

$b = New-Env -Action $ACT -Payload (PC) -Actor "vicky" -Rol "vicky" -Amb "test" -Ts $now -IdemKey (K "fn-C")
$idC = Assert-OkNew "F2. alta clase C (caja) -> ok nuevo" (Probe $b)

$b = New-Env -Action $ACT -Payload (PD) -Actor "franco" -Rol "socio" -Amb "test" -Ts $now -IdemKey (K "fn-D")
$idD = Assert-OkNew "F3. alta clase D (zona, socio) -> ok nuevo" (Probe $b)

$b = New-Env -Action $ACT -Payload (PE) -Actor "remo" -Rol "socio" -Amb "test" -Ts $now -IdemKey (K "fn-E")
$idE = Assert-OkNew "F4. alta clase E (cabana, socio) -> ok nuevo" (Probe $b)

# F5: ciclo replay / retry / doble-click / conflictos sobre UNA key dedicada (1 escritura).
Write-Host "`n  -- ciclo idempotencia/anti-replay (key -rep) --" -ForegroundColor DarkGray
$keyRep = K "rep"
$tsRep  = [long][DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$bodyRep = New-Env -Action $ACT -Payload (PA "luz rep") -Actor "vicky" -Rol "vicky" -Amb "test" -Ts $tsRep -IdemKey $keyRep
$sigRep  = Get-Signature -Body $bodyRep -Key $Secret

# F5a. alta (unica escritura del ciclo)
$idRep = Assert-OkNew "F5a. alta key -rep -> ok nuevo" (Send-Probe -Body $bodyRep -Signature $sigRep)

# F5b. replay BYTE-IDENTICO (mismo body, misma firma) -> nonce_replay
$r = Send-Probe -Body $bodyRep -Signature $sigRep
Assert-CodeReason "F5b. replay mismo sobre -> conflicto/nonce_replay" $r "conflicto" "nonce_replay"

# F5c. retry: ts nuevo, MISMA key, mismo payload -> idempotente, mismo id
$ts2 = $tsRep + 1000
$b = New-Env -Action $ACT -Payload (PA "luz rep") -Actor "vicky" -Rol "vicky" -Amb "test" -Ts $ts2 -IdemKey $keyRep
Assert-OkIdemp "F5c. retry (ts nuevo, misma key) -> idempotente mismo id" (Probe $b) $idRep

# F5d. doble-click: otro ts nuevo, misma key -> idempotente
$ts3 = $tsRep + 2000
$b = New-Env -Action $ACT -Payload (PA "luz rep") -Actor "vicky" -Rol "vicky" -Amb "test" -Ts $ts3 -IdemKey $keyRep
Assert-OkIdemp "F5d. doble-click (otro ts) -> idempotente mismo id" (Probe $b) $idRep

# F5e. conflicto payload: misma key, MONTO distinto -> payload_mismatch
$ts4 = $tsRep + 3000
$pm = PA "luz rep"; $pm['monto'] = 9999
$b = New-Env -Action $ACT -Payload $pm -Actor "vicky" -Rol "vicky" -Amb "test" -Ts $ts4 -IdemKey $keyRep
Assert-CodeReason "F5e. misma key, payload distinto -> conflicto/payload_mismatch" (Probe $b) "conflicto" "payload_mismatch"

# F5f. conflicto actor: misma key, mismo payload, ACTOR distinto -> actor_mismatch
$ts5 = $tsRep + 4000
$b = New-Env -Action $ACT -Payload (PA "luz rep") -Actor "rodrigo" -Rol "socio" -Amb "test" -Ts $ts5 -IdemKey $keyRep
Assert-CodeReason "F5f. misma key, actor distinto -> conflicto/actor_mismatch" (Probe $b) "conflicto" "actor_mismatch"

# ============================ META ============================
Write-Host "`n----- META -----" -ForegroundColor Magenta
Assert-AllowlistMeta

# ============================ RESUMEN ============================
Write-Host ""
Write-Host "==================================================="
Write-Host ("RESULTADO: {0} PASS / {1} FAIL" -f $script:passed, $script:failed)
if ($script:failed -gt 0) {
  Write-Host "Fallos:"
  $script:failsList | ForEach-Object { Write-Host "  - $_" }
}
Write-Host ("Codigos de error vistos: " + ((@($script:codesSeen.Keys) | Sort-Object) -join ', '))
Write-Host ("ids escritos: A=" + $idA + " C=" + $idC + " D=" + $idD + " E=" + $idE + " rep=" + $idRep)
Write-Host ""
Write-Host "Esperado: 5 gastos nuevos (A,C,D,E,rep). El resto rebota o es idempotente." -ForegroundColor DarkGray
Write-Host ("Teardown: correr C_SLICE3B_A11_teardown.sql (borra 'smoke-a11-%'). RunID de esta corrida: " + $RUNID) -ForegroundColor DarkGray
