# Acceso seguro al panel de superusuario

Esta cuenta es un **administrador de Marketplace UM**, no el superusuario de
PostgreSQL. Nunca uses las credenciales de `marketplace_postgres` o
`marketplace_migrator` para entrar al panel.

## Antes de crear la cuenta

En el servidor deben cumplirse estas condiciones:

- PostgreSQL está levantado y las migraciones ya fueron aplicadas.
- `/root/mercaditoUmBack/.env` tiene `DATABASE_URL` con el rol limitado
  `marketplace_app`.
- `ADMIN_JWT_SECRET`, `ADMIN_TOTP_ENCRYPTION_KEY` y
  `ADMIN_BFF_SHARED_SECRET` son valores distintos de al menos 32 caracteres.
- `ADMIN_PANEL_ORIGIN` contiene el origen HTTPS exacto, sin ruta ni `/` final:
  `https://marketplace-um.me`.
- El `.env` del sitio Next usa el mismo `ADMIN_BFF_SHARED_SECRET`, tiene
  `API_URL=http://127.0.0.1:3000` y el mismo `ADMIN_PANEL_ORIGIN`.

No cambies `ADMIN_TOTP_ENCRYPTION_KEY` después de crear cuentas: esa llave
cifra sus semillas 2FA. Si vienes de SQLite, conserva exactamente la llave que
ya usaba producción.

## 1. Comprobar los servicios

```sh
cd /root/mercaditoUmBack
curl --fail http://127.0.0.1:3000/api/health
pm2 status
```

El backend y `mercadito-website` deben aparecer activos. No continúes si la
salud del backend falla.

## 2. Crear el administrador sin guardar la contraseña en el historial

Ejecuta el asistente en una terminal privada del servidor. La contraseña
debe tener entre 14 y 72 bytes. El usuario admite 3-64 caracteres en minúsculas:
letras, números, punto, guion o guion bajo.

```sh
cd /root/mercaditoUmBack
./scripts/create-superuser-interactive.sh
```

No escribas la contraseña como `ADMIN_CREATE_PASSWORD=...` en la línea de
comandos ni la agregues a `.env`. El asistente la pide dos veces sin mostrarla,
la mantiene sólo durante el proceso y limpia las variables al terminar.

El comando se niega a sobrescribir un usuario existente. Al completarse muestra
un QR una sola vez; no cierres la terminal todavía.

## 3. Registrar y comprobar el segundo factor

1. Abre una aplicación TOTP en el teléfono (por ejemplo, Google Authenticator,
   Microsoft Authenticator o el gestor de contraseñas de tu organización).
2. Elige **Agregar cuenta** y escanea el QR de la terminal.
3. Verifica que el teléfono y el servidor tengan la hora automática correcta.
4. Guarda la cuenta TOTP en el mecanismo de respaldo cifrado de la organización.
   No tomes una captura del QR ni lo envíes por chat o correo.
5. Deja que aparezca un código nuevo antes de hacer varios intentos: un mismo
   código válido no se puede reutilizar para dos inicios de sesión.

## 4. Entrar al panel

1. Abre directamente
   <https://marketplace-um.me/revision-8f4d9c2a> en un navegador actualizado.
2. Escribe el usuario creado, la contraseña y los seis dígitos vigentes del
   autenticador.
3. Pulsa **Entrar al panel**.
4. Comprueba que se muestren las secciones Verificaciones, Dashboard, Reportes,
   Usuarios, Publicaciones, Configuración y Auditoría.
5. Al terminar, pulsa **Cerrar sesión**; esto revoca la sesión además de borrar
   la cookie del navegador.

La URL no es una contraseña y puede ser conocida por terceros. La protección
real es contraseña + TOTP, el límite de intentos y la sesión `Secure`,
`HttpOnly`, `SameSite=Strict`. El panel debe usarse únicamente por HTTPS.

## Recuperación y errores comunes

- **“La autenticación administrativa no está configurada”**: revisa que
  `ADMIN_JWT_SECRET` y `ADMIN_TOTP_ENCRYPTION_KEY` existan, sean distintos y
  tengan al menos 32 caracteres; reinicia el backend con
  `pm2 restart mercadito-backend --update-env`.
- **“Ese administrador ya existe”**: no se reemplazó ninguna credencial. Usa
  la cuenta existente o crea una cuenta de recuperación con otro nombre.
- **Credenciales o código inválidos**: confirma el usuario, espera un TOTP
  nuevo y sincroniza automáticamente la hora del teléfono y del servidor. No
  pruebes repetidamente: el limitador bloqueará temporalmente los intentos.
- **Error 403**: comprueba que ambos `.env` tengan exactamente
  `ADMIN_PANEL_ORIGIN=https://marketplace-um.me`, que se esté usando HTTPS y
  que no se haya entrado por un host alternativo como `www`.
- **Error 502**: desde el servidor verifica
  `curl --fail http://127.0.0.1:3000/api/health`, `API_URL` en el sitio y los
  logs de ambos procesos PM2. Nunca apuntes `API_URL` a HTTP público.
- **El login vuelve al formulario**: entra por HTTPS, permite cookies del sitio
  y borra únicamente la cookie del dominio antes de reintentar. La sesión dura
  30 minutos.
- **Se perdió contraseña o TOTP**: desde una sesión privada del servidor crea
  primero otro administrador con un nombre diferente usando el mismo flujo.
  Valida el nuevo acceso y después solicita al operador de base de datos que
  desactive la cuenta perdida e invalide su `token_version`. No borres la fila:
  debe conservarse la trazabilidad de auditoría.
- **Se perdió `ADMIN_TOTP_ENCRYPTION_KEY`**: los TOTP antiguos no son
  recuperables. Restaura la llave desde el respaldo secreto autorizado o crea
  una cuenta de reemplazo. Nunca pruebes llaves ni semillas directamente en la
  base productiva.

Registra toda recuperación como incidente operativo, pero nunca copies
contraseñas, semillas TOTP, JWT ni secretos de entorno en tickets o logs.
