"""easybill REST API v1 client.

Auth: Bearer token (API key from easybill settings).
Docs: https://www.easybill.de/api/
"""
from __future__ import annotations

from pathlib import Path

import requests

API_BASE = "https://api.easybill.de/rest/v1"


class EasybillError(RuntimeError):
    pass


class EasybillClient:
    def __init__(self, api_key: str):
        if not api_key:
            raise ValueError("EASYBILL_API_KEY missing")
        self._session = requests.Session()
        self._session.headers.update({
            "Authorization": f"Bearer {api_key}",
            "Accept": "application/json",
        })

    def _request(self, method: str, path: str, **kwargs) -> requests.Response:
        url = f"{API_BASE}{path}"
        resp = self._session.request(method, url, timeout=60, **kwargs)
        if not resp.ok:
            raise EasybillError(f"{method} {path} -> {resp.status_code}: {resp.text}")
        return resp

    def find_customer_by_number(self, number: str) -> dict:
        resp = self._request("GET", "/customers", params={"number": number, "limit": 10})
        items = resp.json().get("items", [])
        for item in items:
            if str(item.get("number")) == str(number):
                return item
        raise EasybillError(f"Customer with number {number!r} not found")

    def list_customers(self, limit: int = 100) -> list[dict]:
        resp = self._request("GET", "/customers", params={"limit": limit})
        return resp.json().get("items", [])

    def create_invoice_draft(
        self,
        customer_id: int,
        description: str,
        quantity: float,
        single_price_net: float,
        vat_percent: float,
    ) -> dict:
        """Create a DRAFT invoice (status='DRAFT' = unfinished/editable)."""
        payload = {
            "customer_id": customer_id,
            "document_type": "INVOICE",
            "status": "DRAFT",
            "items": [
                {
                    "position": 1,
                    "description": description,
                    "quantity": quantity,
                    "single_price_net": single_price_net,
                    "vat_percent": vat_percent,
                }
            ],
        }
        resp = self._request("POST", "/documents", json=payload)
        return resp.json()

    def upload_attachment(self, file_path: Path, customer_id: int | None = None) -> dict:
        """Upload a file to easybill. Returns the attachment record (incl. id)."""
        with file_path.open("rb") as fh:
            files = {"file": (file_path.name, fh, "application/pdf")}
            data = {}
            if customer_id is not None:
                data["customer_id"] = str(customer_id)
            resp = self._session.post(
                f"{API_BASE}/file-attachments",
                files=files,
                data=data,
                timeout=120,
            )
        if not resp.ok:
            raise EasybillError(
                f"POST /file-attachments -> {resp.status_code}: {resp.text}"
            )
        return resp.json()

    def attach_file_to_document(self, document_id: int, attachment_id: int) -> dict:
        """Link an uploaded file-attachment to a document via document update."""
        payload = {"document_file_attachment_ids": [attachment_id]}
        resp = self._request("PUT", f"/documents/{document_id}", json=payload)
        return resp.json()

    def get_document_pdf(self, document_id: int, target: Path) -> Path:
        target.parent.mkdir(parents=True, exist_ok=True)
        url = f"{API_BASE}/documents/{document_id}/pdf"
        resp = self._session.get(
            url,
            headers={"Accept": "application/pdf"},
            timeout=60,
        )
        if not resp.ok:
            raise EasybillError(f"GET /documents/{document_id}/pdf -> {resp.status_code}: {resp.text}")
        target.write_bytes(resp.content)
        return target
