"""
Telegram Kalorientracker - Hauptdatei.

Flow:
- /start, /help, /heute, /undo: Befehle
- Foto: Claude Vision schaetzt + bestaetigen + loggen
- Reine Ziffern (8-14): EAN-Barcode -> Open Food Facts -> nach Gramm fragen
- Text: Claude parst Items + Open Food Facts Fallback -> bestaetigen + loggen
"""
from __future__ import annotations

import io
import logging
from html import escape

from telegram import InlineKeyboardButton, InlineKeyboardMarkup, Update
from telegram.constants import ChatAction, ParseMode
from telegram.ext import (
    ApplicationBuilder,
    CallbackQueryHandler,
    CommandHandler,
    ContextTypes,
    MessageHandler,
    filters,
)

import ai_estimator
import config
import food_lookup
import sheets

logging.basicConfig(
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    level=logging.INFO,
)
logger = logging.getLogger(__name__)
logging.getLogger("httpx").setLevel(logging.WARNING)


# ---------- Authorization ----------

def _is_authorized(user_id: int) -> bool:
    if not config.ALLOWED_USER_IDS:
        return True
    return user_id in config.ALLOWED_USER_IDS


async def _reject(update: Update) -> None:
    if update.message:
        await update.message.reply_text(
            "Du bist nicht berechtigt, diesen Bot zu nutzen."
        )


# ---------- Formatting helpers ----------

def _fmt_totals(totals: dict) -> str:
    return (
        f"<b>Heute bisher</b>\n"
        f"🔥 <b>{totals['kcal']:.0f}</b> kcal\n"
        f"🥩 {totals['protein']:.0f}g Eiweiß"
        f"   🍞 {totals['carbs']:.0f}g KH"
        f"   🧈 {totals['fat']:.0f}g Fett\n"
        f"📝 {totals['items']} Eintr{'ag' if totals['items'] == 1 else 'äge'}"
    )


def _fmt_preview(entries: list[dict]) -> str:
    total_kcal = sum(e["kcal"] for e in entries)
    total_p = sum(e["protein"] for e in entries)
    total_c = sum(e["carbs"] for e in entries)
    total_f = sum(e["fat"] for e in entries)

    lines = ["<b>Erkannt:</b>"]
    for e in entries:
        src = e.get("source", "")
        src_tag = f" <i>[{escape(src)}]</i>" if src else ""
        lines.append(
            f"• {escape(e['name'])} ({e['grams']:.0f}g): "
            f"{e['kcal']:.0f} kcal | "
            f"P {e['protein']:.0f} / KH {e['carbs']:.0f} / F {e['fat']:.0f}"
            f"{src_tag}"
        )
    lines.append("")
    lines.append(
        f"<b>Σ {total_kcal:.0f} kcal</b> "
        f"(P {total_p:.0f} / KH {total_c:.0f} / F {total_f:.0f})"
    )
    return "\n".join(lines)


def _confirm_keyboard() -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup([
        [
            InlineKeyboardButton("✅ Loggen", callback_data="confirm"),
            InlineKeyboardButton("❌ Abbrechen", callback_data="cancel"),
        ]
    ])


# ---------- Item assembly ----------

def _ai_item_to_entry(item: ai_estimator.FoodItem, source: str) -> dict:
    return {
        "name": item.name,
        "grams": item.grams,
        "kcal": item.kcal,
        "protein": item.protein,
        "carbs": item.carbs,
        "fat": item.fat,
        "source": source,
        "notes": "",
    }


def _off_to_entry(off: food_lookup.FoodEntry, grams: float, note: str = "") -> dict:
    factor = grams / 100.0
    return {
        "name": (f"{off.brand} {off.name}".strip() if off.brand else off.name),
        "grams": grams,
        "kcal": off.kcal_per_100 * factor,
        "protein": off.protein_per_100 * factor,
        "carbs": off.carbs_per_100 * factor,
        "fat": off.fat_per_100 * factor,
        "source": off.source,
        "notes": note,
    }


def _resolve_text_items(parsed: ai_estimator.ParsedMeal) -> list[dict]:
    """Versuche fuer jedes AI-Item Open Food Facts; fallback = AI-Schaetzung."""
    entries: list[dict] = []
    for item in parsed.items:
        off_entry = None
        if item.search_query:
            off_entry = food_lookup.search_by_name(item.search_query)
        if off_entry is not None:
            entries.append(_off_to_entry(off_entry, item.grams))
        else:
            entries.append(_ai_item_to_entry(item, source="KI-Schätzung"))
    return entries


# ---------- Command handlers ----------

async def cmd_start(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not _is_authorized(update.effective_user.id):
        await _reject(update)
        return
    await update.message.reply_text(
        "Hi! Schick mir was du gegessen hast — als Text, Foto oder Barcode.\n\n"
        "Beispiele:\n"
        "• <i>2 Eier mit Toast und Butter</i>\n"
        "• <i>Skyr Natur 200g</i>\n"
        "• 📷 Foto von deinem Teller\n"
        "• <code>4008400123456</code> (EAN-Barcode)\n\n"
        "Befehle:\n"
        "/heute — Tagesbilanz\n"
        "/undo — letzten Eintrag löschen\n"
        "/help — Hilfe",
        parse_mode=ParseMode.HTML,
    )


async def cmd_help(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    await cmd_start(update, context)


async def cmd_today(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not _is_authorized(update.effective_user.id):
        await _reject(update)
        return
    try:
        totals = sheets.today_totals()
    except Exception:
        logger.exception("today_totals failed")
        await update.message.reply_text("Konnte das Sheet gerade nicht lesen.")
        return
    await update.message.reply_text(_fmt_totals(totals), parse_mode=ParseMode.HTML)


async def cmd_undo(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not _is_authorized(update.effective_user.id):
        await _reject(update)
        return
    try:
        removed = sheets.remove_last_entry()
    except Exception:
        logger.exception("remove_last_entry failed")
        await update.message.reply_text("Konnte den letzten Eintrag nicht entfernen.")
        return
    if removed is None:
        await update.message.reply_text("Nichts zu löschen, das Log ist leer.")
        return
    await update.message.reply_text(
        f"❌ Entfernt: {removed['name']} ({removed['kcal']} kcal) "
        f"vom {removed['datum']} {removed['zeit']}"
    )


# ---------- Message handlers ----------

def _looks_like_barcode(text: str) -> bool:
    t = text.strip()
    return t.isdigit() and 8 <= len(t) <= 14


async def handle_text(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not _is_authorized(update.effective_user.id):
        await _reject(update)
        return
    text = (update.message.text or "").strip()
    if not text:
        return

    pending = context.user_data.get("pending")

    if pending and pending.get("type") == "barcode_grams":
        await _handle_barcode_grams_reply(update, context, text)
        return

    if _looks_like_barcode(text):
        await _handle_barcode(update, context, text)
        return

    await _handle_freetext(update, context, text)


async def _handle_barcode(
    update: Update, context: ContextTypes.DEFAULT_TYPE, ean: str
) -> None:
    await update.message.chat.send_action(ChatAction.TYPING)
    off = food_lookup.lookup_barcode(ean)
    if off is None:
        await update.message.reply_text(
            "Konnte den Barcode in Open Food Facts nicht finden. "
            "Schick mir stattdessen eine Beschreibung (z.B. <i>'Skyr Natur 200g'</i>).",
            parse_mode=ParseMode.HTML,
        )
        return

    context.user_data["pending"] = {"type": "barcode_grams", "off": off}
    name = f"{off.brand} {off.name}" if off.brand else off.name
    await update.message.reply_text(
        f"📦 Gefunden: <b>{escape(name)}</b>\n"
        f"({off.kcal_per_100:.0f} kcal / 100g)\n\n"
        f"Wie viele Gramm? Antworte mit einer Zahl.",
        parse_mode=ParseMode.HTML,
    )


async def _handle_barcode_grams_reply(
    update: Update, context: ContextTypes.DEFAULT_TYPE, text: str
) -> None:
    pending = context.user_data.pop("pending", None)
    if not pending:
        return
    off: food_lookup.FoodEntry = pending["off"]

    try:
        grams = float(text.replace(",", ".").replace("g", "").strip())
    except ValueError:
        context.user_data["pending"] = pending  # zuruecklegen
        await update.message.reply_text(
            "Bitte nur eine Zahl schicken (z.B. <code>150</code>).",
            parse_mode=ParseMode.HTML,
        )
        return

    entry = _off_to_entry(off, grams)
    context.user_data["pending"] = {"type": "confirm", "entries": [entry]}
    await update.message.reply_text(
        _fmt_preview([entry]),
        parse_mode=ParseMode.HTML,
        reply_markup=_confirm_keyboard(),
    )


async def _handle_freetext(
    update: Update, context: ContextTypes.DEFAULT_TYPE, text: str
) -> None:
    await update.message.chat.send_action(ChatAction.TYPING)
    try:
        parsed = ai_estimator.parse_text_meal(text)
    except Exception:
        logger.exception("parse_text_meal failed")
        await update.message.reply_text(
            "Konnte das gerade nicht parsen. Versuch's nochmal."
        )
        return

    if not parsed.items:
        await update.message.reply_text("Keine Lebensmittel erkannt.")
        return

    entries = _resolve_text_items(parsed)
    context.user_data["pending"] = {"type": "confirm", "entries": entries}
    await update.message.reply_text(
        _fmt_preview(entries),
        parse_mode=ParseMode.HTML,
        reply_markup=_confirm_keyboard(),
    )


async def handle_photo(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    if not _is_authorized(update.effective_user.id):
        await _reject(update)
        return
    await update.message.chat.send_action(ChatAction.TYPING)

    photo = update.message.photo[-1]  # groesste Variante
    file = await photo.get_file()
    buf = io.BytesIO()
    await file.download_to_memory(buf)
    jpeg_bytes = buf.getvalue()

    try:
        parsed = ai_estimator.analyze_photo(jpeg_bytes)
    except Exception:
        logger.exception("analyze_photo failed")
        await update.message.reply_text(
            "Konnte das Foto gerade nicht analysieren. Schick mir alternativ eine Textbeschreibung."
        )
        return

    if not parsed.items:
        await update.message.reply_text(
            "Auf dem Foto kein Essen erkannt. Schick mir eine Textbeschreibung."
        )
        return

    entries = [_ai_item_to_entry(item, source="KI-Foto") for item in parsed.items]
    context.user_data["pending"] = {"type": "confirm", "entries": entries}
    await update.message.reply_text(
        _fmt_preview(entries),
        parse_mode=ParseMode.HTML,
        reply_markup=_confirm_keyboard(),
    )


async def handle_button(update: Update, context: ContextTypes.DEFAULT_TYPE) -> None:
    query = update.callback_query
    if query is None:
        return
    if not _is_authorized(query.from_user.id):
        await query.answer("Nicht berechtigt.")
        return
    await query.answer()

    pending = context.user_data.pop("pending", None)
    if not pending or pending.get("type") != "confirm":
        await query.edit_message_text(
            (query.message.text_html or query.message.text or "")
            + "\n\n<i>(Eintrag bereits verarbeitet)</i>",
            parse_mode=ParseMode.HTML,
        )
        return

    if query.data == "cancel":
        await query.edit_message_text(
            (query.message.text_html or query.message.text or "")
            + "\n\n❌ <i>Abgebrochen.</i>",
            parse_mode=ParseMode.HTML,
        )
        return

    if query.data == "confirm":
        entries = pending["entries"]
        try:
            sheets.append_entries(entries)
        except Exception:
            logger.exception("append_entries failed")
            await query.edit_message_text(
                (query.message.text_html or query.message.text or "")
                + "\n\n⚠️ <i>Fehler beim Speichern.</i>",
                parse_mode=ParseMode.HTML,
            )
            return

        try:
            totals = sheets.today_totals()
            totals_str = "\n\n" + _fmt_totals(totals)
        except Exception:
            totals_str = ""

        await query.edit_message_text(
            (query.message.text_html or query.message.text or "")
            + "\n\n✅ <i>Geloggt.</i>"
            + totals_str,
            parse_mode=ParseMode.HTML,
        )


# ---------- Main ----------

def main() -> None:
    config.assert_configured()
    app = ApplicationBuilder().token(config.TELEGRAM_BOT_TOKEN).build()

    app.add_handler(CommandHandler("start", cmd_start))
    app.add_handler(CommandHandler("help", cmd_help))
    app.add_handler(CommandHandler(["heute", "today"], cmd_today))
    app.add_handler(CommandHandler("undo", cmd_undo))
    app.add_handler(MessageHandler(filters.PHOTO, handle_photo))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, handle_text))
    app.add_handler(CallbackQueryHandler(handle_button))

    logger.info("Bot startet...")
    app.run_polling(allowed_updates=Update.ALL_TYPES)


if __name__ == "__main__":
    main()
