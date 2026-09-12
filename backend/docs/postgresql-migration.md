# Operación de Marketplace UM sobre PostgreSQL

La API, las herramientas administrativas, las pruebas y los despliegues usan
PostgreSQL como único motor de base de datos. `DATABASE_URL` es obligatoria para
arrancar cualquier proceso que necesite persistencia.

## Arquitectura y seguridad

- PostgreSQL escucha en `127.0.0.1:5432`; el firewall no debe publicar ese
  puerto.
- `marketplace_app` sólo ejecuta DML. No crea tablas, roles ni bases.
- `marketplace_migrator` posee el esquema y se usa sólo durante despliegues.
- El superusuario se reserva para operación del contenedor y respaldos.
- Las tres contraseñas son distintas, SCRAM-SHA-256 y viven en archivos con
  modo `600` bajo `infra/postgres/secrets/`.
- La API limita pool, tiempo de conexión, consultas, locks y transacciones
  inactivas. Una base remota exige TLS con CA verificada.
- Todas las consultas de la aplicación siguen parametrizadas. Los únicos
  identificadores dinámicos tienen listas blancas.

## 1. Preparar PostgreSQL en el servidor

Desde `backend/infra/postgres/secrets`, genera los tres archivos descritos en
`README.md`. Usa secretos URL-safe si los vas a escribir en una URL. Después:

```sh
cd /root/mercaditoUmBack/infra/postgres
docker compose up -d
docker compose ps
```

Instala también en el host las herramientas cliente de PostgreSQL 16 y
comprueba `pg_dump --version`. El respaldo previo que exige una operación
administrativa sensible se ejecuta desde la API, no dentro del contenedor, y
por eso necesita `pg_dump` y `pg_restore` disponibles para el usuario de PM2.
El cliente debe ser de la misma versión mayor del servidor o una posterior.

El script `init/01-roles.sh` sólo corre cuando el volumen está vacío. Si el
volumen ya existía antes de agregarlo, crea los roles manualmente o recrea un
volumen vacío antes de cargar datos mediante un respaldo PostgreSQL verificado.

## 2. Aplicar el esquema

Crea `/root/mercaditoUmBack/.env.migrator` con modo `600`:

```dotenv
DATABASE_URL=postgresql://marketplace_migrator:CLAVE_URL_SAFE@127.0.0.1:5432/marketplace_um
PGSSL=false
PGSCHEMA=public
```

Luego aplica las migraciones versionadas:

```sh
cd /root/mercaditoUmBack
set -a; source ./.env.migrator; set +a
NODE_ENV=production PG_RUN_MIGRATIONS=true npm run db:migrate
unset DATABASE_URL
```

La migración usa un advisory lock, una transacción por archivo y checksum. La
API de producción sólo verifica que todos los archivos estén aplicados; no
posee permisos DDL. No edites una migración que ya fue aplicada: agrega el
siguiente archivo numerado en `migrations/postgres/`.

## 3. Configurar y arrancar la API

En `.env`, usa exclusivamente el rol limitado:

```dotenv
DATABASE_URL=postgresql://marketplace_app:OTRA_CLAVE_URL_SAFE@127.0.0.1:5432/marketplace_um
PGSSL=false
PGSCHEMA=public
PG_RUN_MIGRATIONS=false
PGPOOL_MAX=10
```

Arranca y verifica:

```sh
pm2 restart ecosystem.config.js --update-env
pm2 logs mercadito-backend --lines 100
curl --fail http://127.0.0.1:3000/api/health
```

Prueba además login, lista de productos, chat y un checkout de prueba.

## Respaldos y restauración

`npm run db:backup` produce un dump custom, lo valida con
`pg_restore --list` y usa permisos `600`. Instala el timer diario incluido:

```sh
cd /root/mercaditoUmBack
sudo ./scripts/install-postgres-backup-timer.sh
systemctl status marketplace-postgres-backup.timer
```

Por defecto conserva 14 días. `MERCADITO_BACKUP_MIRROR_DIR` permite copiar cada
dump a un volumen montado aparte; para tolerar la pérdida completa del servidor,
ese destino debe terminar replicado o montado desde otro host.

Prueba periódicamente una restauración completa, incluidos los privilegios:

```sh
./scripts/test-postgres-restore.sh infra/postgres/backups/marketplace_um-FECHA.dump
```

Para recuperar producción, detén primero la API, restaura un dump validado en
una instancia limpia, aplica cualquier migración posterior y sólo entonces
vuelve a habilitar escrituras. Nunca restaures encima de una instancia que sigue
recibiendo tráfico.

## PostgreSQL en otra máquina

Quita el bind local sólo en una red privada, limita `pg_hba.conf` a la IP de la
API y permite el puerto únicamente en el firewall interno. Configura:

```dotenv
PGSSL=true
PGSSL_CA_FILE=/etc/marketplace-um/postgres-ca.pem
```

La aplicación rechaza en producción una conexión remota sin TLS y nunca acepta
certificados sin verificar.
