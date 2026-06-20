# ============================================================================
# C_SLICE2_A08 - BLOQUE 3: SMOKE FUNCIONAL (CON ESCRITURA)
# Wrapper portal-a08-crear-bloqueo__TEST. Corre DESPUES del gate residual (0/0).
#   A  B_FELIZ    cab1 2027-09-01..05  -> ok, id_bloqueo, tipo cabana_especifica
#   B  B_RETRY    = B_FELIZ            -> conflicto (bloqueo_solapado), sin duplicar
#   C  B_SOLAPA   cab1 2027-09-03..07  -> conflicto (bloqueo_solapado con B_FELIZ)
#   D  B_CABANA99 cab99 2027-09-10..12 -> payload_invalido (cabana_no_existe)
# La NO duplicacion (B) se confirma luego en verif_writes (TOTAL_NS=1).
#
# Requisitos: workflow ACTIVO; $env:VITA_HMAC_SECRET_TEST seteado.
# Uso:  pwsh ./C_SLICE2_A08_smoke_funcional.ps1
# ============================================================================
param(
  [string]$BaseUrl = "https://federicosecchi.app.n8n.cloud/webhook",
  [string]$Path    = "portal-a08-crear-bloqueo__TEST"
)
$ErrorActionPreference = "Stop"

$Secret = $env:VITA_HMAC_SECRET_TEST
if (-not $Secret) { Write-Host "FALTA: setea `$env:VITA_HMAC_SECRET_TEST" -ForegroundColor Red; exit 1 }

$enc = [System.Text.Encoding]::UTF8

function New-Sobre {
  param([object]$Payload, [string]$Rol="vicky", [string]$Actor="vicky", [string]$Amb="test")
  $ts = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  return [ordered]@{
    action="bloqueo.crear_manual"; rol=$Rol; actor=$Actor; ambiente_esperado=$Amb
    ts=$ts; nonce=[guid]::NewGuid().ToString(); payload=$Payload
  }
}

function Invoke-A08 {
  param([object]$BodyObj)
  $json = $BodyObj | ConvertTo-Json -Compress -Depth 12
  $bodyBytes = $enc.GetBytes($json)
  $h = [System.Security.Cryptography.HMACSHA256]::new($enc.GetBytes($Secret))
  $sig = "sha256=" + ([System.BitConverter]::ToString($h.ComputeHash($bodyBytes)) -replace '-','').ToLower()
  $headers = @{ "x-vita-signature" = $sig }
  try {
    return Invoke-RestMethod -Uri "$BaseUrl/$Path" -Method Post -Body $bodyBytes `
                             -Headers $headers -ContentType "application/json"
  } catch {
    $r = $_.Exception.Response
    if ($r) { $sr = New-Object System.IO.StreamReader($r.GetResponseStream()); $txt = $sr.ReadToEnd()
              try { return $txt | ConvertFrom-Json } catch { return @{ ok=$false; error=@{ code="_http"; message=$txt } } } }
    return @{ ok=$false; error=@{ code="_neterr"; message=$_.Exception.Message } }
  }
}

$pFELIZ    = [ordered]@{ id_cabana=1;  fecha_desde="2027-09-01"; fecha_hasta="2027-09-05"; motivo="mantenimiento" }
$pSOLAPA   = [ordered]@{ id_cabana=1;  fecha_desde="2027-09-03"; fecha_hasta="2027-09-07"; motivo="mantenimiento" }
$pCABANA99 = [ordered]@{ id_cabana=99; fecha_desde="2027-09-10"; fecha_hasta="2027-09-12"; motivo="mantenimiento" }

Write-Host "`n=== BLOQUE 3: SMOKE FUNCIONAL A08 (con escritura) ===" -ForegroundColor Cyan
Write-Host "URL: $BaseUrl/$Path`n"
$pass = 0; $total = 4

# A - feliz especifico
$rA = Invoke-A08 (New-Sobre $pFELIZ)
$okA = ([bool]$rA.ok -eq $true) -and ($null -ne $rA.data.id_bloqueo) -and ($rA.data.tipo_bloqueo -eq "cabana_especifica") -and ($rA.data.id_cabana -eq 1)
if ($okA){$pass++;Write-Host ("  [PASS] A feliz especifico -> id_bloqueo={0}, tipo={1}, id_cabana={2}" -f $rA.data.id_bloqueo,$rA.data.tipo_bloqueo,$rA.data.id_cabana) -ForegroundColor Green}
else{Write-Host ("  [FAIL] A feliz especifico -> {0}" -f ($rA|ConvertTo-Json -Compress -Depth 6)) -ForegroundColor Red}

# B - retry exacto (mismo bloqueo) -> bloqueo_solapado -> conflicto, sin duplicar
$rB = Invoke-A08 (New-Sobre $pFELIZ)
$okB = ([bool]$rB.ok -eq $false) -and ($rB.error.code -eq "conflicto")
if ($okB){$pass++;Write-Host "  [PASS] B retry exacto -> conflicto (bloqueo_solapado), no duplica" -ForegroundColor Green}
else{Write-Host ("  [FAIL] B retry exacto -> {0}" -f ($rB|ConvertTo-Json -Compress -Depth 6)) -ForegroundColor Red}

# C - bloqueo distinto que solapa parcialmente B_FELIZ -> conflicto
$rC = Invoke-A08 (New-Sobre $pSOLAPA)
$okC = ([bool]$rC.ok -eq $false) -and ($rC.error.code -eq "conflicto")
if ($okC){$pass++;Write-Host "  [PASS] C bloqueo solapado distinto -> conflicto" -ForegroundColor Green}
else{Write-Host ("  [FAIL] C bloqueo solapado distinto -> {0}" -f ($rC|ConvertTo-Json -Compress -Depth 6)) -ForegroundColor Red}

# D - cabana inexistente -> payload_invalido (cabana_no_existe desde crear_bloqueo)
$rD = Invoke-A08 (New-Sobre $pCABANA99)
$okD = ([bool]$rD.ok -eq $false) -and ($rD.error.code -eq "payload_invalido")
if ($okD){$pass++;Write-Host "  [PASS] D cabana inexistente -> payload_invalido (cabana_no_existe)" -ForegroundColor Green}
else{Write-Host ("  [FAIL] D cabana inexistente -> {0}" -f ($rD|ConvertTo-Json -Compress -Depth 6)) -ForegroundColor Red}

$col = if ($pass -eq $total) { "Green" } else { "Red" }
Write-Host ("`nRESULTADO: {0}/{1} PASS" -f $pass,$total) -ForegroundColor $col
Write-Host "Ahora corre C_SLICE2_A08_verif_writes.sql (esperado B_FELIZ=1, B_SOLAPA=0, B_CABANA99=0, TOTAL_NS=1).`n"
if ($pass -ne $total) { exit 1 }
