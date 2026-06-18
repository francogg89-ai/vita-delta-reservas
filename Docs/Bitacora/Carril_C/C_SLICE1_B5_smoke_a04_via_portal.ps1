# =============================================================================
# C_SLICE1_B5_smoke_a04_via_portal.ps1  (ASCII puro)
# Smokes de A04 VIA portal-api (TEST) - Carril C / Slice 1 / Bloque 5.
# Prueba el camino completo: login -> JWT -> portal-api -> CATALOG (calendario.operativo)
# -> firma HMAC -> wrapper n8n -> revalidacion -> reads -> render -> envelope (con montos).
#
# A04 habilita SOLO vicky/socio (D-C-39). Por eso, a diferencia de A03:
#  - vicky / socio  -> calendario.operativo ok:true, formato=html, html real (con montos);
#                      y sesion.contexto INCLUYE 'calendario.operativo'.
#  - jenny          -> calendario.operativo rol_no_permitido (HITO: rebota EN EL GATEWAY,
#                      antes de firmar, sin tocar n8n); y sesion.contexto NO la incluye.
#  - sin JWT        -> no_autorizado.
#
# NO commitear con credenciales reales: harness local de prueba (TEST).
# =============================================================================

try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

# ============ CONFIG - completar ============
$SUPABASE_URL = 'https://bdskhhbmcksskkzqkcdp.supabase.co'
$ANON_KEY     = 'sb_publishable_fvbXZk2YZgGIWZj6d25VwA_req0lwTU'   # publishable key (publica) de TEST; copiala del smoke B3
$USERS = @(
  @{ nombre = 'vicky';  rol = 'vicky'; email = 'vicky@vitadelta.test';  pass = '1234'; esperaA04 = $true  },
  @{ nombre = 'franco'; rol = 'socio'; email = 'franco@vitadelta.test'; pass = '1234'; esperaA04 = $true  },
  @{ nombre = 'jenny';  rol = 'jenny'; email = 'jenny@vitadelta.test';  pass = '1234'; esperaA04 = $false }
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

if ($ANON_KEY -eq 'PEGAR_ANON_KEY') {
  Write-Host "Falta pegar ANON_KEY (publishable key de TEST) en CONFIG. Copiala del smoke B3." -ForegroundColor Red
  return
}

Write-Host ""
Write-Host "=== Smokes A04 via portal-api (Slice 1 / Bloque 5) ==="
Write-Host ""

foreach ($u in $USERS) {
  Write-Host ("Usuario: {0} ({1})  esperaA04={2}" -f $u.nombre, $u.rol, $u.esperaA04)
  $jwt = Get-Jwt $u.email $u.pass
  if (-not $jwt) { $script:fails++; Write-Host ""; continue }

  # a) sesion.contexto: 'calendario.operativo' visible SOLO si el rol la tiene (A04 = vicky/socio)
  $s = Invoke-Portal $jwt 'sesion.contexto'
  if ($s) {
    $acc = (@($s.data.acciones) -join ',')
    $tiene = (@($s.data.acciones) -contains 'calendario.operativo')
    if ($u.esperaA04) {
      Assert "sesion.contexto INCLUYE calendario.operativo" ($tiene) "acciones=[$acc]"
    } else {
      Assert "sesion.contexto NO incluye calendario.operativo (jenny)" (-not $tiene) "acciones=[$acc]"
    }
  } else { $script:fails++ }

  # b) calendario.operativo: vicky/socio -> ok:true html ; jenny -> rol_no_permitido (gateway)
  $r = Invoke-Portal $jwt 'calendario.operativo'
  if ($r) {
    if ($u.esperaA04) {
      $fmt  = if ($r.data) { $r.data.formato } else { '' }
      $hlen = if ($r.data -and $r.data.html) { $r.data.html.Length } else { 0 }
      Assert "calendario.operativo ok:true"  ($r.ok -eq $true)  "ok=$($r.ok) code=$($r.error.code)"
      Assert "formato=html"                  ($fmt -eq 'html')  "formato=$fmt"
      Assert "html no vacio (len>0)"         ($hlen -gt 0)      "html_len=$hlen"
    } else {
      Assert "calendario.operativo ok:false"                       ($r.ok -eq $false)                       "ok=$($r.ok)"
      Assert "error.code=rol_no_permitido (rebota en el gateway)"  ($r.error.code -eq 'rol_no_permitido')   "code=$($r.error.code)"
    }
  } else { $script:fails++ }
  Write-Host ""
}

# c) sin JWT -> no_autorizado
Write-Host "Sin JWT -> calendario.operativo"
$r = Invoke-Portal $null 'calendario.operativo'
if ($r) { Assert "error.code=no_autorizado" ($r.error.code -eq 'no_autorizado') "code=$($r.error.code)" }
else    { $script:fails++ }
Write-Host ""

if ($script:fails -eq 0) {
  Write-Host "RESULTADO: sin fallos. A04 anda de punta a punta via portal-api. Bloque 5 / A04 listo." -ForegroundColor Green
} else {
  Write-Host "RESULTADO: $($script:fails) fallo(s). Revisar antes de cerrar." -ForegroundColor Red
}
