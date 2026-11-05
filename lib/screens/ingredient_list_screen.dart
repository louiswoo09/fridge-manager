import 'dart:async';
import 'package:flutter/material.dart';
import '../models/ingredient.dart';
import '../services/ingredient_service.dart';
import 'add_ingredient_screen.dart';
import 'edit_ingredient_screen.dart';
import 'profile_screen.dart';
import '../services/notification_service.dart';
import 'trash_screen.dart';
import '../services/fridge_analysis_service.dart';
import '../services/ingredient_icon_mapper.dart';
import '../main.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/fridge_service.dart';
import '../services/cart_service.dart';
import '../services/gemini_cache_service.dart';
import '../services/api_client.dart';
import 'package:image_picker/image_picker.dart';
import '../services/ingredient_recognition_service.dart';
import 'recognition_review_screen.dart';
import 'photo_collect_screen.dart';
import '../services/product_name_formatter.dart';

class IngredientListScreen extends StatefulWidget {
  final OnRequestRecipeKeywordSearch? onRequestRecipeKeywordSearch;

  const IngredientListScreen({super.key, this.onRequestRecipeKeywordSearch});

  @override
  State<IngredientListScreen> createState() => _IngredientListScreenState();
}

class _IngredientListScreenState extends State<IngredientListScreen> {
  // 직접 추가 화면과 같은 선택지
  static const _categories = ['채소', '육류', '유제품', '과일', '해산물', '기타'];
  static const _units = ['개', 'g', 'ml', 'L', '팩'];
  static const _storages = ['냉장', '냉동', '실온'];

  final IngredientService _service = IngredientService();
  final FridgeService _fridgeService = FridgeService();
  StreamSubscription<List<Ingredient>>? _subscription;
  StreamSubscription<String?>? _activeFridgeIdSub;
  String _activeFridgeName = '냉장고 매니저';
  bool _isDeleteMode = false;
  bool _isMenuOpen = false;
  bool _isLoading = true;
  bool _isSearching = false;
  bool _notificationScheduled = false;
  final Set<String> _selectedIds = {};
  List<Ingredient> _items = [];
  bool _isAnalysisExpanded = true;

  final FridgeAnalysisService _analysisService = FridgeAnalysisService();
  FridgeAnalysis? _analysis;
  bool _isAnalyzing = false;
  String? _analysisError;
  String? _analysisNotice; // 실패가 아닌 안내 (예: 분석할 재료 없음)

  String _selectedCategory = '전체';
  String _selectedStorage = '전체';
  int? _selectedExpiry;
  String _searchQuery = '';

  final TextEditingController _searchController = TextEditingController();

  // ───────────────────────── 목록 계산 ─────────────────────────

  List<Ingredient> get _filteredItems {
    return _items.where((item) {
      final categoryMatch =
          _selectedCategory == '전체' || item.category == _selectedCategory;
      final storageMatch =
          _selectedStorage == '전체' || item.storage == _selectedStorage;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final expiry = DateTime(
        item.expirationDate.year,
        item.expirationDate.month,
        item.expirationDate.day,
      );
      final days = expiry.difference(today).inDays;
      final expiryMatch = _selectedExpiry == null
          ? true
          : _selectedExpiry == -1
          ? days < 0
          : days <= _selectedExpiry!;
      final searchMatch =
          _searchQuery.isEmpty ||
          item.name.toLowerCase().contains(_searchQuery.toLowerCase());
      return categoryMatch && storageMatch && expiryMatch && searchMatch;
    }).toList();
  }

  List<Ingredient> get _notExpiredItems {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _items.where((item) {
      final exp = DateTime(
        item.expirationDate.year,
        item.expirationDate.month,
        item.expirationDate.day,
      );
      return !exp.isBefore(today);
    }).toList();
  }

  List<Ingredient> _getImminentIngredients() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final threshold = today.add(const Duration(days: 3));

    return _items.where((item) {
      final exp = DateTime(
        item.expirationDate.year,
        item.expirationDate.month,
        item.expirationDate.day,
      );
      return !exp.isBefore(today) && !exp.isAfter(threshold);
    }).toList()..sort((a, b) => a.expirationDate.compareTo(b.expirationDate));
  }

  bool get _hasFilter =>
      _selectedCategory != '전체' ||
      _selectedStorage != '전체' ||
      _selectedExpiry != null;

  bool _isExpired(Ingredient e) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final exp = DateTime(
      e.expirationDate.year,
      e.expirationDate.month,
      e.expirationDate.day,
    );
    return exp.isBefore(today);
  }

  /// 이름이 같은 재료끼리 묶음
  /// 묶음 안: 남은 것(임박순) → 지난 것 / 묶음끼리: 대표(첫 건) 소비기한 순
  List<List<Ingredient>> _groupByName(List<Ingredient> items) {
    final groups = <String, List<Ingredient>>{};
    for (final item in items) {
      groups.putIfAbsent(item.name.trim(), () => []).add(item);
    }

    final result = groups.values.map((lots) {
      final fresh = lots.where((e) => !_isExpired(e)).toList();
      final expired = lots.where(_isExpired).toList();
      return [...fresh, ...expired];
    }).toList();

    result.sort(
      (a, b) => a.first.expirationDate.compareTo(b.first.expirationDate),
    );
    return result;
  }
  // ───────────────────────── 생명주기 ─────────────────────────

  @override
  void initState() {
    super.initState();
    _service.cleanOldDeletedItems();

    // 활성 냉장고 변경 감지 → 화면 갱신
    _activeFridgeIdSub = _fridgeService.watchActiveFridgeId().listen((id) {
      if (id == null || !mounted) return;
      _onActiveFridgeChanged(id);
    });
  }

  Future<void> _onActiveFridgeChanged(String fridgeId) async {
    // Service 캐시 무효화
    _service.invalidateCache();
    CartService().invalidateCache();
    _analysisService.invalidateCache();
    GeminiCacheService().clear();

    // 활성 냉장고 이름 가져오기
    final fridgeDoc = await FirebaseFirestore.instance
        .collection('fridges')
        .doc(fridgeId)
        .get();
    if (!mounted) return;

    final name = fridgeDoc.data()?['name']?.toString() ?? '냉장고';

    // 기존 구독 해제
    await _subscription?.cancel();

    // 상태 초기화
    setState(() {
      _activeFridgeName = name;
      _items = [];
      _isLoading = true;
      _notificationScheduled = false;
      _analysis = null; // 다른 냉장고 분석 결과 제거
      _analysisError = null;
      _analysisNotice = null;
    });

    // 새 식재료 구독 시작
    _subscription = _service.getIngredients().listen(
      (items) {
        if (!mounted) return;
        setState(() {
          _items = List.from(items)
            ..sort((a, b) => a.expirationDate.compareTo(b.expirationDate));
          _selectedIds.removeWhere((id) => !_items.any((e) => e.id == id));
          _isLoading = false;
        });
        if (!_notificationScheduled) {
          _notificationScheduled = true;
          NotificationService.scheduleAllNotifications(_items);
        }
        _fetchAnalysis();
      },
      onError: (error) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('데이터 불러오기 실패')));
        });
      },
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _activeFridgeIdSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // ───────────────────────── 공통 도우미 ─────────────────────────

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _dDayText(DateTime expiration, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final expiry = DateTime(expiration.year, expiration.month, expiration.day);
    final days = expiry.difference(today).inDays;
    if (days < 0) return '${days.abs()}일 지남';
    if (days == 0) return 'D-Day';
    return 'D-$days';
  }

  Color _getExpiryColor(DateTime expiry, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final expiryDate = DateTime(expiry.year, expiry.month, expiry.day);
    final days = expiryDate.difference(today).inDays;
    if (days < 0) return Colors.grey;
    if (days <= 3) return Colors.red;
    if (days <= 7) return Colors.orange;
    return Colors.green;
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _ingredientAvatar(Ingredient item, {double radius = 24}) =>
      CircleAvatar(
        backgroundColor: Colors.grey[200],
        radius: radius,
        child: IngredientIconMapper.build(
          name: item.name,
          category: item.category,
          size: radius,
        ),
      );

  Widget _deleteBackground() => Container(
    alignment: Alignment.centerRight,
    padding: const EdgeInsets.only(right: 20),
    color: Colors.red[400],
    child: const Icon(Icons.delete, color: Colors.white),
  );

  /// 카드를 펼치거나 접을 때 열려 있던 메뉴 닫기
  void _closeMenuAfterFrame() {
    if (!_isMenuOpen) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _isMenuOpen = false);
    });
  }

  void _openEdit(Ingredient item) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EditIngredientScreen(ingredient: item)),
    );
  }

  /// 밀어서 삭제할 때 확인 → 휴지통으로
  Future<bool> _confirmAndSoftDelete(Ingredient item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('삭제 확인'),
        content: Text('${item.name}을(를) 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return false;

    try {
      await _service.softDeleteIngredient(item.id);
      _snack('${item.name} 삭제됨');
      return true;
    } catch (e) {
      return false;
    }
  }

  // ───────────────────────── 창 안에서 쓰는 위젯 ─────────────────────────

  Widget _dialogDropdown(
    String label,
    String value,
    List<String> options,
    ValueChanged<String> onChanged,
  ) {
    return Row(
      children: [
        Text(label),
        const Spacer(),
        DropdownButton<String>(
          value: options.contains(value) ? value : options.first,
          items: options
              .map((o) => DropdownMenuItem(value: o, child: Text(o)))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ],
    );
  }

  Widget _dialogDateRow(
    BuildContext ctx,
    DateTime value,
    ValueChanged<DateTime> onPicked,
  ) {
    return Row(
      children: [
        const Text('소비기한'),
        const Spacer(),
        TextButton.icon(
          onPressed: () async {
            final picked = await showDatePicker(
              context: ctx,
              initialDate: value,
              firstDate: DateTime(2000),
              lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
            );
            if (picked != null) onPicked(picked);
          },
          icon: const Icon(Icons.event, size: 18),
          label: Text(_formatDate(value)),
        ),
      ],
    );
  }

  // ───────────────────────── 합치기 · 나누기 ─────────────────────────

  /// 묶음 안에서 재료 고르기
  /// multiple: true → 합치기용 (2건 이상), false → 나누기용 (1건, 누르면 바로 선택)
  Future<List<Ingredient>?> _pickLots(
    List<Ingredient> lots, {
    required bool multiple,
  }) {
    final selected = <String>{};
    final now = DateTime.now();

    return showDialog<List<Ingredient>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          void toggle(String id) => setDialog(() {
            if (selected.contains(id)) {
              selected.remove(id);
            } else {
              selected.add(id);
            }
          });

          return AlertDialog(
            title: Text(multiple ? '합칠 재료 선택' : '나눌 재료 선택'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: lots.map((item) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: _ingredientAvatar(item, radius: 16),
                    title: Text(
                      '${item.quantity}${item.unit} · ${item.storage}',
                    ),
                    subtitle: Text(
                      '${_formatDate(item.expirationDate)}  ${_dDayText(item.expirationDate, now)}',
                    ),
                    trailing: multiple
                        ? Checkbox(
                            value: selected.contains(item.id),
                            onChanged: (_) => toggle(item.id),
                          )
                        : const Icon(Icons.chevron_right),
                    onTap: () {
                      if (!multiple) {
                        Navigator.pop(ctx, [item]);
                        return;
                      }
                      toggle(item.id);
                    },
                  );
                }).toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('취소'),
              ),
              if (multiple)
                TextButton(
                  onPressed: selected.length < 2
                      ? null
                      : () => Navigator.pop(
                          ctx,
                          lots.where((e) => selected.contains(e.id)).toList(),
                        ),
                  child: Text(
                    selected.length < 2
                        ? '2건 이상 골라주세요'
                        : '다음 (${selected.length}건)',
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// 나누기: 수량·단위·보관 방법·소비기한을 정해서 일부를 떼어냄
  Future<void> _openSplit(Ingredient item) async {
    var qtyText = '${item.quantity ~/ 2 > 0 ? item.quantity ~/ 2 : 1}';
    var remainText = '';
    var unit = item.unit;
    var remainUnit = item.unit;
    var storage = item.storage;
    var expiration = item.expirationDate;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text('${item.name} 나누기'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item.quantity}${item.unit} 중 일부를 따로 보관해요',
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: qtyText,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '나눌 수량',
                          isDense: true,
                        ),
                        onChanged: (v) => qtyText = v,
                      ),
                    ),
                    const SizedBox(width: 12),
                    DropdownButton<String>(
                      value: _units.contains(unit) ? unit : _units.first,
                      items: _units
                          .map(
                            (u) => DropdownMenuItem(value: u, child: Text(u)),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setDialog(() => unit = v);
                      },
                    ),
                  ],
                ),
                // 단위를 바꾸면 원래 재료가 얼마 남는지 계산할 수 없어서 직접 입력
                if (unit != item.unit) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          initialValue: remainText,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: '원래 재료에 남는 수량',
                            helperText: '단위가 달라서 남는 양을 직접 입력해주세요',
                            isDense: true,
                          ),
                          onChanged: (v) => remainText = v,
                        ),
                      ),
                      const SizedBox(width: 12),
                      DropdownButton<String>(
                        value: remainUnit,
                        items: _units
                            .map(
                              (u) => DropdownMenuItem(value: u, child: Text(u)),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setDialog(() => remainUnit = v);
                        },
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                _dialogDropdown(
                  '보관 방법',
                  storage,
                  _storages,
                  (v) => setDialog(() => storage = v),
                ),
                _dialogDateRow(
                  ctx,
                  expiration,
                  (d) => setDialog(() => expiration = d),
                ),
                const Text(
                  '냉동 보관하면 소비기한을 늘려주세요',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('나누기'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;

    final qty = int.tryParse(qtyText.trim()) ?? 0;
    if (qty <= 0) {
      _snack('나눌 수량을 입력해주세요');
      return;
    }

    final int remaining;
    final String finalRemainUnit;
    if (unit == item.unit) {
      remaining = item.quantity - qty;
      finalRemainUnit = item.unit; // 단위가 같으면 원래 단위 그대로
      if (remaining <= 0) {
        _snack('나눌 수량은 ${item.quantity}${item.unit}보다 적어야 해요');
        return;
      }
    } else {
      remaining = int.tryParse(remainText.trim()) ?? 0;
      finalRemainUnit = remainUnit;
      if (remaining <= 0) {
        _snack('원래 재료에 남는 수량을 입력해주세요');
        return;
      }
    }

    try {
      await _service.splitIngredient(
        item,
        remainingQuantity: remaining,
        remainingUnit: finalRemainUnit,
        quantity: qty,
        unit: unit,
        storage: storage,
        expirationDate: expiration,
      );
      _snack('$qty$unit를 나눠서 $storage 보관했어요');
    } catch (e) {
      _snack('나누기 실패: $e');
    }
  }

  /// 합치기: 고른 재료들을 하나로, 결과(수량·단위·카테고리·보관·소비기한)는 직접 정함
  Future<void> _openMerge(List<Ingredient> picked) async {
    // 가장 임박한 건을 남기고 나머지를 합침
    final sorted = [...picked]
      ..sort((a, b) => a.expirationDate.compareTo(b.expirationDate));
    final target = sorted.first;
    final sameUnit = picked.map((e) => e.unit).toSet().length == 1;

    var qtyText = sameUnit
        ? '${picked.fold<int>(0, (s, e) => s + e.quantity)}'
        : '';
    var unit = target.unit;
    var category = target.category;
    var storage = target.storage;
    var expiration = target.expirationDate; // 가장 짧은 소비기한

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text('${target.name.trim()} 합치기'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '합칠 재료',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 4),
                ...sorted.map(
                  (e) => Text(
                    '• ${e.quantity}${e.unit} · ${e.storage} · ${_formatDate(e.expirationDate)}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                const Divider(height: 24),
                const Text(
                  '합친 결과',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        initialValue: qtyText,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: '수량',
                          helperText: sameUnit ? null : '단위가 달라서 직접 입력해주세요',
                          isDense: true,
                        ),
                        onChanged: (v) => qtyText = v,
                      ),
                    ),
                    const SizedBox(width: 12),
                    DropdownButton<String>(
                      value: _units.contains(unit) ? unit : _units.first,
                      items: _units
                          .map(
                            (u) => DropdownMenuItem(value: u, child: Text(u)),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setDialog(() => unit = v);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _dialogDropdown(
                  '카테고리',
                  category,
                  _categories,
                  (v) => setDialog(() => category = v),
                ),
                _dialogDropdown(
                  '보관 방법',
                  storage,
                  _storages,
                  (v) => setDialog(() => storage = v),
                ),
                _dialogDateRow(
                  ctx,
                  expiration,
                  (d) => setDialog(() => expiration = d),
                ),
                const Text(
                  '소비기한은 가장 짧은 날짜로 채워져 있어요',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('합치기'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;

    final qty = int.tryParse(qtyText.trim()) ?? 0;
    if (qty <= 0) {
      _snack('합친 수량을 입력해주세요');
      return;
    }

    final others = picked.where((e) => e.id != target.id).toList();
    final result = target.copyWith(
      quantity: qty,
      unit: unit,
      category: category,
      storage: storage,
      expirationDate: expiration,
    );

    try {
      await _service.mergeIngredients(target, others, result);
      _snack('${picked.length}건을 하나로 합쳤어요');
    } catch (e) {
      _snack('합치기 실패: $e');
    }
  }

  // ───────────────────────── 필터 ─────────────────────────

  void _showFilterSheet() {
    String tempCategory = _selectedCategory;
    String tempStorage = _selectedStorage;
    int? tempExpiry = _selectedExpiry;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '필터',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _selectedCategory = '전체';
                            _selectedStorage = '전체';
                            _selectedExpiry = null;
                          });
                          setSheetState(() {});
                        },
                        child: const Text('초기화'),
                      ),
                    ],
                  ),
                  const Divider(),
                  const Text(
                    '식재료 분류',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: ['전체', ..._categories]
                        .map(
                          (c) => FilterChip(
                            label: Text(c),
                            selected: _selectedCategory == c,
                            onSelected: (_) {
                              setState(() => _selectedCategory = c);
                              setSheetState(() {});
                            },
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '보관 유형',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: ['전체', ..._storages]
                        .map(
                          (s) => FilterChip(
                            label: Text(s),
                            selected: _selectedStorage == s,
                            onSelected: (_) {
                              setState(() => _selectedStorage = s);
                              setSheetState(() {});
                            },
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '소비기한',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      _sheetExpiryChip('전체', null, setSheetState),
                      _sheetExpiryChip('3일 이내', 3, setSheetState),
                      _sheetExpiryChip('7일 이내', 7, setSheetState),
                      _sheetExpiryChip('14일 이내', 14, setSheetState),
                      _sheetExpiryChip('만료', -1, setSheetState),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _selectedCategory = tempCategory;
                            _selectedStorage = tempStorage;
                            _selectedExpiry = tempExpiry;
                          });
                          Navigator.pop(context);
                        },
                        child: const Text('취소'),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('확인'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _sheetExpiryChip(String label, int? value, StateSetter setSheetState) {
    return FilterChip(
      label: Text(label),
      selected: _selectedExpiry == value,
      onSelected: (_) {
        setState(() => _selectedExpiry = value);
        setSheetState(() {});
      },
    );
  }

  // ───────────────────────── 분석 카드 ─────────────────────────

  Future<void> _fetchAnalysis({bool forceRefresh = false}) async {
    if (_items.isEmpty) {
      await _analysisService.clearCurrent();
      if (!mounted) return;
      setState(() {
        _analysis = null;
        _analysisError = null;
        _analysisNotice = null;
      });
      return;
    }

    // 재료는 있지만 전부 소비기한이 지남 → 서버에 보내지 않고 안내
    if (_notExpiredItems.isEmpty) {
      await _analysisService.clearCurrent();
      if (!mounted) return;
      setState(() {
        _analysis = null;
        _analysisError = null;
        _analysisNotice = '소비기한이 남은 재료가 없어 분석할 수 없어요';
      });
      return;
    }

    final cached = _analysisService.cached;
    if (cached != null && !forceRefresh) {
      if (!mounted) return;
      setState(() {
        _analysis = cached;
        _analysisError = null;
        _analysisNotice = null;
      });
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _analysisError = null;
      _analysisNotice = null;
    });

    try {
      final imminent = _getImminentIngredients();
      final result = await _analysisService.analyze(
        ingredients: _notExpiredItems,
        imminentIngredients: imminent,
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() => _analysis = result);
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _analysisError = friendlyError(e, fallback: '분석 실패. 다시 시도해주세요'),
      );
      debugPrint('분석 실패: $e');
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  // ───────────────────────── 사진으로 추가 ─────────────────────────

  Future<void> _startPhotoRecognition() async {
    setState(() => _isMenuOpen = false);

    // 1. 사진 모으기 (앱 안 카메라 + 앨범, 최대 5장)
    final photos = await Navigator.push<List<XFile>>(
      context,
      MaterialPageRoute(builder: (_) => const PhotoCollectScreen()),
    );
    if (photos == null || photos.isEmpty || !mounted) return;

    // 2. 인식 중 안내 (닫을 수 없게)
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Expanded(
              child: Text('사진 ${photos.length}장에서 식재료를 찾는 중이에요\n잠시만 기다려주세요'),
            ),
          ],
        ),
      ),
    );

    try {
      final result = await IngredientRecognitionService.recognize(photos);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // 안내 닫기

      // 찾은 게 없으면 안내만
      if (result.items.isEmpty) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('식재료를 찾지 못했어요'),
            contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
            actionsPadding: const EdgeInsets.fromLTRB(24, 0, 16, 12),
            content: const Text('식재료나 영수증이 잘 보이게 다시 찍어주세요.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('확인'),
              ),
            ],
          ),
        );
        return;
      }

      // 확인·수정 화면
      final ingredients = await Navigator.push<List<Ingredient>>(
        context,
        MaterialPageRoute(
          builder: (_) => RecognitionReviewScreen(
            result: result,
            photos: photos,
            existingItems: _items,
          ),
        ),
      );
      if (ingredients == null || ingredients.isEmpty || !mounted) return;

      // 일괄 등록 (똑같은 재료가 있으면 수량 합치기)
      try {
        final merged = await _service.addMany(ingredients);
        final added = ingredients.length - merged;
        if (!mounted) return;

        final message = merged == 0
            ? '$added개 재료를 등록했어요'
            : added == 0
            ? '$merged개 재료를 동일한 재료와 합쳤어요'
            : '$added개 재료를 등록하고 $merged개는 동일한 재료와 합쳤어요';

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
        await _offerCartCleanup(ingredients);
      } catch (e) {
        _snack('등록 중 오류: $e');
      }
    } catch (e) {
      debugPrint('식재료 인식 실패: $e');
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // 안내 닫기
      _snack(friendlyError(e, fallback: '식재료 인식에 실패했어요'));
    }
  }

  // ───────────────────────── 담아놓기 정리 제안 ─────────────────────────

  /// 비교용 이름 정리: 괄호 내용 제거, 공백 제거, 표기 통일
  String _baseName(String name) => _normalizeName(
    name.replaceAll(RegExp(r'\([^)]*\)'), '').replaceAll(' ', '').trim(),
  );

  /// 담아놓기(KAMIS) 이름의 비교 후보: "포도/샤인머스켓" → [포도, 샤인머스캣]
  List<String> _cartNameCandidates(String display) =>
      display.split('/').map(_baseName).where((n) => n.isNotEmpty).toList();

  /// 자주 섞여 쓰이는 표기 → 하나로 통일 (비교할 때만 사용)
  static const _nameAliases = {
    '메론': '멜론',
    '샤인머스켓': '샤인머스캣',
    '소세지': '소시지',
    '쭈꾸미': '주꾸미',
    '브로컬리': '브로콜리',
    '참다래': '키위',
    '케찹': '케첩',
  };

  String _normalizeName(String name) {
    var result = name;
    _nameAliases.forEach((from, to) => result = result.replaceAll(from, to));
    return result;
  }

  bool _isNameMatch(String a, String b) {
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b) return true;
    final shorter = a.length <= b.length ? a : b;
    final longer = a.length <= b.length ? b : a;
    return shorter.length >= 2 && longer.endsWith(shorter);
  }

  /// 등록한 재료와 이름이 맞는 담아놓기 품목이 있으면 빼기를 제안
  Future<void> _offerCartCleanup(List<Ingredient> registered) async {
    final List<Map<String, dynamic>> cart;
    try {
      cart = await CartService().getItems();
    } catch (_) {
      return; // 정리 제안은 부가 기능이라 실패해도 조용히 넘어감
    }
    if (cart.isEmpty || !mounted) return;

    final names = registered
        .map((e) => _baseName(e.name))
        .where((n) => n.isNotEmpty)
        .toSet();

    // (담아놓기 품목, 표시 이름, 맞은 재료 이름)
    final matches = <({String key, String display, String matched})>[];
    for (final c in cart) {
      final display = (c['displayName'] ?? c['productName'] ?? '').toString();
      final candidates = _cartNameCandidates(display);
      String? matched;
      for (final n in names) {
        if (candidates.any((cand) => _isNameMatch(cand, n))) {
          matched = n;
          break;
        }
      }
      if (matched != null) {
        matches.add((
          key: c['_key'] as String,
          display: display,
          matched: matched,
        ));
      }
    }
    if (matches.isEmpty || !mounted) return;

    final selected = matches.map((m) => m.key).toSet(); // 기본은 전부 선택

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('담아놓기에 있던 재료를 샀나요?'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: matches
                  .map(
                    (m) => CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: selected.contains(m.key),
                      onChanged: (v) => setDialog(() {
                        if (v == true) {
                          selected.add(m.key);
                        } else {
                          selected.remove(m.key);
                        }
                      }),
                      title: Text(m.display),
                      subtitle: Text('등록한 "${m.matched}"'),
                    ),
                  )
                  .toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('그대로 두기'),
            ),
            TextButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: const Text('담아놓기에서 빼기'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;

    try {
      await CartService().removeByKeys(selected);
      _snack('담아놓기에서 ${selected.length}개를 뺐어요');
    } catch (e) {
      _snack('담아놓기 정리 실패: $e');
    }
  }

  // ───────────────────────── 삭제 모드 ─────────────────────────

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('삭제 확인'),
        content: Text('선택한 ${_selectedIds.length}개의 식재료를 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final deletedCount = _selectedIds.length;
    final deletedIds = Set<String>.from(_selectedIds);

    try {
      await _service.softDeleteMany(deletedIds);
      if (!mounted) return;
      setState(() {
        _selectedIds.clear();
        _isDeleteMode = false;
      });
      _snack('$deletedCount개 삭제됨');
    } catch (e) {
      _snack('삭제 중 오류: $e');
    }
  }

  // ───────────────────────── 화면 ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isDeleteMode ? '${_selectedIds.length}개 선택됨' : _activeFridgeName,
        ),
        bottom: _isSearching
            ? PreferredSize(
                preferredSize: const Size.fromHeight(56),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: '재료명 검색',
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      filled: true,
                      fillColor: const Color.fromARGB(15, 158, 158, 158),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                      ),
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                ),
              )
            : null,
        actions: _isDeleteMode
            ? [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selectedIds.clear();
                      _isDeleteMode = false;
                    });
                  },
                  child: const Text('취소', style: TextStyle(color: Colors.red)),
                ),
                TextButton(
                  onPressed: _selectedIds.isEmpty ? null : _deleteSelected,
                  child: const Text('삭제 완료'),
                ),
              ]
            : [
                IconButton(
                  icon: Icon(_isSearching ? Icons.close : Icons.search),
                  onPressed: () {
                    setState(() {
                      _isSearching = !_isSearching;
                      if (!_isSearching) {
                        _searchQuery = '';
                        _searchController.clear();
                      }
                    });
                  },
                ),
                IconButton(
                  icon: Badge(
                    isLabelVisible: _hasFilter,
                    child: const Icon(Icons.tune),
                  ),
                  onPressed: _showFilterSheet,
                ),
                IconButton(
                  icon: const Icon(Icons.person),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ProfileScreen(),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const TrashScreen(),
                    ),
                  ),
                ),
              ],
      ),
      body: _buildBody(),
      floatingActionButton: _isDeleteMode
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (_isMenuOpen) ...[
                  _menuButton(
                    heroTag: 'ingredient_add',
                    icon: Icons.add,
                    label: '재료 추가',
                    onPressed: () {
                      setState(() => _isMenuOpen = false);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AddIngredientScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  _menuButton(
                    heroTag: 'ingredient_photo',
                    icon: Icons.photo_camera,
                    label: '사진으로 추가',
                    onPressed: _startPhotoRecognition,
                  ),
                  const SizedBox(height: 8),
                  _menuButton(
                    heroTag: 'ingredient_delete',
                    icon: Icons.delete,
                    label: '재료 삭제',
                    onPressed: () {
                      setState(() {
                        _isMenuOpen = false;
                        _isDeleteMode = true;
                        _selectedIds.clear();
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                ],
                FloatingActionButton(
                  heroTag: 'ingredient_menu',
                  onPressed: () => setState(() => _isMenuOpen = !_isMenuOpen),
                  child: Icon(_isMenuOpen ? Icons.close : Icons.menu),
                ),
              ],
            ),
    );
  }

  /// 메뉴 버튼 (아이콘 왼쪽 + 글자 가운데 정렬로 크기 통일)
  Widget _menuButton({
    required String heroTag,
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return FloatingActionButton.extended(
      heroTag: heroTag,
      onPressed: onPressed,
      icon: Icon(icon),
      label: SizedBox(
        width: 88,
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          softWrap: false,
        ),
      ),
    );
  }

  Widget _buildAnalysisCard() {
    if (_analysisNotice != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.grey.shade600, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _analysisNotice!,
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_isAnalyzing && _analysis == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('냉장고 분석 중...'),
            ],
          ),
        ),
      );
    }

    if (_analysisError != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.orange, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(_analysisError!)),
              TextButton(
                onPressed: () => _fetchAnalysis(forceRefresh: true),
                child: const Text('재시도'),
              ),
            ],
          ),
        ),
      );
    }

    if (_analysis == null) return const SizedBox.shrink();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, _isAnalysisExpanded ? 4 : 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더 — 클릭하면 접기/펼치기
            InkWell(
              onTap: () =>
                  setState(() => _isAnalysisExpanded = !_isAnalysisExpanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.auto_awesome,
                      size: 18,
                      color: Colors.indigo,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      '냉장고 분석',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      _isAnalysisExpanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      size: 20,
                      color: Colors.indigo,
                    ),
                  ],
                ),
              ),
            ),
            // 펼친 상태에서만 분석 내용 표시
            if (_isAnalysisExpanded) ...[
              const SizedBox(height: 8),
              Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildAnalysisRow('재료 균형', _analysis!.status),
                      const SizedBox(height: 4),
                      _buildAnalysisRow('추천 요리', _analysis!.suggestion),
                      if (_analysis!.imminentNames.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        _buildAnalysisRow(
                          '임박 재료',
                          _analysis!.imminentNames.join(', '),
                          highlight: true,
                        ),
                      ],
                    ],
                  ),
                  // 우측 상단 새로고침
                  Positioned(
                    top: 0,
                    right: -3,
                    child: InkWell(
                      onTap: _isAnalyzing
                          ? null
                          : () => _fetchAnalysis(forceRefresh: true),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: _isAnalyzing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.refresh,
                                size: 18,
                                color: Colors.indigo,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // "레시피 검색" 부분만 누를 수 있게
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    InkWell(
                      onTap: () {
                        final keywords = _analysis!.suggestion
                            .split(',')
                            .map((s) => s.trim())
                            .where((s) => s.isNotEmpty)
                            .toList();
                        if (keywords.isEmpty) return;
                        widget.onRequestRecipeKeywordSearch?.call(keywords);
                      },
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '"${_analysis!.suggestion}" 레시피 검색',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.indigo,
                              ),
                            ),
                            const Icon(
                              Icons.chevron_right,
                              size: 16,
                              color: Colors.indigo,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAnalysisRow(
    String label,
    String value, {
    bool highlight = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 56,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: highlight ? FontWeight.w600 : FontWeight.normal,
              color: highlight ? Colors.orange.shade700 : Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final now = DateTime.now();
    final filtered = _filteredItems;
    final groups = _groupByName(filtered);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (_isMenuOpen) setState(() => _isMenuOpen = false);
      },
      child: Column(
        children: [
          // 분석 카드 (식재료 있을 때만)
          if (_items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: _buildAnalysisCard(),
            ),
          // 리스트 영역
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      _searchQuery.isNotEmpty || _hasFilter
                          ? '검색 결과가 없어요.'
                          : '등록된 식재료가 없어요.',
                    ),
                  )
                : ListView.builder(
                    itemCount: groups.length,
                    itemBuilder: (context, index) {
                      final lots = groups[index];
                      if (_isDeleteMode) {
                        return lots.length == 1
                            ? _buildDeleteModeCard(lots.first, now)
                            : _buildDeleteModeGroupCard(lots, now);
                      }
                      return lots.length == 1
                          ? _buildSingleItemCard(lots.first, now)
                          : _buildGroupCard(lots, now);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── 카드: 일반 모드 ─────────────────────────

  /// 상세보기 아래 버튼들 (묶음 안 건은 나누기가 위쪽 버튼에 있어서 수정만)
  Widget _detailActions(Ingredient item, {bool showSplit = true}) {
    final buttonStyle = OutlinedButton.styleFrom(
      side: const BorderSide(width: 0.3),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              style: buttonStyle,
              onPressed: () => _openEdit(item),
              child: const Text('수정'),
            ),
          ),
          if (showSplit) ...[
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                style: buttonStyle,
                onPressed: () => _openSplit(item),
                child: const Text('나누기'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 1건짜리 재료 카드 (기존 모양)
  Widget _buildSingleItemCard(Ingredient item, DateTime now) {
    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: _deleteBackground(),
      confirmDismiss: (_) => _confirmAndSoftDelete(item),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: ExpansionTile(
          key: PageStorageKey(item.id),
          onExpansionChanged: (_) => _closeMenuAfterFrame(),
          collapsedShape: const Border(),
          shape: const Border(),
          leading: _ingredientAvatar(item),
          title: Text(
            '${item.name} (${item.storage})',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            _dDayText(item.expirationDate, now),
            style: TextStyle(
              color: _getExpiryColor(item.expirationDate, now),
              fontWeight: FontWeight.bold,
            ),
          ),
          trailing: Text(
            '${item.quantity}${item.unit}',
            style: const TextStyle(fontSize: 16),
          ),
          children: [
            const Divider(height: 1),
            const SizedBox(height: 8),
            _detailRow('카테고리', item.category),
            _detailRow('수량', '${item.quantity}${item.unit}'),
            _detailRow('보관 방법', item.storage),
            _detailRow('소비기한', _formatDate(item.expirationDate)),
            _detailRow('등록일', _formatDate(item.addedAt)),
            const SizedBox(height: 8),
            _detailActions(item),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 같은 이름 2건 이상 묶음 카드
  Widget _buildGroupCard(List<Ingredient> lots, DateTime now) {
    final first = lots.first; // 가장 임박한 것
    final expiredCount = lots.where(_isExpired).length;
    final name = first.name.trim();

    // 단위가 다 같으면 합계, 다르면 건수
    final units = lots.map((e) => e.unit).toSet();
    final summary = units.length == 1
        ? '${lots.fold<int>(0, (total, e) => total + e.quantity)}${first.unit}'
        : '${lots.length}건';

    // 보관 방법이 다 같으면 제목에 표시
    final storages = lots.map((e) => e.storage).toSet();
    final title = storages.length == 1 ? '$name (${first.storage})' : name;

    final buttonStyle = OutlinedButton.styleFrom(
      side: const BorderSide(width: 0.3),
    );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: PageStorageKey('group_$name'),
        onExpansionChanged: (_) => _closeMenuAfterFrame(),
        collapsedShape: const Border(),
        shape: const Border(),
        leading: _ingredientAvatar(first),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: _dDayText(first.expirationDate, now),
                style: TextStyle(
                  color: _getExpiryColor(first.expirationDate, now),
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextSpan(
                text: ' · ${lots.length}건',
                style: const TextStyle(color: Colors.grey),
              ),
              // 대표가 남은 것인데 지난 건이 섞여 있을 때만
              if (expiredCount > 0 && !_isExpired(first))
                TextSpan(
                  text: ' · 지남 $expiredCount건',
                  style: TextStyle(
                    color: Colors.red.shade300,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
        trailing: Text(summary, style: const TextStyle(fontSize: 16)),
        children: [
          const Divider(height: 1),
          // 묶음 단위 합치기 · 나누기
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: buttonStyle,
                    onPressed: () async {
                      final picked = await _pickLots(lots, multiple: true);
                      if (picked == null || picked.length < 2 || !mounted) {
                        return;
                      }
                      _openMerge(picked);
                    },
                    icon: const Icon(Icons.merge_type, size: 18),
                    label: const Text('합치기'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: buttonStyle,
                    onPressed: () async {
                      final picked = await _pickLots(lots, multiple: false);
                      if (picked == null || picked.isEmpty || !mounted) return;
                      _openSplit(picked.first);
                    },
                    icon: const Icon(Icons.call_split, size: 18),
                    label: const Text('나누기'),
                  ),
                ),
              ],
            ),
          ),
          ...lots.map((item) => _buildLotTile(item, now)),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  /// 묶음 안의 한 건: 기존 카드와 같은 배치, 누르면 상세보기
  Widget _buildLotTile(Ingredient item, DateTime now) {
    return Dismissible(
      key: ValueKey(item.id),
      direction: DismissDirection.endToStart,
      background: _deleteBackground(),
      confirmDismiss: (_) => _confirmAndSoftDelete(item),
      child: ExpansionTile(
        key: PageStorageKey('lot_${item.id}'),
        tilePadding: const EdgeInsets.only(left: 24, right: 16),
        collapsedShape: const Border(),
        shape: const Border(),
        leading: _ingredientAvatar(item, radius: 18),
        title: Text(
          '${item.name} (${item.storage})',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          _dDayText(item.expirationDate, now),
          style: TextStyle(
            color: _getExpiryColor(item.expirationDate, now),
            fontWeight: FontWeight.bold,
          ),
        ),
        trailing: Text(
          '${item.quantity}${item.unit}',
          style: const TextStyle(fontSize: 15),
        ),
        children: [
          const Divider(height: 1, indent: 24),
          const SizedBox(height: 8),
          _detailRow('카테고리', item.category),
          _detailRow('수량', '${item.quantity}${item.unit}'),
          _detailRow('보관 방법', item.storage),
          _detailRow('소비기한', _formatDate(item.expirationDate)),
          _detailRow('등록일', _formatDate(item.addedAt)),
          const SizedBox(height: 4),
          _detailActions(item, showSplit: false),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ───────────────────────── 카드: 삭제 모드 ─────────────────────────

  Widget _buildDeleteModeCard(Ingredient item, DateTime now) {
    final isSelected = _selectedIds.contains(item.id);
    return Card(
      key: ValueKey(item.id),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: isSelected ? Colors.red[50] : null,
      child: CheckboxListTile(
        value: isSelected,
        onChanged: (checked) {
          setState(() {
            if (checked == true) {
              _selectedIds.add(item.id);
            } else {
              _selectedIds.remove(item.id);
            }
          });
        },
        secondary: _ingredientAvatar(item),
        title: Text(
          '${item.name} (${item.storage})',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          _dDayText(item.expirationDate, now),
          style: TextStyle(
            color: _getExpiryColor(item.expirationDate, now),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildDeleteModeGroupCard(List<Ingredient> lots, DateTime now) {
    final first = lots.first;
    final ids = lots.map((e) => e.id).toList();
    final selectedCount = ids.where(_selectedIds.contains).length;
    // 전부 선택 true / 하나도 없음 false / 일부 null(— 표시)
    final bool? groupValue = selectedCount == 0
        ? false
        : selectedCount == ids.length
        ? true
        : null;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: selectedCount > 0 ? Colors.red[50] : null,
      child: Column(
        children: [
          CheckboxListTile(
            tristate: true,
            value: groupValue,
            onChanged: (_) {
              setState(() {
                if (selectedCount == ids.length) {
                  _selectedIds.removeAll(ids);
                } else {
                  _selectedIds.addAll(ids);
                }
              });
            },
            secondary: _ingredientAvatar(first),
            title: Text(
              first.name.trim(),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              '${lots.length}건 중 $selectedCount건 선택',
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ...lots.map(
            (item) => CheckboxListTile(
              dense: true,
              contentPadding: const EdgeInsets.only(left: 24, right: 16),
              value: _selectedIds.contains(item.id),
              onChanged: (checked) {
                setState(() {
                  if (checked == true) {
                    _selectedIds.add(item.id);
                  } else {
                    _selectedIds.remove(item.id);
                  }
                });
              },
              secondary: _ingredientAvatar(item, radius: 18),
              title: Text(
                '${item.name} (${item.storage}) · ${item.quantity}${item.unit}',
              ),
              subtitle: Text(
                _dDayText(item.expirationDate, now),
                style: TextStyle(
                  color: _getExpiryColor(item.expirationDate, now),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
