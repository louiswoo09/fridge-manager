import 'package:flutter/material.dart';

class IngredientIconMapper {

  static const Map<String, String> _icons = {
    //'감자': 'assets/ingredient_icons/potato.png',
    //'당근': 'assets/ingredient_icons/carrot.png',
    //'토마토': 'assets/ingredient_icons/tomato.png',
    //'양파': 'assets/ingredient_icons/onion.png',
  };


  static String? getIcon(String name) {
    for (final key in _icons.keys) {
      if (name.contains(key)) {
        return _icons[key];
      }
    }

    return null;
  }


  static Widget build({
    required String name,
    required String category,
    double size = 40,
  }) {

    final iconPath = getIcon(name);


    // 개별 아이콘 있으면 사용
    if (iconPath != null) {
      return Image.asset(
        iconPath,
        width: size,
        height: size,
        fit: BoxFit.contain,
      );
    }


    // 없으면 기존 카테고리 아이콘
    return Icon(
      _categoryIcon(category),
      size: size,
      color: Colors.grey[700],
    );
  }



  static IconData _categoryIcon(String category) {
    switch(category){

      case '채소':
        return Icons.eco;

      case '육류':
        return Icons.kebab_dining;

      case '유제품':
        return Icons.water_drop;

      case '과일':
        return Icons.apple;

      case '해산물':
        return Icons.set_meal;

      default:
        return Icons.kitchen;
    }
  }
}