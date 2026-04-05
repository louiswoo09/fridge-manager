import 'package:flutter/material.dart';
import '../models/ingredient.dart';
import '../services/ingredient_service.dart';
import 'add_ingredient_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'edit_ingredient_screen.dart';

class IngredientListScreen extends StatelessWidget {
  final IngredientService _service = IngredientService();

  IngredientListScreen({super.key});

  Color _getExpiryColor(DateTime expiry) {
    final days = expiry.difference(DateTime.now()).inDays;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('냉장고 매니저')),
      body: StreamBuilder<List<Ingredient>>(
        stream: _service.getIngredients(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('에러 발생: ${snapshot.error}'));
          }

          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('등록된 식재료가 없어요.'));
          }

          final items = snapshot.data!;

          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];

              final date = item.expirationDate;
              final formattedDate =
                  "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";

              final days = item.expirationDate
                  .difference(DateTime.now())
                  .inDays;
              final dDay = days < 0
                  ? '유통기한 ${days.abs()}일 지남'
                  : days == 0
                  ? 'D-Day'
                  : 'D-$days';

              return Dismissible(
                key: Key(item.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  color: Colors.red,
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                confirmDismiss: (direction) async {
                  return await showDialog(
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
                },
                onDismissed: (direction) async {
                  try {
                    await FirebaseFirestore.instance
                        .collection('Ingredients')
                        .doc(item.id)
                        .update({
                          'is_deleted': true,
                          'deleted_at': Timestamp.now(),
                        });

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('${item.name} 삭제됨'),
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
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('삭제 중 오류가 발생했습니다.')),
                    );
                  }
                },
                child: Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: ExpansionTile(
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
                        color: _getExpiryColor(item.expirationDate),
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
                      _detailRow('유통기한', formattedDate),
                      _detailRow(
                        '등록일',
                        "${item.addedAt.year}-${item.addedAt.month.toString().padLeft(2, '0')}-${item.addedAt.day.toString().padLeft(2, '0')}",
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () => Navigator.push(
                             context,
                              MaterialPageRoute(
                                builder: (context) => EditIngredientScreen(ingredient: item),
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
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const AddIngredientScreen()),
        ),
        child: const Icon(Icons.add),
      ),
    );
  }
}
