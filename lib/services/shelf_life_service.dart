import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../utils/ingredient_name.dart';

enum ShelfLifeSource { item, similar, category, fallback }

/// 계산 결과: 며칠인지 + 어디서 나온 값인지
class ShelfLifeEstimate {
  final int days;
  final ShelfLifeSource source;
  final String? baseName; // 기준이 된 품목 이름 (item, similar)
  final String? category; // 일반 기준일 때 카테고리

  const ShelfLifeEstimate(
    this.days,
    this.source, {
    this.baseName,
    this.category,
  });

  /// base 날짜부터 days일 뒤
  DateTime expirationFrom(DateTime base) =>
      DateTime(base.year, base.month, base.day + days);

  /// 오늘부터 days일 뒤
  DateTime get expirationDate => expirationFrom(DateTime.now());

  /// 화면 표시용 문구
  String get label => switch (source) {
    ShelfLifeSource.item => '$baseName 기준',
    ShelfLifeSource.similar => '$baseName 기준 · 비슷한 재료',
    ShelfLifeSource.category => '$category 일반 기준',
    ShelfLifeSource.fallback => '기본값',
  };
}

class _Entry {
  final String name; // 표의 품목 이름 (비슷한 재료면 기준 품목 이름)
  final Map<String, int> days;
  final bool similar;
  _Entry(this.name, this.days, {this.similar = false});
}

/// 재료 이름·카테고리·보관 방법으로 소비기한 계산 (assets/data/shelf_life.json)
class ShelfLifeService {
  static final ShelfLifeService _instance = ShelfLifeService._();
  factory ShelfLifeService() => _instance;
  ShelfLifeService._();

  static const int fallbackDays = 7;
  static const storages = ['냉장', '냉동', '실온'];

  final Map<String, _Entry> _byName = {};
  List<String> _keysLongestFirst = [];
  Map<String, Map<String, int>> _categoryDefaults = {};
  bool _loaded = false;

  /// 앱 시작 시 한 번 호출
  Future<void> load() async {
    if (_loaded) return;
    try {
      final raw = await rootBundle.loadString('assets/data/shelf_life.json');
      final data = jsonDecode(raw) as Map<String, dynamic>;

      Map<String, int> toDays(dynamic m) => (m as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, (v as num).toInt()),
      );

      final itemsByName = <String, _Entry>{};
      void register(List names, _Entry entry) {
        for (final n in names) {
          _byName[normalizeIngredientName(n as String)] = entry;
        }
      }

      for (final item in (data['items'] as List)) {
        final entry = _Entry(item['name'] as String, toDays(item['days']));
        itemsByName[entry.name] = entry;
        register([item['name'], ...(item['aliases'] as List)], entry);
      }

      // 비슷한 재료: 기준 품목의 값을 그대로 쓰되 similar로 표시
      for (final s in (data['similar'] as List? ?? [])) {
        final base = itemsByName[s['similar_to']];
        if (base == null) continue;
        register([
          s['name'],
          ...(s['aliases'] as List),
        ], _Entry(base.name, base.days, similar: true));
      }

      _keysLongestFirst = _byName.keys.toList()
        ..sort((a, b) => b.length.compareTo(a.length));
      _categoryDefaults = (data['category_defaults'] as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, toDays(v)));
      _loaded = true;
    } catch (e) {
      debugPrint('소비기한 기준표 불러오기 실패: $e');
    }
  }

  _Entry? _find(String name) {
    final key = normalizeIngredientName(name);
    if (key.isEmpty) return null;
    final exact = _byName[key];
    if (exact != null) return exact;
    // 앞에 꾸밈말이 붙은 경우만 (적양파 → 양파, 고등어회 ✕)
    for (final k in _keysLongestFirst) {
      if (k.length >= 2 && key.endsWith(k)) return _byName[k];
    }
    return null;
  }

  ShelfLifeEstimate estimate({
    required String name,
    required String category,
    required String storage,
  }) {
    final entry = _find(name);
    final itemDays = entry?.days[storage];
    if (entry != null && itemDays != null) {
      return ShelfLifeEstimate(
        itemDays,
        entry.similar ? ShelfLifeSource.similar : ShelfLifeSource.item,
        baseName: entry.name,
      );
    }
    final catDays = _categoryDefaults[category]?[storage];
    if (catDays != null) {
      return ShelfLifeEstimate(
        catDays,
        ShelfLifeSource.category,
        category: category,
      );
    }
    return const ShelfLifeEstimate(fallbackDays, ShelfLifeSource.fallback);
  }

  /// 표에 값이 있는 보관 방법. 재료를 못 찾았거나 세 가지 다 있으면 빈 집합
  /// (일부만 있을 때 "(추천)" 표시용)
  Set<String> recommendedStorages(String name) {
    final entry = _find(name);
    if (entry == null) return {};
    final available = storages.where(entry.days.containsKey).toSet();
    return available.length == storages.length ? {} : available;
  }
}
