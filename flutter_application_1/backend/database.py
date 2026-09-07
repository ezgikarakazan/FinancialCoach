from sqlalchemy import create_engine, inspect, text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import sessionmaker

DATABASE_URL = "sqlite:///./finance_ai.db"

engine = create_engine(
    DATABASE_URL,
    connect_args={"check_same_thread": False}
)

SessionLocal = sessionmaker(
    autocommit=False,
    autoflush=False,
    bind=engine
)


def ensure_transaction_user_id_column() -> None:
    """Eski (auth öncesi) transactions tablosuna user_id kolonu ekler.

    SQLite ALTER TABLE ile NOT NULL + FK eklenemediği için kolon nullable
    olarak eklenir; sahibi belli olmayan (auth öncesi) satırlar silinir,
    çünkü hiçbir kullanıcıya atanamazlar.
    """
    inspector = inspect(engine)
    if "transactions" not in inspector.get_table_names():
        return

    columns = [col["name"] for col in inspector.get_columns("transactions")]
    if "user_id" in columns:
        return

    with engine.begin() as connection:
        connection.execute(text("ALTER TABLE transactions ADD COLUMN user_id INTEGER"))
        connection.execute(text("DELETE FROM transactions WHERE user_id IS NULL"))


def ensure_user_login_security_columns() -> None:
    """Eski users tablosuna brute-force koruması için gereken kolonları ekler."""
    inspector = inspect(engine)
    if "users" not in inspector.get_table_names():
        return

    columns = [col["name"] for col in inspector.get_columns("users")]

    with engine.begin() as connection:
        if "failed_login_attempts" not in columns:
            connection.execute(
                text("ALTER TABLE users ADD COLUMN failed_login_attempts INTEGER DEFAULT 0")
            )
        if "locked_until" not in columns:
            connection.execute(text("ALTER TABLE users ADD COLUMN locked_until DATETIME"))


def ensure_user_access_columns() -> None:
    """Eski kullanıcılara rol ve abonelik alanlarını ekler."""
    inspector = inspect(engine)
    if "users" not in inspector.get_table_names():
        return

    columns = [col["name"] for col in inspector.get_columns("users")]
    with engine.begin() as connection:
        if "role" not in columns:
            connection.execute(text("ALTER TABLE users ADD COLUMN role VARCHAR(20) DEFAULT 'user'"))
        if "subscription_type" not in columns:
            connection.execute(text("ALTER TABLE users ADD COLUMN subscription_type VARCHAR(20) DEFAULT 'free'"))
        if "subscription_expires_at" not in columns:
            connection.execute(text("ALTER TABLE users ADD COLUMN subscription_expires_at DATETIME"))


def ensure_transaction_source_type_column() -> None:
    """Eski transaction kayıtlarına banka/kredi kartı kaynağı bilgisi ekler."""
    inspector = inspect(engine)
    if "transactions" not in inspector.get_table_names():
        return

    columns = [col["name"] for col in inspector.get_columns("transactions")]
    if "source_type" in columns:
        return

    with engine.begin() as connection:
        connection.execute(
            text("ALTER TABLE transactions ADD COLUMN source_type VARCHAR(20) DEFAULT 'bank'")
        )


def ensure_transaction_classification_columns() -> None:
    inspector = inspect(engine)
    if "transactions" not in inspector.get_table_names():
        return

    columns = [col["name"] for col in inspector.get_columns("transactions")]
    with engine.begin() as connection:
        if "transaction_type" not in columns:
            connection.execute(
                text("ALTER TABLE transactions ADD COLUMN transaction_type VARCHAR(30) DEFAULT 'expense'")
            )
        if "institution_name" not in columns:
            connection.execute(
                text("ALTER TABLE transactions ADD COLUMN institution_name VARCHAR(120) DEFAULT 'Bilinmiyor'")
            )


def ensure_pdf_upload_statement_type_columns() -> None:
    """Eski PDF yüklemelerine ekstre tipi bilgisini ekler."""
    inspector = inspect(engine)

    if "pdf_uploads" in inspector.get_table_names():
        upload_columns = [col["name"] for col in inspector.get_columns("pdf_uploads")]
        with engine.begin() as connection:
            if "statement_type" not in upload_columns:
                connection.execute(
                    text("ALTER TABLE pdf_uploads ADD COLUMN statement_type VARCHAR(20) DEFAULT 'bank'")
                )
            if "institution_name" not in upload_columns:
                connection.execute(
                    text("ALTER TABLE pdf_uploads ADD COLUMN institution_name VARCHAR(120) DEFAULT 'Bilinmiyor'")
                )

    if "pdf_upload_items" in inspector.get_table_names():
        item_columns = [col["name"] for col in inspector.get_columns("pdf_upload_items")]
        with engine.begin() as connection:
            if "source_type" not in item_columns:
                connection.execute(
                    text("ALTER TABLE pdf_upload_items ADD COLUMN source_type VARCHAR(20) DEFAULT 'bank'")
                )
            if "transaction_type" not in item_columns:
                connection.execute(
                    text("ALTER TABLE pdf_upload_items ADD COLUMN transaction_type VARCHAR(30) DEFAULT 'expense'")
                )


def ensure_description_columns() -> None:
    """Eski işlem ve PDF öğelerine isteğe bağlı açıklama alanı ekler."""
    inspector = inspect(engine)
    with engine.begin() as connection:
        if "transactions" in inspector.get_table_names():
            columns = [col["name"] for col in inspector.get_columns("transactions")]
            if "description" not in columns:
                connection.execute(
                    text("ALTER TABLE transactions ADD COLUMN description VARCHAR(500) DEFAULT ''")
                )

        if "pdf_upload_items" in inspector.get_table_names():
            columns = [col["name"] for col in inspector.get_columns("pdf_upload_items")]
            if "description" not in columns:
                connection.execute(
                    text("ALTER TABLE pdf_upload_items ADD COLUMN description VARCHAR(500) DEFAULT ''")
                )


def test_connection() -> bool:
    try:
        with engine.connect() as connection:
            connection.execute(text("SELECT 1"))
        print("Database connection successful.")
        return True
    except SQLAlchemyError as exc:
        print(f"Database connection failed: {exc}")
        return False


if __name__ == "__main__":
    raise SystemExit(0 if test_connection() else 1)