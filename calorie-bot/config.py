import os
from dotenv import load_dotenv

load_dotenv()

TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "").strip()
ANTHROPIC_API_KEY = os.getenv("ANTHROPIC_API_KEY", "").strip()
GOOGLE_SHEETS_ID = os.getenv("GOOGLE_SHEETS_ID", "").strip()
GOOGLE_CREDENTIALS_PATH = os.getenv("GOOGLE_CREDENTIALS_PATH", "./credentials.json").strip()

_allowed = os.getenv("ALLOWED_USER_IDS", "").strip()
ALLOWED_USER_IDS: set[int] = (
    {int(x.strip()) for x in _allowed.split(",") if x.strip()} if _allowed else set()
)


def assert_configured() -> None:
    missing = []
    if not TELEGRAM_BOT_TOKEN:
        missing.append("TELEGRAM_BOT_TOKEN")
    if not ANTHROPIC_API_KEY:
        missing.append("ANTHROPIC_API_KEY")
    if not GOOGLE_SHEETS_ID:
        missing.append("GOOGLE_SHEETS_ID")
    if not os.path.exists(GOOGLE_CREDENTIALS_PATH):
        missing.append(f"Credentials-Datei unter {GOOGLE_CREDENTIALS_PATH}")
    if missing:
        raise RuntimeError(
            "Fehlende Konfiguration: " + ", ".join(missing) +
            "\nSiehe README.md fuer Setup-Anleitung."
        )
