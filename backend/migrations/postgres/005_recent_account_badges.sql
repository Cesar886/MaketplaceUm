-- Conserva el instante de la primera verificación en el registro idempotente
-- de insignias. Las verificaciones futuras lo insertan al aprobarse; esto
-- rescata las cuentas que ya estaban verificadas antes de esa lógica.
INSERT INTO insignias_otorgadas (seller_id, clave, otorgada_en)
SELECT usuario_id, 'recien_verificado', fecha_verificacion
  FROM verificaciones
 WHERE estado = 'verificado' AND fecha_verificacion IS NOT NULL
ON CONFLICT (seller_id, clave) DO NOTHING;
