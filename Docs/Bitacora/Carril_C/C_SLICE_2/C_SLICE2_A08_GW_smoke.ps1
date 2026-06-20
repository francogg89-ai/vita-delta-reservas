# ============================================================================
# C_SLICE2_A08_GW - SMOKE VIA GATEWAY (portal-api -> wrapper A08)
# Corre los casos end-to-end a traves del gateway con JWT real. ASCII puro.
# Compatible 5.1/7.
#
# Casos:
#   a) vicky  + bloqueo.crear_manual + payload valido -> ok (crea; creado_por=vicky)
#   b) franco + bloqueo.crear_manual + payload valido -> ok (crea; creado_por=franco)
#   c) jenny  + bloqueo.crear_manual                  -> rol_no_permitido (gateway)
#   d) SIN JWT + bloqueo.crear_manual                 -> no_autorizado
#   e) vicky  + payload invalido (id_cabana 0)        -> payload_invalido (gateway)
#   f) vicky  + creado_por DENTRO del payload (spoof)  -> payload_invalido (reject-unknown)
#   g) vicky  + action inexistente                    -> accion_desconocida
#
# El actor (creado_por) lo inyecta el gateway desde el JWT (el smoke NO lo manda):
# a/b prueban la inyeccion server-side; el verif SQL confirma bloqueos.creado_por.
# a usa cab2 y b cab3 (source_event distinto) para que ambos creen sin solaparse.
#
# Requisitos: VITA_SUPABASE_URL_TEST, VITA_SUPABASE_ANON_TEST, VITA_PW_VICKY,
# VITA_PW_FRANCO, VITA_PW_JENNY. Precheck en verde, gate residual=0, workflow ACTIVO.
# Uso:  powershell -ExecutionPolicy Bypass -File .\C_SLICE2_A08_GW_smoke.ps1
# ============================================================================
param(
  [string]$SupabaseUrl = $env:VITA_SUPABASE_URL_TEST,
  [string]$AnonKey     = $env:VITA_SUPABASE_ANON_TEST
)
$ErrorActionPreference = "Stop"
if (-not $SupabaseUrl) { Write-Host "FALTA: setea `$env:VITA_SUPABASE_URL_TEST" -ForegroundColor Red; exit 1 }
if (-not $AnonKey)     { Write-Host "FALTA: setea `$env:VITA_SUPABASE_ANON_TEST" -ForegroundColor Red; exit 1 }
$SupabaseUrl = $SupabaseUrl.TrimEnd('/')
$fnUrl = "$SupabaseUrl/functions/v1/portal-api"

function Get-Jwt {
  param($email, $pw)
  if (-not $pw) { return $null }
  $body = @{ email=$email; password=$pw } | ConvertTo-Json -Compress
  try {
    $r = Invoke-RestMethod -Uri "$SupabaseUrl/auth/v1/token?grant_type=password" -Method Post `
                           -Headers @{ apikey=$AnonKey } -ContentType "application/json" -Body $body
    return $r.access_token
  } catch { return $null }
}
function Invoke-Gw {
  param($jwt, $action, $payload)
  $body = @{ action=$action; payload=$payload } | ConvertTo-Json -Compress -Depth 8
  $headers = @{ apikey=$AnonKey }
  if ($jwt) { $headers['Authorization'] = "Bearer $jwt" }
  try {
    return Invoke-RestMethod -Uri $fnUrl -Method Post -Headers $headers -ContentType "application/json" -Body $body
  } catch {
    $resp = $_.Exception.Response
    if ($resp) { $sr = New-Object System.IO.StreamReader($resp.GetResponseStream()); $t = $sr.ReadToEnd()
                 try { return ($t | ConvertFrom-Json) } catch { return @{ ok=$false; error=@{ code='_http'; message=$t } } } }
    return @{ ok=$false; error=@{ code='_neterr'; message=$_.Exception.Message } }
  }
}

$jwtVicky  = Get-Jwt 'vicky@vitadelta.test'  $env:VITA_PW_VICKY
$jwtFranco = Get-Jwt 'franco@vitadelta.test' $env:VITA_PW_FRANCO
$jwtJenny  = Get-Jwt 'jenny@vitadelta.test'  $env:VITA_PW_JENNY
if (-not $jwtVicky -or -not $jwtFranco -or -not $jwtJenny) {
  Write-Host "FALTA algun JWT (corre el precheck primero)." -ForegroundColor Red; exit 1
}

# payloads validos (cab distinta por caso para no solaparse)
$pVicky  = @{ id_cabana=2; fecha_desde="2027-10-01"; fecha_hasta="2027-10-03"; motivo="mantenimiento" }
$pFranco = @{ id_cabana=3; fecha_desde="2027-10-01"; fecha_hasta="2027-10-03"; motivo="mantenimiento" }
$pSpoof  = @{ id_cabana=2; fecha_desde="2027-10-05"; fecha_hasta="2027-10-07"; motivo="mantenimiento"; creado_por="rodrigo" }
$pInval  = @{ id_cabana=0; fecha_desde="2027-10-01"; fecha_hasta="2027-10-03"; motivo="mantenimiento" }

Write-Host "`n=== SMOKE VIA GATEWAY A08 (portal-api -> wrapper A08) ===" -ForegroundColor Cyan
Write-Host "URL: $fnUrl`n"
$pass = 0; $total = 7

# a) vicky feliz
$ra = Invoke-Gw $jwtVicky 'bloqueo.crear_manual' $pVicky
$oka = ([bool]$ra.ok -eq $true) -and ($null -ne $ra.data.id_bloqueo) -and ($ra.data.tipo_bloqueo -eq "cabana_especifica")
if ($oka){$pass++;Write-Host ("  [PASS] a vicky feliz -> id_bloqueo={0} (creado_por=vicky via JWT)" -f $ra.data.id_bloqueo) -ForegroundColor Green}
else{Write-Host ("  [FAIL] a vicky feliz -> {0}" -f ($ra|ConvertTo-Json -Compress -Depth 6)) -ForegroundColor Red}

# b) franco (socio) feliz
$rb = Invoke-Gw $jwtFranco 'bloqueo.crear_manual' $pFranco
$okb = ([bool]$rb.ok -eq $true) -and ($null -ne $rb.data.id_bloqueo) -and ($rb.data.tipo_bloqueo -eq "cabana_especifica")
if ($okb){$pass++;Write-Host ("  [PASS] b socio/franco feliz -> id_bloqueo={0} (creado_por=franco via JWT)" -f $rb.data.id_bloqueo) -ForegroundColor Green}
else{Write-Host ("  [FAIL] b socio/franco feliz -> {0}" -f ($rb|ConvertTo-Json -Compress -Depth 6)) -ForegroundColor Red}

# c) jenny -> rol_no_permitido (gateway, antes de firmar)
$rc = Invoke-Gw $jwtJenny 'bloqueo.crear_manual' $pVicky
$okc = ([bool]$rc.ok -eq $false) -and ($rc.error.code -eq "rol_no_permitido")
if ($okc){$pass++;Write-Host "  [PASS] c jenny -> rol_no_permitido" -ForegroundColor Green}
else{Write-Host ("  [FAIL] c jenny -> {0}" -f ($rc|ConvertTo-Json -Compress -Depth 6)) -ForegroundColor Red}

# d) sin JWT -> no_autorizado
$rd = Invoke-Gw $null 'bloqueo.crear_manual' $pVicky
$okd = ([bool]$rd.ok -eq $false) -and ($rd.error.code -eq "no_autorizado")
if ($okd){$pass++;Write-Host "  [PASS] d sin JWT -> no_autorizado" -ForegroundColor Green}
else{Write-Host ("  [FAIL] d sin JWT -> {0}" -f ($rd|ConvertTo-Json -Compress -Depth 6)) -ForegroundColor Red}

# e) payload invalido (id_cabana 0) -> payload_invalido (gateway)
$re = Invoke-Gw $jwtVicky 'bloqueo.crear_manual' $pInval
$oke = ([bool]$re.ok -eq $false) -and ($re.error.code -eq "payload_invalido")
if ($oke){$pass++;Write-Host "  [PASS] e payload invalido (id_cabana 0) -> payload_invalido" -ForegroundColor Green}
else{Write-Host ("  [FAIL] e payload invalido -> {0}" -f ($re|ConvertTo-Json -Compress -Depth 6)) -ForegroundColor Red}

# f) creado_por dentro del payload (spoof) -> payload_invalido (reject-unknown)
$rf = Invoke-Gw $jwtVicky 'bloqueo.crear_manual' $pSpoof
$okf = ([bool]$rf.ok -eq $false) -and ($rf.error.code -eq "payload_invalido")
if ($okf){$pass++;Write-Host "  [PASS] f creado_por en payload (spoof) -> payload_invalido (reject-unknown)" -ForegroundColor Green}
else{Write-Host ("  [FAIL] f spoof creado_por -> {0}" -f ($rf|ConvertTo-Json -Compress -Depth 6)) -ForegroundColor Red}

# g) action inexistente -> accion_desconocida
$rg = Invoke-Gw $jwtVicky 'bloqueo.inexistente' $pVicky
$okg = ([bool]$rg.ok -eq $false) -and ($rg.error.code -eq "accion_desconocida")
if ($okg){$pass++;Write-Host "  [PASS] g action inexistente -> accion_desconocida" -ForegroundColor Green}
else{Write-Host ("  [FAIL] g action inexistente -> {0}" -f ($rg|ConvertTo-Json -Compress -Depth 6)) -ForegroundColor Red}

$col = if ($pass -eq $total) { "Green" } else { "Red" }
Write-Host ("`nRESULTADO: {0}/{1} PASS" -f $pass,$total) -ForegroundColor $col
Write-Host "Ahora corre C_SLICE2_A08_GW_verif.sql (GW_VICKY creado_por=vicky, GW_FRANCO creado_por=franco, ambos 1 fila).`n"
if ($pass -ne $total) { exit 1 }
