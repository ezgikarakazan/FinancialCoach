from datetime import date, timedelta

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

import main
from models.transaction import Base, Transaction
from models.user import User


def test_ai_summary_defaults_to_the_last_30_days():
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
                email="finance-summary@test.com",
                password_hash="not-used",
            )
            db.add(user)
            db.flush()

            db.add_all(
                [
                    Transaction(
                        user_id=user.id,
                        title=(
                            "Old expense - Sayfa 1/3 Enpara Bank A.Ş "
                            "Ticaret sicil no 494129-5"
                        ),
                        amount=-31837.50,
                        category="Other",
                        date=date.today() - timedelta(days=90),
                    ),
                    Transaction(
                        user_id=user.id,
                        title="Recent income",
                        amount=1000,
                        category="Income",
                        date=date.today(),
                    ),
                    Transaction(
                        user_id=user.id,
                        title="Recent expense",
                        amount=-21552.01,
                        category="Bills",
                        date=date.today(),
                    ),
                ]
            )
            db.flush()

            summary = main.get_ai_coach_summary(db=db, current_user=user)
            transactions = main.transactions(db=db, current_user=user)
            old_transaction = next(
                item for item in transactions if item["title"].startswith("Old expense")
            )

            assert summary["period_days"] == 30
            assert summary["total_income"] == 1000
            assert summary["total_expense"] == 21552.01
            assert summary["net_saving"] == -20552.01
            assert summary["risk_level"] == "Yüksek"
            assert old_transaction["title"] == "Old expense"
    finally:
        Base.metadata.drop_all(engine)
        engine.dispose()
