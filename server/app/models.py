from sqlalchemy import Column, Integer, String, Boolean, ForeignKey, DateTime
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from .database import Base

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    username = Column(String, unique=True, index=True)
    hashed_password = Column(String)
    identity_key = Column(String, unique=True, index=True) # Public identity key
    registration_id = Column(Integer)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

class PreKey(Base):
    __tablename__ = "prekeys"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    key_id = Column(Integer, index=True)
    public_key = Column(String) # Base64 encoded public key
    
    user = relationship("User", backref="prekeys")

class SignedPreKey(Base):
    __tablename__ = "signed_prekeys"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), unique=True)
    key_id = Column(Integer)
    public_key = Column(String)
    signature = Column(String)

    user = relationship("User", backref="signed_prekey")

class Message(Base):
    """
    Offline message queue.
    Stores encrypted message blobs until the recipient fetches them.
    """
    __tablename__ = "messages"

    id = Column(Integer, primary_key=True, index=True)
    sender_id = Column(Integer, ForeignKey("users.id"))
    recipient_id = Column(Integer, ForeignKey("users.id"))
    content = Column(String) # Encrypted JSON blob
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    delivered = Column(Boolean, default=False)