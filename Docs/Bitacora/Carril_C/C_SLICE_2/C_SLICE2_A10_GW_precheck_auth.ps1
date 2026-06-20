# ============================================================================
# C_SLICE2_A10_GW_precheck_auth.ps1 -- precheck de auth + visibilidad de la accion A10.
# Verifica: (1) los 3 usuarios obtienen JWT; (2) sesion.contexto lista
# cobranza.registrar_saldo para vicky y socio(franco), y NO para jenny.
# No escribe. Correr ANTES del smoke gateway.
#
# Requiere: VITA_SUPABASE_URL_TEST, VITA_SUPABASE_ANON_TEST,
#           VITA_PW_VICKY, VITA_PW_FRANCO, VITA_PW_JENNY.
# Identidades hardcodeadas (reconciliadas con C_SLICE2_A08_GW_smoke.ps1).
# ============================================================================
. "$PSScriptRoot\C_SLICE2_A10_GW_common.ps1"

$EMAIL_VICKY  = 'vicky@vitadelta.test'
$EMAIL_FRANCO = 'franco@vitadelta.test'
$EMAIL_JENNY  = 'jenny@vitadelta.test'
foreach ($pair in @(
    @('VITA_PW_VICKY',$env:VITA_PW_VICKY), @('VITA_PW_FRANCO',$env:VITA_PW_FRANCO), @('VITA_PW_JENNY',$env:VITA_PW_JENNY))) {
  if ([string]::IsNullOrEmpty($pair[1])) { throw ('Falta ' + $pair[0]) }
}

$ACTION = 'cobranza.registrar_saldo'

Write-Host "=== A10 GW precheck auth ==="

function Check-Contexto {
  param($label, $identity, $password, $debePoder)
  $jwt = Get-PortalJwt -Identity $identity -Password $password
  Record "$label JWT obtenido" ([bool]$jwt) "no se obtuvo token (revisar credenciales / Supabase Auth)"
  if (-not $jwt) { return }
  $r = Invoke-Gateway -Action 'sesion.contexto' -Payload @{} -Jwt $jwt
  $okCtx = ($r.ok -eq $true) -and ($null -ne $r.data) -and ($null -ne $r.data.acciones)
  Record "$label sesion.contexto ok" $okCtx "no devolvio acciones (ok=$($r.ok) code=$(Get-Code $r))"
  if ($okCtx) {
    $tiene = (@($r.data.acciones) -contains $ACTION)
    if ($debePoder) {
      Record "$label ve $ACTION" $tiene "no aparece en acciones"
    } else {
      Record "$label NO ve $ACTION" (-not $tiene) "aparece en acciones (no deberia)"
    }
  }
}

Check-Contexto 'vicky'  $EMAIL_VICKY  $env:VITA_PW_VICKY  $true
Check-Contexto 'franco' $EMAIL_FRANCO $env:VITA_PW_FRANCO $true
Check-Contexto 'jenny'  $EMAIL_JENNY  $env:VITA_PW_JENNY  $false

Summary
