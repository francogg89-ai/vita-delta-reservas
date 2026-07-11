# ============================================================================
# CC_L3_GW_smoke.ps1 -- SMOKE VIA GATEWAY (portal-api -> wrappers A30/A31 -> L3)
# Acciones: cuenta_corriente.historico y cuenta_corriente.historico_acumulados (LECTURA, socio-only).
# End-to-end con JWT real. Prueba el objetivo del Bloque 0: gateway -> wrapper -> L3.
#
# El gateway firma HMAC hacia n8n server-side: este harness NUNCA ve el secreto HMAC. Envia
# { action, payload } y JWT. Cubre: A02 (visibilidad por rol via CATALOG), negativos de rol,
# payloads invalidos rebotados EN EL GATEWAY, y AMBOS caminos end-to-end de A30 (foto pre-extension
# y mes sin foto) de forma BLOQUEANTE: no puede terminar verde sin ejecutar asserts exitosos.
#
# Data-resiliente: NO hardcodea cantidad de periodos/socios/movimientos ni el mes sin foto.
# ASCII PURO (PS 5.1 / CP1252). NO toca OPS. NO escribe (lecturas puras: 0 mutacion).
# Codigo de salida: 0 si todos los asserts pasan; 1 si hay >=1 falla o falta config (env/JWT).
#
# Requisitos (env vars): VITA_SUPABASE_URL_TEST, VITA_SUPABASE_ANON_TEST,
#   VITA_PW_FRANCO (socio), VITA_PW_VICKY, VITA_PW_JENNY.
# Correr con los wrappers A30/A31 ACTIVOS y el gateway A31 (TEST) desplegado.
# Uso:  powershell -ExecutionPolicy Bypass -File .\CC_L3_GW_smoke.ps1
# ============================================================================
param(
  [string]$SupabaseUrl = $env:VITA_SUPABASE_URL_TEST,
  [string]$AnonKey     = $env:VITA_SUPABASE_ANON_TEST
)
$ErrorActionPreference = "Stop"
if ([string]::IsNullOrEmpty($SupabaseUrl)) { Write-Host "ABORT: setea VITA_SUPABASE_URL_TEST" -ForegroundColor Red; exit 1 }
if ([string]::IsNullOrEmpty($AnonKey))     { Write-Host "ABORT: setea VITA_SUPABASE_ANON_TEST" -ForegroundColor Red; exit 1 }
$SupabaseUrl = $SupabaseUrl.TrimEnd('/')
$fnUrl  = "$SupabaseUrl/functions/v1/portal-api"
$ACT_H  = 'cuenta_corriente.historico'
$ACT_A  = 'cuenta_corriente.historico_acumulados'
$Piso   = '2026-07-01'

$script:passed = 0
$script:failed = 0
$script:fails  = @()
$script:codes  = @{}
$ALLOWLIST = @('payload_invalido','no_autorizado','rol_no_permitido','accion_desconocida','no_encontrado','conflicto','error_entorno','error_interno','estado_incierto','firma_invalida','ts_fuera_de_ventana','raw_body_ausente','ambiente_incorrecto')

function Get-Jwt {
  param($email, $pw)
  if ([string]::IsNullOrEmpty($pw)) { return $null }
  $body = @{ email = $email; password = $pw } | ConvertTo-Json -Compress
  try {
    $r = Invoke-RestMethod -Uri "$SupabaseUrl/auth/v1/token?grant_type=password" -Method Post -Headers @{ apikey = $AnonKey } -ContentType 'application/json' -Body $body
    return $r.access_token
  } catch { return $null }
}
function Invoke-GwRaw {
  param([hashtable]$Body, $Jwt = $null)
  $json = $Body | ConvertTo-Json -Compress -Depth 10
  $headers = @{ apikey = $AnonKey }
  if ($Jwt) { $headers['Authorization'] = "Bearer $Jwt" }
  try {
    return Invoke-RestMethod -Uri $fnUrl -Method Post -Headers $headers -ContentType 'application/json' -Body $json
  } catch {
    $resp = $_.Exception.Response
    if ($resp) {
      $sr = New-Object System.IO.StreamReader($resp.GetResponseStream())
      $t = $sr.ReadToEnd(); $sr.Close()
      try { return ($t | ConvertFrom-Json) } catch { return [pscustomobject]@{ ok = $false; error = [pscustomobject]@{ code = '__http_error__'; message = $t } } }
    }
    return [pscustomobject]@{ ok = $false; error = [pscustomobject]@{ code = '__network_error__'; message = $_.Exception.Message } }
  }
}
# New-Body: sin Payload -> body sin clave payload (omitido). Con Payload (incl. $null) -> la incluye.
function New-Body { param([string]$Action, $Payload) if ($PSBoundParameters.ContainsKey('Payload')) { return @{ action = $Action; payload = $Payload } } else { return @{ action = $Action } } }
function Get-Code { param($r) if ($r -and ($r.ok -eq $false) -and $r.error) { return $r.error.code } return $null }
function Track   { param($r) $c = Get-Code $r; if ($null -ne $c) { $script:codes[$c] = $true } }
function Record  {
  param($name, $ok, $detail)
  if ($ok) { $script:passed++; Write-Host "PASS  $name" -ForegroundColor Green }
  else { $script:failed++; $script:fails += "$name :: $detail"; Write-Host "FAIL  $name  ($detail)" -ForegroundColor Red }
}
function Assert-Code {
  param($r, $name, $expected)
  Track $r
  $c = Get-Code $r
  $ok = ($r.ok -eq $false) -and ($c -eq $expected)
  Record $name $ok "esperaba ok:false code=$expected; obtuve ok=$($r.ok) code=$c"
}
function Assert-OkData {
  param($r, $name, [scriptblock]$Check = $null)
  Track $r
  $ok = ($r.ok -eq $true) -and ($null -ne $r.data)
  if ($ok -and $Check) { $ok = [bool](& $Check $r.data) }
  Record $name $ok "esperaba ok:true + data valida; obtuve ok=$($r.ok) code=$(Get-Code $r)"
}
function Assert-AllowlistMeta {
  $bad = @(); foreach ($c in $script:codes.Keys) { if ($ALLOWLIST -notcontains $c) { $bad += $c } }
  Record "META allowlist (todos los error.code en la allowlist)" (@($bad).Count -eq 0) ("fuera de allowlist: " + ($bad -join ', '))
}
function HasKey { param($obj, $name); if ($null -eq $obj) { return $false }; return ($obj.PSObject.Properties.Name -contains $name) }
function Is-Arr { param($v); return ($v -is [System.Array]) }
function Ymd { param($v); if ($null -eq $v) { return $null }; $s = [string]$v; if ($s.Length -ge 10) { return $s.Substring(0,10) } return $s }
function Add-Months { param([string]$ymd, [int]$n); $d = [datetime]::ParseExact($ymd,'yyyy-MM-dd',$null); return $d.AddMonths($n).ToString('yyyy-MM-01') }
function AccionesDe { param($r); if ($r -and $r.ok -eq $true -and $r.data -and (HasKey $r.data 'acciones')) { return @($r.data.acciones) } return @() }

$KEYS14 = @('sin_foto','detalle_disponible','detalle_motivo','periodo','cabecera','cascada','socios','participacion','gastos','incidencias','movimientos','matriz_por_socio','gastos_sin_incidencia','retribucion_operativo')
$LIST8  = @('cascada','socios','participacion','gastos','incidencias','movimientos','matriz_por_socio','gastos_sin_incidencia')
$FINE5  = @('participacion','gastos','incidencias','matriz_por_socio','gastos_sin_incidencia')
$KEYS6  = @('sin_datos','piso','totales','evolucion','saldos_por_socio','meta')
function Has14 { param($d); foreach ($k in $KEYS14) { if (-not (HasKey $d $k)) { return $false } }; return $true }
function Has6  { param($d); foreach ($k in $KEYS6)  { if (-not (HasKey $d $k)) { return $false } }; return $true }
function AllEmpty {
  param($d, $keys)
  foreach ($k in $keys) {
    if (-not (Is-Arr $d.$k)) { return $false }
    if (@($d.$k).Count -ne 0) { return $false }
  }
  return $true
}

# ---------- JWTs ----------
$jwtFranco = Get-Jwt 'franco@vitadelta.test' $env:VITA_PW_FRANCO
$jwtVicky  = Get-Jwt 'vicky@vitadelta.test'  $env:VITA_PW_VICKY
$jwtJenny  = Get-Jwt 'jenny@vitadelta.test'  $env:VITA_PW_JENNY
if (-not $jwtFranco -or -not $jwtVicky -or -not $jwtJenny) {
  Write-Host "ABORT: no se pudieron obtener los 3 JWT (franco/vicky/jenny). Revisar passwords/env." -ForegroundColor Red
  exit 1
}

Write-Host ""
Write-Host "=== L3 GATEWAY SMOKE (historico + acumulados) ===" -ForegroundColor Cyan

# ==========================================================================
# A02 -- visibilidad por rol (CATALOG filter; sin logica nueva)
# ==========================================================================
Write-Host "`n----- A02 (sesion.contexto) -----" -ForegroundColor Magenta
$ctxF = Invoke-GwRaw -Body (New-Body 'sesion.contexto') -Jwt $jwtFranco
$ctxV = Invoke-GwRaw -Body (New-Body 'sesion.contexto') -Jwt $jwtVicky
$ctxJ = Invoke-GwRaw -Body (New-Body 'sesion.contexto') -Jwt $jwtJenny
# Bloqueantes: las 3 llamadas exitosas + rol esperado (una respuesta fallida/vacia no puede aprobar por ausencia de acciones).
Record "A02-0A contexto socio ok:true" ($ctxF.ok -eq $true) "sesion.contexto socio fallo"
Record "A02-0B contexto vicky ok:true" ($ctxV.ok -eq $true) "sesion.contexto vicky fallo"
Record "A02-0C contexto jenny ok:true" ($ctxJ.ok -eq $true) "sesion.contexto jenny fallo"
Record "A02-0D rol socio correcto" ($ctxF.data.rol -eq 'socio') "rol inesperado"
Record "A02-0E rol vicky correcto" ($ctxV.data.rol -eq 'vicky') "rol inesperado"
Record "A02-0F rol jenny correcto" ($ctxJ.data.rol -eq 'jenny') "rol inesperado"
$accF = AccionesDe $ctxF; $accV = AccionesDe $ctxV; $accJ = AccionesDe $ctxJ
Write-Host ("    [obs] socio ve " + $accF.Count + " acciones; vicky " + $accV.Count + "; jenny " + $accJ.Count) -ForegroundColor DarkGray
Record "A02-1 socio ve cuenta_corriente.historico"            ($accF -contains $ACT_H) "no aparece en acciones de socio"
Record "A02-2 socio ve cuenta_corriente.historico_acumulados" ($accF -contains $ACT_A) "no aparece en acciones de socio"
Record "A02-3 vicky NO ve historico"            (-not ($accV -contains $ACT_H)) "vicky no deberia verla"
Record "A02-4 vicky NO ve historico_acumulados" (-not ($accV -contains $ACT_A)) "vicky no deberia verla"
Record "A02-5 jenny NO ve historico"            (-not ($accJ -contains $ACT_H)) "jenny no deberia verla"
Record "A02-6 jenny NO ve historico_acumulados" (-not ($accJ -contains $ACT_A)) "jenny no deberia verla"

# ==========================================================================
# SEGURIDAD / negativos de rol (el gateway rebota ANTES de despachar a n8n)
# ==========================================================================
Write-Host "`n----- SEGURIDAD (roles) -----" -ForegroundColor Magenta
Assert-Code (Invoke-GwRaw -Body (New-Body $ACT_H @{ mes = $Piso }) -Jwt $jwtVicky) 'S1 historico vicky -> rol_no_permitido' 'rol_no_permitido'
Assert-Code (Invoke-GwRaw -Body (New-Body $ACT_H @{ mes = $Piso }) -Jwt $jwtJenny) 'S2 historico jenny -> rol_no_permitido' 'rol_no_permitido'
Assert-Code (Invoke-GwRaw -Body (New-Body $ACT_H @{ mes = $Piso }) -Jwt $null)      'S3 historico sin JWT -> no_autorizado' 'no_autorizado'
Assert-Code (Invoke-GwRaw -Body (New-Body $ACT_A @{}) -Jwt $jwtVicky) 'S4 acumulados vicky -> rol_no_permitido' 'rol_no_permitido'
Assert-Code (Invoke-GwRaw -Body (New-Body $ACT_A @{}) -Jwt $jwtJenny) 'S5 acumulados jenny -> rol_no_permitido' 'rol_no_permitido'
Assert-Code (Invoke-GwRaw -Body (New-Body $ACT_A @{}) -Jwt $null)      'S6 acumulados sin JWT -> no_autorizado' 'no_autorizado'
Assert-Code (Invoke-GwRaw -Body @{ action = 'cuenta_corriente.historico_fantasma'; payload = @{} } -Jwt $jwtFranco) 'S7 accion inexistente -> accion_desconocida' 'accion_desconocida'

# ==========================================================================
# PAYLOAD invalido rebotado EN EL GATEWAY (validators espejo)
# ==========================================================================
Write-Host "`n----- PAYLOAD (gateway) -----" -ForegroundColor Magenta
Assert-Code (Invoke-GwRaw -Body (New-Body $ACT_H @{}) -Jwt $jwtFranco)                     'P1 historico sin mes -> payload_invalido' 'payload_invalido'
Assert-Code (Invoke-GwRaw -Body (New-Body $ACT_H @{ mes = '2026-07-15' }) -Jwt $jwtFranco) 'P2 historico dia != 01 -> payload_invalido' 'payload_invalido'
Assert-Code (Invoke-GwRaw -Body (New-Body $ACT_H @{ mes = '2026-05-01' }) -Jwt $jwtFranco) 'P3 historico pre-piso -> payload_invalido' 'payload_invalido'
Assert-Code (Invoke-GwRaw -Body (New-Body $ACT_H @{ mes = $Piso; foo = 1 }) -Jwt $jwtFranco) 'P4 historico clave extra -> payload_invalido' 'payload_invalido'
Assert-Code (Invoke-GwRaw -Body @{ action = $ACT_H; payload = 'no-soy-objeto' } -Jwt $jwtFranco) 'P5 historico payload string -> payload_invalido' 'payload_invalido'
Assert-Code (Invoke-GwRaw -Body (New-Body $ACT_A @{ foo = 1 }) -Jwt $jwtFranco) 'P6 acumulados {foo:1} -> payload_invalido' 'payload_invalido'
Assert-Code (Invoke-GwRaw -Body @{ action = $ACT_A; payload = @(1,2) } -Jwt $jwtFranco) 'P7 acumulados array -> payload_invalido' 'payload_invalido'
Assert-Code (Invoke-GwRaw -Body @{ action = $ACT_A; payload = 'x' } -Jwt $jwtFranco) 'P8 acumulados string -> payload_invalido' 'payload_invalido'
Assert-OkData (Invoke-GwRaw -Body (New-Body $ACT_A @{}) -Jwt $jwtFranco) 'P9 acumulados {} -> ok:true' { param($d) $null -ne $d }
Assert-OkData (Invoke-GwRaw -Body (New-Body $ACT_A) -Jwt $jwtFranco) 'P10 acumulados payload omitido -> ok:true' { param($d) $null -ne $d }
Assert-OkData (Invoke-GwRaw -Body (New-Body $ACT_A $null) -Jwt $jwtFranco) 'P11 acumulados payload null -> ok:true' { param($d) $null -ne $d }

# ==========================================================================
# FUNCIONAL acumulados (invariantes)
# ==========================================================================
Write-Host "`n----- FUNCIONAL acumulados -----" -ForegroundColor Magenta
$acc = Invoke-GwRaw -Body (New-Body $ACT_A @{}) -Jwt $jwtFranco
$evo = @()
if ($acc.ok -and $acc.data) { foreach ($e in @($acc.data.evolucion)) { $evo += (Ymd $e.periodo) } }
Write-Host ("    [obs] periodos vigentes: " + $(if ($evo.Count) { $evo -join ', ' } else { '(ninguno)' })) -ForegroundColor DarkGray
Assert-OkData $acc 'FA1 acumulados 6 claves' { param($d) Has6 $d }
Assert-OkData $acc 'FA2 evolucion/saldos arrays; totales/meta objetos' { param($d) (Is-Arr $d.evolucion) -and (Is-Arr $d.saldos_por_socio) -and ($null -ne $d.totales) -and ($null -ne $d.meta) }
Assert-OkData $acc 'FA3 piso == 2026-07-01' { param($d) (Ymd $d.piso) -eq $Piso }
Assert-OkData $acc 'FA4 evolucion ordenada asc' { param($d) $ps=@(); foreach ($e in @($d.evolucion)) { $ps += (Ymd $e.periodo) }; $s=$true; for ($i=1;$i -lt $ps.Count;$i++){ if ($ps[$i] -lt $ps[$i-1]){$s=$false} }; $s }
Assert-OkData $acc 'FA5 meta.fotos_vigentes == evolucion.length' { param($d) ([int]$d.meta.fotos_vigentes) -eq (@($d.evolucion).Count) }

# ==========================================================================
# FUNCIONAL historico -- AMBOS CAMINOS BLOQUEANTES (foto pre-extension + mes sin foto)
# ==========================================================================
Write-Host "`n----- FUNCIONAL historico (gateway -> wrapper -> L3) -----" -ForegroundColor Magenta
# $MesPreExtension EXCLUSIVA: primer periodo vigente con triple condicion.
$MesPreExtension = $null
foreach ($p in $evo) {
  $pr = Invoke-GwRaw -Body (New-Body $ACT_H @{ mes = $p }) -Jwt $jwtFranco
  if ($pr.ok -and $pr.data -and ($pr.data.sin_foto -eq $false) -and ($pr.data.detalle_disponible -eq $false) -and ($pr.data.detalle_motivo -eq 'foto_pre_extension')) { $MesPreExtension = $p; break }
}
# $MesSinFoto: primer gap >= piso.
$MesSinFoto = $null; $cand = $Piso
for ($i = 0; $i -lt 120; $i++) { if ($evo -notcontains $cand) { $MesSinFoto = $cand; break }; $cand = Add-Months $cand 1 }
Write-Host ("    [obs] MesPreExtension=" + $MesPreExtension + "  MesSinFoto=" + $MesSinFoto) -ForegroundColor DarkGray

# Derivaciones BLOQUEANTES: no puede terminar verde sin ambos caminos.
Record "FH-DERIV-1 foto pre-extension vigente hallada" ($null -ne $MesPreExtension) "no se hallo foto pre-extension vigente via gateway"
Record "FH-DERIV-2 mes sin foto hallado" ($null -ne $MesSinFoto) "no se hallo gap >= piso en 120 meses"

# Camino 1: foto pre-extension
if ($MesPreExtension) {
  $rH = Invoke-GwRaw -Body (New-Body $ACT_H @{ mes = $MesPreExtension }) -Jwt $jwtFranco
  Assert-OkData $rH "FH1 foto: ok:true + 14 claves" { param($d) Has14 $d }
  Assert-OkData $rH "FH2 foto: periodo round-trip ($MesPreExtension)" { param($d) (Ymd $d.periodo) -eq $MesPreExtension }
  Assert-OkData $rH "FH3 foto: sin_foto=false" { param($d) $d.sin_foto -eq $false }
  Assert-OkData $rH "FH4 foto: detalle_disponible=false + detalle_motivo=foto_pre_extension" { param($d) ($d.detalle_disponible -eq $false) -and ($d.detalle_motivo -eq 'foto_pre_extension') }
  Assert-OkData $rH "FH5 foto: detalle fino vacio" { param($d) AllEmpty $d $FINE5 }
  Assert-OkData $rH "FH6 foto: cabecera/cascada/socios/retribucion presentes" { param($d) ($null -ne $d.cabecera) -and (@($d.cascada).Count -gt 0) -and (@($d.socios).Count -gt 0) -and ($null -ne $d.retribucion_operativo) }
}
# Camino 2: mes sin foto
if ($MesSinFoto) {
  $rN = Invoke-GwRaw -Body (New-Body $ACT_H @{ mes = $MesSinFoto }) -Jwt $jwtFranco
  Assert-OkData $rN "FH7 sin foto: ok:true + 14 claves" { param($d) Has14 $d }
  Assert-OkData $rN "FH8 sin foto: sin_foto=true" { param($d) $d.sin_foto -eq $true }
  Assert-OkData $rN "FH9 sin foto: detalle_motivo=sin_foto_vigente" { param($d) $d.detalle_motivo -eq 'sin_foto_vigente' }
  Assert-OkData $rN "FH10 sin foto: 8 secciones vacias" { param($d) AllEmpty $d $LIST8 }
  Assert-OkData $rN "FH11 sin foto: cabecera null y retribucion null" { param($d) ($null -eq $d.cabecera) -and ($null -eq $d.retribucion_operativo) }
  Assert-OkData $rN "FH12 sin foto: periodo round-trip ($MesSinFoto)" { param($d) (Ymd $d.periodo) -eq $MesSinFoto }
}

Assert-AllowlistMeta

Write-Host "`n===== RESUMEN =====" -ForegroundColor Magenta
Write-Host ("PASSED: " + $script:passed) -ForegroundColor Green
Write-Host ("FAILED: " + $script:failed) -ForegroundColor Red
if ($script:failed -gt 0) { Write-Host "`nFallos:" -ForegroundColor Red; foreach ($f in $script:fails) { Write-Host ("  - " + $f) -ForegroundColor Red } }

if ($script:failed -gt 0) { exit 1 }
exit 0
