import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const String kGeminiApiKey = String.fromEnvironment('GEMINI_API_KEY');

class RecipeDetailScreen extends StatefulWidget {
  final Map<String, dynamic> recipe;
  final String myIngredients;

  const RecipeDetailScreen({
    super.key,
    required this.recipe,
    required this.myIngredients,
  });

  @override
  State<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends State<RecipeDetailScreen> {
  bool _isGeminiLoading = false;
  String? _geminiResult;

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  List<String> _getManuals() {
    final manuals = <String>[];
    for (int i = 1; i <= 20; i++) {
      final key = 'MANUAL${i.toString().padLeft(2, '0')}';
      final val = widget.recipe[key];
      if (val != null && val.toString().trim().isNotEmpty) {
        manuals.add(val.toString().trim());
      }
    }
    return manuals;
  }

  Future<void> _callGemini() async {
    if (_isGeminiLoading) return;
    if (kGeminiApiKey.isEmpty) {
      _showSnack('Gemini API 키가 설정되지 않았습니다');
      return;
    }

    setState(() {
      _isGeminiLoading = true;
      _geminiResult = null;
    });

    final recipeName = widget.recipe['RCP_NM'] ?? '';
    final recipeIngredients = widget.recipe['RCP_PARTS_DTLS'] ?? '';

    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$kGeminiApiKey',
    );

    final prompt =
        '''
다음 레시피를 참고해서 내가 가진 재료에 맞게 변형해줘.

조건:
- 결과는 반드시 한국어
- 단계별 번호로 작성
- 5단계 이내
- 부족한 재료는 대체 재료 제안
- 불필요한 재료는 제거
- 불필요한 설명 금지

[레시피 이름]
$recipeName

[기존 재료]
$recipeIngredients

[내 재료]
${widget.myIngredients}
''';

    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              "contents": [
                {
                  "parts": [
                    {"text": prompt},
                  ],
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final candidates = data['candidates'];
        if (candidates == null || candidates.isEmpty) {
          throw Exception('응답 없음');
        }
        final parts = candidates[0]['content']?['parts'];
        if (parts == null || parts.isEmpty) {
          throw Exception('parts 없음');
        }
        final text = parts[0]['text'];
        if (text == null || text.trim().isEmpty) {
          setState(() => _geminiResult = '추천 결과가 없습니다.');
          return;
        }
        if (!mounted) return;
        setState(() => _geminiResult = text);
      } else {
        debugPrint('Gemini 실패: ${response.body}');
        _showSnack('AI 응답 오류가 발생했습니다');
      }
    } on TimeoutException {
      _showSnack('요청 시간이 초과되었습니다');
    } catch (e) {
      if (!mounted) return;
      _showSnack('AI 응답 오류가 발생했습니다');
      debugPrint(e.toString());
    } finally {
      if (mounted) {
        setState(() => _isGeminiLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.recipe['RCP_NM'] ?? '';
    final ingredients = widget.recipe['RCP_PARTS_DTLS'] ?? '';
    final imageUrl =
        (widget.recipe['ATT_FILE_NO_MAIN'] ??
                widget.recipe['MANUAL_IMG01'] ??
                '')
            as String;
    final manuals = _getManuals();

    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imageUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  imageUrl,
                  width: double.infinity,
                  height: 200,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            const SizedBox(height: 16),
            Text(
              '출처: ${widget.recipe['source'] ?? ''}',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const SizedBox(height: 8),
            const Text(
              '재료',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(ingredients, style: const TextStyle(height: 1.6)),
            const SizedBox(height: 16),
            if (manuals.isNotEmpty) ...[
              const Text(
                '조리법',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ...manuals.map(
                (step) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    step.replaceAll('\n', ' '),
                    style: const TextStyle(height: 1.6),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            const Divider(),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isGeminiLoading ? null : _callGemini,
                icon: _isGeminiLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(_isGeminiLoading ? 'AI 변형 중...' : 'AI 맞춤 변형'),
              ),
            ),
            if (_geminiResult != null) ...[
              const SizedBox(height: 16),
              const Text(
                'AI 맞춤 레시피',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _geminiResult!,
                  style: const TextStyle(height: 1.6),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
