'use strict';

// Las rutas se montan también de forma aislada en pruebas y herramientas;
// instalar aquí el puente garantiza propagación de errores async aun cuando
// no se haya cargado todavía el entrypoint principal.
require('./asyncExpress').installAsyncExpressBridge();

// PostgreSQL es el único motor soportado. Mantener este punto de entrada
// estable evita que rutas y herramientas tengan que conocer el adaptador,
// pero una variable heredada ya no puede cambiar silenciosamente de motor.
module.exports = require('./database.postgres');
