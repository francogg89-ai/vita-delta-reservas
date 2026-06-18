# =============================================================================
# C_SLICE1_B11_smoke_a12_via_portal.ps1  (ASCII puro)
# Smokes de A12 VIA portal-api (TEST) - Carril C / Slice 1 / Bloque 11 (ULTIMO del slice).
# Prueba el camino completo: login -> JWT -> portal-api -> CATALOG (cobranza.saldos) ->
# firma HMAC -> wrapper n8n -> revalidacion -> read CTEs -> render -> envelope JSON data:{filas}.
#
# A12 NO lleva payload (payloadVacio) y NO tiene no_encontrado (lista). Smoke corto, como A06:
#  - vicky / socio  -> cobranza.saldos ok:true, data.filas array (filas>=0; 0 es VALIDO);
#                      y sesion.contexto INCLUYE 'cobranza.saldos'.
#  - jenny          -> cobranza.saldos rol_no_permitido (rebota EN EL GATEWAY, antes de firmar);
#                      y sesion.contexto NO la incluye.
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
  @{ nombre = 'vicky';  rol = 'vicky'; email = 'vicky@vitadelta.test';  pass = '1234'; esperaA12 = $true  },
  @{ nombre = 'franco'; rol = 'socio'; email = 'franco@vitadelta.test'; pass = '1234'; esperaA12 = $true  },
  @{ nombre = 'jenny';  rol = 'jenny'; email = 'jenny@vitadelta.test';  pass = '1234'; esperaA12 = $false }
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
$B_A12 = '{"action":"cobranza.saldos"}'

Write-Host ""
Write-Host "=== Smokes A12 via portal-api (Slice 1 / Bloque 11 - ultimo del slice) ==="
Write-Host ""

foreach ($u in $USERS) {
  Write-Host ("Usuario: {0} ({1})  esperaA12={2}" -f $u.nombre, $u.rol, $u.esperaA12)
  $jwt = Get-Jwt $u.email $u.pass
  if (-not $jwt) { $script:fails++; Write-Host ""; continue }

  # a) sesion.contexto: 'cobranza.saldos' visible SOLO si el rol la tiene (A12 = vicky/socio)
  $s = Invoke-PortalRaw $jwt $B_CTX
  if ($s) {
    $acc = (@($s.data.acciones) -join ',')
    $tiene = (@($s.data.acciones) -contains 'cobranza.saldos')
    if ($u.esperaA12) {
      Assert "sesion.contexto INCLUYE cobranza.saldos" ($tiene) "acciones=[$acc]"
    } else {
      Assert "sesion.contexto NO incluye cobranza.saldos (jenny)" (-not $tiene) "acciones=[$acc]"
    }
  } else { $script:fails++ }

  # b) cobranza.saldos: vicky/socio -> ok:true + filas array ; jenny -> rol_no_permitido
  $r = Invoke-PortalRaw $jwt $B_A12
  if ($r) {
    if ($u.esperaA12) {
      $tieneFilas = ($null -ne $r.data) -and ($r.data.PSObject.Properties.Name -contains 'filas')
      $n = 0; if ($tieneFilas) { $n = @($r.data.filas).Count }
      Assert "cobranza.saldos ok:true"               ($r.ok -eq $true)  "ok=$($r.ok) code=$($r.error.code)"
      Assert "data.filas presente (array, filas=$n)"  ($tieneFilas)      "data=$($r.data)"
    } else {
      Assert "cobranza.saldos ok:false"                          ($r.ok -eq $false)                      "ok=$($r.ok)"
      Assert "error.code=rol_no_permitido (rebota en gateway)"   ($r.error.code -eq 'rol_no_permitido')  "code=$($r.error.code)"
    }
  } else { $script:fails++ }
  Write-Host ""
}

# c) sin JWT -> no_autorizado
Write-Host "Sin JWT -> cobranza.saldos"
$r = Invoke-PortalRaw $null $B_A12
if ($r) { Assert "error.code=no_autorizado" ($r.error.code -eq 'no_autorizado') "code=$($r.error.code)" }
else    { $script:fails++ }
Write-Host ""

if ($script:fails -eq 0) {
  Write-Host "RESULTADO: sin fallos. A12 anda de punta a punta via portal-api. Bloque 11 / A12 listo." -ForegroundColor Green
  Write-Host "Slice 1 COMPLETO (A03 - A04 - A05 - A06 - A12). Sigue el cierre formal del slice." -ForegroundColor Green
} else {
  Write-Host "RESULTADO: $($script:fails) fallo(s). Revisar antes de cerrar." -ForegroundColor Red
}
