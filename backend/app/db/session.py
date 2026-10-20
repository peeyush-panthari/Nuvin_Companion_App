import os
from typing import AsyncGenerator
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.orm import declarative_base
from backend.app.config import settings

Base = declarative_base()

def get_engine_url() -> str:
    if settings.USE_SQLITE_FALLBACK and not os.getenv("FORCE_POSTGRES"):
        # Local SQLite for testing & zero-setup local dev
        return f"sqlite+aiosqlite:///{settings.SQLITE_DB_PATH}"
    return settings.DATABASE_URL

engine = create_async_engine(
    get_engine_url(),
    echo=False,
    future=True
)

AsyncSessionLocal = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autocommit=False,
    autoflush=False
)

async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with AsyncSessionLocal() as session:
        try:
            yield session
        finally:
            await session.close()
