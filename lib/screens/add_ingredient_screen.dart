import 'package:flutter/material.dart';
import '../models/ingredient.dart';
import '../services/ingredient_service.dart';

class AddIngredientScreen extends StatefulWidget {
  final String? prefilledName;

  const AddIngredientScreen({super.key, this.prefilledName});

  @override
  State<AddIngredientScreen> createState() => _AddIngredientScreenState();
}

class _AddIngredientScreenState extends State<AddIngredientScreen> {
  final _nameController = TextEditingController();
  final _quantityController = TextEditingController();

  String _category = '채소';
  String _unit = '개';
  String _storage = '냉장';
  DateTime _expirationDate = DateTime.now().add(const Duration(days: 7));

  final List<String> _categories = ['채소', '육류', '유제품', '과일', '해산물', '기타'];
  final List<String> _units = ['개', 'g', 'ml', 'L', '팩'];
  final List<String> _storages = ['냉장', '냉동', '실온'];

  @override
  void initState() {
    super.initState();
    if (widget.prefilledName != null) {
      _nameController.text = widget.prefilledName!;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expirationDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (picked != null) {
      setState(() => _expirationDate = picked);
    }
  }

  /// 이름 끝 글자에 받침이 있으면 '을', 없으면 '를'
  String _objectParticle(String word) {
    if (word.isEmpty) return '를';
    final code = word.codeUnitAt(word.length - 1);
    if (code < 0xAC00 || code > 0xD7A3) return '를';
    return (code - 0xAC00) % 28 == 0 ? '를' : '을';
  }

  Future<void> _save() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('식재료 이름을 입력해주세요.')));
      return;
    }
    if (_quantityController.text.isNotEmpty &&
        int.tryParse(_quantityController.text) == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('수량은 숫자로 입력해주세요.')));
      return;
    }

    final ingredient = Ingredient(
      id: '',
      name: _nameController.text.trim(),
      category: _category,
      quantity: int.tryParse(_quantityController.text) ?? 1,
      unit: _unit,
      storage: _storage,
      expirationDate: _expirationDate,
      addedAt: DateTime.now(),
      isDeleted: false,
    );

    try {
      final merged = await IngredientService().addIngredient(ingredient);
      if (!mounted) return;

      final name = _nameController.text.trim();
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context, name);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            merged
                ? '$name${_objectParticle(name)} 동일한 재료와 합쳤어요'
                : '$name${_objectParticle(name)} 등록했어요',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('저장 중 오류: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('식재료 추가')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '식재료 이름',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quantityController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '수량',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: _unit,
                  items: _units
                      .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                      .toList(),
                  onChanged: (v) => setState(() => _unit = v!),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text('카테고리', style: TextStyle(color: Colors.grey)),
            DropdownButton<String>(
              value: _category,
              isExpanded: true,
              items: _categories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _category = v!),
            ),
            const SizedBox(height: 16),
            const Text('보관 방법', style: TextStyle(color: Colors.grey)),
            DropdownButton<String>(
              value: _storage,
              isExpanded: true,
              items: _storages
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (v) => setState(() => _storage = v!),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '소비기한: ${_expirationDate.year}-${_expirationDate.month.toString().padLeft(2, '0')}-${_expirationDate.day.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontSize: 16),
                ),
                TextButton(
                  onPressed: () => _selectDate(context),
                  child: const Text('날짜 선택'),
                ),
              ],
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(onPressed: _save, child: const Text('저장')),
            ),
          ],
        ),
      ),
    );
  }
}
