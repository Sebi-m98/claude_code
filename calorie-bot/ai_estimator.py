"""
Claude-basierte Estimator-Funktionen.

- parse_text_meal(text): Beschreibung in Items + geschaetzte Naehrwerte
- analyze_photo(jpeg_bytes): Foto -> Items + geschaetzte Naehrwerte
"""
from __future__ import annotations

import base64
import logging
from typing import List, Optional

import anthropic
from pydantic import BaseModel, Field

import config

logger = logging.getLogger(__name__)

MODEL = "claude-opus-4-7"

_client: anthropic.Anthropic | None = None


def _get_client() -> anthropic.Anthropic:
    global _client
    if _client is None:
        _client = anthropic.Anthropic(api_key=config.ANTHROPIC_API_KEY)
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


def parse_text_meal(text: str) -> ParsedMeal:
    """Parse eine deutsche Mahlzeitenbeschreibung in strukturierte Items."""
    client = _get_client()
    response = client.messages.parse(
        model=MODEL,
        max_tokens=2048,
        system=TEXT_SYSTEM,
        messages=[{"role": "user", "content": f"Was ich gegessen habe: {text}"}],
        output_format=ParsedMeal,
    )
    parsed = response.parsed_output
    if parsed is None:
        raise ValueError("Konnte Mahlzeit nicht parsen.")
    return parsed


def analyze_photo(jpeg_bytes: bytes) -> ParsedMeal:
    """Analysiere ein Mahlzeit-Foto."""
    client = _get_client()
    image_data = base64.standard_b64encode(jpeg_bytes).decode("utf-8")

    response = client.messages.parse(
        model=MODEL,
        max_tokens=2048,
        system=PHOTO_SYSTEM,
        messages=[
            {
                "role": "user",
                "content": [
                    {
                        "type": "image",
                        "source": {
                            "type": "base64",
                            "media_type": "image/jpeg",
                            "data": image_data,
                        },
                    },
                    {
                        "type": "text",
                        "text": "Analysiere diese Mahlzeit und schaetze die Naehrwerte.",
                    },
                ],
            }
        ],
        output_format=ParsedMeal,
    )
    parsed = response.parsed_output
    if parsed is None:
        raise ValueError("Konnte Foto nicht analysieren.")
    return parsed


def estimate_for_grams(name: str, grams: float) -> FoodItem:
    """Schaetze Naehrwerte fuer ein einzelnes Item mit bekannter Menge.

    Wird genutzt wenn der User z.B. einen Barcode + Gramm-Menge mit Custom-Beschreibung gibt.
    """
    client = _get_client()
    response = client.messages.parse(
        model=MODEL,
        max_tokens=512,
        system=TEXT_SYSTEM,
        messages=[
            {
                "role": "user",
                "content": f"Schaetze die Naehrwerte fuer: {grams}g {name}",
            }
        ],
        output_format=ParsedMeal,
    )
    parsed = response.parsed_output
    if parsed is None or not parsed.items:
        raise ValueError("Schaetzung fehlgeschlagen.")
    return parsed.items[0]
