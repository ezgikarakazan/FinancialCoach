from datetime import date

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

import main
from models.pdf_upload import PdfUpload, PdfUploadItem
from models.transaction import Base
from models.user import User


def test_confirmed_category_is_learned_for_future_uploads_per_user():
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    session_factory = sessionmaker(bind=engine)

    try:
        with session_factory() as db:
            user = User(
                name="Test User",
                email="merchant-learning@test.com",
                password_hash="not-used",
            )
            other_user = User(
                name="Other User",
                email="other-merchant-learning@test.com",
                password_hash="not-used",
            )
            db.add_all([user, other_user])
            db.flush()

            upload = PdfUpload(
                user_id=user.id,
                filename="statement.pdf",
                file_hash="a" * 64,
                statement_type="bank",
                institution_name="Test Bank",
            )
            db.add(upload)
            db.flush()
            item = PdfUploadItem(
                upload_id=upload.id,
                date=date.today(),
                title="Diğer, HAKMAR MARKET ISTANBUL",
                amount=-250,
                category="Diğer",
                source_type="bank",
                transaction_type="expense",
                status="pending",
            )
            db.add(item)
            db.flush()

            main.decide_pdf_upload_item(
                upload_id=upload.id,
                item_id=item.id,
                payload=main.PdfUploadItemDecision(
                    status="added",
                    category="Alışveriş",
                    learn_category=True,
                ),
                db=db,
                current_user=user,
            )

            unlearned_item = PdfUploadItem(
                upload_id=upload.id,
                date=date.today(),
                title="Diğer, TEST TAXI ISTANBUL",
                amount=-100,
                category="Diğer",
                source_type="bank",
                transaction_type="expense",
                status="pending",
            )
            db.add(unlearned_item)
            db.flush()
            main.decide_pdf_upload_item(
                upload_id=upload.id,
                item_id=unlearned_item.id,
                payload=main.PdfUploadItemDecision(
                    status="added",
                    category="Ulaşım",
                ),
                db=db,
                current_user=user,
            )
            assert db.query(main.MerchantCategoryRule).count() == 1

            next_upload = [
                {
                    "title": "Diğer, Hakmar Express Kadikoy",
                    "category": "Diğer",
                },
                {
                    "title": "Diğer, Hakmar Express Kadikoy",
                    "category": "Diğer",
                },
            ]
            main._apply_learned_merchant_categories(db, user.id, next_upload[:1])
            main._apply_learned_merchant_categories(db, other_user.id, next_upload[1:])

            assert next_upload[0]["category"] == "Alışveriş"
            assert next_upload[1]["category"] == "Diğer"
    finally:
        Base.metadata.drop_all(engine)
        engine.dispose()
