

**1 Pre_reserva.**
Se verificó que upsert_huesped puede ejecutarse antes de un rechazo de pre-reserva. Se acepta el comportamiento vigente para este release. El riesgo general de actualización por identidad incorrecta existe tanto en operaciones rechazadas como exitosas y se resolverá en un futuro bloque de reconocimiento y verificación de huéspedes recurrentes, no mediante el simple reordenamiento del upsert.

Identidad segura y reconocimiento de huéspedes recurrentes
Con una interacción como:
¿Ya reservaste antes con nosotros?
[ Sí ]
[ No ]
Si responde “No”
Y el sistema encuentra que el teléfono o email ya existe:
Detectamos que este teléfono o email ya está registrado. Revisá los datos ingresados o indicá que ya reservaste anteriormente.
La operación debería frenarse antes de actualizar nada.
Si responde “Sí”
Se intenta reconocer al huésped existente. Más adelante incluso podría verificarse con:
código enviado por WhatsApp;
código por email;
últimos dígitos del teléfono;
confirmación humana.
Conflicto fuerte
Si sucede esto:
email → huésped 10
teléfono → huésped 20
debe devolverse un conflicto explícito:
Los datos ingresados corresponden a registros diferentes.
No se actualiza ni se fusiona ningún huésped.
Requiere revisión.
Nunca debería elegirse uno silenciosamente ni mezclar automáticamente las dos identidades.

