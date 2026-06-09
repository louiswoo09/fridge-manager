import 'dart:async';
import 'package:flutter/material.dart';
import '../services/favorite_service.dart';
import '../services/ingredient_service.dart';
import '../services/cart_service.dart';
import '../models/ingredient.dart';
import '../models/recipe_mode.dart';
import 'recipe_detail_screen.dart';
import 'dart:convert';

class FavoriteListScreen extends StatefulWidget {
  const FavoriteListScreen({super.key});

  @override
  State<FavoriteListScreen> createState() => _FavoriteListScreenState();
}

class _FavoriteListScreenState extends State<FavoriteListScreen> {
  final FavoriteService _favoriteService = FavoriteService();
  final IngredientService _ingredientService = IngredientService();
  final CartService _cartService = CartService();

  List<Map<String, dynamic>> _favorites = [];
  List<Ingredient> _ingredients = [];
  List<String> _cartNames = [];

  StreamSubscription<List<Map<String, dynamic>>>? _subscription;
  StreamSubscription<List<Ingredient>>? _ingredientSubscription;
  StreamSubscription<List<String>>? _cartSubscription;

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();

    _subscription = _favoriteService.watchFavorites().listen((items) {
      if (!mounted) return;
      setState(() {
        _favorites = items;
        _isLoading = false;
      });
    });

    _ingredientSubscription = _ingredientService.getIngredients().listen((
      items,
    ) {
      if (!mounted) return;
      setState(() => _ingredients = items);
    });

    _cartSubscription = _cartService.watchDisplayNames().listen((names) {
      if (!mounted) return;
      setState(() => _cartNames = names);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _ingredientSubscription?.cancel();
    _cartSubscription?.cancel();
    super.dispose();
  }

  /// 만료 안 된 보유 식재료명
  List<String> get _ownedIngredientNames {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _ingredients
        .where((item) {
          final exp = DateTime(
            item.expirationDate.year,
            item.expirationDate.month,
            item.expirationDate.day,
          );
          return !exp.isBefore(today);
        })
        .map((item) => item.name)
        .toList();
  }

  /// 3일 이내 임박 식재료명
  List<String> get _imminentIngredientNames {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final threshold = today.add(const Duration(days: 3));

    return _ingredients
        .where((item) {
          final exp = DateTime(
            item.expirationDate.year,
            item.expirationDate.month,
            item.expirationDate.day,
          );
          return !exp.isBefore(today) && !exp.isAfter(threshold);
        })
        .map((item) => item.name)
        .toList();
  }

  /// recipeId별로 그룹화 — 원본과 변형들을 분리
  Map<String, _RecipeGroup> get _grouped {
    final map = <String, _RecipeGroup>{};
    for (final fav in _favorites) {
      final recipeId = fav['recipeId']?.toString() ?? '';
      final group = map.putIfAbsent(
        recipeId,
        () => _RecipeGroup(recipeId: recipeId),
      );

      if (fav['aiResult'] == null) {
        group.original = fav;
      } else {
        group.variants.add(fav);
      }
    }
    return map;
  }

  String _extractVariantTitle(String? aiResult) {
    if (aiResult == null) return '변형 레시피';

    final trimmed = aiResult.trim();

    // JSON 형식인지 시도
    if (trimmed.startsWith('{')) {
      try {
        final json = jsonDecode(trimmed);
        final title = (json as Map<String, dynamic>)['title']?.toString();
        if (title != null && title.isNotEmpty) {
          return title;
        }
      } catch (_) {
        // 파싱 실패 시 아래로
      }
    }

    // 옛 형식 — 첫 줄
    final lines = trimmed.split('\n');
    for (final line in lines) {
      final t = line.trim();
      if (t.isNotEmpty) {
        return t;
      }
    }

    return '변형 레시피';
  }

  RecipeMode? _parseMode(String? name) {
    if (name == null) return null;
    return RecipeMode.values.firstWhere(
      (e) => e.name == name,
      orElse: () => RecipeMode.fridge,
    );
  }

  FridgeFilter? _parseFilter(String? name) {
    if (name == null) return null;
    return FridgeFilter.values.firstWhere(
      (e) => e.name == name,
      orElse: () => FridgeFilter.all,
    );
  }

  Future<void> _openOriginalWithData(Map<String, dynamic> recipeData) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecipeDetailScreen(
          recipe: recipeData,
          ownedIngredients: _ownedIngredientNames,
          extraIngredients: _cartNames,
          imminentIngredients: _imminentIngredientNames,
          fromFavorite: true,
        ),
      ),
    );
  }

  Future<void> _openVariant(Map<String, dynamic> fav) async {
    final recipeData = Map<String, dynamic>.from(fav['recipeData'] ?? {});
    final mode = _parseMode(fav['mode']?.toString()) ?? RecipeMode.fridge;
    final fridgeFilter =
        _parseFilter(fav['fridgeFilter']?.toString()) ?? FridgeFilter.all;
    final aiResult = fav['aiResult']?.toString();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RecipeDetailScreen(
          recipe: recipeData,
          ownedIngredients: _ownedIngredientNames,
          extraIngredients: _cartNames,
          imminentIngredients: _imminentIngredientNames,
          mode: mode,
          fridgeFilter: fridgeFilter,
          initialAiResult: aiResult,
          fromFavorite: true,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(Map<String, dynamic> fav, String label) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('즐겨찾기 해제'),
        content: Text('$label을(를) 해제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('해제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    await _favoriteService.remove(
      recipeId: fav['recipeId']?.toString() ?? '',
      aiResult: fav['aiResult']?.toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _grouped;

    return Scaffold(
      appBar: AppBar(title: const Text('즐겨찾기 레시피')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : grouped.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  '즐겨찾기한 레시피가 없어요.\n\n레시피 상세 화면에서 ⭐ 버튼으로 추가해보세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, height: 1.5),
                ),
              ),
            )
          : ListView(
              children: grouped.values.map((group) {
                return _buildGroupCard(group);
              }).toList(),
            ),
    );
  }

  Widget _buildGroupCard(_RecipeGroup group) {
    final original = group.original;
    final variants = group.variants;

    // 원본 recipeData 확보 — 원본 즐겨찾기에 있으면 거기서, 없으면 변형에서
    Map<String, dynamic>? recipeData;
    if (original != null) {
      recipeData = Map<String, dynamic>.from(original['recipeData'] ?? {});
    } else if (variants.isNotEmpty) {
      recipeData = Map<String, dynamic>.from(
        variants.first['recipeData'] ?? {},
      );
    }

    final recipeName =
        original?['recipeName']?.toString() ??
        (variants.isNotEmpty
            ? variants.first['recipeName']?.toString() ?? '레시피'
            : '레시피');

    final hasOriginal = original != null;
    final hasVariants = variants.isNotEmpty;
    final canOpenOriginal = recipeData != null;

    // 변형 없으면 ListTile (^ 버튼 없음)
    if (!hasVariants) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: ListTile(
          leading: const Icon(Icons.restaurant_menu, color: Colors.deepPurple),
          title: Text(
            recipeName,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.deepPurple,
            ),
          ),
          trailing: hasOriginal
              ? IconButton(
                  icon: const Icon(Icons.star, color: Colors.amber, size: 20),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _confirmDelete(original, recipeName),
                )
              : null,
          onTap: canOpenOriginal
              ? () => _openOriginalWithData(recipeData!)
              : null,
        ),
      );
    }

    // 변형 있으면 ExpansionTile
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: const Icon(Icons.restaurant_menu, color: Colors.deepPurple),
        title: InkWell(
          onTap: canOpenOriginal
              ? () => _openOriginalWithData(recipeData!)
              : null,
          child: Text(
            recipeName,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: canOpenOriginal ? Colors.deepPurple : Colors.grey,
            ),
          ),
        ),
        subtitle: Text(
          '변형 ${variants.length}개',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        initiallyExpanded: true,
        children: variants.map((fav) {
          final title = _extractVariantTitle(fav['aiResult']?.toString());
          return ListTile(
            leading: const Icon(
              Icons.auto_awesome,
              color: Colors.indigo,
              size: 20,
            ),
            title: Text(title, style: const TextStyle(fontSize: 14)),
            trailing: IconButton(
              icon: const Icon(Icons.star, color: Colors.amber, size: 20),
              visualDensity: VisualDensity.compact,
              onPressed: () => _confirmDelete(fav, title),
            ),
            onTap: () => _openVariant(fav),
          );
        }).toList(),
      ),
    );
  }
}

class _RecipeGroup {
  final String recipeId;
  Map<String, dynamic>? original;
  final List<Map<String, dynamic>> variants = [];

  _RecipeGroup({required this.recipeId});
}
