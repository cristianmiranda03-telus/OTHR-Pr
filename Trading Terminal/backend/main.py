"""
Quant-Joker Trader - Backend API.
Run: uvicorn main:app --reload --host 0.0.0.0 --port 8000
"""
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from config.settings import settings
from api.mt5 import router as mt5_router
from api.sessions import router as sessions_router
from api.strategies import router as strategies_router
from api.market import router as market_router
from api.news import router as news_router
from api.agents import router as agents_router

app = FastAPI(title=settings.APP_NAME, version="2.0.0", description="AI-Powered Agentic Trading Platform")

app.add_middleware(
    CORSMiddleware,
    allow_origins=[settings.FRONTEND_URL, "http://localhost:3000"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(mt5_router)
app.include_router(sessions_router)
app.include_router(strategies_router)
app.include_router(market_router)
app.include_router(news_router)
app.include_router(agents_router)


@app.get("/")
def root():
    return {
        "app": settings.APP_NAME,
        "version": "2.0.0",
        "status": "ok",
        "docs": "/docs",
        "ai_provider": settings.AI_PROVIDER,
        "model": settings.FUELIX_MODEL,
    }


@app.get("/health")
def health():
    return {"status": "healthy", "app": settings.APP_NAME}
