import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'utils/estado_conexion.dart';

/// Convierte una fecha ISO en un texto relativo corto ("Hace 5 min").
/// Usado por publicaciones que no traen un `publishedAgo` ya calculado
/// por el backend (p. ej. "se busca").
String relativeTimeFromIso(String iso) {
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return '';
  final diff = DateTime.now().difference(parsed);
  if (diff.inMinutes < 1) return 'time.now'.tr();
  if (diff.inHours < 1) {
    return 'time.minutes_ago'.tr(namedArgs: {'n': '${diff.inMinutes}'});
  }
  if (diff.inDays < 1) {
    return 'time.hours_ago'.tr(namedArgs: {'n': '${diff.inHours}'});
  }
  if (diff.inDays < 7) {
    return 'time.days_ago'.tr(namedArgs: {'n': '${diff.inDays}'});
  }
  return 'time.weeks_ago'.tr(namedArgs: {'n': '${(diff.inDays / 7).floor()}'});
}

/// Map from icon name strings (from backend) to Flutter [IconData].
IconData _parseIcon(String icon) {
  const map = <String, IconData>{
    'menu_book': Icons.menu_book_rounded,
    'article': Icons.article_rounded,
    'devices': Icons.devices_rounded,
    'checkroom': Icons.checkroom_rounded,
    'construction': Icons.construction_rounded,
    'restaurant': Icons.restaurant_rounded,
    'bed': Icons.bed_rounded,
    'category': Icons.category_rounded,
    'laptop_mac': Icons.laptop_mac_rounded,
    'functions': Icons.functions_rounded,
    'kitchen': Icons.kitchen_rounded,
    'tablet_mac': Icons.tablet_mac_rounded,
    'music_note': Icons.music_note_rounded,
    'headphones': Icons.headphones_rounded,
    'calculate': Icons.calculate_rounded,
    'chair_alt': Icons.chair_alt_rounded,
    'slideshow': Icons.slideshow_rounded,
    'local_hospital': Icons.local_hospital_rounded,
    'architecture': Icons.architecture_rounded,
    'desktop_windows': Icons.desktop_windows_rounded,
    'table_restaurant': Icons.table_restaurant_rounded,
    'print': Icons.print_rounded,
    'backpack': Icons.backpack_rounded,
    'local_drink': Icons.local_drink_rounded,
    'psychology': Icons.psychology_rounded,
    'coffee_maker': Icons.coffee_maker_rounded,
    'library_music': Icons.library_music_rounded,
    'router': Icons.router_rounded,
    'ramen_dining': Icons.ramen_dining_rounded,
    'lunch_dining': Icons.lunch_dining_rounded,
    'takeout_dining': Icons.takeout_dining_rounded,
    'fastfood': Icons.fastfood_rounded,
    'dinner_dining': Icons.dinner_dining_rounded,
    'dining': Icons.dining_rounded,
    'set_meal': Icons.set_meal_rounded,
    'bedroom_parent': Icons.bedroom_parent_rounded,
    'apartment': Icons.apartment_rounded,
    'home_work': Icons.home_work_rounded,
    'weekend': Icons.weekend_rounded,
    'pedal_bike': Icons.pedal_bike_rounded,
    'auto_stories': Icons.auto_stories_rounded,
    'light': Icons.light_rounded,
    'directions_run': Icons.directions_run_rounded,
    'fact_check': Icons.fact_check_rounded,
    'inventory_2': Icons.inventory_2_rounded,
    'storefront': Icons.storefront_rounded,
    'local_offer': Icons.local_offer_rounded,
    'star': Icons.star_rounded,
    'search': Icons.search_rounded,
    'tune': Icons.tune_rounded,
    'place': Icons.place_rounded,
    'sell': Icons.sell_rounded,
    'apps': Icons.apps_rounded,
    'sort': Icons.sort_rounded,
  };
  return map[icon] ?? Icons.category_rounded;
}

Color _parseColor(String hex) {
  hex = hex.replaceFirst('#', '');
  if (hex.length == 6) hex = 'FF$hex';
  return Color(int.parse(hex, radix: 16));
}

class MarketplaceCategory {
  const MarketplaceCategory({
    required this.id,
    required this.name,
    required this.emoji,
    required this.icon,
    required this.color,
  });

  factory MarketplaceCategory.fromJson(Map<String, dynamic> json) {
    return MarketplaceCategory(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      emoji: json['emoji'] as String? ?? '',
      icon: _parseIcon(json['icon'] as String? ?? 'category'),
      color: _parseColor(json['color'] as String? ?? '#607D8B'),
    );
  }

  final String id;
  final String name;
  final String emoji;
  final IconData icon;
  final Color color;
}

/// Horario de apertura/cierre de un negocio para un día específico.
class BusinessHoursRange {
  const BusinessHoursRange({required this.open, required this.close});

  factory BusinessHoursRange.fromJson(Map<String, dynamic> json) {
    return BusinessHoursRange(
      open: json['open'] as String,
      close: json['close'] as String,
    );
  }

  /// Hora de apertura en formato 'HH:mm'.
  final String open;

  /// Hora de cierre en formato 'HH:mm'.
  final String close;

  Map<String, String> toJson() => {'open': open, 'close': close};
}

/// Parsea el objeto de horarios del negocio: keyed por día
/// ('0'=Lunes .. '6'=Domingo), un día ausente significa "cerrado" ese día.
Map<int, BusinessHoursRange> businessHoursFromJson(dynamic json) {
  if (json is! Map) return {};
  final result = <int, BusinessHoursRange>{};
  for (final entry in json.entries) {
    final day = int.tryParse(entry.key.toString());
    if (day == null || entry.value is! Map) continue;
    result[day] = BusinessHoursRange.fromJson(
      Map<String, dynamic>.from(entry.value as Map),
    );
  }
  return result;
}

Map<String, dynamic> businessHoursToJson(Map<int, BusinessHoursRange> hours) {
  return hours.map((day, range) => MapEntry(day.toString(), range.toJson()));
}

class Seller {
  const Seller({
    this.id = '',
    required this.name,
    required this.avatarInitials,
    required this.major,
    this.isBusiness = false,
    this.isGuest = false,
    this.logoUrl,
    this.phone,
    required this.rating,
    required this.reviews,
    this.profileViews = 0,
    required this.verified,
    this.socioFundador = false,
    this.tipoCuenta = 'particular',
    this.businessDescription,
    this.businessCategory,
    this.businessHours = const {},
    this.locationLat,
    this.locationLng,
    this.paymentMethods = const [],
    this.carrera,
    this.tipoVerificacion,
    this.colorAcento,
    this.productoFijadoId,
    this.estadoConexion = EstadoConexion.desconocido,
    this.respondeRapido = false,
    this.respuestaInstantanea = false,
    this.vendedorConfiable = false,
    this.esVendedorNuevo = false,
    this.leyendaMercadito = false,
    this.vendedorDeOro = false,
    this.ratingPerfecto = false,
    this.cienCincoEstrellas = false,
    this.siempreResponde = false,
    this.aniversarioAnios = 0,
    this.rachaSemanas = 0,
    this.enigmaPosicion,
    this.insigniasOcultas = const <String>{},
    this.insigniasGanadas = const <String, bool>{},
    this.facebookUrl,
    this.instagramUrl,
    this.whatsappNumber,
    this.tiktokUrl,
    this.twitterUrl,
  });

  factory Seller.fromJson(Map<String, dynamic> json) {
    return Seller(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      avatarInitials: json['avatarInitials'] as String? ?? '',
      major: json['major'] as String? ?? '',
      isBusiness: json['isBusiness'] as bool? ?? false,
      isGuest: json['isGuest'] as bool? ?? false,
      logoUrl: json['logoUrl'] as String?,
      phone: json['phone'] as String?,
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      reviews: (json['reviews'] as num?)?.toInt() ?? 0,
      profileViews: (json['profileViews'] as num?)?.toInt() ?? 0,
      verified: json['verified'] as bool? ?? false,
      socioFundador: json['socioFundador'] as bool? ?? false,
      // Backends viejos no mandan tipoCuenta: 'particular' es el tipo menos
      // privilegiado, así que es el default seguro.
      tipoCuenta: json['tipoCuenta'] as String? ?? 'particular',
      businessDescription: json['businessDescription'] as String?,
      businessCategory: json['businessCategory'] as String?,
      businessHours: businessHoursFromJson(json['businessHours']),
      locationLat: (json['locationLat'] as num?)?.toDouble(),
      locationLng: (json['locationLng'] as num?)?.toDouble(),
      paymentMethods:
          (json['paymentMethods'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      carrera: json['carrera'] as String?,
      tipoVerificacion: json['tipoVerificacion'] as String?,
      colorAcento: json['colorAcento'] as String?,
      productoFijadoId: json['productoFijadoId'] as String?,
      estadoConexion: EstadoConexion.desdeJson(json),
      // Ambas solo llegan en el detalle del vendedor, no en el listado: los
      // defaults dejan que un Seller construido desde una respuesta parcial
      // simplemente no muestre los badges, en vez de reventar.
      respondeRapido: json['respondeRapido'] as bool? ?? false,
      respuestaInstantanea: json['respuestaInstantanea'] as bool? ?? false,
      vendedorConfiable: json['vendedorConfiable'] as bool? ?? false,
      esVendedorNuevo: json['esVendedorNuevo'] as bool? ?? false,
      leyendaMercadito: json['leyendaMercadito'] as bool? ?? false,
      vendedorDeOro: json['vendedorDeOro'] as bool? ?? false,
      ratingPerfecto: json['ratingPerfecto'] as bool? ?? false,
      cienCincoEstrellas: json['cienCincoEstrellas'] as bool? ?? false,
      siempreResponde: json['siempreResponde'] as bool? ?? false,
      aniversarioAnios: (json['aniversarioAnios'] as num?)?.toInt() ?? 0,
      rachaSemanas: (json['rachaSemanas'] as num?)?.toInt() ?? 0,
      enigmaPosicion: (json['enigmaPosicion'] as num?)?.toInt(),
      insigniasOcultas: {
        ...?(json['insigniasOcultas'] as List<dynamic>?)?.map(
          (c) => c as String,
        ),
      },
      insigniasGanadas: {
        ...?(json['insigniasGanadas'] as Map<String, dynamic>?)?.map(
          (clave, valor) => MapEntry(clave, valor as bool),
        ),
      },
      facebookUrl: json['facebookUrl'] as String?,
      instagramUrl: json['instagramUrl'] as String?,
      whatsappNumber: json['whatsappNumber'] as String?,
      tiktokUrl: json['tiktokUrl'] as String?,
      twitterUrl: json['twitterUrl'] as String?,
    );
  }

  final String id;
  final String name;
  final String avatarInitials;
  final String major;
  final bool isBusiness;
  final bool isGuest;
  final String? logoUrl;
  final String? phone;
  final double rating;
  final int reviews;

  /// Visitas al perfil, separadas de las vistas de publicaciones.
  final int profileViews;
  final bool verified;

  /// Insignia verde otorgada a mano por el admin. No la gana ningún dato de
  /// la cuenta ni ningún trámite — a diferencia de [verified], que sí. Ver
  /// [InsigniaSocioFundador] en widgets/badges.dart.
  final bool socioFundador;

  /// Carrera elegida al verificar como estudiante (lista fija, ver
  /// `constants/carreras_um.dart`). Null si no es estudiante o si se
  /// verificó antes de que existiera este campo — el perfil cae a
  /// "Estudiante" en ese caso.
  final String? carrera;

  /// 'estudiante' | 'empleado': alumno o personal de la universidad. Ambos
  /// comparten [tipoCuenta] 'estudiante' y se distinguen por el dominio de
  /// correo con el que se verificaron.
  final String? tipoVerificacion;

  /// Link de Facebook del negocio. Solo tiene valor cuando [isBusiness].
  final String? facebookUrl;

  /// Link de Instagram del negocio. Solo tiene valor cuando [isBusiness].
  final String? instagramUrl;

  /// Número de WhatsApp del negocio: dígitos con código de país, sin '+' ni
  /// espacios (ej. "5215512345678"). El link se arma como
  /// https://wa.me/<whatsappNumber>. Solo tiene valor cuando [isBusiness].
  final String? whatsappNumber;

  /// Link de TikTok del negocio. Solo tiene valor cuando [isBusiness].
  final String? tiktokUrl;

  /// Link de X/Twitter del negocio. Solo tiene valor cuando [isBusiness].
  final String? twitterUrl;

  /// 'estudiante' | 'negocio' | 'particular'. Determina el color y la
  /// etiqueta de [InsigniaVerificada]. 'particular' es lo que la UI llama
  /// cuenta "externa".
  final String tipoCuenta;
  final String? businessDescription;
  final String? businessCategory;
  final Map<int, BusinessHoursRange> businessHours;
  final double? locationLat;
  final double? locationLng;
  final List<String> paymentMethods;

  /// ID del swatch de acento elegido (ver [AccentSwatch]). Null = color de
  /// marca. Se guarda el ID y no un hex porque cada swatch son cuatro
  /// colores coordinados, no uno.
  final String? colorAcento;

  /// Publicación que el vendedor fijó arriba de su perfil. El backend ya
  /// verifica que siga existiendo y siendo suya, así que un ID no nulo aquí
  /// es siempre resoluble.
  final String? productoFijadoId;

  /// Presencia que traía la respuesta. Es la SEMILLA de la primera pintura;
  /// lo que se muestra sale de PresenceService, que además recibe los
  /// cambios en vivo por socket.
  final EstadoConexion estadoConexion;

  /// La MEDIANA de su tiempo de respuesta está por debajo del umbral del
  /// sistema. Lo decide el backend para que la app no tenga que conocer el
  /// umbral ni recibir los tiempos crudos de nadie.
  final bool respondeRapido;

  /// Igual que [respondeRapido] pero con un umbral bastante más estricto.
  /// Cuando es true, [respondeRapido] también lo es — el backend calcula
  /// ambas del mismo dato, solo cambia el umbral.
  final bool respuestaInstantanea;

  /// Rating alto sostenido por un mínimo de reseñas, calculado por el
  /// backend. Ver [InsigniaVendedorConfiable] en widgets/badges.dart.
  final bool vendedorConfiable;

  /// Insignia de bienvenida: cuenta creada hace poco que ya tiene su primera
  /// venta confirmada. A diferencia del resto de insignias, no es
  /// permanente — deja de mostrarse cuando la cuenta envejece, aunque las
  /// ventas se mantengan.
  final bool esVendedorNuevo;

  // ── Insignias élite ────────────────────────────────────────────
  // Las cinco las calcula el backend en `conMetricas` (routes/sellers.js) a
  // partir de historial acumulado, con umbrales altos a propósito. Llegan
  // solo en el detalle del vendedor, como el resto: el default en false hace
  // que un Seller armado desde una respuesta parcial simplemente no las
  // pinte.

  /// 50 o más ventas confirmadas de por vida.
  final bool leyendaMercadito;

  /// $100,000 MXN o más facturados en órdenes pagadas.
  final bool vendedorDeOro;

  /// Promedio perfecto (cada reseña un cinco) con al menos 50 reseñas.
  /// Cuando es true, [vendedorConfiable] también lo es.
  final bool ratingPerfecto;

  /// 100 o más calificaciones de cinco estrellas, aunque haya otras más
  /// bajas de por medio. Mide volumen; [ratingPerfecto] mide no fallar.
  final bool cienCincoEstrellas;

  /// Respondió al menos el 95% de las preguntas recibidas, con un mínimo de
  /// 20 preguntas. Es constancia, no velocidad: eso lo mide
  /// [respondeRapido].
  final bool siempreResponde;

  /// Años completos desde el alta de la cuenta. 0 = todavía no cumple un
  /// año, así que no hay nada que mostrar.
  final int aniversarioAnios;

  /// Ventanas consecutivas de 7 días en las que publicó algo. Solo cuenta
  /// publicar: vender no la mueve.
  final int rachaSemanas;

  /// Posición con la que resolvió el enigma escondido (1 = fue el primero de
  /// toda la app), o null si no lo ha resuelto.
  ///
  /// Es la única huella pública de algo que por lo demás no se anuncia en
  /// ninguna parte: la insignia aparece en el perfil sin explicar de dónde
  /// salió. Ver [InsigniaEnigma] y backend/src/secreto/enigma.js.
  final int? enigmaPosicion;

  /// Claves de las insignias que su dueño decidió no mostrar en el perfil.
  ///
  /// No hace falta consultarla para pintar: el backend ya manda apagados los
  /// campos correspondientes, así que un perfil ajeno se dibuja igual que
  /// siempre. Sirve para la pantalla que edita el ajuste.
  final Set<String> insigniasOcultas;

  /// Qué insignias tiene REALMENTE la cuenta, ocultas incluidas, por clave.
  ///
  /// Solo llega en el perfil propio (es privado, como el email): en
  /// cualquier otro caso es un mapa vacío. Sin esto, la pantalla de
  /// selección no podría distinguir "la escondí" de "no la tengo", porque
  /// las dos llegan apagadas en el perfil.
  final Map<String, bool> insigniasGanadas;

  /// Atajo para los call sites que solo preguntan si lleva la insignia.
  bool get resolvioElEnigma => enigmaPosicion != null;

  bool get hasLocation => locationLat != null && locationLng != null;

  /// null = no configuró horario, así que no hay nada que decidir;
  /// true/false = abierto/cerrado en este momento según [businessHours] y la
  /// hora local del dispositivo.
  ///
  /// Ya no se filtra por `isBusiness`: el horario es requisito de
  /// verificación para todos los tipos de cuenta, porque un estudiante que
  /// vende comida también cierra.
  ///
  /// Esto es solo para PINTAR. La decisión de aceptar o rechazar un cobro
  /// fuera de horario la toma el servidor (`validation/horarioNegocio.js`):
  /// la hora del dispositivo la cambia quien lo usa.
  bool? get isOpenNow {
    if (businessHours.isEmpty) return null;
    final now = DateTime.now();
    final day =
        now.weekday - 1; // DateTime: 1=Lunes..7=Domingo → 0=Lunes..6=Domingo
    final range = businessHours[day];
    if (range == null) return false;
    final openParts = range.open.split(':');
    final closeParts = range.close.split(':');
    final openMinutes = int.parse(openParts[0]) * 60 + int.parse(openParts[1]);
    final closeMinutes =
        int.parse(closeParts[0]) * 60 + int.parse(closeParts[1]);
    final nowMinutes = now.hour * 60 + now.minute;
    return nowMinutes >= openMinutes && nowMinutes < closeMinutes;
  }
}

// TODO: Destacar publicaciones pendiente para próxima actualización - no
// eliminar `featured`: el backend sigue pudiendo devolver ese estado y
// `Product.isFeatured` para publicaciones ya destacadas. Lo que está apagado
// es su presentación (ver features/highlight/destacar_flag.dart).
enum ListingStatus { active, featured, expired }

extension ListingStatusCopy on ListingStatus {
  String get label {
    switch (this) {
      case ListingStatus.active:
        return 'Activa';
      case ListingStatus.featured:
        return 'Destacada';
      case ListingStatus.expired:
        return 'Expirada';
    }
  }
}

/// Estado manual "pegajoso" que el dueño activa explícitamente y que
/// sobreescribe el cálculo automático hasta que lo reactive (vuelva a
/// `null`) o borre la publicación. 'Disponible'/'No disponible' NO son
/// valores de este enum — esos son resultados de [ComputedStatus], nunca
/// una elección manual (ver [Product.computedStatus]).
enum ManualStatus {
  reserved,
  sold,
  negotiating,
  paused;

  String get label {
    switch (this) {
      case ManualStatus.reserved:
        return 'status.reserved'.tr();
      case ManualStatus.sold:
        return 'status.sold'.tr();
      case ManualStatus.negotiating:
        return 'status.negotiating'.tr();
      case ManualStatus.paused:
        return 'status.paused'.tr();
    }
  }

  /// Valor tal como lo espera/devuelve el backend (`manual_status`).
  String get apiValue => name;

  static ManualStatus? fromString(String? value) {
    if (value == null) return null;
    for (final status in ManualStatus.values) {
      if (status.name == value) return status;
    }
    return null;
  }
}

/// Badge de disponibilidad calculado por el backend (`computed_status`) a
/// partir de [ManualStatus] + inventario + días disponibles + horario del
/// negocio — nunca se elige a mano, ver `computeProductStatus` en
/// `backend/src/routes/products.js` para la jerarquía completa.
enum ComputedStatus {
  available,
  soldOut,
  availableOtherDay,
  closed,
  reserved,
  sold,
  negotiating,
  paused;

  static ComputedStatus fromString(String? value) {
    switch (value) {
      case 'sold_out':
        return ComputedStatus.soldOut;
      case 'available_other_day':
        return ComputedStatus.availableOtherDay;
      case 'closed':
        return ComputedStatus.closed;
      case 'reserved':
        return ComputedStatus.reserved;
      case 'sold':
        return ComputedStatus.sold;
      case 'negotiating':
        return ComputedStatus.negotiating;
      case 'paused':
        return ComputedStatus.paused;
      case 'available':
      default:
        return ComputedStatus.available;
    }
  }
}

class Product {
  const Product({
    required this.id,
    required this.title,
    required this.price,
    required this.category,
    required this.description,
    required this.publishedAgo,
    required this.seller,
    this.images = const [],
    required this.imageIcon,
    required this.imageColor,
    this.previousPrice,
    this.discountLabel,
    this.isFeatured = false,
    this.isOffer = false,
    this.isFavorite = false,
    this.status,
    this.manualStatus,
    this.computedStatus = ComputedStatus.available,
    this.nextAvailableDay,
    this.opensAt,
    this.stockQuantity,
    this.stockResetDaily = false,
    this.stockInitial,
    this.isAvailable = true,
    this.extras = const [],
    this.availableDays = const [],
    this.productRating = 0.0,
    this.productReviews = 0,
    this.userRating,
    this.postType = 'producto',
    this.priceMin,
    this.priceMax,
    this.wantedStatus,
    this.wantedKind,
    this.locationLat,
    this.locationLng,
    this.paymentMethods,
    this.views = 0,
    this.atributos = const {},
    this.atributosDestacados = const [],
  });

  /// Adapta un [WantedPost] a la forma de [Product] para que
  /// [ProductDetailScreen] pueda mostrar ambos tipos de publicación con la
  /// misma pantalla. Los campos exclusivos de producto (precio fijo, stock,
  /// extras, imágenes, rating) quedan en su valor "vacío" y la pantalla los
  /// oculta según [postType] en vez de mostrarlos vacíos o con error.
  factory Product.fromWantedPost(WantedPost post) {
    final category =
        post.categoryObj ??
        const MarketplaceCategory(
          id: 'other',
          name: 'Otros',
          emoji: '\u{1F4E6}',
          icon: Icons.category_rounded,
          color: Color(0xFF607D8B),
        );
    final seller =
        post.sellerObj ??
        Seller(
          id: post.userId,
          name: post.userId,
          avatarInitials: '??',
          major: '',
          rating: 0,
          reviews: 0,
          verified: false,
        );
    return Product(
      id: post.id,
      title: post.title,
      price: 0,
      category: category,
      description: post.description ?? '',
      publishedAgo: relativeTimeFromIso(post.createdAt),
      seller: seller,
      imageIcon: category.icon,
      imageColor: category.color,
      isAvailable: !post.isResolved,
      postType: 'se_busca',
      priceMin: post.priceMin,
      priceMax: post.priceMax,
      wantedStatus: post.status,
      wantedKind: post.type,
      locationLat: post.locationLat,
      locationLng: post.locationLng,
      paymentMethods: post.paymentMethods,
      views: post.views,
    );
  }

  /// Formatea un precio numérico a string con símbolo de moneda.
  /// Ej: 250.0 → "\$250", 1500.0 → "\$1,500"
  static String formatPrice(double price) {
    final whole = price.floor();
    final cents = ((price - whole) * 100).round();
    final formatted = whole.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (match) => '${match.group(1)},',
    );
    if (cents > 0) {
      return '\$${formatted}.${cents.toString().padLeft(2, '0')}';
    }
    return '\$$formatted';
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    Seller parseSeller() {
      if (json['sellerObj'] != null) {
        return Seller.fromJson(json['sellerObj'] as Map<String, dynamic>);
      }
      return Seller(
        id: json['seller'] as String? ?? '',
        name: 'search.seller'.tr(),
        avatarInitials: '??',
        major: '',
        rating: 0,
        reviews: 0,
        verified: false,
      );
    }

    MarketplaceCategory parseCategory() {
      if (json['categoryObj'] != null) {
        return MarketplaceCategory.fromJson(
          json['categoryObj'] as Map<String, dynamic>,
        );
      }
      return MarketplaceCategory(
        id: json['category'] as String? ?? 'other',
        name: 'Otros',
        emoji: '\u{1F4E6}',
        icon: Icons.category_rounded,
        color: const Color(0xFF607D8B),
      );
    }

    ListingStatus? parseStatus() {
      final statusValue = json['status'] as String?;
      if (statusValue == null) return null;
      switch (statusValue) {
        case 'active':
          return ListingStatus.active;
        case 'featured':
          return ListingStatus.featured;
        case 'expired':
          return ListingStatus.expired;
        default:
          return null;
      }
    }

    // Parsear imágenes reales
    final List<String> parsedImages = [];
    if (json['images'] != null) {
      final raw = json['images'];
      if (raw is List) {
        for (final item in raw) {
          if (item is String) parsedImages.add(item);
        }
      }
    }

    // Price viene del API como número; si por algún motivo es string, lo parseamos
    final dynamic rawPrice = json['price'];
    final double priceVal;
    if (rawPrice is num) {
      priceVal = rawPrice.toDouble();
    } else if (rawPrice is String) {
      priceVal =
          double.tryParse(rawPrice.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
    } else {
      priceVal = 0.0;
    }

    final dynamic rawPrev = json['previousPrice'];
    final double? prevVal;
    if (rawPrev is num) {
      prevVal = rawPrev.toDouble();
    } else if (rawPrev is String) {
      prevVal =
          double.tryParse(rawPrev.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
    } else {
      prevVal = null;
    }

    /// Respuestas a las preguntas dinámicas. Las listas se normalizan a
    /// `List<String>` aquí y no en cada lector: sin esto, un `List<dynamic>`
    /// del decodificador de JSON revienta con un cast en la pantalla que lo
    /// consuma, que es donde peor se diagnostica.
    Map<String, dynamic> parseAtributos() {
      final raw = json['atributos'];
      if (raw is! Map) return const {};
      return {
        for (final entry in raw.entries)
          entry.key.toString(): entry.value is List
              ? (entry.value as List).map((e) => e.toString()).toList()
              : entry.value,
      };
    }

    List<AtributoDestacado> parseAtributosDestacados() {
      final raw = json['atributosDestacados'];
      if (raw is! List) return const [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(AtributoDestacado.fromJson)
          .toList(growable: false);
    }

    List<ProductExtra> parseExtras() {
      if (json['extras'] != null && json['extras'] is List) {
        return (json['extras'] as List)
            .map((e) => ProductExtra.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    }

    return Product(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      price: priceVal,
      category: parseCategory(),
      description: json['description'] as String? ?? '',
      publishedAgo: json['publishedAgo'] as String? ?? '',
      seller: parseSeller(),
      images: parsedImages,
      imageIcon: _parseIcon(json['imageIcon'] as String? ?? 'inventory_2'),
      imageColor: _parseColor(json['imageColor'] as String? ?? '#607D8B'),
      previousPrice: prevVal,
      discountLabel: json['discountLabel'] as String?,
      isFeatured: json['isFeatured'] as bool? ?? false,
      isOffer: json['isOffer'] as bool? ?? false,
      isFavorite: json['isFavorite'] as bool? ?? false,
      status: parseStatus(),
      manualStatus: ManualStatus.fromString(json['manual_status'] as String?),
      computedStatus: ComputedStatus.fromString(
        json['computed_status'] as String?,
      ),
      nextAvailableDay:
          (json['computed_status_detail']
                  as Map<String, dynamic>?)?['next_available_day']
              as String?,
      opensAt:
          (json['computed_status_detail'] as Map<String, dynamic>?)?['opens_at']
              as String?,
      stockQuantity: json['stock_quantity'] as int?,
      stockResetDaily: json['stock_reset_daily'] as bool? ?? false,
      stockInitial: json['stock_initial'] as int?,
      isAvailable: json['is_available'] as bool? ?? true,
      extras: parseExtras(),
      availableDays:
          (json['availableDays'] as List<dynamic>?)
              ?.map((e) => e as int)
              .toList() ??
          const [],
      productRating: (json['productRating'] as num?)?.toDouble() ?? 0.0,
      productReviews: (json['productReviews'] as num?)?.toInt() ?? 0,
      userRating: (json['userRating'] as num?)?.toInt(),
      postType: json['postType'] as String? ?? 'producto',
      locationLat: (json['locationLat'] as num?)?.toDouble(),
      locationLng: (json['locationLng'] as num?)?.toDouble(),
      paymentMethods: (json['paymentMethods'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      views: (json['views'] as num?)?.toInt() ?? 0,
      atributos: parseAtributos(),
      atributosDestacados: parseAtributosDestacados(),
    );
  }

  final String id;
  final String title;
  final double price;
  final double? previousPrice;
  final String? discountLabel;
  final MarketplaceCategory category;
  final String description;
  final String publishedAgo;
  final Seller seller;
  final List<String> images; // URLs de imágenes reales (del backend)
  final IconData imageIcon;
  final Color imageColor;
  final bool isFeatured;
  final bool isOffer;
  final bool isFavorite;
  final ListingStatus? status;
  final ManualStatus? manualStatus;
  final ComputedStatus computedStatus;
  final String? nextAvailableDay;
  final String? opensAt;
  final int? stockQuantity;
  final bool stockResetDaily;
  final int? stockInitial;
  final bool isAvailable;
  final List<ProductExtra> extras;
  final List<int> availableDays; // 0=Mon, 1=Tue ... 6=Sun
  final double productRating;
  final int productReviews;
  final int? userRating; // null = no ha calificado, 1-5 = su calificación

  /// 'producto' o 'se_busca'. Determina qué secciones de
  /// [ProductDetailScreen] se muestran/ocultan.
  final String postType;
  // Campos exclusivos de "se busca" (postType == 'se_busca'):
  final double? priceMin;
  final double? priceMax;
  final String? wantedStatus; // 'abierta' | 'resuelta'
  final String? wantedKind; // 'producto' | 'servicio' (lo que se busca)

  // Ubicación puntual de esta publicación (Nivel 2, solo negocios). No
  // confundir con la ubicación de perfil del vendedor ([Seller.locationLat]).
  final double? locationLat;
  final double? locationLng;

  /// Override de métodos de pago para ESTA publicación (null = hereda los
  /// del perfil del vendedor). Usa [effectivePaymentMethods] para el valor
  /// a mostrar/considerar; no leas este campo directamente en UI.
  final List<String>? paymentMethods;

  /// Conteo simple de vistas de detalle (no vistas únicas por usuario).
  final int views;

  /// Respuestas a las preguntas dinámicas de la categoría, con la key de la
  /// pregunta como llave (ver `constants/atributos_categoria.dart`).
  ///
  /// Siempre un mapa, nunca null: una publicación que no respondió nada trae
  /// `{}`, igual que una anterior a que existieran las preguntas. Los valores
  /// son `bool`, `String`, `num` o `List<String>` según el tipo de pregunta.
  final Map<String, dynamic> atributos;

  /// Los 1-2 atributos que la tarjeta del listado muestra como badge, ya
  /// resueltos por el servidor. Se recibe hecho a propósito: la tarjeta se
  /// pinta en cuatro pantallas y ninguna debería tener su propia opinión
  /// sobre cuál es el dato clave de un producto de ropa.
  final List<AtributoDestacado> atributosDestacados;

  bool get isWantedPost => postType == 'se_busca';
  bool get hasLocation => locationLat != null && locationLng != null;

  /// Métodos de pago que realmente aplican a esta publicación: los propios
  /// si se personalizaron, o los del perfil del vendedor si no.
  List<String> get effectivePaymentMethods =>
      paymentMethods ?? seller.paymentMethods;
}

/// Un atributo listo para pintarse como badge en la tarjeta del listado.
///
/// El servidor decide cuáles son (máximo dos por categoría) y ya los resuelve
/// a texto: los booleanos llegan con su afirmación corta ("Acepta mascotas")
/// en vez de la pregunta, y las listas llegan unidas. La tarjeta solo pinta.
class AtributoDestacado {
  const AtributoDestacado({
    required this.key,
    required this.label,
    required this.value,
  });

  factory AtributoDestacado.fromJson(Map<String, dynamic> json) {
    return AtributoDestacado(
      key: json['key'] as String? ?? '',
      label: json['label'] as String? ?? '',
      value: json['value']?.toString() ?? '',
    );
  }

  /// Key de la pregunta de origen. No se pinta; sirve para que un filtro
  /// futuro pueda saber sobre qué atributo está el badge.
  final String key;

  /// La pregunta completa, para tooltips o accesibilidad.
  final String label;

  /// Lo que se muestra dentro del badge.
  final String value;
}

/// El detalle de una publicación: el producto más los dos carruseles que
/// GET /products/:id devuelve en la MISMA respuesta.
///
/// Van juntos a propósito: son parte del detalle, no una carga aparte, y
/// pedirlos por separado los haría aparecer a destiempo bajo el contenido ya
/// pintado. Ambas listas llegan siempre (vacías si no hay nada), así que la
/// pantalla decide con `isEmpty` y no con chequeos de nulos.
class ProductDetail {
  const ProductDetail({
    required this.product,
    this.relatedProducts = const [],
    this.sellerOtherProducts = const [],
  });

  factory ProductDetail.fromJson(Map<String, dynamic> json) {
    List<Product> parseList(String key) {
      final raw = json[key];
      if (raw is! List) return const [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(Product.fromJson)
          .toList(growable: false);
    }

    return ProductDetail(
      product: Product.fromJson(json),
      relatedProducts: parseList('relatedProducts'),
      sellerOtherProducts: parseList('sellerOtherProducts'),
    );
  }

  final Product product;

  /// Publicaciones parecidas, de OTROS vendedores.
  final List<Product> relatedProducts;

  /// Otras publicaciones activas del mismo vendedor.
  final List<Product> sellerOtherProducts;
}

class CartItem {
  const CartItem({
    required this.id,
    required this.product,
    required this.quantity,
    required this.meetingPoint,
  });

  factory CartItem.fromJson(Map<String, dynamic> json) {
    return CartItem(
      id: json['id'] as String? ?? '',
      product: Product.fromJson(json['product'] as Map<String, dynamic>),
      quantity: json['quantity'] as int? ?? 1,
      meetingPoint:
          json['meetingPoint'] as String? ?? 'cart.meeting_point_tbd'.tr(),
    );
  }

  final String id;
  final Product product;
  final int quantity;
  final String meetingPoint;
}

// TODO: Destacar publicaciones pendiente para próxima actualización - no
// eliminar. El modelo se mantiene intacto (lo sigue usando la pantalla de
// planes, hoy inaccesible) aunque la feature esté apagada
// (ver features/highlight/destacar_flag.dart).
class HighlightPlan {
  const HighlightPlan({
    required this.id,
    required this.title,
    required this.price,
    required this.description,
    required this.days,
  });

  factory HighlightPlan.fromJson(Map<String, dynamic> json) {
    return HighlightPlan(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      price: json['price'] as String? ?? '\$0',
      description: json['description'] as String? ?? '',
      days: json['days'] as int? ?? 0,
    );
  }

  final String id;
  final String title;
  final String price;
  final String description;
  final int days;
}

/// Extra opcional que el comprador puede agregar a un producto.
class ProductExtra {
  const ProductExtra({required this.name, required this.extraPrice});

  factory ProductExtra.fromJson(Map<String, dynamic> json) {
    return ProductExtra(
      name: json['name'] as String? ?? '',
      extraPrice: (json['extraPrice'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'extraPrice': extraPrice};

  final String name;
  final double extraPrice;
}

/// Publicación de demanda: alguien busca un producto o servicio que
/// todavía no existe en el catálogo, y espera que un vendedor le responda.
class WantedPost {
  const WantedPost({
    required this.id,
    required this.userId,
    required this.title,
    this.description,
    required this.categoryId,
    required this.type,
    this.priceMin,
    this.priceMax,
    required this.status,
    this.resolvedWithUserId,
    required this.createdAt,
    this.updatedAt,
    this.resolvedAt,
    this.sellerObj,
    this.categoryObj,
    this.locationLat,
    this.locationLng,
    this.paymentMethods,
    this.views = 0,
  });

  factory WantedPost.fromJson(Map<String, dynamic> json) {
    return WantedPost(
      id: json['id'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      categoryId: json['categoryId'] as String? ?? '',
      type: json['type'] as String? ?? 'producto',
      priceMin: (json['priceMin'] as num?)?.toDouble(),
      priceMax: (json['priceMax'] as num?)?.toDouble(),
      status: json['status'] as String? ?? 'abierta',
      resolvedWithUserId: json['resolvedWithUserId'] as String?,
      createdAt: json['createdAt'] as String? ?? '',
      updatedAt: json['updatedAt'] as String?,
      resolvedAt: json['resolvedAt'] as String?,
      sellerObj: json['sellerObj'] != null
          ? Seller.fromJson(json['sellerObj'] as Map<String, dynamic>)
          : null,
      categoryObj: json['categoryObj'] != null
          ? MarketplaceCategory.fromJson(
              json['categoryObj'] as Map<String, dynamic>,
            )
          : null,
      locationLat: (json['locationLat'] as num?)?.toDouble(),
      locationLng: (json['locationLng'] as num?)?.toDouble(),
      paymentMethods: (json['paymentMethods'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      views: (json['views'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String userId;
  final String title;
  final String? description;
  final String categoryId;
  final String type; // 'producto' | 'servicio'
  final double? priceMin;
  final double? priceMax;
  final String status; // 'abierta' | 'resuelta'
  final String? resolvedWithUserId;
  final String createdAt;
  final String? updatedAt;
  final String? resolvedAt;
  final Seller? sellerObj;
  final MarketplaceCategory? categoryObj;
  final double? locationLat;
  final double? locationLng;
  final List<String>? paymentMethods;
  final int views;

  bool get isService => type == 'servicio';
  bool get isResolved => status == 'resuelta';
}

class NotificationItem {
  const NotificationItem({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.body,
    this.data = const {},
    this.read = false,
    required this.createdAt,
  });

  factory NotificationItem.fromJson(Map<String, dynamic> json) {
    return NotificationItem(
      id: json['id'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      type: json['type'] as String? ?? '',
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      data: json['data'] as Map<String, dynamic>? ?? {},
      read: json['read'] as bool? ?? false,
      createdAt: json['createdAt'] as String? ?? '',
    );
  }

  final String id;
  final String userId;
  final String type;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final bool read;
  final String createdAt;
}

class Conversation {
  const Conversation({
    required this.id,
    required this.productId,
    required this.buyerId,
    required this.sellerId,
    required this.createdAt,
    this.lastMessageAt,
    this.lastMessagePreview = '',
    this.product,
    this.otherUser,
    this.lastMessage,
    this.wantedPostId,
    this.wantedPostTitle,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'] as String? ?? '',
      productId: json['productId'] as String? ?? '',
      buyerId: json['buyerId'] as String? ?? '',
      sellerId: json['sellerId'] as String? ?? '',
      createdAt: json['createdAt'] as String? ?? '',
      lastMessageAt: json['lastMessageAt'] as String?,
      lastMessagePreview: json['lastMessagePreview'] as String? ?? '',
      product: json['product'] != null
          ? ChatProduct.fromJson(json['product'] as Map<String, dynamic>)
          : null,
      otherUser: json['otherUser'] != null
          ? ChatUser.fromJson(json['otherUser'] as Map<String, dynamic>)
          : null,
      lastMessage: json['lastMessage'] != null
          ? ChatMessage.fromJson(json['lastMessage'] as Map<String, dynamic>)
          : null,
      wantedPostId: json['wantedPostId'] as String?,
      wantedPostTitle: json['wantedPost'] != null
          ? (json['wantedPost'] as Map<String, dynamic>)['title'] as String?
          : null,
    );
  }

  final String id;
  final String productId;
  final String buyerId;
  final String sellerId;
  final String createdAt;
  final String? lastMessageAt;
  final String lastMessagePreview;
  final ChatProduct? product;
  final ChatUser? otherUser;
  final ChatMessage? lastMessage;
  final String? wantedPostId;
  final String? wantedPostTitle;
}

class ChatProduct {
  const ChatProduct({
    required this.id,
    required this.title,
    this.price = 0,
    this.images = const [],
    this.imageIcon,
    this.imageColor,
  });

  factory ChatProduct.fromJson(Map<String, dynamic> json) {
    return ChatProduct(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0,
      images:
          (json['images'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      imageIcon: json['imageIcon'] as String?,
      imageColor: json['imageColor'] as String?,
    );
  }

  final String id;
  final String title;
  final double price;
  final List<String> images;
  final String? imageIcon;
  final String? imageColor;
}

/// Estado de seguridad y consentimiento entre la cuenta actual y otra.
///
/// Se calcula en el servidor para que el límite de primer contacto no se
/// pueda evadir modificando el cliente o abriendo otro chat.
class ChatRelationship {
  const ChatRelationship({
    this.blockedByMe = false,
    this.blockedMe = false,
    this.mutedByMe = false,
    this.accepted = false,
    this.awaitingReply = false,
    this.firstContactLimit = 5,
    this.remainingMessages,
    this.canSend = true,
  });

  factory ChatRelationship.fromJson(Map<String, dynamic> json) {
    return ChatRelationship(
      blockedByMe: json['blockedByMe'] as bool? ?? false,
      blockedMe: json['blockedMe'] as bool? ?? false,
      mutedByMe: json['mutedByMe'] as bool? ?? false,
      accepted: json['accepted'] as bool? ?? false,
      awaitingReply: json['awaitingReply'] as bool? ?? false,
      firstContactLimit: json['firstContactLimit'] as int? ?? 5,
      remainingMessages: json['remainingMessages'] as int?,
      canSend: json['canSend'] as bool? ?? true,
    );
  }

  final bool blockedByMe;
  final bool blockedMe;
  final bool mutedByMe;
  final bool accepted;
  final bool awaitingReply;
  final int firstContactLimit;
  final int? remainingMessages;
  final bool canSend;
}

class ChatUser {
  const ChatUser({
    required this.id,
    required this.name,
    this.avatarInitials = '',
    this.logoUrl,
    this.estadoConexion = EstadoConexion.desconocido,
    this.verified = false,
    this.socioFundador = false,
    this.tipoCuenta = 'particular',
    this.isGuest = false,
  });

  factory ChatUser.fromJson(Map<String, dynamic> json) {
    return ChatUser(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      avatarInitials: json['avatarInitials'] as String? ?? '',
      logoUrl: json['logoUrl'] as String?,
      estadoConexion: EstadoConexion.desdeJson(json),
      verified: json['verified'] as bool? ?? false,
      socioFundador: json['socioFundador'] as bool? ?? false,
      tipoCuenta: json['tipoCuenta'] as String? ?? 'particular',
      isGuest: json['isGuest'] as bool? ?? false,
    );
  }

  final String id;
  final String name;
  final String avatarInitials;
  final String? logoUrl;

  /// Presencia tal y como venía en la respuesta. Es solo la SEMILLA: lo que
  /// se pinta sale de PresenceService, que además recibe los cambios en vivo.
  final EstadoConexion estadoConexion;

  /// La palomita junto al nombre en el chat sale de estos tres, con
  /// [InsigniaCuenta] — misma decisión (verde > azul > nada) que en
  /// comentarios, preguntas y el resto de la app.
  final bool verified;
  final bool socioFundador;
  final String tipoCuenta;
  final bool isGuest;

  /// Para abrir el chat desde la ficha de un producto, donde lo que se tiene
  /// a mano es el [Seller] y no un [ChatUser] (ese solo viaja dentro de una
  /// [Conversation] ya existente). Mismos campos, otro origen.
  factory ChatUser.deSeller(Seller seller) => ChatUser(
    id: seller.id,
    name: seller.name,
    avatarInitials: seller.avatarInitials,
    logoUrl: seller.logoUrl,
    estadoConexion: seller.estadoConexion,
    verified: seller.verified,
    socioFundador: seller.socioFundador,
    tipoCuenta: seller.tipoCuenta,
    isGuest: seller.isGuest,
  );
}

/// El mensaje al que responde otro, resumido para pintar la cita.
///
/// Es una vista reducida y no un [ChatMessage] completo a propósito: la cita
/// solo necesita saber de quién era y qué decía. El backend la manda ya
/// resuelta dentro de cada mensaje (LEFT JOIN, ver `getMessages`), así que la
/// burbuja no dispara ninguna petición extra para pintarla.
class RepliedMessage {
  const RepliedMessage({
    required this.id,
    required this.senderId,
    required this.text,
    this.imageUrl,
  });

  factory RepliedMessage.fromJson(Map<String, dynamic> json) {
    return RepliedMessage(
      id: json['id'] as String? ?? '',
      senderId: json['senderId'] as String? ?? '',
      text: json['text'] as String? ?? '',
      imageUrl: json['imageUrl'] as String?,
    );
  }

  final String id;
  final String senderId;
  final String text;
  final String? imageUrl;

  /// Qué mostrar en una sola línea dentro de la cita.
  String get resumen {
    if (text.isNotEmpty) return text;
    if (imageUrl != null) return '📷 Foto';
    return '';
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.text,
    required this.createdAt,
    this.read = false,
    this.imageUrl,
    this.replyTo,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final reply = json['replyTo'] as Map<String, dynamic>?;
    return ChatMessage(
      id: json['id'] as String? ?? '',
      conversationId: json['conversationId'] as String? ?? '',
      senderId: json['senderId'] as String? ?? '',
      text: json['text'] as String? ?? '',
      createdAt: json['createdAt'] as String? ?? '',
      read: json['read'] as bool? ?? false,
      imageUrl: json['imageUrl'] as String?,
      replyTo: reply == null ? null : RepliedMessage.fromJson(reply),
    );
  }

  final String id;
  final String conversationId;
  final String senderId;
  final String text;
  final String createdAt;
  final bool read;
  final String? imageUrl;

  /// El mensaje citado, si este es una respuesta.
  final RepliedMessage? replyTo;

  /// Copia con el texto reemplazado por el placeholder de borrado.
  ///
  /// Existe para que el borrado (por acción propia o por evento de socket) no
  /// tenga que reconstruir el mensaje campo por campo: hacerlo a mano ya
  /// perdía silenciosamente cualquier campo nuevo, que es justo lo que le
  /// habría pasado a `replyTo`.
  ChatMessage comoEliminado() => ChatMessage(
    id: id,
    conversationId: conversationId,
    senderId: senderId,
    text: '[Mensaje eliminado]',
    createdAt: createdAt,
    read: read,
    imageUrl: null,
    replyTo: replyTo,
  );
}

/// Un comentario en una publicación.
///
/// [author] es un [Seller] completo a propósito, aunque el backend solo
/// mande un puñado de campos: así el hilo puede usar `subtituloRol()` e
/// `InsigniaVerificada` —los mismos widgets que el perfil y el detalle— en
/// vez de reimplementar el copy del rol y desincronizarse de las otras tres
/// pantallas. Los campos que el endpoint no manda (teléfono, rating) caen a
/// los defaults de [Seller.fromJson] y ningún widget del hilo los lee.
class ProductComment {
  const ProductComment({
    required this.id,
    required this.productId,
    required this.texto,
    required this.createdAt,
    required this.author,
    this.productTitle,
    this.productImage,
  });

  factory ProductComment.fromJson(Map<String, dynamic> json) {
    final producto = json['product'] as Map<String, dynamic>?;
    return ProductComment(
      id: json['id'] as String? ?? '',
      // En el feed del perfil el id del producto viene dentro de `product`,
      // que es también de donde salen título y miniatura.
      productId:
          json['productId'] as String? ?? producto?['id'] as String? ?? '',
      texto: json['texto'] as String? ?? '',
      createdAt: _parseUtc(json['createdAt'] as String?),
      author: Seller.fromJson(
        (json['author'] as Map<String, dynamic>?) ?? const {},
      ),
      productTitle: producto?['title'] as String?,
      productImage: producto?['image'] as String?,
    );
  }

  /// El backend emite ISO-8601 con 'Z' (ver database.js). Se convierte a
  /// hora local para que el tiempo relativo cuadre con el reloj del
  /// dispositivo; si por lo que sea llegara sin zona, se asume UTC en vez de
  /// local, que es lo que realmente guarda SQLite.
  static DateTime _parseUtc(String? raw) {
    if (raw == null || raw.isEmpty) return DateTime.now();
    final normalizado = raw.contains('T') ? raw : raw.replaceFirst(' ', 'T');
    final conZona =
        normalizado.endsWith('Z') ||
            RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(normalizado)
        ? normalizado
        : '${normalizado}Z';
    return DateTime.tryParse(conZona)?.toLocal() ?? DateTime.now();
  }

  final String id;
  final String productId;
  final String texto;
  final DateTime createdAt;
  final Seller author;

  /// Título del producto comentado. Solo lo trae `GET /api/users/:id/comments`
  /// (la pestaña del perfil); dentro del hilo de un producto es null porque
  /// ya se sabe en qué publicación estás.
  final String? productTitle;

  /// Ruta relativa de la primera foto del producto ('/uploads/x.webp'), o
  /// null si la publicación no tiene fotos. Mismo alcance que [productTitle].
  final String? productImage;
}

/// Una página de comentarios: las filas más el cursor de la siguiente.
class ProductCommentPage {
  const ProductCommentPage({
    required this.comments,
    required this.total,
    this.nextCursor,
  });

  factory ProductCommentPage.fromJson(Map<String, dynamic> json) {
    return ProductCommentPage(
      comments: ((json['comments'] as List<dynamic>?) ?? const [])
          .map((e) => ProductComment.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: (json['total'] as num?)?.toInt() ?? 0,
      nextCursor: json['nextCursor'] as String?,
    );
  }

  final List<ProductComment> comments;

  /// Total de comentarios vivos, no el tamaño de esta página. Viene en cada
  /// página para que el contador del header siga siendo correcto después de
  /// paginar o de borrar uno.
  final int total;

  /// Null cuando ya no hay más páginas.
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
}

/// Una pregunta pública sobre una publicación, con la respuesta del vendedor
/// si ya la dio.
///
/// Pregunta y respuesta viven en la misma fila porque son un solo hilo de dos
/// turnos: cada pregunta admite UNA respuesta, la del dueño. Por eso no hay
/// una lista de respuestas ni un autor por respuesta — siempre es el mismo, y
/// quién es se sabe desde la publicación.
class ProductQuestion {
  const ProductQuestion({
    required this.id,
    required this.productId,
    required this.questionText,
    required this.createdAt,
    required this.author,
    this.answerText,
    this.answeredAt,
    this.status = 'pending',
  });

  factory ProductQuestion.fromJson(Map<String, dynamic> json) {
    final respuesta = json['answerText'] as String?;
    return ProductQuestion(
      id: json['id'] as String? ?? '',
      productId: json['productId'] as String? ?? '',
      questionText: json['questionText'] as String? ?? '',
      answerText: (respuesta != null && respuesta.isNotEmpty)
          ? respuesta
          : null,
      // El estado se lee del backend, que es quien manda, pero se cae a
      // deducirlo del texto si llegara vacío: una respuesta visible con
      // badge de "pendiente" al lado es peor que no tener el campo.
      status:
          json['status'] as String? ??
          ((respuesta != null && respuesta.isNotEmpty)
              ? 'answered'
              : 'pending'),
      createdAt: _parseUtc(json['createdAt'] as String?),
      answeredAt: json['answeredAt'] == null
          ? null
          : _parseUtc(json['answeredAt'] as String?),
      author: Seller.fromJson(
        (json['author'] as Map<String, dynamic>?) ?? const {},
      ),
    );
  }

  /// Mismo criterio que [ProductComment._parseUtc]: el backend emite UTC con
  /// 'Z' y aquí se pasa a hora local.
  static DateTime _parseUtc(String? raw) => ProductComment._parseUtc(raw);

  final String id;
  final String productId;
  final String questionText;

  /// Null mientras el vendedor no responde.
  final String? answerText;

  /// 'pending' | 'answered'. Ambos son públicos: que una pregunta lleve días
  /// sin respuesta también es información sobre la publicación.
  final String status;

  final DateTime createdAt;
  final DateTime? answeredAt;

  /// Quien preguntó. Solo lo mínimo para pintar nombre e insignia.
  final Seller author;

  bool get isAnswered => status == 'answered' && answerText != null;
}

/// Una página de preguntas: las filas, el cursor de la siguiente y los dos
/// contadores que la UI necesita sin tener que pedir el listado completo.
class ProductQuestionPage {
  const ProductQuestionPage({
    required this.questions,
    required this.total,
    required this.pendingCount,
    this.nextCursor,
  });

  factory ProductQuestionPage.fromJson(Map<String, dynamic> json) {
    return ProductQuestionPage(
      questions: ((json['questions'] as List<dynamic>?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ProductQuestion.fromJson)
          .toList(),
      total: (json['total'] as num?)?.toInt() ?? 0,
      pendingCount: (json['pendingCount'] as num?)?.toInt() ?? 0,
      nextCursor: json['nextCursor'] as String?,
    );
  }

  final List<ProductQuestion> questions;

  /// Total de preguntas de la publicación, no el tamaño de esta página.
  final int total;

  /// Cuántas siguen sin responder — el chip del dueño.
  final int pendingCount;

  final String? nextCursor;

  bool get hasMore => nextCursor != null;
}
