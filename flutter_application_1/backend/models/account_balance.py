from sqlalchemy import Column, Date, ForeignKey, Integer, Numeric, String, UniqueConstraint

from models.transaction import Base


class AccountBalance(Base):
    __tablename__ = "account_balances"
    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "institution_name",
            "balance_date",
            name="uq_user_institution_balance_date",
        ),
    )

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    institution_name = Column(String(120), nullable=False)
    balance = Column(Numeric(12, 2), nullable=False)
    balance_date = Column(Date, nullable=False)
