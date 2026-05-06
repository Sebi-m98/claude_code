"""Toggl Track Reports API v3 client.

Auth: Basic Auth with `<API_TOKEN>:api_token`.
Docs: https://engineering.toggl.com/docs/reports/detailed_reports/
"""
from __future__ import annotations

import calendar
from dataclasses import dataclass
from datetime import date
from pathlib import Path

import requests

API_BASE = "https://api.track.toggl.com/reports/api/v3"
PAGE_SIZE = 1000


@dataclass(frozen=True)
class MonthRange:
    start: date
    end: date

    @classmethod
    def for_month(cls, year: int, month: int) -> "MonthRange":
        last_day = calendar.monthrange(year, month)[1]
        return cls(date(year, month, 1), date(year, month, last_day))

    @property
    def label(self) -> str:
        return self.start.strftime("%Y-%m")


class TogglClient:
    def __init__(self, api_token: str, workspace_id: str | int):
        if not api_token:
            raise ValueError("TOGGL_API_TOKEN missing")
        if not workspace_id:
            raise ValueError("TOGGL_WORKSPACE_ID missing")
        self.workspace_id = str(workspace_id)
        self._auth = (api_token, "api_token")

    def _search_url(self, suffix: str = "") -> str:
        return f"{API_BASE}/workspace/{self.workspace_id}/search/time_entries{suffix}"

    def total_seconds(self, period: MonthRange) -> int:
        """Sum duration of all time entries in the given month, paginated."""
        total = 0
        next_id: int | None = None
        next_row: int | None = None
        while True:
            body: dict = {
                "start_date": period.start.isoformat(),
                "end_date": period.end.isoformat(),
                "page_size": PAGE_SIZE,
            }
            if next_id is not None:
                body["first_id"] = next_id
            if next_row is not None:
                body["first_row_number"] = next_row

            resp = requests.post(self._search_url(), json=body, auth=self._auth, timeout=60)
            resp.raise_for_status()
            entries = resp.json()
            for entry in entries:
                for item in entry.get("time_entries", []):
                    seconds = item.get("seconds")
                    if seconds is None:
                        # Fallback: compute from start/stop if needed
                        continue
                    total += int(seconds)

            next_id_header = resp.headers.get("X-Next-ID")
            next_row_header = resp.headers.get("X-Next-Row-Number")
            if not next_id_header or not next_row_header:
                break
            next_id = int(next_id_header)
            next_row = int(next_row_header)
        return total

    def download_detailed_pdf(self, period: MonthRange, target: Path) -> Path:
        """POST .../search/time_entries.pdf and write the bytes to `target`."""
        target.parent.mkdir(parents=True, exist_ok=True)
        body = {
            "start_date": period.start.isoformat(),
            "end_date": period.end.isoformat(),
            "date_format": "DD.MM.YYYY",
            "duration_format": "improved",
            "display_mode": "date_and_time",
        }
        resp = requests.post(
            self._search_url(".pdf"),
            json=body,
            auth=self._auth,
            timeout=120,
        )
        resp.raise_for_status()
        target.write_bytes(resp.content)
        return target


def hours_from_seconds(seconds: int) -> float:
    """Convert seconds to exact decimal hours, rounded to 4 decimals to avoid float noise."""
    return round(seconds / 3600, 4)
