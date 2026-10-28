"""
사진 인식 테스트 코드입니다

사용법:
- 로컬 서버 실행시킨 상태에서 다른 터미널에 아래 코드 입력하세요
- 넣을사진파일경로 <- 이거를 컴퓨터에 있는 사진 경로로 바꿔서 입력해야 합니다
- 사진 파일은 jpg, jpeg, jfif, png, webp만 가능합니다
- 코드 입력하면 토큰 입력하라고 하는데 에뮬레이터 프로필의 '개발용: ID 토큰 복사' 버튼으로 복사해서 붙여넣으세요
- pip install pillow <- 이 명령어는 맨처음 한번만 입력해서 설치하는거입니다

cd server
.\venv\Scripts\Activate.ps1
pip install pillow
python tools/test_recognize.py 넣을사진파일경로
"""

import base64
import json
import os
import sys
import time
from io import BytesIO

import httpx
from PIL import Image

if len(sys.argv) < 2:
    print("사진 경로가 입력되지 않았습니다. 형식: python tools/test_recognize.py 사진파일경로")
    sys.exit(1)

path = sys.argv[1]
ext = path.lower().rsplit(".", 1)[-1]
if ext not in ("jpg", "jpeg", "jfif", "png", "webp"):
    print("jpg, jpeg, jfif, png, webp 파일만 가능합니다")
    sys.exit(1)

# 앱과 같은 조건으로 줄이기: 긴 변 1280px, JPEG 품질 85
img = Image.open(path).convert("RGB")
original_size = img.size
img.thumbnail((1280, 1280))
buf = BytesIO()
img.save(buf, "JPEG", quality=85)
data = buf.getvalue()

print(f"원본: {os.path.getsize(path) / 1024:.0f}KB ({original_size[0]}x{original_size[1]})")
print(f"전송: {len(data) / 1024:.0f}KB ({img.size[0]}x{img.size[1]})")

token = input("ID 토큰을 입력하세요: ").strip()

start = time.perf_counter()
res = httpx.post(
    "http://127.0.0.1:8000/ai/recognize-ingredients",
    json={"image_base64": base64.b64encode(data).decode(), "mime_type": "image/jpeg"},
    headers={"Authorization": f"Bearer {token}"},
    timeout=120,
)
elapsed = time.perf_counter() - start

print(f"{res.status_code} ({elapsed:.1f}초)")
print(json.dumps(res.json(), ensure_ascii=False, indent=2))