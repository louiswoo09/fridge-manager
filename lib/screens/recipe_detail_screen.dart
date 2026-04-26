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
    if (widget.myIngredients.isEmpty) {
      _showSnack('보유 식재료가 없습니다. 먼저 식재료를 등록해주세요.');
      return;
    }

    setState(() {
      _isGeminiLoading = true;
      _geminiResult = null;
    });

    final recipeName = widget.recipe['RCP_NM'] ?? '';
    final recipeIngredients = widget.recipe['RCP_PARTS_DTLS'] ?? '';
    final manuals = _getManuals().join('\n');

    final url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$kGeminiApiKey',
    );

    final prompt =
        '''
너는 TV 예능 프로그램 '냉장고를 부탁해'에 출연한 요리 연구가야. 
이번 프로그램의 주제는 '[주어진 레시피]를 바탕으로 [냉장고 속 재료]만으로 조리가 가능하도록 레시피를 변형시켜라!'야.
레시피에 사용하는 재료는 주어진 기본 양념 외에는 반드시 [냉장고 속 재료]에 포함된 것만 사용해야해.
그러므로 [주어진 레시피]의 재료 중 [냉장고 속 재료]에 없는 것은 제거하거나, [냉장고 속 재료] 내에서 재료의 종류와 역할이 유사한 경우에 대체해서 만들어야해. 소스나 양념류는 기본 양념에서 대체해줘.
변형시킨 레시피가 [주어진 레시피]와 요리 유형(한식/중식/일식/양식 등), 형식(국/볶음/구이/샐러드 등), 메인 재료(고기/해산물/채소/과일)이 동일할 수록 높은 평가를 받을거야. 
물론 재료 상황에 맞게 자연스럽게 변형하는게 더욱 중요해. 상식에서 벗어난 이상한 레시피는 매우 낮은 평가를 받을거라는걸 꼭 기억해줘.
출연진에게 최고로 높은 평가를 받을 수 있도록 노력하자! 

레시피 작성 조건: 
1. 한국어로 작성할 것. 
2. 요리 제목은 사용 재료를 나열하지 않고 주재료만 포함하여 자연스럽게 작성할 것. 
3. 재료 목록에는 각 재료의 대략적인 양(예: 1캔, 1/2개, 100g, 1스푼 등)을 포함 할것.
4. 조리법은 번호(1., 2., ...)로 작성하고 최대 8단계 이내로 간결하게 작성할 것. 
5. [냉장고 속 재료] 외의 재료는 기본 양념(소금, 설탕, 간장, 식용유, 참기름, 후추, 고춧가루, 된장, 고추장, 식초, 다진마늘, 마요네즈, 케첩, 밥, 물)만 추가할 것. 
6. 요리의 정체성을 유지하는 데 필요한 주재료(예: 고기, 해산물, 면 등)가 [냉장고 속 재료]에 존재하지 않는 경우에는 무리하게 레시피를 변형하지 말고 조건 9번을 따를 것.
7. [냉장고 속 재료]나 기본 양념을 제외한 권장 재료는 재료 목록 마지막에 '💡 OO가 있으면 더 좋아요.' 형식을 지켜 팁 한 줄만 추가할 것. 
8. 레시피 형식은 설명, 인사말, 결론 없이 [주어진 레시피]와 동일하게 '제목 - 재료 - 조리법' 순으로 작성할 것.
9. [냉장고 속 재료]가 너무 부족해 요리 성립이 어렵다고 판단되면 기존 레시피 형식을 무시하고 아래 형식으로만 답변할 것:
'현재 재료로는 레시피 변형이 어려워요. 
OO 재료를 더해주시면 훌륭한 요리가 될 것 같아요!'

[주어진 레시피 제목]
$recipeName
[주어진 레시피 재료]
$recipeIngredients
[주어진 레시피 조리법]
$manuals

[냉장고 속 재료]
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
          .timeout(const Duration(seconds: 30));

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
      if (!mounted) return;
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
                child: SelectableText(
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
