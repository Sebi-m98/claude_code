"""
Gemini-basierte Estimator-Funktionen.

- parse_text_meal(text): Beschreibung in Items + geschaetzte Naehrwerte
- analyze_photo(jpeg_bytes): Foto -> Items + geschaetzte Naehrwerte
"""
from __future__ import annotations

import logging
from typing import List, Optional

from google import genai
from google.genai import types
from pydantic import BaseModel, Field

import config

logger = logging.getLogger(__name__)

MODEL = "gemini-2.5-flash"

_client: genai.Client | None = None


def _get_client() -> genai.Client:
    global _client
    if _client is None:
        _client = genai.Client(api_key=config.GEMINI_API_KEY)
    return _client


class FoodItem(BaseModel):
    name: str = Field(description="Kurzer Name des Lebensmittels, z.B. 'Ei', 'Vollkornbrot'.")
    grams: float = Field(description="Geschaetzte Portionsgroesse in Gramm.")
    search_query: Optional[str] = Field(
        default=None,
        description=(
            "Optional: Suchbegriff fuer Open Food Facts, falls dies ein "
            "verpacktes Produkt sein koennte (z.B. 'Barilla Spaghetti'). "
            "Bei selbstgemachten/zubereiteten Mahlzeiten oder Restaurantessen leer lassen."
        ),
    )
    kcal: float = Field(description="Kalorien fuer die geschaetzte Portion.")
    protein: float = Field(description="Eiweiss in g fuer die Portion.")
    carbs: float = Field(description="Kohlenhydrate in g fuer die Portion.")
    fat: float = Field(description="Fett in g fuer die Portion.")


class ParsedMeal(BaseModel):
    items: List[FoodItem] = Field(description="Liste der erkannten Lebensmittel.")
    summary: str = Field(description="Kurze Zusammenfassung der Mahlzeit auf Deutsch (max 1 Satz).")


TEXT_SYSTEM = """Du bist ein praeziser Ernaehrungs-Parser fuer einen Kalorientracking-Bot.
Der User schickt dir auf Deutsch was er gegessen hat. Zerlege es in einzelne Lebensmittel
und schaetze fuer jedes:
- Name und Portionsgroesse in Gramm
- Naehrwerte (Kalorien, Eiweiss, Kohlenhydrate, Fett) fuer DIESE Portion (nicht pro 100g)

Wenn keine Menge angegeben ist, nimm typische Portionen an (z.B. 1 Ei = 60g, 1 Scheibe Toast = 30g).
Sei konservativ realistisch, nicht uebertrieben optimistisch.

WICHTIG: Wenn ein Item ein verpacktes Markenprodukt sein koennte (z.B. 'Skyr Natur', 'Barilla Spaghetti'),
gib einen kurzen `search_query` an, damit wir Open Food Facts pruefen koennen.
Bei selbstgemachten Gerichten, Restaurant-Essen, frischem Obst/Gemuese, einfachen Zutaten:
search_query LEER lassen - dann werden deine Schaetzungen direkt verwendet.
"""


PHOTO_SYSTEM = """Du analysierst Fotos von Mahlzeiten fuer einen Kalorientracking-Bot.
Schaetze pro sichtbarem Lebensmittel:
- Name und Portionsgroesse in Gramm (anhand visueller Hinweise wie Tellergroesse, Besteck etc.)
- Naehrwerte fuer DIESE Portion

Sei realistisch, schaetze konservativ. Fuer Fotos KEIN search_query zurueckgeben - direkte Schaetzung."""


def _generate(contents, system: str) -> ParsedMeal:
    client = _get_client()
    response = client.models.generate_content(
        model=MODEL,
        contents=contents,
        config=types.GenerateContentConfig(
            system_instruction=system,
            response_mime_type="application/json",
            response_schema=ParsedMeal,
        ),
    )
    parsed = response.parsed
    if parsed is None:
        raise ValueError(f"Gemini-Antwort konnte nicht geparsed werden: {response.text!r}")
    return parsed


def parse_text_meal(text: str) -> ParsedMeal:
    """Parse eine deutsche Mahlzeitenbeschreibung in strukturierte Items."""
    return _generate(f"Was ich gegessen habe: {text}", system=TEXT_SYSTEM)


def analyze_photo(jpeg_bytes: bytes) -> ParsedMeal:
    """Analysiere ein Mahlzeit-Foto."""
    return _generate(
        contents=[
            types.Part.from_bytes(data=jpeg_bytes, mime_type="image/jpeg"),
            "Analysiere diese Mahlzeit und schaetze die Naehrwerte.",
        ],
        system=PHOTO_SYSTEM,
    )


def estimate_for_grams(name: str, grams: float) -> FoodItem:
    """Schaetze Naehrwerte fuer ein einzelnes Item mit bekannter Menge."""
    parsed = _generate(f"Schaetze die Naehrwerte fuer: {grams}g {name}", system=TEXT_SYSTEM)
    if not parsed.items:
        raise ValueError("Schaetzung fehlgeschlagen.")
    return parsed.items[0]
