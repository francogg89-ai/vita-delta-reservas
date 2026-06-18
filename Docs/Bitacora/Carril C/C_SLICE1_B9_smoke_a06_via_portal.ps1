# =============================================================================
# C_SLICE1_B9_smoke_a06_via_portal.ps1  (ASCII puro)
# Smokes de A06 VIA portal-api (TEST) - Carril C / Slice 1 / Bloque 9.
# Prueba el camino completo: login -> JWT -> portal-api -> CATALOG (prereservas.activas) ->
# firma HMAC -> wrapper n8n -> revalidacion -> read vista -> render -> envelope JSON data:{filas}.
#
# A06 NO lleva payload (payloadVacio) y NO tiene no_encontrado (lista). Por eso este smoke es
# mas corto que el de A05:
#  - vicky / socio  -> prereservas.activas ok:true, data.filas array (filas>=0; 0 es VALIDO);
#                      y sesion.contexto INCLUYE 'prereservas.activas'.
#  - jenny          -> prereservas.activas rol_no_permitido (rebota EN EL GATEWAY, antes de
#                      firmar); y sesion.contexto NO la incluye.
#  - sin JWT        -> no_autorizado.
#
# El happy path PASA aunque filas.length = 0 (D-C-47). No se crean fixtures.
# NO commitear con credenciales reales: harness local de prueba (TEST). La ANON_KEY es la
# publishable key (publica) de TEST.
# =============================================================================

try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

# ============ CONFIG - completar/verificar ============
$SUPABASE_URL = 'https://bdskhhbmcksskkzqkcdp.supabase.co'
$ANON_KEY     = 'sb_publishable_fvbXZk2YZgGIWZj6d25VwA_req0lwTU'   # publishable key (publica) de TEST
$USERS = @(
  @{ nombre = 'vicky';  rol = 'vicky'; email = 'vicky@vitadelta.test';  pass = '1234'; esperaA06 = $true  },
  @{ nombre = 'franco'; rol = 'socio'; email = 'franco@vitadelta.test'; pass = '1234'; esperaA06 = $true  },
  @{ nombre = 'jenny';  rol = 'jenny'; email = 'jenny@vitadelta.test';  pass = '1234'; esperaA06 = $false }
)
# =====================================================

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

function Invoke-PortalRaw($jwt, [string]$BodyJson) {
  $headers = @{ apikey = $ANON_KEY }
  if ($jwt) { $headers['Authorization'] = "Bearer $jwt" }
  try {
    return Invoke-RestMethod -Uri $PORTAL -Method POST -Headers $headers -ContentType 'application/json' -Body $BodyJson
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
  Write-Host "Falta pegar ANON_KEY (publishable key de TEST) en CONFIG." -ForegroundColor Red
  return
}

$B_CTX = '{"action":"sesion.contexto"}'
$B_A06 = '{"action":"prereservas.activas"}'

Write-Host ""
Write-Host "=== Smokes A06 via portal-api (Slice 1 / Bloque 9) ==="
Write-Host ""

foreach ($u in $USERS) {
  Write-Host ("Usuario: {0} ({1})  esperaA06={2}" -f $u.nombre, $u.rol, $u.esperaA06)
  $jwt = Get-Jwt $u.email $u.pass
  if (-not $jwt) { $script:fails++; Write-Host ""; continue }

  # a) sesion.contexto: 'prereservas.activas' visible SOLO si el rol la tiene (A06 = vicky/socio)
  $s = Invoke-PortalRaw $jwt $B_CTX
  if ($s) {
    $acc = (@($s.data.acciones) -join ',')
    $tiene = (@($s.data.acciones) -contains 'prereservas.activas')
    if ($u.esperaA06) {
      Assert "sesion.contexto INCLUYE prereservas.activas" ($tiene) "acciones=[$acc]"
    } else {
      Assert "sesion.contexto NO incluye prereservas.activas (jenny)" (-not $tiene) "acciones=[$acc]"
    }
  } else { $script:fails++ }

  # b) prereservas.activas: vicky/socio -> ok:true + filas array ; jenny -> rol_no_permitido
  $r = Invoke-PortalRaw $jwt $B_A06
  if ($r) {
    if ($u.esperaA06) {
      $tieneFilas = ($null -ne $r.data) -and ($r.data.PSObject.Properties.Name -contains 'filas')
      $n = 0; if ($tieneFilas) { $n = @($r.data.filas).Count }
      Assert "prereservas.activas ok:true"          ($r.ok -eq $true)  "ok=$($r.ok) code=$($r.error.code)"
      Assert "data.filas presente (array, filas=$n)" ($tieneFilas)      "data=$($r.data)"
    } else {
      Assert "prereservas.activas ok:false"                       ($r.ok -eq $false)                      "ok=$($r.ok)"
      Assert "error.code=rol_no_permitido (rebota en gateway)"    ($r.error.code -eq 'rol_no_permitido')  "code=$($r.error.code)"
    }
  } else { $script:fails++ }
  Write-Host ""
}

# c) sin JWT -> no_autorizado
Write-Host "Sin JWT -> prereservas.activas"
$r = Invoke-PortalRaw $null $B_A06
if ($r) { Assert "error.code=no_autorizado" ($r.error.code -eq 'no_autorizado') "code=$($r.error.code)" }
else    { $script:fails++ }
Write-Host ""

if ($script:fails -eq 0) {
  Write-Host "RESULTADO: sin fallos. A06 anda de punta a punta via portal-api. Bloque 9 / A06 listo." -ForegroundColor Green
  Write-Host "(filas=0 en vicky/socio es PASS: lista vacia valida, D-C-47.)" -ForegroundColor DarkGray
} else {
  Write-Host "RESULTADO: $($script:fails) fallo(s). Revisar antes de cerrar." -ForegroundColor Red
}
