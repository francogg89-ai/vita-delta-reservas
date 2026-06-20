# ============================================================================
# C_SLICE2_A07 — BLOQUE 4: SMOKE DE CONCURRENCIA (CON ESCRITURA)
# Dispara N POSTs SIMULTANEOS con el MISMO sobre (mismo idem CONCUR). El
# advisory lock de PG-2 (pg_advisory_xact_lock sobre el idem) serializa el
# registro de seña, y la idempotencia de crear_prereserva + el recheck de
# confirmar_reserva (estado_invalido='convertida' -> PG-4) garantizan que NO se
# duplica: 1 reserva, 1 seña. Todos los POSTs deben volver ok:true (uno con
# idempotent_match:false, el resto true).
#
# Compatible con Windows PowerShell 5.1 y PowerShell 7 (usa RunspacePool, no -Parallel).
# Workflow ACTIVO.
# $env:VITA_HMAC_SECRET_TEST seteado. Correr despues del funcional.
#
# Uso:  pwsh ./C_SLICE2_A07_smoke_concurrencia.ps1
# ============================================================================
param(
  [string]$BaseUrl = "https://federicosecchi.app.n8n.cloud/webhook",
  [string]$Path    = "portal-a07-crear-reserva__TEST",
  [int]$N          = 8
)
$ErrorActionPreference = "Stop"
$Secret = $env:VITA_HMAC_SECRET_TEST
if (-not $Secret) { Write-Host "FALTA: setea `$env:VITA_HMAC_SECRET_TEST" -ForegroundColor Red; exit 1 }
$enc = [System.Text.Encoding]::UTF8

# Un unico sobre CONCUR; ts/nonce fijos (el idem NO depende de ellos, no hay store de nonce).
$sobre = [ordered]@{
  action="reserva.crear_manual"; rol="vicky"; actor="vicky"; ambiente_esperado="test"
  ts=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(); nonce=[guid]::NewGuid().ToString()
  payload=[ordered]@{ id_cabana=3; fecha_in="2027-05-10"; fecha_out="2027-05-12"; personas=2
    monto_total=90000; monto_sena=45000; canal_pago_esperado="transferencia_mp"; medio_pago="transferencia_mp"
    huesped=[ordered]@{ nombre="PORTAL TEST A07 CONCUR"; telefono="+5490000000703" } }
}
$json = $sobre | ConvertTo-Json -Compress -Depth 12
$h = [System.Security.Cryptography.HMACSHA256]::new($enc.GetBytes($Secret))
$sig = "sha256=" + ([System.BitConverter]::ToString($h.ComputeHash($enc.GetBytes($json))) -replace '-','').ToLower()
$uri = "$BaseUrl/$Path"

Write-Host "`n=== BLOQUE 4: SMOKE DE CONCURRENCIA A07.2 ($N POSTs simultaneos) ===" -ForegroundColor Cyan

# Concurrencia real in-process compatible con Windows PowerShell 5.1 (RunspacePool).
# Todos los BeginInvoke se disparan antes de recolectar, asi los POSTs solapan.
$pool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, $N)
$pool.Open()
$worker = {
  param($uri, $json, $sig, $idx)
  $b = [System.Text.Encoding]::UTF8.GetBytes($json)
  try {
    $r = Invoke-RestMethod -Uri $uri -Method Post -Body $b `
                           -Headers @{ "x-vita-signature"=$sig } -ContentType "application/json"
    [pscustomobject]@{ i=$idx; ok=[bool]$r.ok; idem=$r.data.idempotent_match; id_reserva=$r.data.id_reserva; code=$r.error.code }
  } catch {
    [pscustomobject]@{ i=$idx; ok=$false; idem=$null; id_reserva=$null; code="_neterr" }
  }
}
$invokes = @()
for ($i = 1; $i -le $N; $i++) {
  $ps = [PowerShell]::Create()
  $ps.RunspacePool = $pool
  [void]$ps.AddScript($worker).AddArgument($uri).AddArgument($json).AddArgument($sig).AddArgument($i)
  $invokes += [pscustomobject]@{ PS = $ps; Handle = $ps.BeginInvoke() }
}
$results = @()
foreach ($inv in $invokes) {
  $results += $inv.PS.EndInvoke($inv.Handle)
  $inv.PS.Dispose()
}
$pool.Close(); $pool.Dispose()

$results | Sort-Object i | Format-Table -AutoSize
$allOk    = ($results | Where-Object { -not $_.ok } | Measure-Object).Count -eq 0
$idsDist  = ($results | Where-Object { $_.id_reserva } | Select-Object -ExpandProperty id_reserva | Sort-Object -Unique)
$nCreate  = ($results | Where-Object { $_.idem -eq $false } | Measure-Object).Count

Write-Host ("`nTodos ok:true       : {0}" -f $allOk)
Write-Host ("id_reserva distintos: {0}  -> {1}" -f $idsDist.Count, ($idsDist -join ', '))
Write-Host ("idempotent_match=false (creadores): {0}" -f $nCreate)
$verdict = $allOk -and ($idsDist.Count -eq 1) -and ($nCreate -eq 1)
$vtxt = if ($verdict) { "OK (todos ok, 1 id_reserva, 1 creador)" } else { "REVISAR" }
$vcol = if ($verdict) { "Green" } else { "Red" }
Write-Host ("`nVEREDICTO PRELIMINAR: {0}" -f $vtxt) -ForegroundColor $vcol

# Diagnostico de la carrera PG-0/PG-1 (hipotesis): un request que devuelve
# 'conflicto' con un UNICO id_reserva no es duplicacion, sino falta de rama de
# recheck en router1_crear ante no_disponible por carrera (L-C candidata).
$nConfl = ($results | Where-Object { $_.code -eq "conflicto" } | Measure-Object).Count
if ($nConfl -gt 0 -and $idsDist.Count -le 1) {
  Write-Host ("DIAGNOSTICO: {0} request(s) con 'conflicto' y <=1 id_reserva -> probable carrera PG-0/PG-1 (NO duplicacion). Falta rama de recheck en router1_crear ante no_disponible." -f $nConfl) -ForegroundColor Yellow
}
Write-Host "VERIFICACION DURA: corre C_SLICE2_A07_verif_writes.sql -> CONCUR debe dar 1 / 1 / 1.`n"
