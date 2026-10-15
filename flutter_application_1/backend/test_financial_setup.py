from datetime import date, timedelta
from decimal import Decimal

import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

import main
from models.account_balance import AccountBalance
from models.category_budget import CategoryBudget
from models.pdf_upload import PdfUpload
from models.plan import Plan
from models.transaction import Base, Transaction
from models.user import User


@pytest.fixture
def db_session():
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(engine)
    session_factory = sessionmaker(bind=engine)
    with session_factory() as session:
        yield session
    Base.metadata.drop_all(engine)
    engine.dispose()


def test_account_balance_is_saved_per_user_and_date(db_session):
    user = User(name="Test User", email="balance@test.com", password_hash="unused")
    other_user = User(
        name="Other User",
        email="other-balance@test.com",
        password_hash="unused",
    )
    db_session.add_all([user, other_user])
    db_session.flush()

    payload = main.AccountBalanceCreate(
        institution_name="Enpara",
        balance=Decimal("12500.50"),
        balance_date=date(2026, 9, 1),
    )
    first = main.save_account_balance(payload, db_session, user)
    updated = main.save_account_balance(
        main.AccountBalanceCreate(
            institution_name=" Enpara ",
            balance=Decimal("14000.00"),
            balance_date=date(2026, 9, 1),
        ),
        db_session,
        user,
    )
    other = main.save_account_balance(payload, db_session, other_user)

    assert first.id == updated.id
    assert updated.balance == Decimal("14000.00")
    assert other.id != updated.id
    assert db_session.query(AccountBalance).count() == 2
    assert len(main.list_account_balances(db_session, user)) == 1


def test_account_balance_rejects_a_future_balance_date(db_session):
    user = User(name="Test User", email="future-balance@test.com", password_hash="unused")
    db_session.add(user)
    db_session.flush()

    with pytest.raises(HTTPException) as error:
        main.save_account_balance(
            main.AccountBalanceCreate(
                institution_name="Enpara",
                balance=Decimal("10"),
                balance_date=date.today() + timedelta(days=1),
            ),
            db_session,
            user,
        )

    assert error.value.status_code == 400


def test_account_balance_edit_moves_existing_setup_snapshot(db_session):
    user = User(name="Test User", email="balance-edit@test.com", password_hash="unused")
    db_session.add(user)
    db_session.flush()
    old_date = date(2026, 8, 3)
    new_date = date(2026, 9, 3)
    old_balance = AccountBalance(
        user_id=user.id,
        institution_name="Enpara",
        balance=Decimal("12500.50"),
        balance_date=old_date,
    )
    db_session.add(old_balance)
    db_session.flush()

    updated = main.save_account_balance(
        main.AccountBalanceCreate(
            institution_name="Enpara",
            balance=Decimal("13000.00"),
            balance_date=new_date,
            previous_institution_name="Enpara",
            previous_balance_date=old_date,
        ),
        db_session,
        user,
    )

    assert updated.balance_date == new_date
    assert updated.balance == Decimal("13000.00")
    balances = main.list_account_balances(db_session, user)
    assert len(balances) == 1
    assert balances[0].id == updated.id


def test_category_budget_reports_current_month_spending_for_its_owner(db_session):
    user = User(name="Test User", email="budget@test.com", password_hash="unused")
    other_user = User(
        name="Other User",
        email="other-budget@test.com",
        password_hash="unused",
    )
    db_session.add_all([user, other_user])
    db_session.flush()
    db_session.add_all(
        [
            Transaction(
                user_id=user.id,
                title="Market",
                amount=Decimal("-800"),
                category="Alışveriş",
                date=date.today(),
                transaction_type="expense",
            ),
            Transaction(
                user_id=other_user.id,
                title="Other user market",
                amount=Decimal("-500"),
                category="Alışveriş",
                date=date.today(),
                transaction_type="expense",
            ),
        ]
    )
    db_session.flush()

    result = main.save_category_budget(
        main.CategoryBudgetCreate(
            category="Alışveriş",
            monthly_limit=Decimal("1000"),
        ),
        db_session,
        user,
    )

    assert result["spent_this_month"] == 800
    assert result["percent_used"] == 80
    assert len(main.list_category_budgets(db_session, user)) == 1
    assert db_session.query(CategoryBudget).count() == 1


def test_financial_goal_update_does_not_create_duplicate_plans(db_session):
    user = User(name="Test User", email="goal@test.com", password_hash="unused")
    db_session.add(user)
    db_session.flush()

    first = main.save_financial_goal(
        main.FinancialGoalCreate(name="Acil durum fonu", target_amount=Decimal("10000")),
        db_session,
        user,
    )
    updated = main.save_financial_goal(
        main.FinancialGoalCreate(name="Tatil", target_amount=Decimal("15000")),
        db_session,
        user,
    )

    assert first["id"] == updated["id"]
    assert updated["name"] == "Tatil"
    assert updated["target_amount"] == 15000
    assert db_session.query(Plan).count() == 1


def test_pdf_history_exposes_selected_statement_date(db_session):
    user = User(name="Test User", email="statement-date@test.com", password_hash="unused")
    db_session.add(user)
    db_session.flush()
    upload = PdfUpload(
        user_id=user.id,
        filename="statement.pdf",
        file_hash="b" * 64,
        statement_type="bank",
        institution_name="Enpara",
        statement_date=date(2026, 9, 1),
    )
    db_session.add(upload)
    db_session.flush()

    history = main.list_pdf_uploads(db_session, user)
    detail = main.get_pdf_upload(upload.id, db_session, user)

    assert history[0].statement_date == date(2026, 9, 1)
    assert detail.statement_date == date(2026, 9, 1)


def test_dashboard_uses_opening_balance_and_transactions_from_its_date_onward(
    db_session,
):
    user = User(
        name="Test User",
        email="dashboard-balance@test.com",
        password_hash="unused",
    )
    db_session.add(user)
    db_session.flush()
    balance_date = date.today() - timedelta(days=10)
    db_session.add(
        AccountBalance(
            user_id=user.id,
            institution_name="Enpara",
            balance=Decimal("1000"),
            balance_date=balance_date,
        )
    )
    db_session.add_all(
        [
            Transaction(
                user_id=user.id,
                title="Before opening balance",
                amount=Decimal("-500"),
                category="Alışveriş",
                date=balance_date - timedelta(days=1),
                source_type="bank",
                transaction_type="expense",
                institution_name="Enpara",
            ),
            Transaction(
                user_id=user.id,
                title="On opening balance date",
                amount=Decimal("-50"),
                category="Yeme İçme",
                date=balance_date,
                source_type="bank",
                transaction_type="expense",
                institution_name="Enpara",
            ),
            Transaction(
                user_id=user.id,
                title="After opening balance",
                amount=Decimal("-200"),
                category="Alışveriş",
                date=balance_date + timedelta(days=1),
                source_type="bank",
                transaction_type="expense",
                institution_name="Enpara",
            ),
        ]
    )
    db_session.flush()

    summary = main.dashboard(db_session, user)

    assert summary["balance"] == 750
    assert summary["saving"] == -750
