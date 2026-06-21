# ============================================================================
# C_SLICE3A_A25_smoke_directo.ps1
# Carril C / Portal Operativo Interno - Slice 3a, A25 (ingresos.cobrados_periodo).
# Smoke DIRECTO al wrapper n8n "portal-a25-ingresos" (TEST), SIN gateway.
#
# Arma el sobre { action, payload, rol, ambiente_esperado, ts, nonce }, firma HMAC-SHA256
# sobre los BYTES EXACTOS que envia, y POSTea al webhook. n8n recomputa el HMAC (D-C-29).
#
# ASCII PURO (PS 5.1 / CP1252). Sin -Parallel. Sin if inline en -ForegroundColor.
# HttpWebRequest con ContentLength + TLS 1.2 (L-C-17b). Contadores $script: (L-C-17d).
#
# DATOS ESPERADOS EN TEST (S8/S9 del snapshot, periodo floored [2026-07-01, 2026-12-31]):
#   total_cobrado (sena+saldo) = 921200 ; julio 670200 ; noviembre 251000 ; 4 pagos.
#   por_medio: efectivo 300200, transferencia_bancaria 621000.
#   otros_movimientos: extra 8500 (julio), SEPARADO e informativo (no sumado).
#   Hoy (2026-06-20) < floor (2026-07-01): el default {} devuelve VACIO con ok:true.
#
# NO toca OPS. NO escribe. El secreto NO se commitea: se pega en $Secret y se borra antes
# de guardar. Debe ser el MISMO valor del nodo validar_firma_ts_rol (Modo B, L-C-10).
# ============================================================================

[Net.ServicePointManager]::SecurityProtocol = `
  [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# ====== CONFIG (editar) ======
$BaseUrl = "https://federicosecchi.app.n8n.cloud"
$Webhook = "portal-a25-ingresos"
$Secret  = "SECRETO_NO_COMMIT"
$FLOOR   = "2026-07-01"
$HASTA   = "2026-12-31"   # cota explicita para los casos con datos
# =============================

$WebhookUrl = "$($BaseUrl.TrimEnd('/'))/webhook/$Webhook"
$ACT = "ingresos.cobrados_periodo"

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
# Acepta payload de cualquier tipo (string/array) para P6.
function New-BodyRaw {
  param([string]$Action, [object]$Payload, [string]$Rol, [string]$AmbienteEsperado, [long]$Ts, [string]$Nonce)
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

# ---- helpers de montos ----
function SumMonto { param($arr); if (-not $arr) { return [double]0 } ; return [double]((@($arr) | Measure-Object -Property monto -Sum).Sum) }
function FindMonto { param($arr, $keyName, $keyVal); $e = @($arr | Where-Object { $_.$keyName -eq $keyVal }); if ($e.Count -eq 0) { return $null } ; return $e[0].monto }
function Eq2 { param($a, $b); if ($null -eq $a -or $null -eq $b) { return $false } ; return ([math]::Abs([double]$a - [double]$b) -lt 0.01) }
function Filas { param($d); if ($d -and $d.filas) { return @($d.filas) } ; return @() }

if ($Secret.StartsWith("__PEGAR_")) {
  Write-Host "Falta pegar el secreto en `$Secret (igual al del nodo validar_firma_ts_rol)." -ForegroundColor Red
  return
}

Write-Host "Wrapper: $WebhookUrl" -ForegroundColor Magenta
Write-Host "Floor: $FLOOR | Cota con datos: $HASTA" -ForegroundColor DarkGray
$now = [long][DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
function NG { return [guid]::NewGuid().ToString() }

# ============================ SEGURIDAD (8) ============================
Write-Host "`n----- SEGURIDAD -----" -ForegroundColor Magenta

# 1. vicky OK (default {}; hoy<floor -> vacio OK)
$b = New-Body -Action $ACT -Payload @{} -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-OkData "1. vicky OK (default {})" $r { param($d) $null -ne $d.total_cobrado }

# 2. socio OK
$b = New-Body -Action $ACT -Payload @{} -Rol "socio" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-OkData "2. socio OK (default {})" $r { param($d) $null -ne $d.total_cobrado }

# 3. jenny -> rol_no_permitido
$b = New-Body -Action $ACT -Payload @{} -Rol "jenny" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-Code "3. jenny -> rol_no_permitido" $r "rol_no_permitido"

# 4. intruso -> rol_no_permitido
$b = New-Body -Action $ACT -Payload @{} -Rol "intruso" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-Code "4. intruso -> rol_no_permitido" $r "rol_no_permitido"

# 5. firma invalida -> firma_invalida
$b = New-Body -Action $ACT -Payload @{} -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key "SECRETO_EQUIVOCADO")
Assert-Code "5. firma invalida -> firma_invalida" $r "firma_invalida"

# 6. ts viejo -> ts_fuera_de_ventana
$b = New-Body -Action $ACT -Payload @{} -Rol "vicky" -AmbienteEsperado "test" -Ts ($now - 600000) -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-Code "6. ts viejo -> ts_fuera_de_ventana" $r "ts_fuera_de_ventana"

# 7. ambiente cruzado -> ambiente_incorrecto
$b = New-Body -Action $ACT -Payload @{} -Rol "vicky" -AmbienteEsperado "ops" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-Code "7. ambiente cruzado -> ambiente_incorrecto" $r "ambiente_incorrecto"

# 8. action incorrecta -> accion_desconocida
$b = New-Body -Action "cobranza.saldos" -Payload @{} -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-Code "8. action incorrecta -> accion_desconocida" $r "accion_desconocida"

# ============================ FUNCIONALES ============================
Write-Host "`n----- FUNCIONALES -----" -ForegroundColor Magenta

# Periodo con datos (limit 200 para traer todas las filas y poder cuadrar).
$b = New-Body -Action $ACT -Payload @{ periodo_hasta = $HASTA; limit = [int]200 } -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$rFull = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
if ($rFull.json -and $rFull.json.ok) {
  $d = $rFull.json.data
  Write-Host ("    total_cobrado=" + $d.total_cobrado + " total=" + $d.total + " filas=" + @(Filas $d).Count) -ForegroundColor DarkGray
}

# G1. total_cobrado headline (solo sena+saldo) = 921200; total = 4 pagos
Assert-OkData "G1. total_cobrado=921200, total=4" $rFull { param($d) (Eq2 $d.total_cobrado 921200) -and ($d.total -eq 4) }

# G2. cuadre: Sum(por_medio)=Sum(por_tipo)=Sum(filas)=total_cobrado
Assert-OkData "G2. cuadre por_medio=por_tipo=filas=total_cobrado" $rFull {
  param($d)
  (Eq2 (SumMonto $d.por_medio) $d.total_cobrado) -and
  (Eq2 (SumMonto $d.por_tipo) $d.total_cobrado) -and
  (Eq2 (SumMonto $d.filas) $d.total_cobrado)
}

# G3. por_mes: julio 670200, noviembre 251000
Assert-OkData "G3. por_mes julio=670200, nov=251000" $rFull {
  param($d) (Eq2 (FindMonto $d.por_mes 'mes' '2026-07') 670200) -and (Eq2 (FindMonto $d.por_mes 'mes' '2026-11') 251000)
}

# G4. por_medio: efectivo 300200, transferencia_bancaria 621000
Assert-OkData "G4. por_medio efectivo=300200, transf=621000" $rFull {
  param($d) (Eq2 (FindMonto $d.por_medio 'medio_pago' 'efectivo') 300200) -and (Eq2 (FindMonto $d.por_medio 'medio_pago' 'transferencia_bancaria') 621000)
}

# G5. otros_movimientos informativo: extra=8500 y NO sumado al headline
Assert-OkData "G5. otros extra=8500 NO sumado (total sigue 921200)" $rFull {
  param($d) (Eq2 (FindMonto $d.otros_movimientos.por_tipo 'tipo' 'extra') 8500) -and (Eq2 $d.total_cobrado 921200)
}

# G8. headline SOLO sena+saldo: por_tipo no contiene extra/ajuste/reembolso
Assert-OkData "G8. por_tipo solo sena/saldo" $rFull {
  param($d) @($d.por_tipo | Where-Object { @('sena','saldo') -notcontains $_.tipo }).Count -eq 0
}

# G6. periodo vacio (default {}): hoy<floor -> total_cobrado=0, filas:[], ok:true
$b = New-Body -Action $ACT -Payload @{} -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-OkData "G6. default vacio (total_cobrado=0, filas:[])" $r { param($d) (Eq2 $d.total_cobrado 0) -and (@(Filas $d).Count -eq 0) }

# G7. periodo_desde<floor recortado -> mismo total que el floored (June/May excluidos)
$b = New-Body -Action $ACT -Payload @{ periodo_desde = "2026-06-01"; periodo_hasta = $HASTA; limit = [int]200 } -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-OkData "G7. periodo_desde<floor recortado (total=921200)" $r { param($d) Eq2 $d.total_cobrado 921200 }

# G9. paginacion limit=1 -> 1 fila; total=4 (universo de pagos sena+saldo)
$b = New-Body -Action $ACT -Payload @{ periodo_hasta = $HASTA; limit = [int]1; offset = [int]0 } -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$rG9 = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-OkData "G9. limit=1 (1 fila, total=4)" $rG9 { param($d) (@(Filas $d).Count -le 1) -and ($d.total -eq 4) -and ($d.limit -eq 1) }

# G10. paginacion offset -> pagina distinta
$b = New-Body -Action $ACT -Payload @{ periodo_hasta = $HASTA; limit = [int]2; offset = [int]2 } -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$rG10 = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-OkData "G10. limit=2 offset=2 (pagina distinta)" $rG10 {
  param($d)
  $idsA = @(Filas $rG9.json.data | ForEach-Object { $_.id_pago })
  $idsB = @(Filas $d | ForEach-Object { $_.id_pago })
  $solapan = @($idsB | Where-Object { $idsA -contains $_ }).Count
  ($d.offset -eq 2) -and ($solapan -eq 0 -or @($idsB).Count -eq 0)
}

# ============================ PAYLOAD INVALIDO ============================
Write-Host "`n----- PAYLOAD INVALIDO -----" -ForegroundColor Magenta

# P1. clave no permitida
$b = New-Body -Action $ACT -Payload @{ foo = 1 } -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-Code "P1. clave no permitida -> payload_invalido" $r "payload_invalido"

# P2. periodo_desde mal formado
$b = New-Body -Action $ACT -Payload @{ periodo_desde = "2026-13-01" } -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-Code "P2. periodo_desde mal formado -> payload_invalido" $r "payload_invalido"

# P3. inversion EXPLICITA (tras clamp): periodo_desde=2026-08-01, periodo_hasta=2026-07-01
$b = New-Body -Action $ACT -Payload @{ periodo_desde = "2026-08-01"; periodo_hasta = "2026-07-01" } -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-Code "P3. inversion explicita -> payload_invalido" $r "payload_invalido"

# P4. periodo_hasta mal formado
$b = New-Body -Action $ACT -Payload @{ periodo_hasta = "2026-02-31" } -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-Code "P4. periodo_hasta mal formado -> payload_invalido" $r "payload_invalido"

# P5. limit no entero
$b = New-Body -Action $ACT -Payload @{ limit = "x" } -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-Code "P5. limit no entero -> payload_invalido" $r "payload_invalido"

# P6a. payload string -> payload_invalido (no se coerciona a {})
$b = New-BodyRaw -Action $ACT -Payload "soy_un_string" -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-Code "P6a. payload string -> payload_invalido" $r "payload_invalido"

# P6b. payload array -> payload_invalido
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
Write-Host "Recorda: el default {} hoy da total_cobrado=0 (floor en el futuro) y es PASS." -ForegroundColor DarkGray
