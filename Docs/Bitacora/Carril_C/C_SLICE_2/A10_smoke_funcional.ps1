# ============================================================================
# A10_smoke_funcional.ps1 -- Bloque 3 (funcional A-I) + meta allowlist.
# Fixtures (de A10_setup.sql): saldo_real inicial ->
#   9900001:70000(confirmada)  9900002:70000(confirmada)  9900003:100000(activa)
#   9900004:cancelada          9900005:0(saldada)
# Orden: A,B,C,D,F sobre 9900001 (saldo decreciente + idempotencia); E,G,H,I aparte.
# Requiere: VITA_A10_WEBHOOK_URL, VITA_HMAC_SECRET_TEST. Correr DESPUES de setup, con W09 inactivo.
# ============================================================================
. "$PSScriptRoot\A10_smoke_common.ps1"

function P { param($res, $monto, $key, $medio = 'transferencia_mp')
  return [ordered]@{ id_reserva = $res; monto = $monto; medio_pago = $medio; idempotency_key = $key; notas = 'smoke funcional' }
}
function Near { param($a, $b) return ([math]::Abs([double]$a - [double]$b) -lt 0.01) }

$KEY_A = 'a10funcAfeliz01'

Write-Host "=== A10 Bloque 3: Funcional ==="

# A FELIZ: 9900001 saldo 70000, paga 50000 -> ok, nuevo, saldo 20000.
$rA = Invoke-A10 -Payload (P 9900001 50000 $KEY_A) -Rol 'vicky' -Actor 'vicky'
Assert-OkData $rA 'A FELIZ (9900001, 50000)' { param($d) (-not $d.idempotent_match) -and (Near $d.saldo_real_actual 20000) }
$idA = $null
if ($rA.ok -eq $true) { $idA = $rA.data.id_pago }

# B RETRY: misma key, mismo monto -> idempotent_match:true, mismo id_pago, saldo sigue 20000.
$rB = Invoke-A10 -Payload (P 9900001 50000 $KEY_A) -Rol 'vicky' -Actor 'vicky'
Assert-OkData $rB 'B RETRY (misma key -> idempotente)' { param($d) ($d.idempotent_match -eq $true) -and ($d.id_pago -eq $idA) -and (Near $d.saldo_real_actual 20000) }

# C MISMATCH-MONTO: misma key, monto distinto -> conflicto, sin escritura.
$rC = Invoke-A10 -Payload (P 9900001 60000 $KEY_A) -Rol 'vicky' -Actor 'vicky'
Assert-Code $rC 'C MISMATCH-MONTO (misma key, monto distinto)' 'conflicto'

# D MISMATCH-MEDIO: misma key, medio distinto -> conflicto, sin escritura.
$rD = Invoke-A10 -Payload (P 9900001 50000 $KEY_A 'efectivo') -Rol 'vicky' -Actor 'vicky'
Assert-Code $rD 'D MISMATCH-MEDIO (misma key, medio distinto)' 'conflicto'

# Da MISMATCH-ACTOR: misma key/monto/medio que A pero actor distinto (socio/franco) ->
# idempotency_mismatch -> conflicto. Evita idempotent_match silencioso sobre un pago de otra persona.
$rDa = Invoke-A10 -Payload (P 9900001 50000 $KEY_A) -Rol 'socio' -Actor 'franco'
Assert-Code $rDa 'Da MISMATCH-ACTOR (misma key, actor distinto)' 'conflicto'

# F SOBREPAGO: saldo de 9900001 ahora 20000; paga 30000 (>saldo) con key nueva -> conflicto.
$rF = Invoke-A10 -Payload (P 9900001 30000 'a10funcFsobre01') -Rol 'vicky' -Actor 'vicky'
Assert-Code $rF 'F SOBREPAGO (30000 > saldo 20000)' 'conflicto'

# E COMPLETA: 9900002 saldo 70000, paga 70000 -> ok, saldo 0.
$rE = Invoke-A10 -Payload (P 9900002 70000 'a10funcEcompleta1') -Rol 'socio' -Actor 'franco'
Assert-OkData $rE 'E COMPLETA (9900002, 70000 -> 0)' { param($d) (Near $d.saldo_real_actual 0) }

# G SALDADA: 9900005 saldo 0, paga 10000 -> conflicto (saldo_ya_cancelado).
$rG = Invoke-A10 -Payload (P 9900005 10000 'a10funcGsaldada1') -Rol 'vicky' -Actor 'vicky'
Assert-Code $rG 'G SALDADA (saldo 0)' 'conflicto'

# H CANCELADA: 9900004 cancelada -> conflicto (estado_no_cobrable).
$rH = Invoke-A10 -Payload (P 9900004 10000 'a10funcHcancel01') -Rol 'vicky' -Actor 'vicky'
Assert-Code $rH 'H CANCELADA (estado no cobrable)' 'conflicto'

# I ACTIVA: 9900003 activa saldo 100000, paga 40000 -> ok, saldo 60000.
$rI = Invoke-A10 -Payload (P 9900003 40000 'a10funcIactiva01') -Rol 'socio' -Actor 'remo'
Assert-OkData $rI 'I ACTIVA (9900003, 40000 -> 60000)' { param($d) (Near $d.saldo_real_actual 60000) }

Write-Host ""
Write-Host "=== meta-check allowlist ==="
Assert-AllowlistMeta

Summary
Write-Host ""
Write-Host "NOTA: verificar escrituras con A10_verif_writes.sql -> esperado: 9900001=1 (A), 9900002=1 (E), 9900003=1 (I); C/D/F/G/H sin pago."
