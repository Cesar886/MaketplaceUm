# Pruebas del panel administrativo con Postman

Importa `Marketplace-UM-Admin.postman_collection.json` y usa exclusivamente
las rutas bajo:

```text
https://mercaditoum.site/revision-8f4d9c2a/api
```

La ruta real del backend, `https://mercaditoum.site/api/admin/*`, está
bloqueada en Apache. El intermediario del panel (BFF) accede por loopback,
guarda el JWT en una cookie `Secure`, `HttpOnly`, `SameSite=Strict` y nunca lo
devuelve en el JSON.

## Uso

1. En las variables de la colección llena `username`, `password` y el TOTP
   vigente. No sincronices ni exportes una colección que ya tenga secretos.
2. Ejecuta **Login**. Postman debe guardar la cookie del dominio de forma
   automática.
3. Ejecuta **Validar sesión** y después las consultas de solo lectura.
4. Actualiza `account_id`, `publication_id` o `verification_id` antes de una
   operación de escritura. Esas peticiones modifican la base de producción.
   Para desbloquear esa carpeta deliberadamente, cambia `allow_writes` de
   `NO` a `SI_ENTIENDO` y vuelve a `NO` al terminar.
5. Genera un UUID v4 nuevo para `request_id` en cada cambio manual de
   verificación; reutilizarlo deliberadamente activa la defensa idempotente.
6. Ejecuta **Cerrar sesión** al terminar. Además de borrar la cookie, el
   backend revoca el `jti` del JWT hasta su expiración.

Toda mutación enviada al BFF exige simultáneamente `Origin` exacto,
`X-Revision-CSRF: 1`, JSON y una cookie administrativa vigente. Saber la URL
o copiar esos encabezados no sustituye la cookie, que solo se obtiene con
contraseña y TOTP válidos.
