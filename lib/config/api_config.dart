/// 개발 기본값: 에뮬레이터에서 PC 서버 (10.0.2.2 = PC의 127.0.0.1)
/// 배포 후엔 --dart-define=API_BASE_URL=https://... 로 바꿔서 실행
const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://10.0.2.2:8000',
);