# 냉장고 매니저 FastAPI 서버 설정 안내

- 안내사항: 이제 FastAPI 서버가 꺼져 있으면 가격 동향 탭이 동작하지 않음

## 최초 설정 (한 번만)
1. 컴퓨터에 Python 설치 (3.10 이후 버전)
- 설치됐는지는 터미널에서 `python --version` 으로 확인 

2. `server` 폴더에 `.env` 파일 생성 
- 아래 내용 키값이랑 아이디 수정해서 복붙 (공개 안되도록 보안 주의)
```
KAMIS_CERT_KEY=키값
KAMIS_CERT_ID=아이디
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

- 서버 동작 테스트: 인터넷 브라우저에서 http://localhost:8000/docs -> GET /kamis/daily 클릭 → Try it out 클릭 → Execute 클릭→ 아래에 식품 목록이 나오면 정상
- 에뮬 & 서버 연결 테스트: 에뮬레이터 내부 Chrome에서 http://10.0.2.2:8000/health 접속 → {"status":"ok"} 나오면 정상