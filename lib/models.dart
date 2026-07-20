import 'package:flutter/material.dart';

class MarketplaceCategory {
  const MarketplaceCategory({
    required this.id,
    required this.name,
    required this.emoji,
    required this.icon,
    required this.color,
  });

  final String id;
  final String name;
  final String emoji;
  final IconData icon;
  final Color color;
}

class Seller {
  const Seller({
    required this.name,
    required this.avatarInitials,
    required this.major,
    required this.rating,
    required this.reviews,
    required this.verified,
  });

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
    required this.imageIcon,
    required this.imageColor,
    this.previousPrice,
    this.discountLabel,
    this.isFeatured = false,
    this.isOffer = false,
    this.isFavorite = false,
    this.status,
  });

  final String id;
  final String title;
  final String price;
  final String? previousPrice;
  final String? discountLabel;
  final MarketplaceCategory category;
  final String description;
  final String publishedAgo;
  final Seller seller;
  final IconData imageIcon;
  final Color imageColor;
  final bool isFeatured;
  final bool isOffer;
  final bool isFavorite;
  final ListingStatus? status;
}

class CartItem {
  const CartItem({
    required this.product,
    required this.quantity,
    required this.meetingPoint,
  });

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

  final String id;
  final String title;
  final String price;
  final String description;
  final int days;
}
