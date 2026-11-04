import 'package:flutter/material.dart';
import '../models/ingredient.dart';
import '../services/ingredient_service.dart';
import '../services/ingredient_icon_mapper.dart';

class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key});
  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  final IngredientService _service = IngredientService();

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// 소비기한 순으로 정렬 후 이름별로 묶음 (냉장고 화면과 같은 기준)
  List<List<Ingredient>> _group(List<Ingredient> items) {
    final sorted = [...items]
      ..sort((a, b) => a.expirationDate.compareTo(b.expirationDate));
    final groups = <String, List<Ingredient>>{};
    for (final item in sorted) {
      groups.putIfAbsent(item.name.trim(), () => []).add(item);
    }
    return groups.values.toList();
  }

  Future<void> _restore(List<Ingredient> items) async {
    try {
      await _service.restoreMany(items.map((e) => e.id));
      _showSnack(items.length > 1 ? '${items.length}건 복구했어요' : '복구했어요');
    } catch (e) {
      _showSnack('복구 실패: $e');
    }
  }

  Future<void> _deleteForever(List<Ingredient> items) async {
    final name = items.first.name.trim();
    final label = items.length > 1 ? '$name ${items.length}건' : name;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('완전 삭제'),
        content: Text('$label을(를) 완전히 삭제할까요?\n되돌릴 수 없어요.'),
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
    if (confirm != true) return;
    await _service.permanentlyDeleteMany(items.map((e) => e.id));
  }

  Future<void> _deleteAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('전체 삭제'),
        content: const Text('휴지통의 모든 항목을 삭제하시겠습니까?'),
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
    if (confirm != true) return;
    await _service.emptyTrash();
  }

  Widget _avatar(Ingredient item, {double radius = 20}) => CircleAvatar(
    backgroundColor: Colors.grey[200],
    radius: radius,
    child: IngredientIconMapper.build(
      name: item.name,
      category: item.category,
      size: radius,
    ),
  );

  Widget _actions(List<Ingredient> items) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton(
        icon: const Icon(Icons.restore),
        tooltip: '복구',
        onPressed: () => _restore(items),
      ),
      IconButton(
        icon: const Icon(Icons.delete_forever, color: Colors.red),
        tooltip: '완전 삭제',
        onPressed: () => _deleteForever(items),
      ),
    ],
  );

  String _lotText(Ingredient item) =>
      '${item.quantity}${item.unit} · ${item.storage} · 소비기한 ${_formatDate(item.expirationDate)}';

  Widget _buildGroup(List<Ingredient> lots) {
    final first = lots.first;

    if (lots.length == 1) {
      return ListTile(
        leading: _avatar(first),
        title: Text(first.name),
        subtitle: Text(_lotText(first), style: const TextStyle(fontSize: 12)),
        trailing: _actions(lots),
      );
    }

    return ExpansionTile(
      leading: _avatar(first),
      title: Text(first.name.trim()),
      subtitle: Text('${lots.length}건', style: const TextStyle(fontSize: 12)),
      trailing: _actions(lots), // 묶음째 복구·삭제
      shape: const Border(),
      collapsedShape: const Border(),
      children: lots
          .map(
            (item) => ListTile(
              contentPadding: const EdgeInsets.only(left: 32, right: 16),
              leading: _avatar(item, radius: 16),
              title: Text(_lotText(item), style: const TextStyle(fontSize: 13)),
              trailing: _actions([item]),
            ),
          )
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('휴지통'),
        actions: [
          TextButton(
            onPressed: _deleteAll,
            child: const Text('전체 삭제', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
      body: StreamBuilder<List<Ingredient>>(
        stream: _service.getDeletedIngredients(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('휴지통이 비어 있습니다.'));
          }

          final groups = _group(snapshot.data!);
          return ListView.separated(
            itemCount: groups.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (_, i) => _buildGroup(groups[i]),
          );
        },
      ),
    );
  }
}
