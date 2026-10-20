import os
from pathlib import Path
from dotenv import load_dotenv
from pydantic_settings import BaseSettings

# Load .env from backend/.env or current working directory
env_path = Path(__file__).resolve().parent.parent / ".env"
load_dotenv(dotenv_path=env_path)
load_dotenv()

class Settings(BaseSettings):
    PROJECT_NAME: str = "Nuvin Backend"
    VERSION: str = "0.1.0"
    API_V1_STR: str = "/api/v1"
    
    # Database
    DATABASE_URL: str = os.getenv(
        "DATABASE_URL", 
        "postgresql+asyncpg://postgres:postgres@localhost:5432/nuvin"
    )
    # Fallback to local SQLite for local dev/testing if Postgres isn't active
    USE_SQLITE_FALLBACK: bool = os.getenv("USE_SQLITE_FALLBACK", "true").lower() == "true"
    SQLITE_DB_PATH: str = os.getenv("SQLITE_DB_PATH", "backend/nuvin_dev.db")
    
    # Security & Tokens
    SECRET_KEY: str = os.getenv("SECRET_KEY", "nuvin-super-secure-production-secret-key-2026")
    LIVE_TRACKING_BASE_URL: str = os.getenv("LIVE_TRACKING_BASE_URL", "http://localhost:8000/sos/live")
    GOOGLE_MAPS_API_KEY: str = os.getenv("GOOGLE_MAPS_API_KEY", "")
    
    # Gemini LLM
    GEMINI_API_KEY: str = os.getenv("GEMINI_API_KEY", "")
    GEMINI_MODEL: str = os.getenv("GEMINI_MODEL", "gemini-3.1-pro-preview")
    GEMINI_FALLBACK_MODEL: str = os.getenv("GEMINI_FALLBACK_MODEL", "gemini-3.8-flash")

    # OpenAI / ChatGPT Moderation API
    OPENAI_API_KEY: str = os.getenv("OPENAI_API_KEY", "")
    OPENAI_MODERATION_MODEL: str = os.getenv("OPENAI_MODERATION_MODEL", "omni-moderation-latest")

    # Local LLM (Ollama)
    OLLAMA_BASE_URL: str = os.getenv("OLLAMA_BASE_URL", "http://127.0.0.1:11434")
    OLLAMA_MODEL: str = os.getenv("OLLAMA_MODEL", "llama3.1:8b")
    USE_OLLAMA_LOCAL: bool = os.getenv("USE_OLLAMA_LOCAL", "false").lower() == "true"

    # Helplines (India)
    HELPLINE_KIRAN: str = "1800-599-0019"
    HELPLINE_TELE_MANAS: str = "14416"
    HELPLINE_EMERGENCY_NATIONAL: str = "112"

    model_config = {"case_sensitive": True}

settings = Settings()
