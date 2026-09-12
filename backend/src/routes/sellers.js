const path = require('path');
const fs = require('fs');
const crypto = require('crypto');
const sharp = require('sharp');
const multer = require('multer');
const {
  sellers,
  categories,
  updateSellerField
} = require('../data');
const {
  requireAuth,
  optionalAuth
} = require('../auth');
const {
  presenciaDe
} = require('./presenciaHttp');
const {
  guestPublicProfile
} = require('../guestProfile');
const db = require('../database');
const {
  validateName,
  validatePhone,
  validateBusinessDescription,
  validateBusinessCategory,
  validateBusinessHours,
  validateLocation,
  validatePaymentMethods,
  validateColorAcento,
  validateSocialUrl,
  validateWhatsappNumber
} = require('../validation/sellerProfile');
const {
  validarMetodosPermitidos
} = require('../payments/methods');
const {
  validateInsigniasOcultas,
  aplicarInsigniasOcultas,
  insigniasGanadas,
  estaEnPrimeraSemana,
  diasDesde
} = require('../validation/insignias');
const UPLOADS_DIR = path.join(__dirname, '..', '..', 'uploads');
const upload = multer({
  storage: multer.diskStorage({
    destination: (_req, _file, cb) => cb(null, UPLOADS_DIR),
    filename: (_req, file, cb) => {
      const ext = path.extname(file.originalname) || '.png';
      cb(null, `logo_${Date.now()}_${crypto.randomBytes(12).toString('hex')}${ext}`);
    }
  }),
  limits: {
    fileSize: 5 * 1024 * 1024
  },
  fileFilter: (_req, file, cb) => {
    cb(null, /\.(jpg|jpeg|png|gif|webp)$/i.test(path.extname(file.originalname)));
  }
});
function profileViewerKey(req) {
  if (req.user?.id) {
    return `${req.user.anon ? 'anon' : 'user'}:${req.user.id}`;
  }
  const forwarded = String(req.headers['x-forwarded-for'] || '').split(',')[0].trim();
  const ip = forwarded || req.ip || req.socket?.remoteAddress || 'unknown';
  const ua = String(req.headers['user-agent'] || '').slice(0, 180);
  return `net:${crypto.createHash('sha256').update(`${ip}|${ua}`).digest('hex')}`;
}
function register(app) {
  app.get('/api/sellers', async (_req, res) => {
    const visibility = await Promise.all(sellers.map(async seller => await db.isSellerPubliclyActive(seller.id)));
    res.json(sellers.filter((_seller, index) => visibility[index]));
  });

  // Cuentas oficiales a las que "Reportar un problema" abre chat. Público
  // como el resto de `rowToSeller` (mismos campos que ya se ven en un perfil
  // o en la bandeja), sin requerir sesión: alguien sin cuenta también debe
  // poder ver a quién le escribiría antes de decidir si inicia sesión.
  app.get('/api/support/contacts', async (_req, res) => {
    res.json({
      contacts: await db.getCuentasSoporte()
    });
  });

  // El email es privado: solo se incluye en la respuesta si quien pide el
  // perfil es el propio dueño (Bearer token cuyo sub coincide con :id).
  // El resto de campos, incluido phone, ya son públicos vía rowToSeller.
  // Métricas que se calculan al vuelo en vez de cachearse en la fila: la
  // racha cambia sola con el paso del tiempo (una semana sin publicar la
  // rompe sin que nadie escriba nada), así que un caché estaría mintiendo
  // hasta el siguiente evento que lo refrescara.
  async function conMetricas(seller) {
    const w = db.FEED_WEIGHTS;
    const ventasConfirmadas = await db.countVentasConfirmadas(seller.id);
    // `created_at` se guarda como 'YYYY-MM-DD HH:MM:SS' (UTC, sin 'Z') —
    // mismo formato que el resto de columnas datetime('now') del esquema.
    // `new Date` no lo interpreta como UTC sin el separador 'T' y el
    // sufijo 'Z' explícitos.
    const diasDesdeAlta = diasDesde(seller.createdAt);
    const otorgamientoVerificacion = await db.getDb().prepare(
      `SELECT otorgada_en FROM insignias_otorgadas
        WHERE seller_id = ? AND clave = 'recien_verificado'`,
    ).get(seller.id);
    // Cuenta propia del admin: todas las insignias de esta pantalla quedan
    // desbloqueadas siempre, sin depender de métricas reales que puedan
    // subir y bajar (racha, tiempo de respuesta, etc.) — ver
    // `esCuentaTodosLosBadges` para el mismo trato en `verified`/
    // `socioFundador`, que se resuelve en `rowToSeller` porque esos dos se
    // usan fuera de este endpoint también (tarjetas, comentarios...).
    const todosLosBadges = db.esUsuarioTodosLosBadges(seller.id);
    // Métricas de las insignias élite. Se leen una vez aquí y no dentro del
    // objeto para no disparar la consulta dos veces si una insignia futura
    // necesita el mismo dato.
    const montoFacturado = await db.sumarVentasConfirmadas(seller.id);
    const calificaciones = await db.getEstadisticasCalificaciones(seller.id);
    const preguntas = await db.getEstadisticasPreguntasVendedor(seller.id);
    // Las tres insignias de acumulado de por vida no se recalculan desde
    // cero: se cumplen por la regla de hoy O ya están registradas de antes.
    // Ver INSIGNIAS_PERMANENTES — subir un umbral no puede quitarle a nadie
    // algo que ya se ganó con el umbral anterior.
    const otorgadas = await db.getInsigniasOtorgadas(seller.id);
    async function permanente(clave, cumpleLaRegla) {
      // Se registra solo cuando la gana por la regla, y solo la primera vez.
      // Las cuentas del dueño (`todosLosBadges`) quedan fuera a propósito:
      // las llevan todas por excepción, no por haberlas ganado, y guardarlas
      // ensuciaría el registro con concesiones que nadie cumplió.
      if (cumpleLaRegla && !otorgadas.has(clave)) {
        await db.registrarInsigniaOtorgada(seller.id, clave);
      }
      return todosLosBadges || cumpleLaRegla || otorgadas.has(clave);
    }
    return {
      ...seller,
      // Actividad publica del vendedor: una sola agregacion SQL sobre todos
      // sus productos conservados, sin limitarla a lo que hoy esta publicado.
      productViews: await db.getSellerProductViews(seller.id),
      rachaSemanas: todosLosBadges ? Math.max(2, await db.computeRachaPublicaciones(seller.id)) : await db.computeRachaPublicaciones(seller.id),
      // Posición en el enigma escondido, o null si no lo ha resuelto. Es lo
      // ÚNICO que el mundo secreto asoma a una respuesta pública, y a
      // propósito no dice nada de cómo se consigue: un número suelto en el
      // perfil de quien lo tiene, que es justo lo que hace que el resto
      // pregunte. Ver secreto/enigma.js.
      enigmaPosicion: ((await db.getResolucionEnigma(seller.id)) || {}).posicion ?? null,
      respondeRapido: todosLosBadges || seller.medianResponseMinutes !== null && seller.medianResponseMinutes <= w.FAST_REPLY_MAX_MINUTES,
      // Nivel superior de "responde rápido": mediana bajo un umbral bastante
      // más estricto. No reemplaza a `respondeRapido` en la respuesta — el
      // cliente decide cuál mostrar (ver InsigniaCuenta para el mismo patrón
      // con verificado/socio fundador) porque esta implica la otra.
      respuestaInstantanea: todosLosBadges || seller.medianResponseMinutes !== null && seller.medianResponseMinutes <= w.INSTANT_REPLY_MAX_MINUTES,
      // Insignias temporales de bienvenida. La primera nace con el alta; la
      // segunda usa el otorgamiento idempotente que se registra al verificar,
      // de modo que una revocación y restauración no reinicie sus siete días.
      recienRegistrado: todosLosBadges || estaEnPrimeraSemana(seller.createdAt),
      recienVerificado: todosLosBadges || seller.verified && estaEnPrimeraSemana(otorgamientoVerificacion?.otorgada_en),
      // "Vendedor confiable": rating alto sostenido por un mínimo de
      // reseñas. Sin el mínimo, un solo comentario de 5 estrellas bastaría
      // para la insignia, que es justo el ruido que el umbral de reseñas
      // busca evitar.
      vendedorConfiable: todosLosBadges || seller.rating >= w.TOP_RATED_MIN_RATING && seller.reviews >= w.TOP_RATED_MIN_REVIEWS,
      // "Novato": insignia de bienvenida, no de mérito permanente — por eso
      // depende de la antigüedad de la cuenta y no solo de la venta. Sin el
      // límite de días se quedaría pegada para siempre en cuanto se hiciera
      // la primera venta, y dejaría de leerse como "nuevo por aquí".
      esVendedorNuevo: todosLosBadges || diasDesdeAlta !== null && diasDesdeAlta <= w.NOVATO_MAX_DIAS && ventasConfirmadas >= 1,
      // Años completos desde el alta. 0 significa "todavía no cumple un
      // año": el call site decide no pintar nada en ese caso, así que el
      // valor crudo (y no un booleano) es lo que necesita.
      aniversarioAnios: todosLosBadges ? Math.max(1, diasDesdeAlta !== null ? Math.floor(diasDesdeAlta / 365) : 0) : diasDesdeAlta !== null ? Math.floor(diasDesdeAlta / 365) : 0,
      // ─── Insignias élite ──────────────────────────────────────
      // Todas siguen el mismo patrón que las de arriba: `todosLosBadges ||
      // <regla>`, para que las cuentas del dueño las lleven siempre. Los
      // umbrales viven en FEED_WEIGHTS, no aquí, por la misma razón que los
      // pesos del feed: ajustarlos no debe implicar leer esta función.

      // "Leyenda del Mercadito": volumen de ventas de por vida. No caduca ni
      // se rompe con el tiempo, a diferencia de la racha: es historial
      // acumulado, y esa permanencia es justo lo que la hace valiosa.
      leyendaMercadito: await permanente('leyenda', ventasConfirmadas >= w.LEYENDA_MIN_VENTAS),
      // "Vendedor de oro": dinero facturado. Va aparte de la anterior porque
      // mide otra cosa — cien ventas de $50 no son lo mismo que veinte de
      // $5,000, y ninguna de las dos debería tapar a la otra.
      vendedorDeOro: await permanente('vendedor_de_oro', montoFacturado >= w.ORO_MIN_FACTURADO),
      // "Impecable": promedio perfecto de verdad (cada reseña un cinco) con
      // un piso alto de reseñas. Se compara contra el conteo crudo y no
      // contra `seller.rating`, que está redondeado a un decimal y diría 5.0
      // con un cuatro de por medio.
      ratingPerfecto: todosLosBadges || calificaciones.total >= w.IMPECABLE_MIN_RESENAS && calificaciones.cincos === calificaciones.total,
      // "Centenario": cien calificaciones de cinco estrellas, sin exigir que
      // TODAS lo sean. Premia el volumen de gente contenta; "Impecable"
      // premia no haber fallado nunca.
      cienCincoEstrellas: await permanente('centenario', calificaciones.cincos >= w.CENTENARIO_MIN_CINCOS),
      // "Siempre responde": tasa de preguntas contestadas, con un mínimo de
      // preguntas para que la proporción signifique algo — sin ese piso,
      // 1 de 1 sería el 100%. Es distinta de "Responde rápido", que mide
      // velocidad en el chat: aquí lo que se mide es no dejar a nadie sin
      // respuesta.
      siempreResponde: todosLosBadges || preguntas.total >= w.SIEMPRE_RESPONDE_MIN_PREGUNTAS && preguntas.respondidas / preguntas.total >= w.SIEMPRE_RESPONDE_MIN_TASA,
      // El producto fijado se verifica al leer: si se borró o ya no es del
      // vendedor, se devuelve null en vez de un ID colgante que el cliente
      // tendría que resolver a una tarjeta vacía.
      productoFijadoId: await productoFijadoVigente(seller)
    };
  }
  async function productoFijadoVigente(seller) {
    if (!seller.productoFijadoId) return null;
    const row = await db.getDb().prepare('SELECT seller FROM products WHERE id = ?').get(seller.productoFijadoId);
    return row && row.seller === seller.id ? seller.productoFijadoId : null;
  }

  /**
   * El perfil tal como se publica: con las insignias que su dueño decidió
   * ocultar ya apagadas.
   *
   * El filtro corre en el servidor y no en el cliente porque un booleano en
   * true en la respuesta ya es la información que se quería esconder. Y se
   * aplica también cuando quien mira es el propio dueño, para que su perfil
   * se vea exactamente como lo ve el resto; lo que necesita para editar el
   * ajuste viaja aparte, en `insigniasGanadas`.
   */
  async function perfilPublico(seller, metricas) {
    if (metricas === undefined) metricas = await conMetricas(seller);
    const filtradas = aplicarInsigniasOcultas(metricas, seller.insigniasOcultas);
    // La lista de ocultas es privada: saber QUÉ escondió alguien es
    // exactamente lo que se quería no enseñar. Solo se le devuelve a su
    // dueño, junto al resto de campos privados del perfil.
    delete filtradas.insigniasOcultas;
    return filtradas;
  }
  app.get('/api/sellers/:id', optionalAuth, async (req, res) => {
    const seller = sellers.find(s => s.id === req.params.id);
    if (!seller) {
      const guest = guestPublicProfile(req.params.id);
      if (guest) {
        return res.json({
          ...guest,
          ...(await presenciaDe(req, req.user ? req.user.id : null, guest.id))
        });
      }
      return res.status(404).json({
        error: 'Vendedor no encontrado'
      });
    }
    if (!(await db.isSellerPubliclyActive(seller.id))) {
      return res.status(404).json({
        error: 'Vendedor no encontrado'
      });
    }
    // Es una métrica del PERFIL, no de sus publicaciones. Solo una visita
    // ajena cuenta: al dueño se le devuelve el total sin aumentarlo cuando
    // abre su propio perfil o su pantalla de configuración.
    if (!req.user || req.user.id !== seller.id) {
      await db.recordSellerProfileView(seller.id, profileViewerKey(req));
      // El acumulado se guarda directamente en SQLite. Ya no forma parte del
      // objeto publico cacheado: solo se devuelve al propio dueño y al admin.
    }
    // Un visitante sin sesión no tiene "visor", así que nunca ve presencia:
    // si no, bastaría con cerrar sesión para saltarse la reciprocidad del
    // ajuste de privacidad.
    const presencia = await presenciaDe(req, req.user ? req.user.id : null, seller.id);
    if (req.user && req.user.id === seller.id) {
      const metricas = await conMetricas(seller);
      const rawRow = await db.getDb().prepare('SELECT email, profile_views FROM sellers WHERE id = ?').get(seller.id);
      return res.json({
        ...(await perfilPublico(seller, metricas)),
        ...presencia,
        email: rawRow.email || null,
        profileViews: rawRow.profile_views ?? 0,
        // Privado, como el email: qué insignias tiene realmente, ocultas
        // incluidas. Es lo único con lo que la pantalla de selección puede
        // saber qué switches ofrecer encendibles.
        insigniasGanadas: insigniasGanadas(metricas),
        insigniasOcultas: seller.insigniasOcultas
      });
    }
    res.json({
      ...(await perfilPublico(seller)),
      ...presencia
    });
  });

  // PATCH /api/sellers/:id — editar el propio perfil (usuario o negocio).
  // Campos de usuario: name, phone. Campos exclusivos de negocio
  // (businessDescription, businessCategory): solo se aplican si isBusiness.
  app.patch('/api/sellers/:id', requireAuth, async (req, res) => {
    if (req.user.id !== req.params.id) {
      return res.status(403).json({
        error: 'No autorizado'
      });
    }
    const seller = sellers.find(s => s.id === req.params.id);
    if (!seller) return res.status(404).json({
      error: 'Vendedor no encontrado'
    });
    const {
      name,
      phone,
      businessDescription,
      businessCategory,
      businessHours,
      locationLat,
      locationLng,
      paymentMethods,
      colorAcento,
      productoFijadoId,
      insigniasOcultas,
      facebookUrl,
      instagramUrl,
      whatsappNumber,
      tiktokUrl,
      twitterUrl
    } = req.body;

    // ─── Validar todo antes de escribir nada (evita estado a medias) ──
    if (name !== undefined) {
      const nameError = validateName(name);
      if (nameError) return res.status(400).json({
        error: nameError
      });
    }
    const phoneError = validatePhone(phone);
    if (phoneError) return res.status(400).json({
      error: phoneError
    });

    // Métodos de pago: a diferencia de horario/descripción/ubicación, esto
    // aplica a CUALQUIER vendedor (negocio o no) — no está gated por
    // isBusiness. Si se manda, debe quedar al menos 1 (no se permite vaciar
    // por completo desde edición de perfil).
    let normalizedPaymentMethods;
    if (paymentMethods !== undefined) {
      const paymentMethodsResult = validatePaymentMethods(paymentMethods, {
        required: true
      });
      if (paymentMethodsResult.error) return res.status(400).json({
        error: paymentMethodsResult.error
      });

      // 'tarjeta' además exige cuenta de pagos conectada. Sin esto un
      // vendedor podría anunciar que acepta tarjeta y dejar al comprador
      // frente a un método que va a fallar al cobrar.
      const permitidos = await validarMetodosPermitidos(req.params.id, paymentMethodsResult.value);
      if (permitidos.error) return res.status(400).json({
        error: permitidos.error
      });
      normalizedPaymentMethods = paymentMethodsResult.value;
    }

    // Personalización del perfil. A diferencia de descripción/horario, NO
    // está restringida a negocios: cualquier vendedor puede elegir su color
    // y fijar una publicación.
    const colorError = validateColorAcento(colorAcento);
    if (colorError) return res.status(400).json({
      error: colorError
    });

    // Qué insignias mostrar. No comprueba que las claves mandadas sean
    // insignias que la cuenta ya tenga: ocultar una que todavía no se ha
    // ganado es legítimo —queda lista para cuando llegue— y exigir lo
    // contrario obligaría a recalcular todas las métricas en cada PATCH.
    let normalizedInsigniasOcultas;
    if (insigniasOcultas !== undefined) {
      const resultado = validateInsigniasOcultas(insigniasOcultas);
      if (resultado.error) return res.status(400).json({
        error: resultado.error
      });
      normalizedInsigniasOcultas = resultado.value;
    }

    // Fijar exige ser dueño del producto. Sin esta comprobación, cualquiera
    // podría fijar la publicación de otro en su propio perfil y presentarla
    // como suya.
    if (productoFijadoId !== undefined && productoFijadoId !== null) {
      if (typeof productoFijadoId !== 'string') {
        return res.status(400).json({
          error: 'productoFijadoId inválido'
        });
      }
      const producto = await db.getDb().prepare('SELECT seller FROM products WHERE id = ?').get(productoFijadoId);
      if (!producto) {
        return res.status(400).json({
          error: 'La publicación no existe'
        });
      }
      if (producto.seller !== seller.id) {
        return res.status(403).json({
          error: 'Esa publicación no es tuya'
        });
      }
    }
    let normalizedHours;
    let normalizedLocation;
    let normalizedFacebook, normalizedInstagram, normalizedTiktok, normalizedTwitter, normalizedWhatsapp;
    // La ubicación de perfil (Nivel 1) es exclusiva de negocios, igual que
    // horario/descripción/categoría: un usuario normal no puede guardarla
    // mandando estos campos manualmente al endpoint.
    if (seller.isBusiness) {
      const descriptionError = validateBusinessDescription(businessDescription);
      if (descriptionError) return res.status(400).json({
        error: descriptionError
      });
      const categoryIds = categories.map(c => c.id);
      const categoryError = validateBusinessCategory(businessCategory, categoryIds);
      if (categoryError) return res.status(400).json({
        error: categoryError
      });
      if (businessHours !== undefined) {
        const hoursResult = validateBusinessHours(businessHours);
        if (hoursResult.error) return res.status(400).json({
          error: hoursResult.error
        });
        normalizedHours = hoursResult.value;
      }
      if (locationLat !== undefined || locationLng !== undefined) {
        const locationResult = validateLocation(locationLat, locationLng);
        if (locationResult.error) return res.status(400).json({
          error: locationResult.error
        });
        normalizedLocation = locationResult.value; // { lat, lng } o null (borra la ubicación)
      }
      if (facebookUrl !== undefined) {
        const r = validateSocialUrl('facebook', facebookUrl);
        if (r.error) return res.status(400).json({
          error: r.error
        });
        normalizedFacebook = r.value;
      }
      if (instagramUrl !== undefined) {
        const r = validateSocialUrl('instagram', instagramUrl);
        if (r.error) return res.status(400).json({
          error: r.error
        });
        normalizedInstagram = r.value;
      }
      if (tiktokUrl !== undefined) {
        const r = validateSocialUrl('tiktok', tiktokUrl);
        if (r.error) return res.status(400).json({
          error: r.error
        });
        normalizedTiktok = r.value;
      }
      if (twitterUrl !== undefined) {
        const r = validateSocialUrl('twitter', twitterUrl);
        if (r.error) return res.status(400).json({
          error: r.error
        });
        normalizedTwitter = r.value;
      }
      if (whatsappNumber !== undefined) {
        const r = validateWhatsappNumber(whatsappNumber);
        if (r.error) return res.status(400).json({
          error: r.error
        });
        normalizedWhatsapp = r.value;
      }
    }

    // ─── Aplicar cambios ────────────────────────────────────────────
    if (name !== undefined) {
      const trimmedName = name.trim();
      await updateSellerField(seller.id, 'name', trimmedName);
      const initials = trimmedName.split(/\s+/).map(w => w[0]).slice(0, 2).join('').toUpperCase();
      await updateSellerField(seller.id, 'avatarInitials', initials);
    }
    if (phone !== undefined) {
      await updateSellerField(seller.id, 'phone', phone.trim());
    }
    if (normalizedPaymentMethods !== undefined) {
      await updateSellerField(seller.id, 'paymentMethods', JSON.stringify(normalizedPaymentMethods));
    }
    if (colorAcento !== undefined) {
      // null limpia el campo y devuelve el perfil al color de marca.
      await updateSellerField(seller.id, 'colorAcento', colorAcento);
    }
    if (productoFijadoId !== undefined) {
      await updateSellerField(seller.id, 'producto_fijado_id', productoFijadoId);
    }
    if (normalizedInsigniasOcultas !== undefined) {
      await updateSellerField(seller.id, 'insignias_ocultas', JSON.stringify(normalizedInsigniasOcultas));
    }
    if (seller.isBusiness) {
      if (businessDescription !== undefined) {
        await updateSellerField(seller.id, 'businessDescription', businessDescription.trim());
      }
      if (businessCategory !== undefined) {
        await updateSellerField(seller.id, 'businessCategory', businessCategory);
      }
      if (normalizedHours !== undefined) {
        await updateSellerField(seller.id, 'businessHours', JSON.stringify(normalizedHours));
      }
      if (normalizedLocation !== undefined) {
        await updateSellerField(seller.id, 'location_lat', normalizedLocation ? normalizedLocation.lat : null);
        await updateSellerField(seller.id, 'location_lng', normalizedLocation ? normalizedLocation.lng : null);
      }
      if (normalizedFacebook !== undefined) {
        await updateSellerField(seller.id, 'facebook_url', normalizedFacebook);
      }
      if (normalizedInstagram !== undefined) {
        await updateSellerField(seller.id, 'instagram_url', normalizedInstagram);
      }
      if (normalizedTiktok !== undefined) {
        await updateSellerField(seller.id, 'tiktok_url', normalizedTiktok);
      }
      if (normalizedTwitter !== undefined) {
        await updateSellerField(seller.id, 'twitter_url', normalizedTwitter);
      }
      if (normalizedWhatsapp !== undefined) {
        await updateSellerField(seller.id, 'whatsapp_number', normalizedWhatsapp);
      }
    }
    const updated = sellers.find(s => s.id === req.params.id);
    const rawRow = await db.getDb().prepare('SELECT phone, email FROM sellers WHERE id = ?').get(req.params.id);
    res.json({
      ...(await conMetricas(updated)),
      phone: rawRow.phone || null,
      email: rawRow.email || null
    });
  });

  // Borra un archivo de /uploads referenciado por una URL pública tipo
  // "/uploads/xxx.webp", sin lanzar si ya no existe (best-effort).
  function deleteUploadedFile(publicUrl) {
    if (!publicUrl || !publicUrl.startsWith('/uploads/')) return;
    const filePath = path.join(UPLOADS_DIR, path.basename(publicUrl));
    fs.unlink(filePath, err => {
      if (err && err.code !== 'ENOENT') {
        console.error('Error eliminando archivo huérfano:', filePath, err.message);
      }
    });
  }

  // POST /api/sellers/:id/logo – subir logo del negocio (multipart, dueño-only)
  app.post('/api/sellers/:id/logo', requireAuth, (req, res) => {
    if (req.user.id !== req.params.id) {
      return res.status(403).json({
        error: 'No autorizado'
      });
    }
    const seller = sellers.find(s => s.id === req.params.id);
    if (!seller) return res.status(404).json({
      error: 'Vendedor no encontrado'
    });
    upload.single('logo')(req, res, err => {
      if (err) {
        return res.status(400).json({
          error: 'Error al subir logo: ' + err.message
        });
      }
      if (!req.file) {
        return res.status(400).json({
          error: 'No se envió ningún archivo'
        });
      }
      const previousLogoUrl = seller.logoUrl;

      // Convertir a WebP
      const parsed = path.parse(req.file.path);
      const webpPath = path.join(parsed.dir, parsed.name + '.webp');
      const publicUrl = '/uploads/' + parsed.name + '.webp';
      sharp(req.file.path).resize(256, 256, {
        fit: 'cover'
      }).webp({
        quality: 80
      }).toFile(webpPath).then(async () => {
        fs.unlinkSync(req.file.path);
        await updateSellerField(seller.id, 'logoUrl', publicUrl);
        deleteUploadedFile(previousLogoUrl);
        res.json(sellers.find(s => s.id === seller.id));
      }).catch(convErr => {
        console.error('Error convirtiendo logo a WebP:', convErr);
        fs.unlink(req.file.path, () => {});
        res.status(400).json({
          error: 'El archivo no es una imagen válida.'
        });
      });
    });
  });
}
module.exports = {
  register
};
