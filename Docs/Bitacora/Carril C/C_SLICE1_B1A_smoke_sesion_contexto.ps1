# =============================================================================
# C_SLICE1_B1A_smoke_sesion_contexto.ps1  (v2 - ASCII puro)
# Smokes de no-regresion de sesion.contexto - Carril C / Slice 1 / Bloque 1A (TEST).
#
# Las 6 llamadas son identicas a las de Slice 0: A03 aun NO esta en el CATALOG, asi
# que 'acciones' debe seguir siendo exactamente ["sesion.contexto"] en los 3 roles.
#
# Archivo en ASCII puro a proposito: evita el gotcha de encoding de PowerShell 5.1
# (un .ps1 UTF-8 sin BOM se lee como ANSI y rompe el parseo). Anda en PS 5.1 y PS 7+.
# NO commitear este archivo con credenciales reales: es harness local de prueba.
# =============================================================================

# TLS 1.2 explicito (Supabase lo exige; necesario en PS 5.1, inocuo en 7).
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

# ============ CONFIG - completar ============
$SUPABASE_URL = 'https://bdskhhbmcksskkzqkcdp.supabase.co'

# apikey para el sign-in: la ANON o PUBLISHABLE key (sb_publishable_... o la anon legacy).
# NUNCA la secret/service key. Dashboard -> Project Settings -> API.
$ANON_KEY     = 'sb_publishable_fvbXZk2YZgGIWZj6d25VwA_req0lwTU'

# Usuarios del portal (creados en Supabase Auth) + sus passwords de prueba.
$USERS = @(
  @{ nombre = 'vicky';  rol = 'vicky'; email = 'vicky@vitadelta.test';  pass = '1234'  },
  @{ nombre = 'franco'; rol = 'socio'; email = 'franco@vitadelta.test'; pass = '1234' },
  @{ nombre = 'jenny';  rol = 'jenny'; email = 'jenny@vitadelta.test';  pass = '1234'  }
)
# ============================================

$PORTAL = "$SUPABASE_URL/functions/v1/portal-api"
$AUTH   = "$SUPABASE_URL/auth/v1/token?grant_type=password"
$script:fails = 0

# Login por password grant -> devuelve el access_token (JWT) o $null.
function Get-Jwt([string]$email, [string]$pass) {
  $body = @{ email = $email; password = $pass } | ConvertTo-Json -Compress
  try {
    $r = Invoke-RestMethod -Uri $AUTH -Method POST -Headers @{ apikey = $ANON_KEY } -ContentType 'application/json' -Body $body
    return $r.access_token
  } catch {
    Write-Host "  [auth] no pude loguear $email - revisa email / password / ANON_KEY" -ForegroundColor Yellow
    return $null
  }
}

# Llama a portal-api. Devuelve la respuesta parseada (ok/data/error) o $null si hubo
# no-2xx (tipicamente 5xx de preflight = faltan VITA_AMBIENTE / N8N_BASE_URL).
function Invoke-Portal($jwt, [string]$action) {
  $headers = @{ apikey = $ANON_KEY }
  if ($jwt) { $headers['Authorization'] = "Bearer $jwt" }
  $body = @{ action = $action } | ConvertTo-Json -Compress
  try {
    return Invoke-RestMethod -Uri $PORTAL -Method POST -Headers $headers -ContentType 'application/json' -Body $body
  } catch {
    $code = -1
    try { $code = [int]$_.Exception.Response.StatusCode } catch {}
    Write-Host "  [http $code] portal-api no devolvio 200 - faltan los secrets del Paso 1/2 (preflight 5xx)? Mira los logs de la funcion." -ForegroundColor Red
    return $null
  }
}

function Assert([string]$name, [bool]$cond, [string]$actual) {
  if ($cond) { Write-Host "  PASS  $name" -ForegroundColor Green }
  else       { Write-Host "  FALL  $name  -> $actual" -ForegroundColor Red; $script:fails++ }
}

Write-Host ""
Write-Host "=== Smokes sesion.contexto (Slice 1 / Bloque 1A) ==="
Write-Host ""

# --- Casos 1-3: cada usuario; ok:true, rol correcto, acciones EXACTAMENTE [sesion.contexto] ---
$jwtVicky = $null
foreach ($u in $USERS) {
  Write-Host ("Caso {0}: {1}" -f $u.nombre, $u.email)
  $jwt = Get-Jwt $u.email $u.pass
  if ($u.nombre -eq 'vicky') { $jwtVicky = $jwt }
  if (-not $jwt) { $script:fails++; Write-Host ""; continue }

  $r = Invoke-Portal $jwt 'sesion.contexto'
  if (-not $r) { $script:fails++; Write-Host ""; continue }

  $acc = (@($r.data.acciones) -join ',')
  Assert "ok:true"                     ($r.ok -eq $true)              "ok=$($r.ok)"
  Assert "rol=$($u.rol)"               ($r.data.rol -eq $u.rol)       "rol=$($r.data.rol)"
  Assert "nombre=$($u.nombre)"         ($r.data.nombre -eq $u.nombre) "nombre=$($r.data.nombre)"
  Assert "acciones==[sesion.contexto]" ($acc -eq 'sesion.contexto')   "acciones=[$acc]"
  Write-Host ""
}

# --- Caso 4: sin JWT -> no_autorizado ---
Write-Host "Caso 4: sin JWT"
$r = Invoke-Portal $null 'sesion.contexto'
if ($r) { Assert "error.code=no_autorizado" ($r.error.code -eq 'no_autorizado') "code=$($r.error.code)" }
else    { $script:fails++ }
Write-Host ""

# --- Caso 5: JWT basura -> no_autorizado ---
Write-Host "Caso 5: JWT basura"
$r = Invoke-Portal 'esto.no.es.un.jwt' 'sesion.contexto'
if ($r) { Assert "error.code=no_autorizado" ($r.error.code -eq 'no_autorizado') "code=$($r.error.code)" }
else    { $script:fails++ }
Write-Host ""

# --- Caso 6: accion desconocida (JWT valido) -> accion_desconocida ---
Write-Host "Caso 6: accion desconocida"
if ($jwtVicky) {
  $r = Invoke-Portal $jwtVicky 'accion.que.no.existe'
  if ($r) { Assert "error.code=accion_desconocida" ($r.error.code -eq 'accion_desconocida') "code=$($r.error.code)" }
  else    { $script:fails++ }
} else {
  Write-Host "  (no tengo JWT de vicky; revisa el Caso 1)" -ForegroundColor Yellow
  $script:fails++
}
Write-Host ""

# --- Veredicto ---
if ($script:fails -eq 0) {
  Write-Host "RESULTADO: sin fallos en los 6 casos. acciones quedo en [sesion.contexto] (A03 NO visible). Podes pasar al Bloque 2." -ForegroundColor Green
} else {
  Write-Host "RESULTADO: $($script:fails) fallo(s). NO avanzar al Bloque 2." -ForegroundColor Red
}
