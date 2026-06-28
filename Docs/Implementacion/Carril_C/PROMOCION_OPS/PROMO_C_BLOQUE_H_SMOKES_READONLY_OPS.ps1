#Requires -Version 5.1
# ============================================================================
# PROMO_C_BLOQUE_H_SMOKES_READONLY_OPS.ps1
# Promocion Carril C a OPS - BLOQUE H.2: smokes read-only end-to-end por rol.
# SOLO OPS. Read-only del dominio de negocio.
#
# Que prueba (todo via gateway portal-api OPS, cadena gateway->allowlist->HMAC->
# wrapper n8n->motor OPS):
#   B1) sesion.contexto por los 3 roles -> menu correcto (acciones permitidas).
#   B2) una lectura por accion (cobertura de los 8 wrappers __OPS de lectura).
#   B3) allowlist: jenny rebota en economicos (rol_no_permitido).
#
# GUARD DE ENTORNO: este smoke SOLO corre contra OPS. Antes de pedir credenciales
# o autenticar, exige que SupabaseUrl y GatewayUrl contengan el ref de OPS
# (lpiatqztudxiwdlcoasv) y que GatewayUrl apunte a /functions/v1/portal-api. Si no,
# FRENAR con exit 3 sin intentar login (evita evidencia invalida contra TEST/otro).
#
# ANTI-OPS (D-PROMO-09): NO invoca ninguna de las 5 escrituras
# (reserva.crear_manual / bloqueo.crear_manual / cobranza.registrar_saldo[W10] /
#  cargar.gasto_interno / cobranza.registrar_cobro). Cero nextval, cero consumo
# de secuencias de reservas/pagos/gastos/idempotencia. Las lecturas son SELECT
# aguas abajo; las economicas devuelven vacio por el floor 2026-07-01 (D-NEG-02),
# lo cual es respuesta valida (se verifica forma, no contenido).
#
# W10 (cobranza.registrar_saldo): NUNCA se invoca. Si aparece en sesion.contexto
# es solo catalogo tecnico legado/deprecated; NO se trata como accion productiva
# validada. El gate de B1 para vicky/socio es por ALLOWLIST ESTRICTA: deben estar
# las 13 productivas y nada fuera del universo {13 productivas + W10}; cualquier
# accion extra inesperada -> FRENAR.
#
# Exit codes: 0 = VERDE (parcial o plena) | 1 = FRENAR (algun chequeo en rojo) |
#             2 = login fallido | 3 = guard de entorno OPS fallido.
#
# SECRETOS: nada hardcodeado, nada por linea de comando, nada impreso.
#   - anon key y passwords: variables de entorno locales, o prompt seguro
#     (Read-Host -AsSecureString) si la env var falta.
#   - emails: variables de entorno locales o prompt (no se imprimen).
#   - JWTs, anon, passwords, HMAC: jamas se loguean.
# PII: NUNCA se imprime el body completo. reserva.detalle (A05) puede traer datos
#   del huesped; solo se loguea accion, rol, status, ok, error.code, conteos y
#   nombres de claves top-level. Nunca telefono, email, DNI, notas ni valores.
#
# Variables de entorno esperadas (modo no interactivo):
#   VITA_OPS_SUPABASE_URL   (o pasar -SupabaseUrl)   ej: https://lpiatqztudxiwdlcoasv.supabase.co
#   VITA_OPS_GATEWAY_URL    (o pasar -GatewayUrl)    ej: https://<ref>.supabase.co/functions/v1/portal-api
#   VITA_OPS_ANON           anon key de OPS (publica por diseno; no se imprime)
#   VITA_OPS_JENNY_EMAIL / VITA_OPS_JENNY_PASS
#   VITA_OPS_VICKY_EMAIL / VITA_OPS_VICKY_PASS
#   VITA_OPS_SOCIO_EMAIL / VITA_OPS_SOCIO_PASS   (franco | rodrigo | remo)
#
# Parametro opcional -IdReservaProbe <int>: id real de una reserva de OPS para
#   ejercer A05 con cobertura PLENA (valida forma sin imprimir PII). Sin id, A05
#   corre con cobertura PARCIAL (acepta no_encontrado bien formado).
# ============================================================================

[CmdletBinding()]
param(
  [string]$SupabaseUrl = $env:VITA_OPS_SUPABASE_URL,
  [string]$GatewayUrl  = $env:VITA_OPS_GATEWAY_URL,
  [int]$IdReservaProbe = 0
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ---------------------------------------------------------------------------
# Catalogo de acciones (alineado al CATALOG del gateway). W10 separado: legado.
# ---------------------------------------------------------------------------
$ACC_JENNY = @('sesion.contexto', 'calendario.limpieza')
$ACC_PRODUCTIVAS_FULL = @(
  'sesion.contexto', 'calendario.limpieza', 'calendario.operativo', 'reserva.detalle',
  'prereservas.activas', 'cobranza.saldos', 'historico.reservas', 'ingresos.cobrados_periodo',
  'gastos.listado', 'reserva.crear_manual', 'bloqueo.crear_manual', 'cargar.gasto_interno',
  'cobranza.registrar_cobro'
)
$W10 = 'cobranza.registrar_saldo'   # legado/deprecated: NUNCA se invoca.
$ID_RESERVA_SINTETICO = 2147483646  # id improbable para A05 sin id real.

# ---------------------------------------------------------------------------
# Resultados.
# ---------------------------------------------------------------------------
$script:Results = New-Object System.Collections.ArrayList

function Add-Result {
  param(
    [string]$Bloque, [string]$Accion, [string]$Rol,
    [string]$Detalle, [string]$Veredicto, [bool]$Informativo = $false
  )
  $null = $script:Results.Add([pscustomobject]@{
    Bloque = $Bloque; Accion = $Accion; Rol = $Rol
    Detalle = $Detalle; Veredicto = $Veredicto; Informativo = $Informativo
  })
  $line = ('[{0}] {1} {2} | {3} | {4}' -f `
            $Bloque, $Accion.PadRight(28), $Rol.PadRight(6), $Detalle.PadRight(46), $Veredicto)
  Write-Host $line
}

# ---------------------------------------------------------------------------
# SecureString -> plano en memoria (efimero; nunca se loguea).
# ---------------------------------------------------------------------------
function ConvertTo-Plain {
  param([System.Security.SecureString]$Secure)
  $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
  try { return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
  finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

# Lee un secreto: env var (Process/User) o, si falta, prompt. Nunca lo imprime.
function Resolve-Secret {
  param([string]$EnvName, [string]$Prompt, [switch]$Secure)
  $v = [Environment]::GetEnvironmentVariable($EnvName, 'Process')
  if ([string]::IsNullOrEmpty($v)) { $v = [Environment]::GetEnvironmentVariable($EnvName, 'User') }
  if (-not [string]::IsNullOrEmpty($v)) { return $v }
  if ($Secure) {
    $ss = Read-Host -AsSecureString -Prompt $Prompt
    return (ConvertTo-Plain $ss)
  }
  return (Read-Host -Prompt $Prompt)
}

# ---------------------------------------------------------------------------
# HTTP JSON. Devuelve { Status, Body } sin lanzar para 4xx/5xx (el gateway usa
# 200 para ok:false; solo crash es 500). Body en UTF-8 (passwords no-ASCII ok).
# ---------------------------------------------------------------------------
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
    if (-not [string]::IsNullOrEmpty($resp.Content)) {
      try { $body = $resp.Content | ConvertFrom-Json } catch { $body = $null }
    }
    return [pscustomobject]@{ Status = [int]$resp.StatusCode; Body = $body }
  } catch [System.Net.WebException] {
    $r = $_.Exception.Response
    if ($null -ne $r) {
      $code = [int]$r.StatusCode
      $raw = ''
      try {
        $sr = New-Object System.IO.StreamReader($r.GetResponseStream())
        $raw = $sr.ReadToEnd(); $sr.Close()
      } catch { }
      $body = $null
      if (-not [string]::IsNullOrEmpty($raw)) { try { $body = $raw | ConvertFrom-Json } catch { } }
      return [pscustomobject]@{ Status = $code; Body = $body }
    }
    return [pscustomobject]@{ Status = -1; Body = $null }
  }
}

# Helper: existe propiedad en un PSCustomObject (para JSON dinamico).
function Test-Prop {
  param($Obj, [string]$Name)
  if ($null -eq $Obj) { return $false }
  return (($Obj.PSObject.Properties.Name) -contains $Name)
}

# ---------------------------------------------------------------------------
# Login Supabase Auth REST -> JWT. No imprime email/password/token.
# ---------------------------------------------------------------------------
function Get-Jwt {
  param([string]$Email, [string]$PlainPass)
  $uri = ('{0}/auth/v1/token?grant_type=password' -f $script:SupabaseUrl.TrimEnd('/'))
  $headers = @{ apikey = $script:AnonKey }
  $r = Invoke-Json -Method 'POST' -Uri $uri -Headers $headers -BodyObj @{ email = $Email; password = $PlainPass }
  if ($r.Status -eq 200 -and (Test-Prop $r.Body 'access_token') -and -not [string]::IsNullOrEmpty($r.Body.access_token)) {
    return $r.Body.access_token
  }
  throw ('login fallo (status {0})' -f $r.Status)   # sin email/password en el mensaje
}

# ---------------------------------------------------------------------------
# Llamada al gateway. Devuelve solo metadata: Status, Ok, Code, Keys, Count.
# Nunca devuelve ni loguea valores del body.
# ---------------------------------------------------------------------------
function Invoke-Portal {
  param([string]$Jwt, [string]$Action, $PayloadObj)
  $headers = @{ Authorization = ('Bearer {0}' -f $Jwt) }
  $r = Invoke-Json -Method 'POST' -Uri $script:GatewayUrl -Headers $headers `
        -BodyObj @{ action = $Action; payload = $PayloadObj }
  $ok = $false; $code = ''; $keys = @(); $count = $null; $isArray = $false
  if ($null -ne $r.Body) {
    if (Test-Prop $r.Body 'ok') { $ok = [bool]$r.Body.ok }
    if (-not $ok -and (Test-Prop $r.Body 'error') -and (Test-Prop $r.Body.error 'code')) {
      $code = [string]$r.Body.error.code
    }
    if ($ok -and (Test-Prop $r.Body 'data')) {
      $d = $r.Body.data
      if ($d -is [System.Array]) { $isArray = $true; $count = @($d).Count }
      elseif ($d -is [System.Management.Automation.PSCustomObject]) { $keys = @($d.PSObject.Properties.Name) }
    }
  }
  return [pscustomobject]@{ Status = $r.Status; Ok = $ok; Code = $code; Keys = $keys; Count = $count; IsArray = $isArray }
}

# Solo para sesion.contexto: extrae rol + acciones (no son PII; nombre NO se lee).
function Get-Contexto {
  param([string]$Jwt)
  $headers = @{ Authorization = ('Bearer {0}' -f $Jwt) }
  $r = Invoke-Json -Method 'POST' -Uri $script:GatewayUrl -Headers $headers `
        -BodyObj @{ action = 'sesion.contexto'; payload = @{} }
  $ok = $false; $rol = ''; $acciones = @()
  if ($null -ne $r.Body -and (Test-Prop $r.Body 'ok') -and ([bool]$r.Body.ok) -and (Test-Prop $r.Body 'data')) {
    $ok = $true
    if (Test-Prop $r.Body.data 'rol') { $rol = [string]$r.Body.data.rol }
    if (Test-Prop $r.Body.data 'acciones') { $acciones = @($r.Body.data.acciones) }
  }
  return [pscustomobject]@{ Status = $r.Status; Ok = $ok; Rol = $rol; Acciones = $acciones }
}

# Describe el resultado de una lectura SIN exponer valores.
function Get-LecturaInfo {
  param($Res)
  if ($Res.IsArray) { return ('status={0} ok={1} data=array(count={2})' -f $Res.Status, $Res.Ok, $Res.Count) }
  if (@($Res.Keys).Count -gt 0) { return ('status={0} ok={1} keys=[{2}]' -f $Res.Status, $Res.Ok, ($Res.Keys -join ',')) }
  if (-not $Res.Ok) { return ('status={0} ok={1} code={2}' -f $Res.Status, $Res.Ok, $Res.Code) }
  return ('status={0} ok={1}' -f $Res.Status, $Res.Ok)
}

# ===========================================================================
# 0. Configuracion + credenciales.
# ===========================================================================
Write-Host '============================================================'
Write-Host 'BLOQUE H.2 - smokes read-only end-to-end por rol (OPS)'
Write-Host '============================================================'

if ([string]::IsNullOrEmpty($SupabaseUrl)) { $SupabaseUrl = Resolve-Secret -EnvName 'VITA_OPS_SUPABASE_URL' -Prompt 'Supabase URL OPS' }
if ([string]::IsNullOrEmpty($GatewayUrl))  { $GatewayUrl  = Resolve-Secret -EnvName 'VITA_OPS_GATEWAY_URL'  -Prompt 'Gateway URL (portal-api OPS)' }
$script:SupabaseUrl = $SupabaseUrl
$script:GatewayUrl  = $GatewayUrl

# --- GUARD DE ENTORNO (antes de CUALQUIER credencial/login) ----------------
# Este smoke SOLO corre contra OPS. Si las URLs no apuntan a OPS y al gateway
# correcto, FRENAR sin pedir credenciales ni autenticar: evita generar evidencia
# invalida por correr accidentalmente contra TEST u otro entorno.
$OPS_REF = 'lpiatqztudxiwdlcoasv'
$guardErrores = @()
if ($script:SupabaseUrl -notlike ('*{0}*' -f $OPS_REF)) { $guardErrores += ('SupabaseUrl no contiene el ref de OPS ({0})' -f $OPS_REF) }
if ($script:GatewayUrl  -notlike ('*{0}*' -f $OPS_REF)) { $guardErrores += ('GatewayUrl no contiene el ref de OPS ({0})' -f $OPS_REF) }
if ($script:GatewayUrl  -notlike '*/functions/v1/portal-api*') { $guardErrores += 'GatewayUrl no apunta a /functions/v1/portal-api' }
if (@($guardErrores).Count -gt 0) {
  Write-Host ''
  Write-Host 'FRENAR: el guard de entorno OPS fallo. NO se intenta login.'
  foreach ($e in $guardErrores) { Write-Host ('  - {0}' -f $e) }
  Write-Host 'Revisar VITA_OPS_SUPABASE_URL / VITA_OPS_GATEWAY_URL (o -SupabaseUrl / -GatewayUrl).'
  exit 3
}
Write-Host ('Guard OPS: OK (ref {0} + gateway /functions/v1/portal-api).' -f $OPS_REF)

$script:AnonKey = Resolve-Secret -EnvName 'VITA_OPS_ANON' -Prompt 'anon key OPS' -Secure
$jennyEmail = Resolve-Secret -EnvName 'VITA_OPS_JENNY_EMAIL' -Prompt 'email jenny'
$jennyPass  = Resolve-Secret -EnvName 'VITA_OPS_JENNY_PASS'  -Prompt 'password jenny' -Secure
$vickyEmail = Resolve-Secret -EnvName 'VITA_OPS_VICKY_EMAIL' -Prompt 'email vicky'
$vickyPass  = Resolve-Secret -EnvName 'VITA_OPS_VICKY_PASS'  -Prompt 'password vicky' -Secure
$socioEmail = Resolve-Secret -EnvName 'VITA_OPS_SOCIO_EMAIL' -Prompt 'email socio (franco/rodrigo/remo)'
$socioPass  = Resolve-Secret -EnvName 'VITA_OPS_SOCIO_PASS'  -Prompt 'password socio' -Secure

Write-Host ('Gateway: {0}' -f $script:GatewayUrl)
if ($IdReservaProbe -gt 0) { Write-Host ('A05: cobertura PLENA (id_reserva provisto)') }
else { Write-Host ('A05: cobertura PARCIAL (sin id_reserva real; acepta no_encontrado)') }
Write-Host ''

# Login los 3 roles (los planos de password se descartan al salir de scope).
try {
  $jwtJenny = Get-Jwt -Email $jennyEmail -PlainPass $jennyPass
  $jwtVicky = Get-Jwt -Email $vickyEmail -PlainPass $vickyPass
  $jwtSocio = Get-Jwt -Email $socioEmail -PlainPass $socioPass
} catch {
  Write-Host ('ERROR de login: {0}' -f $_.Exception.Message)
  Write-Host 'FRENAR: no se pudo autenticar. Revisar credenciales/anon/url (no se imprimen).'
  exit 2
}
Write-Host 'Login OK para jenny / vicky / socio (JWT obtenido; no se imprime).'
Write-Host ''

# ===========================================================================
# B1. sesion.contexto por rol -> menu correcto.
# ===========================================================================
Write-Host '--- B1: sesion.contexto (menu por rol) ---'

# jenny: acciones EXACTAS = {sesion.contexto, calendario.limpieza}.
$cj = Get-Contexto -Jwt $jwtJenny
if (-not $cj.Ok) {
  Add-Result 'B1' 'sesion.contexto' 'jenny' ('status={0} ok=False' -f $cj.Status) 'FRENAR'
} else {
  $diff = Compare-Object -ReferenceObject $ACC_JENNY -DifferenceObject @($cj.Acciones)
  $exact = (@($diff).Count -eq 0)
  $det = ('rol={0} acciones={1} (exact match={2})' -f $cj.Rol, @($cj.Acciones).Count, $exact)
  Add-Result 'B1' 'sesion.contexto' 'jenny' $det ($(if ($exact -and $cj.Rol -eq 'jenny') { 'VERDE' } else { 'FRENAR' }))
}

# vicky / socio: deben CONTENER las 13 productivas. W10 informativo (legado).
foreach ($p in @(@{ J = $jwtVicky; R = 'vicky' }, @{ J = $jwtSocio; R = 'socio' })) {
  $c = Get-Contexto -Jwt $p.J
  if (-not $c.Ok) {
    Add-Result 'B1' 'sesion.contexto' $p.R ('status={0} ok=False' -f $c.Status) 'FRENAR'
    continue
  }
  # Allowlist ESTRICTA: deben estar TODAS las 13 productivas y NADA fuera del
  # universo aceptable (13 productivas + W10 informativo). Cualquier accion extra
  # inesperada -> FRENAR (no solo verificar presencia de las productivas).
  $universo = $ACC_PRODUCTIVAS_FULL + @($W10)
  $missing = @($ACC_PRODUCTIVAS_FULL | Where-Object { @($c.Acciones) -notcontains $_ })
  $extra   = @(@($c.Acciones) | Where-Object { $universo -notcontains $_ })
  $fullOk  = (@($missing).Count -eq 0) -and (@($extra).Count -eq 0) -and ($c.Rol -eq $p.R)
  $det = ('rol={0} acciones={1} faltantes={2} extra={3}' -f $c.Rol, @($c.Acciones).Count, @($missing).Count, @($extra).Count)
  Add-Result 'B1' 'sesion.contexto' $p.R $det ($(if ($fullOk) { 'VERDE' } else { 'FRENAR' }))
  # Listar las extras inesperadas (nombres de accion, no PII) para diagnostico.
  if (@($extra).Count -gt 0) { Write-Host ('    extras inesperadas: {0}' -f ($extra -join ',')) }

  # Informativo (NO afecta veredicto): W10 presente en catalogo tecnico legado.
  $w10In = (@($c.Acciones) -contains $W10)
  Add-Result 'B1-info' 'catalogo.legado.W10' $p.R ('W10_en_catalogo={0} (legado, no productivo)' -f $w10In) 'INFO' $true
}
Write-Host ''

# ===========================================================================
# B2. una lectura por accion (8 wrappers __OPS de lectura).
#     Payload {} salvo A05 (id_reserva). Floor 2026-07-01 -> economicas vacias.
# ===========================================================================
Write-Host '--- B2: una lectura por accion (cobertura de los 8 wrappers de lectura) ---'

# Las 7 lecturas con payload vacio, cada una con un rol habilitado.
$lecturasVacias = @(
  @{ Accion = 'calendario.limpieza';        Rol = 'jenny'; Jwt = $jwtJenny },
  @{ Accion = 'calendario.operativo';       Rol = 'vicky'; Jwt = $jwtVicky },
  @{ Accion = 'prereservas.activas';        Rol = 'vicky'; Jwt = $jwtVicky },
  @{ Accion = 'cobranza.saldos';            Rol = 'socio'; Jwt = $jwtSocio },
  @{ Accion = 'historico.reservas';         Rol = 'socio'; Jwt = $jwtSocio },
  @{ Accion = 'ingresos.cobrados_periodo';  Rol = 'socio'; Jwt = $jwtSocio },
  @{ Accion = 'gastos.listado';             Rol = 'vicky'; Jwt = $jwtVicky }
)
foreach ($l in $lecturasVacias) {
  $res = Invoke-Portal -Jwt $l.Jwt -Action $l.Accion -PayloadObj @{}
  $det = Get-LecturaInfo $res
  # Verde = HTTP 200 + ok:true (la cadena gateway->n8n->motor respondio bien).
  $verde = ($res.Status -eq 200) -and ($res.Ok)
  Add-Result 'B2' $l.Accion $l.Rol $det ($(if ($verde) { 'VERDE' } else { 'FRENAR' }))
}

# A05 reserva.detalle (parametrizable). Con id real -> PLENA; sin id -> PARCIAL.
if ($IdReservaProbe -gt 0) {
  $resA05 = Invoke-Portal -Jwt $jwtVicky -Action 'reserva.detalle' -PayloadObj @{ id_reserva = $IdReservaProbe }
  $det = Get-LecturaInfo $resA05
  $verde = ($resA05.Status -eq 200) -and ($resA05.Ok)   # forma valida (keys), sin PII
  Add-Result 'B2' 'reserva.detalle (plena)' 'vicky' $det ($(if ($verde) { 'VERDE' } else { 'FRENAR' }))
} else {
  $resA05 = Invoke-Portal -Jwt $jwtVicky -Action 'reserva.detalle' -PayloadObj @{ id_reserva = $ID_RESERVA_SINTETICO }
  $det = Get-LecturaInfo $resA05
  # PARCIAL: ok:true (existe) o code=no_encontrado (cadena ok, reserva inexistente).
  # FRENAR si error_entorno (cadena rota), rol_no_permitido (acceso) o payload_invalido (bug).
  $bienFormado = ($resA05.Status -eq 200) -and ($resA05.Ok -or ($resA05.Code -eq 'no_encontrado'))
  $ver = $(if ($bienFormado) { 'VERDE(parcial)' } else { 'FRENAR' })
  Add-Result 'B2' 'reserva.detalle (parcial)' 'vicky' $det $ver
}
Write-Host ''

# ===========================================================================
# B3. allowlist: jenny rebota en economicos.
#     CRITICO: el rebote es HTTP 200 + error.code=rol_no_permitido (NO 403).
# ===========================================================================
Write-Host '--- B3: allowlist (jenny rebota en economicos) ---'
$rebotes = @('cobranza.saldos', 'calendario.operativo', 'ingresos.cobrados_periodo')
foreach ($a in $rebotes) {
  $res = Invoke-Portal -Jwt $jwtJenny -Action $a -PayloadObj @{}
  $rebota = ($res.Status -eq 200) -and (-not $res.Ok) -and ($res.Code -eq 'rol_no_permitido')
  $det = ('status={0} ok={1} code={2}' -f $res.Status, $res.Ok, $res.Code)
  Add-Result 'B3' $a 'jenny' $det ($(if ($rebota) { 'VERDE' } else { 'FRENAR' }))
}
Write-Host ''

# ===========================================================================
# VEREDICTO.
# ===========================================================================
Write-Host '============================================================'
Write-Host 'VEREDICTO H.2'
Write-Host '============================================================'
$criticos = @($script:Results | Where-Object { -not $_.Informativo })
$frenar   = @($criticos | Where-Object { $_.Veredicto -eq 'FRENAR' })
$parcial  = @($criticos | Where-Object { $_.Veredicto -eq 'VERDE(parcial)' })
$verdes   = @($criticos | Where-Object { $_.Veredicto -like 'VERDE*' })

Write-Host ('Chequeos criticos: {0} | verdes: {1} | parciales: {2} | FRENAR: {3}' -f `
            @($criticos).Count, @($verdes).Count, @($parcial).Count, @($frenar).Count)

if (@($frenar).Count -eq 0) {
  if (@($parcial).Count -gt 0) {
    Write-Host 'RESULTADO: VERDE (con A05 en cobertura parcial; pasar -IdReservaProbe para cobertura plena).'
  } else {
    Write-Host 'RESULTADO: VERDE.'
  }
  Write-Host 'Anti-OPS respetado: cero escrituras, cero consumo de secuencias del negocio.'
  exit 0
} else {
  Write-Host 'RESULTADO: FRENAR. Revisar las filas marcadas FRENAR arriba.'
  exit 1
}
