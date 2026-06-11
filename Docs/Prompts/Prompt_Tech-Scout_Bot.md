# Vita Delta — Carril D — Tech-Scout Bot / Radar Tecnológico Automatizado

## Diseño conceptual de radar tecnológico por proyecto

## Contexto general

Estamos desarrollando **Vita Delta**, un sistema integral para un complejo de cabañas en el Delta de Tigre.

El proyecto no es solo un sistema de reservas. La visión completa incluye:

* operación interna;
* reservas;
* pagos;
* bloqueos;
* calendario operativo;
* limpieza;
* mantenimiento;
* contabilidad interna;
* portal operativo interno;
* web pública;
* cobro online por la web;
* bot conversacional para clientes;
* bot por WhatsApp;
* bot por Instagram;
* automatizaciones n8n;
* paneles/reportes;
* seguridad;
* backups;
* migrabilidad futura;
* posible reemplazo de herramientas actuales si aparece algo mejor.

La arquitectura actual y en evolución usa principalmente:

* **Supabase / PostgreSQL** como fuente de verdad;
* **n8n** como capa de automatización, formularios y lógica operativa;
* formularios internos n8n;
* calendario HTML operativo;
* funciones SQL en Supabase;
* Claude / IA como copiloto de diseño, auditoría y automatización;
* futuro portal operativo interno;
* futura web pública;
* futura capa conversacional multicanal.

Este carril es independiente de los carriles de implementación actuales.

No estamos modificando reservas.
No estamos modificando contabilidad.
No estamos tocando schema.
No estamos implementando todavía.
No estamos eligiendo herramientas definitivas.

El objetivo es diseñar un **Tech-Scout Bot**, también llamado **Radar Tecnológico Automatizado**, capaz de monitorear novedades tecnológicas relevantes para Vita Delta y para futuros proyectos.

---

## Idea principal

Quiero crear un sistema que, conociendo el estado y la arquitectura de cada proyecto, busque periódicamente tecnologías, actualizaciones, herramientas, librerías, servicios, cambios de precios, mejoras de seguridad, alternativas y buenas prácticas que podrían mejorar el proyecto.

El objetivo no es perseguir modas tecnológicas.

El objetivo es tener un radar que detecte señales útiles y las traduzca en decisiones posibles.

Ejemplos de alertas deseadas:

* “n8n lanzó una mejora en formularios que podría simplificar el flujo actual de reservas.”
* “Supabase agregó una función de Auth o permisos que podría servir para el Portal Operativo Interno.”
* “Apareció una alternativa más simple para proteger endpoints internos.”
* “Hay una nueva forma de hacer backups/restores en Supabase/Postgres que conviene evaluar antes de escalar OPS.”
* “WhatsApp Business API cambió precios o reglas que afectan al futuro bot conversacional.”
* “Instagram Messaging API agregó una capacidad útil para atención automática.”
* “Mercado Pago / Stripe / MODO / otro medio de pago lanzó una integración que podría servir para cobro web.”
* “Apareció una herramienta open-source que podría reemplazar parte de n8n en el futuro.”
* “Una vulnerabilidad o cambio de seguridad afecta alguna herramienta del stack.”
* “Un nuevo modelo de IA más barato/rápido podría servir para el bot de atención o auditoría interna.”

El bot debe ayudarme a no quedar atado a herramientas actuales, pero sin generar FOMO ni distracciones.

Frase guía:

> El Tech-Scout no cambia arquitectura; alimenta decisiones de arquitectura.

---

## Alcance del proyecto Vita Delta que el radar debe conocer

El radar debe contemplar tanto lo existente como lo pendiente.

### 1. Sistema operativo interno actual

* Reservas.
* Pre-reservas.
* Confirmaciones.
* Pagos.
* Bloqueos.
* Calendario operativo.
* Formularios n8n.
* Supabase como base de datos.
* Funciones SQL.
* Entornos TEST / OPS.
* Seguridad básica por credenciales.
* Operación desde celular.

### 2. Contabilidad interna

* Carril B en desarrollo.
* Gastos.
* Pagos.
* Matriz de participación.
* Cascada de liquidación.
* Saldos internos.
* Retiros.
* Conversión ARS/USD futura.
* Reportes para socios.
* Separación estricta de fiscal/AFIP/ARCA/IVA.

### 3. Portal operativo interno

Futuro Carril C:

* login por usuario;
* permisos por rol;
* Franco/Rodrigo/Remo con acceso amplio;
* Vicky con operación de reservas;
* Jennifer/Jenny con limpieza;
* calendarios;
* formularios;
* reportes;
* tareas;
* mantenimiento;
* contabilidad según permisos.

### 4. Web pública

Pendiente futuro:

* sitio de Vita Delta;
* presentación de cabañas;
* fotos;
* disponibilidad;
* consulta de precios;
* solicitud de reserva;
* pago online;
* integración con calendario/reservas;
* SEO;
* velocidad;
* seguridad;
* mantenimiento simple.

### 5. Cobro online

Pendiente futuro:

* cobro por seña;
* saldo;
* pagos parciales;
* links de pago;
* integración con Mercado Pago, MODO, transferencia, Stripe u otros;
* conciliación con Supabase;
* webhooks de pagos;
* seguridad;
* comprobantes;
* auditoría.

### 6. Bot conversacional multicanal

Pendiente futuro:

* bot en la web;
* bot por WhatsApp;
* bot por Instagram;
* posible bot por Facebook u otros canales;
* consulta de disponibilidad;
* preguntas frecuentes;
* envío de precios;
* generación de pre-reserva;
* seguimiento de pagos;
* instrucciones de llegada;
* reglas de la casa;
* soporte post-reserva;
* derivación a humano;
* control de alucinaciones;
* integración con Supabase/n8n;
* logging y auditoría.

### 7. Seguridad, backups y observabilidad

El radar debe monitorear oportunidades en:

* autenticación;
* permisos por rol;
* protección de webhooks;
* manejo de secretos;
* backups de Supabase/Postgres;
* pruebas de restore;
* logs;
* alertas;
* errores de n8n;
* monitoreo de workflows;
* rate limits;
* protección contra abuso;
* auditoría de operaciones.

### 8. Migrabilidad

El radar debe ayudar a evitar dependencia excesiva de:

* n8n;
* Supabase;
* un proveedor de IA;
* un proveedor de pagos;
* un canal de mensajería;
* una herramienta no-code específica.

Debe detectar alternativas, pero sin recomendar cambios si no hay un beneficio claro.

---

## Objetivo de esta conversación

Diseñar conceptualmente el **Tech-Scout Bot / Radar Tecnológico Automatizado**.

Quiero una arquitectura y un plan.

No quiero implementación todavía.

No quiero código.
No quiero DDL.
No quiero workflows n8n.
No quiero prompts definitivos de producción.
No quiero elegir herramientas cerradas todavía.

Primero quiero:

* alcance;
* arquitectura conceptual;
* fuentes de información;
* criterios de relevancia;
* categorías de hallazgos;
* estructura de salida;
* cómo evitar ruido;
* cómo priorizar;
* cómo guardar histórico;
* roadmap por fases;
* riesgos;
* decisiones pendientes.

---

## Rol que quiero que tomes

Actuá como:

* arquitecto de software senior;
* asesor de estrategia tecnológica;
* auditor crítico;
* diseñador de sistemas automatizados;
* especialista en evitar sobreingeniería;
* alguien que entiende que el foco del negocio es operar mejor Vita Delta, no probar herramientas por moda.

Cuestioná supuestos.

Detectá riesgos.

Priorizá simplicidad, bajo mantenimiento y utilidad real.

---

## Arquitectura conceptual inicial imaginada

La idea inicial podría seguir esta filosofía:

> PostgreSQL/Supabase persiste.
> n8n orquesta.
> IA analiza y resume.
> Franco decide.

Flujo posible:

1. Fuentes de información.
2. n8n recolecta periódicamente.
3. IA filtra y compara contra el contexto del proyecto.
4. Supabase guarda hallazgos relevantes.
5. Se genera un digest semanal o alerta puntual.
6. Franco revisa, descarta, posterga o transforma en decisión de arquitectura.

Pero esta arquitectura es tentativa. Podés cuestionarla.

---

## Fuentes posibles a monitorear

Proponer y priorizar fuentes para distintos tipos de novedades.

### Herramientas actuales

* n8n releases / blog / GitHub.
* Supabase blog / changelog / GitHub.
* PostgreSQL releases.
* OpenAI / Anthropic / modelos de IA.
* Proveedores de hosting si aplica.
* Herramientas de correo / SMTP / Mailgun si aplica.

### Futuras áreas del proyecto

* Supabase Auth / alternativas de auth.
* Cloudflare Access / Zero Trust / seguridad simple.
* PWA / frameworks web simples.
* WhatsApp Business Platform.
* Instagram Messaging API.
* Meta for Developers.
* Mercado Pago Developers.
* MODO / pagos argentinos.
* Stripe, solo si tiene sentido.
* Herramientas de calendario.
* Herramientas de dashboards internos.
* Herramientas de backup y restore.
* Observabilidad y logs.

### Ecosistema general

* Hacker News.
* Product Hunt.
* Reddit: r/n8n, r/selfhosted, r/Supabase, r/PostgreSQL, r/LocalLLaMA, r/webdev.
* GitHub Trending, pero filtrado.
* Newsletters técnicas seleccionadas.
* Blogs de seguridad relevantes.

No quiero que el radar lea todo. Quiero que diseñes una estrategia para evitar ruido.

---

## Tipos de hallazgo que sí importan

Clasificar hallazgos en categorías como:

1. **Seguridad crítica**

   * vulnerabilidades;
   * cambios de autenticación;
   * malas prácticas detectadas;
   * exposición de claves;
   * protección de webhooks.

2. **Mejora directa del stack actual**

   * nueva función de n8n que reemplaza workaround;
   * nueva función de Supabase útil;
   * mejoras en Postgres;
   * mejoras de logs/backups.

3. **Ahorro de costo**

   * APIs de IA más baratas;
   * cambios de precio;
   * servicios que reemplazan otros más caros.

4. **Ahorro de tiempo operativo**

   * herramientas que simplifican formularios;
   * dashboards;
   * gestión de tareas;
   * reportes.

5. **Mejora de seguridad/backups/observabilidad**

   * soluciones de backup;
   * restore testing;
   * monitoreo;
   * alertas.

6. **Mejora para portal operativo interno**

   * auth por rol;
   * PWA;
   * dashboards internos;
   * permisos.

7. **Mejora para web pública**

   * performance;
   * SEO;
   * formularios;
   * integración con reservas;
   * hosting.

8. **Mejora para cobro online**

   * pagos;
   * webhooks;
   * conciliación;
   * links de pago;
   * cuotas/comisiones.

9. **Mejora para bot conversacional**

   * WhatsApp;
   * Instagram;
   * web chat;
   * modelos de IA;
   * reducción de alucinaciones;
   * RAG;
   * logging;
   * handoff a humano.

10. **Reemplazo futuro de pieza actual**

* alternativa a n8n;
* alternativa a Supabase;
* alternativa de IA;
* alternativa de portal/app.

11. **Interesante pero no accionable**

* guardar, pero no interrumpir roadmap.

---

## Reglas anti-FOMO

El radar debe tener reglas explícitas para no distraer.

Por ejemplo:

* No recomendar migraciones grandes salvo que haya un beneficio claro.
* No sugerir cambiar tecnología durante una etapa crítica salvo riesgo de seguridad.
* No confundir “nuevo” con “mejor”.
* No alertar por herramientas sin relación directa con el proyecto.
* No enviar más de X hallazgos por semana.
* Separar “revisar urgente” de “guardar para futuro”.
* Toda recomendación debe incluir costo de adopción y riesgo.
* El humano decide.

---

## Salida esperada de cada hallazgo

Diseñar el formato ideal de salida.

Cada hallazgo debería incluir, por ejemplo:

* proyecto afectado;
* área afectada;
* fuente;
* link;
* fecha;
* tecnología;
* resumen;
* qué cambió;
* por qué importa;
* etapa o módulo afectado;
* impacto estimado;
* urgencia;
* costo de adopción;
* riesgo de adopción;
* riesgo de no hacer nada;
* recomendación;
* acción sugerida;
* estado: nuevo / descartado / evaluar / postergado / adoptado;
* comentario humano;
* fecha de próxima revisión.

---

## Proyectos futuros

Aunque el primer caso sea Vita Delta, quiero que el diseño sea reutilizable para otros proyectos.

El radar debería poder tener perfiles por proyecto:

* Vita Delta.
* Bemvelon / restobar.
* Travesías Delta / turismo.
* futuros proyectos tecnológicos.
* proyectos personales.

Cada proyecto debería tener:

* stack actual;
* módulos existentes;
* módulos futuros;
* prioridades;
* restricciones;
* fuentes relevantes;
* palabras clave;
* tecnologías prohibidas o no deseadas;
* nivel de tolerancia al cambio;
* frecuencia de revisión.

---

## Roadmap deseado

Proponer fases.

Ejemplo tentativo:

### Fase 0 — Diseño del perfil del proyecto

* Crear ficha técnica de Vita Delta.
* Listar stack actual.
* Listar módulos futuros.
* Listar prioridades.
* Listar restricciones.
* Definir categorías de hallazgos.

### Fase 1 — Radar manual asistido

* Sin automatizar todavía.
* Usar un prompt semanal.
* Pegar novedades o links manualmente.
* La IA filtra contra el perfil de Vita Delta.
* Sirve para validar si el formato de hallazgos aporta valor.

### Fase 2 — Recolección automatizada simple

* n8n lee RSS, GitHub releases, blogs y APIs.
* IA clasifica.
* Digest semanal por email o HTML interno.
* Sin scraping frágil.

### Fase 3 — Persistencia en Supabase

* tabla de hallazgos;
* histórico;
* estados;
* decisiones humanas;
* tags por proyecto;
* búsqueda.

### Fase 4 — Integración al Portal Operativo

* sección “Radar tecnológico” solo para Franco/socios;
* hallazgos pendientes;
* decisiones;
* seguimiento.

### Fase 5 — Radar multi-proyecto

* perfiles separados;
* fuentes específicas;
* digest por proyecto;
* métricas de utilidad.

Podés ajustar las fases.

---

## Preguntas que quiero que respondas

1. ¿Tiene sentido este Tech-Scout Bot para Vita Delta y futuros proyectos?
2. ¿Qué problema real resuelve?
3. ¿Qué riesgos tiene?
4. ¿Cómo evitar que genere ruido o distracción?
5. ¿Qué debería saber sobre cada proyecto?
6. ¿Qué fuentes conviene monitorear primero?
7. ¿Qué fuentes conviene evitar al principio?
8. ¿Qué categorías de hallazgos proponés?
9. ¿Qué formato debería tener cada hallazgo?
10. ¿Conviene empezar manual/semi-automático antes de automatizar?
11. ¿Cómo sería la arquitectura MVP?
12. ¿Dónde debería persistirse la información?
13. ¿Con qué frecuencia debería correr?
14. ¿Cómo se integra a futuro con el Portal Operativo?
15. ¿Qué decisiones habría que tomar antes de implementar?
16. ¿Qué roadmap por fases recomendás?

---

## Restricciones

* No implementar todavía.
* No escribir código.
* No crear DDL.
* No hacer workflows n8n.
* No elegir stack definitivo.
* No mezclarlo con el desarrollo actual de 9F/9G.
* No interrumpir el roadmap principal salvo seguridad crítica.
* No recomendar migraciones grandes sin evidencia.
* No diseñarlo como lector genérico de noticias.
* No generar FOMO.

---

## Forma de respuesta esperada

Quiero una respuesta de arquitectura conceptual con:

1. diagnóstico;
2. definición del Tech-Scout Bot;
3. perfiles por proyecto;
4. fuentes recomendadas;
5. categorías de hallazgos;
6. criterios de relevancia;
7. reglas anti-ruido;
8. arquitectura conceptual;
9. formato de salida;
10. roadmap por fases;
11. riesgos;
12. decisiones pendientes;
13. recomendación final.

No quiero todavía:

* código;
* DDL;
* workflows;
* prompts definitivos de producción;
* implementación.
