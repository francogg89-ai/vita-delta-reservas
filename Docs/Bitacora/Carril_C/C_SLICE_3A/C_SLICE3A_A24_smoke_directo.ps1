# ============================================================================
# C_SLICE3A_A24_smoke_directo.ps1
# Carril C / Portal Operativo Interno - Slice 3a, A24 (historico.reservas).
# Smoke DIRECTO al wrapper n8n "portal-a24-historico-reservas" (TEST), SIN gateway.
#
# Replica lo que hara portal-api: arma el sobre { action, payload, rol, ambiente_esperado,
# ts, nonce }, firma HMAC-SHA256 sobre los BYTES EXACTOS que envia, y POSTea al webhook.
# n8n recomputa el HMAC sobre el raw body recibido (D-C-29).
#
# ASCII PURO (PS 5.1 / CP1252). Sin -Parallel. Sin if inline en -ForegroundColor.
# Envio por HttpWebRequest con ContentLength explicito + TLS 1.2 (L-C-17b: Invoke-WebRequest
# -Body byte[] puede mandar cuerpo vacio en PS 5.1). Contadores con $script: (L-C-17d).
# Conteos de un solo objeto envueltos en @(...) (L-C-17c).
#
# NO toca OPS. NO escribe en Supabase. Solo POSTea al webhook de n8n TEST.
# El secreto NO se commitea: se pega abajo en $Secret y se borra antes de guardar al repo.
# Debe ser el MISMO valor pegado en el nodo validar_firma_ts_rol (Modo B, L-C-10).
#
# DATOS ESPERADOS EN TEST (de S5/S6 del snapshot, pueden variar):
#   - 7 reservas con fecha_checkin >= 2026-07-01 (las 6 de junio quedan bajo el floor).
#   - todas estado 'confirmada'. Cabana 5 (Tokio) con reservas de julio; cabana 3 (Arrebol) sin.
#   - el happy {} deberia devolver total = 7 (ajustar si los datos cambiaron).
# ============================================================================

[Net.ServicePointManager]::SecurityProtocol = `
  [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# ====== CONFIG (editar) ======
$BaseUrl = "https://federicosecchi.app.n8n.cloud"      # base de n8n Cloud (sin /webhook)
$Webhook = "portal-a24-historico-reservas"             # path del Webhook del wrapper
$Secret  = "SECRET_NO_COMMITEAR"       # == secreto del nodo; NO commitear
$FLOOR   = "2026-07-01"                                 # floor duro D-C-11/20
# =============================

$WebhookUrl = "$($BaseUrl.TrimEnd('/'))/webhook/$Webhook"
$ACT = "historico.reservas"                             # EXPECTED_ACTION del wrapper

$script:passed = 0
$script:failed = 0
$script:failsList = @()
$script:codesSeen = @{}

# Allowlist EXACTA del gateway (D-C-18). Codigos internos no pertenecen.
$script:ALLOWLIST = @('payload_invalido','no_autorizado','rol_no_permitido','accion_desconocida','no_encontrado','conflicto','error_entorno','error_interno','estado_incierto','firma_invalida','ts_fuera_de_ventana','raw_body_ausente','ambiente_incorrecto')

function New-Body {
  param([string]$Action, [hashtable]$Payload, [string]$Rol, [string]$AmbienteEsperado, [long]$Ts, [string]$Nonce)
  $obj = [ordered]@{
    action = $Action
    payload = $Payload
    rol = $Rol
    ambiente_esperado = $AmbienteEsperado
    ts = $Ts
    nonce = $Nonce
  }
  return ($obj | ConvertTo-Json -Compress -Depth 8)
}

# Igual que New-Body pero acepta payload de cualquier tipo (string/array/etc) para P6.
function New-BodyRaw {
  param([string]$Action, [object]$Payload, [string]$Rol, [string]$AmbienteEsperado, [long]$Ts, [string]$Nonce)
  $obj = [ordered]@{
    action = $Action
    payload = $Payload
    rol = $Rol
    ambiente_esperado = $AmbienteEsperado
    ts = $Ts
    nonce = $Nonce
  }
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

# POST por HttpWebRequest con ContentLength explicito (L-C-17b). Devuelve { code, json, raw }.
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

function Track-Code {
  param($resp)
  if ($resp.json -and ($resp.json.ok -eq $false) -and $resp.json.error) {
    $script:codesSeen[$resp.json.error.code] = $true
  }
}

function Record {
  param([string]$name, [bool]$ok, [string]$detail)
  if ($ok) {
    $script:passed++
    Write-Host "PASS  $name" -ForegroundColor Green
  } else {
    $script:failed++
    $script:failsList += "$name :: $detail"
    Write-Host "FAIL  $name  ($detail)" -ForegroundColor Red
  }
}

# Espera ok:true + data; opcional scriptblock de validacion extra sobre $data.
function Assert-OkData {
  param([string]$name, $resp, [scriptblock]$Check = $null)
  Track-Code $resp
  $ok = ($resp.json -and ($resp.json.ok -eq $true) -and ($null -ne $resp.json.data))
  if ($ok -and $Check) { $ok = [bool](& $Check $resp.json.data) }
  $code = ''
  if ($resp.json -and $resp.json.error) { $code = $resp.json.error.code }
  Record $name $ok "HTTP $($resp.code); ok=$($resp.json.ok) code=$code"
}

# Espera ok:false + error.code == $expected.
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

# ---- helpers de assert sobre filas ----
function Filas { param($d); if ($d -and $d.filas) { return @($d.filas) } ; return @() }

if ($Secret.StartsWith("__PEGAR_")) {
  Write-Host "Falta pegar el secreto en `$Secret (igual al del nodo validar_firma_ts_rol)." -ForegroundColor Red
  return
}

Write-Host "Wrapper: $WebhookUrl" -ForegroundColor Magenta
Write-Host "Floor: $FLOOR" -ForegroundColor DarkGray
$now = [long][DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
function NG { return [guid]::NewGuid().ToString() }

# ============================ SEGURIDAD (8) ============================
Write-Host "`n----- SEGURIDAD -----" -ForegroundColor Magenta

# 1. vicky OK (payload vacio) -> ok:true, filas presente
$b = New-Body -Action $ACT -Payload @{} -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-OkData "1. vicky OK (sin filtros)" $r { param($d) $null -ne $d.filas }

# 2. socio OK
$b = New-Body -Action $ACT -Payload @{} -Rol "socio" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-OkData "2. socio OK (sin filtros)" $r { param($d) $null -ne $d.filas }

# 3. jenny (rol valido, NO habilitado A24) -> rol_no_permitido
$b = New-Body -Action $ACT -Payload @{} -Rol "jenny" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-Code "3. jenny -> rol_no_permitido" $r "rol_no_permitido"

# 4. intruso (rol basura) -> rol_no_permitido
$b = New-Body -Action $ACT -Payload @{} -Rol "intruso" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-Code "4. intruso -> rol_no_permitido" $r "rol_no_permitido"

# 5. firma invalida (firmado con secreto equivocado) -> firma_invalida
$b = New-Body -Action $ACT -Payload @{} -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key "SECRETO_EQUIVOCADO")
Assert-Code "5. firma invalida -> firma_invalida" $r "firma_invalida"

# 6. ts viejo (-10 min) -> ts_fuera_de_ventana
$b = New-Body -Action $ACT -Payload @{} -Rol "vicky" -AmbienteEsperado "test" -Ts ($now - 600000) -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-Code "6. ts viejo -> ts_fuera_de_ventana" $r "ts_fuera_de_ventana"

# 7. ambiente cruzado (esperado ops contra wrapper TEST) -> ambiente_incorrecto
$b = New-Body -Action $ACT -Payload @{} -Rol "vicky" -AmbienteEsperado "ops" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-Code "7. ambiente cruzado -> ambiente_incorrecto" $r "ambiente_incorrecto"

# 8. action incorrecta (sobre bien firmado, action ajena) -> accion_desconocida
$b = New-Body -Action "cobranza.saldos" -Payload @{} -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-Code "8. action incorrecta -> accion_desconocida" $r "accion_desconocida"

# ============================ FUNCIONALES (filtros/paginacion/floor) ============================
Write-Host "`n----- FUNCIONALES -----" -ForegroundColor Magenta

# F1. happy sin filtros -> filas array (esperado 7 segun datos; assert: filas presente + total numerico)
$b = New-Body -Action $ACT -Payload @{} -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$rF1 = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-OkData "F1. sin filtros (filas + total)" $rF1 {
  param($d) ($null -ne $d.filas) -and ($null -ne $d.total) -and ($d.limit -eq 50) -and ($d.offset -eq 0)
}
if ($rF1.json -and $rF1.json.ok) { Write-Host ("    total=" + $rF1.json.data.total + " filas=" + @(Filas $rF1.json.data).Count) -ForegroundColor DarkGray }

# F2. fecha_desde dentro de rango -> todas fecha_checkin >= fecha_desde
$desde = "2026-07-10"
$b = New-Body -Action $ACT -Payload @{ fecha_desde = $desde } -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-OkData "F2. fecha_desde=$desde (todas >= desde)" $r {
  param($d) @(Filas $d | Where-Object { $_.fecha_checkin -lt $desde }).Count -eq 0
}

# F3. fecha_desde < floor -> RECORTE a floor; NINGUNA fila < floor (regresion de floor)
$b = New-Body -Action $ACT -Payload @{ fecha_desde = "2026-06-01" } -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-OkData "F3. fecha_desde<floor recortado (0 filas < $FLOOR)" $r {
  param($d) @(Filas $d | Where-Object { $_.fecha_checkin -lt $FLOOR }).Count -eq 0
}

# F4. id_cabana=5 (Tokio) -> todas id_cabana == 5
$b = New-Body -Action $ACT -Payload @{ id_cabana = [int]5 } -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-OkData "F4. id_cabana=5 (todas cabana 5)" $r {
  param($d) (@(Filas $d).Count -ge 0) -and (@(Filas $d | Where-Object { $_.id_cabana -ne 5 }).Count -eq 0)
}

# F5. id_cabana=3 (Arrebol, sin reservas) -> filas vacia, ok:true (D-C-47)
$b = New-Body -Action $ACT -Payload @{ id_cabana = [int]3 } -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-OkData "F5. id_cabana=3 sin reservas -> filas:[]" $r {
  param($d) @(Filas $d).Count -eq 0
}

# F6. estado=confirmada -> todas confirmada
$b = New-Body -Action $ACT -Payload @{ estado = "confirmada" } -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-OkData "F6. estado=confirmada (todas confirmada)" $r {
  param($d) @(Filas $d | Where-Object { $_.estado -ne 'confirmada' }).Count -eq 0
}

# F7. estado=completada -> filas vacia, ok:true (no hay completadas en datos)
$b = New-Body -Action $ACT -Payload @{ estado = "completada" } -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-OkData "F7. estado=completada -> filas:[]" $r {
  param($d) @(Filas $d).Count -eq 0
}

# F8. texto que no matchea -> filas vacia, ok:true (caso POSITIVO requiere un substring real; ver runsheet)
$b = New-Body -Action $ACT -Payload @{ texto = "zzz_no_existe_qwerty" } -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-OkData "F8. texto sin match -> filas:[]" $r {
  param($d) @(Filas $d).Count -eq 0
}

# F9. limit=2 offset=0 -> filas <= 2; total = universo
$b = New-Body -Action $ACT -Payload @{ limit = [int]2; offset = [int]0 } -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$rF9 = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-OkData "F9. limit=2 offset=0 (<=2 filas, total presente)" $rF9 {
  param($d) (@(Filas $d).Count -le 2) -and ($d.limit -eq 2) -and ($d.offset -eq 0) -and ($null -ne $d.total)
}

# F10. limit=2 offset=2 -> pagina distinta (ids != los de F9)
$b = New-Body -Action $ACT -Payload @{ limit = [int]2; offset = [int]2 } -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$rF10 = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-OkData "F10. limit=2 offset=2 (pagina distinta de F9)" $rF10 {
  param($d)
  $idsF9  = @(Filas $rF9.json.data  | ForEach-Object { $_.id_reserva })
  $idsF10 = @(Filas $d | ForEach-Object { $_.id_reserva })
  $solapan = @($idsF10 | Where-Object { $idsF9 -contains $_ }).Count
  ($d.offset -eq 2) -and ($solapan -eq 0 -or @($idsF10).Count -eq 0)
}

# ============================ PAYLOAD INVALIDO ============================
Write-Host "`n----- PAYLOAD INVALIDO -----" -ForegroundColor Magenta

# P1. clave no permitida
$b = New-Body -Action $ACT -Payload @{ foo = 1 } -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-Code "P1. clave no permitida -> payload_invalido" $r "payload_invalido"

# P2. fecha mal formada
$b = New-Body -Action $ACT -Payload @{ fecha_desde = "2026-13-01" } -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-Code "P2. fecha mal formada -> payload_invalido" $r "payload_invalido"

# P3. estado fuera del enum
$b = New-Body -Action $ACT -Payload @{ estado = "xxx" } -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-Code "P3. estado fuera de enum -> payload_invalido" $r "payload_invalido"

# P4. id_cabana no entero (decimal)
$b = New-Body -Action $ACT -Payload @{ id_cabana = 1.5 } -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-Code "P4. id_cabana decimal -> payload_invalido" $r "payload_invalido"

# P5. fecha_hasta < fecha_desde
$b = New-Body -Action $ACT -Payload @{ fecha_desde = "2026-08-01"; fecha_hasta = "2026-07-15" } -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-Code "P5. fecha_hasta < fecha_desde -> payload_invalido" $r "payload_invalido"

# P6a. payload string (no objeto plano) -> payload_invalido (no se coerciona a {})
$b = New-BodyRaw -Action $ACT -Payload "soy_un_string" -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-Code "P6a. payload string -> payload_invalido" $r "payload_invalido"

# P6b. payload array (no objeto plano) -> payload_invalido
$b = New-BodyRaw -Action $ACT -Payload @(1, 2, 3) -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-Code "P6b. payload array -> payload_invalido" $r "payload_invalido"

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
Write-Host ""
Write-Host "Recorda: en happy/filtros, filas=0 puede ser PASS (lista vacia valida, D-C-47)." -ForegroundColor DarkGray
Write-Host "Para un caso POSITIVO de texto, edita F8 con un substring real de un huesped en TEST." -ForegroundColor DarkGray
