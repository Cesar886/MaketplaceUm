Genera tres secretos distintos, de al menos 32 caracteres, directamente en el servidor:

```sh
umask 077
openssl rand -base64 48 > postgres_superuser_password
openssl rand -base64 48 > postgres_app_password
openssl rand -base64 48 > postgres_migrator_password
```

No copies estos archivos al repositorio ni los reutilices para JWT, TOTP o Mercado Pago.
