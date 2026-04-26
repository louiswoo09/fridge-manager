import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../models/ingredient.dart';
import '../services/ingredient_service.dart';
import 'recipe_detail_screen.dart';

const String kFoodApiKey = String.fromEnvironment('FOOD_API_KEY');

class RecipeScreen extends StatefulWidget {
  const RecipeScreen({super.key});

  @override
  State<RecipeScreen> createState() => _RecipeScreenState();
}

class _RecipeScreenState extends State<RecipeScreen> {
  final IngredientService _service = IngredientService();
  late StreamSubscription<List<Ingredient>> _sub;
  List<Ingredient> _items = [];
  List<Map<String, dynamic>> _recipes = [];
  bool _isLoading = true;
  bool _isFetching = false;
  bool _hasSearched = false;
  String _searchedKeywords = '';

  bool _isIgnored(String name) {
    const ignore = {'물', '소금', '설탕', '후추', '기름', '간장'};
    return ignore.any((e) => name.contains(e));
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void initState() {
    super.initState();
    _sub = _service.getIngredients().listen((items) {
      if (!mounted) return;
      setState(() {
        _items = items;
        _isLoading = false;
      });
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _search(String keyword) async {
    final url = Uri.parse(
      'https://openapi.foodsafetykorea.go.kr/api/$kFoodApiKey/COOKRCP01/json/1/8/RCP_PARTS_DTLS=${Uri.encodeComponent(keyword)}',
    );

    debugPrint('검색 키워드: $keyword');

    final response = await http.get(url).timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) return [];

    final data = jsonDecode(response.body);
    final cook = data['COOKRCP01'];
    if (cook == null) return [];

    final rows = (cook['row'] as List?)?.cast<Map<String, dynamic>>();
    if (rows == null || rows.isEmpty) return [];

    return rows
        .map(
          (r) => {
            ...r,
            'source': '식품의약품안전처',
            'searched_keywords': [keyword],
          },
        )
        .toList();
  }

  void _addToUnique(
    Map<String, Map<String, dynamic>> unique,
    List<Map<String, dynamic>> results,
  ) {
    for (var r in results) {
      final name = r['RCP_NM'];
      if (name == null) continue;

      if (unique.containsKey(name)) {
        final existing = List<String>.from(
          unique[name]!['searched_keywords'] ?? [],
        );
        final newKeywords = List<String>.from(r['searched_keywords'] ?? []);
        for (final k in newKeywords) {
          if (!existing.contains(k)) existing.add(k);
        }
        unique[name] = {...unique[name]!, 'searched_keywords': existing};
      } else {
        unique[name] = r;
      }
    }
  }

  Future<void> _fetchRecipes() async {
    if (_isFetching) return;

    if (kFoodApiKey.isEmpty) {
      _showSnack('API 키가 설정되지 않았습니다');
      return;
    }

    if (_items.isEmpty) {
      _showSnack('식재료를 먼저 등록하세요');
      return;
    }

    final filtered = _items
        .map((e) => e.name.trim())
        .where((name) => name.length >= 2 && !_isIgnored(name))
        .toSet()
        .toList();

    if (filtered.isEmpty) {
      _showSnack('유효한 식재료가 없습니다');
      return;
    }

    final shuffled = List<String>.from(filtered)..shuffle();
    final selected = shuffled.take(min(2, shuffled.length)).toList();

    setState(() {
      _isFetching = true;
      _recipes = [];
      _hasSearched = false;
      _searchedKeywords = '';
    });

    try {
      final unique = <String, Map<String, dynamic>>{};
      final usedKeywords = <String>[];

      // 복합 검색
      if (selected.length >= 2) {
        final combined = selected.join(' ');
        final results = await _search(combined);
        final splitResults = results
            .map((r) => {...r, 'searched_keywords': selected.toList()})
            .toList();
        _addToUnique(unique, splitResults);
        if (results.isNotEmpty) {
          for (final k in selected) {
            if (!usedKeywords.contains(k)) usedKeywords.add(k);
          }
        }
      }

      // 단일 검색
      for (final keyword in selected) {
        final results = await _search(keyword);
        _addToUnique(unique, results);
        if (results.isNotEmpty && !usedKeywords.contains(keyword)) {
          usedKeywords.add(keyword);
        }
      }

      // 10개 미만이면 순차 검색
      if (unique.length < 10) {
        final remaining = shuffled.where((k) => !selected.contains(k)).toList();

        for (final keyword in remaining.take(5)) {
          if (unique.length >= 10) break;
          final results = await _search(keyword);
          _addToUnique(unique, results);
          if (results.isNotEmpty && !usedKeywords.contains(keyword)) {
            usedKeywords.add(keyword);
          }
        }
      }

      if (!mounted) return;

      final allRecipes = unique.values.toList();
      allRecipes.shuffle();

      setState(() {
        _recipes = allRecipes.take(20).toList();
        _hasSearched = true;
        _searchedKeywords = usedKeywords.join(', ');
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _recipes = [];
        _hasSearched = true;
      });
      _showSnack('요청 시간이 초과되었습니다');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _recipes = [];
        _hasSearched = true;
      });
      _showSnack('네트워크 오류가 발생했습니다');
      debugPrint('레시피 불러오기 실패: $e');
    } finally {
      if (mounted) {
        setState(() => _isFetching = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('레시피 추천')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: ElevatedButton(
                    onPressed: (_isFetching || _items.isEmpty)
                        ? null
                        : _fetchRecipes,
                    child: const Text('레시피 추천 받기'),
                  ),
                ),
                if (_hasSearched && _searchedKeywords.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '"$_searchedKeywords" 로 검색된 레시피',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                Expanded(
                  child: _isFetching
                      ? const Center(child: CircularProgressIndicator())
                      : _recipes.isEmpty
                      ? Center(
                          child: Text(
                            _hasSearched
                                ? '추천할 레시피가 없습니다'
                                : '버튼을 눌러 레시피를 추천받으세요',
                          ),
                        )
                      : ListView.builder(
                          itemCount: _recipes.length,
                          itemBuilder: (context, index) {
                            final recipe = _recipes[index];
                            final imageUrl =
                                (recipe['ATT_FILE_NO_MAIN'] ??
                                        recipe['MANUAL_IMG01'] ??
                                        '')
                                    as String;
                            final name = recipe['RCP_NM'] ?? '';
                            final keywords =
                                (recipe['searched_keywords'] as List?)?.join(
                                  ', ',
                                ) ??
                                '';

                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              child: ListTile(
                                leading: imageUrl.isNotEmpty
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          imageUrl,
                                          width: 60,
                                          height: 60,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, _, _) =>
                                              const Icon(
                                                Icons.restaurant,
                                                size: 40,
                                              ),
                                        ),
                                      )
                                    : const Icon(Icons.restaurant, size: 40),
                                title: Text(
                                  name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  '"$keywords" 포함 레시피',
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 12,
                                  ),
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => RecipeDetailScreen(
                                        recipe: recipe,
                                        myIngredients: _items
                                            .map((e) => e.name)
                                            .join(', '),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
