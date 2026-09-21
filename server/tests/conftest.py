import os
import tempfile
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

_tmp = Path(tempfile.mkdtemp(prefix="p2p_test_"))
os.environ["DATABASE_URL"] = f"sqlite:///{_tmp}/test.db"

from app.database import Base, engine  # noqa: E402
from app.main import app  # noqa: E402


@pytest.fixture(autouse=True)
def fresh_db():
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)
    yield


@pytest.fixture
def client():
    with TestClient(app) as c:
        yield c