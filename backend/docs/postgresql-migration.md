# Migración de Marketplace UM a PostgreSQL

La API usa PostgreSQL como única base de producción. El lector SQLite queda
instalado únicamente para crear snapshots, importar el archivo histórico y
ejecutar las pruebas legacy; la API de producción nunca lo selecciona.

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
volumen vacío antes de importar datos.

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

La migración usa un advisory lock, transacción por archivo y checksum. La API
de producción sólo verifica que todos los archivos estén aplicados; no posee
permisos DDL.

## 3. Trasladar el SQLite actual

Programa una ventana breve sin escrituras y detén PM2. El comando de snapshot
usa la API de backup de SQLite, valida tanto el origen como el resultado con
`quick_check` y llaves foráneas, registra conteos y genera SHA-256. Así consolida
correctamente cualquier WAL; no copies el `.db` en caliente ignorándolo.

Con PostgreSQL vacío y la API detenida:

```sh
cd /root/mercaditoUmBack
pm2 stop mercadito-backend
npm run db:snapshot-sqlite -- ./mercadito_um.db /root/marketplace-migration-snapshots
cd /root/marketplace-migration-snapshots
sha256sum -c mercadito_um-FECHA.db.sha256
cd /root/mercaditoUmBack
set -a; source ./.env.migrator; set +a
NODE_ENV=production npm run db:import-sqlite -- /root/marketplace-migration-snapshots/mercadito_um-FECHA.db --replace
unset DATABASE_URL
```

`--replace` sustituye únicamente tablas representadas por el snapshot, nunca
usa `CASCADE` y sólo debe usarse con la API detenida. El preflight compara todas
las tablas y columnas en ambos motores; cualquier omisión no clasificada,
catálogo incompleto, diferencia de conteos o cambio en una tabla preservada
hace rollback completo. También valida llaves foráneas, orden y secuencias.

## 4. Configurar y arrancar la API

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

Prueba además login, lista de productos, chat y un checkout de prueba. Conserva
el SQLite y el release anterior sin modificaciones hasta cerrar la validación.

## Respaldos y restauración

`npm run db:backup` produce un dump custom con ACL, lo valida con
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

Para volver atrás durante la primera ventana, detén la API nueva, restaura el
release anterior junto con la copia SQLite consistente y arráncalo. No habilites
escrituras simultáneas en SQLite y PostgreSQL: no existe replicación bidireccional.

## PostgreSQL en otra máquina

Quita el bind local sólo en una red privada, limita `pg_hba.conf` a la IP de la
API y permite el puerto únicamente en el firewall interno. Configura:

```dotenv
PGSSL=true
PGSSL_CA_FILE=/etc/marketplace-um/postgres-ca.pem
```

La aplicación rechaza en producción una conexión remota sin TLS y nunca
acepta certificados sin verificar.
