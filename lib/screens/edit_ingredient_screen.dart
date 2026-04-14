import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/ingredient.dart';
import 'package:firebase_auth/firebase_auth.dart';

class EditIngredientScreen extends StatefulWidget {
  final Ingredient ingredient;

  const EditIngredientScreen({super.key, required this.ingredient});

  @override
  State<EditIngredientScreen> createState() => _EditIngredientScreenState();
}

class _EditIngredientScreenState extends State<EditIngredientScreen> {
  late TextEditingController _nameController;
  late TextEditingController _quantityController;

  late String _category;
  late String _unit;
  late String _storage;
  late DateTime _expirationDate;

  final List<String> _categories = ['채소', '육류', '유제품', '과일', '해산물', '기타'];
  final List<String> _units = ['개', 'g', 'ml', 'L', '팩'];
  final List<String> _storages = ['냉장', '냉동', '실온'];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.ingredient.name);
    _quantityController = TextEditingController(
      text: widget.ingredient.quantity.toString(),
    );
    _category = widget.ingredient.category;
    _unit = widget.ingredient.unit;
    _storage = widget.ingredient.storage;
    _expirationDate = widget.ingredient.expirationDate;
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
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (picked != null) {
      setState(() => _expirationDate = picked);
    }
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

    final updated = widget.ingredient.copyWith(
      name: _nameController.text.trim(),
      category: _category,
      quantity:
          int.tryParse(_quantityController.text) ?? widget.ingredient.quantity,
      unit: _unit,
      storage: _storage,
      expirationDate: _expirationDate,
    );

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('ingredients')
          .doc(widget.ingredient.id)
          .update(updated.toMap(isCreate: false));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('수정 중 오류가 발생했습니다.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('식재료 수정')),
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
              child: ElevatedButton(
                onPressed: _save,
                child: const Text('수정 완료'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
