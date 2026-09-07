from datetime import date

from sqlalchemy import Column, Date, ForeignKey, Integer, Numeric, String, Text
from sqlalchemy.orm import relationship

from models.transaction import Base


class Plan(Base):
    __tablename__ = "plans"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    name = Column(String(160), nullable=False)
    plan_type = Column(String(20), nullable=False)
    target_amount = Column(Numeric(12, 2), nullable=False, default=0, server_default="0")
    monthly_amount = Column(Numeric(12, 2), nullable=False, default=0, server_default="0")
    total_installments = Column(Integer, nullable=False, default=0, server_default="0")
    paid_installments = Column(Integer, nullable=False, default=0, server_default="0")
    start_date = Column(Date, nullable=False, default=date.today)
    notes = Column(Text, nullable=False, default="", server_default="")

    entries = relationship(
        "PlanEntry",
        backref="plan",
        cascade="all, delete-orphan",
        order_by="PlanEntry.date.desc(), PlanEntry.id.desc()",
    )


class PlanEntry(Base):
    __tablename__ = "plan_entries"

    id = Column(Integer, primary_key=True, index=True)
    plan_id = Column(Integer, ForeignKey("plans.id"), nullable=False, index=True)
    title = Column(String(160), nullable=False)
    amount = Column(Numeric(12, 2), nullable=False)
    date = Column(Date, nullable=False)
    notes = Column(Text, nullable=False, default="", server_default="")