# ============================================================================
# E3_smoke_seguridad_escritura__OPS.ps1
# Carril C - Promocion OPS - Bloque E3. Smoke de SEGURIDAD para wrappers de
# ESCRITURA __OPS (A10-MP / A07). SOLO prueba REBOTES: NINGUN probe escribe,
# porque todos son rechazados ANTES de los nodos PG de escritura.
#
#   P1 action INCORRECTO  + firma valida -> accion_desconocida  (action binding)
#   P2 firma INVALIDA                     -> firma_invalida
#   P3 rol jenny (no permitido)           -> rol_no_permitido
#   P4 ambiente_esperado=test             -> ambiente_incorrecto
#
# Lo critico (lo que pediste): P1 confirma que si el action no coincide con
# EXPECTED_ACTION, el wrapper rebota y NO llega a escribir. Para confirmarlo de
# forma dura, corre el gate E3_gate_no_escribe.sql ANTES y DESPUES (conteo igual).
#
# ASCII PURO. TLS 1.2. NO toca TEST. El secreto se pega en $Secret y se borra.
# ============================================================================

[Net.ServicePointManager]::SecurityProtocol = `
  [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# ============ CONFIG (editar por wrapper) ============
$BaseUrl       = "https://federicosecchi.app.n8n.cloud"
# --- A10-MP ---
$Webhook       = "portal-a10mp-registrar-cobro__OPS"
$ACT_OK        = "cobranza.registrar_cobro"
$ACT_BAD       = "cobranza.registrar_saldo"   # action de OTRO endpoint (W10) -> debe rebotar
# --- A07 (descomentar para A07) ---
# $Webhook     = "portal-a07-crear-reserva__OPS"
# $ACT_OK      = "reserva.crear_manual"
# $ACT_BAD     = "cobranza.registrar_cobro"
$Secret        = "PEGAR_HMAC_OPS_Y_BORRAR"
# Payload minimo: da igual el contenido, todos los probes rebotan antes de escribir.
$Payload       = @{ ping = "seguridad" }
# ====================================================

$WebhookUrl = "$($BaseUrl.TrimEnd('/'))/webhook/$Webhook"
$script:passed = 0; $script:failed = 0

function New-Body {
  param([string]$Action,[object]$Pl,[string]$RolX,[string]$Amb,[long]$Ts,[string]$Nonce)
  $obj = [ordered]@{ action=$Action; payload=$Pl; rol=$RolX; ambiente_esperado=$Amb; ts=$Ts; nonce=$Nonce }
  return ($obj | ConvertTo-Json -Compress -Depth 8)
}
function Get-Signature {
  param([string]$Body,[string]$Key)
  $h = New-Object System.Security.Cryptography.HMACSHA256
  $h.Key = [System.Text.Encoding]::UTF8.GetBytes($Key)
  $hash = $h.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Body))
  return "sha256=" + (($hash | ForEach-Object { $_.ToString('x2') }) -join '')
}
function Send-Probe {
  param([string]$Body,[string]$Signature)
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
  $req = [System.Net.HttpWebRequest]::Create($WebhookUrl)
  $req.Method='POST'; $req.ContentType='application/json'
  $req.Headers.Add('X-Vita-Signature',$Signature); $req.ContentLength=$bytes.Length
  $code=0; $content=''
  try {
    $rs=$req.GetRequestStream(); $rs.Write($bytes,0,$bytes.Length); $rs.Close()
    $resp=$req.GetResponse(); $code=[int]$resp.StatusCode
    $sr=New-Object System.IO.StreamReader($resp.GetResponseStream()); $content=$sr.ReadToEnd(); $sr.Close(); $resp.Close()
  } catch [System.Net.WebException] {
    $r=$_.Exception.Response
    if ($r) { $code=[int]$r.StatusCode; $sr=New-Object System.IO.StreamReader($r.GetResponseStream()); $content=$sr.ReadToEnd(); $sr.Close() }
    else { $code=-1; $content=$_.Exception.Message }
  }
  return [pscustomobject]@{ Code=$code; Content=$content }
}
function Code-Of { param($Content) try { return ($Content | ConvertFrom-Json).error.code } catch { return '' } }
function Check { param([string]$Name,[bool]$Cond,[string]$Detail)
  if ($Cond) { $script:passed++; Write-Host "  PASS  $Name" -ForegroundColor Green }
  else { $script:failed++; Write-Host "  FAIL  $Name -> $Detail" -ForegroundColor Red }
}

Write-Host ""
Write-Host "Smoke SEGURIDAD (no escribe): $Webhook" -ForegroundColor Cyan
Write-Host "URL: $WebhookUrl"; Write-Host ""

$ts = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()

# P1: action INCORRECTO + firma valida -> accion_desconocida (NO escribe)
$b1 = New-Body $ACT_BAD $Payload "socio" "ops" $ts ([guid]::NewGuid().ToString())
$r1 = Send-Probe $b1 (Get-Signature $b1 $Secret); $c1 = Code-Of $r1.Content
Check "P1 action=$ACT_BAD -> accion_desconocida (NO escribe)" ($c1 -eq 'accion_desconocida') "code=$c1 / $($r1.Content)"

# P2: firma invalida -> firma_invalida
$b2 = New-Body $ACT_OK $Payload "socio" "ops" $ts ([guid]::NewGuid().ToString())
$r2 = Send-Probe $b2 "sha256=deadbeef"; $c2 = Code-Of $r2.Content
Check "P2 firma invalida -> firma_invalida" ($c2 -eq 'firma_invalida') "code=$c2 / $($r2.Content)"

# P3: rol jenny -> rol_no_permitido
$b3 = New-Body $ACT_OK $Payload "jenny" "ops" $ts ([guid]::NewGuid().ToString())
$r3 = Send-Probe $b3 (Get-Signature $b3 $Secret); $c3 = Code-Of $r3.Content
Check "P3 rol=jenny -> rol_no_permitido" ($c3 -eq 'rol_no_permitido') "code=$c3 / $($r3.Content)"

# P4: ambiente_esperado=test -> ambiente_incorrecto
$b4 = New-Body $ACT_OK $Payload "socio" "test" $ts ([guid]::NewGuid().ToString())
$r4 = Send-Probe $b4 (Get-Signature $b4 $Secret); $c4 = Code-Of $r4.Content
Check "P4 ambiente=test -> ambiente_incorrecto" ($c4 -eq 'ambiente_incorrecto') "code=$c4 / $($r4.Content)"

Write-Host ""
Write-Host "RESULTADO: $script:passed PASS / $script:failed FAIL" -ForegroundColor (&{ if ($script:failed -eq 0){'Green'} else {'Red'} })
Write-Host "Recorda: corre E3_gate_no_escribe.sql ANTES y DESPUES para confirmar 0 escrituras." -ForegroundColor Yellow
