# ============================================================================
# CC_L3_A30_historico_smoke_directo.ps1
# Frente Cuenta corriente de socios / L3 - A30 (cuenta_corriente.historico).
# Smoke DIRECTO al wrapper n8n "portal-a30-cuenta-corriente-historico__TEST", SIN gateway.
#
# Arma el sobre { action, payload:{mes}, rol, ambiente_esperado, ts, nonce }, firma HMAC-SHA256
# sobre los BYTES EXACTOS y POSTea. n8n recomputa el HMAC (D-C-29) y revalida el payload {mes}
# (2da defensa: YMD real + dia==01 + piso 2026-07-01).
#
# Data-resiliente (D-Bloque0): NO hardcodea cantidad de periodos/socios/movimientos ni el mes sin
# foto. Deriva desde acumulados (A31). $MesPreExtension es EXCLUSIVA: solo se asigna si la foto
# cumple sin_foto==false AND detalle_disponible==false AND detalle_motivo=='foto_pre_extension'.
# $MesValido (separada) es un mes valido cualquiera para los negativos de seguridad. Invariantes
# CONTRACTUALES (bloqueantes) vs OBSERVACIONES (informativas). Exige HTTP 200 en resultados manejados.
#
# ASCII PURO (PS 5.1 / CP1252). HttpWebRequest + TLS 1.2. LECTURA socio-only. NO toca OPS. NO escribe.
# Codigo de salida: 0 si todos los asserts pasan; 1 si hay >=1 falla o falta config (secreto/URLs).
# El secreto NO se commitea: pegar en $Secret (o exportar VITA_HMAC_SECRET), el MISMO del wrapper.
# Requiere el wrapper A30 y el A31 (para derivar periodos) ACTIVOS en TEST.
# ============================================================================

[Net.ServicePointManager]::SecurityProtocol = `
  [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# ====== CONFIG (editar) ======
$BaseUrl     = "https://federicosecchi.app.n8n.cloud"
$WebhookHist = "portal-a30-cuenta-corriente-historico__TEST"
$WebhookAcum = "portal-a31-cuenta-corriente-historico-acumulados__TEST"
$Secret      = if ($env:VITA_HMAC_SECRET) { $env:VITA_HMAC_SECRET } else { "__PEGAR_SECRETO_O_USAR_VARIABLE__" }
$Piso        = "2026-07-01"
# =============================

$UrlHist = "$($BaseUrl.TrimEnd('/'))/webhook/$WebhookHist"
$UrlAcum = "$($BaseUrl.TrimEnd('/'))/webhook/$WebhookAcum"
$ACT_H = "cuenta_corriente.historico"
$ACT_A = "cuenta_corriente.historico_acumulados"

$script:passed = 0
$script:failed = 0
$script:failsList = @()
$script:codesSeen = @{}
$script:ALLOWLIST = @('payload_invalido','no_autorizado','rol_no_permitido','accion_desconocida','no_encontrado','conflicto','error_entorno','error_interno','estado_incierto','firma_invalida','ts_fuera_de_ventana','raw_body_ausente','ambiente_incorrecto')

function New-Body {
  param([string]$Action, $Payload, [string]$Rol, [string]$AmbienteEsperado, [long]$Ts, [string]$Nonce)
  $obj = [ordered]@{ action = $Action; payload = $Payload; rol = $Rol; ambiente_esperado = $AmbienteEsperado; ts = $Ts; nonce = $Nonce }
  return ($obj | ConvertTo-Json -Compress -Depth 8)
}
function Get-Signature {
  param([string]$Body, [string]$Key)
  $h = New-Object System.Security.Cryptography.HMACSHA256
  $h.Key = [System.Text.Encoding]::UTF8.GetBytes($Key)
  $hash = $h.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Body))
  return "sha256=" + (($hash | ForEach-Object { $_.ToString('x2') }) -join '')
}
function Send-Probe {
  param([string]$Url, [string]$Body, [string]$Signature)
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
  $req = [System.Net.HttpWebRequest]::Create($Url)
  $req.Method = 'POST'; $req.ContentType = 'application/json'
  $req.Headers.Add('X-Vita-Signature', $Signature); $req.ContentLength = $bytes.Length
  $code = 0; $content = ''
  try {
    $rs = $req.GetRequestStream(); $rs.Write($bytes, 0, $bytes.Length); $rs.Close()
    $resp = $req.GetResponse(); $code = [int]$resp.StatusCode
    $sr = New-Object System.IO.StreamReader($resp.GetResponseStream()); $content = $sr.ReadToEnd(); $sr.Close(); $resp.Close()
  } catch [System.Net.WebException] {
    $r = $_.Exception.Response
    if ($r) { $code = [int]$r.StatusCode; $sr = New-Object System.IO.StreamReader($r.GetResponseStream()); $content = $sr.ReadToEnd(); $sr.Close() }
    else { $content = '{"ok":false,"error":{"code":"__network_error__","message":"' + $_.Exception.Message + '"}}' }
  }
  $j = $null; try { $j = $content | ConvertFrom-Json } catch { }
  return [pscustomobject]@{ code = $code; json = $j; raw = $content }
}
function Track-Code { param($resp); if ($resp.json -and ($resp.json.ok -eq $false) -and $resp.json.error) { $script:codesSeen[$resp.json.error.code] = $true } }
function Record {
  param([string]$name, [bool]$ok, [string]$detail)
  if ($ok) { $script:passed++; Write-Host "PASS  $name" -ForegroundColor Green }
  else { $script:failed++; $script:failsList += "$name :: $detail"; Write-Host "FAIL  $name  ($detail)" -ForegroundColor Red }
}
# Resultados manejados: EXIGE HTTP 200 ademas del envelope/codigo esperado.
function Assert-OkData {
  param([string]$name, $resp, [scriptblock]$Check = $null)
  Track-Code $resp
  $ok = ($resp.code -eq 200) -and ($resp.json) -and ($resp.json.ok -eq $true) -and ($null -ne $resp.json.data)
  if ($ok -and $Check) { $ok = [bool](& $Check $resp.json.data) }
  $code = ''; if ($resp.json -and $resp.json.error) { $code = $resp.json.error.code }
  Record $name $ok "HTTP $($resp.code); ok=$($resp.json.ok) code=$code"
}
function Assert-Code {
  param([string]$name, $resp, [string]$expected)
  Track-Code $resp
  $code = $null; if ($resp.json -and ($resp.json.ok -eq $false) -and $resp.json.error) { $code = $resp.json.error.code }
  Record $name (($resp.code -eq 200) -and ($code -eq $expected)) "esperaba HTTP 200 + ok:false code=$expected; HTTP $($resp.code) ok=$($resp.json.ok) code=$code"
}
function Assert-AllowlistMeta {
  $bad = @(); foreach ($c in $script:codesSeen.Keys) { if ($script:ALLOWLIST -notcontains $c) { $bad += $c } }
  Record "META allowlist (todos los error.code en la allowlist)" (@($bad).Count -eq 0) ("fuera de allowlist: " + ($bad -join ', '))
}
function HasKey { param($obj, $name); if ($null -eq $obj) { return $false }; return ($obj.PSObject.Properties.Name -contains $name) }
function Is-Arr { param($v); return ($v -is [System.Array]) }
function Ymd { param($v); if ($null -eq $v) { return $null }; $s = [string]$v; if ($s.Length -ge 10) { return $s.Substring(0,10) } return $s }
function Add-Months { param([string]$ymd, [int]$n); $d = [datetime]::ParseExact($ymd,'yyyy-MM-dd',$null); return $d.AddMonths($n).ToString('yyyy-MM-01') }
function NG { return [guid]::NewGuid().ToString() }
function Sig-Send {
  param([string]$Url, $Payload, [string]$Rol, [string]$Amb, [long]$Ts, [string]$Act, [string]$Key = $Secret)
  $b = New-Body -Action $Act -Payload $Payload -Rol $Rol -AmbienteEsperado $Amb -Ts $Ts -Nonce (NG)
  return Send-Probe -Url $Url -Body $b -Signature (Get-Signature -Body $b -Key $Key)
}

$KEYS14 = @('sin_foto','detalle_disponible','detalle_motivo','periodo','cabecera','cascada','socios','participacion','gastos','incidencias','movimientos','matriz_por_socio','gastos_sin_incidencia','retribucion_operativo')
$LIST8  = @('cascada','socios','participacion','gastos','incidencias','movimientos','matriz_por_socio','gastos_sin_incidencia')
$FINE5  = @('participacion','gastos','incidencias','matriz_por_socio','gastos_sin_incidencia')
function Has14 { param($d); foreach ($k in $KEYS14) { if (-not (HasKey $d $k)) { return $false } }; return $true }
function AllArr { param($d); foreach ($k in $LIST8) { if (-not (Is-Arr $d.$k)) { return $false } }; return $true }
function AllEmpty {
  param($d, $keys)
  foreach ($k in $keys) {
    if (-not (Is-Arr $d.$k)) { return $false }
    if (@($d.$k).Count -ne 0) { return $false }
  }
  return $true
}

# Aborto por falta de config -> exit distinto de cero (no return silencioso).
if ($Secret.StartsWith("__PEGAR_")) { Write-Host "ABORT: falta pegar el secreto en `$Secret (o exportar VITA_HMAC_SECRET)." -ForegroundColor Red; exit 1 }
if ([string]::IsNullOrEmpty($BaseUrl)) { Write-Host "ABORT: falta BaseUrl." -ForegroundColor Red; exit 1 }

Write-Host "Wrapper historico: $UrlHist" -ForegroundColor Magenta
$now = [long][DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()

# ============================ DERIVACION DINAMICA ============================
Write-Host "`n----- DERIVACION (desde acumulados A31) -----" -ForegroundColor Magenta
$acc = Sig-Send -Url $UrlAcum -Payload @{} -Rol "socio" -Amb "test" -Ts $now -Act $ACT_A
$evo = @()
if ($acc.json -and $acc.json.ok -and $acc.json.data) { foreach ($e in @($acc.json.data.evolucion)) { $evo += (Ymd $e.periodo) } }
Write-Host ("    [obs] periodos vigentes (evolucion): " + $(if ($evo.Count) { $evo -join ', ' } else { '(ninguno)' })) -ForegroundColor DarkGray

# Un solo barrido: $MesValido = primer periodo vigente (foto cualquiera, para negativos de seguridad).
# $MesPreExtension = primer periodo que cumple LA TRIPLE condicion (exclusiva).
$MesValido = $null; $MesPreExtension = $null
foreach ($p in $evo) {
  $pr = Sig-Send -Url $UrlHist -Payload @{mes=$p} -Rol "socio" -Amb "test" -Ts $now -Act $ACT_H
  if ($pr.json -and $pr.json.ok -and $pr.json.data) {
    $d = $pr.json.data
    if ($d.sin_foto -eq $false) {
      if ($null -eq $MesValido) { $MesValido = $p }
      if (($d.detalle_disponible -eq $false) -and ($d.detalle_motivo -eq 'foto_pre_extension') -and ($null -eq $MesPreExtension)) { $MesPreExtension = $p }
    }
  }
  if ($MesValido -and $MesPreExtension) { break }
}
if ($null -eq $MesValido) { $MesValido = $Piso }

# $MesSinFoto: primer mes >= piso ausente de evolucion.
$MesSinFoto = $null; $cand = $Piso
for ($i = 0; $i -lt 120; $i++) { if ($evo -notcontains $cand) { $MesSinFoto = $cand; break }; $cand = Add-Months $cand 1 }

Write-Host ("    [obs] MesValido (negativos)=" + $MesValido + "  MesPreExtension=" + $MesPreExtension + "  MesSinFoto=" + $MesSinFoto) -ForegroundColor DarkGray
# Derivaciones BLOQUEANTES (registran falla si no se hallan; no se aprueban por defecto).
Record "DERIV-1 foto pre-extension vigente hallada (sin_foto=false + detalle_disponible=false + motivo=foto_pre_extension)" ($null -ne $MesPreExtension) "no se hallo foto pre-extension vigente (wrapper A31 activo? datos?)"
Record "DERIV-2 mes sin foto hallado (gap >= piso)" ($null -ne $MesSinFoto) "no se hallo gap >= piso en 120 meses"

# ============================ SEGURIDAD ============================
Write-Host "`n----- SEGURIDAD -----" -ForegroundColor Magenta
Assert-OkData "1. socio OK (HTTP 200, ok:true, data presente)" (Sig-Send -Url $UrlHist -Payload @{mes=$MesValido} -Rol "socio" -Amb "test" -Ts $now -Act $ACT_H) { param($d) $null -ne $d }
Assert-Code "2. vicky -> rol_no_permitido (socio-only)" (Sig-Send -Url $UrlHist -Payload @{mes=$MesValido} -Rol "vicky" -Amb "test" -Ts $now -Act $ACT_H) "rol_no_permitido"
Assert-Code "3. jenny -> rol_no_permitido" (Sig-Send -Url $UrlHist -Payload @{mes=$MesValido} -Rol "jenny" -Amb "test" -Ts $now -Act $ACT_H) "rol_no_permitido"
Assert-Code "4. intruso -> rol_no_permitido (rol fuera de allowlist)" (Sig-Send -Url $UrlHist -Payload @{mes=$MesValido} -Rol "intruso" -Amb "test" -Ts $now -Act $ACT_H) "rol_no_permitido"
Assert-Code "5. firma equivocada -> firma_invalida" (Sig-Send -Url $UrlHist -Payload @{mes=$MesValido} -Rol "socio" -Amb "test" -Ts $now -Act $ACT_H -Key "SECRETO_MALO") "firma_invalida"
Assert-Code "6. ts viejo -> ts_fuera_de_ventana" (Sig-Send -Url $UrlHist -Payload @{mes=$MesValido} -Rol "socio" -Amb "test" -Ts ($now - 600000) -Act $ACT_H) "ts_fuera_de_ventana"
Assert-Code "7. ambiente cruzado -> ambiente_incorrecto" (Sig-Send -Url $UrlHist -Payload @{mes=$MesValido} -Rol "socio" -Amb "ops" -Ts $now -Act $ACT_H) "ambiente_incorrecto"
Assert-Code "8. accion equivocada -> accion_desconocida" (Sig-Send -Url $UrlHist -Payload @{mes=$MesValido} -Rol "socio" -Amb "test" -Ts $now -Act "cobranza.saldos") "accion_desconocida"

# ============================ PAYLOAD {mes} ============================
Write-Host "`n----- PAYLOAD (mes) -----" -ForegroundColor Magenta
Assert-Code "9. sin mes -> payload_invalido" (Sig-Send -Url $UrlHist -Payload @{} -Rol "socio" -Amb "test" -Ts $now -Act $ACT_H) "payload_invalido"
Assert-Code "10. mes mal formado (2026-13-99) -> payload_invalido" (Sig-Send -Url $UrlHist -Payload @{mes="2026-13-99"} -Rol "socio" -Amb "test" -Ts $now -Act $ACT_H) "payload_invalido"
Assert-Code "11. mes dia != 01 (2026-07-15) -> payload_invalido" (Sig-Send -Url $UrlHist -Payload @{mes="2026-07-15"} -Rol "socio" -Amb "test" -Ts $now -Act $ACT_H) "payload_invalido"
Assert-Code "12. mes pre-piso (2026-05-01) -> payload_invalido" (Sig-Send -Url $UrlHist -Payload @{mes="2026-05-01"} -Rol "socio" -Amb "test" -Ts $now -Act $ACT_H) "payload_invalido"
Assert-Code "13. clave no permitida -> payload_invalido" (Sig-Send -Url $UrlHist -Payload @{mes=$MesValido; foo=1} -Rol "socio" -Amb "test" -Ts $now -Act $ACT_H) "payload_invalido"

# ============================ FUNCIONAL: foto pre-extension (BLOQUEANTE via $MesPreExtension) ==========
Write-Host "`n----- FUNCIONAL: foto pre-extension ($MesPreExtension) -----" -ForegroundColor Magenta
if ($MesPreExtension) {
  $rF = Sig-Send -Url $UrlHist -Payload @{mes=$MesPreExtension} -Rol "socio" -Amb "test" -Ts $now -Act $ACT_H
  if ($rF.json -and $rF.json.ok) {
    $d = $rF.json.data
    Write-Host ("    [obs] periodo=" + (Ymd $d.periodo) + " cascada=" + @($d.cascada).Count + " socios=" + @($d.socios).Count + " movimientos=" + @($d.movimientos).Count + " gastos=" + @($d.gastos).Count) -ForegroundColor DarkGray
  }
  Assert-OkData "F1. periodo round-trip (data.periodo == $MesPreExtension)" $rF { param($d) (Ymd $d.periodo) -eq $MesPreExtension }
  Assert-OkData "F2. 14 claves top-level presentes" $rF { param($d) Has14 $d }
  Assert-OkData "F3. las 8 secciones-lista son arrays" $rF { param($d) AllArr $d }
  Assert-OkData "F4. sin_foto=false" $rF { param($d) $d.sin_foto -eq $false }
  Assert-OkData "F5. detalle_disponible=false + detalle_motivo=foto_pre_extension" $rF { param($d) ($d.detalle_disponible -eq $false) -and ($d.detalle_motivo -eq 'foto_pre_extension') }
  Assert-OkData "F6. detalle fino vacio (participacion/gastos/incidencias/matriz/gastos_sin_incidencia)" $rF { param($d) AllEmpty $d $FINE5 }
  Assert-OkData "F7. cabecera presente (no null) con linaje" $rF { param($d) ($null -ne $d.cabecera) -and (HasKey $d.cabecera 'linaje') }
  Assert-OkData "F8. cascada no vacia" $rF { param($d) @($d.cascada).Count -gt 0 }
  Assert-OkData "F9. socios no vacio" $rF { param($d) @($d.socios).Count -gt 0 }
  Assert-OkData "F10. retribucion_operativo presente (no null)" $rF { param($d) $null -ne $d.retribucion_operativo }
  Assert-OkData "F11. movimientos dentro de la ventana [$MesPreExtension, +1 mes)" $rF {
    param($d)
    $lo = $MesPreExtension; $hi = Add-Months $MesPreExtension 1; $ok = $true
    foreach ($m in @($d.movimientos)) { $f = Ymd $m.fecha; if (-not ($f -ge $lo -and $f -lt $hi)) { $ok = $false } }
    $ok
  }
} else {
  Write-Host "    (sin MesPreExtension: DERIV-1 ya registro la falla; no se ejecutan F1..F11)" -ForegroundColor Yellow
}

# ============================ FUNCIONAL: mes sin foto ============================
Write-Host "`n----- FUNCIONAL: mes sin foto ($MesSinFoto) -----" -ForegroundColor Magenta
if ($MesSinFoto) {
  $rS = Sig-Send -Url $UrlHist -Payload @{mes=$MesSinFoto} -Rol "socio" -Amb "test" -Ts $now -Act $ACT_H
  Assert-OkData "S1. sin_foto -> ok:true (NUNCA no_encontrado)" $rS { param($d) $d.sin_foto -eq $true }
  Assert-OkData "S2. 14 claves top-level presentes (rama sin foto)" $rS { param($d) Has14 $d }
  Assert-OkData "S3. detalle_motivo == sin_foto_vigente" $rS { param($d) $d.detalle_motivo -eq 'sin_foto_vigente' }
  Assert-OkData "S4. las 8 secciones-lista vacias" $rS { param($d) AllEmpty $d $LIST8 }
  Assert-OkData "S5. cabecera null y retribucion_operativo null" $rS { param($d) ($null -eq $d.cabecera) -and ($null -eq $d.retribucion_operativo) }
  Assert-OkData "S6. detalle_disponible=false" $rS { param($d) $d.detalle_disponible -eq $false }
  Assert-OkData "S7. periodo round-trip (data.periodo == $MesSinFoto)" $rS { param($d) (Ymd $d.periodo) -eq $MesSinFoto }
} else {
  Write-Host "    (sin MesSinFoto: DERIV-2 ya registro la falla; no se ejecutan S1..S7)" -ForegroundColor Yellow
}

Assert-AllowlistMeta

Write-Host "`n===== RESUMEN =====" -ForegroundColor Magenta
Write-Host ("PASSED: " + $script:passed) -ForegroundColor Green
Write-Host ("FAILED: " + $script:failed) -ForegroundColor Red
if ($script:failed -gt 0) { Write-Host "`nFallos:" -ForegroundColor Red; foreach ($f in $script:failsList) { Write-Host ("  - " + $f) -ForegroundColor Red } }

if ($script:failed -gt 0) { exit 1 }
exit 0
