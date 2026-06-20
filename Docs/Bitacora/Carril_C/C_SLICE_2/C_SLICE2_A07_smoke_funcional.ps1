# ============================================================================
# C_SLICE2_A07 — BLOQUE 3: SMOKES FUNCIONALES (CON ESCRITURA)
# Correr SOLO despues de: Bloque 1 (12/12), gate residual = 0, setup Caso 2.
# Workflow ACTIVO. $env:VITA_HMAC_SECRET_TEST seteado.
#
# Fixtures (fechas 2027, huespedes centinela PORTAL TEST A07 *):
#   FELIZ   cab1 2027-03-01..03  -> crea reserva (idempotent_match:false)
#   FELIZ²  retry identico        -> idempotent_match:true, MISMO id_reserva (Caso 1)
#   NODISP  cab1 mismas fechas    -> conflicto (la reserva FELIZ ocupa)
#   CAPAC   cab5 personas 10      -> payload_invalido (excede_capacidad; no escribe reserva)
#   PARCIAL cab2 2027-04-05..07   -> resume el estado del setup (idempotent_match:false) (Caso 2)
#
# Uso:  pwsh ./C_SLICE2_A07_smoke_funcional.ps1
# ============================================================================
param(
  [string]$BaseUrl = "https://federicosecchi.app.n8n.cloud/webhook",
  [string]$Path    = "portal-a07-crear-reserva__TEST"
)
$ErrorActionPreference = "Stop"
$Secret = $env:VITA_HMAC_SECRET_TEST
if (-not $Secret) { Write-Host "FALTA: setea `$env:VITA_HMAC_SECRET_TEST" -ForegroundColor Red; exit 1 }
$enc = [System.Text.Encoding]::UTF8

function New-Sobre {
  param([object]$Payload, [string]$Rol="vicky", [string]$Actor="vicky", [string]$Amb="test")
  return [ordered]@{
    action="reserva.crear_manual"; rol=$Rol; actor=$Actor; ambiente_esperado=$Amb
    ts=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(); nonce=[guid]::NewGuid().ToString(); payload=$Payload
  }
}
function Invoke-A07 {
  param([object]$BodyObj)
  $json = $BodyObj | ConvertTo-Json -Compress -Depth 12
  $bodyBytes = $enc.GetBytes($json)
  $h = [System.Security.Cryptography.HMACSHA256]::new($enc.GetBytes($Secret))
  $sig = "sha256=" + ([System.BitConverter]::ToString($h.ComputeHash($bodyBytes)) -replace '-','').ToLower()
  try {
    return Invoke-RestMethod -Uri "$BaseUrl/$Path" -Method Post -Body $bodyBytes `
                             -Headers @{ "x-vita-signature"=$sig } -ContentType "application/json"
  } catch {
    $r=$_.Exception.Response
    if ($r){ $sr=New-Object System.IO.StreamReader($r.GetResponseStream()); $t=$sr.ReadToEnd()
             try { return $t | ConvertFrom-Json } catch { return @{ok=$false;error=@{code="_http";message=$t}} } }
    return @{ok=$false;error=@{code="_neterr";message=$_.Exception.Message}}
  }
}

$pFELIZ   = [ordered]@{ id_cabana=1; fecha_in="2027-03-01"; fecha_out="2027-03-03"; personas=2; monto_total=100000; monto_sena=50000; canal_pago_esperado="transferencia_mp"; medio_pago="transferencia_mp"; huesped=[ordered]@{nombre="PORTAL TEST A07 FELIZ"; telefono="+5490000000701"} }
$pNODISP  = [ordered]@{ id_cabana=1; fecha_in="2027-03-01"; fecha_out="2027-03-03"; personas=2; monto_total=100000; monto_sena=50000; canal_pago_esperado="transferencia_mp"; medio_pago="transferencia_mp"; huesped=[ordered]@{nombre="PORTAL TEST A07 NODISP"; telefono="+5490000000704"} }
$pCAPAC   = [ordered]@{ id_cabana=5; fecha_in="2027-06-01"; fecha_out="2027-06-03"; personas=10; monto_total=50000; monto_sena=25000; canal_pago_esperado="transferencia_mp"; medio_pago="transferencia_mp"; huesped=[ordered]@{nombre="PORTAL TEST A07 CAPAC"; telefono="+5490000000705"} }
$pPARCIAL = [ordered]@{ id_cabana=2; fecha_in="2027-04-05"; fecha_out="2027-04-07"; personas=2; monto_total=120000; monto_sena=60000; canal_pago_esperado="transferencia_mp"; medio_pago="transferencia_mp"; huesped=[ordered]@{nombre="PORTAL TEST A07 PARCIAL"; telefono="+5490000000702"} }

Write-Host "`n=== BLOQUE 3: SMOKES FUNCIONALES A07.2 (con escritura) ===" -ForegroundColor Cyan
$pass=0; $total=5

# A — camino feliz
$rA = Invoke-A07 (New-Sobre $pFELIZ)
$okA = ([bool]$rA.ok -eq $true) -and ($rA.data.idempotent_match -eq $false) -and ($rA.data.id_reserva)
if ($okA){$pass++;Write-Host ("  [PASS] A camino feliz -> id_reserva={0} idempotent=false" -f $rA.data.id_reserva) -ForegroundColor Green}
else{Write-Host ("  [FAIL] A camino feliz -> {0}" -f ($rA|ConvertTo-Json -Compress -Depth 6)) -ForegroundColor Red}

# B — Caso 1 retry completo (mismo sobre)
$rB = Invoke-A07 (New-Sobre $pFELIZ)
$okB = ([bool]$rB.ok -eq $true) -and ($rB.data.idempotent_match -eq $true) -and ($rB.data.id_reserva -eq $rA.data.id_reserva)
if ($okB){$pass++;Write-Host ("  [PASS] B Caso1 retry completo -> idempotent=true, id_reserva={0} (igual)" -f $rB.data.id_reserva) -ForegroundColor Green}
else{Write-Host ("  [FAIL] B Caso1 retry completo -> {0}" -f ($rB|ConvertTo-Json -Compress -Depth 6)) -ForegroundColor Red}

# C — no_disponible -> conflicto
$rC = Invoke-A07 (New-Sobre $pNODISP)
$okC = ([bool]$rC.ok -eq $false) -and ($rC.error.code -eq "conflicto")
if ($okC){$pass++;Write-Host "  [PASS] C no_disponible -> conflicto" -ForegroundColor Green}
else{Write-Host ("  [FAIL] C no_disponible -> {0}" -f ($rC|ConvertTo-Json -Compress -Depth 6)) -ForegroundColor Red}

# D — excede_capacidad -> payload_invalido (no crea reserva)
$rD = Invoke-A07 (New-Sobre $pCAPAC)
$okD = ([bool]$rD.ok -eq $false) -and ($rD.error.code -eq "payload_invalido")
if ($okD){$pass++;Write-Host "  [PASS] D excede_capacidad -> payload_invalido" -ForegroundColor Green}
else{Write-Host ("  [FAIL] D excede_capacidad -> {0}" -f ($rD|ConvertTo-Json -Compress -Depth 6)) -ForegroundColor Red}

# E — Caso 2 retry parcial (resume el estado del setup)
$rE = Invoke-A07 (New-Sobre $pPARCIAL)
$okE = ([bool]$rE.ok -eq $true) -and ($rE.data.idempotent_match -eq $false) -and ($rE.data.id_reserva)
if ($okE){$pass++;Write-Host ("  [PASS] E Caso2 retry parcial -> resume, id_reserva={0}" -f $rE.data.id_reserva) -ForegroundColor Green}
else{Write-Host ("  [FAIL] E Caso2 retry parcial -> {0}" -f ($rE|ConvertTo-Json -Compress -Depth 6)) -ForegroundColor Red}

$col = if ($pass -eq $total) { "Green" } else { "Red" }
Write-Host ("`nRESULTADO: {0}/{1} PASS" -f $pass,$total) -ForegroundColor $col
Write-Host "Ahora corre C_SLICE2_A07_verif_writes.sql (esperado FELIZ 1/1/1, PARCIAL 1/1/1, NODISP/CAPAC 0/0/0).`n"
if ($pass -ne $total) { exit 1 }
