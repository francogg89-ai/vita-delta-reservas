# ============================================================================
# A26_smoke_directo.ps1  --  Carril C / Portal Operativo Interno - Bloque A
# Smoke DIRECTO contra el wrapper n8n portal-a26-disponibilidad__OPS (sin gateway).
# 100% OPS. READ-ONLY: A26 es lectura, no consume secuencias (D-PROMO-09).
#
# Prueba el contrato A26 'disponibilidad.cabana':
#   - cabana activa sin ocupacion  -> ok:true, dias no vacio, todos 'disponible'
#   - id inexistente/inactiva      -> no_encontrado (NUNCA ok:true con dias:[])
#   - rango invertido / span > 366 -> payload_invalido
#   - ventana con ocupacion        -> estructura OK + volcado para paridad oracle
#   - intervalo [fecha_in,fecha_out) con dia de checkout -> checkout_disponible
#   + seguridad: firma, rol, action, ambiente, claves desconocidas, id_cabana
#
# PS 5.1 / Windows. ASCII puro. Firma HMAC-SHA256 sobre los bytes EXACTOS del
# cuerpo (igual molde que el smoke A25). No requiere modulos externos.
#
# USO:
#   1) Defini $env:VITA_OPS_A26_HMAC con el secreto HMAC de OPS (NO se hardcodea).
#   2) Ajusta $CabValida / $CabInvalida si en OPS no son 1 / 999999.
#   3) (opcional) Completa $OcupDesde/$OcupHasta/$FechaCheckout desde
#      A26_smoke_oracle_OPS.sql para activar T5/T6 (si quedan vacios, se SALTEAN).
#   4) Activa el workflow en n8n (o usa $WebhookSeg='webhook-test' con "Listen").
#   5) powershell -ExecutionPolicy Bypass -File .\A26_smoke_directo.ps1
# ============================================================================

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ===== PARAMETROS (editar antes de correr) ==================================
$Secret    = $env:VITA_OPS_A26_HMAC                                                       # secreto HMAC OPS desde variable de entorno (NUNCA hardcodeado)
$BaseUrl   = 'https://federicosecchi.app.n8n.cloud'
$Webhook   = 'portal-a26-disponibilidad__OPS'
$WebhookSeg= 'webhook'                             # 'webhook' (activo) o 'webhook-test' (editor)
$Ambiente  = 'ops'                                # ambiente_esperado del sobre (== configuracion_general)

$CabValida   = 1                                  # id de una cabana ACTIVA en OPS (confirmar con [A] del oracle; cabanas 1-5)
$CabInvalida = 999999                             # id positivo SIN cabana activa -> no_encontrado

# Ventana de OCUPACION (T5) y fecha de CHECKOUT (T6): completar desde el oracle.
$CabOcup       = 5                                          # <<< cabana OPS con ocupacion (del oracle OPS); ajustar
$OcupDesde     = ''                                         # <<< 'yyyy-MM-dd' inclusive (del oracle OPS). Vacio => T5/T6 SKIP
$OcupHasta     = ''                                         # <<< 'yyyy-MM-dd' exclusive (del oracle OPS)
$FechaCheckout = ''                                         # <<< 'yyyy-MM-dd' checkout_disponible (del oracle OPS)

# Ventana presuntamente LIBRE para T1 (lejos en el futuro). Override si hace falta.
$LibreDesde = (Get-Date).Date.AddDays(400).ToString('yyyy-MM-dd')
$LibreHasta = (Get-Date).Date.AddDays(405).ToString('yyyy-MM-dd')

# Codigos que el wrapper DIRECTO puede emitir (allowlist anti-fuga).
$ALLOW = @('ok','firma_invalida','ts_fuera_de_ventana','rol_no_permitido',
           'accion_desconocida','payload_invalido','ambiente_incorrecto',
           'no_encontrado','error_interno','raw_body_ausente')

# ===== Guards de precondicion ==============================================
if ([string]::IsNullOrWhiteSpace($Secret) -or $Secret.StartsWith('__PEGAR_')) {
  Write-Host 'ERROR: falta el secreto HMAC OPS. Defini $env:VITA_OPS_A26_HMAC (no se imprime).' -ForegroundColor Red
  exit 2
}

# ===== Guard anti-OPS (adaptado de D-PROMO-C-10 al smoke directo) ===========
# Este smoke SOLO debe pegarle al wrapper OPS. Si el path no termina en __OPS o
# el ambiente del sobre no es 'ops', FRENA (exit 3) antes de firmar o enviar.
if (-not $Webhook.EndsWith('__OPS')) { Write-Host 'GUARD OPS: $Webhook no termina en __OPS. FRENO.' -ForegroundColor Red; exit 3 }
if ($Ambiente -ne 'ops')             { Write-Host ("GUARD OPS: ambiente != ops ({0}). FRENO." -f $Ambiente) -ForegroundColor Red; exit 3 }

# ===== Estado =============================================================
$script:PASS = 0; $script:FAIL = 0; $script:SKIP = 0
$ENUM = @('disponible','checkout_disponible','ocupada','bloqueada')

# ===== Helpers ============================================================
function Now-Ms {
  $epoch = New-Object DateTime(1970,1,1,0,0,0,([DateTimeKind]::Utc))
  [long](([DateTime]::UtcNow - $epoch).TotalMilliseconds)
}
function Day([int]$delta){ (Get-Date).Date.AddDays($delta).ToString('yyyy-MM-dd') }

function Get-Signature([byte[]]$bytes,[string]$secret){
  $h = New-Object System.Security.Cryptography.HMACSHA256
  $h.Key = [Text.Encoding]::UTF8.GetBytes($secret)
  $hash = $h.ComputeHash($bytes)
  $sb = New-Object System.Text.StringBuilder
  foreach($b in $hash){ [void]$sb.Append($b.ToString('x2')) }
  'sha256=' + $sb.ToString()
}

function Invoke-A26 {
  param(
    [hashtable]$Payload,
    [string]$Rol = 'vicky',
    [string]$Action = 'disponibilidad.cabana',
    [string]$AmbEsperado = $Ambiente,
    [long]$Ts = -1,
    [switch]$TamperSig
  )
  if ($Ts -lt 0) { $Ts = Now-Ms }
  $sobre = [ordered]@{
    action            = $Action
    payload           = $Payload
    rol               = $Rol
    ambiente_esperado = $AmbEsperado
    ts                = $Ts
    nonce             = [guid]::NewGuid().ToString('N')
  }
  $json  = ($sobre | ConvertTo-Json -Compress -Depth 8)
  $bytes = [Text.Encoding]::UTF8.GetBytes($json)
  $sig   = Get-Signature $bytes $Secret
  if ($TamperSig) {
    $last = $sig.Substring($sig.Length-1,1)
    $repl = '0'; if ($last -eq '0') { $repl = '1' }
    $sig  = $sig.Substring(0,$sig.Length-1) + $repl
  }

  $url = "$BaseUrl/$WebhookSeg/$Webhook"
  $req = [Net.HttpWebRequest]::Create($url)
  $req.Method = 'POST'
  $req.ContentType = 'application/json'
  $req.Headers.Add('x-vita-signature', $sig)
  $req.ContentLength = $bytes.Length
  $rs = $req.GetRequestStream(); $rs.Write($bytes,0,$bytes.Length); $rs.Close()

  $resp = $null
  try { $resp = $req.GetResponse() }
  catch [Net.WebException] { $resp = $_.Exception.Response }
  if ($resp -eq $null) { return [pscustomobject]@{ http=0; raw=''; obj=$null } }

  $sr  = New-Object IO.StreamReader($resp.GetResponseStream())
  $txt = $sr.ReadToEnd(); $sr.Close()
  $code = 0; try { $code = [int]$resp.StatusCode } catch {}
  $obj = $null; try { $obj = $txt | ConvertFrom-Json } catch {}
  return [pscustomobject]@{ http=$code; raw=$txt; obj=$obj }
}

function Expect-Ok($resp){
  if ($resp.obj -eq $null) { Write-Host "   (sin JSON; http=$($resp.http) raw=$($resp.raw))"; return $false }
  if ($resp.obj.ok -ne $true) {
    $c = $null; if ($resp.obj.error) { $c = $resp.obj.error.code }
    Write-Host "   esperaba ok:true, vino ok:$($resp.obj.ok) code:$c"; return $false
  }
  return $true
}
function Expect-Error($resp,[string]$expCode){
  if ($resp.obj -eq $null) { Write-Host "   (sin JSON; http=$($resp.http) raw=$($resp.raw))"; return $false }
  if ($resp.obj.ok -ne $false) { Write-Host "   esperaba ok:false, vino ok:$($resp.obj.ok)"; return $false }
  $code = $null; if ($resp.obj.error) { $code = $resp.obj.error.code }
  if (-not ($ALLOW -contains $code)) { Write-Host "   codigo FUERA de allowlist: $code"; return $false }
  if ($code -ne $expCode) { Write-Host "   esperaba $expCode, vino $code"; return $false }
  return $true
}

function Test-Dias($diasRaw,[string]$desde,[string]$hasta,[bool]$allDisponible){
  $dias = @($diasRaw)
  if ($dias.Count -eq 0) { Write-Host "   dias vacio (no permitido para cabana activa)"; return $false }
  $dD = [DateTime]::ParseExact($desde,'yyyy-MM-dd',$null)
  $dH = [DateTime]::ParseExact($hasta,'yyyy-MM-dd',$null)
  $spanDays = [int]($dH - $dD).Days
  if ($dias.Count -ne $spanDays) { Write-Host "   count=$($dias.Count) != span=$spanDays"; return $false }
  $prev = $null
  for ($i=0; $i -lt $dias.Count; $i++) {
    $d = $dias[$i]
    if (-not ($ENUM -contains $d.estado)) { Write-Host "   estado invalido en $($d.fecha): $($d.estado)"; return $false }
    if ($allDisponible -and $d.estado -ne 'disponible') { Write-Host "   esperaba disponible en $($d.fecha): $($d.estado)"; return $false }
    if ($i -eq 0 -and $d.fecha -ne $desde) { Write-Host "   primer dia=$($d.fecha) != desde=$desde"; return $false }
    if ($d.id_cabana -eq $null -or [int]$d.id_cabana -ne [int]$script:CabOcupRef) {
      Write-Host "   id_cabana del dia $($d.fecha) = $($d.id_cabana) (esperaba $($script:CabOcupRef))"; return $false
    }
    if ($prev -ne $null) {
      $exp = ([DateTime]::ParseExact($prev,'yyyy-MM-dd',$null)).AddDays(1).ToString('yyyy-MM-dd')
      if ($d.fecha -ne $exp) { Write-Host "   no contiguo: $prev -> $($d.fecha)"; return $false }
    }
    $prev = $d.fecha
  }
  $lastExp = $dH.AddDays(-1).ToString('yyyy-MM-dd')   # intervalo [) : ultima NOCHE = hasta - 1 dia
  if ($dias[$dias.Count-1].fecha -ne $lastExp) { Write-Host "   ultimo=$($dias[$dias.Count-1].fecha) != hasta-1=$lastExp"; return $false }
  return $true
}

function Test-Case([string]$name,[scriptblock]$body){
  try {
    $r = & $body
    if (($r -is [string]) -and ($r -eq 'SKIP')) {
      $script:SKIP++
      Write-Host ("SKIP  {0}" -f $name) -ForegroundColor Yellow
    }
    elseif ($r -eq $true) {
      $script:PASS++
      Write-Host ("PASS  {0}" -f $name) -ForegroundColor Green
    }
    else {
      $script:FAIL++
      Write-Host ("FAIL  {0}" -f $name) -ForegroundColor Red
    }
  } catch {
    $script:FAIL++; Write-Host ("FAIL  {0} (excepcion: {1})" -f $name,$_.Exception.Message) -ForegroundColor Red
  }
}

# ===== Cabecera ===========================================================
Write-Host ''
Write-Host '=== A26 smoke directo (OPS, read-only) ===' -ForegroundColor Cyan
Write-Host ("    url        : {0}/{1}/{2}" -f $BaseUrl,$WebhookSeg,$Webhook)
Write-Host ("    cab valida : {0}   cab invalida: {1}" -f $CabValida,$CabInvalida)
Write-Host ("    libre      : {0} -> {1}" -f $LibreDesde,$LibreHasta)
Write-Host ''

# ===== Casos de contrato (minimos pedidos) ================================
$script:CabOcupRef = $CabValida
Test-Case 'T1 cabana activa SIN ocupacion -> ok:true, dias todos disponible' {
  $r = Invoke-A26 -Payload @{ id_cabana=$CabValida; fecha_desde=$LibreDesde; fecha_hasta=$LibreHasta }
  if (-not (Expect-Ok $r)) { return $false }
  Test-Dias $r.obj.data.dias $LibreDesde $LibreHasta $true
}

Test-Case 'T2 id positivo inexistente/inactiva -> no_encontrado' {
  $r = Invoke-A26 -Payload @{ id_cabana=$CabInvalida; fecha_desde=$LibreDesde; fecha_hasta=$LibreHasta }
  Expect-Error $r 'no_encontrado'
}

Test-Case 'T3 rango invertido (hasta <= desde) -> payload_invalido' {
  $r = Invoke-A26 -Payload @{ id_cabana=$CabValida; fecha_desde=(Day 20); fecha_hasta=(Day 10) }
  Expect-Error $r 'payload_invalido'
}

Test-Case 'T4 span > 366 dias -> payload_invalido' {
  $r = Invoke-A26 -Payload @{ id_cabana=$CabValida; fecha_desde=(Day 10); fecha_hasta=(Day 410) }
  Expect-Error $r 'payload_invalido'
}

$script:CabOcupRef = $CabOcup
Test-Case 'T5 ventana CON ocupacion -> estructura OK + volcado (paridad oracle)' {
  if ($OcupDesde -eq '' -or $OcupHasta -eq '') { Write-Host '   (definir $OcupDesde/$OcupHasta desde el oracle)'; return 'SKIP' }
  $r = Invoke-A26 -Payload @{ id_cabana=$CabOcup; fecha_desde=$OcupDesde; fecha_hasta=$OcupHasta }
  if (-not (Expect-Ok $r)) { return $false }
  Write-Host '   --- volcado dias (comparar con A26_smoke_oracle.sql) ---'
  foreach ($d in @($r.obj.data.dias)) { Write-Host ("   {0}  {1}" -f $d.fecha,$d.estado) }
  Test-Dias $r.obj.data.dias $OcupDesde $OcupHasta $false
}

Test-Case 'T6 dia de checkout dentro de [in,out) -> checkout_disponible' {
  if ($OcupDesde -eq '' -or $OcupHasta -eq '' -or $FechaCheckout -eq '') { Write-Host '   (definir $FechaCheckout dentro de la ventana)'; return 'SKIP' }
  $r = Invoke-A26 -Payload @{ id_cabana=$CabOcup; fecha_desde=$OcupDesde; fecha_hasta=$OcupHasta }
  if (-not (Expect-Ok $r)) { return $false }
  $hit = @($r.obj.data.dias) | Where-Object { $_.fecha -eq $FechaCheckout }
  if ($hit -eq $null) { Write-Host "   $FechaCheckout no esta en la ventana"; return $false }
  if ($hit.estado -ne 'checkout_disponible') { Write-Host "   $FechaCheckout estado=$($hit.estado) (esperaba checkout_disponible)"; return $false }
  return $true
}

# ===== Seguridad / robustez ==============================================
Test-Case 'T7 firma HMAC invalida -> firma_invalida' {
  $r = Invoke-A26 -Payload @{ id_cabana=$CabValida; fecha_desde=$LibreDesde; fecha_hasta=$LibreHasta } -TamperSig
  Expect-Error $r 'firma_invalida'
}
Test-Case 'T8 rol jenny -> rol_no_permitido' {
  $r = Invoke-A26 -Payload @{ id_cabana=$CabValida; fecha_desde=$LibreDesde; fecha_hasta=$LibreHasta } -Rol 'jenny'
  Expect-Error $r 'rol_no_permitido'
}
Test-Case 'T9 action equivocada -> accion_desconocida' {
  $r = Invoke-A26 -Payload @{ id_cabana=$CabValida; fecha_desde=$LibreDesde; fecha_hasta=$LibreHasta } -Action 'reserva.detalle'
  Expect-Error $r 'accion_desconocida'
}
Test-Case 'T10 ambiente_esperado=test (mismatch en OPS) -> ambiente_incorrecto' {
  $r = Invoke-A26 -Payload @{ id_cabana=$CabValida; fecha_desde=$LibreDesde; fecha_hasta=$LibreHasta } -AmbEsperado 'test'
  Expect-Error $r 'ambiente_incorrecto'
}
Test-Case 'T11 clave desconocida en payload -> payload_invalido' {
  $r = Invoke-A26 -Payload @{ id_cabana=$CabValida; fecha_desde=$LibreDesde; fecha_hasta=$LibreHasta; extra='x' }
  Expect-Error $r 'payload_invalido'
}
Test-Case 'T12a id_cabana=0 -> payload_invalido' {
  $r = Invoke-A26 -Payload @{ id_cabana=0; fecha_desde=$LibreDesde; fecha_hasta=$LibreHasta }
  Expect-Error $r 'payload_invalido'
}
Test-Case 'T12b id_cabana negativo -> payload_invalido' {
  $r = Invoke-A26 -Payload @{ id_cabana=-3; fecha_desde=$LibreDesde; fecha_hasta=$LibreHasta }
  Expect-Error $r 'payload_invalido'
}
Test-Case 'T12c id_cabana string -> payload_invalido' {
  $r = Invoke-A26 -Payload @{ id_cabana='1'; fecha_desde=$LibreDesde; fecha_hasta=$LibreHasta }
  Expect-Error $r 'payload_invalido'
}
Test-Case 'T13 falta fecha_hasta -> payload_invalido' {
  $r = Invoke-A26 -Payload @{ id_cabana=$CabValida; fecha_desde=$LibreDesde }
  Expect-Error $r 'payload_invalido'
}

# ===== Resumen ============================================================
Write-Host ''
Write-Host ('===== RESUMEN  PASS={0}  FAIL={1}  SKIP={2} =====' -f $script:PASS,$script:FAIL,$script:SKIP) -ForegroundColor Cyan
if ($script:FAIL -gt 0) { exit 1 } else { exit 0 }
