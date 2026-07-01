#Requires -Version 5.1
# ============================================================================
# A26_GW_smoke_OPS.ps1
# OPS-B: smoke GATEWAY read-only de A26 (disponibilidad.cabana) contra portal-api OPS.
# SOLO OPS. Cadena: gateway -> allowlist(rol) -> validate -> HMAC server-side -> wrapper
# n8n __OPS -> motor OPS. Este harness NUNCA ve el secreto HMAC (lo firma el gateway).
#
# GUARD DE ENTORNO (antes de pedir credenciales o autenticar): SupabaseUrl y GatewayUrl
# deben contener el ref de OPS (lpiatqztudxiwdlcoasv) y GatewayUrl apuntar a
# /functions/v1/portal-api. Si no, FRENAR con exit 3 (evita evidencia invalida).
#
# READ-ONLY (D-PROMO-09): disponibilidad.cabana es lectura pura. Cero escrituras,
# cero secuencias, cero reservas/bloqueos/pagos. No se invoca ninguna accion de escritura.
#
# SECRETOS: nada hardcodeado, nada por linea de comando, nada impreso (anon/passwords/JWT
# por env var o prompt seguro). PII: nunca se imprime el body; solo accion, status, ok,
# error.code y conteo de dias (los estados de disponibilidad no son PII).
#
# Variables de entorno (modo no interactivo):
#   VITA_OPS_SUPABASE_URL   ej: https://lpiatqztudxiwdlcoasv.supabase.co
#   VITA_OPS_GATEWAY_URL    ej: https://lpiatqztudxiwdlcoasv.supabase.co/functions/v1/portal-api
#   VITA_OPS_ANON           anon key OPS (publica por diseno; no se imprime)
#   VITA_OPS_VICKY_EMAIL / VITA_OPS_VICKY_PASS
#   VITA_OPS_SOCIO_EMAIL / VITA_OPS_SOCIO_PASS   (franco | rodrigo | remo)
#   VITA_OPS_JENNY_EMAIL / VITA_OPS_JENNY_PASS
#
# Parametros opcionales (de [A] del oraculo OPS):
#   -CabValida <int>   cabana ACTIVA en OPS (default 1)
#   -CabInvalida <int> id positivo SIN cabana activa (default 999999)
#
# Exit codes: 0 = VERDE | 1 = algun chequeo en rojo | 2 = login fallido | 3 = guard OPS.
# ============================================================================

[CmdletBinding()]
param(
  [string]$SupabaseUrl = $env:VITA_OPS_SUPABASE_URL,
  [string]$GatewayUrl  = $env:VITA_OPS_GATEWAY_URL,
  [int]$CabValida      = 1,
  [int]$CabInvalida    = 999999
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ACT = 'disponibilidad.cabana'
# Allowlist de error.code que el GATEWAY puede emitir para esta accion (META).
$ALLOW = @('no_autorizado','rol_no_permitido','accion_desconocida','payload_invalido',
           'no_encontrado','error_entorno','estado_incierto','error_interno')

# Ventana presuntamente LIBRE (lejos en el futuro): para los OK sin depender de ocupacion.
$LibreDesde = (Get-Date).Date.AddDays(400).ToString('yyyy-MM-dd')
$LibreHasta = (Get-Date).Date.AddDays(405).ToString('yyyy-MM-dd')

$script:PASS = 0; $script:FAIL = 0
$script:Codes = New-Object System.Collections.ArrayList

function Record {
  param([string]$Name, [bool]$Ok, [string]$Detail)
  if ($Ok) { $script:PASS++; $tag = 'PASS' } else { $script:FAIL++; $tag = 'FAIL' }
  Write-Host ('{0}  {1}  {2}' -f $tag, $Name.PadRight(52), $Detail)
}

# ---- Secretos: env var o prompt seguro. Nunca se imprime. -------------------
function ConvertTo-Plain {
  param([System.Security.SecureString]$Secure)
  $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
  try { return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
  finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}
function Resolve-Secret {
  param([string]$EnvName, [string]$Prompt, [switch]$Secure)
  $v = [Environment]::GetEnvironmentVariable($EnvName, 'Process')
  if ([string]::IsNullOrEmpty($v)) { $v = [Environment]::GetEnvironmentVariable($EnvName, 'User') }
  if (-not [string]::IsNullOrEmpty($v)) { return $v }
  if ($Secure) { $ss = Read-Host -AsSecureString -Prompt $Prompt; return (ConvertTo-Plain $ss) }
  return (Read-Host -Prompt $Prompt)
}

# ---- HTTP JSON: { Status, Body } sin lanzar en 4xx/5xx (el gateway usa 200 + envelope).
function Invoke-Json {
  param([string]$Method, [string]$Uri, [hashtable]$Headers, $BodyObj)
  $bytes = $null
  if ($null -ne $BodyObj) {
    $json = $BodyObj | ConvertTo-Json -Depth 8 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
  }
  try {
    $resp = Invoke-WebRequest -Method $Method -Uri $Uri -Headers $Headers -Body $bytes `
              -ContentType 'application/json; charset=utf-8' -UseBasicParsing -TimeoutSec 30
    $body = $null
    if (-not [string]::IsNullOrEmpty($resp.Content)) { try { $body = $resp.Content | ConvertFrom-Json } catch { $body = $null } }
    return [pscustomobject]@{ Status = [int]$resp.StatusCode; Body = $body }
  } catch [System.Net.WebException] {
    $r = $_.Exception.Response
    if ($null -ne $r) {
      $code = [int]$r.StatusCode; $raw = ''
      try { $sr = New-Object System.IO.StreamReader($r.GetResponseStream()); $raw = $sr.ReadToEnd(); $sr.Close() } catch { }
      $body = $null
      if (-not [string]::IsNullOrEmpty($raw)) { try { $body = $raw | ConvertFrom-Json } catch { } }
      return [pscustomobject]@{ Status = $code; Body = $body }
    }
    return [pscustomobject]@{ Status = -1; Body = $null }
  }
}

function Test-Prop { param($Obj, [string]$Name); if ($null -eq $Obj) { return $false }; return (($Obj.PSObject.Properties.Name) -contains $Name) }

# ---- Login Supabase Auth -> JWT. No imprime email/password/token. -----------
function Get-Jwt {
  param([string]$Email, [string]$PlainPass)
  $uri = ('{0}/auth/v1/token?grant_type=password' -f $script:SupabaseUrl.TrimEnd('/'))
  $headers = @{ apikey = $script:AnonKey }
  $r = Invoke-Json -Method 'POST' -Uri $uri -Headers $headers -BodyObj @{ email = $Email; password = $PlainPass }
  if ($r.Status -eq 200 -and (Test-Prop $r.Body 'access_token') -and -not [string]::IsNullOrEmpty($r.Body.access_token)) { return $r.Body.access_token }
  throw ('login fallo (status {0})' -f $r.Status)
}

# ---- Llamada A26 al gateway. Devuelve solo metadata (sin valores del body). --
# DiasCount = cantidad de dias (no es PII); -1 si data.dias no esta presente.
function Invoke-A26 {
  param([string]$Jwt, $PayloadObj, [switch]$NoAuth)
  $headers = @{}
  if (-not $NoAuth) { $headers = @{ Authorization = ('Bearer {0}' -f $Jwt) } }
  $r = Invoke-Json -Method 'POST' -Uri $script:GatewayUrl -Headers $headers -BodyObj @{ action = $ACT; payload = $PayloadObj }
  $ok = $false; $code = ''; $dias = -1
  if ($null -ne $r.Body) {
    if (Test-Prop $r.Body 'ok') { $ok = [bool]$r.Body.ok }
    if (-not $ok -and (Test-Prop $r.Body 'error') -and (Test-Prop $r.Body.error 'code')) {
      $code = [string]$r.Body.error.code
      $null = $script:Codes.Add($code)
    }
    if ($ok -and (Test-Prop $r.Body 'data') -and (Test-Prop $r.Body.data 'dias')) { $dias = @($r.Body.data.dias).Count }
  }
  return [pscustomobject]@{ Status = $r.Status; Ok = $ok; Code = $code; Dias = $dias }
}

# Variante: el gateway con un body que NO es objeto (array). Mismo metadata.
function Invoke-A26Raw {
  param([string]$Jwt, $BodyObj)
  $headers = @{ Authorization = ('Bearer {0}' -f $Jwt) }
  $r = Invoke-Json -Method 'POST' -Uri $script:GatewayUrl -Headers $headers -BodyObj $BodyObj
  $ok = $false; $code = ''
  if ($null -ne $r.Body) {
    if (Test-Prop $r.Body 'ok') { $ok = [bool]$r.Body.ok }
    if (-not $ok -and (Test-Prop $r.Body 'error') -and (Test-Prop $r.Body.error 'code')) { $code = [string]$r.Body.error.code; $null = $script:Codes.Add($code) }
  }
  return [pscustomobject]@{ Status = $r.Status; Ok = $ok; Code = $code }
}

# ===========================================================================
# 0. Config + GUARD DE ENTORNO (antes de credenciales).
# ===========================================================================
Write-Host '============================================================'
Write-Host 'A26 smoke GATEWAY OPS (disponibilidad.cabana, read-only)'
Write-Host '============================================================'

if ([string]::IsNullOrEmpty($SupabaseUrl)) { $SupabaseUrl = Resolve-Secret -EnvName 'VITA_OPS_SUPABASE_URL' -Prompt 'Supabase URL OPS' }
if ([string]::IsNullOrEmpty($GatewayUrl))  { $GatewayUrl  = Resolve-Secret -EnvName 'VITA_OPS_GATEWAY_URL'  -Prompt 'Gateway URL (portal-api OPS)' }
$script:SupabaseUrl = $SupabaseUrl
$script:GatewayUrl  = $GatewayUrl

$OPS_REF = 'lpiatqztudxiwdlcoasv'
$guardErrores = @()
if ($script:SupabaseUrl -notlike ('*{0}*' -f $OPS_REF)) { $guardErrores += ('SupabaseUrl no contiene el ref de OPS ({0})' -f $OPS_REF) }
if ($script:GatewayUrl  -notlike ('*{0}*' -f $OPS_REF)) { $guardErrores += ('GatewayUrl no contiene el ref de OPS ({0})' -f $OPS_REF) }
if ($script:GatewayUrl  -notlike '*/functions/v1/portal-api*') { $guardErrores += 'GatewayUrl no apunta a /functions/v1/portal-api' }
if (@($guardErrores).Count -gt 0) {
  Write-Host ''
  Write-Host 'FRENAR: el guard de entorno OPS fallo. NO se intenta login.'
  foreach ($e in $guardErrores) { Write-Host ('  - {0}' -f $e) }
  exit 3
}
Write-Host ('Guard OPS: OK (ref {0} + gateway /functions/v1/portal-api).' -f $OPS_REF)

$script:AnonKey = Resolve-Secret -EnvName 'VITA_OPS_ANON' -Prompt 'anon key OPS' -Secure
$vickyEmail = Resolve-Secret -EnvName 'VITA_OPS_VICKY_EMAIL' -Prompt 'email vicky'
$vickyPass  = Resolve-Secret -EnvName 'VITA_OPS_VICKY_PASS'  -Prompt 'password vicky' -Secure
$socioEmail = Resolve-Secret -EnvName 'VITA_OPS_SOCIO_EMAIL' -Prompt 'email socio (franco/rodrigo/remo)'
$socioPass  = Resolve-Secret -EnvName 'VITA_OPS_SOCIO_PASS'  -Prompt 'password socio' -Secure
$jennyEmail = Resolve-Secret -EnvName 'VITA_OPS_JENNY_EMAIL' -Prompt 'email jenny'
$jennyPass  = Resolve-Secret -EnvName 'VITA_OPS_JENNY_PASS'  -Prompt 'password jenny' -Secure

Write-Host ('Gateway: {0} | accion: {1} | cabana valida: {2} | invalida: {3}' -f $script:GatewayUrl, $ACT, $CabValida, $CabInvalida)
Write-Host ''

try {
  $jwtVicky = Get-Jwt -Email $vickyEmail -PlainPass $vickyPass
  $jwtSocio = Get-Jwt -Email $socioEmail -PlainPass $socioPass
  $jwtJenny = Get-Jwt -Email $jennyEmail -PlainPass $jennyPass
} catch {
  Write-Host ('ERROR de login: {0}' -f $_.Exception.Message)
  Write-Host 'FRENAR: no se pudo autenticar (credenciales/anon/url no se imprimen).'
  exit 2
}
Write-Host 'Login OK para vicky / socio / jenny (JWT obtenido; no se imprime).'
Write-Host ''

# ===========================================================================
# Casos
# ===========================================================================
Write-Host '----- roles / auth -----'
# 1. vicky OK
$r = Invoke-A26 -Jwt $jwtVicky -PayloadObj @{ id_cabana = $CabValida; fecha_desde = $LibreDesde; fecha_hasta = $LibreHasta }
Record '1. vicky -> ok:true + data.dias no vacio' ($r.Ok -and $r.Dias -gt 0) ('status={0} ok={1} dias={2}' -f $r.Status, $r.Ok, $r.Dias)

# 2. socio OK
$r = Invoke-A26 -Jwt $jwtSocio -PayloadObj @{ id_cabana = $CabValida; fecha_desde = $LibreDesde; fecha_hasta = $LibreHasta }
Record '2. socio -> ok:true + data.dias no vacio' ($r.Ok -and $r.Dias -gt 0) ('status={0} ok={1} dias={2}' -f $r.Status, $r.Ok, $r.Dias)

# 3. jenny -> rol_no_permitido
$r = Invoke-A26 -Jwt $jwtJenny -PayloadObj @{ id_cabana = $CabValida; fecha_desde = $LibreDesde; fecha_hasta = $LibreHasta }
Record '3. jenny -> rol_no_permitido' ((-not $r.Ok) -and $r.Code -eq 'rol_no_permitido') ('status={0} code={1}' -f $r.Status, $r.Code)

# 4. sin JWT -> no_autorizado
$r = Invoke-A26 -NoAuth -PayloadObj @{ id_cabana = $CabValida; fecha_desde = $LibreDesde; fecha_hasta = $LibreHasta }
Record '4. sin JWT -> no_autorizado' ((-not $r.Ok) -and $r.Code -eq 'no_autorizado') ('status={0} code={1}' -f $r.Status, $r.Code)

Write-Host ''
Write-Host '----- action / no_encontrado -----'
# 5. action inexistente -> accion_desconocida
$r = Invoke-A26Raw -Jwt $jwtVicky -BodyObj @{ action = 'accion.que.no.existe'; payload = @{} }
Record '5. action inexistente -> accion_desconocida' ((-not $r.Ok) -and $r.Code -eq 'accion_desconocida') ('status={0} code={1}' -f $r.Status, $r.Code)

# 6. cabana inexistente -> no_encontrado
$r = Invoke-A26 -Jwt $jwtVicky -PayloadObj @{ id_cabana = $CabInvalida; fecha_desde = $LibreDesde; fecha_hasta = $LibreHasta }
Record '6. cabana inexistente -> no_encontrado' ((-not $r.Ok) -and $r.Code -eq 'no_encontrado') ('status={0} code={1}' -f $r.Status, $r.Code)

Write-Host ''
Write-Host '----- payloads invalidos (gateway valida antes de firmar) -----'
# 7. rango invertido
$r = Invoke-A26 -Jwt $jwtVicky -PayloadObj @{ id_cabana = $CabValida; fecha_desde = (Get-Date).Date.AddDays(20).ToString('yyyy-MM-dd'); fecha_hasta = (Get-Date).Date.AddDays(10).ToString('yyyy-MM-dd') }
Record '7. rango invertido -> payload_invalido' ((-not $r.Ok) -and $r.Code -eq 'payload_invalido') ('status={0} code={1}' -f $r.Status, $r.Code)

# 8. span > 366
$r = Invoke-A26 -Jwt $jwtVicky -PayloadObj @{ id_cabana = $CabValida; fecha_desde = (Get-Date).Date.AddDays(10).ToString('yyyy-MM-dd'); fecha_hasta = (Get-Date).Date.AddDays(410).ToString('yyyy-MM-dd') }
Record '8. span > 366 -> payload_invalido' ((-not $r.Ok) -and $r.Code -eq 'payload_invalido') ('status={0} code={1}' -f $r.Status, $r.Code)

# 9a/b/c. id_cabana 0 / negativo / string
$r = Invoke-A26 -Jwt $jwtVicky -PayloadObj @{ id_cabana = 0; fecha_desde = $LibreDesde; fecha_hasta = $LibreHasta }
Record '9a. id_cabana=0 -> payload_invalido' ((-not $r.Ok) -and $r.Code -eq 'payload_invalido') ('status={0} code={1}' -f $r.Status, $r.Code)
$r = Invoke-A26 -Jwt $jwtVicky -PayloadObj @{ id_cabana = -3; fecha_desde = $LibreDesde; fecha_hasta = $LibreHasta }
Record '9b. id_cabana negativo -> payload_invalido' ((-not $r.Ok) -and $r.Code -eq 'payload_invalido') ('status={0} code={1}' -f $r.Status, $r.Code)
$r = Invoke-A26 -Jwt $jwtVicky -PayloadObj @{ id_cabana = '1'; fecha_desde = $LibreDesde; fecha_hasta = $LibreHasta }
Record '9c. id_cabana string -> payload_invalido' ((-not $r.Ok) -and $r.Code -eq 'payload_invalido') ('status={0} code={1}' -f $r.Status, $r.Code)

# 10. clave desconocida
$r = Invoke-A26 -Jwt $jwtVicky -PayloadObj @{ id_cabana = $CabValida; fecha_desde = $LibreDesde; fecha_hasta = $LibreHasta; extra = 'x' }
Record '10. clave desconocida -> payload_invalido' ((-not $r.Ok) -and $r.Code -eq 'payload_invalido') ('status={0} code={1}' -f $r.Status, $r.Code)

# 11. falta fecha_hasta
$r = Invoke-A26 -Jwt $jwtVicky -PayloadObj @{ id_cabana = $CabValida; fecha_desde = $LibreDesde }
Record '11. falta fecha_hasta -> payload_invalido' ((-not $r.Ok) -and $r.Code -eq 'payload_invalido') ('status={0} code={1}' -f $r.Status, $r.Code)

# 12. payload array
$r = Invoke-A26 -Jwt $jwtVicky -PayloadObj @(1, 2, 3)
Record '12. payload array -> payload_invalido' ((-not $r.Ok) -and $r.Code -eq 'payload_invalido') ('status={0} code={1}' -f $r.Status, $r.Code)

Write-Host ''
Write-Host '----- META allowlist -----'
# 13. todos los error.code observados pertenecen a la allowlist
$fuera = @($script:Codes | Where-Object { $ALLOW -notcontains $_ } | Select-Object -Unique)
Record '13. META: error.code en allowlist' (@($fuera).Count -eq 0) ('codes_vistos=[{0}] fuera=[{1}]' -f (($script:Codes | Select-Object -Unique) -join ','), ($fuera -join ','))

# ===========================================================================
# Resumen
# ===========================================================================
Write-Host ''
Write-Host ('===== RESUMEN  PASS={0}  FAIL={1} =====' -f $script:PASS, $script:FAIL)
if ($script:FAIL -gt 0) { exit 1 } else { exit 0 }
