// Verificación de cuentas.
//
// Dos flujos según el tipo de cuenta:
//   estudiante → OTP al correo institucional (<matrícula>.um.edu.mx)
//   negocio    → solicitud manual con INE y evidencias para revisión privada
// Las cuentas particulares pueden usar el marketplace, pero no se verifican.
//
// `sellers.verified` es la bandera rápida que lee toda la app; la tabla
// `verificaciones` guarda el detalle del flujo. Ambas se escriben en la misma
// transacción para que nunca queden en desacuerdo.

const crypto = require('crypto');
const express = require('express');
const fs = require('fs');
const path = require('path');
const multer = require('multer');
const { requireAuth } = require('../auth');
const {
  generarCodigo,
  hashCodigo,
  verificarCodigo,
  calcularExpiracion,
  VIGENCIA_MINUTOS,
} = require('../services/otp');
const {
  validarCorreoPorTipo,
  validarTipoVerificacion,
  extraerMatriculaDeCorreo,
  validarNombreNegocio,
  validarLinkRedSocial,
} = require('../validation/verificacion');
const { validateLocation } = require('../validation/sellerProfile');
const { validarCarrera } = require('../validation/carreras');
const {
  requisitosDeVerificacion,
  primerFaltante,
} = require('../validation/requisitosVerificacion');

// Envío de OTP: 3 solicitudes por ventana. Se cuenta por usuario Y por
// destino, para que N cuentas no puedan bombardear un correo/teléfono ajeno
// (cada SMS cuesta dinero, además de la molestia).
const MAX_ENVIOS = 3;
const VENTANA_ENVIO_MINUTOS = 15;

// Confirmación: sin este tope, un código de 6 dígitos con 10 minutos de vida
// es forzable por fuerza bruta. El límite de envío no protege contra eso.
const MAX_INTENTOS_CONFIRMACION = 5;

const ahora = () => new Date().toISOString();
const UPLOADS_DIR = path.join(__dirname, '..', '..', 'uploads');
const DOCUMENT_TYPES = new Set(['responsible_ine_front', 'responsible_ine_back', 'additional_evidence']);
fs.mkdirSync(UPLOADS_DIR, { recursive: true });
const documentUpload = multer({
  storage: multer.diskStorage({
    destination: (_req, _file, cb) => cb(null, UPLOADS_DIR),
    filename: (_req, file, cb) => cb(null, 'verification_' + Date.now() + '_' + Math.random().toString(36).slice(2, 10) + path.extname(file.originalname).toLowerCase()),
  }),
  limits: { fileSize: 15 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => cb(null, /\.(jpg|jpeg|png|webp|pdf)$/i.test(path.extname(file.originalname))),
});

/**
 * Rutas de verificación con sus dependencias inyectadas: así los tests pueden
 * correr contra una base temporal y sustituir los adaptadores de salida
 * (email, SMS, comprobación HTTP del link) sin mandar nada de verdad.
 */
function crearRutasVerificacion({
  getDb,
  mailer,
  sms,
  verificarLink,
  refrescarSellers,
}) {
  const router = express.Router();

  // ─── Acceso a datos ────────────────────────────────────────

  const obtenerSeller = id =>
    getDb().prepare('SELECT id, verified, tipo_cuenta FROM sellers WHERE id = ?').get(id);

  const obtenerVerificacion = usuarioId =>
    getDb().prepare('SELECT * FROM verificaciones WHERE usuario_id = ?').get(usuarioId);

  /** Crea la fila de verificación si aún no existe y la devuelve. */
  function asegurarVerificacion(usuarioId, tipoCuenta) {
    const existente = obtenerVerificacion(usuarioId);
    if (existente) return existente;
    getDb()
      .prepare(
        `INSERT INTO verificaciones (usuario_id, tipo_cuenta, estado, creado_en)
         VALUES (?, ?, 'pendiente', ?)`,
      )
      .run(usuarioId, tipoCuenta, ahora());
    return obtenerVerificacion(usuarioId);
  }

  /**
   * Marca la cuenta como verificada: fila de verificaciones + bandera rápida
   * en sellers, en una sola transacción. Después refresca la caché en memoria
   * de vendedores (`data.js` la mantiene como array), que si no seguiría
   * sirviendo `verified: false` hasta el próximo reinicio.
   */
  /**
   * @param camposSellers Columnas adicionales a copiar a `sellers` en la
   * misma transacción (p. ej. `carrera`), además de `verified`. Es el mismo
   * patrón que `verified`: una bandera rápida en `sellers` para no tener que
   * hacer join contra `verificaciones` solo para mostrar el dato en el perfil.
   */
  function marcarVerificado(usuarioId, camposExtra = {}, camposSellers = {}) {
    const columnas = Object.keys(camposExtra);
    const asignaciones = columnas.map(c => `${c} = @${c}`).join(', ');

    const columnasSellers = Object.keys(camposSellers);
    const asignacionesSellers = columnasSellers.map(c => `${c} = @${c}`).join(', ');

    getDb().transaction(() => {
      getDb()
        .prepare(
          `UPDATE verificaciones SET
             estado = 'verificado',
             fecha_verificacion = @fecha,
             motivo_rechazo = NULL,
             campo_rechazado = NULL,
             codigo_otp_email = NULL,
             codigo_otp_email_expira = NULL,
             codigo_otp_sms = NULL,
             codigo_otp_sms_expira = NULL,
             intentos_confirmacion = 0
             ${asignaciones ? ', ' + asignaciones : ''}
           WHERE usuario_id = @usuarioId`,
        )
        .run({ usuarioId, fecha: ahora(), ...camposExtra });
      getDb()
        .prepare(
          `UPDATE sellers SET verified = 1${asignacionesSellers ? ', ' + asignacionesSellers : ''} WHERE id = @usuarioId`,
        )
        .run({ usuarioId, ...camposSellers });
    })();

    refrescarSellers();
  }

  // ─── Guardas comunes ───────────────────────────────────────

  /**
   * Middleware: exige que el usuario exista, no esté ya verificado, y que su
   * tipo de cuenta corresponda al flujo del endpoint.
   */
  function exigirTipo(tipoEsperado) {
    return (req, res, next) => {
      const seller = obtenerSeller(req.user.id);
      if (!seller) {
        return res.status(404).json({ error: 'Cuenta no encontrada.' });
      }
      if (seller.verified) {
        // `ya_verificado` es la señal que el cliente usa para distinguir
        // este 409 (nada que corregir, solo refrescar y cerrar la pantalla)
        // de los 409 de "correo/teléfono ya registrado en otra cuenta" más
        // abajo en este archivo, que sí traen un error que el usuario debe
        // ver y corregir. Antes se distinguían solo por el status code, y
        // ambos casos comparten 409 — el cliente los confundía.
        return res.status(409).json({
          error: 'Tu cuenta ya está verificada.',
          ya_verificado: true,
        });
      }
      const tipo = seller.tipo_cuenta || 'particular';
      if (tipo !== tipoEsperado) {
        return res.status(403).json({
          error: 'Este método de verificación no corresponde a tu tipo de cuenta.',
        });
      }
      req.seller = seller;
      req.tipoCuenta = tipo;
      next();
    };
  }

  // ─── Rate limiting del envío de OTP ────────────────────────

  const minutosRestantes = inicioVentana =>
    Math.max(
      1,
      Math.ceil(
        (new Date(inicioVentana).getTime() +
          VENTANA_ENVIO_MINUTOS * 60 * 1000 -
          Date.now()) /
          60000,
      ),
    );

  /**
   * @returns {null|{ minutos: number }} null si puede enviar.
   */
  function limiteAlcanzado(verificacion, columnaDestino, destino) {
    const inicioVentanaValida = new Date(
      Date.now() - VENTANA_ENVIO_MINUTOS * 60 * 1000,
    ).toISOString();

    // Límite por usuario.
    if (
      verificacion.ventana_envio_inicio &&
      verificacion.ventana_envio_inicio > inicioVentanaValida &&
      verificacion.intentos_envio >= MAX_ENVIOS
    ) {
      return { minutos: minutosRestantes(verificacion.ventana_envio_inicio) };
    }

    // Límite por destino: suma los envíos que otras cuentas hicieron al mismo
    // correo/teléfono dentro de la ventana.
    const otras = getDb()
      .prepare(
        `SELECT intentos_envio, ventana_envio_inicio FROM verificaciones
         WHERE ${columnaDestino} = ? AND usuario_id != ?
           AND ventana_envio_inicio > ?`,
      )
      .all(destino, verificacion.usuario_id, inicioVentanaValida);

    for (const fila of otras) {
      if (fila.intentos_envio >= MAX_ENVIOS) {
        return { minutos: minutosRestantes(fila.ventana_envio_inicio) };
      }
    }
    return null;
  }

  /** Suma 1 al contador de envíos, reiniciando la ventana si ya venció. */
  function registrarEnvio(verificacion) {
    const ventanaVigente =
      verificacion.ventana_envio_inicio &&
      new Date(verificacion.ventana_envio_inicio).getTime() >
        Date.now() - VENTANA_ENVIO_MINUTOS * 60 * 1000;

    getDb()
      .prepare(
        `UPDATE verificaciones
         SET intentos_envio = ?, ventana_envio_inicio = ?
         WHERE usuario_id = ?`,
      )
      .run(
        ventanaVigente ? verificacion.intentos_envio + 1 : 1,
        ventanaVigente ? verificacion.ventana_envio_inicio : ahora(),
        verificacion.usuario_id,
      );
  }

  // ─── Flujo genérico de OTP (email y SMS comparten todo) ────

  /**
   * Genera, guarda y envía un código. Devuelve la respuesta HTTP ya resuelta.
   */
  async function solicitarOtp(res, {
    verificacion,
    destino,
    columnaDestino,
    columnaCodigo,
    columnaExpira,
    adaptador,
    camposExtra = {},
  }) {
    const limite = limiteAlcanzado(verificacion, columnaDestino, destino);
    if (limite) {
      return res.status(429).json({
        error: `Demasiados códigos solicitados. Intenta de nuevo en ${limite.minutos} minuto${limite.minutos === 1 ? '' : 's'}.`,
        puede_reintentar_en: limite.minutos,
      });
    }

    const codigo = generarCodigo();
    const expira = calcularExpiracion();

    let resultadoEnvio;
    try {
      resultadoEnvio = await adaptador.enviarCodigo(destino, codigo);
    } catch (err) {
      console.error(
        `[verificacion] Envío fallido (code=${err.code}): ${err.message}`,
      );
      return res.status(502).json({
        error: 'No pudimos enviar el código en este momento. Inténtalo de nuevo.',
      });
    }

    if (resultadoEnvio.modo === 'no_disponible') {
      return res.status(503).json({
        error: 'El envío de códigos no está disponible en este momento.',
      });
    }

    // El código solo se guarda si el envío no falló: si se guardara antes,
    // un fallo del proveedor dejaría al usuario con un código pendiente que
    // nunca recibió, consumiendo su cuota de reintentos.
    const columnas = Object.keys(camposExtra);
    getDb()
      .prepare(
        `UPDATE verificaciones SET
           ${columnaDestino} = @destino,
           ${columnaCodigo} = @codigo,
           ${columnaExpira} = @expira,
           intentos_confirmacion = 0,
           estado = 'pendiente',
           motivo_rechazo = NULL,
           campo_rechazado = NULL
           ${columnas.length ? ', ' + columnas.map(c => `${c} = @${c}`).join(', ') : ''}
         WHERE usuario_id = @usuarioId`,
      )
      .run({
        usuarioId: verificacion.usuario_id,
        destino,
        codigo: hashCodigo(codigo),
        expira,
        ...camposExtra,
      });

    registrarEnvio(verificacion);

    return res.json({
      enviado: true,
      expira_en_minutos: VIGENCIA_MINUTOS,
      // Solo en modo dev (sin proveedor configurado, fuera de producción):
      // permite probar el flujo completo sin recibir el correo/SMS.
      ...(resultadoEnvio.modo === 'dev' ? { codigo_dev: codigo } : {}),
    });
  }

  /**
   * Deja constancia de que la identidad quedó probada y consume el código.
   *
   * Se separa de `marcarVerificado` porque ya no son lo mismo: demostrar
   * quién eres es un paso, y completar la verificación exige además tener
   * dónde cobrar. Sin este registro, quien sale a conectar Mercado Pago
   * vuelve con el código expirado y tiene que pedir otro.
   */
  function marcarIdentidadConfirmada(usuarioId, columnaCodigo, columnaExpira) {
    getDb()
      .prepare(
        `UPDATE verificaciones SET
           identidad_confirmada_en = COALESCE(identidad_confirmada_en, @ahora),
           ${columnaCodigo} = NULL,
           ${columnaExpira} = NULL,
           intentos_confirmacion = 0
         WHERE usuario_id = @usuarioId`,
      )
      .run({ usuarioId, ahora: ahora() });
  }

  /**
   * Último paso común a los tres flujos: con la identidad ya probada, se
   * verifica si además hay cuenta de cobros conectada.
   *
   * Conectar Mercado Pago es requisito para TODOS los tipos de cuenta, no
   * solo para negocio: una cuenta verificada es una que puede cobrar dentro
   * de la app. No conectar no impide publicar ni vender por chat — solo deja
   * la verificación en 'pendiente'.
   */
  function completarSiPuedeCobrar(res, verificacion, camposSellers) {
    const falta = primerFaltante(verificacion.usuario_id);
    if (falta) {
      // `motivo_rechazo` y `campo_rechazado` se rellenan aunque el estado sea
      // 'pendiente' y no 'rechazado': son las columnas genéricas de "qué
      // falta por corregir", y es de donde la app lee el mensaje al refrescar
      // el estado de verificación.
      getDb()
        .prepare(
          `UPDATE verificaciones SET
             estado = 'pendiente',
             motivo_rechazo = @motivo,
             campo_rechazado = @campo
           WHERE usuario_id = @usuarioId`,
        )
        .run({
          usuarioId: verificacion.usuario_id,
          motivo: falta.detalle,
          campo: falta.id,
        });

      // 200 y no 4xx: la petición fue válida y se procesó; lo que se devuelve
      // es el estado del trámite, igual que en el flujo de negocio.
      //
      // Va la lista COMPLETA además del primer faltante: así la app pinta el
      // checklist entero sin una segunda llamada, y quien arregla una cosa ve
      // de una vez qué le queda en vez de descubrirlo de uno en uno.
      return res.json({
        verificado: false,
        estado: 'pendiente',
        campo: falta.id,
        motivo: falta.detalle,
        motivo_rechazo: falta.detalle,
        requisitos: requisitosDeVerificacion(verificacion.usuario_id),
        tipo_cuenta: verificacion.tipo_cuenta,
      });
    }

    marcarVerificado(verificacion.usuario_id, {}, camposSellers);
    return res.json({
      verificado: true,
      estado: 'verificado',
      tipo_cuenta: verificacion.tipo_cuenta,
    });
  }

  /** Valida el código recibido y marca verificado si corresponde. */
  function confirmarOtp(res, { verificacion, columnaCodigo, columnaExpira, camposSellers = {} }) {
    // Identidad ya probada en un intento anterior: lo único que pudo faltar
    // es la cuenta de cobros, así que se retoma ahí sin pedir otro código.
    // Es seguro porque este endpoint va detrás de `requireAuth` y la columna
    // solo se rellena tras un OTP válido DE ESTE MISMO usuario.
    if (verificacion.identidad_confirmada_en) {
      return completarSiPuedeCobrar(res, verificacion, camposSellers);
    }

    const resultado = verificarCodigo(
      typeof res.req.body.codigo_otp === 'string' ? res.req.body.codigo_otp.trim() : '',
      verificacion[columnaCodigo],
      verificacion[columnaExpira],
    );

    if (resultado.ok) {
      marcarIdentidadConfirmada(verificacion.usuario_id, columnaCodigo, columnaExpira);
      return completarSiPuedeCobrar(res, verificacion, camposSellers);
    }

    if (resultado.razon === 'sin_codigo') {
      return res.status(400).json({
        error: 'No hay un código pendiente. Solicita uno nuevo.',
        intentos_restantes: 0,
      });
    }
    if (resultado.razon === 'expirado') {
      getDb()
        .prepare(
          `UPDATE verificaciones SET ${columnaCodigo} = NULL, ${columnaExpira} = NULL
           WHERE usuario_id = ?`,
        )
        .run(verificacion.usuario_id);
      return res.status(400).json({
        error: 'El código expiró. Solicita uno nuevo.',
        intentos_restantes: 0,
      });
    }

    // Código incorrecto: se consume un intento y, al agotarlos, el código se
    // invalida para cortar la fuerza bruta.
    const intentos = (verificacion.intentos_confirmacion || 0) + 1;
    const agotados = intentos >= MAX_INTENTOS_CONFIRMACION;

    getDb()
      .prepare(
        `UPDATE verificaciones SET
           intentos_confirmacion = ?
           ${agotados ? `, ${columnaCodigo} = NULL, ${columnaExpira} = NULL` : ''}
         WHERE usuario_id = ?`,
      )
      .run(intentos, verificacion.usuario_id);

    return res.status(400).json({
      error: agotados
        ? 'Demasiados intentos fallidos. Solicita un código nuevo.'
        : 'El código no es correcto.',
      intentos_restantes: Math.max(0, MAX_INTENTOS_CONFIRMACION - intentos),
    });
  }

  // ═══ ESTUDIANTE ══════════════════════════════════════════

  router.post(
    '/estudiante/solicitar',
    requireAuth,
    exigirTipo('estudiante'),
    async (req, res) => {
      // Normalizar ANTES de validar: así 1220326@ALUMNO.UM.EDU.MX y el mismo
      // correo con espacios no crean filas distintas para la misma persona.
      const correo = String(req.body.correo_institucional ?? '').trim().toLowerCase();

      // El tipo lo declara el cliente EXPLÍCITAMENTE en vez de deducirse del
      // dominio: así el servidor puede contrastar una cosa contra la otra en
      // lugar de creerle al formato del correo.
      const tipo = String(req.body.tipo ?? '').trim();
      const errorTipo = validarTipoVerificacion(tipo);
      if (errorTipo) {
        return res.status(400).json({ error: errorTipo, campo: 'tipo' });
      }
      const esEmpleado = tipo === 'empleado';

      // La app ya valida el formato, pero un cliente puede llamar al endpoint
      // directamente: esta es la validación que cuenta. Se valida contra las
      // reglas del tipo DECLARADO, así que un correo de alumno enviado como
      // tipo='empleado' (o al revés) se rechaza en vez de colarse por el
      // flujo con menos requisitos.
      const errorCorreo = validarCorreoPorTipo(correo, tipo);
      if (errorCorreo) {
        return res.status(400).json({ error: errorCorreo, campo: 'correo_institucional' });
      }

      // Solo el alumno tiene matrícula, y no llega en el cuerpo: son los 7
      // dígitos del correo, extraídos con regex (nunca con substring, que
      // aceptaría cualquier cosa antes del arroba). El personal no tiene, así
      // que se guarda null.
      let matricula = null;
      if (!esEmpleado) {
        matricula = extraerMatriculaDeCorreo(correo);
        if (!matricula) {
          return res.status(400).json({
            error: 'Tu correo institucional debe empezar con tu matrícula de 7 dígitos',
            campo: 'correo_institucional',
          });
        }
      }

      // La carrera aplica solo al alumno. Para el personal se guarda null y
      // NO se valida: la app ni siquiera muestra el campo.
      let carrera = null;
      if (!esEmpleado) {
        // La app ya solo deja elegir de la lista fija, pero un cliente puede
        // llamar al endpoint directamente: esta es la validación que cuenta.
        carrera = String(req.body.carrera ?? '').trim();
        const errorCarrera = validarCarrera(carrera);
        if (errorCarrera) {
          return res.status(400).json({ error: errorCarrera, campo: 'carrera' });
        }
      }

      // Un correo institucional identifica a una persona: no puede respaldar
      // dos cuentas verificadas. Se comprueba también por matrícula, porque
      // una misma matrícula con dos dominios institucionales distintos sería
      // la misma persona con dos cuentas. Para el personal `matricula` es
      // null y esa mitad de la condición nunca casa (NULL = NULL no es
      // verdadero en SQL), así que solo cuenta el correo.
      const yaUsado = getDb()
        .prepare(
          `SELECT correo_institucional FROM verificaciones
           WHERE (correo_institucional = ? OR matricula = ?)
             AND estado = 'verificado' AND usuario_id != ?`,
        )
        .get(correo, matricula, req.user.id);
      if (yaUsado) {
        return res.status(409).json({
          error:
            yaUsado.correo_institucional === correo
              ? 'Ese correo institucional ya está registrado en otra cuenta.'
              : 'Esa matrícula ya está registrada en otra cuenta.',
          campo: 'correo_institucional',
        });
      }

      const verificacion = asegurarVerificacion(req.user.id, 'estudiante');
      return solicitarOtp(res, {
        verificacion,
        destino: correo,
        columnaDestino: 'correo_institucional',
        columnaCodigo: 'codigo_otp_email',
        columnaExpira: 'codigo_otp_email_expira',
        adaptador: mailer,
        // Se reescriben SIEMPRE los tres, también con null: si alguien pidió
        // primero un código como alumno y luego cambia a personal, la
        // matrícula y la carrera de aquel intento tienen que desaparecer.
        camposExtra: { matricula, carrera, tipo_verificacion: tipo },
      });
    },
  );

  router.post(
    '/estudiante/confirmar',
    requireAuth,
    exigirTipo('estudiante'),
    (req, res) => {
      const verificacion = asegurarVerificacion(req.user.id, 'estudiante');
      return confirmarOtp(res, {
        verificacion,
        columnaCodigo: 'codigo_otp_email',
        columnaExpira: 'codigo_otp_email_expira',
        // Copia a `sellers` lo capturado en la solicitud para que el perfil
        // lo muestre sin join contra `verificaciones`. La carrera va como
        // null para el personal, que es justo lo que hace que el perfil
        // muestre "Personal UM" en vez de una carrera.
        camposSellers: {
          carrera: verificacion.carrera ?? null,
          tipo_verificacion: verificacion.tipo_verificacion ?? null,
        },
      });
    },
  );

  // ═══ NEGOCIO ═════════════════════════════════════════════

  router.post('/negocio/documentos', requireAuth, exigirTipo('negocio'), (req, res) => {
    documentUpload.single('file')(req, res, error => {
      if (error) {
        return res.status(400).json({
          error: 'No pudimos subir el documento: ' + error.message,
        });
      }

      const descartarArchivo = () => {
        if (req.file?.path) fs.unlink(req.file.path, () => {});
      };
      const docType = String(req.body.doc_type || '');
      if (!DOCUMENT_TYPES.has(docType)) {
        descartarArchivo();
        return res.status(400).json({
          error: 'Tipo de documento inválido.',
          campo: 'doc_type',
        });
      }
      if (!req.file) {
        return res.status(400).json({
          error: 'Selecciona un archivo válido.',
          campo: 'file',
        });
      }
      if (
        docType !== 'additional_evidence'
        && path.extname(req.file.originalname).toLowerCase() === '.pdf'
      ) {
        descartarArchivo();
        return res.status(400).json({
          error: 'La INE debe enviarse como fotografía.',
          campo: 'file',
        });
      }

      const db = getDb();
      const contentHash = crypto
        .createHash('sha256')
        .update(fs.readFileSync(req.file.path))
        .digest('hex');
      const archivo = '/uploads/' + path.basename(req.file.path);

      if (docType === 'additional_evidence') {
        const existente = db.prepare(
          'SELECT file_url FROM verification_documents '
            + 'WHERE usuario_id = ? AND doc_type = ? AND content_hash = ? '
            + 'ORDER BY id DESC LIMIT 1',
        ).get(req.user.id, docType, contentHash);
        if (existente) {
          descartarArchivo();
          return res.status(200).json({
            doc_type: docType,
            file_url: existente.file_url,
            duplicate: true,
          });
        }
      } else {
        db.prepare(
          'DELETE FROM verification_documents '
            + 'WHERE usuario_id = ? AND doc_type = ?',
        ).run(req.user.id, docType);
      }

      db.prepare(
        'INSERT INTO verification_documents '
          + '(usuario_id, doc_type, file_url, original_name, mime_type, '
          + 'uploaded_at, content_hash) VALUES (?, ?, ?, ?, ?, ?, ?)',
      ).run(
        req.user.id,
        docType,
        archivo,
        path.basename(req.file.originalname),
        req.file.mimetype || 'application/octet-stream',
        ahora(),
        contentHash,
      );
      return res.status(201).json({ doc_type: docType, file_url: archivo });
    });
  });

  router.post('/negocio/solicitar-manual', requireAuth, exigirTipo('negocio'), (req, res) => {
    const db = getDb();
    const perfil = db.prepare(
      'SELECT name, businessCategory FROM sellers WHERE id = ?',
    ).get(req.user.id);
    const responsable = String(req.body.responsable_nombre || '').trim();
    const nombre = String(req.body.nombre_negocio || '').trim();
    const link = String(req.body.link_red_social || '').trim();
    const ubicacion = validateLocation(
      req.body.ubicacion_lat,
      req.body.ubicacion_lng,
    );

    const camposFaltantes = [];
    if (!responsable) camposFaltantes.push('responsable');
    if (!perfil?.name?.trim()) camposFaltantes.push('perfil_nombre_negocio');
    if (!perfil?.businessCategory?.trim()) camposFaltantes.push('categoria');
    if (camposFaltantes.length) {
      return res.status(400).json({
        error: 'Completa los campos obligatorios del perfil de negocio.',
        campo: camposFaltantes[0],
        campos_faltantes: camposFaltantes,
      });
    }

    const errorNombre = validarNombreNegocio(nombre);
    if (errorNombre) {
      return res.status(400).json({ error: errorNombre, campo: 'nombre_negocio' });
    }
    if (ubicacion.error || !ubicacion.value) {
      return res.status(400).json({
        error: ubicacion.error || 'Coloca la ubicación de tu negocio en el mapa.',
        campo: 'ubicacion',
      });
    }
    const errorLink = validarLinkRedSocial(link);
    if (errorLink) {
      return res.status(400).json({ error: errorLink, campo: 'link_red_social' });
    }

    const requisitoFaltante = primerFaltante(req.user.id);
    if (requisitoFaltante) {
      return res.status(400).json({
        error: requisitoFaltante.detalle,
        campo: requisitoFaltante.id,
      });
    }
    const documentos = db.prepare(
      'SELECT doc_type FROM verification_documents WHERE usuario_id = ?',
    ).all(req.user.id);
    const tipos = new Set(documentos.map(d => d.doc_type));
    const faltantes = ['responsible_ine_front', 'responsible_ine_back']
      .filter(tipo => !tipos.has(tipo));
    if (faltantes.length) {
      return res.status(400).json({
        error: 'Adjunta el frente y reverso de la INE del responsable.',
        campo: 'ine',
        documentos_faltantes: faltantes,
      });
    }

    asegurarVerificacion(req.user.id, 'negocio');
    db.prepare(
      `UPDATE verificaciones SET
         estado = 'pendiente',
         creado_en = ?,
         nombre_negocio = ?,
         responsable_negocio = ?,
         ubicacion_lat = ?,
         ubicacion_lng = ?,
         link_red_social = ?,
         motivo_rechazo = NULL,
         campo_rechazado = NULL
       WHERE usuario_id = ?`,
    ).run(
      ahora(),
      nombre,
      responsable,
      ubicacion.value.lat,
      ubicacion.value.lng,
      link,
      req.user.id,
    );
    return res.status(201).json({
      estado: 'pendiente',
      verificado: false,
      solicitud_manual_pendiente: true,
    });
  });

  // El endpoint histórico se conserva para clientes antiguos.


  router.post(
    '/negocio/solicitar',
    requireAuth,
    exigirTipo('negocio'),
    async (req, res) => {
      const nombre = String(req.body.nombre_negocio ?? '').trim();
      const link = String(req.body.link_red_social ?? '').trim();

      const errorNombre = validarNombreNegocio(nombre);
      if (errorNombre) {
        return res.status(400).json({ error: errorNombre, campo: 'nombre_negocio' });
      }

      const ubicacion = validateLocation(req.body.ubicacion_lat, req.body.ubicacion_lng);
      if (ubicacion.error || !ubicacion.value) {
        return res.status(400).json({
          error: ubicacion.error || 'Coloca el pin de ubicación de tu negocio',
          campo: 'ubicacion',
        });
      }

      const errorLink = validarLinkRedSocial(link);
      if (errorLink) {
        return res.status(400).json({ error: errorLink, campo: 'link_red_social' });
      }

      const verificacion = asegurarVerificacion(req.user.id, 'negocio');
      const datos = {
        nombre_negocio: nombre,
        ubicacion_lat: ubicacion.value.lat,
        ubicacion_lng: ubicacion.value.lng,
        link_red_social: link,
      };

      // Última comprobación, y la única que toca la red: que el link exista.
      // Deliberadamente tolerante — ver services/linkCheck.js.
      const resultadoLink = await verificarLink(link);
      if (!resultadoLink.ok) {
        getDb()
          .prepare(
            `UPDATE verificaciones SET
               estado = 'rechazado',
               motivo_rechazo = @motivo,
               campo_rechazado = 'link_red_social',
               nombre_negocio = @nombre_negocio,
               ubicacion_lat = @ubicacion_lat,
               ubicacion_lng = @ubicacion_lng,
               link_red_social = @link_red_social
             WHERE usuario_id = @usuarioId`,
          )
          .run({ usuarioId: req.user.id, motivo: resultadoLink.motivo, ...datos });

        // 200 y no 4xx: la petición fue válida y se procesó; el resultado del
        // trámite es el rechazo, que la app muestra como estado, no como error.
        return res.json({
          estado: 'rechazado',
          motivo_rechazo: resultadoLink.motivo,
          campo: 'link_red_social',
        });
      }

      // El link comprobado es la prueba de identidad del negocio, el
      // equivalente al OTP de los otros dos flujos. Se registra ANTES de
      // mirar la cuenta de cobros, y junto con los datos del negocio, por dos
      // razones: al volver de conectar Mercado Pago no hay que teclearlo todo
      // otra vez, y `identidad_confirmada_en` es justo lo que autoriza a
      // conectarla estando aún sin verificar (ver `puedeVender`).
      getDb()
        .prepare(
          `UPDATE verificaciones SET
             identidad_confirmada_en = COALESCE(identidad_confirmada_en, @ahora),
             nombre_negocio = @nombre_negocio,
             ubicacion_lat = @ubicacion_lat,
             ubicacion_lng = @ubicacion_lng,
             link_red_social = @link_red_social
           WHERE usuario_id = @usuarioId`,
        )
        .run({ usuarioId: req.user.id, ahora: ahora(), ...datos });

      return completarSiPuedeCobrar(res, verificacion, {});
    },
  );

  // ═══ EXTERNO (particular) ════════════════════════════════

  // Las cuentas externas pueden usar el marketplace y publicar, pero la
  // insignia de verificación queda reservada para estudiantes y negocios.
  // Estas rutas se conservan para devolver una respuesta explícita a clientes
  // antiguos en vez de dejar una vía de verificación por compatibilidad.
  const externoNoVerificable = (_req, res) =>
    res.status(403).json({
      error: 'Las cuentas externas no pueden verificarse.',
    });

  router.post('/externo/solicitar', requireAuth, externoNoVerificable);
  router.post('/externo/confirmar', requireAuth, externoNoVerificable);

  // ═══ ESTADO ══════════════════════════════════════════════

  // Único endpoint que no bloquea si la cuenta ya está verificada: lo consulta
  // tanto el registro como el perfil para saber qué mostrar.
  router.get('/estado', requireAuth, (req, res) => {
    const seller = obtenerSeller(req.user.id);
    if (!seller) return res.status(404).json({ error: 'Cuenta no encontrada.' });

    const verificacion = obtenerVerificacion(req.user.id);
    const tipoCuenta = seller.tipo_cuenta || 'particular';

    let puedeReintentar = 0;
    if (
      verificacion &&
      verificacion.ventana_envio_inicio &&
      verificacion.intentos_envio >= MAX_ENVIOS
    ) {
      const restantes = minutosRestantes(verificacion.ventana_envio_inicio);
      const ventanaVigente =
        new Date(verificacion.ventana_envio_inicio).getTime() >
        Date.now() - VENTANA_ENVIO_MINUTOS * 60 * 1000;
      puedeReintentar = ventanaVigente ? restantes : 0;
    }

    res.json({
      tipo_cuenta: tipoCuenta,
      estado: seller.verified ? 'verificado' : verificacion?.estado || 'pendiente',
      verificado: !!seller.verified,
      // `estado='pendiente'` también es el valor por defecto antes de iniciar
      // un trámite. Esta bandera distingue una solicitud manual realmente
      // enviada para que Flutter muestre la pantalla "En revisión".
      solicitud_manual_pendiente: Boolean(
        !seller.verified
          && verificacion?.tipo_cuenta === 'negocio'
          && verificacion?.estado === 'pendiente'
          && verificacion?.responsable_negocio,
      ),
      motivo_rechazo: verificacion?.motivo_rechazo || null,
      campo_rechazado: verificacion?.campo_rechazado || null,
      // La identidad ya está probada y lo único que puede faltar es conectar
      // la cuenta de cobros. La app lo usa para retomar en ese paso en vez de
      // volver a mandar un código que no hace falta.
      identidad_confirmada: Boolean(verificacion?.identidad_confirmada_en),
      // El checklist que la app pinta ANTES del botón de verificar. Se sirve
      // siempre, también para quien ya está verificado: es lo que le permite
      // ver que sigue cumpliendo (o que dejó de cumplir al desconectar su
      // cuenta, por ejemplo) sin tener que intentar y fallar.
      requisitos: requisitosDeVerificacion(req.user.id),
      puede_reintentar_en: puedeReintentar,
    });
  });

  return router;
}

/**
 * Cierra una verificación que estaba esperando ÚNICAMENTE a que se conectara
 * la cuenta de cobros. La llama el callback de OAuth en cuanto la conexión
 * queda guardada.
 *
 * Existe porque conectar Mercado Pago no se hace solo desde el formulario de
 * verificación: también desde "Editar perfil" y desde la pantalla de cobros.
 * Si el cierre viviera únicamente en el reintento del formulario, quien
 * conectara desde cualquier otro sitio se quedaría en 'pendiente' para
 * siempre sin ninguna pista de qué le falta — no le falta nada.
 *
 * Es deliberadamente estricta: solo toca filas cuya identidad YA está probada
 * y cuyo único pendiente anotado es 'mercadopago'. Una verificación rechazada
 * por el link, o una que nunca confirmó su OTP, no se cierra por conectar una
 * cuenta de pagos.
 *
 * @returns {boolean} true si esta llamada la dejó verificada.
 */
function completarVerificacionPendientePorPagos(usuarioId) {
  const db = require('../database');
  const { sellers } = require('../data');
  const { cumpleTodos } = require('../validation/requisitosVerificacion');
  const conexionDb = db.getDb();

  const fila = conexionDb
    .prepare('SELECT * FROM verificaciones WHERE usuario_id = ?')
    .get(usuarioId);
  if (!fila) return false;
  if (fila.estado === 'verificado') return false;
  // Old external verification attempts can never be completed by payments.
  if (fila.tipo_cuenta === 'particular') return false;
  if (!fila.identidad_confirmada_en) return false;
  if (fila.campo_rechazado !== 'mercadopago') return false;

  // La lista COMPLETA, no solo la cuenta de cobros. Conectar Mercado Pago
  // puede no ser lo único que faltaba —quizá tampoco tiene horario— y
  // verificar aquí saltándose el resto abriría una puerta trasera a todos
  // los demás requisitos.
  if (!cumpleTodos(usuarioId)) return false;

  conexionDb.transaction(() => {
    conexionDb
      .prepare(
        `UPDATE verificaciones SET
           estado = 'verificado',
           fecha_verificacion = @fecha,
           motivo_rechazo = NULL,
           campo_rechazado = NULL
         WHERE usuario_id = @usuarioId`,
      )
      .run({ usuarioId, fecha: ahora() });

    // Las mismas banderas rápidas que copia `marcarVerificado`: el perfil las
    // lee de `sellers` sin join contra `verificaciones`.
    conexionDb
      .prepare(
        `UPDATE sellers SET verified = 1, carrera = @carrera, tipo_verificacion = @tipo
         WHERE id = @usuarioId`,
      )
      .run({
        usuarioId,
        carrera: fila.carrera ?? null,
        tipo: fila.tipo_verificacion ?? null,
      });
  })();

  // data.js sirve los vendedores desde un array en memoria: sin esto seguiría
  // diciendo `verified: false` hasta el siguiente reinicio.
  db.refrescarCuentasDueno();
  sellers.length = 0;
  sellers.push(...db.getSellers());

  console.log(`[verificacion] ${usuarioId} quedó verificado al conectar su cuenta de cobros`);
  return true;
}

/**
 * Reconciliación de arranque: cierra toda verificación que quedó 'pendiente'
 * ÚNICAMENTE por falta de conectar Mercado Pago.
 *
 * Existe por MERCADO_PAGO_HABILITADO=false (ver payments/config.js): las
 * cuentas que quedaron atoradas en `campo_rechazado = 'mercadopago'` antes de
 * apagar el flag no tenían forma de resolverlo por su cuenta —la app ya no
 * ofrece conectar nada— así que sin esto se quedarían en ese estado para
 * siempre. Se ejecuta al arrancar el servidor (ver index.js) y es idempotente:
 * una fila ya verificada, o una que de verdad sigue esperando otra cosa
 * (según [cumpleTodos]), no se toca.
 *
 * Reutiliza [completarVerificacionPendientePorPagos], que ya solo verifica
 * cuando TODOS los requisitos —no solo el de pagos— están cumplidos, así que
 * esto no abre una puerta trasera a otros requisitos pendientes ni depende de
 * si el flag está prendido o apagado: si algún día se reactiva Mercado Pago
 * con cuentas todavía sin conectar, esta misma función simplemente no las
 * toca.
 */
function reconciliarVerificacionesPendientesPorMercadoPago() {
  const db = require('../database');
  const filas = db.getDb()
    .prepare(
      `SELECT usuario_id FROM verificaciones
       WHERE estado != 'verificado' AND campo_rechazado = 'mercadopago'`,
    )
    .all();

  let resueltas = 0;
  for (const { usuario_id: usuarioId } of filas) {
    if (completarVerificacionPendientePorPagos(usuarioId)) resueltas += 1;
  }
  if (resueltas > 0) {
    console.log(`[verificacion] ${resueltas} cuenta(s) desatoradas de 'pendiente por mercadopago' al arrancar`);
  }
  return resueltas;
}

/** Montaje real, con los adaptadores de producción. */
function register(app) {
  const db = require('../database');
  const { sellers } = require('../data');
  const mailer = require('../services/mailer');
  const sms = require('../services/sms');
  const { verificarLink } = require('../services/linkCheck');

  app.use(
    '/api/verificacion',
    crearRutasVerificacion({
      getDb: () => db.getDb(),
      mailer,
      sms,
      verificarLink,
      // data.js mantiene los vendedores en un array en memoria que las demás
      // rutas leen directamente; sin este refresco seguirían sirviendo
      // `verified: false` hasta el siguiente reinicio del servidor.
      refrescarSellers: () => {
        // ANTES de releer los vendedores: `rowToSeller` consulta el conjunto
        // de cuentas del dueño, y si una acaba de verificarse con su correo
        // institucional el conjunto que hay en caché todavía no la incluye.
        db.refrescarCuentasDueno();
        sellers.length = 0;
        sellers.push(...db.getSellers());
      },
    }),
  );
}

module.exports = {
  register,
  crearRutasVerificacion,
  completarVerificacionPendientePorPagos,
  reconciliarVerificacionesPendientesPorMercadoPago,
};
