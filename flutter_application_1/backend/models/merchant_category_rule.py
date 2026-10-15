from sqlalchemy import Column, ForeignKey, Integer, String, UniqueConstraint

from models.transaction import Base


class MerchantCategoryRule(Base):
    __tablename__ = "merchant_category_rules"
    __table_args__ = (
        UniqueConstraint("user_id", "merchant_key", name="uq_user_merchant_category"),
    )

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    merchant_key = Column(String(120), nullable=False)
    category = Column(String(100), nullable=False)
