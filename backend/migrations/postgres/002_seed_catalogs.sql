-- Catálogos mínimos para una instalación nueva. Son idempotentes para que
-- una importación posterior conserve los valores que ya existan.
INSERT INTO categories (id, name, emoji, icon, color) VALUES
  ('books', 'Libros', '📚', 'menu_book', '#2A6FBB'),
  ('notes', 'Apuntes', '📝', 'article', '#D97706'),
  ('electronics', 'Electrónicos', '💻', 'devices', '#1B998B'),
  ('clothes', 'Ropa', '👔', 'checkroom', '#9B5DE5'),
  ('services', 'Servicios', '🛠️', 'construction', '#E76F51'),
  ('food', 'Comida', '🍕', 'restaurant', '#E86F2C'),
  ('housing', 'Hospedaje', '🛏️', 'bed', '#6A994E'),
  ('other', 'Otros', '📦', 'category', '#607D8B')
ON CONFLICT (id) DO NOTHING;

INSERT INTO highlight_plans (id, title, price, description, days) VALUES
  ('d1', 'Destacado 24h', '$20', 'Para ventas rapidas y urgentes. Aparece arriba por un dia.', 1),
  ('d3', 'Destacado 3 dias', '$40', 'Buena opcion para rotar inventario sin pagar de mas.', 3),
  ('d7', 'Destacado 7 dias', '$70', 'Mayor visibilidad durante toda la semana escolar.', 7),
  ('m1', 'Plan mensual', '$180', 'Pensado para negocios fijos: aparece arriba en su categoria todo el mes.', 30)
ON CONFLICT (id) DO NOTHING;

INSERT INTO config (
  key, products_active, products_daily, wanted_active, wanted_daily, duration_days
) VALUES
  ('negocio_verificado', 40, 8, 10, 3, 60),
  ('um_verificado', 30, 6, 10, 3, 60),
  ('negocio_sin_verificar', 15, 3, 4, 1, 20),
  ('um_sin_verificar', 10, 3, 5, 2, 30),
  ('externo', 8, 2, 3, 1, 30)
ON CONFLICT (key) DO NOTHING;
