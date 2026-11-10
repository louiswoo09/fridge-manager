import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// 폰 안에서 사진 속 글자를 읽는 서비스 (ML Kit, 한국어 + 영어·숫자)
class DateOcrService {
  static final TextRecognizer _recognizer =
      TextRecognizer(script: TextRecognitionScript.korean);

  /// 사진에서 읽은 글자를 줄 단위로 돌려줌
  static Future<List<String>> readLines(String imagePath) async {
    final input = InputImage.fromFilePath(imagePath);
    final result = await _recognizer.processImage(input);
    return result.blocks
        .expand((block) => block.lines)
        .map((line) => line.text.trim())
        .where((text) => text.isNotEmpty)
        .toList();
  }
}