# 냉장고 매니저 FastAPI 서버


## 깃허브 37차 수정 작업 정리

- 사진·영수증 식재료 인식 기능 추가 (POST /ai/recognize-ingredients)
- 사진을 Gemini에 보내서 식재료 목록을 받아옴. 식재료 사진인지, 영수증인지, 관련 없는 사진인지 자동 구분
- 영수증은 봉투·세제 같은 생활용품은 빼고 식재료만, 브랜드·중량 표기 뺀 일반 이름으로 정리
- AI가 앱에 없는 단위(kg, 봉지 등)나 카테고리를 주면 서버가 앱 선택지에 맞게 변환
- 사진은 서버에 저장하지 않음
- Gemini 모델 변경 + 예비 모델: 기본 모델을 3.5 flash-lite로 바꾸고, Gemini가 혼잡(503)하거나 사용량 초과(429)면 3.1 flash-lite로 자동 재시도
- Gemini 응답 시간·토큰 로그 추가, 사진 인식은 생각 단계를 최소로 해서 응답 속도 단축
- 로그 보안 정리: KAMIS·식약처 요청 URL에 API 키가 들어 있어서, 요청 로그와 에러 메시지에 키가 안 찍히게 수정
- 테스트 스크립트 server/tools/test_recognize.py: PC의 사진 파일로 인식 기능을 바로 테스트 (배포에는 포함 안 됨) <- 이거 사용법은 해당 파일 안에 적혀있습니다
- 냉장고 탭 메뉴에 "사진으로 추가" → 카메라 촬영 또는 앨범 선택
- 인식 결과 확인 화면: AI가 찾은 재료를 체크, 이름·수량·단위·카테고리·보관 방법·소비기한(기본 7일) 수정 가능, 빠진 재료 직접 추가 가능
- image_picker 패키지가 추가됨

## 팀원이 해야 할 것

git pull
flutter pub get



## 중요 안내사항
- .env에 사용중인 구글 키가 냉장고 매니저 프로젝트로 생성한 키라면 구글 AI 스튜디오에서 새 프로젝트(예: fridge-manager-gemini) 만들고 그 프로젝트로 만든 API 키로 바꾸기 바람. 서버를 배포하는 과정에서 Firebase 유료 전환을 해서 냉장고 매니저와 연결된 API를 사용하면 비용 청구되거나 사용이 안될 가능성이 있음
- 배포한 서버 주소는 따로 전달하겠음




# 배포 서버 설정 안내
## 기본 정보
- Google Cloud Run(서울 지역)에 서버 배포함
- Run and Debug(Ctrl+Shift+D)에서 배포 서버와 로컬 서버 중 하나를 선택해 에뮬레이터를 동작시킬 수 있음. 로컬 서버는 기존처럼 컴퓨터에서 서버를 실행해야 정보를 받아올 수 있음
- 서버 코드는 수정 후 재배포해야 배포 서버에 적용됨. 재배포 권한이 이쪽에만 있으니 깃허브에 올리면 재배포하겠음. 
- 서버 코드를 수정하고 테스트가 필요하다면 로컬 서버에서 하면 됨


## 최초 설정 (한 번만)
- .vscode/launch.json 파일 내용 아래로 수정 바람. `배포서버주소`라 적힌 부분만 서버 주소로 고쳐서 넣어주면 됨.

{
  "version": "0.2.0",
  "configurations": [
    {
      "name": "배포 서버",
      "type": "dart",
      "request": "launch",
      "program": "lib/main.dart",
      "args": ["--dart-define=API_BASE_URL=배포서버주소"]
    },
    {
      "name": "로컬 서버",
      "type": "dart",
      "request": "launch",
      "program": "lib/main.dart"
    },
  ]
}




# 로컬 서버 설정 안내
## 기본 정보
- 가격 동향, 레시피 추천/검색, AI 레시피 변형, 냉장고 분석 카드는 FastAPI 서버를 거쳐서 동작함
- 서버가 꺼져 있으면 위 기능들이 모두 동작하지 않음 (식재료 목록, 공유 냉장고는 서버 없이도 동작)
- API 키를 `.env` 파일에 넣고 이상 없이 돌아가면 launch.json에 있는 API키들은 지워도 됨
- 서버는 앱에 로그인한 사용자 요청만 받음 (Firebase 로그인 인증)
- http://localhost:8000/docs를 이용하기 위해선 웹 오른쪽 위 Authorize에 ID 토큰을 입력해야함
- ID 토큰은 에뮬레이터 실행 후 프로필에서 복사 버튼 누르면 받을 수 있음


## 최초 설정 (한 번만)
1. 컴퓨터에 Python 설치 (3.10 이후 버전)
- 설치됐는지는 터미널에서 `python --version` 으로 확인

2. `server` 폴더에 `.env` 파일 생성 
- 아래 내용 키값이랑 아이디 수정해서 복붙 (공개 안되도록 보안 주의)
- 파이어베이스프로젝트ID는 android/app/google-services.json 파일 안의 project_id 값임
```
KAMIS_CERT_KEY=키값
KAMIS_CERT_ID=아이디
FOOD_API_KEY=식약처키
GEMINI_API_KEY=제미나이키
FIREBASE_PROJECT_ID=파이어베이스프로젝트ID
```

3. 터미널에 아래 코드 순서대로 입력 
```
cd server
python -m venv venv
.\venv\Scripts\Activate.ps1
pip install -r requirements.txt
```


## 서버 실행 (매번 입력)
- 터미널에 아래 코드 순서대로 입력
- 새 터미널 열어서 거기다 실행시켜 놓으면 편함
- `cd server`는 터미널 경로가 fridge_manager> 일때 입력

```
cd server 
.\venv\Scripts\Activate.ps1
uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
```


## 주의점
- `git add .` 같은 명령 입력할 때 터미널 경로가 server> 이라면 server 폴더만 들어가니까 `cd ..` 입력하여 경로가 fridge_manager> 에 있는 상태에서 입력해야함


## 동작 확인
- 서버 동작 테스트: http://localhost:8000/docs → Authorize에 ID 토큰 입력 → GET /kamis/daily → Try it out 클릭 → Execute 클릭 → 아래 식품 목록이 나오면 정상
- 에뮬 & 서버 연결 테스트: 에뮬레이터 내부 Chrome에서 http://10.0.2.2:8000/health 접속 → {"status":"ok"} 나오면 정상
- 에뮬레이터 실행 후 서버 터미널에 401 Unauthorized 안나오면 정상