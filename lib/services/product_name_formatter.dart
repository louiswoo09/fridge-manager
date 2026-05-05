class ProductNameFormatter {
  ProductNameFormatter._();

  static const Map<String, String> _nameOverride = {
    '풋고추/풋고추(녹광 등)': '풋고추',
    '고구마/밤': '밤고구마',
  };

  static const List<String> _stripPrefix = ['풋고추'];

  /// KAMIS API 응답 item에서 표시용 이름 생성
  static String format(Map<String, dynamic> item) {
    final productNameRaw = item['productName']?.toString() ?? '';
    final categoryCode = item['category_code']?.toString() ?? '';

    // 매핑 테이블 우선
    if (_nameOverride.containsKey(productNameRaw)) {
      return _nameOverride[productNameRaw]!;
    }
    if (productNameRaw.isEmpty) {
      return item['item_name']?.toString() ?? '';
    }

    final parts = productNameRaw.split('/');
    if (parts.length == 2) {
      final front = parts[0].trim();
      final back = parts[1].trim();

      // 앞 단어 제거 대상이면 뒤만
      if (_stripPrefix.contains(front)) return back;
      // 뒤에 앞이 포함되면 뒤만 (예: 콩/흰 콩(국산) → 흰 콩(국산))
      if (back.contains(front)) return back;
      // 축산물(500)은 슬래시를 공백으로
      if (categoryCode == '500') return '$front $back';
      // 백색(국산) → 백색)(국산 으로 변환해서 참깨(백색)(국산) 형태로
      if (back.contains('(')) {
        final cleaned = back.replaceFirst('(', ')(');
        return '$front($cleaned';
      }
      // 그 외는 슬래시를 괄호로 감싸기
      return '$front($back)';
    }
    return productNameRaw;
  }
}