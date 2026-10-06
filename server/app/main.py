from fastapi import FastAPI

app = FastAPI(title="냉장고 매니저 API")


@app.get("/health")
def health():
    return {"status": "ok"}