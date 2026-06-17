# =============================================================================
# C_SLICE1_B3_smoke_a03_via_portal.ps1  (ASCII puro)
# Smokes de A03 VIA portal-api (TEST) - Carril C / Slice 1 / Bloque 3.
# Prueba el camino completo: login -> JWT -> portal-api -> CATALOG (calendario.limpieza)
# -> firma HMAC -> wrapper n8n -> revalidacion -> reads -> render -> envelope.
#
# Verifica:
#  - sesion.contexto ahora incluye 'calendario.limpieza' en acciones (A03 visible).
#  - calendario.limpieza devuelve ok:true, formato=html, con HTML real.
#  - sin JWT -> no_autorizado.
#
# A03 habilita los 3 roles, asi que jenny/vicky/socio dan ok:true (no hay
# rol_no_permitido por el gateway aca; ese caso se probo directo al wrapper en B2).
# NO commitear con credenciales reales: harness local de prueba (TEST).
# =============================================================================

try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

# ============ CONFIG - completar ============
$SUPABASE_URL = 'https://bdskhhbmcksskkzqkcdp.supabase.co'
$ANON_KEY     = 'sb_publishable_fvbXZk2YZgGIWZj6d25VwA_req0lwTU'
$USERS = @(
  @{ nombre = 'vicky';  rol = 'vicky'; email = 'vicky@vitadelta.test';  pass = '1234'  },
  @{ nombre = 'franco'; rol = 'socio'; email = 'franco@vitadelta.test'; pass = '1234' },
  @{ nombre = 'jenny';  rol = 'jenny'; email = 'jenny@vitadelta.test';  pass = '1234'  }
)
# ============================================

$PORTAL = "$SUPABASE_URL/functions/v1/portal-api"
$AUTH   = "$SUPABASE_URL/auth/v1/token?grant_type=password"
$script:fails = 0

function Get-Jwt([string]$email, [string]$pass) {
  $body = @{ email = $email; password = $pass } | ConvertTo-Json -Compress
  try {
    $r = Invoke-RestMethod -Uri $AUTH -Method POST -Headers @{ apikey = $ANON_KEY } -ContentType 'application/json' -Body $body
    return $r.access_token
  } catch { Write-Host "  [auth] no pude loguear $email" -ForegroundColor Yellow; return $null }
}

function Invoke-Portal($jwt, [string]$action) {
  $headers = @{ apikey = $ANON_KEY }
  if ($jwt) { $headers['Authorization'] = "Bearer $jwt" }
  $body = @{ action = $action } | ConvertTo-Json -Compress
  try {
    return Invoke-RestMethod -Uri $PORTAL -Method POST -Headers $headers -ContentType 'application/json' -Body $body
  } catch {
    $code = -1; try { $code = [int]$_.Exception.Response.StatusCode } catch {}
    Write-Host "  [http $code] portal-api no devolvio 200 (preflight 5xx?)" -ForegroundColor Red
    return $null
  }
}

function Assert([string]$name, [bool]$cond, [string]$actual) {
  if ($cond) { Write-Host "  PASS  $name" -ForegroundColor Green }
  else       { Write-Host "  FALL  $name  -> $actual" -ForegroundColor Red; $script:fails++ }
}

Write-Host ""
Write-Host "=== Smokes A03 via portal-api (Slice 1 / Bloque 3) ==="
Write-Host ""

foreach ($u in $USERS) {
  Write-Host ("Usuario: {0} ({1})" -f $u.nombre, $u.rol)
  $jwt = Get-Jwt $u.email $u.pass
  if (-not $jwt) { $script:fails++; Write-Host ""; continue }

  # a) sesion.contexto: acciones ahora incluye calendario.limpieza
  $s = Invoke-Portal $jwt 'sesion.contexto'
  if ($s) {
    $acc = (@($s.data.acciones) -join ',')
    Assert "acciones incluye calendario.limpieza" ((@($s.data.acciones) -contains 'calendario.limpieza')) "acciones=[$acc]"
  } else { $script:fails++ }

  # b) calendario.limpieza: ok:true, formato html, html real
  $r = Invoke-Portal $jwt 'calendario.limpieza'
  if ($r) {
    $fmt = if ($r.data) { $r.data.formato } else { '' }
    $hlen = if ($r.data -and $r.data.html) { $r.data.html.Length } else { 0 }
    Assert "calendario.limpieza ok:true"   ($r.ok -eq $true)        "ok=$($r.ok) code=$($r.error.code)"
    Assert "formato=html"                  ($fmt -eq 'html')        "formato=$fmt"
    Assert "html no vacio (len>0)"         ($hlen -gt 0)            "html_len=$hlen"
  } else { $script:fails++ }
  Write-Host ""
}

# c) sin JWT -> no_autorizado
Write-Host "Sin JWT -> calendario.limpieza"
$r = Invoke-Portal $null 'calendario.limpieza'
if ($r) { Assert "error.code=no_autorizado" ($r.error.code -eq 'no_autorizado') "code=$($r.error.code)" }
else    { $script:fails++ }
Write-Host ""

if ($script:fails -eq 0) {
  Write-Host "RESULTADO: sin fallos. A03 anda de punta a punta via portal-api. Bloque 3 / A03 listo." -ForegroundColor Green
} else {
  Write-Host "RESULTADO: $($script:fails) fallo(s). Revisar antes de cerrar." -ForegroundColor Red
}
