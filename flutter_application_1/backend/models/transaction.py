from sqlalchemy import Column, ForeignKey, Integer, String, Numeric, Date
from sqlalchemy.orm import declarative_base

Base = declarative_base()

class Transaction(Base):
    __tablename__ = "transactions"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    title = Column(String(255), nullable=False)
    description = Column(String(500), nullable=False, default="", server_default="")
    amount = Column(Numeric(12, 2), nullable=False)  # Para için Decimal
    category = Column(String(100), nullable=False)
    date = Column(Date, nullable=False)
    source_type = Column(String(20), nullable=False, default="bank", server_default="bank")
    transaction_type = Column(String(30), nullable=False, default="expense", server_default="expense")
    institution_name = Column(String(120), nullable=False, default="Bilinmiyor", server_default="Bilinmiyor")