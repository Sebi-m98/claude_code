"""
Open Food Facts Lookup.

Zwei Funktionen:
- lookup_barcode(ean): direkte Suche per EAN/Barcode
- search_by_name(query): Volltextsuche, gibt das beste Ergebnis zurueck
"""
from __future__ import annotations

import logging
from dataclasses import dataclass

import requests

logger = logging.getLogger(__name__)

OFF_BASE = "https://world.openfoodfacts.org"
USER_AGENT = "telegram-calorie-bot/1.0 (personal-use)"
TIMEOUT = 10


@dataclass
class FoodEntry:
    """Pro 100 g/ml Naehrwerte aus OFF."""

    name: str
    brand: str | None
    kcal_per_100: float
    protein_per_100: float
    carbs_per_100: float
    fat_per_100: float
    fiber_per_100: float | None
    source: str  # "OFF-Barcode" oder "OFF-Suche"
    barcode: str | None = None


def _extract_nutriments(product: dict) -> dict | None:
    nutriments = product.get("nutriments") or {}
    kcal = nutriments.get("energy-kcal_100g")
    if kcal is None:
        # Manche Eintraege haben nur kJ
        kj = nutriments.get("energy_100g") or nutriments.get("energy-kj_100g")
        if kj is None:
            return None
        kcal = float(kj) / 4.184

    return {
        "kcal": float(kcal),
        "protein": float(nutriments.get("proteins_100g") or 0),
        "carbs": float(nutriments.get("carbohydrates_100g") or 0),
        "fat": float(nutriments.get("fat_100g") or 0),
        "fiber": float(nutriments.get("fiber_100g")) if nutriments.get("fiber_100g") is not None else None,
    }


def _to_entry(product: dict, source: str) -> FoodEntry | None:
    n = _extract_nutriments(product)
    if n is None:
        return None
    name = (
        product.get("product_name_de")
        or product.get("product_name")
        or product.get("generic_name_de")
        or product.get("generic_name")
        or "Unbekanntes Produkt"
    )
    return FoodEntry(
        name=str(name).strip(),
        brand=(product.get("brands") or "").split(",")[0].strip() or None,
        kcal_per_100=n["kcal"],
        protein_per_100=n["protein"],
        carbs_per_100=n["carbs"],
        fat_per_100=n["fat"],
        fiber_per_100=n["fiber"],
        source=source,
        barcode=product.get("code"),
    )


def lookup_barcode(ean: str) -> FoodEntry | None:
    ean = ean.strip()
    if not ean.isdigit():
        return None
    url = f"{OFF_BASE}/api/v2/product/{ean}.json"
    try:
        resp = requests.get(
            url,
            headers={"User-Agent": USER_AGENT},
            timeout=TIMEOUT,
            params={"fields": "code,product_name,product_name_de,generic_name,generic_name_de,brands,nutriments"},
        )
        resp.raise_for_status()
        data = resp.json()
    except requests.RequestException as e:
        logger.warning("OFF Barcode-Lookup fehlgeschlagen: %s", e)
        return None

    if data.get("status") != 1:
        return None
    return _to_entry(data.get("product") or {}, source="OFF-Barcode")


def search_by_name(query: str) -> FoodEntry | None:
    query = query.strip()
    if not query:
        return None
    url = f"{OFF_BASE}/cgi/search.pl"
    try:
        resp = requests.get(
            url,
            headers={"User-Agent": USER_AGENT},
            timeout=TIMEOUT,
            params={
                "search_terms": query,
                "search_simple": 1,
                "action": "process",
                "json": 1,
                "page_size": 5,
                "fields": "code,product_name,product_name_de,generic_name,generic_name_de,brands,nutriments,countries_tags",
            },
        )
        resp.raise_for_status()
        data = resp.json()
    except requests.RequestException as e:
        logger.warning("OFF Suche fehlgeschlagen: %s", e)
        return None

    products = data.get("products") or []
    # Bevorzuge deutsche Eintraege, dann den ersten mit gueltigen Naehrwerten
    products.sort(
        key=lambda p: (
            0 if "en:germany" in (p.get("countries_tags") or []) else 1,
        )
    )
    for p in products:
        entry = _to_entry(p, source="OFF-Suche")
        if entry is not None and entry.kcal_per_100 > 0:
            return entry
    return None
