# ============================================================================
# C_SLICE3A_A24_GW_smoke.ps1 -- smoke GATEWAY de A24 (historico.reservas) via JWT.
# Carril C / Portal Operativo Interno - Slice 3a, cableado de A24 en portal-api.
#
# A DIFERENCIA del smoke directo (HMAC al webhook de n8n), este se autentica con JWT de
# Supabase y POSTea { action, payload } a la Edge Function portal-api. El gateway valida
# (payloadHistoricoReservas), inyecta nada (lectura), firma HMAC server-side hacia n8n y
# el wrapper revalida (2da defensa). Este harness NUNCA ve el secreto HMAC.
#
# Reutiliza el helper comun C_SLICE2_A10_GW_common.ps1 (Get-PortalJwt / Invoke-Gateway /
# Assert-*). ASCII puro (PS 5.1 / CP1252). Sin -Parallel. Sin if inline en -ForegroundColor.
#
# Variables de entorno requeridas (las mismas del molde de A08/A10):
#   VITA_SUPABASE_URL_TEST    base del proyecto Supabase TEST (https://<ref>.supabase.co)
#   VITA_SUPABASE_ANON_TEST   anon key de TEST (header apikey)
#   VITA_PW_VICKY / VITA_PW_FRANCO / VITA_PW_JENNY   passwords de los 3 usuarios portal
#
# TEST exclusivamente. No toca OPS. El gateway es read-only para esta accion.
# ============================================================================

# Ruta al helper comun. EDITAR si esta en otra carpeta (p.ej. ..\C_SLICE_2\).
$CommonPath = Join-Path $PSScriptRoot 'C_SLICE2_A10_GW_common.ps1'
if (-not (Test-Path $CommonPath)) {
  throw "No encuentro C_SLICE2_A10_GW_common.ps1 en '$CommonPath'. Edita la variable `$CommonPath con la ruta correcta."
}
. $CommonPath

$ACT   = 'historico.reservas'
$FLOOR = '2026-07-01'

# Helper local: filas como array seguro.
function Filas { param($d); if ($d -and $d.filas) { return @($d.filas) } ; return @() }

# ---- JWTs ----
$jwtVicky  = Get-PortalJwt -Identity 'vicky@vitadelta.test'  -Password $env:VITA_PW_VICKY
$jwtFranco = Get-PortalJwt -Identity 'franco@vitadelta.test' -Password $env:VITA_PW_FRANCO
$jwtJenny  = Get-PortalJwt -Identity 'jenny@vitadelta.test'  -Password $env:VITA_PW_JENNY

if (-not $jwtVicky) {
  Write-Host "No se pudo obtener JWT de vicky. Revisa VITA_SUPABASE_URL_TEST / VITA_SUPABASE_ANON_TEST / VITA_PW_VICKY." -ForegroundColor Red
  return
}

$cfg = Get-GwEnv
Write-Host "Gateway: $($cfg.url)/functions/v1/portal-api" -ForegroundColor Magenta
Write-Host "Action: $ACT | Floor: $FLOOR" -ForegroundColor DarkGray

# ============================ SEGURIDAD ============================
Write-Host "`n----- SEGURIDAD (gateway) -----" -ForegroundColor Magenta

# 1. vicky OK (sin filtros) -> ok:true, filas + total
$r = Invoke-Gateway -Action $ACT -Jwt $jwtVicky
Assert-OkData $r "1. vicky OK (sin filtros)" { param($d) ($null -ne $d.filas) -and ($null -ne $d.total) -and ($d.limit -eq 50) -and ($d.offset -eq 0) }
if ($r.ok) { Write-Host ("    total=" + $r.data.total + " filas=" + @(Filas $r.data).Count) -ForegroundColor DarkGray }

# 2. socio (franco) OK
if ($jwtFranco) {
  $r = Invoke-Gateway -Action $ACT -Jwt $jwtFranco
  Assert-OkData $r "2. socio (franco) OK" { param($d) $null -ne $d.filas }
} else {
  Record "2. socio (franco) OK" $false "no se obtuvo JWT de franco (revisa VITA_PW_FRANCO)"
}

# 3. jenny -> rol_no_permitido (rebota en el gateway por allowlist, antes de firmar)
if ($jwtJenny) {
  $r = Invoke-Gateway -Action $ACT -Jwt $jwtJenny
  Assert-Code $r "3. jenny -> rol_no_permitido" "rol_no_permitido"
} else {
  Record "3. jenny -> rol_no_permitido" $false "no se obtuvo JWT de jenny (revisa VITA_PW_JENNY)"
}

# 4. sin JWT -> no_autorizado
$r = Invoke-Gateway -Action $ACT -Jwt $null
Assert-Code $r "4. sin JWT -> no_autorizado" "no_autorizado"

# 5. action desconocida -> accion_desconocida
$r = Invoke-Gateway -Action 'historico.inexistente' -Jwt $jwtVicky
Assert-Code $r "5. action desconocida -> accion_desconocida" "accion_desconocida"

# ============================ FUNCIONALES (vicky) ============================
Write-Host "`n----- FUNCIONALES (gateway) -----" -ForegroundColor Magenta

# F1. sin filtros -> filas + total, limit 50, offset 0
$r = Invoke-Gateway -Action $ACT -Payload @{} -Jwt $jwtVicky
Assert-OkData $r "F1. sin filtros (filas + total)" { param($d) ($null -ne $d.filas) -and ($null -ne $d.total) }

# F2. fecha_desde dentro de rango -> todas >= desde
$desde = "2026-07-10"
$r = Invoke-Gateway -Action $ACT -Payload @{ fecha_desde = $desde } -Jwt $jwtVicky
Assert-OkData $r "F2. fecha_desde=$desde (todas >= desde)" { param($d) @(Filas $d | Where-Object { $_.fecha_checkin -lt $desde }).Count -eq 0 }

# F3. fecha_desde < floor -> recorte; ninguna fila < floor
$r = Invoke-Gateway -Action $ACT -Payload @{ fecha_desde = "2026-06-01" } -Jwt $jwtVicky
Assert-OkData $r "F3. fecha_desde<floor recortado (0 filas < $FLOOR)" { param($d) @(Filas $d | Where-Object { $_.fecha_checkin -lt $FLOOR }).Count -eq 0 }

# F4. id_cabana=5 -> todas cabana 5
$r = Invoke-Gateway -Action $ACT -Payload @{ id_cabana = [int]5 } -Jwt $jwtVicky
Assert-OkData $r "F4. id_cabana=5 (todas cabana 5)" { param($d) @(Filas $d | Where-Object { $_.id_cabana -ne 5 }).Count -eq 0 }

# F5. id_cabana=3 (Arrebol, sin reservas) -> filas vacia
$r = Invoke-Gateway -Action $ACT -Payload @{ id_cabana = [int]3 } -Jwt $jwtVicky
Assert-OkData $r "F5. id_cabana=3 sin reservas -> filas:[]" { param($d) @(Filas $d).Count -eq 0 }

# F6. estado=confirmada -> todas confirmada
$r = Invoke-Gateway -Action $ACT -Payload @{ estado = "confirmada" } -Jwt $jwtVicky
Assert-OkData $r "F6. estado=confirmada (todas confirmada)" { param($d) @(Filas $d | Where-Object { $_.estado -ne 'confirmada' }).Count -eq 0 }

# F7. estado=completada -> filas vacia
$r = Invoke-Gateway -Action $ACT -Payload @{ estado = "completada" } -Jwt $jwtVicky
Assert-OkData $r "F7. estado=completada -> filas:[]" { param($d) @(Filas $d).Count -eq 0 }

# F8. texto sin match -> filas vacia
$r = Invoke-Gateway -Action $ACT -Payload @{ texto = "zzz_no_existe_qwerty" } -Jwt $jwtVicky
Assert-OkData $r "F8. texto sin match -> filas:[]" { param($d) @(Filas $d).Count -eq 0 }

# F9. limit=2 offset=0 -> <=2 filas; total presente
$rF9 = Invoke-Gateway -Action $ACT -Payload @{ limit = [int]2; offset = [int]0 } -Jwt $jwtVicky
Assert-OkData $rF9 "F9. limit=2 offset=0 (<=2 filas, total presente)" { param($d) (@(Filas $d).Count -le 2) -and ($d.limit -eq 2) -and ($d.offset -eq 0) -and ($null -ne $d.total) }

# F10. limit=2 offset=2 -> pagina distinta de F9
$rF10 = Invoke-Gateway -Action $ACT -Payload @{ limit = [int]2; offset = [int]2 } -Jwt $jwtVicky
Assert-OkData $rF10 "F10. limit=2 offset=2 (pagina distinta de F9)" {
  param($d)
  $idsF9  = @(Filas $rF9.data  | ForEach-Object { $_.id_reserva })
  $idsF10 = @(Filas $d | ForEach-Object { $_.id_reserva })
  $solapan = @($idsF10 | Where-Object { $idsF9 -contains $_ }).Count
  ($d.offset -eq 2) -and ($solapan -eq 0 -or @($idsF10).Count -eq 0)
}

# ============================ PAYLOAD INVALIDO (vicky) ============================
Write-Host "`n----- PAYLOAD INVALIDO (gateway) -----" -ForegroundColor Magenta

# P1. clave no permitida
$r = Invoke-Gateway -Action $ACT -Payload @{ foo = 1 } -Jwt $jwtVicky
Assert-Code $r "P1. clave no permitida -> payload_invalido" "payload_invalido"

# P2. fecha mal formada
$r = Invoke-Gateway -Action $ACT -Payload @{ fecha_desde = "2026-13-01" } -Jwt $jwtVicky
Assert-Code $r "P2. fecha mal formada -> payload_invalido" "payload_invalido"

# P3. estado fuera del enum
$r = Invoke-Gateway -Action $ACT -Payload @{ estado = "xxx" } -Jwt $jwtVicky
Assert-Code $r "P3. estado fuera de enum -> payload_invalido" "payload_invalido"

# P4. id_cabana decimal
$r = Invoke-Gateway -Action $ACT -Payload @{ id_cabana = 1.5 } -Jwt $jwtVicky
Assert-Code $r "P4. id_cabana decimal -> payload_invalido" "payload_invalido"

# P5. fecha_hasta < fecha_desde
$r = Invoke-Gateway -Action $ACT -Payload @{ fecha_desde = "2026-08-01"; fecha_hasta = "2026-07-15" } -Jwt $jwtVicky
Assert-Code $r "P5. fecha_hasta < fecha_desde -> payload_invalido" "payload_invalido"

# P6a. payload string (no objeto) -> payload_invalido (no se coerciona a {})
$r = Invoke-Gateway -Action $ACT -Payload "soy_un_string" -Jwt $jwtVicky
Assert-Code $r "P6a. payload string -> payload_invalido" "payload_invalido"

# P6b. payload array (no objeto) -> payload_invalido
$r = Invoke-Gateway -Action $ACT -Payload @(1, 2, 3) -Jwt $jwtVicky
Assert-Code $r "P6b. payload array -> payload_invalido" "payload_invalido"

# ============================ META ============================
Write-Host "`n----- META -----" -ForegroundColor Magenta
Assert-AllowlistMeta

Summary
Write-Host ""
Write-Host "Nota: filas=0 puede ser PASS (lista vacia valida, D-C-47)." -ForegroundColor DarkGray
Write-Host "Para un caso POSITIVO de texto, edita F8 con un substring real de un huesped en TEST." -ForegroundColor DarkGray
