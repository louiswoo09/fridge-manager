import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/ingredient.dart';
import '../services/ingredient_service.dart';
import 'add_ingredient_screen.dart';
import 'edit_ingredient_screen.dart';
import 'profile_screen.dart';

class IngredientListScreen extends StatefulWidget {
  const IngredientListScreen({super.key});

  @override
  State<IngredientListScreen> createState() => _IngredientListScreenState();
}

class _IngredientListScreenState extends State<IngredientListScreen> {
  final IngredientService _service = IngredientService();
  late StreamSubscription<List<Ingredient>> _subscription;
  bool _isDeleteMode = false;
  bool _isMenuOpen = false;
  bool _isLoading = true;
  final Set<String> _selectedIds = {};
  List<Ingredient> _items = [];

  @override
  void initState() {
    super.initState();
    _subscription = _service.getIngredients().listen(
      (items) {
        if (!mounted) return;
        setState(() {
          _items = List.from(items)
            ..sort((a, b) => a.expirationDate.compareTo(b.expirationDate));
          _selectedIds.removeWhere((id) => !_items.any((e) => e.id == id));
          _isLoading = false;
        });
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
    _subscription.cancel();
    super.dispose();
  }

  Color _getExpiryColor(DateTime expiry, DateTime now) {
    final days = expiry.difference(now).inDays;
    if (days < 0) return Colors.grey;
    if (days <= 3) return Colors.red;
    if (days <= 7) return Colors.orange;
    return Colors.green;
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
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

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);
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
      final batch = FirebaseFirestore.instance.batch();
      for (final id in deletedIds) {
        final ref = FirebaseFirestore.instance
            .collection('Ingredients')
            .doc(id);
        batch.update(ref, {'is_deleted': true, 'deleted_at': Timestamp.now()});
      }
      await batch.commit();

      if (!mounted) return;

      setState(() {
        _selectedIds.clear();
        _isDeleteMode = false;
      });

      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text('$deletedCount개 삭제됨'),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: '되돌리기',
              onPressed: () async {
                try {
                  final batch = FirebaseFirestore.instance.batch();
                  for (final id in deletedIds) {
                    final ref = FirebaseFirestore.instance
                        .collection('Ingredients')
                        .doc(id);
                    batch.update(ref, {
                      'is_deleted': false,
                      'deleted_at': null,
                    });
                  }
                  await batch.commit();
                } catch (e) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('복구 실패')),
                  );
                }
              },
            ),
          ),
        );
    } catch (e) {
      messenger.showSnackBar(const SnackBar(content: Text('삭제 중 오류가 발생했습니다.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isDeleteMode ? '${_selectedIds.length}개 선택됨' : '냉장고 매니저'),
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
            icon: const Icon(Icons.person),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const ProfileScreen()),
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
                  FloatingActionButton.extended(
                    heroTag: 'ingredient_add',
                    onPressed: () {
                      setState(() => _isMenuOpen = false);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const AddIngredientScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('재료 추가'),
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton.extended(
                    heroTag: 'ingredient_delete',
                    onPressed: () {
                      setState(() {
                        _isMenuOpen = false;
                        _isDeleteMode = true;
                        _selectedIds.clear();
                      });
                    },
                    icon: const Icon(Icons.delete),
                    label: const Text('재료 삭제'),
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

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_items.isEmpty) {
      return const Center(child: Text('등록된 식재료가 없어요.'));
    }

    final now = DateTime.now();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (_isMenuOpen) setState(() => _isMenuOpen = false);
      },
      child: ListView.builder(
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final item = _items[index];

          final date = item.expirationDate;
          final formattedDate =
              "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";

          final days = item.expirationDate.difference(now).inDays;
          final dDay = days < 0
              ? '${days.abs()}일 지남'
              : days == 0
              ? 'D-Day'
              : 'D-$days';

          final isSelected = _selectedIds.contains(item.id);

          if (_isDeleteMode) {
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
                secondary: CircleAvatar(
                  backgroundColor: Colors.grey[200],
                  radius: 24,
                  child: Icon(
                    _getCategoryIcon(item.category),
                    color: Colors.grey[700],
                  ),
                ),
                title: Text(
                  '${item.name} (${item.storage})',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  dDay,
                  style: TextStyle(
                    color: _getExpiryColor(item.expirationDate, now),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            );
          }

          return Dismissible(
            key: ValueKey(item.id),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              color: Colors.red[400],
              child: const Icon(Icons.delete, color: Colors.white),
            ),
            confirmDismiss: (direction) async {
              final messenger = ScaffoldMessenger.of(context);

              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('삭제 확인'),
                  content: Text('${item.name}을(를) 삭제할까요?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('취소'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text(
                        '삭제',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              );

              if (confirm != true) return false;

              try {
                await FirebaseFirestore.instance
                    .collection('Ingredients')
                    .doc(item.id)
                    .update({
                      'is_deleted': true,
                      'deleted_at': Timestamp.now(),
                    });

                messenger
                  ..clearSnackBars()
                  ..showSnackBar(
                    SnackBar(
                      content: Text('${item.name} 삭제됨'),
                      duration: const Duration(seconds: 5),
                      action: SnackBarAction(
                        label: '되돌리기',
                        onPressed: () {
                          FirebaseFirestore.instance
                              .collection('Ingredients')
                              .doc(item.id)
                              .update({
                                'is_deleted': false,
                                'deleted_at': null,
                              });
                        },
                      ),
                    ),
                  );

                return true;
              } catch (e) {
                messenger.showSnackBar(const SnackBar(content: Text('삭제 실패')));
                return false;
              }
            },
            onDismissed: (_) {},
            child: Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: ExpansionTile(
                key: PageStorageKey(item.id),
                onExpansionChanged: (isExpanded) {
                  if (_isMenuOpen) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) setState(() => _isMenuOpen = false);
                    });
                  }
                },
                collapsedShape: const Border(),
                shape: const Border(),
                leading: CircleAvatar(
                  backgroundColor: Colors.grey[200],
                  radius: 24,
                  child: Icon(
                    _getCategoryIcon(item.category),
                    color: Colors.grey[700],
                  ),
                ),
                title: Text(
                  '${item.name} (${item.storage})',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  dDay,
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
                  _detailRow('소비기한', formattedDate),
                  _detailRow(
                    '등록일',
                    "${item.addedAt.year}-${item.addedAt.month.toString().padLeft(2, '0')}-${item.addedAt.day.toString().padLeft(2, '0')}",
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(width: 0.3),
                        ),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                EditIngredientScreen(ingredient: item),
                          ),
                        ),
                        child: const Text('수정'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
