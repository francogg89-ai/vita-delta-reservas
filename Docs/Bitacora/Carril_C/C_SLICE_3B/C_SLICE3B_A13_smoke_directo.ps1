# ============================================================================
# C_SLICE3B_A13_smoke_directo.ps1
# Carril C / Portal Operativo Interno - Slice 3b, A13 (gastos.listado), LECTURA.
# Smoke DIRECTO al wrapper n8n "portal-a13-gastos-listado" (TEST), SIN gateway.
#
# Arma el sobre { action, payload, rol, ambiente_esperado, ts, nonce }, firma HMAC-SHA256
# sobre los BYTES EXACTOS que envia, y POSTea al webhook. n8n recomputa el HMAC (D-C-29).
#
# ASCII PURO (PS 5.1 / CP1252). Sin -Parallel. HttpWebRequest con ContentLength + TLS 1.2.
# Contadores $script: (L-C-17d). El secreto NO se commitea: se pega en $Secret (Modo B,
# L-C-10) y se borra antes de guardar. Debe ser el MISMO valor del nodo validar_firma_ts_rol.
#
# LECTURA: NO escribe -> SIN teardown y SIN gate de write-residual. Nada que limpiar.
#
# CUADRE: este smoke valida invariantes ESTRUCTURALES (independientes de los datos):
#   - particion por clase:   sum(total_gastos|clase=A,C,D,E) == total_gastos(full)
#   - particion por pagador: sum(total_gastos|pagador=socio,caja) == total_gastos(full)
#   - cuadre interno:        sum(por_clase.monto) == total_gastos == sum(filas.monto)  (limit>=universo)
#   - paginacion no altera los agregados; default {} -> vacio (floor futuro); vicky==socio.
# El cruce AL CENTAVO contra el ground-truth se hace contra C_SLICE3B_A13_smoke_expected.sql
# (E2/E3). Opcional: pega los numeros de E1/E2 en $EXP_NFILAS / $EXP_TOTAL para asserts duros.
#
# DATOS: hoy (junio 2026) < floor (2026-07-01) -> el default {} devuelve VACIO con ok:true.
# Para ver datos el smoke usa periodo_hasta=$HASTA (amplio, incluye fixture julio + sinteticos 2099).
# ============================================================================

[Net.ServicePointManager]::SecurityProtocol = `
  [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# ====== CONFIG (editar) ======
$BaseUrl = "https://federicosecchi.app.n8n.cloud"
$Webhook = "portal-a13-gastos-listado"
$Secret  = "SECRETO_NO_SUBIR"
$FLOOR   = "2026-07-01"
$HASTA   = "2099-12-01"   # cota amplia para traer datos (fixture julio + sinteticos 2099)
# --- opcional: ground-truth de C_SLICE3B_A13_smoke_expected.sql para asserts duros ---
$EXP_NFILAS = $null       # E1 (n_filas)        -> si no es $null, assert dura
$EXP_TOTAL  = $null       # E2 (total_gastos)   -> si no es $null, assert dura
# =============================

$WebhookUrl = "$($BaseUrl.TrimEnd('/'))/webhook/$Webhook"
$ACT = "gastos.listado"

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
# Acepta payload de cualquier tipo (string/array) para los casos de payload no-objeto.
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

# ---- helpers ----
function SumMonto { param($arr); if (-not $arr) { return [double]0 } ; return [double]((@($arr) | Measure-Object -Property monto -Sum).Sum) }
function Eq2 { param($a, $b); if ($null -eq $a -or $null -eq $b) { return $false } ; return ([math]::Abs([double]$a - [double]$b) -lt 0.01) }
function Filas { param($d); if ($d -and $d.filas) { return @($d.filas) } ; return @() }

# Total de gastos de una consulta (con $HASTA y limit 200), o $null si error.
function Get-Total {
  param([hashtable]$Payload)
  $b = New-Body -Action $ACT -Payload $Payload -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
  $r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
  Track-Code $r
  if ($r.json -and ($r.json.ok -eq $true) -and ($null -ne $r.json.data)) { return [double]$r.json.data.total_gastos }
  return $null
}

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
Assert-OkData "1. vicky OK (default {})" $r { param($d) $null -ne $d.total_gastos }

# 2. socio OK
$b = New-Body -Action $ACT -Payload @{} -Rol "socio" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-OkData "2. socio OK (default {})" $r { param($d) $null -ne $d.total_gastos }

# 3. jenny -> rol_no_permitido (D-C-03: contenido economico)
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
$b = New-Body -Action "ingresos.cobrados_periodo" -Payload @{} -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-Code "8. action incorrecta -> accion_desconocida" $r "accion_desconocida"

# ============================ FUNCIONALES ============================
Write-Host "`n----- FUNCIONALES -----" -ForegroundColor Magenta

# Universo de la ventana (limit 200 para traer todas las filas y poder cuadrar).
$b = New-Body -Action $ACT -Payload @{ periodo_hasta = $HASTA; limit = [int]200 } -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$rFull = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
$nFull = $null; $totFull = $null
if ($rFull.json -and $rFull.json.ok) {
  $d = $rFull.json.data
  $nFull = @(Filas $d).Count
  $totFull = [double]$d.total_gastos
  Write-Host ("    total_gastos=" + $d.total_gastos + " filas=" + $nFull + " por_clase=" + (@($d.por_clase | ForEach-Object { $_.clase + ':' + $_.monto + '(' + $_.n + ')' }) -join ' ')) -ForegroundColor DarkGray
  if ($nFull -ge 200) { Write-Host "    AVISO: universo >= 200; subir limit/ajustar ventana para cuadre completo." -ForegroundColor Yellow }
}

# G0a/G0b. Asserts duros opcionales contra el ground-truth (si se pegaron E1/E2).
if ($null -ne $EXP_TOTAL) {
  Assert-OkData "G0a. total_gastos == EXP_TOTAL ($EXP_TOTAL)" $rFull { param($d) Eq2 $d.total_gastos $EXP_TOTAL }
}
if ($null -ne $EXP_NFILAS) {
  Assert-OkData "G0b. n_filas == EXP_NFILAS ($EXP_NFILAS)" $rFull { param($d) (@(Filas $d).Count) -eq [int]$EXP_NFILAS }
}

# G1. cuadre interno: sum(por_clase.monto) == total_gastos == sum(filas.monto) [universo en pagina]
Assert-OkData "G1. cuadre por_clase == total_gastos == filas" $rFull {
  param($d)
  (Eq2 (SumMonto $d.por_clase) $d.total_gastos) -and
  ((@(Filas $d).Count) -ge 200 -or (Eq2 (SumMonto $d.filas) $d.total_gastos))
}

# G2. por_clase: solo clases validas {A,C,D,E} y sum(n) == filas (si universo en pagina)
Assert-OkData "G2. por_clase clases en {A,C,D,E} y n cuadra" $rFull {
  param($d)
  $fueraEnum = @($d.por_clase | Where-Object { @('A','C','D','E') -notcontains $_.clase }).Count
  $sumN = [int]((@($d.por_clase) | Measure-Object -Property n -Sum).Sum)
  ($fueraEnum -eq 0) -and ((@(Filas $d).Count) -ge 200 -or ($sumN -eq @(Filas $d).Count))
}

# G3. default {} (hoy<floor) -> total_gastos=0, por_clase=[], filas=[], ok:true
$b = New-Body -Action $ACT -Payload @{} -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-OkData "G3. default vacio (total=0, por_clase vacio, filas=[])" $r {
  param($d) (Eq2 $d.total_gastos 0) -and ((SumMonto $d.por_clase) -eq 0) -and (@(Filas $d).Count -eq 0)
}

# G4. periodo_desde<floor recortado (clamp) -> mismo total que el floored (junio no agrega)
$b = New-Body -Action $ACT -Payload @{ periodo_desde = "2026-06-01"; periodo_hasta = $HASTA; limit = [int]200 } -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-OkData "G4. periodo_desde<floor recortado (== universo)" $r { param($d) Eq2 $d.total_gastos $totFull }

# G5. PARTICION por clase: sum(A,C,D,E) == total(full)  [independiente de los datos]
$tA = Get-Total @{ periodo_hasta = $HASTA; clase = "A"; limit = [int]200 }
$tC = Get-Total @{ periodo_hasta = $HASTA; clase = "C"; limit = [int]200 }
$tD = Get-Total @{ periodo_hasta = $HASTA; clase = "D"; limit = [int]200 }
$tE = Get-Total @{ periodo_hasta = $HASTA; clase = "E"; limit = [int]200 }
$okPart = ($null -ne $tA) -and ($null -ne $tC) -and ($null -ne $tD) -and ($null -ne $tE) -and ($null -ne $totFull) -and (Eq2 ($tA + $tC + $tD + $tE) $totFull)
Record "G5. particion por clase A+C+D+E == universo" $okPart ("A=$tA C=$tC D=$tD E=$tE suma=$($tA+$tC+$tD+$tE) full=$totFull")

# G6. PARTICION por pagador: sum(socio,caja) == total(full)
$tSoc = Get-Total @{ periodo_hasta = $HASTA; pagador_tipo = "socio"; limit = [int]200 }
$tCaj = Get-Total @{ periodo_hasta = $HASTA; pagador_tipo = "caja"; limit = [int]200 }
$okPag = ($null -ne $tSoc) -and ($null -ne $tCaj) -and ($null -ne $totFull) -and (Eq2 ($tSoc + $tCaj) $totFull)
Record "G6. particion por pagador socio+caja == universo" $okPag ("socio=$tSoc caja=$tCaj suma=$($tSoc+$tCaj) full=$totFull")

# G7. monotonia: total(clase=A) <= total(full)
$okMono = ($null -ne $tA) -and ($null -ne $totFull) -and ([double]$tA -le [double]$totFull + 0.01)
Record "G7. monotonia clase=A <= universo" $okMono ("A=$tA full=$totFull")

# G8. q sin match -> vacio (total=0, filas=[])
$b = New-Body -Action $ACT -Payload @{ periodo_hasta = $HASTA; q = "zzz_nomatch_vd_zzz"; limit = [int]200 } -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-OkData "G8. q sin match -> vacio (total=0, filas=[])" $r { param($d) (Eq2 $d.total_gastos 0) -and (@(Filas $d).Count -eq 0) }

# G9. paginacion limit=1 -> <=1 fila; total_gastos NO cambia (agregado del universo); limit=1
$b = New-Body -Action $ACT -Payload @{ periodo_hasta = $HASTA; limit = [int]1; offset = [int]0 } -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$rG9 = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-OkData "G9. limit=1 (<=1 fila, total==universo, limit=1)" $rG9 {
  param($d) (@(Filas $d).Count -le 1) -and (Eq2 $d.total_gastos $totFull) -and ($d.limit -eq 1)
}

# G10. paginacion offset -> pagina distinta (sin solape de id_gasto)
$b = New-Body -Action $ACT -Payload @{ periodo_hasta = $HASTA; limit = [int]2; offset = [int]2 } -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$rG10 = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-OkData "G10. limit=2 offset=2 (pagina distinta)" $rG10 {
  param($d)
  $idsA = @(Filas $rG9.json.data | ForEach-Object { $_.id_gasto })
  $idsB = @(Filas $d | ForEach-Object { $_.id_gasto })
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

# P3. inversion EXPLICITA (nivel mes): desde=2026-08-15, hasta=2026-07-20 -> 08 > 07
$b = New-Body -Action $ACT -Payload @{ periodo_desde = "2026-08-15"; periodo_hasta = "2026-07-20" } -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-Code "P3. inversion explicita (nivel mes) -> payload_invalido" $r "payload_invalido"

# P4. periodo_hasta mal formado
$b = New-Body -Action $ACT -Payload @{ periodo_hasta = "2026-02-31" } -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-Code "P4. periodo_hasta mal formado -> payload_invalido" $r "payload_invalido"

# P5. limit no entero
$b = New-Body -Action $ACT -Payload @{ limit = "x" } -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-Code "P5. limit no entero -> payload_invalido" $r "payload_invalido"

# P6. clase invalida
$b = New-Body -Action $ACT -Payload @{ clase = "Z" } -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-Code "P6. clase invalida -> payload_invalido" $r "payload_invalido"

# P7. pagador_tipo invalido
$b = New-Body -Action $ACT -Payload @{ pagador_tipo = "foo" } -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-Code "P7. pagador_tipo invalido -> payload_invalido" $r "payload_invalido"

# P8. id_zona <= 0
$b = New-Body -Action $ACT -Payload @{ id_zona = [int]0 } -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-Code "P8. id_zona=0 -> payload_invalido" $r "payload_invalido"

# P8b. id_cabana no entero
$b = New-Body -Action $ACT -Payload @{ id_cabana = "x" } -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-Code "P8b. id_cabana no entero -> payload_invalido" $r "payload_invalido"

# P9. q vacio (trim -> vacio)
$b = New-Body -Action $ACT -Payload @{ q = "   " } -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-Code "P9. q vacio -> payload_invalido" $r "payload_invalido"

# P10. q oversized (>120)
$bigQ = ("a" * 121)
$b = New-Body -Action $ACT -Payload @{ q = $bigQ } -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-Code "P10. q oversized (>120) -> payload_invalido" $r "payload_invalido"

# P11a. payload string -> payload_invalido (no se coerciona a {})
$b = New-BodyRaw -Action $ACT -Payload "soy_un_string" -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-Code "P11a. payload string -> payload_invalido" $r "payload_invalido"

# P11b. payload array -> payload_invalido
$b = New-BodyRaw -Action $ACT -Payload @(1, 2, 3) -Rol "vicky" -AmbienteEsperado "test" -Ts $now -Nonce (NG)
$r = Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Secret)
Assert-Code "P11b. payload array -> payload_invalido" $r "payload_invalido"

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
Write-Host "Recorda: el default {} hoy da total_gastos=0 (floor en el futuro) y es PASS." -ForegroundColor DarkGray
Write-Host "Cruce al centavo: compara total_gastos/por_clase del universo contra E2/E3 de C_SLICE3B_A13_smoke_expected.sql." -ForegroundColor DarkGray
