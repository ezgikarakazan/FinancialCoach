from sqlalchemy import Column, ForeignKey, Integer, Numeric, String, UniqueConstraint

from models.transaction import Base


class CategoryBudget(Base):
    __tablename__ = "category_budgets"
    __table_args__ = (
        UniqueConstraint("user_id", "category", name="uq_user_category_budget"),
    )

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    category = Column(String(100), nullable=False)
    monthly_limit = Column(Numeric(12, 2), nullable=False)
    warning_percent = Column(Integer, nullable=False, default=80, server_default="80")
