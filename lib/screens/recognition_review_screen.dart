import 'package:flutter/material.dart';
import '../models/ingredient.dart';
import '../services/ingredient_recognition_service.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';

/// 사진·영수증 인식 결과를 확인하고 고친 뒤 등록할 재료 목록을 돌려주는 화면
/// 등록 버튼을 누르면 고친 재료 목록을 이전 화면으로 돌려줌
class RecognitionReviewScreen extends StatefulWidget {
  final RecognitionResult result;
  final List<XFile> photos;

  const RecognitionReviewScreen({
    super.key,
    required this.result,
    this.photos = const [],
  });

  @override
  State<RecognitionReviewScreen> createState() =>
      _RecognitionReviewScreenState();
}

/// 화면에서 수정 중인 재료 하나
class _Draft {
  bool selected = true;
  final TextEditingController name;
  final TextEditingController quantity;
  String category;
  String unit;
  String storage;
  DateTime expirationDate;

  _Draft({
    required String name,
    required int quantity,
    required this.category,
    required this.unit,
    required this.storage,
    required this.expirationDate,
  }) : name = TextEditingController(text: name),
       quantity = TextEditingController(text: '$quantity');

  void dispose() {
    name.dispose();
    quantity.dispose();
  }
}

class _RecognitionReviewScreenState extends State<RecognitionReviewScreen> {
  // 직접 추가 화면과 같은 선택지
  static const _categories = ['채소', '육류', '유제품', '과일', '해산물', '기타'];
  static const _units = ['개', 'g', 'ml', 'L', '팩'];
  static const _storages = ['냉장', '냉동', '실온'];

  /// 임시 기본값 (직접 추가와 동일). 11월 소비기한 자동 계산으로 교체 예정
  static const _defaultShelfDays = 7;

  late final List<_Draft> _drafts;

  DateTime get _defaultExpiration {
    final now = DateTime.now();
    return DateTime(
      now.year,
      now.month,
      now.day,
    ).add(const Duration(days: _defaultShelfDays));
  }

  /// 서버가 이미 정리해서 보내지만, 혹시 모를 값은 기본값으로
  String _pick(String value, List<String> options, String fallback) =>
      options.contains(value) ? value : fallback;

  @override
  void initState() {
    super.initState();
    _drafts = widget.result.items
        .map(
          (e) => _Draft(
            name: e.name,
            quantity: e.quantity,
            category: _pick(e.category, _categories, '기타'),
            unit: _pick(e.unit, _units, '개'),
            storage: _pick(e.storage, _storages, '냉장'),
            expirationDate: _defaultExpiration,
          ),
        )
        .toList();
  }

  @override
  void dispose() {
    for (final d in _drafts) {
      d.dispose();
    }
    super.dispose();
  }

  int get _selectedCount => _drafts.where((d) => d.selected).length;
  bool get _allSelected =>
      _drafts.isNotEmpty && _drafts.every((d) => d.selected);

  void _toggleAll() {
    final value = !_allSelected;
    setState(() {
      for (final d in _drafts) {
        d.selected = value;
      }
    });
  }

  void _addEmpty() {
    setState(() {
      _drafts.add(
        _Draft(
          name: '',
          quantity: 1,
          category: '기타',
          unit: '개',
          storage: '냉장',
          expirationDate: _defaultExpiration,
        ),
      );
    });
  }

  Future<void> _pickDate(_Draft d) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: d.expirationDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (picked != null) setState(() => d.expirationDate = picked);
  }

  void _submit() {
    final selected = _drafts.where((d) => d.selected).toList();
    if (selected.isEmpty) return;

    if (selected.any((d) => d.name.text.trim().isEmpty)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('이름이 비어 있는 재료가 있어요')));
      return;
    }

    final now = DateTime.now();
    final ingredients = selected.map((d) {
      final qty = int.tryParse(d.quantity.text.trim()) ?? 1;
      return Ingredient(
        id: '',
        name: d.name.text.trim(),
        category: d.category,
        quantity: qty < 1 ? 1 : qty,
        unit: d.unit,
        storage: d.storage,
        expirationDate: d.expirationDate,
        addedAt: now,
        isDeleted: false,
      );
    }).toList();

    Navigator.pop(context, ingredients);
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Widget _dropdown(
    String value,
    List<String> options,
    bool enabled,
    void Function(String) onChanged,
  ) {
    return DropdownButton<String>(
      value: value,
      isDense: true,
      items: options
          .map((o) => DropdownMenuItem(value: o, child: Text(o)))
          .toList(),
      onChanged: enabled
          ? (v) {
              if (v != null) setState(() => onChanged(v));
            }
          : null,
    );
  }

  void _openViewer(int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            _PhotoViewer(photos: widget.photos, initialIndex: index),
      ),
    );
  }

  Widget _buildPhotoStrip() {
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: widget.photos.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) => GestureDetector(
          onTap: () => _openViewer(i),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(widget.photos[i].path),
              width: 72,
              height: 72,
              fit: BoxFit.cover,
              cacheWidth: 200,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDraftCard(_Draft d) {
    final enabled = d.selected;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: enabled ? null : Colors.grey.shade100,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 12, 4),
        child: Column(
          children: [
            Row(
              children: [
                Checkbox(
                  value: d.selected,
                  onChanged: (v) => setState(() => d.selected = v ?? false),
                ),
                Expanded(
                  child: TextField(
                    controller: d.name,
                    enabled: enabled,
                    decoration: const InputDecoration(
                      hintText: '재료 이름',
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 64,
                    child: TextField(
                      controller: d.quantity,
                      enabled: enabled,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '수량',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _dropdown(d.unit, _units, enabled, (v) => d.unit = v),
                  const Spacer(),
                  _dropdown(
                    d.category,
                    _categories,
                    enabled,
                    (v) => d.category = v,
                  ),
                  const SizedBox(width: 12),
                  _dropdown(
                    d.storage,
                    _storages,
                    enabled,
                    (v) => d.storage = v,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Row(
                children: [
                  const Text('소비기한', style: TextStyle(color: Colors.grey)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: enabled ? () => _pickDate(d) : null,
                    icon: const Icon(Icons.event, size: 18),
                    label: Text(_formatDate(d.expirationDate)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.result.sourceType == 'receipt'
        ? '영수증에서 찾은 재료'
        : '사진에서 찾은 재료';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          TextButton(
            onPressed: _drafts.isEmpty ? null : _toggleAll,
            child: Text(_allSelected ? '전체 해제' : '전체 선택'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          if (widget.photos.isNotEmpty) ...[
            _buildPhotoStrip(),
            const SizedBox(height: 8),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              '재료 ${widget.result.items.length}개를 찾았어요. 등록 전에 확인하고 고쳐주세요.',
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ),
          ..._drafts.map(_buildDraftCard),
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: _addEmpty,
            icon: const Icon(Icons.add),
            label: const Text('빠진 재료 직접 추가'),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _selectedCount == 0 ? null : _submit,
              child: Text('$_selectedCount개 등록'),
            ),
          ),
        ),
      ),
    );
  }
}

/// 사진 크게 보기: 두 손가락 확대, 옆으로 넘기기
class _PhotoViewer extends StatefulWidget {
  final List<XFile> photos;
  final int initialIndex;

  const _PhotoViewer({required this.photos, required this.initialIndex});

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  late final PageController _pageController =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        // 앱 전체 AppBar가 투명이라 여기선 직접 지정
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: widget.photos.length > 1
            ? Text('${_index + 1} / ${widget.photos.length}')
            : null,
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.photos.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) => InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: Center(
            child: Image.file(
              File(widget.photos[i].path),
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}