# ============================================================================
# CC_L3_A31_acumulados_smoke_directo.ps1
# Frente Cuenta corriente de socios / L3 - A31 (cuenta_corriente.historico_acumulados).
# Smoke DIRECTO al wrapper n8n "portal-a31-cuenta-corriente-historico-acumulados__TEST", SIN gateway.
#
# Arma el sobre { action, payload, rol, ambiente_esperado, ts, nonce }, firma HMAC-SHA256 sobre los
# BYTES EXACTOS y POSTea. n8n recomputa el HMAC (D-C-29) y revalida el payload VACIO ESTRICTO (D1):
# undefined/null -> {}; {} -> ok; objeto con claves / array / string / number / boolean -> payload_invalido.
#
# Data-resiliente (D-Bloque0): NO hardcodea cantidad de periodos/socios/movimientos ni totales.
# Invariantes CONTRACTUALES (bloqueantes: 6 claves, tipos, evolucion ordenada, meta.fotos_vigentes ==
# evolucion.length, piso 2026-07-01) vs OBSERVACIONES (informativas). Exige HTTP 200 en resultados manejados.
#
# ASCII PURO (PS 5.1 / CP1252). HttpWebRequest + TLS 1.2. LECTURA socio-only. NO toca OPS. NO escribe.
# Codigo de salida: 0 si todos los asserts pasan; 1 si hay >=1 falla o falta config (secreto).
# El secreto NO se commitea: pegar en $Secret (o exportar VITA_HMAC_SECRET), el MISMO del wrapper.
# ============================================================================

[Net.ServicePointManager]::SecurityProtocol = `
  [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# ====== CONFIG (editar) ======
$BaseUrl = "https://federicosecchi.app.n8n.cloud"
$Webhook = "portal-a31-cuenta-corriente-historico-acumulados__TEST"
$Secret  = if ($env:VITA_HMAC_SECRET) { $env:VITA_HMAC_SECRET } else { "__PEGAR_SECRETO_O_USAR_VARIABLE__" }
$Piso    = "2026-07-01"
# =============================

$Url = "$($BaseUrl.TrimEnd('/'))/webhook/$Webhook"
$ACT = "cuenta_corriente.historico_acumulados"

$script:passed = 0
$script:failed = 0
$script:failsList = @()
$script:codesSeen = @{}
$script:ALLOWLIST = @('payload_invalido','no_autorizado','rol_no_permitido','accion_desconocida','no_encontrado','conflicto','error_entorno','error_interno','estado_incierto','firma_invalida','ts_fuera_de_ventana','raw_body_ausente','ambiente_incorrecto')

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
function NG { return [guid]::NewGuid().ToString() }
function Sig-Send {
  param($Payload, [string]$Rol, [string]$Amb, [long]$Ts, [string]$Act = $ACT, [string]$Key = $Secret, [switch]$Omit)
  if ($Omit) { $obj = [ordered]@{ action = $Act; rol = $Rol; ambiente_esperado = $Amb; ts = $Ts; nonce = (NG) } }
  else       { $obj = [ordered]@{ action = $Act; payload = $Payload; rol = $Rol; ambiente_esperado = $Amb; ts = $Ts; nonce = (NG) } }
  $b = ($obj | ConvertTo-Json -Compress -Depth 8)
  return Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Key)
}

$KEYS6 = @('sin_datos','piso','totales','evolucion','saldos_por_socio','meta')
function Has6 { param($d); foreach ($k in $KEYS6) { if (-not (HasKey $d $k)) { return $false } }; return $true }

# Aborto por falta de config -> exit distinto de cero (no return silencioso).
if ($Secret.StartsWith("__PEGAR_")) { Write-Host "ABORT: falta pegar el secreto en `$Secret (o exportar VITA_HMAC_SECRET)." -ForegroundColor Red; exit 1 }
if ([string]::IsNullOrEmpty($BaseUrl)) { Write-Host "ABORT: falta BaseUrl." -ForegroundColor Red; exit 1 }

Write-Host "Wrapper: $Url" -ForegroundColor Magenta
$now = [long][DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()

# ============================ SEGURIDAD ============================
Write-Host "`n----- SEGURIDAD -----" -ForegroundColor Magenta
Assert-OkData "1. socio OK (HTTP 200, ok:true, data presente)" (Sig-Send -Payload @{} -Rol "socio" -Amb "test" -Ts $now) { param($d) $null -ne $d }
Assert-Code "2. vicky -> rol_no_permitido (socio-only)" (Sig-Send -Payload @{} -Rol "vicky" -Amb "test" -Ts $now) "rol_no_permitido"
Assert-Code "3. jenny -> rol_no_permitido" (Sig-Send -Payload @{} -Rol "jenny" -Amb "test" -Ts $now) "rol_no_permitido"
Assert-Code "4. intruso -> rol_no_permitido (rol fuera de allowlist)" (Sig-Send -Payload @{} -Rol "intruso" -Amb "test" -Ts $now) "rol_no_permitido"
Assert-Code "5. firma equivocada -> firma_invalida" (Sig-Send -Payload @{} -Rol "socio" -Amb "test" -Ts $now -Key "SECRETO_MALO") "firma_invalida"
Assert-Code "6. ts viejo -> ts_fuera_de_ventana" (Sig-Send -Payload @{} -Rol "socio" -Amb "test" -Ts ($now - 600000)) "ts_fuera_de_ventana"
Assert-Code "7. ambiente cruzado -> ambiente_incorrecto" (Sig-Send -Payload @{} -Rol "socio" -Amb "ops" -Ts $now) "ambiente_incorrecto"
Assert-Code "8. accion equivocada -> accion_desconocida" (Sig-Send -Payload @{} -Rol "socio" -Amb "test" -Ts $now -Act "cobranza.saldos") "accion_desconocida"

# ============================ PAYLOAD VACIO ESTRICTO (D1) ============================
Write-Host "`n----- PAYLOAD (vacio estricto) -----" -ForegroundColor Magenta
Assert-OkData "9. payload {} -> ok:true" (Sig-Send -Payload @{} -Rol "socio" -Amb "test" -Ts $now) { param($d) $null -ne $d }
Assert-OkData "10. payload omitido -> ok:true (normaliza a vacio)" (Sig-Send -Payload $null -Rol "socio" -Amb "test" -Ts $now -Omit) { param($d) $null -ne $d }
Assert-OkData "11. payload null -> ok:true (normaliza a vacio)" (Sig-Send -Payload $null -Rol "socio" -Amb "test" -Ts $now) { param($d) $null -ne $d }
Assert-Code "12. payload con clave {foo:1} -> payload_invalido" (Sig-Send -Payload @{foo=1} -Rol "socio" -Amb "test" -Ts $now) "payload_invalido"
Assert-Code "13. payload array -> payload_invalido" (Sig-Send -Payload @(1,2) -Rol "socio" -Amb "test" -Ts $now) "payload_invalido"
Assert-Code "14. payload string -> payload_invalido" (Sig-Send -Payload "x" -Rol "socio" -Amb "test" -Ts $now) "payload_invalido"
Assert-Code "15. payload number -> payload_invalido" (Sig-Send -Payload 5 -Rol "socio" -Amb "test" -Ts $now) "payload_invalido"
Assert-Code "16. payload boolean -> payload_invalido" (Sig-Send -Payload $true -Rol "socio" -Amb "test" -Ts $now) "payload_invalido"

# ============================ FUNCIONAL ============================
Write-Host "`n----- FUNCIONAL -----" -ForegroundColor Magenta
$rF = Sig-Send -Payload @{} -Rol "socio" -Amb "test" -Ts $now
if ($rF.json -and $rF.json.ok) {
  $d = $rF.json.data
  $per = @(); foreach ($e in @($d.evolucion)) { $per += (Ymd $e.periodo) }
  Write-Host ("    [obs] sin_datos=" + $d.sin_datos + " piso=" + (Ymd $d.piso) + " fotos_vigentes=" + $d.meta.fotos_vigentes) -ForegroundColor DarkGray
  Write-Host ("    [obs] evolucion periodos: " + $(if ($per.Count) { $per -join ', ' } else { '(ninguno)' })) -ForegroundColor DarkGray
  Write-Host ("    [obs] saldos_por_socio=" + @($d.saldos_por_socio).Count + " socios") -ForegroundColor DarkGray
  if ($d.totales) {
    Write-Host ("    [obs] totales: ingresos=" + $d.totales.ingresos_acumulados + " gastos=" + $d.totales.gastos_acumulados + " utilidad=" + $d.totales.utilidad_acumulada + " repartos=" + $d.totales.repartos_acumulados + " retiros=" + $d.totales.retiros_acumulados) -ForegroundColor DarkGray
  }
}
Assert-OkData "F1. 6 claves top-level presentes" $rF { param($d) Has6 $d }
Assert-OkData "F2. evolucion y saldos_por_socio son arrays; totales y meta objetos" $rF {
  param($d)
  (Is-Arr $d.evolucion) -and (Is-Arr $d.saldos_por_socio) -and ($null -ne $d.totales) -and ($null -ne $d.meta)
}
Assert-OkData "F3. piso == 2026-07-01 (D-NEG-02)" $rF { param($d) (Ymd $d.piso) -eq $Piso }
Assert-OkData "F4. sin_datos es booleano" $rF { param($d) ($d.sin_datos -is [bool]) }
Assert-OkData "F5. evolucion ordenada por periodo asc" $rF {
  param($d)
  $ps = @(); foreach ($e in @($d.evolucion)) { $ps += (Ymd $e.periodo) }
  $sorted = $true; for ($i = 1; $i -lt $ps.Count; $i++) { if ($ps[$i] -lt $ps[$i-1]) { $sorted = $false } }
  $sorted
}
Assert-OkData "F6. meta.fotos_vigentes == evolucion.length" $rF { param($d) ([int]$d.meta.fotos_vigentes) -eq (@($d.evolucion).Count) }
Assert-OkData "F7. si sin_datos=false -> evolucion no vacia (coherencia)" $rF { param($d) ($d.sin_datos -eq $true) -or (@($d.evolucion).Count -gt 0) }

Assert-AllowlistMeta

Write-Host "`n===== RESUMEN =====" -ForegroundColor Magenta
Write-Host ("PASSED: " + $script:passed) -ForegroundColor Green
Write-Host ("FAILED: " + $script:failed) -ForegroundColor Red
if ($script:failed -gt 0) { Write-Host "`nFallos:" -ForegroundColor Red; foreach ($f in $script:failsList) { Write-Host ("  - " + $f) -ForegroundColor Red } }

if ($script:failed -gt 0) { exit 1 }
exit 0
