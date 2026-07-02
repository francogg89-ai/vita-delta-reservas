# ============================================================================
# CC_L2_A28_smoke_directo.ps1
# Frente Cuenta corriente de socios / L2 - A28 (cuenta_corriente.detalle).
# Smoke DIRECTO al wrapper n8n "portal-a28-cuenta-corriente-detalle" (OPS), SIN gateway.
#
# Arma el sobre { action, payload:{mes}, rol, ambiente_esperado, ts, nonce }, firma HMAC-SHA256
# sobre los BYTES EXACTOS, y POSTea. n8n recomputa el HMAC (D-C-29) y revalida el payload {mes}.
#
# ENTORNO: OPS. Guard: frena si el webhook no termina en __OPS o el ambiente != ops.
# ASCII PURO (PS 5.1 / CP1252). Sin -Parallel. HttpWebRequest + TLS 1.2. Contadores $script:.
# LECTURA socio-only. Diferencias con A27: el payload lleva { mes } (obligatorio, YMD, >= piso),
# y la respuesta es el jsonb del drill-down (cascada/matriz/matriz_cabanas/incidencias/...).
#
# NO toca OPS. NO escribe. NO consume secuencias. El secreto NO se commitea: pegar en $Secret,
# el MISMO del nodo validar_firma_ts_rol (Modo B).
# ============================================================================

[Net.ServicePointManager]::SecurityProtocol = `
  [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# ====== CONFIG (editar) ======
$BaseUrl = "https://federicosecchi.app.n8n.cloud"
$Webhook = "portal-a28-cuenta-corriente-detalle__OPS"
$Secret  = "secreto_no_subir"
$MesOk   = "2026-07-01"   # mes con actividad en OPS
# =============================

$WebhookUrl = "$($BaseUrl.TrimEnd('/'))/webhook/$Webhook"
$ACT = "cuenta_corriente.detalle"
$Ambiente = "ops"   # ambiente_esperado correcto en OPS

# GUARD OPS: este smoke SOLO le pega al wrapper OPS. Si el webhook no termina en __OPS
# o el ambiente no es ops, FRENA (exit 3) antes de firmar o enviar.
if (-not $Webhook.EndsWith('__OPS')) { Write-Host 'GUARD OPS: $Webhook no termina en __OPS. FRENO.' -ForegroundColor Red; exit 3 }
if ($Ambiente -ne 'ops')             { Write-Host 'GUARD OPS: ambiente != ops. FRENO.' -ForegroundColor Red; exit 3 }

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
function Assert-OkData {
  param([string]$name, $resp, [scriptblock]$Check = $null)
  Track-Code $resp
  $ok = ($resp.json -and ($resp.json.ok -eq $true) -and ($null -ne $resp.json.data))
  if ($ok -and $Check) { $ok = [bool](& $Check $resp.json.data) }
  $code = ''; if ($resp.json -and $resp.json.error) { $code = $resp.json.error.code }
  Record $name $ok "HTTP $($resp.code); ok=$($resp.json.ok) code=$code"
}
function Assert-Code {
  param([string]$name, $resp, [string]$expected)
  Track-Code $resp
  $code = $null; if ($resp.json -and ($resp.json.ok -eq $false) -and $resp.json.error) { $code = $resp.json.error.code }
  Record $name ($code -eq $expected) "esperaba ok:false code=$expected; HTTP $($resp.code) ok=$($resp.json.ok) code=$code"
}
function Assert-AllowlistMeta {
  $bad = @(); foreach ($c in $script:codesSeen.Keys) { if ($script:ALLOWLIST -notcontains $c) { $bad += $c } }
  Record "META allowlist (todos los error.code en la allowlist)" (@($bad).Count -eq 0) ("fuera de allowlist: " + ($bad -join ', '))
}
function HasKey { param($obj, $name); if ($null -eq $obj) { return $false }; return ($obj.PSObject.Properties.Name -contains $name) }

if ($Secret.StartsWith("__PEGAR_")) { Write-Host "Falta pegar el secreto en `$Secret." -ForegroundColor Red; return }

Write-Host "Wrapper: $WebhookUrl" -ForegroundColor Magenta
$now = [long][DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
function NG { return [guid]::NewGuid().ToString() }
function Sig-Send { param([hashtable]$Payload, [string]$Rol, [string]$Amb, [long]$Ts, [string]$Act = $ACT, [string]$Key = $Secret)
  $b = New-Body -Action $Act -Payload $Payload -Rol $Rol -AmbienteEsperado $Amb -Ts $Ts -Nonce (NG)
  return Send-Probe -Body $b -Signature (Get-Signature -Body $b -Key $Key)
}

# ============================ SEGURIDAD ============================
Write-Host "`n----- SEGURIDAD -----" -ForegroundColor Magenta
Assert-OkData "1. socio OK (ok:true, data presente)" (Sig-Send -Payload @{mes=$MesOk} -Rol "socio" -Amb $Ambiente -Ts $now) { param($d) $null -ne $d }
Assert-Code "2. vicky -> rol_no_permitido (socio-only)" (Sig-Send -Payload @{mes=$MesOk} -Rol "vicky" -Amb $Ambiente -Ts $now) "rol_no_permitido"
Assert-Code "3. jenny -> rol_no_permitido" (Sig-Send -Payload @{mes=$MesOk} -Rol "jenny" -Amb $Ambiente -Ts $now) "rol_no_permitido"
Assert-Code "4. firma equivocada -> firma_invalida" (Sig-Send -Payload @{mes=$MesOk} -Rol "socio" -Amb $Ambiente -Ts $now -Key "SECRETO_MALO") "firma_invalida"
Assert-Code "5. ts viejo -> ts_fuera_de_ventana" (Sig-Send -Payload @{mes=$MesOk} -Rol "socio" -Amb $Ambiente -Ts ($now - 600000)) "ts_fuera_de_ventana"
Assert-Code "6. ambiente cruzado -> ambiente_incorrecto" (Sig-Send -Payload @{mes=$MesOk} -Rol "socio" -Amb "test" -Ts $now) "ambiente_incorrecto"
Assert-Code "7. accion equivocada -> accion_desconocida" (Sig-Send -Payload @{mes=$MesOk} -Rol "socio" -Amb $Ambiente -Ts $now -Act "cobranza.saldos") "accion_desconocida"

# ============================ PAYLOAD {mes} ============================
Write-Host "`n----- PAYLOAD (mes) -----" -ForegroundColor Magenta
Assert-Code "8. sin mes -> payload_invalido" (Sig-Send -Payload @{} -Rol "socio" -Amb $Ambiente -Ts $now) "payload_invalido"
Assert-Code "9. mes mal formado -> payload_invalido" (Sig-Send -Payload @{mes="2026-13-99"} -Rol "socio" -Amb $Ambiente -Ts $now) "payload_invalido"
Assert-Code "10. mes pre-piso (2026-05-01) -> payload_invalido" (Sig-Send -Payload @{mes="2026-05-01"} -Rol "socio" -Amb $Ambiente -Ts $now) "payload_invalido"
Assert-Code "11. clave no permitida -> payload_invalido" (Sig-Send -Payload @{mes=$MesOk; foo=1} -Rol "socio" -Amb $Ambiente -Ts $now) "payload_invalido"

# ============================ FUNCIONAL ============================
Write-Host "`n----- FUNCIONAL -----" -ForegroundColor Magenta
$rF = Sig-Send -Payload @{mes=$MesOk} -Rol "socio" -Amb $Ambiente -Ts $now
if ($rF.json -and $rF.json.ok) {
  $d = $rF.json.data
  Write-Host ("    mes=" + $d.mes) -ForegroundColor DarkGray
  Write-Host ("    cascada=" + @($d.cascada).Count + " matriz=" + @($d.matriz).Count + " matriz_cabanas=" + @($d.matriz_cabanas).Count + " incidencias=" + @($d.incidencias).Count + " gastos_sin_incidencia=" + @($d.gastos_sin_incidencia).Count) -ForegroundColor DarkGray
}
# F1. mes del request round-trippeado (prueba que el wrapper paso el mes correctamente)
Assert-OkData "F1. data.mes == mes pedido ($MesOk)" $rF { param($d) $d.mes -eq $MesOk }
# F2. las 6 secciones presentes
Assert-OkData "F2. jsonb con las 6 claves" $rF {
  param($d)
  (HasKey $d 'mes') -and (HasKey $d 'cascada') -and (HasKey $d 'matriz') -and (HasKey $d 'matriz_cabanas') -and (HasKey $d 'incidencias') -and (HasKey $d 'gastos_sin_incidencia')
}
# F3. cascada es arreglo no vacio (julio tiene actividad)
Assert-OkData "F3. cascada no vacia" $rF { param($d) @($d.cascada).Count -gt 0 }

Assert-AllowlistMeta

Write-Host "`n===== RESUMEN =====" -ForegroundColor Magenta
Write-Host ("PASSED: " + $script:passed) -ForegroundColor Green
Write-Host ("FAILED: " + $script:failed) -ForegroundColor Red
if ($script:failed -gt 0) { Write-Host "`nFallos:" -ForegroundColor Red; foreach ($f in $script:failsList) { Write-Host ("  - " + $f) -ForegroundColor Red } }
