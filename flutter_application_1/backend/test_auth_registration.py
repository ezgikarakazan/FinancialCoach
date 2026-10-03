import pytest
from fastapi import HTTPException
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

import main
from models.transaction import Base
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


def _payload(
    email="ada@gmail.com",
    password="Strong123!",
    password_confirmation=None,
    first_name="Ada",
    last_name="Test",
):
    return main.RegisterRequest(
        first_name=first_name,
        last_name=last_name,
        email=email,
        password=password,
        password_confirmation=password_confirmation or password,
    )


def test_register_creates_account_and_returns_token_immediately(db_session):
    response = main.register(_payload(), db_session)

    user = db_session.query(User).filter_by(email="ada@gmail.com").one()
    assert response["access_token"]
    assert response["user"]["name"] == "Ada Test"
    assert user.password_hash != "Strong123!"


def test_register_rejects_weak_password(db_session):
    with pytest.raises(HTTPException) as error:
        main.register(_payload(password="password"), db_session)

    assert error.value.status_code == 400
    assert db_session.query(User).count() == 0


@pytest.mark.parametrize("first_name,last_name", [("", "Test"), ("Ada", "")])
def test_register_requires_first_and_last_name(db_session, first_name, last_name):
    with pytest.raises(HTTPException) as error:
        main.register(
            _payload(first_name=first_name, last_name=last_name),
            db_session,
        )

    assert error.value.status_code == 400
    assert db_session.query(User).count() == 0


@pytest.mark.parametrize("first_name,last_name", [("Ada1", "Test"), ("Ada", "Test2")])
def test_register_rejects_digits_in_names(db_session, first_name, last_name):
    with pytest.raises(HTTPException) as error:
        main.register(
            _payload(first_name=first_name, last_name=last_name),
            db_session,
        )

    assert error.value.status_code == 400
    assert db_session.query(User).count() == 0


def test_register_rejects_password_mismatch(db_session):
    with pytest.raises(HTTPException) as error:
        main.register(
            _payload(password_confirmation="Different123!"),
            db_session,
        )

    assert error.value.status_code == 400
    assert db_session.query(User).count() == 0


@pytest.mark.parametrize(
    "email",
    [
        "gmail-user@gmail.com",
        "hotmail-user@hotmail.com",
        "test-user@test.com",
        "custom-user@finance.co.uk",
    ],
)
def test_register_accepts_valid_email_domains(db_session, email):
    result = main.register(_payload(email=email), db_session)

    assert result["user"]["email"] == email


@pytest.mark.parametrize(
    "email",
    [
        "user@example.com",
        "user@example.net",
        "user@example.org",
    ],
)
def test_register_rejects_reserved_example_domains(db_session, email):
    with pytest.raises(HTTPException) as error:
        main.register(_payload(email=email), db_session)

    assert error.value.status_code == 400
    assert db_session.query(User).count() == 0


def test_register_rejects_duplicate_email(db_session):
    main.register(_payload(), db_session)

    with pytest.raises(HTTPException) as error:
        main.register(_payload(), db_session)

    assert error.value.status_code == 409