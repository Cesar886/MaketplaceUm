const express = require('express');
const cors = require('cors');

const routes = [
  require('./routes/categories'),
  require('./routes/products'),
  require('./routes/sellers'),
  require('./routes/cart'),
  require('./routes/listings'),
  require('./routes/highlightPlans'),
];

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json());

// Registrar rutas
for (const route of routes) {
  route.register(app);
}

// Health check
app.get('/api/health', (_req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 Mercadito UM API corriendo en http://localhost:${PORT}`);
});
