"""initial schema

Revision ID: 0001
Revises:
"""
from alembic import op
import sqlalchemy as sa

revision = "0001"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "devices",
        sa.Column("device_id", sa.String(64), primary_key=True),
        sa.Column("pubkey_ed25519", sa.Text, nullable=False),
        sa.Column("pubkey_x25519", sa.Text, nullable=False),
        sa.Column("created_at", sa.Integer, nullable=False),
        sa.Column("last_seen_at", sa.Integer, nullable=False),
    )

    op.create_table(
        "signals",
        sa.Column("signal_id", sa.String(64), primary_key=True),
        sa.Column(
            "from_device_id", sa.String(64),
            sa.ForeignKey("devices.device_id"), nullable=False,
        ),
        sa.Column(
            "to_device_id", sa.String(64),
            sa.ForeignKey("devices.device_id"), nullable=False,
        ),
        sa.Column("kind", sa.String(16), nullable=False),
        sa.Column("payload", sa.Text, nullable=False),
        sa.Column("payload_bytes", sa.Integer, nullable=False),
        sa.Column("seq", sa.Integer, autoincrement=True, unique=True, nullable=False),
        sa.Column("created_at", sa.Integer, nullable=False),
        sa.Column("expires_at", sa.Integer, nullable=False),
    )
    op.create_index("ix_signals_from", "signals", ["from_device_id"])
    op.create_index("ix_signals_to", "signals", ["to_device_id"])
    op.create_index("ix_signals_expires", "signals", ["expires_at"])
    op.create_index(
        "ix_signals_recipient_seq", "signals", ["to_device_id", "seq"]
    )

    op.create_table(
        "rate_buckets",
        sa.Column("device_id", sa.String(64), primary_key=True),
        sa.Column("kind", sa.String(16), primary_key=True),
        sa.Column("window_start", sa.Integer, primary_key=True),
        sa.Column("count", sa.Integer, nullable=False, server_default="0"),
        sa.UniqueConstraint("device_id", "kind", "window_start"),
    )

    op.create_table(
        "signed_prekeys",
        sa.Column(
            "device_id", sa.String(64),
            sa.ForeignKey("devices.device_id"), primary_key=True,
        ),
        sa.Column("spk_id", sa.Integer, primary_key=True),
        sa.Column("public", sa.Text, nullable=False),
        sa.Column("signature", sa.Text, nullable=False),
        sa.Column("created_at", sa.Integer, nullable=False),
        sa.Column("expires_at", sa.Integer, nullable=False),
    )
    op.create_index("ix_spk_expires", "signed_prekeys", ["expires_at"])

    op.create_table(
        "one_time_prekeys",
        sa.Column(
            "device_id", sa.String(64),
            sa.ForeignKey("devices.device_id"), primary_key=True,
        ),
        sa.Column("opk_id", sa.Integer, primary_key=True),
        sa.Column("public", sa.Text, nullable=False),
        sa.Column("created_at", sa.Integer, nullable=False),
        sa.Column("consumed_at", sa.Integer, nullable=True),
    )
    op.create_index(
        "ix_opk_device_unconsumed", "one_time_prekeys",
        ["device_id", "consumed_at"],
    )


def downgrade() -> None:
    op.drop_table("one_time_prekeys")
    op.drop_table("signed_prekeys")
    op.drop_table("rate_buckets")
    op.drop_table("signals")
    op.drop_table("devices")