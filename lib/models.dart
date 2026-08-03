import 'package:flutter/material.dart';

/// Convierte una fecha ISO en un texto relativo corto ("Hace 5 min").
/// Usado por publicaciones que no traen un `publishedAgo` ya calculado
/// por el backend (p. ej. "se busca").
String relativeTimeFromIso(String iso) {
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) return '';
  final diff = DateTime.now().difference(parsed);
  if (diff.inMinutes < 1) return 'Ahora';
  if (diff.inHours < 1) return 'Hace ${diff.inMinutes} min';
  if (diff.inDays < 1) return 'Hace ${diff.inHours} h';
  if (diff.inDays < 7) return 'Hace ${diff.inDays} d';
  return 'Hace ${(diff.inDays / 7).floor()} sem';
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
    this.logoUrl,
    this.phone,
    required this.rating,
    required this.reviews,
    required this.verified,
    this.businessDescription,
    this.businessCategory,
    this.businessHours = const {},
    this.locationLat,
    this.locationLng,
  });

  factory Seller.fromJson(Map<String, dynamic> json) {
    return Seller(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      avatarInitials: json['avatarInitials'] as String? ?? '',
      major: json['major'] as String? ?? '',
      isBusiness: json['isBusiness'] as bool? ?? false,
      logoUrl: json['logoUrl'] as String?,
      phone: json['phone'] as String?,
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      reviews: (json['reviews'] as num?)?.toInt() ?? 0,
      verified: json['verified'] as bool? ?? false,
      businessDescription: json['businessDescription'] as String?,
      businessCategory: json['businessCategory'] as String?,
      businessHours: businessHoursFromJson(json['businessHours']),
      locationLat: (json['locationLat'] as num?)?.toDouble(),
      locationLng: (json['locationLng'] as num?)?.toDouble(),
    );
  }

  final String id;
  final String name;
  final String avatarInitials;
  final String major;
  final bool isBusiness;
  final String? logoUrl;
  final String? phone;
  final double rating;
  final int reviews;
  final bool verified;
  final String? businessDescription;
  final String? businessCategory;
  final Map<int, BusinessHoursRange> businessHours;
  final double? locationLat;
  final double? locationLng;

  bool get hasLocation => locationLat != null && locationLng != null;

  /// null = no aplica (no es negocio o no configuró horario, así que no hay
  /// nada que decidir); true/false = abierto/cerrado en este momento según
  /// [businessHours] y la hora local del dispositivo.
  bool? get isOpenNow {
    if (!isBusiness || businessHours.isEmpty) return null;
    final now = DateTime.now();
    final day = now.weekday - 1; // DateTime: 1=Lunes..7=Domingo → 0=Lunes..6=Domingo
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

/// Estados de disponibilidad que el dueño puede asignar a su producto.
enum ProductAvailability {
  available,
  reserved,
  sold,
  negotiating,
  paused,
  unavailable;

  String get label {
    switch (this) {
      case ProductAvailability.available:
        return 'Disponible';
      case ProductAvailability.reserved:
        return 'Apartado';
      case ProductAvailability.sold:
        return 'Vendido';
      case ProductAvailability.negotiating:
        return 'En negociación';
      case ProductAvailability.paused:
        return 'Pausado';
      case ProductAvailability.unavailable:
        return 'No disponible';
    }
  }

  /// Map from the backend string value.
  static ProductAvailability? fromString(String? value) {
    if (value == null) return null;
    switch (value) {
      case 'available':
        return ProductAvailability.available;
      case 'reserved':
        return ProductAvailability.reserved;
      case 'sold':
        return ProductAvailability.sold;
      case 'negotiating':
        return ProductAvailability.negotiating;
      case 'paused':
        return ProductAvailability.paused;
      case 'unavailable':
        return ProductAvailability.unavailable;
      default:
        return null;
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
    this.availability,
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
        name: 'Vendedor',
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
      availability: ProductAvailability.fromString(json['status'] as String?),
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
  final ProductAvailability? availability;
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

  bool get isWantedPost => postType == 'se_busca';
  bool get hasLocation => locationLat != null && locationLng != null;
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
      meetingPoint: json['meetingPoint'] as String? ?? 'Por definir',
    );
  }

  final String id;
  final Product product;
  final int quantity;
  final String meetingPoint;
}

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

class ChatUser {
  const ChatUser({
    required this.id,
    required this.name,
    this.avatarInitials = '',
  });

  factory ChatUser.fromJson(Map<String, dynamic> json) {
    return ChatUser(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      avatarInitials: json['avatarInitials'] as String? ?? '',
    );
  }

  final String id;
  final String name;
  final String avatarInitials;
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
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as String? ?? '',
      conversationId: json['conversationId'] as String? ?? '',
      senderId: json['senderId'] as String? ?? '',
      text: json['text'] as String? ?? '',
      createdAt: json['createdAt'] as String? ?? '',
      read: json['read'] as bool? ?? false,
      imageUrl: json['imageUrl'] as String?,
    );
  }

  final String id;
  final String conversationId;
  final String senderId;
  final String text;
  final String createdAt;
  final bool read;
  final String? imageUrl;
}
