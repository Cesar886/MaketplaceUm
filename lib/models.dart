import 'package:flutter/material.dart';

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
      id: json['id'] as String,
      name: json['name'] as String,
      emoji: json['emoji'] as String,
      icon: _parseIcon(json['icon'] as String),
      color: _parseColor(json['color'] as String),
    );
  }

  final String id;
  final String name;
  final String emoji;
  final IconData icon;
  final Color color;
}

class Seller {
  const Seller({
    this.id = '',
    required this.name,
    required this.avatarInitials,
    required this.major,
    required this.rating,
    required this.reviews,
    required this.verified,
  });

  factory Seller.fromJson(Map<String, dynamic> json) {
    return Seller(
      id: json['id'] as String,
      name: json['name'] as String,
      avatarInitials: json['avatarInitials'] as String,
      major: json['major'] as String,
      rating: (json['rating'] as num).toDouble(),
      reviews: json['reviews'] as int,
      verified: json['verified'] as bool,
    );
  }

  final String id;
  final String name;
  final String avatarInitials;
  final String major;
  final double rating;
  final int reviews;
  final bool verified;
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
  });

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
            json['categoryObj'] as Map<String, dynamic>);
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
      if (json['status'] == null) return null;
      switch (json['status'] as String) {
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

    return Product(
      id: json['id'] as String,
      title: json['title'] as String,
      price: json['price'] as String,
      category: parseCategory(),
      description: json['description'] as String,
      publishedAgo: json['publishedAgo'] as String,
      seller: parseSeller(),
      images: parsedImages,
      imageIcon: _parseIcon(json['imageIcon'] as String? ?? 'inventory_2'),
      imageColor: _parseColor(json['imageColor'] as String? ?? '#607D8B'),
      previousPrice: json['previousPrice'] as String?,
      discountLabel: json['discountLabel'] as String?,
      isFeatured: json['isFeatured'] as bool? ?? false,
      isOffer: json['isOffer'] as bool? ?? false,
      isFavorite: json['isFavorite'] as bool? ?? false,
      status: parseStatus(),
    );
  }

  final String id;
  final String title;
  final String price;
  final String? previousPrice;
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
      quantity: json['quantity'] as int,
      meetingPoint: json['meetingPoint'] as String,
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
      id: json['id'] as String,
      title: json['title'] as String,
      price: json['price'] as String,
      description: json['description'] as String,
      days: json['days'] as int,
    );
  }

  final String id;
  final String title;
  final String price;
  final String description;
  final int days;
}
