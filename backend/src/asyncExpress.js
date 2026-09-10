'use strict';

const INSTALLED = Symbol.for('marketplaceUm.expressAsyncBridge');

/**
 * Express 4 no envía al middleware de errores los rechazos de handlers async.
 * PostgreSQL vuelve asíncrona toda ruta que consulta la base, por lo que el
 * puente se instala una sola vez en el prototipo compartido de Router.Layer.
 */
function installAsyncExpressBridge() {
  const Layer = require('express/lib/router/layer');
  if (Layer.prototype[INSTALLED]) return;
  const original = Layer.prototype.handle_request;
  Layer.prototype.handle_request = function handleAsyncRequest(req, res, next) {
    const handler = this.handle;
    if (handler.length > 3) return original.call(this, req, res, next);
    try {
      const result = handler(req, res, next);
      if (result && typeof result.then === 'function') result.catch(next);
    } catch (error) {
      next(error);
    }
  };
  Object.defineProperty(Layer.prototype, INSTALLED, { value: true });
}

module.exports = { installAsyncExpressBridge };
