from sqlalchemy import Column, Integer, String, Numeric, Date, DateTime, ForeignKey, func
from sqlalchemy.orm import relationship

from models.transaction import Base


class PdfUpload(Base):
    __tablename__ = "pdf_uploads"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    filename = Column(String(255), nullable=False)
    file_hash = Column(String(64), nullable=False, index=True)
    statement_type = Column(String(20), nullable=False, default="bank", server_default="bank")
    institution_name = Column(String(120), nullable=False, default="Bilinmiyor", server_default="Bilinmiyor")
    uploaded_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)

    items = relationship(
        "PdfUploadItem",
        backref="upload",
        cascade="all, delete-orphan",
        order_by="PdfUploadItem.id",
    )


class PdfUploadItem(Base):
    __tablename__ = "pdf_upload_items"

    id = Column(Integer, primary_key=True, index=True)
    upload_id = Column(Integer, ForeignKey("pdf_uploads.id"), nullable=False, index=True)
    date = Column(Date, nullable=False)
    title = Column(String(255), nullable=False)
    description = Column(String(500), nullable=False, default="", server_default="")
    amount = Column(Numeric(12, 2), nullable=False)
    category = Column(String(100), nullable=False)
    source_type = Column(String(20), nullable=False, default="bank", server_default="bank")
    transaction_type = Column(String(30), nullable=False, default="expense", server_default="expense")
    status = Column(String(20), nullable=False, default="pending")  # pending | added | skipped
    transaction_id = Column(Integer, ForeignKey("transactions.id"), nullable=True)
