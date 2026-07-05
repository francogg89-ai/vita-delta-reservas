# ============================================================================
# portal-a29-retiro__GW_smoke_OPS.ps1 -- SMOKE OPS VIA GATEWAY (portal-api -> wrapper A29__OPS)
# Accion: cuenta_corriente.retirar (ESCRITURA, socio-only). End-to-end con JWT real.
# ASCII puro (PS 5.1 lee .ps1 como Windows-1252; sin acentos ni em-dash). Compatible 5.1/7.
#
# El gateway firma HMAC hacia n8n server-side: este harness NUNCA ve el secreto HMAC.
# Envia { action, payload, idempotency_key } (key SIBLING de payload, D-C-57). El gateway
# inyecta id_socio + user_id server-side (injectSocioIdentity); el harness NO los manda.
#
# OPS NEGATIVE-ONLY: CERO happy-path, CERO retiro real, CERO escrituras. Se quitaron F1/F2/F3
# (retiro real 0.01 + retry idempotente + conflicto) del smoke de TEST -- cualquiera de esos
# CREA o REUSA un retiro real, prohibido en OPS. Todos los casos de aca son rechazos (rol/auth/
# accion/payload/key/id_socio-user_id) o saldo_insuficiente (VD001 ANTES del INSERT). Ninguno
# escribe: 0 filas en movimientos_socio y portal_idempotencia_cc, 0 nextval. saldo_insuficiente
# NO quema la key (savepoint revierte). Verificar el estado en la DB con el companion:
# portal-a29-retiro__GW_verify_OPS.sql (PART A baseline antes/despues + PART B checklist 0-en-todo).
#
# Requisitos (env vars, TODOS con sufijo _OPS para no mezclar con el entorno de prueba):
#   VITA_SUPABASE_URL_OPS, VITA_SUPABASE_ANON_OPS,
#   VITA_EMAIL_FRANCO_OPS/VICKY_OPS/JENNY_OPS, VITA_PW_FRANCO_OPS/VICKY_OPS/JENNY_OPS.
# Correr con el workflow portal-a29-retiro__OPS ACTIVO y el gateway A29 desplegado en OPS.
# Uso:  powershell -ExecutionPolicy Bypass -File .\portal-a29-retiro__GW_smoke.ps1
# ============================================================================
param(
  [string]$SupabaseUrl = $env:VITA_SUPABASE_URL_OPS,
  [string]$AnonKey     = $env:VITA_SUPABASE_ANON_OPS,
  [string]$EmailFranco = $env:VITA_EMAIL_FRANCO_OPS,
  [string]$EmailVicky  = $env:VITA_EMAIL_VICKY_OPS,
  [string]$EmailJenny  = $env:VITA_EMAIL_JENNY_OPS
)
$ErrorActionPreference = "Stop"
if ([string]::IsNullOrEmpty($SupabaseUrl)) { Write-Host "FALTA: setea VITA_SUPABASE_URL_OPS" -ForegroundColor Red; exit 1 }
if ([string]::IsNullOrEmpty($AnonKey))     { Write-Host "FALTA: setea VITA_SUPABASE_ANON_OPS" -ForegroundColor Red; exit 1 }
if ([string]::IsNullOrEmpty($EmailFranco) -or [string]::IsNullOrEmpty($EmailVicky) -or [string]::IsNullOrEmpty($EmailJenny)) {
  Write-Host "FALTA: setea VITA_EMAIL_FRANCO_OPS / VICKY_OPS / JENNY_OPS (emails de los usuarios OPS)" -ForegroundColor Red; exit 1
}
$SupabaseUrl = $SupabaseUrl.TrimEnd('/')
$fnUrl  = "$SupabaseUrl/functions/v1/portal-api"
$ACTION = 'cuenta_corriente.retirar'

# Keys FIJAS con marcador 'smoke-a29gw-' para el verify. NEGATIVE-ONLY => ninguna se escribe
# (rechazo pre-dispatch o saldo_insuficiente con savepoint). No hay clave de happy-path.
$K_SALDO = 'smoke-a29gw-saldo-insuf'
$K_SEC   = 'smoke-a29gw-sec-reject'
$K_AJENO = 'smoke-a29gw-ajeno-payload'
$COMENT  = 'A29 smoke gw OPS'

# ---------- contadores / helpers ----------
$script:passed = 0
$script:failed = 0
$script:fails  = @()
$script:codes  = @{}

$ALLOWLIST = @('payload_invalido','no_autorizado','rol_no_permitido','accion_desconocida','no_encontrado','conflicto','error_entorno','error_interno','estado_incierto','firma_invalida','ts_fuera_de_ventana','raw_body_ausente','ambiente_incorrecto','saldo_insuficiente')

function Get-Jwt {
  param($email, $pw)
  if ([string]::IsNullOrEmpty($pw)) { return $null }
  $body = @{ email = $email; password = $pw } | ConvertTo-Json -Compress
  try {
    $r = Invoke-RestMethod -Uri "$SupabaseUrl/auth/v1/token?grant_type=password" -Method Post -Headers @{ apikey = $AnonKey } -ContentType 'application/json' -Body $body
    return $r.access_token
  } catch { return $null }
}

# POST crudo de un body arbitrario (permite key sibling y bodies de spoof). $Jwt=$null => sin Authorization.
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

# Body A29 estandar { action, payload, idempotency_key }.
function New-Body {
  param($Payload, [string]$Key)
  return @{ action = $ACTION; payload = $Payload; idempotency_key = $Key }
}
# Payload de retiro valido (monto STRING, D-A29-1).
function New-Retiro {
  param([string]$Monto = '0.01', [string]$Medio = 'efectivo', [string]$Coment = $COMENT)
  return [ordered]@{ monto = $Monto; medio_pago = $Medio; comentario = $Coment }
}

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
# saldo_insuficiente CON detail sanitizado numerico (D-A29-3): saldo_disponible + monto_solicitado numeros.
function Assert-SaldoInsuf {
  param($r, $name)
  Track $r
  $c = Get-Code $r
  $d = $null
  if ($r -and $r.error) { $d = $r.error.detail }
  $sd = $null; $ms = $null
  if ($d) { $sd = $d.saldo_disponible; $ms = $d.monto_solicitado }
  $isNum = { param($x) ($x -is [int]) -or ($x -is [long]) -or ($x -is [double]) -or ($x -is [decimal]) }
  $ok = ($r.ok -eq $false) -and ($c -eq 'saldo_insuficiente') -and (& $isNum $sd) -and (& $isNum $ms)
  Record $name $ok "esperaba saldo_insuficiente + detail{saldo_disponible,monto_solicitado} numericos; obtuve code=$c sd=$sd ms=$ms"
}

# ---------- JWTs ----------
$jwtFranco = Get-Jwt $EmailFranco $env:VITA_PW_FRANCO_OPS
$jwtVicky  = Get-Jwt $EmailVicky  $env:VITA_PW_VICKY_OPS
$jwtJenny  = Get-Jwt $EmailJenny  $env:VITA_PW_JENNY_OPS
if (-not $jwtFranco -or -not $jwtVicky -or -not $jwtJenny) {
  Write-Host "FALLO: no se pudieron obtener los 3 JWT (franco/vicky/jenny). Revisar passwords/env." -ForegroundColor Red
  exit 1
}

Write-Host ""
Write-Host "=== A29 GATEWAY SMOKE OPS -- NEGATIVE-ONLY (cuenta_corriente.retirar) ===" -ForegroundColor Cyan
Write-Host ""

# ==========================================================================
# SEGURIDAD / RECHAZOS (0 escrituras: el gateway rechaza ANTES de despachar a n8n)
# ==========================================================================
Assert-Code (Invoke-GwRaw -Body (New-Body -Payload (New-Retiro) -Key $K_SEC) -Jwt $jwtJenny) `
  'S1 jenny -> rol_no_permitido' 'rol_no_permitido'

Assert-Code (Invoke-GwRaw -Body (New-Body -Payload (New-Retiro) -Key $K_SEC) -Jwt $jwtVicky) `
  'S2 vicky -> rol_no_permitido (A29 socio-only)' 'rol_no_permitido'

Assert-Code (Invoke-GwRaw -Body (New-Body -Payload (New-Retiro) -Key $K_SEC) -Jwt $null) `
  'S3 sin JWT -> no_autorizado' 'no_autorizado'

Assert-Code (Invoke-GwRaw -Body @{ action = 'cuenta_corriente.retirar_fantasma'; payload = (New-Retiro); idempotency_key = $K_SEC } -Jwt $jwtFranco) `
  'S4 accion inexistente -> accion_desconocida' 'accion_desconocida'

# --- monto invalido (D-A29-1: STRING, <=12 enteros, <=2 decimales, > 0) ---
Assert-Code (Invoke-GwRaw -Body (New-Body -Payload (New-Retiro -Monto 'abc') -Key $K_SEC) -Jwt $jwtFranco) `
  'S5a monto no numerico -> payload_invalido' 'payload_invalido'
Assert-Code (Invoke-GwRaw -Body (New-Body -Payload (New-Retiro -Monto '10.999') -Key $K_SEC) -Jwt $jwtFranco) `
  'S5b monto 3 decimales -> payload_invalido' 'payload_invalido'
# monto como NUMERO (no string) -> payload_invalido
$pMontoNum = [ordered]@{ monto = 100; medio_pago = 'efectivo'; comentario = $COMENT }
Assert-Code (Invoke-GwRaw -Body (New-Body -Payload $pMontoNum -Key $K_SEC) -Jwt $jwtFranco) `
  'S5c monto como numero (no string) -> payload_invalido' 'payload_invalido'
Assert-Code (Invoke-GwRaw -Body (New-Body -Payload (New-Retiro -Monto '0') -Key $K_SEC) -Jwt $jwtFranco) `
  'S5d monto 0 -> payload_invalido' 'payload_invalido'
Assert-Code (Invoke-GwRaw -Body (New-Body -Payload (New-Retiro -Monto '1000000000000') -Key $K_SEC) -Jwt $jwtFranco) `
  'S5e monto 13 enteros -> payload_invalido' 'payload_invalido'

Assert-Code (Invoke-GwRaw -Body (New-Body -Payload (New-Retiro -Medio 'tarjeta') -Key $K_SEC) -Jwt $jwtFranco) `
  'S6 medio_pago invalido -> payload_invalido' 'payload_invalido'

Assert-Code (Invoke-GwRaw -Body @{ action = $ACTION; payload = 'no-soy-objeto'; idempotency_key = $K_SEC } -Jwt $jwtFranco) `
  'S7 payload string -> payload_invalido' 'payload_invalido'

# --- idempotency_key (needsIdempotencyKey + IDEM_RE) ---
Assert-Code (Invoke-GwRaw -Body @{ action = $ACTION; payload = (New-Retiro) } -Jwt $jwtFranco) `
  'S8 key ausente -> payload_invalido' 'payload_invalido'
Assert-Code (Invoke-GwRaw -Body (New-Body -Payload (New-Retiro) -Key 'abc123') -Jwt $jwtFranco) `
  'S9 key corta (<8) -> payload_invalido' 'payload_invalido'
Assert-Code (Invoke-GwRaw -Body (New-Body -Payload (New-Retiro) -Key 'clave!@#mala') -Jwt $jwtFranco) `
  'S10 key con simbolos -> payload_invalido' 'payload_invalido'

# ==========================================================================
# AJUSTE 1: control DENTRO del payload -> payload_invalido (incluye id_socio/user_id).
# ==========================================================================
foreach ($ck in @('actor','rol','nonce','source_event','creado_por','request_ts','idempotency_key','id_socio','user_id')) {
  $p = New-Retiro
  $p[$ck] = 'x'
  Assert-Code (Invoke-GwRaw -Body (New-Body -Payload $p -Key $K_SEC) -Jwt $jwtFranco) `
    "SP-payload $ck -> payload_invalido" 'payload_invalido'
}

# ==========================================================================
# AJUSTE 1: control TOP-LEVEL -> payload_invalido (incluye id_socio/user_id).
# ==========================================================================
foreach ($ck in @('actor','rol','nonce','id_socio','user_id')) {
  $b = @{ action = $ACTION; payload = (New-Retiro); idempotency_key = $K_SEC }
  $b[$ck] = 'x'
  Assert-Code (Invoke-GwRaw -Body $b -Jwt $jwtFranco) `
    "ST-toplevel $ck -> payload_invalido" 'payload_invalido'
}

# ==========================================================================
# AJUSTE 2: id_socio AJENO dentro del payload -> payload_invalido (NO 'se ignora').
#   El gateway rechaza ANTES de despachar => 0 movimientos y 0 filas en _cc (verify PART B).
# ==========================================================================
$pAjeno = New-Retiro
$pAjeno['id_socio'] = 999999
Assert-Code (Invoke-GwRaw -Body (New-Body -Payload $pAjeno -Key $K_AJENO) -Jwt $jwtFranco) `
  'ADJ2 id_socio ajeno en payload -> payload_invalido (0 escrituras)' 'payload_invalido'

# ==========================================================================
# saldo_insuficiente (VD001 ANTES del INSERT) -- NO escribe, NO quema la key.
#   N-SALDO-1: monto enorme (> cualquier saldo) -> saldo_insuficiente + detail numerico sanitizado.
#   N-SALDO-2: misma key/payload -> saldo_insuficiente OTRA VEZ (si se hubiera quemado, seria replay
#              y daria conflicto). Prueba que la key NO se quema. El verify PART B confirma
#              0 movimientos y 0 filas en portal_idempotencia_cc para K_SALDO.
# ==========================================================================
$r4 = Invoke-GwRaw -Body (New-Body -Payload (New-Retiro -Monto '999999999999') -Key $K_SALDO) -Jwt $jwtFranco
Assert-SaldoInsuf $r4 'N-SALDO-1 monto > saldo -> saldo_insuficiente (+ detail sanitizado)'
$r5 = Invoke-GwRaw -Body (New-Body -Payload (New-Retiro -Monto '999999999999') -Key $K_SALDO) -Jwt $jwtFranco
Assert-SaldoInsuf $r5 'N-SALDO-2 misma key repetida -> saldo_insuficiente (key NO quemada)'

# ==========================================================================
# META: todos los error.code vistos deben estar en la allowlist del gateway (incl saldo_insuficiente).
# ==========================================================================
$bad = @()
foreach ($c in $script:codes.Keys) { if ($ALLOWLIST -notcontains $c) { $bad += $c } }
Record "META allowlist (error.code en allowlist del gateway)" ($bad.Count -eq 0) ("fuera de allowlist: " + ($bad -join ', '))

# ---------- resumen ----------
Write-Host ""
Write-Host "==================================================="
Write-Host ("RESULTADO: {0} PASS / {1} FAIL" -f $script:passed, $script:failed)
if ($script:failed -gt 0) {
  Write-Host "Fallos:"
  $script:fails | ForEach-Object { Write-Host "  - $_" }
}
Write-Host ("Codigos de error vistos: " + ((@($script:codes.Keys) | Sort-Object) -join ', '))
Write-Host ""
Write-Host "Recordatorio: correr portal-a29-retiro__GW_verify_OPS.sql en el SQL Editor para confirmar"
Write-Host "el estado en la DB: PART B checklist debe dar 0 filas nuevas (idem_cc vacia, secuencia sin"
Write-Host "avance) y 0 retiros de smoke en movimientos_socio (negative-only)."
if ($script:failed -gt 0) { exit 1 }
