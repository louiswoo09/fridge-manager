/// 자주 섞여 쓰이는 표기 → 하나로 통일 (비교할 때만 사용)
const _nameAliases = {
  '메론': '멜론',
  '샤인머스켓': '샤인머스캣',
  '소세지': '소시지',
  '쭈꾸미': '주꾸미',
  '브로컬리': '브로콜리',
  '참다래': '키위',
  '케찹': '케첩',
};

/// 비교용 이름: 괄호 내용 제거, 공백 제거, 표기 통일
String normalizeIngredientName(String name) {
  var result = name.replaceAll(RegExp(r'\([^)]*\)'), '').replaceAll(' ', '').trim();
  _nameAliases.forEach((from, to) => result = result.replaceAll(from, to));
  return result;
}

/// 같은 재료인지: 같거나, 앞에 꾸밈말만 붙은 경우 (적양파 = 양파 O, 고등어회 = 고등어 X)
bool isSameIngredientName(String a, String b) {
  if (a.isEmpty || b.isEmpty) return false;
  if (a == b) return true;
  final shorter = a.length <= b.length ? a : b;
  final longer = a.length <= b.length ? b : a;
  return shorter.length >= 2 && longer.endsWith(shorter);
}