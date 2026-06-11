# Vita Delta — Carril C — Portal Operativo Interno

## Diseño arquitectónico conceptual — Hub de operación, roles y permisos

## Contexto

Estamos desarrollando Vita Delta, sistema interno de reservas, operación y contabilidad para un complejo de cabañas en el Delta de Tigre.

La arquitectura principal ya existe o está en evolución:

* **Supabase** como fuente de verdad.
* **n8n** como capa de lógica de negocio y automatizaciones.
* Formularios internos en n8n para operaciones.
* Calendario operativo HTML ya existente.
* Sistema de reservas, pagos, bloqueos y contabilidad en evolución.
* Carril B en curso para contabilidad operativa interna.

Este carril es independiente.

**No estamos diseñando reservas.**
**No estamos diseñando contabilidad.**
**No estamos modificando schema.**
**No estamos reemplazando n8n ahora.**
**No estamos implementando todavía.**

El objetivo es diseñar una capa de experiencia operativa para el equipo interno: un único lugar donde cada persona vea y use las herramientas que necesita según su rol.

---

## Idea general

Hoy las operaciones están dispersas entre:

* formularios n8n;
* calendario HTML;
* vistas o links sueltos;
* futuras herramientas de contabilidad, limpieza, mantenimiento y reportes.

La idea es crear un **Portal Operativo Interno** para Vita Delta.

Puede empezar como algo muy simple:

* una web responsive;
* una PWA;
* un dashboard interno;
* una app futura;
* o un hub que agrupe formularios, calendarios y reportes.

No estamos decidiendo todavía la tecnología final. Queremos diseñar bien la arquitectura conceptual y el roadmap.

---

## Usuarios internos iniciales

Personas / roles a contemplar:

* **Franco**: acceso total.
* **Rodrigo**: acceso amplio / socio.
* **Remo**: acceso amplio / socio.
* **Vicky**: operación de reservas.
* **Jennifer / Jenny**: limpieza.

Ejemplos de permisos deseados:

* Jenny solo debería ver lo relacionado a limpieza: calendario de limpieza, tareas, próximas salidas/entradas, notas operativas necesarias.
* Vicky debería poder usar formularios de reservas, ver calendario de reservas y eventualmente ver las reservas que cargó o gestiona.
* Franco, Rodrigo y Remo deberían poder ver todo: calendarios, reservas, bloqueos, formularios, pagos, gastos, reportes, contabilidad y configuración.
* Algunos datos sensibles, como DNI, email, dinero o contabilidad, deberían estar restringidos según rol.

---

## Objetivo de esta conversación

Diseñar la arquitectura conceptual completa del Portal Operativo.

Quiero una respuesta de arquitectura, no implementación.

No escribir código.
No generar DDL.
No modificar schema.
No crear workflows n8n todavía.
No decidir tecnología prematuramente.

Primero quiero diagnóstico, alternativas, riesgos, roles, módulos, permisos y roadmap.

---

## Temas a analizar

### 1. Alcance funcional del portal

Definir qué módulos debería tener el portal ahora y a futuro.

Ejemplos:

* Reservas.
* Alta de reservas / pre-reservas.
* Pagos.
* Bloqueos.
* Calendario de reservas.
* Calendario de limpieza.
* Limpieza / tareas.
* Mantenimiento.
* Gastos.
* Contabilidad.
* Reportes.
* Configuración.
* Usuarios y permisos.
* Links útiles / herramientas internas.

Analizar si falta algún módulo y cuáles deberían ser MVP vs futuro.

---

### 2. Roles y permisos

Diseñar una matriz conceptual de permisos.

Roles iniciales sugeridos:

* Admin / socio total.
* Socio.
* Operación reservas.
* Limpieza.
* Mantenimiento, si aplica a futuro.

Para cada rol, definir:

* qué puede ver;
* qué puede crear;
* qué puede editar;
* qué no debería ver;
* qué datos sensibles deberían ocultarse;
* si necesita historial o auditoría.

Importante: separar permisos de interfaz de permisos reales. No alcanza con ocultar botones si el endpoint queda abierto.

---

### 3. Autenticación y control de acceso

Analizar alternativas para login y permisos:

A) Basic Auth de n8n por formulario/herramienta.
B) Login propio del portal.
C) Supabase Auth.
D) Cloudflare Access u otra capa externa.
E) Híbrido: portal con login + n8n protegido detrás.

Evaluar ventajas, riesgos y complejidad.

Puntos a considerar:

* usuarios y contraseñas individuales;
* revocar acceso cuando alguien deja de trabajar;
* permisos por rol;
* no compartir una misma clave para todos;
* uso desde celular;
* seguridad suficiente sin sobrediseñar;
* facilidad de mantenimiento por Franco.

---

### 4. Arquitectura técnica posible

Analizar alternativas:

A) Portal que simplemente agrupa links o iframes de formularios n8n y calendarios.
B) Portal propio que consume webhooks n8n.
C) Portal conectado directamente a Supabase.
D) Portal propio con backend intermedio.
E) Arquitectura híbrida progresiva.

Para cada alternativa, evaluar:

* complejidad;
* seguridad;
* migrabilidad;
* velocidad de implementación;
* dependencia de n8n;
* riesgo de exponer datos;
* facilidad para permisos por rol;
* mantenimiento futuro.

Mi sesgo inicial: empezar simple, probablemente con un hub/portal que use n8n como backend controlado, y evitar exponer Supabase directo al frontend salvo que esté muy bien justificado.

---

### 5. Migrabilidad futura

Diseñar para que:

* n8n pueda ser reemplazado en el futuro;
* los formularios puedan cambiar;
* Supabase siga siendo fuente de verdad;
* el portal no quede atado a URLs sueltas imposibles de mantener;
* los permisos puedan crecer sin rehacer todo;
* sea posible pasar de web simple a PWA/app si realmente aporta.

---

### 6. MVP y roadmap por fases

Proponer una evolución en fases, buscando máximo valor operativo con mínima complejidad.

Ejemplo tentativo:

**Fase 0 — Inventario**

* listar formularios, calendarios, endpoints y usuarios;
* mapear permisos actuales.

**Fase 1 — Hub operativo**

* login;
* menú por rol;
* links o embeds a formularios/calendarios existentes;
* sin rediseñar lógica de negocio.

**Fase 2 — Portal con endpoints controlados**

* consumir webhooks n8n;
* vistas más integradas;
* mejores permisos y auditoría.

**Fase 3 — App/PWA**

* experiencia móvil mejorada;
* notificaciones;
* tareas de limpieza/mantenimiento.

**Fase 4 — Reemplazo gradual de n8n si conviene**

* backend propio o servicios más robustos;
* n8n queda solo para automatizaciones o se reemplaza.

Podés ajustar estas fases si ves un orden mejor.

---

## Restricciones importantes

* No tocar schema en esta conversación.
* No tocar OPS.
* No implementar.
* No escribir código.
* No diseñar todavía la app visual en detalle.
* No mezclar este carril con 9F/9G de contabilidad.
* No asumir que todos deben ver todo.
* No depender de seguridad por “links ocultos”.
* No exponer Supabase directamente al frontend sin justificar seguridad y permisos.
* No sobrediseñar con una app grande si una web simple resuelve el 80%.

---

## Preguntas que quiero que respondas

1. ¿Tiene sentido crear este Carril C en paralelo al Carril B?
2. ¿Cuál debería ser el alcance del Portal Operativo?
3. ¿Qué módulos deberían entrar en el MVP y cuáles deberían esperar?
4. ¿Qué roles y permisos iniciales proponés?
5. ¿Qué arquitectura técnica recomendarías para empezar?
6. ¿Qué arquitectura evitarías por ahora?
7. ¿Cómo diseñarías la migrabilidad para no quedar atados a n8n?
8. ¿Qué riesgos ves?
9. ¿Qué decisiones habría que tomar antes de implementar?
10. ¿Qué roadmap por fases proponés?

---

## Forma de respuesta esperada

Quiero una respuesta de arquitectura conceptual, con:

* diagnóstico;
* módulos propuestos;
* matriz de roles/permisos;
* alternativas técnicas;
* recomendación;
* roadmap por fases;
* riesgos;
* decisiones pendientes.

No quiero todavía:

* código;
* DDL;
* workflows n8n;
* pantallas definitivas;
* elección cerrada de framework;
* implementación.
