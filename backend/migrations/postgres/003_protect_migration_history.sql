-- La API necesita leer este historial al arrancar, pero nunca debe poder
-- alterar los checksums que protegen la integridad de las migraciones.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'marketplace_app') THEN
    REVOKE ALL ON TABLE schema_migrations FROM marketplace_app;
    GRANT SELECT ON TABLE schema_migrations TO marketplace_app;
  END IF;
END
$$;
