class VariantRecipe {
  final String title;
  final int servings;
  final List<VariantIngredient> fridgeIngredients;
  final List<VariantIngredient> cartIngredients;
  final List<VariantIngredient> seasoning;
  final String? tip;
  final List<VariantStep> steps;
  final bool insufficient;

  VariantRecipe({
    required this.title,
    required this.servings,
    required this.fridgeIngredients,
    required this.cartIngredients,
    required this.seasoning,
    this.tip,
    required this.steps,
    required this.insufficient,
  });

  factory VariantRecipe.fromJson(Map<String, dynamic> json) {
    final ingredients = json['ingredients'] as Map<String, dynamic>? ?? {};
    
    return VariantRecipe(
      title: json['title']?.toString() ?? '',
      servings: (json['servings'] as num?)?.toInt() ?? 2,
      fridgeIngredients: (ingredients['fridge'] as List?)
              ?.map((e) => VariantIngredient.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      cartIngredients: (ingredients['cart'] as List?)
              ?.map((e) => VariantIngredient.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      seasoning: (ingredients['seasoning'] as List?)
              ?.map((e) => VariantIngredient.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      tip: json['tip']?.toString(),
      steps: (json['steps'] as List?)
              ?.map((e) => VariantStep.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      insufficient: json['insufficient'] as bool? ?? false,
    );
  }
}

class VariantIngredient {
  final String name;
  final String amount;
  final String unit;
  final bool imminent;

  VariantIngredient({
    required this.name,
    required this.amount,
    required this.unit,
    this.imminent = false,
  });

  factory VariantIngredient.fromJson(Map<String, dynamic> json) {
    return VariantIngredient(
      name: json['name']?.toString() ?? '',
      amount: json['amount']?.toString() ?? '',
      unit: json['unit']?.toString() ?? '',
      imminent: json['imminent'] as bool? ?? false,
    );
  }
}

class VariantStep {
  final int order;
  final String instruction;
  final List<String> ingredientsUsed;
  final int? timeSeconds;

  VariantStep({
    required this.order,
    required this.instruction,
    required this.ingredientsUsed,
    this.timeSeconds,
  });

  factory VariantStep.fromJson(Map<String, dynamic> json) {
    return VariantStep(
      order: (json['order'] as num?)?.toInt() ?? 0,
      instruction: json['instruction']?.toString() ?? '',
      ingredientsUsed: (json['ingredients_used'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      timeSeconds: (json['time_seconds'] as num?)?.toInt(),
    );
  }
}