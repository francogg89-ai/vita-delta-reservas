# ============================================================================
# A10_smoke_concurrencia.ps1 -- Bloque 5 (concurrencia, RunspacePool; NO -Parallel).
# C1 retry-race  : 9900006 saldo 70000; N pedidos concurrentes con la MISMA key/monto
#                  -> exactamente 1 escritura (idempotent_match:false), el resto idempotente.
# C2 sobrepago-race: 9900007 saldo 90000; 4 pedidos de 30000 con keys DISTINTAS
#                  -> el advisory lock serializa: 3 ok (suma 90000) + 1 conflicto; saldo final 0.
# Prueba que el lock por id_reserva + snapshot fresco por sentencia impiden doble cobro.
# Requiere: VITA_A10_WEBHOOK_URL, VITA_HMAC_SECRET_TEST. W09 INACTIVO. Correr tras setup.
# ============================================================================

$secret = $env:VITA_HMAC_SECRET_TEST
$url = $env:VITA_A10_WEBHOOK_URL
if ([string]::IsNullOrEmpty($secret)) { throw 'Falta VITA_HMAC_SECRET_TEST' }
if ([string]::IsNullOrEmpty($url)) { throw 'Falta VITA_A10_WEBHOOK_URL' }

# Worker autonomo por runspace: firma HMAC-SHA256 hex sobre bytes UTF-8 + POST + parse.
$worker = {
  param($url, $secret, $idReserva, $monto, $key, $rol, $actor)
  try { [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 } catch {}
  $ts = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $payload = [ordered]@{ id_reserva = $idReserva; monto = $monto; medio_pago = 'transferencia_mp'; idempotency_key = $key; notas = 'smoke conc' }
  $env_ht = [ordered]@{
    action = 'cobranza.registrar_saldo'; payload = $payload; rol = $rol;
    ambiente_esperado = 'test'; ts = $ts; nonce = [guid]::NewGuid().ToString(); actor = $actor
  }
  $bodyString = $env_ht | ConvertTo-Json -Compress -Depth 12
  $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($bodyString)
  $hmac = New-Object System.Security.Cryptography.HMACSHA256
  $hmac.Key = [System.Text.Encoding]::UTF8.GetBytes($secret)
  $hash = $hmac.ComputeHash($bodyBytes)
  $hex = -join ($hash | ForEach-Object { $_.ToString('x2') })
  $sig = "sha256=$hex"
  try {
    $req = [System.Net.HttpWebRequest]::Create($url)
    $req.Method = 'POST'
    $req.ContentType = 'application/json'
    $req.Accept = 'application/json'
    [void]$req.Headers.Add('X-Vita-Signature', $sig)
    $req.ContentLength = $bodyBytes.Length
    $rs = $req.GetRequestStream()
    $rs.Write($bodyBytes, 0, $bodyBytes.Length)
    $rs.Close()
    $resp = $req.GetResponse()
    $sr = New-Object System.IO.StreamReader($resp.GetResponseStream())
    $body = $sr.ReadToEnd(); $sr.Close(); $resp.Close()
    $j = $body | ConvertFrom-Json
  } catch [System.Net.WebException] {
    $r = $_.Exception.Response
    if ($r) { $sr = New-Object System.IO.StreamReader($r.GetResponseStream()); $body = $sr.ReadToEnd(); $sr.Close(); try { $j = $body | ConvertFrom-Json } catch { $j = $null } }
    else { $j = $null }
  } catch { $j = $null }
  $ok = $false; $idem = $null; $code = $null; $idpago = $null; $saldo = $null
  if ($j) {
    $ok = ($j.ok -eq $true)
    if ($ok) { $idem = $j.data.idempotent_match; $idpago = $j.data.id_pago; $saldo = $j.data.saldo_real_actual }
    elseif ($j.error) { $code = $j.error.code }
  }
  return [pscustomobject]@{ ok = $ok; idempotent_match = $idem; code = $code; id_pago = $idpago; saldo = $saldo; monto = $monto; key = $key }
}

function Invoke-Concurrent {
  param([array]$Calls, [int]$MaxThreads = 8)
  $pool = [runspacefactory]::CreateRunspacePool(1, $MaxThreads)
  $pool.Open()
  $jobs = @()
  foreach ($c in $Calls) {
    $ps = [powershell]::Create()
    $ps.RunspacePool = $pool
    [void]$ps.AddScript($worker).AddArgument($url).AddArgument($secret).AddArgument($c.res).AddArgument($c.monto).AddArgument($c.key).AddArgument($c.rol).AddArgument($c.actor)
    $jobs += [pscustomobject]@{ PS = $ps; Handle = $ps.BeginInvoke() }
  }
  $results = @()
  foreach ($j in $jobs) { $results += $j.PS.EndInvoke($j.Handle); $j.PS.Dispose() }
  $pool.Close(); $pool.Dispose()
  return $results
}

$script:pass = 0; $script:fail = 0
function Chk { param($name, $cond, $detail)
  if ($cond) { $script:pass++; Write-Host "PASS  $name" -ForegroundColor Green }
  else { $script:fail++; Write-Host "FAIL  $name  ($detail)" -ForegroundColor Red }
}

# ---- C1 retry-race ----
Write-Host "=== C1 retry-race (9900006, misma key x8) ==="
$N1 = 8
$calls1 = 1..$N1 | ForEach-Object { @{ res = 9900006; monto = 50000; key = 'a10c1retryracekey'; rol = 'vicky'; actor = 'vicky' } }
$res1 = Invoke-Concurrent -Calls $calls1
$okCount1 = @($res1 | Where-Object { $_.ok }).Count
$nuevos1 = @($res1 | Where-Object { $_.ok -and (-not $_.idempotent_match) }).Count
$idemp1 = @($res1 | Where-Object { $_.ok -and ($_.idempotent_match -eq $true) }).Count
$idsUnique1 = @($res1 | Where-Object { $_.ok } | Select-Object -ExpandProperty id_pago | Sort-Object -Unique)
Chk "C1 todas ok" ($okCount1 -eq $N1) "ok=$okCount1 de $N1"
Chk "C1 exactamente 1 escritura nueva" ($nuevos1 -eq 1) "nuevos=$nuevos1 (esperado 1)"
Chk "C1 resto idempotente" ($idemp1 -eq ($N1 - 1)) "idempotentes=$idemp1 (esperado $($N1-1))"
Chk "C1 un unico id_pago" (@($idsUnique1).Count -eq 1) "id_pago distintos=$(@($idsUnique1).Count)"

# ---- C2 sobrepago-race ----
Write-Host ""
Write-Host "=== C2 sobrepago-race (9900007 saldo 90000, 30000 x4 keys distintas) ==="
$calls2 = @(
  @{ res = 9900007; monto = 30000; key = 'a10c2over_k1'; rol = 'vicky'; actor = 'vicky' },
  @{ res = 9900007; monto = 30000; key = 'a10c2over_k2'; rol = 'vicky'; actor = 'vicky' },
  @{ res = 9900007; monto = 30000; key = 'a10c2over_k3'; rol = 'vicky'; actor = 'vicky' },
  @{ res = 9900007; monto = 30000; key = 'a10c2over_k4'; rol = 'vicky'; actor = 'vicky' }
)
$res2 = Invoke-Concurrent -Calls $calls2
$okCount2 = @($res2 | Where-Object { $_.ok }).Count
$confCount2 = @($res2 | Where-Object { (-not $_.ok) -and ($_.code -eq 'conflicto') }).Count
$sumOk2 = (@($res2 | Where-Object { $_.ok }) | Measure-Object -Property monto -Sum).Sum
if ($null -eq $sumOk2) { $sumOk2 = 0 }
Chk "C2 exactamente 3 ok" ($okCount2 -eq 3) "ok=$okCount2 (esperado 3)"
Chk "C2 al menos 1 conflicto" ($confCount2 -ge 1) "conflictos=$confCount2 (esperado >=1)"
Chk "C2 suma de montos ok <= saldo (90000)" ($sumOk2 -le 90000) "suma=$sumOk2"

Write-Host ""
Write-Host "==================================================="
Write-Host ("RESULTADO CONCURRENCIA: {0} PASS / {1} FAIL" -f $script:pass, $script:fail)
Write-Host "Verificacion final por SQL: saldo de 9900006 = 70000-50000 = 20000 (1 pago); saldo de 9900007 = 0 (3 pagos de 30000)."
Write-Host "Usar A10_verif_writes.sql: 9900006 -> 1 pago; 9900007 -> 3 pagos."
