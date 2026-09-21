from typing import Literal

from pydantic import BaseModel, Field

SignalKind = Literal["offer", "answer", "ice", "bye", "ice-restart", "chat"]


class RegisterRequest(BaseModel):
    device_id: str = Field(min_length=8, max_length=64)
    pubkey_ed25519: str = Field(min_length=32, max_length=128)
    pubkey_x25519: str = Field(min_length=32, max_length=128)
    signature: str = Field(min_length=32, max_length=256)


class RegisterResponse(BaseModel):
    ok: bool
    device_id: str


class SendSignalRequest(BaseModel):
    to_device_id: str = Field(min_length=8, max_length=64)
    signal_id: str = Field(min_length=8, max_length=64)
    kind: SignalKind
    payload: str


class SendSignalResponse(BaseModel):
    signal_id: str
    seq: int


class PolledSignal(BaseModel):
    signal_id: str
    from_device_id: str
    kind: SignalKind
    payload: str
    seq: int


class PollResponse(BaseModel):
    signals: list[PolledSignal]
    cursor: int


class AckResponse(BaseModel):
    ok: bool
    deleted: bool


class OPKUpload(BaseModel):
    opk_id: int = Field(ge=1)
    public: str = Field(min_length=32, max_length=64)


class PreKeyUpload(BaseModel):
    spk_id: int = Field(ge=1)
    spk_public: str = Field(min_length=32, max_length=64)
    spk_signature: str = Field(min_length=32, max_length=256)
    opks: list[OPKUpload] = Field(default_factory=list, max_length=500)


class BundleResponse(BaseModel):
    device_id: str
    identity_ed25519: str
    identity_x25519: str
    spk_id: int
    spk_public: str
    spk_signature: str
    opk_id: int | None
    opk_public: str | None


class PreKeyCountResponse(BaseModel):
    spk_present: bool
    opks_remaining: int