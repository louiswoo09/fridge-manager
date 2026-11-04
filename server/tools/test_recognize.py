"""
사진 인식 테스트 코드입니다

사용법:
- 로컬 서버 실행시킨 상태에서 다른 터미널에 아래 코드 입력하세요
- 넣을사진파일경로 <- 이거를 컴퓨터에 있는 사진 경로로 바꿔서 입력해야 합니다
- 사진 파일은 jpg, jpeg, jfif, png, webp만 가능합니다
- 코드 입력하면 토큰 입력하라고 하는데 에뮬레이터 프로필의 '개발용: ID 토큰 복사' 버튼으로 복사해서 붙여넣으세요
- pip install pillow <- 이 명령어는 맨처음 한번만 입력해서 설치하는거입니다
- 사진은 띄어쓰기로 구분해서 최대 5장까지 넣을 수 있습니다

cd server
.\venv\Scripts\Activate.ps1
pip install pillow
python tools/test_recognize.py 사진파일경로1 사진파일경로2 사진파일경로3
"""

import base64
import json
import os
import sys
import time
from io import BytesIO

import httpx
from PIL import Image, ImageOps   # 변경: ImageOps 추가

if len(sys.argv) < 2:
    print("사진 경로가 입력되지 않았습니다. 형식: python tools/test_recognize.py 사진파일경로1 사진파일경로2 ...")
    sys.exit(1)

paths = sys.argv[1:]   # 변경: 여러 장
if len(paths) > 5:
    print("사진은 최대 5장까지 가능합니다")
    sys.exit(1)

images = []   # 변경: 사진마다 줄여서 목록에 담기
for path in paths:
    ext = path.lower().rsplit(".", 1)[-1]
    if ext not in ("jpg", "jpeg", "jfif", "png", "webp"):
        print(f"jpg, jpeg, jfif, png, webp 파일만 가능합니다: {path}")
        sys.exit(1)

    # 앱과 같은 조건으로 줄이기: 긴 변 1280px, JPEG 품질 85
    img = ImageOps.exif_transpose(Image.open(path)).convert("RGB")   # 변경: 폰 사진 회전 반영
    original_size = img.size
    img.thumbnail((1280, 1280))
    buf = BytesIO()
    img.save(buf, "JPEG", quality=85)
    data = buf.getvalue()

    print(f"[{os.path.basename(path)}]")
    print(f"  원본: {os.path.getsize(path) / 1024:.0f}KB ({original_size[0]}x{original_size[1]})")
    print(f"  전송: {len(data) / 1024:.0f}KB ({img.size[0]}x{img.size[1]})")

    images.append({"data": base64.b64encode(data).decode(), "mime_type": "image/jpeg"})

token = input("ID 토큰을 입력하세요: ").strip()

start = time.perf_counter()
res = httpx.post(
    "http://127.0.0.1:8000/ai/recognize-ingredients",
    json={"images": images},   # 변경: 서버 새 형식
    headers={"Authorization": f"Bearer {token}"},
    timeout=200,   # 변경: 예비 모델 재시도까지 여유
)
elapsed = time.perf_counter() - start

print(f"{res.status_code} ({elapsed:.1f}초, 사진 {len(images)}장)")
print(json.dumps(res.json(), ensure_ascii=False, indent=2))