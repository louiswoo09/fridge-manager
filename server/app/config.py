import os
from dotenv import load_dotenv

load_dotenv()  # server/.env 를 찾아서 환경변수로 읽음


class Settings:
    kamis_cert_key: str = os.getenv("KAMIS_CERT_KEY", "")
    kamis_cert_id: str = os.getenv("KAMIS_CERT_ID", "")


settings = Settings()