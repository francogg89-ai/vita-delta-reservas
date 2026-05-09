ARQUITECTURA CONVERSACIONAL — BOT IA + BACKEND DETERMINÍSTICO
Principio arquitectónico fundamental
La IA NO debe ser la fuente de verdad operacional del sistema.
La IA debe funcionar como:
interfaz conversacional,
capa cognitiva,
intérprete de lenguaje natural,
asistente comercial,
capa de comunicación con el cliente.
Mientras que:
disponibilidad,
reservas,
bloqueos,
pricing,
concurrencia,
estados,
pagos,
validaciones,
integridad de datos,
deben ser manejados exclusivamente por workflows determinísticos y motores reales del sistema.

Qué NO debe hacer la IA
La IA NO debe decidir directamente:
disponibilidad real,
conflictos de reservas,
solapamientos,
cálculo final de precios,
estados de reservas,
pagos,
bloqueos,
reglas de negocio,
prioridades,
integridad de datos,
concurrencia,
overrides,
confirmaciones finales.
Razón:
Los modelos de IA:
pueden alucinar,
interpretar mal,
cambiar comportamiento,
responder distinto ante el mismo input,
no garantizan exactitud determinística.
Y un sistema de reservas necesita consistencia absoluta.

Qué SÍ debe hacer la IA
La IA funciona como capa cognitiva.
Excelente para:
conversación,
interpretación,
ventas,
persuasión,
empatía,
contexto,
lenguaje natural,
detectar intención,
explicar,
resumir,
asistir,
traducir,
guiar al cliente.

Arquitectura correcta del sistema
Cliente
↓
Bot IA (WhatsApp / Instagram / Web)
↓
n8n / Backend
↓
Motores reales del sistema
disponibilidad
precios
reservas
bloqueos
overrides
↓
Base de datos / cache

Ejemplo correcto de funcionamiento
Consulta del cliente
Cliente:
“Quisiera saber si hay algo disponible para el fin de semana del 25 de mayo.”
Rol de la IA
La IA:
interpreta intención,
entiende fechas,
entiende lenguaje humano,
entiende contexto,
puede preguntar:
“¿Para cuántas personas?”
“¿Preferís cabaña chica o grande?”
PERO:
La IA NO calcula disponibilidad.

Flujo correcto
IA
↓
Llama workflow real
↓
Workflow consulta DISPONIBILIDAD_CACHE
↓
Workflow consulta motor de precios
↓
Workflow devuelve JSON estructurado
↓
IA traduce resultado a lenguaje humano

Ejemplo de respuesta estructurada del workflow
{
  "disponible": true,
  "cabana": "Bamboo",
  "fecha_in": "2026-05-25",
  "fecha_out": "2026-05-27",
  "precio_total": 350000,
  "sena": 175000,
  "checkin": "13:00",
  "checkout": "16:00"
}


Ejemplo de respuesta final de la IA
“Sí, para el fin de semana del 25 de mayo tengo disponible Bamboo para hasta 5 personas.
El check-in sería a las 13:00 y el checkout a las 16:00.
El total es de $350.000 y la seña requerida es del 50%.”

Consumo de tokens
Este enfoque consume pocos tokens si está bien diseñado.
La IA solo procesa:
mensaje del cliente,
contexto mínimo,
respuesta estructurada corta del workflow.
Lo que NO debe hacerse:
enviar toda la planilla a la IA,
enviar todas las reservas,
enviar todas las reglas,
enviar toda la lógica del sistema.
La IA nunca debería “leer toda la base”.

Generación automática de links de reserva
La IA sí puede generar automáticamente un flujo hacia la reserva.
Flujo ideal
Cliente:
“Quiero ese fin de semana.”
↓
La IA detecta intención de avanzar.
↓
La IA llama workflow:
crear_pre_reserva_o_link
↓
n8n:
valida disponibilidad nuevamente,
crea PRE_RESERVA,
bloquea disponibilidad temporalmente,
genera link único.
↓
La IA envía el link final al cliente.

Importante: usar PRE_RESERVA
No conviene generar links simples modificables por URL.
Malo:
/reservar?cabana=bamboo&in=2026-05-25

Porque el cliente podría modificar parámetros manualmente.

Arquitectura recomendada
Usar:
/reservar?pre_reserva=PR_83921

Donde:
la PRE_RESERVA ya existe en backend,
las fechas ya están validadas,
la disponibilidad ya fue bloqueada,
el precio ya fue calculado.
La web solo lee la PRE_RESERVA y muestra la información.

Flujo completo ideal
Cliente consulta
IA interpreta intención
n8n consulta disponibilidad y pricing
IA responde
Cliente acepta
IA llama workflow de PRE_RESERVA
n8n crea PRE_RESERVA
PRE_RESERVA bloquea disponibilidad temporalmente
n8n genera link seguro
IA envía link
Cliente entra a la web
Cliente paga seña
n8n valida pago
n8n confirma RESERVA
Calendario y disponibilidad se actualizan automáticamente

Principio arquitectónico final
La IA:
conversa,
interpreta,
vende,
asiste,
comunica.
El backend:
calcula,
valida,
reserva,
bloquea,
confirma,
mantiene integridad del sistema.
Nunca mezclar ambos roles.
