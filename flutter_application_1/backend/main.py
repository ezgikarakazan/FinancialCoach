from collections import defaultdict
from datetime import date, datetime, timedelta, timezone
from decimal import Decimal
from typing import Any, List
from uuid import uuid4
import hashlib
import os
import re
import secrets
import statistics
import unicodedata

from dotenv import load_dotenv
from fastapi import Depends, FastAPI, File, Form, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt
from passlib.context import CryptContext
from pydantic import BaseModel, ConfigDict, EmailStr
from sqlalchemy.exc import IntegrityError
from sqlalchemy import func
from sqlalchemy.orm import Session

from database import (
    SessionLocal,
    engine,
    ensure_pdf_upload_statement_type_columns,
    ensure_transaction_source_type_column,
    ensure_transaction_classification_columns,
    ensure_description_columns,
    ensure_transaction_user_id_column,
    ensure_user_login_security_columns,
    ensure_user_access_columns,
    ensure_plan_payment_day_column,
)
from models.transaction import Base, Transaction
from models.user import User
from models.pdf_upload import PdfUpload, PdfUploadItem
from models.plan import Plan, PlanEntry

load_dotenv()


app = FastAPI(
    title="AI Finance Coach API",
    version="1.0.0",
)

Base.metadata.create_all(bind=engine)
ensure_transaction_user_id_column()
ensure_user_login_security_columns()
ensure_user_access_columns()
ensure_transaction_source_type_column()
ensure_transaction_classification_columns()
ensure_description_columns()
ensure_pdf_upload_statement_type_columns()
ensure_plan_payment_day_column()

configured_admin_email = os.getenv("ADMIN_EMAIL", "").strip().lower()
if configured_admin_email:
    with SessionLocal() as startup_db:
        configured_admin = (
            startup_db.query(User)
            .filter(User.email == configured_admin_email)
            .first()
        )
        if configured_admin is not None and configured_admin.role != "admin":
            configured_admin.role = "admin"
            startup_db.commit()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["*"],
    expose_headers=["*"],
)


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def _load_or_create_jwt_secret() -> str:
    env_secret = os.getenv("JWT_SECRET")
    if env_secret:
        return env_secret

    secret_file = os.path.join(os.path.dirname(__file__), ".jwt_secret")
    if os.path.exists(secret_file):
        with open(secret_file, "r", encoding="utf-8") as f:
            saved = f.read().strip()
            if saved:
                return saved

    generated = secrets.token_hex(32)
    with open(secret_file, "w", encoding="utf-8") as f:
        f.write(generated)

    print(
        "UYARI: JWT_SECRET ortam degiskeni/.env dosyasi ayarlanmamis. "
        "Gelistirme icin rastgele bir anahtar uretilip backend/.jwt_secret dosyasina "
        "kaydedildi. Production'da mutlaka JWT_SECRET ortam degiskenini ayarlayin."
    )
    return generated


JWT_SECRET = _load_or_create_jwt_secret()
JWT_ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24 * 7

pwd_context = CryptContext(schemes=["pbkdf2_sha256"], deprecated="auto")
bearer_scheme = HTTPBearer(auto_error=False)


def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def verify_password(plain_password: str, password_hash: str) -> bool:
    return pwd_context.verify(plain_password, password_hash)


def create_access_token(user_id: int) -> str:
    now = datetime.now(timezone.utc)
    expire = now + timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    payload = {
        "sub": str(user_id),
        "iat": int(now.timestamp()),
        "exp": int(expire.timestamp()),
    }
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)


def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
    db: Session = Depends(get_db),
) -> User:
    if credentials is None:
        raise HTTPException(status_code=401, detail="Yetkisiz erişim")

    token = credentials.credentials

    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        sub = payload.get("sub")
        if not sub:
            raise HTTPException(status_code=401, detail="Geçersiz token")
        user_id = int(sub)
    except (JWTError, ValueError):
        raise HTTPException(status_code=401, detail="Geçersiz token")

    user = db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=401, detail="Kullanıcı bulunamadı")

    return user


class TransactionCreate(BaseModel):
    title: str
    amount: Decimal
    category: str
    date: date
    source_type: str = "bank"
    transaction_type: str | None = None
    institution_name: str | None = None


class TransactionOut(BaseModel):
    id: int
    title: str
    description: str = ""
    amount: Decimal
    category: str
    date: date
    source_type: str
    transaction_type: str
    institution_name: str

    model_config = ConfigDict(from_attributes=True)


class RegisterRequest(BaseModel):
    name: str
    email: EmailStr
    password: str


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class UpdateProfileRequest(BaseModel):
    name: str
    email: EmailStr


class ChangePasswordRequest(BaseModel):
    current_password: str
    new_password: str


class PlanCreate(BaseModel):
    name: str
    plan_type: str
    target_amount: Decimal = Decimal("0")
    monthly_amount: Decimal = Decimal("0")
    total_installments: int = 0
    paid_installments: int = 0
    payment_day: int = 1
    start_date: date
    notes: str = ""


class PlanEntryCreate(BaseModel):
    title: str
    amount: Decimal
    date: date
    notes: str = ""


class UserAuthOut(BaseModel):
    id: int
    name: str
    email: str
    role: str
    subscription_type: str
    subscription_expires_at: datetime | None = None

    model_config = ConfigDict(from_attributes=True)


class AuthResponse(BaseModel):
    access_token: str
    token_type: str
    user: UserAuthOut


class PdfUploadItemOut(BaseModel):
    id: int
    date: date
    title: str
    description: str = ""
    amount: Decimal
    category: str
    source_type: str
    transaction_type: str
    status: str

    model_config = ConfigDict(from_attributes=True)


class PdfUploadSummary(BaseModel):
    id: int
    filename: str
    uploaded_at: datetime
    total_count: int
    added_count: int
    skipped_count: int
    pending_count: int
    institution_name: str


class PdfUploadDetail(BaseModel):
    id: int
    filename: str
    uploaded_at: datetime
    items: List[PdfUploadItemOut]
    institution_name: str


class PdfUploadItemDecision(BaseModel):
    status: str
    title: str | None = None
    description: str | None = None
    category: str | None = None
    source_type: str | None = None


VALID_TRANSACTION_TYPES = {
    "income",
    "expense",
    "transfer",
    "credit_card_payment",
    "refund",
}


def _normalize_transaction_type(value: str | None, title: str, amount: float) -> str:
    normalized = (value or "").strip().lower()
    if normalized in VALID_TRANSACTION_TYPES:
        return normalized
    label = (title or "").lower()
    if any(keyword in label for keyword in ("kredi kartı ödemesi", "kredi karti odemesi", "kredi kartı ödeme", "kredi karti odeme")):
        return "credit_card_payment"
    if any(keyword in label for keyword in ("virman", "hesaplar arası transfer", "hesaplar arasi transfer")):
        return "transfer"
    if amount > 0:
        return "income"
    return "expense"


def _detect_institution_name(text: str, fallback: str | None = None) -> str:
    known_institutions = (
        "Garanti BBVA",
        "İş Bankası",
        "Yapı Kredi",
        "Akbank",
        "Ziraat Bankası",
        "Halkbank",
        "VakıfBank",
        "QNB Finansbank",
        "DenizBank",
        "TEB",
        "ING",
        "Enpara",
    )
    haystack = (text or "").lower()
    for institution in known_institutions:
        if institution.lower() in haystack:
            return institution
    normalized_fallback = (fallback or "").strip()
    return normalized_fallback or "Bilinmiyor"


MONTH_NAMES_TR = {
    1: "Oca",
    2: "Sub",
    3: "Mar",
    4: "Nis",
    5: "May",
    6: "Haz",
    7: "Tem",
    8: "Agu",
    9: "Eyl",
    10: "Eki",
    11: "Kas",
    12: "Ara",
}


def format_month_label(month_key: str) -> str:
    year_str, month_str = month_key.split("-")
    month_num = int(month_str)
    return f"{MONTH_NAMES_TR.get(month_num, month_str)} {year_str}"


def extract_pdf_text(file_path: str) -> str:
    import pdfplumber

    text_chunks: List[str] = []

    with pdfplumber.open(file_path) as pdf:
        for page in pdf.pages:
            text_chunks.append(page.extract_text() or "")

    return "\n".join(text_chunks).strip()


def extract_pdf_text_with_ocr(file_path: str) -> str:
    import fitz  # PyMuPDF
    from PIL import Image
    import pytesseract

    tesseract_cmd = os.getenv("TESSERACT_CMD", r"C:\Program Files\Tesseract-OCR\tesseract.exe")
    if os.path.exists(tesseract_cmd):
        pytesseract.pytesseract.tesseract_cmd = tesseract_cmd

    ocr_chunks: List[str] = []

    with fitz.open(file_path) as doc:
        for page in doc:
            pix = page.get_pixmap(matrix=fitz.Matrix(2, 2))
            mode = "RGBA" if pix.alpha else "RGB"
            img = Image.frombytes(mode, [pix.width, pix.height], pix.samples)

            try:
                page_text = pytesseract.image_to_string(img, lang="tur+eng")
            except Exception:
                page_text = pytesseract.image_to_string(img, lang="eng")

            ocr_chunks.append(page_text or "")

    return "\n".join(ocr_chunks).strip()


def _parse_statement_date(date_raw: str) -> date | None:
    cleaned = (date_raw or "").strip()
    if not cleaned:
        return None

    parts = cleaned.replace("-", "/").replace(".", "/").split("/")
    if len(parts) != 3:
        return None

    try:
        day = int(parts[0])
        month = int(parts[1])
        year = int(parts[2])
    except ValueError:
        return None

    if year < 100:
        year += 2000

    try:
        return date(year, month, day)
    except ValueError:
        return None


def _parse_statement_amount(amount_raw: str) -> float | None:
    cleaned = (amount_raw or "").strip().upper()
    if not cleaned:
        return None

    cleaned = cleaned.replace("−", "-")
    cleaned = cleaned.replace("TL", "").replace("TRY", "")
    cleaned = cleaned.replace("USD", "").replace("EUR", "").replace("GBP", "")
    cleaned = cleaned.replace("₺", "").replace(" ", "")

    if "," in cleaned and "." in cleaned:
        if cleaned.rfind(",") > cleaned.rfind("."):
            cleaned = cleaned.replace(".", "").replace(",", ".")
        else:
            cleaned = cleaned.replace(",", "")
    elif "," in cleaned:
        cleaned = cleaned.replace(".", "").replace(",", ".")
    else:
        cleaned = cleaned.replace(",", "")

    try:
        return float(cleaned)
    except ValueError:
        return None


def _guess_category(title: str) -> str:
    lower = (title or "").lower()

    if any(k in lower for k in ["market", "migros", "carrefour", "a101", "bim", "şok", "sok", "shop", "trendyol", "hepsiburada", "amazon", "akpos"]):
        return "Alışveriş"
    if any(k in lower for k in ["okul", "üniversite", "universite", "egitim", "eğitim", "kurs", "udemy", "kitap", "yks"]):
        return "Eğitim"
    if any(k in lower for k in ["sinema", "netflix", "spotify", "oyun", "eglence", "eğlence", "tiyatro", "steam"]):
        return "Eğlence"
    if any(k in lower for k in ["rest", "kafe", "cafe", "yemek", "yeme", "starbucks", "burger", "kahve"]):
        return "Yeme İçme"
    if any(k in lower for k in ["uber", "taksi", "metro", "otobüs", "otobus", "yakıt", "yakit", "shell", "opet"]):
        return "Ulaşım"
    if any(k in lower for k in ["kira", "elektrik", "su", "doğalgaz", "dogalgaz", "aidat", "internet"]):
        return "Faturalar"
    if any(k in lower for k in ["eczane", "hastane", "doktor", "sağlık", "saglik"]):
        return "Sağlık"

    return "Diğer"


def _is_summary_like_transaction(title: str, amount: float | None = None) -> bool:
    cleaned = " ".join((title or "").split()).strip().lower()
    if not cleaned:
        return False

    summary_keywords = (
        "kullanılabilir kart limiti",
        "kullanabilir kart limiti",
        "kart limiti",
        "ekstre borcu",
        "önceki ekstre",
        "onceki ekstre",
        "bakiye",
        "toplam",
        "kullanılabilir limit",
        "kullanabilir limit",
        "son durum",
        "güncel bakiye",
        "guncel bakiye",
    )
    if any(keyword in cleaned for keyword in summary_keywords):
        return True

    if amount is not None and amount > 0 and ("limit" in cleaned or "bakiye" in cleaned):
        return True

    return False


def _is_statement_notice(title: str) -> bool:
    """Ekstre altındaki ücret ve bilgilendirme metinlerini işlemden ayırır."""
    cleaned = " ".join((title or "").split()).strip().lower()
    notice_keywords = (
        "şans oyunu",
        "sans oyunu",
        "işlem başına",
        "islem basina",
        "ücretsiz olarak",
        "ucretsiz olarak",
        "bsmv dahil",
        "tarihinden itibaren",
    )
    return any(keyword in cleaned for keyword in notice_keywords)


def _build_transaction(tx_date: date, title: str, amount: float) -> dict[str, Any]:
    normalized_title = " ".join((title or "").split()).strip()
    if not normalized_title:
        normalized_title = "Ekstre İşlemi"
    elif len(normalized_title.replace(" ", "")) < 2 and not any(ch.isalpha() for ch in normalized_title):
        normalized_title = "Ekstre İşlemi"
    return {
        "date": tx_date.isoformat(),
        "title": normalized_title,
        "amount": round(amount, 2),
        "category": _guess_category(normalized_title),
    }


def parse_transactions_from_text(text: str) -> List[dict[str, Any]]:
    results: List[dict[str, Any]] = []
    seen: set[tuple[str, str, float]] = set()

    for raw_line in (text or "").splitlines():
        line = " ".join(raw_line.split()).strip()
        if not line:
            continue

        tokens = _merge_signed_amount_tokens(line.split())
        if len(tokens) < 3:
            continue

        tx_date = _parse_statement_date(tokens[0])
        if tx_date is None:
            continue

        amount_idx = -1
        amount_value = None
        for idx in range(1, len(tokens)):
            candidate = tokens[idx].strip("()[]{}<>:,;")
            parsed = _parse_statement_amount(candidate)
            if parsed is not None:
                amount_idx = idx
                amount_value = parsed
                break

        if amount_idx == -1 or amount_value is None:
            continue

        title_tokens = tokens[1:amount_idx]
        if not title_tokens:
            title_tokens = tokens[amount_idx + 1:]
        title = " ".join(title_tokens).strip()
        if not title:
            title = "Ekstre İşlemi"
        else:
            title = " ".join(part.strip("(),;:[]{}<>.") for part in title.split() if part.strip("(),;:[]{}<>.") and part.strip("(),;:[]{}<>.").lower() not in {"tl", "try", "usd", "eur", "gbp"})
        if not title:
            title = "Ekstre İşlemi"

        item = _build_transaction(tx_date, title, amount_value)
        if _is_summary_like_transaction(item["title"], item["amount"]) or _is_statement_notice(item["title"]):
            continue

        key = (item["date"], item["title"], item["amount"])
        if key in seen:
            continue
        seen.add(key)
        results.append(item)

    return results


_AMOUNT_RE = re.compile(r'^[\-+]?\d+(?:[.,]\d{3})*(?:[.,]\d{2})$')
_DATE_RE = re.compile(r'^\d{1,2}[./\-]\d{1,2}[./\-]\d{2,4}$')
_PURE_DIGITS_RE = re.compile(r'^\d+$')
_CURRENCY_CODE_RE = re.compile(r'^(TL|TRY|USD|EUR|GBP)$', re.IGNORECASE)

# Açıklama sütunu tutara en yakın olan sütun olduğu için, tarihten sonraki
# tüm kelimeleri değil, tutara en yakın son birkaç kelimeyi başlık olarak alıyoruz.
# Bu, banka/şube adı gibi tutardan uzak sütunların başlığa karışmasını önler.
_TITLE_TOKEN_LIMIT = 6


def _merge_signed_amount_tokens(tokens: list[str]) -> list[str]:
    merged: list[str] = []
    index = 0
    while index < len(tokens):
        token = tokens[index].replace("−", "-")
        if (
            token in {"-", "+"}
            and index + 1 < len(tokens)
            and _AMOUNT_RE.match(tokens[index + 1])
        ):
            merged.append(f"{token}{tokens[index + 1]}")
            index += 2
            continue
        merged.append(token)
        index += 1
    return merged


def _extract_transactions_from_words(words: list, row_bucket: float) -> List[dict[str, Any]]:
    """Bir sayfadaki kelimeleri (text, top, x0) satırlara grupla ve her satırdan
    tarih + tutar + başlık çıkar. Hem pdfplumber hem OCR (image_to_data) çıktısı
    aynı formatta olduğu için bu fonksiyon her iki kaynak için de ortak kullanılır."""
    rows: dict[float, list] = {}
    for word in words:
        row_key = round(word["top"] / row_bucket) * row_bucket
        rows.setdefault(row_key, []).append(word)

    results: List[dict[str, Any]] = []

    for row_key in sorted(rows.keys()):
        row_words = sorted(rows[row_key], key=lambda w: w["x0"])
        texts = _merge_signed_amount_tokens([w["text"] for w in row_words])

        if not texts:
            continue

        date_idx = -1
        tx_date = None
        for idx, t in enumerate(texts):
            if _DATE_RE.match(t):
                maybe = _parse_statement_date(t)
                if maybe is not None:
                    tx_date = maybe
                    date_idx = idx
                    break

        if tx_date is None:
            continue

        amount_indices = [
            i for i, t in enumerate(texts)
            if i > date_idx and _parse_statement_amount(t) is not None
        ]

        if not amount_indices:
            continue

        chosen_idx = amount_indices[-2] if len(amount_indices) >= 2 else amount_indices[-1]
        amount = _parse_statement_amount(texts[chosen_idx])
        if amount is None:
            continue

        title_parts = [
            t for i, t in enumerate(texts)
            if date_idx < i < chosen_idx
            and not _PURE_DIGITS_RE.match(t)
            and not _CURRENCY_CODE_RE.match(t)
            and _parse_statement_amount(t) is None
        ]
        if not title_parts:
            title_parts = [
                t for i, t in enumerate(texts)
                if i > date_idx
                and not _DATE_RE.match(t)
                and not _PURE_DIGITS_RE.match(t)
                and not _CURRENCY_CODE_RE.match(t)
                and _parse_statement_amount(t) is None
            ]
        if not title_parts and chosen_idx + 1 < len(texts):
            title_parts = [
                t for i, t in enumerate(texts)
                if chosen_idx < i <= min(len(texts) - 1, chosen_idx + 4)
                and not _DATE_RE.match(t)
                and not _PURE_DIGITS_RE.match(t)
                and not _CURRENCY_CODE_RE.match(t)
                and _parse_statement_amount(t) is None
            ]
        if len(title_parts) > _TITLE_TOKEN_LIMIT:
            title_parts = title_parts[-_TITLE_TOKEN_LIMIT:]

        cleaned_title_parts = []
        for token in title_parts:
            cleaned = token.strip("();:[]{}<>.")
            if cleaned and cleaned.lower() not in {"tl", "try", "usd", "eur", "gbp"}:
                cleaned_title_parts.append(cleaned)

        title = " ".join(cleaned_title_parts).strip()
        if not title:
            title = "Ekstre İşlemi"

        item = _build_transaction(tx_date, title, amount)
        if _is_summary_like_transaction(item["title"], item["amount"]) or _is_statement_notice(item["title"]):
            continue
        results.append(item)

    return results


def _canonicalize_transaction_key(
    date_value: str,
    title: str | None,
    amount: float | int | Decimal | str | None,
) -> tuple[str, str, str]:
    normalized_date = str(date_value or "").strip()
    normalized_title = " ".join((title or "").split())
    normalized_title = unicodedata.normalize("NFKD", normalized_title.casefold())
    normalized_title = "".join(ch for ch in normalized_title if not unicodedata.combining(ch))
    normalized_title = normalized_title.translate(
        {ord(ch): None for ch in "()[]{}<>:;,.!?/\\\"'`"}
    )
    normalized_title = (
        normalized_title.replace("ı", "i")
        .replace("i", "i")
        .replace("ğ", "g")
        .replace("ü", "u")
        .replace("ş", "s")
        .replace("ö", "o")
        .replace("ç", "c")
    )
    normalized_amount = str(float(amount) if amount is not None else 0.0)
    return normalized_date, normalized_title.strip(), normalized_amount


def _dedupe_transactions(items: List[dict[str, Any]]) -> List[dict[str, Any]]:
    seen: set[tuple[str, str, str]] = set()
    deduped: List[dict[str, Any]] = []
    for item in items:
        key = _canonicalize_transaction_key(item.get("date"), item.get("title"), item.get("amount"))
        if key in seen:
            continue
        seen.add(key)
        deduped.append(item)
    return deduped


def _infer_bank_transaction_sign(title: str, amount: float) -> float:
    label = (title or "").lower()
    negative_keywords = [
        "gider",
        "ödeme",
        "odeme",
        "harcama",
        "taksit",
        "kredi karti",
        "kredi kartı",
        "fatura",
        "aidat",
        "kira",
        "döviz",
        "doviz",
        "alışveriş",
        "alisveris",
        "market",
        "telefon",
        "internet",
        "elektrik",
        "su",
        "yakıt",
        "yakit",
        "taksi",
        "restaurant",
        "kafe",
        "cafe",
        "yemek",
        "burger",
        "sinema",
        "netflix",
        "spotify",
        "kebap",
        "coffee",
        "cadd",
        "cadde",
        "sarayi",
        "restaurant",
        "gida",
        "petrol",
        "oteller",
        "otel",
        "magaza",
        "shop",
        "store",
    ]
    positive_keywords = [
        "gelir",
        "gelen transfer",
        "maaş",
        "maas",
        "maaş ödemesi",
        "maas odemesi",
        "ücret ödemesi",
        "ucret odemesi",
        "ücret",
        "ucret",
        "deposit",
        "iade",
        "refund",
        "credit",
        "gelir transfer",
        "maas transfer",
        "gelen para",
    ]

    has_negative = any(keyword in label for keyword in negative_keywords)
    has_positive = any(keyword in label for keyword in positive_keywords)

    # Ekstreler bazen gelen maaşı eksi sütunda gösterebilir. Açıklama açıkça
    # gelir belirtiyorsa, bu sinyal işaretten daha güvenilirdir.
    if has_positive and not any(
        keyword in label
        for keyword in ("gider", "harcama", "kredi kartı", "kredi karti")
    ):
        return round(abs(amount), 2)

    if amount < 0:
        return amount

    if has_negative and not has_positive:
        return round(-abs(amount), 2)
    if has_positive and not has_negative:
        return round(abs(amount), 2)

    # Açık gelir işareti yoksa, banka/market/restaurant gibi işleme ait pozitif tutar
    # harcama olarak işlenmelidir. Böylece "müşteri transferi" veya detaylı metinlerde
    # tek başına pozitif değerler yanlışlıkla gelir olarak görünmez.
    merchant_like = any(
        marker in label
        for marker in (
            "market",
            "restaurant",
            "kebap",
            "cafe",
            "coffee",
            "cadde",
            "sarayi",
            "gida",
            "shop",
            "store",
            "istanbul",
            "tr",
            "ltd",
            "a.ş",
            "as",
        )
    )
    if merchant_like or not has_positive and not has_negative:
        return round(-abs(amount), 2)

    return round(amount, 2)


def _normalize_statement_signs(items: List[dict[str, Any]], statement_type: str) -> List[dict[str, Any]]:
    normalized_type = (statement_type or "bank").strip().lower()
    if normalized_type not in {"bank", "credit_card"}:
        normalized_type = "bank"

    for item in items:
        amount = float(item.get("amount", 0) or 0)
        if normalized_type == "credit_card":
            item["amount"] = round(-abs(amount), 2)
        else:
            item["amount"] = _infer_bank_transaction_sign(str(item.get("title", "")), amount)
    return items


def _detect_statement_type(text: str) -> str | None:
    normalized = " ".join((text or "").lower().split())
    credit_card_markers = (
        "kredi kartı", "kredi karti", "credit card", "ekstre borcu",
        "dönem borcu", "donem borcu", "asgari ödeme", "asgari odeme",
        "kart limiti", "kullanılabilir kart limiti", "kullanabilir kart limiti",
    )
    bank_markers = (
        "hesap hareketleri", "hesap ekstresi", "hesap özeti", "hesap ozeti",
        "iban", "gelen havale", "giden havale", "eft", "havale",
    )

    credit_score = sum(marker in normalized for marker in credit_card_markers)
    bank_score = sum(marker in normalized for marker in bank_markers)
    if credit_score == 0 and bank_score == 0:
        return None
    return "credit_card" if credit_score > bank_score else "bank"


def _validate_statement_type(selected_type: str, detected_type: str | None) -> None:
    if detected_type is None or selected_type == detected_type:
        return

    labels = {"bank": "banka ekstresi", "credit_card": "kredi kartı ekstresi"}
    raise HTTPException(
        status_code=400,
        detail=(
            f"Yüklediğin dosya {labels[detected_type]} olarak algılandı. "
            f"Lütfen yükleme ekranında {labels[detected_type]} seçeneğini seçip tekrar dene."
        ),
    )


def parse_transactions_by_words(file_path: str) -> List[dict[str, Any]]:
    """Koordinat tabanlı: gerçek metin katmanı olan çok sütunlu PDF'ler için."""
    import pdfplumber

    all_results: List[dict[str, Any]] = []

    with pdfplumber.open(file_path) as pdf:
        for page in pdf.pages:
            words = page.extract_words(x_tolerance=3, y_tolerance=3)
            if not words:
                continue
            all_results.extend(_extract_transactions_from_words(words, row_bucket=5))

    return _dedupe_transactions(all_results)


def parse_transactions_by_ocr_words(file_path: str) -> List[dict[str, Any]]:
    """Koordinat tabanlı: metin katmanı olmayan (taranmış/ekran görüntüsü) PDF'ler için.
    pytesseract.image_to_string tabloları sütun sütun okuyup satır yapısını bozduğundan,
    burada image_to_data ile her kelimenin konumu alınıp pdfplumber ile aynı satır
    gruplama mantığı uygulanır."""
    import fitz  # PyMuPDF
    from PIL import Image
    import pytesseract

    tesseract_cmd = os.getenv("TESSERACT_CMD", r"C:\Program Files\Tesseract-OCR\tesseract.exe")
    if os.path.exists(tesseract_cmd):
        pytesseract.pytesseract.tesseract_cmd = tesseract_cmd

    all_results: List[dict[str, Any]] = []

    with fitz.open(file_path) as doc:
        for page in doc:
            pix = page.get_pixmap(matrix=fitz.Matrix(2, 2))
            mode = "RGBA" if pix.alpha else "RGB"
            img = Image.frombytes(mode, [pix.width, pix.height], pix.samples)

            try:
                data = pytesseract.image_to_data(img, lang="tur+eng", output_type=pytesseract.Output.DICT)
            except Exception:
                data = pytesseract.image_to_data(img, lang="eng", output_type=pytesseract.Output.DICT)

            words: list = []
            heights: List[float] = []
            for i, raw_text in enumerate(data.get("text", [])):
                text = (raw_text or "").strip()
                if not text:
                    continue
                words.append({
                    "text": text,
                    "top": float(data["top"][i]),
                    "x0": float(data["left"][i]),
                })
                heights.append(float(data["height"][i]))

            if not words:
                continue

            row_bucket = (sum(heights) / len(heights)) * 0.6 if heights else 10
            all_results.extend(_extract_transactions_from_words(words, row_bucket=row_bucket))

    return _dedupe_transactions(all_results)

@app.get("/")
def home():
    return {"message": "AI Finance Coach API"}


@app.post("/auth/register", response_model=AuthResponse, status_code=201)
def register(payload: RegisterRequest, db: Session = Depends(get_db)):
    name = payload.name.strip()
    email = payload.email.strip().lower()
    password = payload.password.strip()

    if not name:
        raise HTTPException(status_code=400, detail="Ad alanı zorunludur")

    if len(password) < 8:
        raise HTTPException(status_code=400, detail="Şifre en az 8 karakter olmalıdır")

    user = User(
        name=name,
        email=email,
        password_hash=hash_password(password),
    )

    db.add(user)
    try:
        db.commit()
        db.refresh(user)
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=409, detail="Bu e-posta zaten kayıtlı")

    token = create_access_token(user.id)
    return {
        "access_token": token,
        "token_type": "bearer",
        "user": {
            "id": user.id,
            "name": user.name,
            "email": user.email,
            "role": user.role,
            "subscription_type": user.subscription_type,
            "subscription_expires_at": user.subscription_expires_at,
        },
    }


LOGIN_MAX_ATTEMPTS = 5
LOGIN_LOCKOUT_MINUTES = 15


@app.post("/auth/login", response_model=AuthResponse)
def login(payload: LoginRequest, db: Session = Depends(get_db)):
    email = payload.email.strip().lower()
    now = datetime.now(timezone.utc).replace(tzinfo=None)

    user = db.query(User).filter(User.email == email).first()

    if user is not None and user.locked_until is not None and user.locked_until > now:
        remaining_minutes = max(1, int((user.locked_until - now).total_seconds() // 60) + 1)
        raise HTTPException(
            status_code=429,
            detail=f"Çok fazla başarısız deneme. {remaining_minutes} dakika sonra tekrar dene.",
        )

    if not user or not verify_password(payload.password, user.password_hash):
        if user is not None:
            user.failed_login_attempts = (user.failed_login_attempts or 0) + 1
            if user.failed_login_attempts >= LOGIN_MAX_ATTEMPTS:
                user.locked_until = now + timedelta(minutes=LOGIN_LOCKOUT_MINUTES)
                user.failed_login_attempts = 0
            db.commit()
        raise HTTPException(status_code=401, detail="E-posta veya şifre hatalı")

    user.failed_login_attempts = 0
    user.locked_until = None
    db.commit()

    token = create_access_token(user.id)
    return {
        "access_token": token,
        "token_type": "bearer",
        "user": {
            "id": user.id,
            "name": user.name,
            "email": user.email,
            "role": user.role,
            "subscription_type": user.subscription_type,
            "subscription_expires_at": user.subscription_expires_at,
        },
    }


@app.get("/auth/me", response_model=UserAuthOut)
def me(current_user: User = Depends(get_current_user)):
    return current_user


@app.put("/auth/me", response_model=UserAuthOut)
def update_me(
    payload: UpdateProfileRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    name = payload.name.strip()
    email = payload.email.strip().lower()

    if not name:
        raise HTTPException(status_code=400, detail="Ad soyad alanı zorunludur")

    existing_user = (
        db.query(User)
        .filter(User.email == email, User.id != current_user.id)
        .first()
    )
    if existing_user is not None:
        raise HTTPException(status_code=409, detail="Bu e-posta başka bir kullanıcıya ait")

    current_user.name = name
    current_user.email = email
    db.commit()
    db.refresh(current_user)
    return current_user


@app.post("/auth/change-password")
def change_password(
    payload: ChangePasswordRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if len(payload.new_password.strip()) < 8:
        raise HTTPException(status_code=400, detail="Yeni şifre en az 8 karakter olmalıdır")

    if not verify_password(payload.current_password, current_user.password_hash):
        raise HTTPException(status_code=401, detail="Mevcut şifre yanlış")

    current_user.password_hash = hash_password(payload.new_password.strip())
    db.commit()
    return {"message": "Şifre başarıyla değiştirildi"}


def get_admin_user(current_user: User = Depends(get_current_user)) -> User:
    if current_user.role != "admin":
        raise HTTPException(status_code=403, detail="Bu alan yalnızca yöneticilere açıktır")
    return current_user


@app.get("/admin/overview")
def admin_overview(
    db: Session = Depends(get_db),
    _: User = Depends(get_admin_user),
):
    user_count = db.query(func.count(User.id)).scalar() or 0
    premium_count = (
        db.query(func.count(User.id))
        .filter(User.subscription_type == "premium")
        .scalar()
        or 0
    )
    upload_count = db.query(func.count(PdfUpload.id)).scalar() or 0
    transaction_count = db.query(func.count(Transaction.id)).scalar() or 0
    plan_count = db.query(func.count(Plan.id)).scalar() or 0
    pending_pdf_items = (
        db.query(func.count(PdfUploadItem.id))
        .filter(PdfUploadItem.status == "pending")
        .scalar()
        or 0
    )
    return {
        "users": user_count,
        "premium_users": premium_count,
        "free_users": max(user_count - premium_count, 0),
        "pdf_uploads": upload_count,
        "transactions": transaction_count,
        "plans": plan_count,
        "pending_pdf_items": pending_pdf_items,
    }


@app.get("/dashboard")
def dashboard(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    items = (
        db.query(Transaction)
        .filter(Transaction.user_id == current_user.id)
        .order_by(Transaction.date.desc(), Transaction.id.desc())
        .all()
    )

    income = 0.0
    expense = 0.0
    recent_transactions = []

    for item in items:
        amount_value = float(item.amount or 0)

        if item.transaction_type == "credit_card_payment":
            continue
        if amount_value > 0:
            income += amount_value
        elif amount_value < 0:
            expense += abs(amount_value)

        recent_transactions.append(
            {
                "id": item.id,
                "title": item.title,
                "amount": amount_value,
                "category": item.category,
                "date": item.date.isoformat() if item.date else None,
                "source_type": item.source_type,
                "transaction_type": item.transaction_type,
                "institution_name": item.institution_name,
            }
        )

    saving = income - expense

    if income <= 0:
        risk = "High"
    else:
        expense_ratio = expense / income
        if expense_ratio < 0.5:
            risk = "Low"
        elif expense_ratio < 0.8:
            risk = "Medium"
        else:
            risk = "High"

    return {
        "income": round(income, 2),
        "expense": round(expense, 2),
        "saving": round(saving, 2),
        "risk": risk,
        "recent_transactions": recent_transactions[:3],
    }


MAX_UPLOAD_BYTES = 10 * 1024 * 1024  # 10 MB
PDF_MAGIC = b"%PDF-"


def _current_analysis_period() -> tuple[date, date]:
    """İçinde bulunulan ay ve önceki iki ayı kapsayan analiz penceresini döndürür."""
    today = date.today()
    start_month = today.month - 2
    start_year = today.year
    if start_month <= 0:
        start_month += 12
        start_year -= 1
    return date(start_year, start_month, 1), today


def _validate_transaction_dates(transactions: List[dict[str, Any]]) -> None:
    start_date, end_date = _current_analysis_period()
    transaction_dates = [
        date.fromisoformat(item["date"])
        for item in transactions
        if item.get("date")
    ]
    if not transaction_dates:
        return

    oldest_date = min(transaction_dates)
    newest_date = max(transaction_dates)
    if oldest_date < start_date or newest_date > end_date:
        raise HTTPException(
            status_code=400,
            detail=(
                f"Analiz için yalnızca {start_date.strftime('%d.%m.%Y')} - "
                f"{end_date.strftime('%d.%m.%Y')} tarihleri arasındaki ekstreler yüklenebilir. "
                "Daha eski veya ileri tarihli işlemler içeren PDF'yi yükleyemezsin."
            ),
        )


def _serialize_pdf_item(item: PdfUploadItem) -> dict[str, Any]:
    return {
        "id": item.id,
        "date": item.date.isoformat(),
        "title": item.title,
        "description": item.description or "",
        "amount": float(item.amount),
        "category": item.category,
        "source_type": item.source_type or "bank",
        "transaction_type": item.transaction_type or "expense",
        "status": item.status,
    }


@app.post("/upload-pdf")
async def upload_pdf(
    file: UploadFile = File(...),
    statement_type: str = Form("bank"),
    institution_name: str = Form(""),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    statement_type = (statement_type or "bank").strip().lower()
    if statement_type not in {"bank", "credit_card"}:
        raise HTTPException(status_code=400, detail="Geçersiz ekstre tipi")

    original_name = os.path.basename(file.filename or "")
    if not original_name.lower().endswith(".pdf"):
        raise HTTPException(status_code=400, detail="Sadece PDF dosyaları kabul edilir")

    os.makedirs("uploads", exist_ok=True)
    # Kullanıcının gönderdiği dosya adı hiçbir zaman path olarak kullanılmıyor
    # (path traversal riski); disk üzerinde her zaman rastgele bir isimle saklanır.
    stored_name = f"{uuid4().hex}.pdf"
    file_path = os.path.join("uploads", stored_name)

    try:
        size = 0
        file_hash = hashlib.sha256()
        with open(file_path, "wb") as buffer:
            while True:
                chunk = await file.read(1024 * 1024)
                if not chunk:
                    break
                size += len(chunk)
                if size > MAX_UPLOAD_BYTES:
                    raise HTTPException(status_code=413, detail="Dosya boyutu 10MB sınırını aşamaz")
                file_hash.update(chunk)
                buffer.write(chunk)

        with open(file_path, "rb") as check_file:
            header = check_file.read(len(PDF_MAGIC))
        if header != PDF_MAGIC:
            raise HTTPException(status_code=400, detail="Geçerli bir PDF dosyası değil")

        content_hash = file_hash.hexdigest()

        existing_upload = (
            db.query(PdfUpload)
            .filter(PdfUpload.user_id == current_user.id, PdfUpload.file_hash == content_hash)
            .first()
        )

        if existing_upload is not None:
            # Aynı içerik daha önce yüklenmiş olabilir. Eski sürümde yanlış türle
            # kaydedilmiş kayıtları düzeltmek için PDF içeriğini yeniden doğrula.
            existing_text = ""
            refreshed_transactions: List[dict[str, Any]] = []
            try:
                existing_text = extract_pdf_text(file_path)
                if not existing_text.strip():
                    existing_text = extract_pdf_text_with_ocr(file_path)

                if existing_text.strip():
                    refreshed_transactions = parse_transactions_by_words(file_path)
                else:
                    refreshed_transactions = parse_transactions_by_ocr_words(file_path)
                if not refreshed_transactions:
                    refreshed_transactions = parse_transactions_from_text(existing_text)
                refreshed_transactions = _dedupe_transactions(refreshed_transactions)
                refreshed_transactions = _normalize_statement_signs(
                    refreshed_transactions,
                    statement_type,
                )
                _validate_transaction_dates(refreshed_transactions)
            except HTTPException:
                raise
            except Exception:
                refreshed_transactions = []
            finally:
                if os.path.exists(file_path):
                    os.remove(file_path)

            detected_existing_type = _detect_statement_type(existing_text)
            if detected_existing_type is not None:
                _validate_statement_type(statement_type, detected_existing_type)
            else:
                _validate_statement_type(
                    statement_type,
                    existing_upload.statement_type or "bank",
                )

            if existing_upload.statement_type != statement_type:
                existing_upload.statement_type = statement_type
                for item in existing_upload.items:
                    item.source_type = statement_type
                    if item.transaction_id is not None:
                        linked_transaction = db.get(Transaction, item.transaction_id)
                        if linked_transaction is not None:
                            linked_transaction.source_type = statement_type
                db.commit()

            _validate_statement_type(
                statement_type,
                detected_existing_type or existing_upload.statement_type or "bank",
            )
            stale_notice_items = [
                item
                for item in existing_upload.items
                if item.status == "pending" and _is_statement_notice(item.title)
            ]
            for item in stale_notice_items:
                existing_upload.items.remove(item)

            pending_items = [
                item for item in existing_upload.items if item.status == "pending"
            ]
            for item, refreshed in zip(pending_items, refreshed_transactions):
                if refreshed.get("title"):
                    item.title = refreshed["title"]
                item.amount = refreshed["amount"]
                item.date = date.fromisoformat(refreshed["date"])
                item.category = refreshed["category"]
                item.transaction_type = _normalize_transaction_type(
                    None,
                    item.title,
                    float(item.amount),
                )
            if stale_notice_items or (pending_items and refreshed_transactions):
                db.commit()
            items = [_serialize_pdf_item(item) for item in existing_upload.items]
            return {
                "success": True,
                "duplicate": True,
                "upload_id": existing_upload.id,
                "filename": existing_upload.filename,
                "uploaded_at": existing_upload.uploaded_at.isoformat(),
                "warnings": [],
                "parsed_transactions": items,
                "parsed_count": len(items),
                "institution_name": existing_upload.institution_name or "Bilinmiyor",
            }

        warnings: List[str] = []
        text = ""

        try:
            text = extract_pdf_text(file_path)
        except Exception as exc:
            warnings.append(f"Metin çıkarma başarısız (pdfplumber): {exc}")

        # Gerçek metin katmanı yoksa (taranmış/ekran görüntüsü PDF), önizleme metni
        # için OCR gerekir. Bu durumda tablo yapısını da OCR'ın kelime konumlarından
        # (image_to_data) çıkarırız; image_to_string satır/sütun sırasını bozar.
        is_scanned = not text.strip()

        if is_scanned:
            try:
                text = extract_pdf_text_with_ocr(file_path)
            except Exception as exc:
                warnings.append(f"OCR kullanılamadı: {exc}")

        parsed_transactions: List[dict[str, Any]] = []

        if not is_scanned:
            try:
                parsed_transactions = parse_transactions_by_words(file_path)
            except Exception as exc:
                warnings.append(f"Kelime tabanlı ayrıştırma kullanılamadı: {exc}")
        else:
            try:
                parsed_transactions = parse_transactions_by_ocr_words(file_path)
            except Exception as exc:
                warnings.append(f"OCR tabanlı tablo ayrıştırma kullanılamadı: {exc}")

        if not parsed_transactions:
            try:
                parsed_transactions = parse_transactions_from_text(text)
            except Exception as exc:
                warnings.append(f"Metin ayrıştırma kullanılamadı: {exc}")

        _validate_statement_type(statement_type, _detect_statement_type(text))
        parsed_transactions = _dedupe_transactions(parsed_transactions)
        parsed_transactions = _normalize_statement_signs(parsed_transactions, statement_type)
        _validate_transaction_dates(parsed_transactions)
        detected_institution = _detect_institution_name(text, institution_name)

        upload = PdfUpload(
            user_id=current_user.id,
            filename=original_name,
            file_hash=content_hash,
            statement_type=statement_type,
                    institution_name=detected_institution,
        )
        for candidate in parsed_transactions:
            upload.items.append(
                PdfUploadItem(
                    date=date.fromisoformat(candidate["date"]),
                    title=candidate["title"],
                    amount=candidate["amount"],
                    category=candidate["category"],
                    source_type=statement_type,
                    transaction_type=_normalize_transaction_type(
                        None,
                        candidate["title"],
                        float(candidate["amount"]),
                    ),
                    status="pending",
                )
            )

        db.add(upload)
        db.commit()
        db.refresh(upload)

        items = [_serialize_pdf_item(item) for item in upload.items]

        return {
            "success": True,
            "duplicate": False,
            "upload_id": upload.id,
            "filename": original_name,
            "extracted_text": text,
            "preview": text[:1000],
            "is_empty": not bool(text.strip()),
            "warnings": warnings,
            "parsed_transactions": items,
            "parsed_count": len(items),
            "institution_name": detected_institution,
        }

    except HTTPException:
        if os.path.exists(file_path):
            os.remove(file_path)
        raise
    except Exception as exc:
        if os.path.exists(file_path):
            os.remove(file_path)
        raise HTTPException(status_code=500, detail=f"PDF işleme hatası: {exc}") from exc


def _get_owned_upload(db: Session, current_user: User, upload_id: int) -> PdfUpload:
    upload = (
        db.query(PdfUpload)
        .filter(PdfUpload.id == upload_id, PdfUpload.user_id == current_user.id)
        .first()
    )
    if upload is None:
        raise HTTPException(status_code=404, detail="Yükleme bulunamadı")
    return upload


@app.get("/pdf-uploads", response_model=List[PdfUploadSummary])
def list_pdf_uploads(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    uploads = (
        db.query(PdfUpload)
        .filter(PdfUpload.user_id == current_user.id)
        .order_by(PdfUpload.uploaded_at.desc(), PdfUpload.id.desc())
        .all()
    )

    summaries = []
    for upload in uploads:
        statuses = [item.status for item in upload.items]
        summaries.append(
            PdfUploadSummary(
                id=upload.id,
                filename=upload.filename,
                uploaded_at=upload.uploaded_at,
                total_count=len(statuses),
                added_count=statuses.count("added"),
                skipped_count=statuses.count("skipped"),
                pending_count=statuses.count("pending"),
                institution_name=upload.institution_name or "Bilinmiyor",
            )
        )
    return summaries


@app.get("/pdf-uploads/{upload_id}", response_model=PdfUploadDetail)
def get_pdf_upload(
    upload_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    upload = _get_owned_upload(db, current_user, upload_id)
    return PdfUploadDetail(
        id=upload.id,
        filename=upload.filename,
        uploaded_at=upload.uploaded_at,
        institution_name=upload.institution_name or "Bilinmiyor",
        items=list(upload.items),
    )


@app.post("/pdf-uploads/{upload_id}/items/{item_id}/decide", response_model=PdfUploadItemOut)
def decide_pdf_upload_item(
    upload_id: int,
    item_id: int,
    payload: PdfUploadItemDecision,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if payload.status not in ("added", "skipped"):
        raise HTTPException(status_code=400, detail="Gecersiz durum degeri")

    normalized_source = (payload.source_type or "").strip().lower()
    if normalized_source and normalized_source not in {"bank", "credit_card"}:
        raise HTTPException(status_code=400, detail="Geçersiz kaynak tipi")

    upload = _get_owned_upload(db, current_user, upload_id)
    item = next((candidate for candidate in upload.items if candidate.id == item_id), None)
    if item is None:
        raise HTTPException(status_code=404, detail="İşlem bulunamadı")

    if payload.status == "added":
        if item.status == "added":
            linked_transaction = db.get(Transaction, item.transaction_id) if item.transaction_id else None
            if payload.title is not None and payload.title.strip():
                item.title = payload.title.strip()
                if linked_transaction is not None:
                    linked_transaction.title = item.title
            if payload.description is not None:
                item.description = payload.description.strip()
                if linked_transaction is not None:
                    linked_transaction.description = item.description
            if payload.category is not None and payload.category.strip():
                item.category = payload.category.strip()
                if linked_transaction is not None:
                    linked_transaction.category = item.category
            if normalized_source:
                item.source_type = normalized_source
                if linked_transaction is not None:
                    linked_transaction.source_type = normalized_source
            db.commit()
            db.refresh(item)
            return item

        if payload.title is not None:
            normalized_title = payload.title.strip()
            if normalized_title:
                item.title = normalized_title
        if payload.description is not None:
            item.description = payload.description.strip()
        if payload.category is not None:
            normalized_category = payload.category.strip()
            if normalized_category:
                item.category = normalized_category
        if normalized_source:
            item.source_type = normalized_source

        new_transaction = Transaction(
            user_id=current_user.id,
            title=item.title,
            description=item.description or "",
            amount=item.amount,
            category=item.category,
            date=item.date,
            source_type=item.source_type or "bank",
            transaction_type=item.transaction_type or "expense",
            institution_name=upload.institution_name or "Bilinmiyor",
        )
        db.add(new_transaction)
        db.flush()
        item.transaction_id = new_transaction.id
        item.status = "added"
    else:
        # Daha önce eklenmiş bir işlem geri çıkarılıyorsa, oluşturulan gerçek
        # işlem kaydı da silinir; aksi halde işlemler listesinde tutarsızlık olur.
        if item.status == "added" and item.transaction_id is not None:
            linked_transaction = db.get(Transaction, item.transaction_id)
            if linked_transaction is not None and linked_transaction.user_id == current_user.id:
                db.delete(linked_transaction)
            item.transaction_id = None
        item.status = "skipped"

    db.commit()
    db.refresh(item)
    return item


@app.get("/transactions", response_model=List[TransactionOut])
def transactions(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    items = (
        db.query(Transaction)
        .filter(Transaction.user_id == current_user.id)
        .order_by(Transaction.date.desc(), Transaction.id.desc())
        .all()
    )
    return items


def _get_owned_plan(db: Session, current_user: User, plan_id: int) -> Plan:
    plan = (
        db.query(Plan)
        .filter(Plan.id == plan_id, Plan.user_id == current_user.id)
        .first()
    )
    if plan is None:
        raise HTTPException(status_code=404, detail="Plan bulunamadı")
    return plan


def _serialize_plan(plan: Plan) -> dict[str, Any]:
    spent_amount = sum((float(entry.amount or 0) for entry in plan.entries), 0.0)
    target_amount = float(plan.target_amount or 0)
    total_installments = int(plan.total_installments or 0)
    paid_installments = int(plan.paid_installments or 0)
    return {
        "id": plan.id,
        "name": plan.name,
        "plan_type": plan.plan_type,
        "target_amount": target_amount,
        "monthly_amount": float(plan.monthly_amount or 0),
        "total_installments": total_installments,
        "paid_installments": paid_installments,
        "payment_day": int(plan.payment_day or 1),
        "remaining_installments": max(total_installments - paid_installments, 0),
        "spent_amount": spent_amount,
        "remaining_amount": max(target_amount - spent_amount, 0),
        "start_date": plan.start_date.isoformat(),
        "notes": plan.notes or "",
        "entries": [
            {
                "id": entry.id,
                "title": entry.title,
                "amount": float(entry.amount or 0),
                "date": entry.date.isoformat(),
                "notes": entry.notes or "",
            }
            for entry in plan.entries
        ],
    }


@app.get("/plans")
def list_plans(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    plans = (
        db.query(Plan)
        .filter(Plan.user_id == current_user.id)
        .order_by(Plan.id.desc())
        .all()
    )
    return [_serialize_plan(plan) for plan in plans]


@app.post("/plans", status_code=201)
def create_plan(
    payload: PlanCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if payload.plan_type not in {"budget", "installment"}:
        raise HTTPException(status_code=400, detail="Geçersiz plan türü")
    if not payload.name.strip():
        raise HTTPException(status_code=400, detail="Plan adı boş olamaz")
    if payload.target_amount < 0 or payload.monthly_amount < 0:
        raise HTTPException(status_code=400, detail="Tutarlar negatif olamaz")
    if payload.total_installments < 0 or payload.paid_installments < 0:
        raise HTTPException(status_code=400, detail="Taksit sayıları negatif olamaz")
    if payload.paid_installments > payload.total_installments:
        raise HTTPException(status_code=400, detail="Ödenen taksit toplam taksitten fazla olamaz")
    if payload.plan_type == "installment" and not 1 <= payload.payment_day <= 31:
        raise HTTPException(status_code=400, detail="Ödeme günü 1 ile 31 arasında olmalı")

    plan = Plan(
        user_id=current_user.id,
        name=payload.name.strip(),
        plan_type=payload.plan_type,
        target_amount=payload.target_amount,
        monthly_amount=payload.monthly_amount,
        total_installments=payload.total_installments,
        paid_installments=payload.paid_installments,
        payment_day=payload.payment_day,
        start_date=payload.start_date,
        notes=payload.notes.strip(),
    )
    db.add(plan)
    db.commit()
    db.refresh(plan)
    return _serialize_plan(plan)


@app.post("/plans/{plan_id}/entries", status_code=201)
def add_plan_entry(
    plan_id: int,
    payload: PlanEntryCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    plan = _get_owned_plan(db, current_user, plan_id)
    if not payload.title.strip():
        raise HTTPException(status_code=400, detail="Kayıt adı boş olamaz")
    if payload.amount <= 0:
        raise HTTPException(status_code=400, detail="Tutar sıfırdan büyük olmalı")
    if plan.plan_type == "installment" and plan.paid_installments >= plan.total_installments:
        raise HTTPException(status_code=400, detail="Bu planın tüm taksitleri tamamlandı")

    entry = PlanEntry(
        plan_id=plan.id,
        title=payload.title.strip(),
        amount=payload.amount,
        date=payload.date,
        notes=payload.notes.strip(),
    )
    db.add(entry)
    if plan.plan_type == "installment":
        plan.paid_installments += 1
    db.commit()
    db.refresh(plan)
    return _serialize_plan(plan)


@app.delete("/plans/{plan_id}", status_code=204)
def delete_plan(
    plan_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    plan = _get_owned_plan(db, current_user, plan_id)
    db.delete(plan)
    db.commit()


@app.post("/transactions", response_model=TransactionOut, status_code=201)
def create_transaction(
    payload: TransactionCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    normalized_source = (payload.source_type or "bank").strip().lower()
    if normalized_source not in {"bank", "credit_card"}:
        raise HTTPException(status_code=400, detail="Geçersiz kaynak tipi")

    new_item = Transaction(
        title=payload.title,
        amount=payload.amount,
        category=payload.category,
        date=payload.date,
        user_id=current_user.id,
        source_type=normalized_source,
            transaction_type=_normalize_transaction_type(
                payload.transaction_type,
                payload.title,
                float(payload.amount),
            ),
            institution_name=(payload.institution_name or "Bilinmiyor").strip() or "Bilinmiyor",
    )
    db.add(new_item)
    db.commit()
    db.refresh(new_item)
    return new_item


@app.put("/transactions/{transaction_id}", response_model=TransactionOut)
def update_transaction(
    transaction_id: int,
    payload: TransactionCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    item = (
        db.query(Transaction)
        .filter(Transaction.id == transaction_id, Transaction.user_id == current_user.id)
        .first()
    )
    if item is None:
        raise HTTPException(status_code=404, detail="İşlem bulunamadı")

    normalized_source = (payload.source_type or "bank").strip().lower()
    if normalized_source not in {"bank", "credit_card"}:
        raise HTTPException(status_code=400, detail="Geçersiz kaynak tipi")

    item.title = payload.title
    item.amount = payload.amount
    item.category = payload.category
    item.date = payload.date
    item.source_type = normalized_source
    item.transaction_type = _normalize_transaction_type(
        payload.transaction_type,
        payload.title,
        float(payload.amount),
    )
    item.institution_name = (payload.institution_name or "Bilinmiyor").strip() or "Bilinmiyor"

    db.commit()
    db.refresh(item)
    return item


@app.delete("/transactions/{transaction_id}", status_code=204)
def delete_transaction(
    transaction_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    item = (
        db.query(Transaction)
        .filter(Transaction.id == transaction_id, Transaction.user_id == current_user.id)
        .first()
    )
    if item is None:
        raise HTTPException(status_code=404, detail="İşlem bulunamadı")

    # Bu işlem bir PDF içe aktarmasından geldiyse, o kaydın durumunu da senkronize et
    # (aksi halde PDF geçmişinde artık var olmayan bir işleme işaret eden "eklendi" durumu kalır).
    linked_upload_item = (
        db.query(PdfUploadItem)
        .filter(PdfUploadItem.transaction_id == transaction_id)
        .first()
    )
    if linked_upload_item is not None:
        linked_upload_item.status = "skipped"
        linked_upload_item.transaction_id = None

    db.delete(item)
    db.commit()
    return None


@app.get("/analytics")
def analytics(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    items = (
        db.query(Transaction)
        .filter(Transaction.user_id == current_user.id)
        .order_by(Transaction.date.asc(), Transaction.id.asc())
        .all()
    )

    category_totals = defaultdict(float)
    monthly_totals = defaultdict(float)

    for item in items:
        amount = float(item.amount or 0)

        if amount >= 0 or item.transaction_type in {"transfer", "credit_card_payment"}:
            continue

        expense = abs(amount)
        category = (item.category or "Diger").strip() or "Diger"
        category_totals[category] += expense

        if item.date:
            month_key = item.date.strftime("%Y-%m")
            monthly_totals[month_key] += expense

    categories = [
        {"name": name, "amount": round(total, 2)}
        for name, total in sorted(
            category_totals.items(),
            key=lambda pair: pair[1],
            reverse=True,
        )
    ]

    monthly_expenses = [
        {"month": format_month_label(key), "amount": round(monthly_totals[key], 2)}
        for key in sorted(monthly_totals.keys())
    ]

    return {
        "categories": categories,
        "monthly_expenses": monthly_expenses,
    }


def _calculate_monthly_forecast(monthly_totals: dict[str, float]) -> dict[str, float | int | str]:
    if not monthly_totals:
        return {
            "predicted_expense": 0,
            "confidence": 0,
            "message": "Henüz yeterli gider verisi yok. Tahmin oluşturmak için işlem eklemelisin.",
        }

    ordered_months = sorted(monthly_totals.items())
    values = [float(amount) for _, amount in ordered_months]

    if len(values) == 1:
        predicted = values[0]
        return {
            "predicted_expense": round(predicted, 2),
            "confidence": 40,
            "message": "Tek aylık veri mevcut. Gelecek ay giderler benzer düzeyde devam edebilir.",
        }

    recent_values = values[-min(len(values), 6):]
    weights = list(range(1, len(recent_values) + 1))
    weighted_average = sum(value * weight for value, weight in zip(recent_values, weights)) / sum(weights)

    baseline = weighted_average
    slope = (recent_values[-1] - recent_values[0]) / max(len(recent_values) - 1, 1)
    avg_level = sum(recent_values) / len(recent_values)
    trend_factor = 1 + (slope / max(avg_level, 1)) * 0.8

    predicted = max(baseline * min(max(trend_factor, 0.7), 1.35), 0)

    if len(values) >= 6:
        confidence = 88
    elif len(values) >= 4:
        confidence = 78
    elif len(values) >= 3:
        confidence = 66
    else:
        confidence = 52

    volatility = statistics.pstdev(recent_values)
    if avg_level > 0 and volatility > (avg_level * 0.5):
        confidence = max(confidence - 15, 35)

    if recent_values[-1] > recent_values[0]:
        direction = "artıyor"
    elif recent_values[-1] < recent_values[0]:
        direction = "azalıyor"
    else:
        direction = "sakin"

    message = (
        f"Son {len(recent_values)} ay verisine göre gelecek ay giderler {direction}. "
        f"Tahmini aylık harcama yaklaşık {predicted:.2f} TL."
    )

    return {
        "predicted_expense": round(predicted, 2),
        "confidence": int(confidence),
        "message": message,
    }


@app.get("/prediction")
def prediction(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    items = (
        db.query(Transaction)
        .filter(Transaction.user_id == current_user.id)
        .order_by(Transaction.date.asc(), Transaction.id.asc())
        .all()
    )

    monthly_totals = defaultdict(float)

    for item in items:
        amount = float(item.amount or 0)

        if amount >= 0 or item.transaction_type in {"transfer", "credit_card_payment"} or not item.date:
            continue

        month_key = item.date.strftime("%Y-%m")
        monthly_totals[month_key] += abs(amount)

    return _calculate_monthly_forecast(dict(monthly_totals))