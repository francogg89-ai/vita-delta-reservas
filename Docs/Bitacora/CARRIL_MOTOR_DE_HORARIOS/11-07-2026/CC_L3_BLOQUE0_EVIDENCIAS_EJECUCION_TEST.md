# Evidencias de ejecución TEST — Portal Operativo · Exposición L3 Cuenta Corriente · Bloque 0

Fecha de ejecución: **2026-07-11**  
Entorno: **TEST**  
Ejecutor: **Franco**  
Estado final: **VERDE — 0 fallos y 0 mutación**

Este archivo conserva las evidencias crudas de ejecución que respaldan el acta
`CC_L3_BLOQUE0_CIERRE.md`.

La separación entre **acta** y **evidencias** es deliberada:

- el acta resume, interpreta y acuña decisiones;
- este archivo conserva las salidas reales necesarias para reproducibilidad, auditoría y futura promoción a OPS;
- evita que el cierre dependa solamente de una narración resumida;
- permite comparar más adelante TEST contra OPS sin reconstruir lo ocurrido desde mensajes de chat.

---

## 1. Resumen ejecutivo

| Evidencia | Resultado |
|---|---|
| Rama natural pre-wrappers | `error_entorno`, nunca `estado_incierto` |
| Smoke directo A31 | `PASSED: 24`, `FAILED: 0`, `LASTEXITCODE: 0` |
| Smoke directo A30 | `PASSED: 34`, `FAILED: 0`, `LASTEXITCODE: 0` |
| Smoke gateway end-to-end | `PASSED: 50`, `FAILED: 0`, `LASTEXITCODE: 0` |
| Oracle read-only | `OK: 0 mutacion` |
| Forma del oracle | BEFORE y AFTER `7/7/2/2` |
| Comparaciones | counts, max_ids, table_hashes y sequences idénticos |

---

## 2. Fingerprint BEFORE — Oracle PARTE A

```json
[
  {
    "fingerprint": {
      "counts": {
        "liquidacion_gasto": 0,
        "liquidacion_socio": 12,
        "movimientos_socio": 4,
        "liquidacion_cascada": 32,
        "liquidaciones_periodo": 4,
        "liquidacion_incidencia": 0,
        "liquidacion_participacion": 0
      },
      "max_ids": {
        "movimientos_socio.id_movimiento": "14",
        "liquidaciones_periodo.id_liquidacion": "11"
      },
      "sequences": {
        "movimientos_socio_id_movimiento_seq": {
          "last_value": 14
        },
        "liquidaciones_periodo_id_liquidacion_seq": {
          "last_value": 14
        }
      },
      "captured_at": "2026-07-11T13:55:59.270164+00:00",
      "table_hashes": {
        "liquidacion_gasto": "d751713988987e9331980363e24189ce",
        "liquidacion_socio": "b3c89e14ba7675aa71d17a478ff3e317",
        "movimientos_socio": "c8336a52f9f78275123264278c09dff1",
        "liquidacion_cascada": "26f9878d2e7785adaa5be0563a4bfd95",
        "liquidaciones_periodo": "26e0f933c2e2e40a39303e1c6b912e74",
        "liquidacion_incidencia": "d751713988987e9331980363e24189ce",
        "liquidacion_participacion": "d751713988987e9331980363e24189ce"
      }
    }
  }
]
```

---

## 3. Evidencia de rama natural `error_entorno`

Momento de la prueba: gateway A31 desplegado y wrappers A30/A31 todavía inactivos.

```json
{
  "ok": false,
  "error": {
    "code": "error_entorno",
    "message": "respuesta inesperada del backend",
    "detail": null
  }
}
```

Conclusión respaldada: estas acciones son lecturas. Un dispatch no confiable devuelve
`error_entorno`; no devuelve `estado_incierto`.

---

## 4. Smoke directo A31 — salida completa

Comando ejecutado:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CC_L3_A31_acumulados_smoke_directo.ps1
```

Salida:

```text
Wrapper: https://federicosecchi.app.n8n.cloud/webhook/portal-a31-cuenta-corriente-historico-acumulados__TEST

----- SEGURIDAD -----
PASS  1. socio OK (HTTP 200, ok:true, data presente)
PASS  2. vicky -> rol_no_permitido (socio-only)
PASS  3. jenny -> rol_no_permitido
PASS  4. intruso -> rol_no_permitido (rol fuera de allowlist)
PASS  5. firma equivocada -> firma_invalida
PASS  6. ts viejo -> ts_fuera_de_ventana
PASS  7. ambiente cruzado -> ambiente_incorrecto
PASS  8. accion equivocada -> accion_desconocida

----- PAYLOAD (vacio estricto) -----
PASS  9. payload {} -> ok:true
PASS  10. payload omitido -> ok:true (normaliza a vacio)
PASS  11. payload null -> ok:true (normaliza a vacio)
PASS  12. payload con clave {foo:1} -> payload_invalido
PASS  13. payload array -> payload_invalido
PASS  14. payload string -> payload_invalido
PASS  15. payload number -> payload_invalido
PASS  16. payload boolean -> payload_invalido

----- FUNCIONAL -----
    [obs] sin_datos=False piso=2026-07-01 fotos_vigentes=3
    [obs] evolucion periodos: 2026-07-01, 2026-08-01, 2026-11-01
    [obs] saldos_por_socio=3 socios
    [obs] totales: ingresos=929700 gastos=-335000 utilidad=644400 repartos=644400 retiros=-63452.38
PASS  F1. 6 claves top-level presentes
PASS  F2. evolucion y saldos_por_socio son arrays; totales y meta objetos
PASS  F3. piso == 2026-07-01 (D-NEG-02)
PASS  F4. sin_datos es booleano
PASS  F5. evolucion ordenada por periodo asc
PASS  F6. meta.fotos_vigentes == evolucion.length
PASS  F7. si sin_datos=false -> evolucion no vacia (coherencia)
PASS  META allowlist (todos los error.code en la allowlist)

===== RESUMEN =====
PASSED: 24
FAILED: 0
```

Exit code:

```text
0
```

---

## 5. Smoke directo A30 — salida completa

Comando ejecutado:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CC_L3_A30_historico_smoke_directo.ps1
```

Salida:

```text
Wrapper historico: https://federicosecchi.app.n8n.cloud/webhook/portal-a30-cuenta-corriente-historico__TEST

----- DERIVACION (desde acumulados A31) -----
    [obs] periodos vigentes (evolucion): 2026-07-01, 2026-08-01, 2026-11-01
    [obs] MesValido (negativos)=2026-07-01  MesPreExtension=2026-07-01  MesSinFoto=2026-09-01
PASS  DERIV-1 foto pre-extension vigente hallada (sin_foto=false + detalle_disponible=false + motivo=foto_pre_extension)
PASS  DERIV-2 mes sin foto hallado (gap >= piso)

----- SEGURIDAD -----
PASS  1. socio OK (HTTP 200, ok:true, data presente)
PASS  2. vicky -> rol_no_permitido (socio-only)
PASS  3. jenny -> rol_no_permitido
PASS  4. intruso -> rol_no_permitido (rol fuera de allowlist)
PASS  5. firma equivocada -> firma_invalida
PASS  6. ts viejo -> ts_fuera_de_ventana
PASS  7. ambiente cruzado -> ambiente_incorrecto
PASS  8. accion equivocada -> accion_desconocida

----- PAYLOAD (mes) -----
PASS  9. sin mes -> payload_invalido
PASS  10. mes mal formado (2026-13-99) -> payload_invalido
PASS  11. mes dia != 01 (2026-07-15) -> payload_invalido
PASS  12. mes pre-piso (2026-05-01) -> payload_invalido
PASS  13. clave no permitida -> payload_invalido

----- FUNCIONAL: foto pre-extension (2026-07-01) -----
    [obs] periodo=2026-07-01 cascada=8 socios=3 movimientos=3 gastos=0
PASS  F1. periodo round-trip (data.periodo == 2026-07-01)
PASS  F2. 14 claves top-level presentes
PASS  F3. las 8 secciones-lista son arrays
PASS  F4. sin_foto=false
PASS  F5. detalle_disponible=false + detalle_motivo=foto_pre_extension
PASS  F6. detalle fino vacio (participacion/gastos/incidencias/matriz/gastos_sin_incidencia)
PASS  F7. cabecera presente (no null) con linaje
PASS  F8. cascada no vacia
PASS  F9. socios no vacio
PASS  F10. retribucion_operativo presente (no null)
PASS  F11. movimientos dentro de la ventana [2026-07-01, +1 mes)

----- FUNCIONAL: mes sin foto (2026-09-01) -----
PASS  S1. sin_foto -> ok:true (NUNCA no_encontrado)
PASS  S2. 14 claves top-level presentes (rama sin foto)
PASS  S3. detalle_motivo == sin_foto_vigente
PASS  S4. las 8 secciones-lista vacias
PASS  S5. cabecera null y retribucion_operativo null
PASS  S6. detalle_disponible=false
PASS  S7. periodo round-trip (data.periodo == 2026-09-01)
PASS  META allowlist (todos los error.code en la allowlist)

===== RESUMEN =====
PASSED: 34
FAILED: 0
```

Exit code:

```text
0
```

---

## 6. Smoke gateway end-to-end — salida completa

Comando ejecutado:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\CC_L3_GW_smoke.ps1
```

Salida:

```text
=== L3 GATEWAY SMOKE (historico + acumulados) ===

----- A02 (sesion.contexto) -----
PASS  A02-0A contexto socio ok:true
PASS  A02-0B contexto vicky ok:true
PASS  A02-0C contexto jenny ok:true
PASS  A02-0D rol socio correcto
PASS  A02-0E rol vicky correcto
PASS  A02-0F rol jenny correcto
    [obs] socio ve 20 acciones; vicky 15; jenny 2
PASS  A02-1 socio ve cuenta_corriente.historico
PASS  A02-2 socio ve cuenta_corriente.historico_acumulados
PASS  A02-3 vicky NO ve historico
PASS  A02-4 vicky NO ve historico_acumulados
PASS  A02-5 jenny NO ve historico
PASS  A02-6 jenny NO ve historico_acumulados

----- SEGURIDAD (roles) -----
PASS  S1 historico vicky -> rol_no_permitido
PASS  S2 historico jenny -> rol_no_permitido
PASS  S3 historico sin JWT -> no_autorizado
PASS  S4 acumulados vicky -> rol_no_permitido
PASS  S5 acumulados jenny -> rol_no_permitido
PASS  S6 acumulados sin JWT -> no_autorizado
PASS  S7 accion inexistente -> accion_desconocida

----- PAYLOAD (gateway) -----
PASS  P1 historico sin mes -> payload_invalido
PASS  P2 historico dia != 01 -> payload_invalido
PASS  P3 historico pre-piso -> payload_invalido
PASS  P4 historico clave extra -> payload_invalido
PASS  P5 historico payload string -> payload_invalido
PASS  P6 acumulados {foo:1} -> payload_invalido
PASS  P7 acumulados array -> payload_invalido
PASS  P8 acumulados string -> payload_invalido
PASS  P9 acumulados {} -> ok:true
PASS  P10 acumulados payload omitido -> ok:true
PASS  P11 acumulados payload null -> ok:true

----- FUNCIONAL acumulados -----
    [obs] periodos vigentes: 2026-07-01, 2026-08-01, 2026-11-01
PASS  FA1 acumulados 6 claves
PASS  FA2 evolucion/saldos arrays; totales/meta objetos
PASS  FA3 piso == 2026-07-01
PASS  FA4 evolucion ordenada asc
PASS  FA5 meta.fotos_vigentes == evolucion.length

----- FUNCIONAL historico (gateway -> wrapper -> L3) -----
    [obs] MesPreExtension=2026-07-01  MesSinFoto=2026-09-01
PASS  FH-DERIV-1 foto pre-extension vigente hallada
PASS  FH-DERIV-2 mes sin foto hallado
PASS  FH1 foto: ok:true + 14 claves
PASS  FH2 foto: periodo round-trip (2026-07-01)
PASS  FH3 foto: sin_foto=false
PASS  FH4 foto: detalle_disponible=false + detalle_motivo=foto_pre_extension
PASS  FH5 foto: detalle fino vacio
PASS  FH6 foto: cabecera/cascada/socios/retribucion presentes
PASS  FH7 sin foto: ok:true + 14 claves
PASS  FH8 sin foto: sin_foto=true
PASS  FH9 sin foto: detalle_motivo=sin_foto_vigente
PASS  FH10 sin foto: 8 secciones vacias
PASS  FH11 sin foto: cabecera null y retribucion null
PASS  FH12 sin foto: periodo round-trip (2026-09-01)
PASS  META allowlist (todos los error.code en la allowlist)

===== RESUMEN =====
PASSED: 50
FAILED: 0
```

Exit code:

```text
0
```

---

## 7. Oracle AFTER — PARTE B

```json
[
  {
    "veredicto": "OK: 0 mutacion (forma 7/7/2/2 valida + counts + max_ids + table_hashes + sequences identicos)",
    "before_shape_ok": true,
    "after_shape_ok": true,
    "counts_iguales": true,
    "max_ids_iguales": true,
    "table_hashes_iguales": true,
    "sequences_iguales": true,
    "before_key_counts": {
      "counts": 7,
      "max_ids": 2,
      "sequences": 2,
      "table_hashes": 7
    },
    "after_key_counts": {
      "counts": 7,
      "max_ids": 2,
      "sequences": 2,
      "table_hashes": 7
    },
    "before_sin_captured_at": {
      "counts": {
        "liquidacion_gasto": 0,
        "liquidacion_socio": 12,
        "movimientos_socio": 4,
        "liquidacion_cascada": 32,
        "liquidaciones_periodo": 4,
        "liquidacion_incidencia": 0,
        "liquidacion_participacion": 0
      },
      "max_ids": {
        "movimientos_socio.id_movimiento": "14",
        "liquidaciones_periodo.id_liquidacion": "11"
      },
      "sequences": {
        "movimientos_socio_id_movimiento_seq": {
          "last_value": 14
        },
        "liquidaciones_periodo_id_liquidacion_seq": {
          "last_value": 14
        }
      },
      "table_hashes": {
        "liquidacion_gasto": "d751713988987e9331980363e24189ce",
        "liquidacion_socio": "b3c89e14ba7675aa71d17a478ff3e317",
        "movimientos_socio": "c8336a52f9f78275123264278c09dff1",
        "liquidacion_cascada": "26f9878d2e7785adaa5be0563a4bfd95",
        "liquidaciones_periodo": "26e0f933c2e2e40a39303e1c6b912e74",
        "liquidacion_incidencia": "d751713988987e9331980363e24189ce",
        "liquidacion_participacion": "d751713988987e9331980363e24189ce"
      }
    },
    "after_sin_captured_at": {
      "counts": {
        "liquidacion_gasto": 0,
        "liquidacion_socio": 12,
        "movimientos_socio": 4,
        "liquidacion_cascada": 32,
        "liquidaciones_periodo": 4,
        "liquidacion_incidencia": 0,
        "liquidacion_participacion": 0
      },
      "max_ids": {
        "movimientos_socio.id_movimiento": "14",
        "liquidaciones_periodo.id_liquidacion": "11"
      },
      "sequences": {
        "movimientos_socio_id_movimiento_seq": {
          "last_value": 14
        },
        "liquidaciones_periodo_id_liquidacion_seq": {
          "last_value": 14
        }
      },
      "table_hashes": {
        "liquidacion_gasto": "d751713988987e9331980363e24189ce",
        "liquidacion_socio": "b3c89e14ba7675aa71d17a478ff3e317",
        "movimientos_socio": "c8336a52f9f78275123264278c09dff1",
        "liquidacion_cascada": "26f9878d2e7785adaa5be0563a4bfd95",
        "liquidaciones_periodo": "26e0f933c2e2e40a39303e1c6b912e74",
        "liquidacion_incidencia": "d751713988987e9331980363e24189ce",
        "liquidacion_participacion": "d751713988987e9331980363e24189ce"
      }
    }
  }
]
```

---

## 8. Conclusión de las evidencias

Las evidencias demuestran conjuntamente:

1. A30 y A31 están correctamente expuestas en TEST.
2. Sólo los socios acceden a las nuevas acciones.
3. Los contratos de entrada y salida funcionan tanto directo como por gateway.
4. `sin_foto` y `sin_datos` son éxitos controlados.
5. La lectura combina información congelada y movimientos vivos sin mutar ninguna tabla.
6. Ante backend no disponible, las acciones read-only devuelven `error_entorno`.
7. Las pruebas dejaron intactas las siete tablas, sus filas, sus máximos ID y sus secuencias.
8. El Bloque 0 quedó verde y apto para iniciar el bloque de UI en TEST.

