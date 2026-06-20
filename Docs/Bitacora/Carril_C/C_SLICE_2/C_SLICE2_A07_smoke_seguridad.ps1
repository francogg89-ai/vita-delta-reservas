# ============================================================================
# C_SLICE2_A07 — BLOQUE 1: SMOKES DE SEGURIDAD (SIN ESCRITURA)
# Wrapper portal-a07-crear-reserva__TEST. Todos estos casos REBOTAN antes del
# SQL (firma/ts/rol/action/actor/ambiente/payload), asi que NO escriben nada.
# Para "rol habilitado" (vicky/socio) se usa un payload INVALIDO a proposito:
# el resultado payload_invalido (en vez de rol_no_permitido) prueba que el rol
# fue aceptado y que se freno recien en la validacion de payload, sin tocar PG.
#
# Requisitos:
#   - Workflow ACTIVO (active:true) durante la bateria (el webhook productivo
#     /webhook/ requiere active:true). Se vuelve a active:false en el teardown.
#   - $env:VITA_HMAC_SECRET_TEST = secreto HMAC real de TEST (NO se hardcodea).
#   - El secreto debe coincidir con el configurado en el nodo validar_firma_ts_rol.
#
# Uso:  pwsh ./C_SLICE2_A07_smoke_seguridad.ps1
# ============================================================================
param(
  [string]$BaseUrl = "https://federicosecchi.app.n8n.cloud/webhook",
  [string]$Path    = "portal-a07-crear-reserva__TEST"
)
$ErrorActionPreference = "Stop"

$Secret = $env:VITA_HMAC_SECRET_TEST
if (-not $Secret) { Write-Host "FALTA: setea `$env:VITA_HMAC_SECRET_TEST" -ForegroundColor Red; exit 1 }

$enc = [System.Text.Encoding]::UTF8

function New-Body {
  param([hashtable]$PayloadOverride = @{}, [string]$Rol = "vicky", [string]$Actor = "vicky",
        [string]$Amb = "test", [long]$TsOffsetMs = 0, [string]$Action = "reserva.crear_manual")
  # payload base VALIDO (fechas 2027, huesped centinela de seguridad).
  $payload = [ordered]@{
    id_cabana=4; fecha_in="2027-09-01"; fecha_out="2027-09-03"; personas=2
    monto_total=80000; monto_sena=40000
    canal_pago_esperado="transferencia_mp"; medio_pago="transferencia_mp"
    huesped=[ordered]@{ nombre="PORTAL TEST A07 SEC"; telefono="+5490000000799" }
  }
  foreach ($k in $PayloadOverride.Keys) { $payload[$k] = $PayloadOverride[$k] }
  $ts = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() + $TsOffsetMs
  return [ordered]@{
    action=$Action; rol=$Rol; actor=$Actor; ambiente_esperado=$Amb
    ts=$ts; nonce=[guid]::NewGuid().ToString(); payload=$payload
  }
}

function Invoke-A07 {
  param([object]$BodyObj, [switch]$BadSig)
  $json = $BodyObj | ConvertTo-Json -Compress -Depth 12
  $bodyBytes = $enc.GetBytes($json)
  if ($BadSig) {
    $sig = "sha256=deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
  } else {
    $h = [System.Security.Cryptography.HMACSHA256]::new($enc.GetBytes($Secret))
    $sig = "sha256=" + ([System.BitConverter]::ToString($h.ComputeHash($bodyBytes)) -replace '-','').ToLower()
  }
  $headers = @{ "x-vita-signature" = $sig }
  try {
    return Invoke-RestMethod -Uri "$BaseUrl/$Path" -Method Post -Body $bodyBytes `
                             -Headers $headers -ContentType "application/json"
  } catch {
    # n8n responde 200 con envelope; si hubo error HTTP intentamos leer el cuerpo.
    $r = $_.Exception.Response
    if ($r) { $sr = New-Object System.IO.StreamReader($r.GetResponseStream()); $txt = $sr.ReadToEnd()
              try { return $txt | ConvertFrom-Json } catch { return @{ ok=$false; error=@{ code="_http"; message=$txt } } } }
    return @{ ok=$false; error=@{ code="_neterr"; message=$_.Exception.Message } }
  }
}

# payload invalido reutilizable (monto_sena > monto_total) para los casos de rol.
$invMontos = @{ monto_sena = 999999 }

$cases = @(
  @{ n="01 rol vicky habilitado (payload invalido)"; body=(New-Body -Rol "vicky" -PayloadOverride $invMontos); ok=$false; code="payload_invalido" }
  @{ n="02 rol socio habilitado (payload invalido)"; body=(New-Body -Rol "socio" -PayloadOverride $invMontos); ok=$false; code="payload_invalido" }
  @{ n="03 rol jenny NO permitido";                  body=(New-Body -Rol "jenny");                            ok=$false; code="rol_no_permitido" }
  @{ n="04 rol basura NO permitido";                 body=(New-Body -Rol "intruso");                          ok=$false; code="rol_no_permitido" }
  @{ n="05 firma invalida";                          body=(New-Body); badsig=$true;                           ok=$false; code="firma_invalida" }
  @{ n="06 ts viejo (fuera de ventana)";             body=(New-Body -TsOffsetMs -999999);                     ok=$false; code="ts_fuera_de_ventana" }
  @{ n="07 ambiente cruzado (ops)";                  body=(New-Body -Amb "ops");                              ok=$false; code="ambiente_incorrecto" }
  @{ n="08 action ajena";                            body=(New-Body -Action "reserva.detalle");               ok=$false; code="accion_desconocida" }
  @{ n="09 payload reject-unknown (clave extra)";    body=(New-Body -PayloadOverride @{ foo="x" });           ok=$false; code="payload_invalido" }
  @{ n="10 actor fuera de enum";                     body=(New-Body -Actor "intruso");                        ok=$false; code="payload_invalido" }
  @{ n="11 fecha imposible 2027-02-30";              body=(New-Body -PayloadOverride @{ fecha_in="2027-02-30" }); ok=$false; code="payload_invalido" }
  @{ n="12 hora fuera de rango 99:99";               body=(New-Body -PayloadOverride @{ hora_checkin_solicitada="99:99" }); ok=$false; code="payload_invalido" }
)

Write-Host "`n=== BLOQUE 1: SMOKES DE SEGURIDAD A07.2 (sin escritura) ===" -ForegroundColor Cyan
Write-Host "URL: $BaseUrl/$Path`n"
$pass = 0; $total = $cases.Count
foreach ($c in $cases) {
  $resp = Invoke-A07 -BodyObj $c.body -BadSig:([bool]$c.badsig)
  $gotOk   = [bool]$resp.ok
  $gotCode = if ($resp.error) { $resp.error.code } else { "<sin error>" }
  $okMatch = ($gotOk -eq $c.ok) -and ($gotCode -eq $c.code)
  if ($okMatch) { $pass++; Write-Host ("  [PASS] {0}" -f $c.n) -ForegroundColor Green }
  else { Write-Host ("  [FAIL] {0}  -> ok={1} code={2} (esperado ok={3} code={4})" -f $c.n,$gotOk,$gotCode,$c.ok,$c.code) -ForegroundColor Red }
}
$col = if ($pass -eq $total) { "Green" } else { "Red" }
Write-Host ("`nRESULTADO: {0}/{1} PASS" -f $pass,$total) -ForegroundColor $col
Write-Host "NOTA: ninguno de estos casos escribe. Corre el gate residual igual antes del Bloque 3.`n"
if ($pass -ne $total) { exit 1 }
