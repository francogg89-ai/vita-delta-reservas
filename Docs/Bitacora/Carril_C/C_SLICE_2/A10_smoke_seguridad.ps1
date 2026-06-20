# ============================================================================
# A10_smoke_seguridad.ps1 -- Bloque 1 (seguridad, sin escritura) + Bloque 6 (meta allowlist).
# Todas las dimensiones de validar_firma_ts_rol. Ninguna debe escribir (rebotan antes del PG).
# Requiere: . .\A10_smoke_common.ps1 cargado; VITA_A10_WEBHOOK_URL y VITA_HMAC_SECRET_TEST.
# ============================================================================
. "$PSScriptRoot\A10_smoke_common.ps1"

$RES = 9900001  # fixture confirmada con saldo (no se escribe en estos casos)
function New-BasePayload {
  return [ordered]@{ id_reserva = $RES; monto = 50000; medio_pago = 'transferencia_mp'; idempotency_key = 'segkeybase01'; notas = 'smoke seguridad' }
}
$ZEROS = 'sha256=' + ('0' * 64)

Write-Host "=== A10 Bloque 1: Seguridad (sin escritura) ==="

# ---- Firma ----
Assert-Code (Invoke-A10 -Payload (New-BasePayload) -SigOverride $ZEROS) 'S01 firma invalida (no coincide)' 'firma_invalida'
Assert-Code (Invoke-A10 -Payload (New-BasePayload) -SigOverride '') 'S02 firma ausente' 'firma_invalida'
Assert-Code (Invoke-A10 -Payload (New-BasePayload) -SigOverride 'md5=zzz') 'S03 firma formato invalido' 'firma_invalida'

# ---- ts ----
# Usamos margen amplio para no depender de latencia/clock skew.
# Ademas id_reserva=0 garantiza que, si el test no rebotara por ts,
# tampoco podria escribir: caeria en payload_invalido antes de PG.
$pTs = New-BasePayload
$pTs['id_reserva'] = 0

$tsOld = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() - 900000
$tsFut = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() + 900000

Assert-Code (Invoke-A10 -Payload $pTs -TsOverride $tsOld) 'S04 ts viejo (>300s)' 'ts_fuera_de_ventana'
Assert-Code (Invoke-A10 -Payload $pTs -TsOverride $tsFut) 'S05 ts futuro (>300s)' 'ts_fuera_de_ventana'

# ---- action binding ----
Assert-Code (Invoke-A10 -Payload (New-BasePayload) -ExtraEnvelope @{ action = 'reserva.crear_manual' }) 'S06 action distinta' 'payload_invalido'

# ---- rol / actor ----
Assert-Code (Invoke-A10 -Payload (New-BasePayload) -Rol 'jenny') 'S07 rol jenny' 'rol_no_permitido'
Assert-Code (Invoke-A10 -Payload (New-BasePayload) -Rol 'basura') 'S08 rol basura' 'rol_no_permitido'
Assert-Code (Invoke-A10 -Payload (New-BasePayload) -Actor 'pepe') 'S09 actor fuera de enum' 'payload_invalido'
Assert-Code (Invoke-A10 -Payload (New-BasePayload) -Rol 'vicky' -Actor 'franco') 'S10 actor incoherente vicky->franco' 'rol_no_permitido'

# ---- envelope reject-unknown / faltantes ----
Assert-Code (Invoke-A10 -Payload (New-BasePayload) -ExtraEnvelope @{ extra = 1 }) 'S11 sobre clave extra' 'payload_invalido'
Assert-Code (Invoke-A10 -Payload (New-BasePayload) -DropEnvelopeKeys @('nonce')) 'S12 nonce ausente' 'payload_invalido'

# ---- ambiente ----
Assert-Code (Invoke-A10 -Payload (New-BasePayload) -AmbienteEsperado 'ops') 'S13 ambiente_esperado=ops' 'ambiente_incorrecto'

# ---- payload reject-unknown (spoof de campos server-side) ----
$spoofs = @('actor','tipo','source_event','estado_inicial','validado_por','monto_esperado','id_pre_reserva')
$i = 14
foreach ($f in $spoofs) {
  $p = New-BasePayload; $p[$f] = 'x'
  Assert-Code (Invoke-A10 -Payload $p) ("S{0} spoof '{1}' en payload" -f $i, $f) 'payload_invalido'
  $i++
}

# ---- id_reserva ----
$p = New-BasePayload; $p['id_reserva'] = 0
Assert-Code (Invoke-A10 -Payload $p) 'S21 id_reserva cero' 'payload_invalido'
$p = New-BasePayload; $p['id_reserva'] = '101'
Assert-Code (Invoke-A10 -Payload $p) 'S22 id_reserva string' 'payload_invalido'

# ---- monto ----
$p = New-BasePayload; $p['monto'] = 0
Assert-Code (Invoke-A10 -Payload $p) 'S23 monto cero' 'payload_invalido'
$p = New-BasePayload; $p['monto'] = '50000'
Assert-Code (Invoke-A10 -Payload $p) 'S24 monto string' 'payload_invalido'
$p = New-BasePayload; $p['monto'] = 100.123
Assert-Code (Invoke-A10 -Payload $p) 'S25 monto 3 decimales' 'payload_invalido'
$p = New-BasePayload; $p['monto'] = 10000000000
Assert-Code (Invoke-A10 -Payload $p) 'S26 monto fuera de rango (>NUMERIC 12,2)' 'payload_invalido'

# monto Infinity: construir raw con 1e400 (JSON.parse -> Infinity), firmado correctamente.
$tsNow = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
$envInf = [ordered]@{ action='cobranza.registrar_saldo'; payload=(New-BasePayload); rol='vicky'; ambiente_esperado='test'; ts=$tsNow; nonce=[guid]::NewGuid().ToString(); actor='vicky' }
$rawInf = ($envInf | ConvertTo-Json -Compress -Depth 12) -replace '"monto":50000', '"monto":1e400'
Assert-Code (Invoke-A10 -Payload (New-BasePayload) -RawOverride $rawInf) 'S27 monto Infinity (1e400)' 'payload_invalido'

# ---- medio_pago ----
$p = New-BasePayload; $p['medio_pago'] = 'mp_link'
Assert-Code (Invoke-A10 -Payload $p) 'S28 medio mp_link (no expuesto en A10)' 'payload_invalido'
$p = New-BasePayload; $p['medio_pago'] = 'bitcoin'
Assert-Code (Invoke-A10 -Payload $p) 'S29 medio invalido' 'payload_invalido'

# ---- idempotency_key ----
$p = New-BasePayload; $p['idempotency_key'] = 'abc'
Assert-Code (Invoke-A10 -Payload $p) 'S30 idempotency_key corta (<8)' 'payload_invalido'
$p = New-BasePayload; $p['idempotency_key'] = ('a' * 65)
Assert-Code (Invoke-A10 -Payload $p) 'S31 idempotency_key larga (>64)' 'payload_invalido'
$p = New-BasePayload; $p['idempotency_key'] = 'abc def!'
Assert-Code (Invoke-A10 -Payload $p) 'S32 idempotency_key charset invalido' 'payload_invalido'

# ---- Bloque 6: meta allowlist ----
Write-Host ""
Write-Host "=== Bloque 6: meta-check allowlist ==="
Assert-AllowlistMeta

Summary
