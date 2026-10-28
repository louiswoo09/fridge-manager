import 'dart:convert';

import 'package:image_picker/image_picker.dart';

import 'api_client.dart';

/// 사진에서 인식한 식재료 하나
class RecognizedIngredient {
  final String name;
  final String category;
  final int quantity;
  final String unit;
  final String storage;

  RecognizedIngredient({
    required this.name,
    required this.category,
    required this.quantity,
    required this.unit,
    required this.storage,
  });

  factory RecognizedIngredient.fromJson(Map<String, dynamic> json) {
    return RecognizedIngredient(
      name: json['name']?.toString() ?? '',
      category: json['category']?.toString() ?? '기타',
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      unit: json['unit']?.toString() ?? '개',
      storage: json['storage']?.toString() ?? '냉장',
    );
  }
}

/// 인식 결과 전체
class RecognitionResult {
  /// 'ingredients' (식재료 사진) / 'receipt' (영수증) / 'none' (관련 없음)
  final String sourceType;
  final List<RecognizedIngredient> items;

  RecognitionResult({required this.sourceType, required this.items});
}

class IngredientRecognitionService {
  static final ImagePicker _picker = ImagePicker();

  /// 촬영 또는 앨범 선택. 사용자가 취소하면 null
  /// 테스트 스크립트와 같은 기준으로 긴 변 1280px, 품질 85로 줄임
  static Future<XFile?> pickImage(ImageSource source) {
    return _picker.pickImage(
      source: source,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 85,
    );
  }

  static String _mimeTypeOf(XFile file) {
    final ext = file.path.split('.').last.toLowerCase();
    return switch (ext) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
  }

  static Future<RecognitionResult> recognize(XFile file) async {
    final bytes = await file.readAsBytes();

    final response = await ApiClient.post(
      '/ai/recognize-ingredients',
      jsonEncode({
        'image_base64': base64Encode(bytes),
        'mime_type': _mimeTypeOf(file),
      }),
      // 서버 Gemini 대기(90초) + 재시도 여유
      timeout: const Duration(seconds: 120),
    );

    if (response.statusCode == 503) throw AiBusyException();
    if (response.statusCode != 200) {
      throw Exception('인식 실패 (코드 ${response.statusCode})');
    }

    final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final items = ((data['items'] as List?) ?? [])
        .whereType<Map<String, dynamic>>()
        .map(RecognizedIngredient.fromJson)
        .where((e) => e.name.isNotEmpty)
        .toList();

    return RecognitionResult(
      sourceType: data['source_type']?.toString() ?? 'none',
      items: items,
    );
  }
}