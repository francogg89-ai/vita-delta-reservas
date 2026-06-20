# =============================================================================
# C_SLICE1_B7_smoke_a05_via_portal.ps1  (ASCII puro)
# Smokes de A05 VIA portal-api (TEST) - Carril C / Slice 1 / Bloque 7.
# Prueba el camino completo: login -> JWT -> portal-api -> CATALOG (reserva.detalle) ->
# validate payloadIdReserva (1ra defensa) -> firma HMAC -> wrapper n8n -> revalidacion ->
# reads -> render -> envelope JSON data:{reserva,pagos}.
#
# A05 = PRIMERA accion con payload. Por eso, ademas del control de rol:
#  - vicky / socio + id valido  -> reserva.detalle ok:true, data.reserva.id_reserva == id;
#                                  y sesion.contexto INCLUYE 'reserva.detalle'.
#  - jenny + id valido          -> rol_no_permitido (rebota EN EL GATEWAY, antes de firmar);
#                                  y sesion.contexto NO la incluye.
#  - vicky/socio + id inexistente -> no_encontrado (pasa al wrapper, que no halla la fila).
#  - payload invalido (5 formas) -> payload_invalido RECHAZADO EN EL GATEWAY antes de firmar
#                                   (id ausente / string / negativo / decimal / no-safe).
#  - sin JWT                    -> no_autorizado.
#
# NO commitear con credenciales reales: harness local de prueba (TEST). La ANON_KEY es la
# publishable key (publica) de TEST. $IdReservaOk / $IdReservaInexistente: del runsheet B6.
# =============================================================================

try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

# ============ CONFIG - completar/verificar ============
$SUPABASE_URL         = 'https://bdskhhbmcksskkzqkcdp.supabase.co'
$ANON_KEY             = 'sb_publishable_fvbXZk2YZgGIWZj6d25VwA_req0lwTU'   # publishable key (publica) de TEST
$IdReservaOk          = 4         # id_reserva REAL de TEST
$IdReservaInexistente = 1000013   # id calculado garantizado inexistente
$USERS = @(
  @{ nombre = 'vicky';  rol = 'vicky'; email = 'vicky@vitadelta.test';  pass = '1234'; esperaA05 = $true  },
  @{ nombre = 'franco'; rol = 'socio'; email = 'franco@vitadelta.test'; pass = '1234'; esperaA05 = $true  },
  @{ nombre = 'jenny';  rol = 'jenny'; email = 'jenny@vitadelta.test';  pass = '1234'; esperaA05 = $false }
)
# =====================================================

$PORTAL = "$SUPABASE_URL/functions/v1/portal-api"
$AUTH   = "$SUPABASE_URL/auth/v1/token?grant_type=password"
$script:fails = 0
$script:vickyJwt = $null

function Get-Jwt([string]$email, [string]$pass) {
  $body = @{ email = $email; password = $pass } | ConvertTo-Json -Compress
  try {
    $r = Invoke-RestMethod -Uri $AUTH -Method POST -Headers @{ apikey = $ANON_KEY } -ContentType 'application/json' -Body $body
    return $r.access_token
  } catch { Write-Host "  [auth] no pude loguear $email" -ForegroundColor Yellow; return $null }
}

# Envia un body JSON CRUDO (control total de payload, evita rarezas de ConvertTo-Json con
# numeros grandes/decimales).
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
if ($IdReservaOk -le 0 -or $IdReservaInexistente -le 0) {
  Write-Host "Falta completar `$IdReservaOk y `$IdReservaInexistente (runsheet B6)." -ForegroundColor Red
  return
}

# Bodies CRUDOS reutilizados.
$B_CTX = '{"action":"sesion.contexto"}'
$B_OK  = '{"action":"reserva.detalle","payload":{"id_reserva":' + $IdReservaOk + '}}'
$B_NX  = '{"action":"reserva.detalle","payload":{"id_reserva":' + $IdReservaInexistente + '}}'

Write-Host ""
Write-Host "=== Smokes A05 via portal-api (Slice 1 / Bloque 7) ==="
Write-Host ""

foreach ($u in $USERS) {
  Write-Host ("Usuario: {0} ({1})  esperaA05={2}" -f $u.nombre, $u.rol, $u.esperaA05)
  $jwt = Get-Jwt $u.email $u.pass
  if (-not $jwt) { $script:fails++; Write-Host ""; continue }
  if ($u.nombre -eq 'vicky') { $script:vickyJwt = $jwt }

  # a) sesion.contexto: 'reserva.detalle' visible SOLO si el rol la tiene (A05 = vicky/socio)
  $s = Invoke-PortalRaw $jwt $B_CTX
  if ($s) {
    $acc = (@($s.data.acciones) -join ',')
    $tiene = (@($s.data.acciones) -contains 'reserva.detalle')
    if ($u.esperaA05) {
      Assert "sesion.contexto INCLUYE reserva.detalle" ($tiene) "acciones=[$acc]"
    } else {
      Assert "sesion.contexto NO incluye reserva.detalle (jenny)" (-not $tiene) "acciones=[$acc]"
    }
  } else { $script:fails++ }

  # b) reserva.detalle + id valido: vicky/socio -> ok:true (id correcto) ; jenny -> rol_no_permitido
  $r = Invoke-PortalRaw $jwt $B_OK
  if ($r) {
    if ($u.esperaA05) {
      $idr = if ($r.data -and $r.data.reserva) { $r.data.reserva.id_reserva } else { $null }
      Assert "reserva.detalle ok:true"               ($r.ok -eq $true)         "ok=$($r.ok) code=$($r.error.code)"
      Assert "data.reserva.id_reserva=$IdReservaOk"  ($idr -eq $IdReservaOk)   "id_reserva=$idr"
    } else {
      Assert "reserva.detalle ok:false"                          ($r.ok -eq $false)                      "ok=$($r.ok)"
      Assert "error.code=rol_no_permitido (rebota en gateway)"   ($r.error.code -eq 'rol_no_permitido')  "code=$($r.error.code)"
    }
  } else { $script:fails++ }

  # c) (solo vicky/socio) reserva.detalle + id inexistente -> no_encontrado
  if ($u.esperaA05) {
    $r = Invoke-PortalRaw $jwt $B_NX
    if ($r) {
      Assert "id inexistente -> no_encontrado" ($r.error.code -eq 'no_encontrado') "ok=$($r.ok) code=$($r.error.code)"
    } else { $script:fails++ }
  }
  Write-Host ""
}

# d) payload invalido VIA GATEWAY: con JWT de vicky (rol permitido) para llegar al validate.
#    El gateway rechaza ANTES de firmar -> nunca toca n8n.
if ($script:vickyJwt) {
  Write-Host "Payload invalido via gateway (rechazo en el gateway ANTES de firmar):"
  $casos = @(
    @{ n = '{} (id ausente)';   body = '{"action":"reserva.detalle","payload":{}}' },
    @{ n = 'id string ("42")';  body = '{"action":"reserva.detalle","payload":{"id_reserva":"42"}}' },
    @{ n = 'id negativo (-5)';  body = '{"action":"reserva.detalle","payload":{"id_reserva":-5}}' },
    @{ n = 'id decimal (4.5)';  body = '{"action":"reserva.detalle","payload":{"id_reserva":4.5}}' },
    @{ n = 'id no-safe (1e20)'; body = '{"action":"reserva.detalle","payload":{"id_reserva":100000000000000000000}}' }
  )
  foreach ($c in $casos) {
    $r = Invoke-PortalRaw $script:vickyJwt $c.body
    if ($r) {
      Assert ("payload_invalido <- " + $c.n) (($r.ok -eq $false) -and ($r.error.code -eq 'payload_invalido')) "ok=$($r.ok) code=$($r.error.code)"
    } else { $script:fails++ }
  }
  Write-Host ""
} else {
  Write-Host "No pude loguear vicky; salteo los casos de payload invalido." -ForegroundColor Yellow
  $script:fails++
}

# e) sin JWT -> no_autorizado
Write-Host "Sin JWT -> reserva.detalle"
$r = Invoke-PortalRaw $null $B_OK
if ($r) { Assert "error.code=no_autorizado" ($r.error.code -eq 'no_autorizado') "code=$($r.error.code)" }
else    { $script:fails++ }
Write-Host ""

if ($script:fails -eq 0) {
  Write-Host "RESULTADO: sin fallos. A05 anda de punta a punta via portal-api. Bloque 7 / A05 listo." -ForegroundColor Green
} else {
  Write-Host "RESULTADO: $($script:fails) fallo(s). Revisar antes de cerrar." -ForegroundColor Red
}
