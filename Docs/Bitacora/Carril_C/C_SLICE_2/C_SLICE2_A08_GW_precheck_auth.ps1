# ============================================================================
# C_SLICE2_A08_GW - PRECHECK Auth/JWT (gate previo al smoke via gateway)
# Confirma que existen usuarios + passwords de prueba y que el gateway resuelve
# identidad y expone bloqueo.crear_manual en la allowlist (vicky/socio si; jenny
# no). NO asume passwords: las lee de env vars; si faltan o el login falla, FRENA.
# ASCII puro (PS 5.1 lee .ps1 como Windows-1252). Compatible 5.1/7.
#
# Para cada usuario (vicky, socio/franco, jenny):
#   1) obtiene JWT via /auth/v1/token?grant_type=password,
#   2) llama sesion.contexto con ese JWT,
#   3) valida nombre, rol y si bloqueo.crear_manual aparece en sus acciones.
#
# Requisitos (env vars; passwords NUNCA hardcodeadas):
#   $env:VITA_SUPABASE_URL_TEST / $env:VITA_SUPABASE_ANON_TEST
#   $env:VITA_PW_VICKY / $env:VITA_PW_FRANCO / $env:VITA_PW_JENNY
#
# Correr DESPUES de desplegar el index.ts del gateway (con A08) en TEST.
# Uso:  powershell -ExecutionPolicy Bypass -File .\C_SLICE2_A08_GW_precheck_auth.ps1
# ============================================================================
param(
  [string]$SupabaseUrl = $env:VITA_SUPABASE_URL_TEST,
  [string]$AnonKey     = $env:VITA_SUPABASE_ANON_TEST
)
$ErrorActionPreference = "Stop"
if (-not $SupabaseUrl) { Write-Host "FALTA: setea `$env:VITA_SUPABASE_URL_TEST (https://<ref>.supabase.co)" -ForegroundColor Red; exit 1 }
if (-not $AnonKey)     { Write-Host "FALTA: setea `$env:VITA_SUPABASE_ANON_TEST (anon key del proyecto TEST)" -ForegroundColor Red; exit 1 }
$SupabaseUrl = $SupabaseUrl.TrimEnd('/')

$users = @(
  [pscustomobject]@{ label='vicky';         email='vicky@vitadelta.test';  pw=$env:VITA_PW_VICKY;  expNombre='vicky';  expRol='vicky'; debeCrear=$true  },
  [pscustomobject]@{ label='socio (franco)'; email='franco@vitadelta.test'; pw=$env:VITA_PW_FRANCO; expNombre='franco'; expRol='socio'; debeCrear=$true  },
  [pscustomobject]@{ label='jenny';         email='jenny@vitadelta.test';  pw=$env:VITA_PW_JENNY;  expNombre='jenny';  expRol='jenny'; debeCrear=$false }
)

function Get-Jwt {
  param($email, $pw)
  $body = @{ email=$email; password=$pw } | ConvertTo-Json -Compress
  try {
    $r = Invoke-RestMethod -Uri "$SupabaseUrl/auth/v1/token?grant_type=password" -Method Post `
                           -Headers @{ apikey=$AnonKey } -ContentType "application/json" -Body $body
    return $r.access_token
  } catch { return $null }
}
function Get-Contexto {
  param($jwt)
  $body = @{ action='sesion.contexto'; payload=@{} } | ConvertTo-Json -Compress
  try {
    return Invoke-RestMethod -Uri "$SupabaseUrl/functions/v1/portal-api" -Method Post `
                             -Headers @{ Authorization="Bearer $jwt"; apikey=$AnonKey } -ContentType "application/json" -Body $body
  } catch {
    $resp = $_.Exception.Response
    if ($resp) { $sr = New-Object System.IO.StreamReader($resp.GetResponseStream()); $t = $sr.ReadToEnd()
                 try { return ($t | ConvertFrom-Json) } catch { return $null } }
    return $null
  }
}

Write-Host "`n=== PRECHECK Auth/JWT A08 - gateway portal-api (TEST) ===" -ForegroundColor Cyan
Write-Host "URL: $SupabaseUrl/functions/v1/portal-api"
$allReady = $true
foreach ($u in $users) {
  Write-Host ("`n--- {0}  ({1}) ---" -f $u.label, $u.email)
  if (-not $u.pw) {
    Write-Host "  [FALTA] password no provista (env VITA_PW_*). No se puede obtener JWT." -ForegroundColor Yellow
    $allReady = $false; continue
  }
  $jwt = Get-Jwt $u.email $u.pw
  if (-not $jwt) {
    Write-Host "  [FALLO] no se obtuvo JWT (usuario inexistente o password incorrecta)." -ForegroundColor Red
    $allReady = $false; continue
  }
  Write-Host "  [OK] JWT obtenido"
  $ctx = Get-Contexto $jwt
  if (-not $ctx -or -not $ctx.ok) {
    Write-Host ("  [FALLO] sesion.contexto no devolvio ok. resp: {0}" -f ($ctx | ConvertTo-Json -Compress -Depth 5)) -ForegroundColor Red
    $allReady = $false; continue
  }
  $tieneCrear = ($ctx.data.acciones -contains 'bloqueo.crear_manual')
  Write-Host ("  sesion.contexto: nombre={0} rol={1} bloqueo.crear_manual={2}" -f $ctx.data.nombre, $ctx.data.rol, $tieneCrear)
  $nombreOk = ($ctx.data.nombre -eq $u.expNombre)
  $rolOk    = ($ctx.data.rol -eq $u.expRol)
  $crearOk  = ($tieneCrear -eq $u.debeCrear)
  if ($nombreOk -and $rolOk -and $crearOk) {
    Write-Host "  [OK] identidad y allowlist correctas" -ForegroundColor Green
  } else {
    Write-Host ("  [FALLO] esperado nombre={0} rol={1} bloqueo.crear_manual={2}" -f $u.expNombre, $u.expRol, $u.debeCrear) -ForegroundColor Red
    $allReady = $false
  }
}

Write-Host ""
if ($allReady) {
  Write-Host "PRECHECK OK: los 3 usuarios tienen JWT y bloqueo.crear_manual en la allowlist correcta. Luz verde para el smoke gateway A08." -ForegroundColor Green
} else {
  Write-Host "PRECHECK INCOMPLETO: faltan passwords/usuarios o allowlist no cuadra. NO correr el smoke gateway hasta resolverlo." -ForegroundColor Red
  exit 1
}
