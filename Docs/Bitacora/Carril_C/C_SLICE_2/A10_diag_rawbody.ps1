# ============================================================================
# A10_diag_rawbody.ps1 -- diagnostico de UN disparo (NO escribe: usa firma invalida).
# Manda un request con FIRMA INVALIDA, asi rebota antes de cualquier escritura, y permite
# distinguir tres estados de la lectura del raw body:
#   - code = firma_invalida           -> el raw se leyo BIEN (paso de raw a la verif de firma).
#                                         EL FIX ESTA VIVO. Proceder con A10_smoke_seguridad.ps1.
#   - code = raw_body_ausente + 'v3'   -> nodo v3 desplegado pero el raw AUN no se lee; el diag
#                                         en el mensaje dice por que (helpers/binary/bodyType/via).
#   - code = raw_body_ausente sin 'v3' -> el webhook lo sirve un workflow con el nodo VIEJO:
#                                         actualizar el nodo del workflow ACTIVO.
# Requiere: VITA_A10_WEBHOOK_URL, VITA_HMAC_SECRET_TEST.
# ============================================================================
. "$PSScriptRoot\A10_smoke_common.ps1"

$p = [ordered]@{ id_reserva = 9900001; monto = 50000; medio_pago = 'transferencia_mp'; idempotency_key = 'diagrawbody01'; notas = 'diag raw body' }
$badSig = 'sha256=' + ('0' * 64)
$r = Invoke-A10 -Payload $p -Rol 'vicky' -Actor 'vicky' -SigOverride $badSig

$code = '(none)'
$msg = '(none)'
if ($r.error) { $code = $r.error.code; $msg = $r.error.message }

Write-Host "=== A10 diag raw body (firma invalida, NO escribe) ==="
Write-Host ("ok    : {0}" -f $r.ok)
Write-Host ("code  : {0}" -f $code)
Write-Host ("msg   : {0}" -f $msg)
Write-Host ""

if ($code -eq 'firma_invalida') {
  Write-Host "DIAGNOSTICO: el raw body se LEE bien (llego a la verificacion de firma)."
  Write-Host "  -> El fix esta vivo. Corre A10_smoke_seguridad.ps1; deberia dar verde."
} elseif ($code -eq 'raw_body_ausente') {
  $tieneV3 = ($msg -match 'rawread')
  if ($tieneV3) {
    Write-Host "DIAGNOSTICO: nodo v3 desplegado, pero el raw AUN no se lee."
    Write-Host "  -> Mira el diag de arriba (helpers/getBinFn/binary/binaryDataKeys/bodyType/via)."
    Write-Host "     Pegame esa linea 'diag {...}' y te doy la lectura definitiva."
  } else {
    Write-Host "DIAGNOSTICO: el mensaje NO trae el marcador v3 -> el webhook lo sirve un workflow"
    Write-Host "  con el nodo VIEJO. Actualiza el nodo del workflow ACTIVO (pegar validar_firma_ts_rol.js,"
    Write-Host "  y reemplazar el placeholder del secreto), o deja un solo workflow con ese path y reactivalo."
  }
} else {
  Write-Host "DIAGNOSTICO: respuesta inesperada. Revisa la respuesta cruda."
}
Write-Host ""
Write-Host "Respuesta cruda:"
$r | ConvertTo-Json -Depth 10
