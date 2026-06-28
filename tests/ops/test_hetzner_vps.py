import importlib.util
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("hetzner_vps", ROOT / "projects/ops/scripts/hetzner_vps.py")
hv = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
sys.modules[SPEC.name] = hv
SPEC.loader.exec_module(hv)


FAKE_PUBKEY = (
    "ssh-ed25519 "
    "AAAAC3NzaC1lZDI1NTE5AAAAIH9Q9d6r8tZ2cFx5xYqJk0w0lR5N4HwQ8aZ7vJ8fABCD "
    "operator@workstation"
)


def test_choose_server_type_picks_cheapest_matching_shape():
    catalog = [
        hv.ServerType("cx22", 2, 40, 2, "x86", 3.79, "ash", 1),
        hv.ServerType("cx23", 4, 40, 2, "x86", 4.99, "ash", 2),
        hv.ServerType("cpx31", 8, 160, 4, "x86", 15.99, "ash", 3),
    ]

    selected = hv.choose_server_type(catalog, min_ram=4, min_disk=40, arch="amd", max_price_monthly=25)

    assert selected is not None
    assert selected.name == "cx23"


def test_choose_server_type_respects_price_ceiling():
    catalog = [hv.ServerType("cx23", 4, 40, 2, "x86", 4.99, "ash", 2)]

    assert hv.choose_server_type(catalog, min_ram=4, min_disk=40, arch="amd", max_price_monthly=4.0) is None


def test_cloud_init_is_non_tailscale_and_authorizes_bot():
    rendered = hv.render_cloud_init("stevetrading-live-1", FAKE_PUBKEY)

    assert "tailscale" not in rendered.lower()
    assert "useradd -m -s /bin/bash bot" in rendered
    assert FAKE_PUBKEY in rendered
    assert "PasswordAuthentication no" in rendered
    assert "/opt/stevetrading" in rendered


def test_redact_payload_masks_public_key_and_truncates_user_data():
    payload = {
        "ssh_keys": [123],
        "user_data": hv.render_cloud_init("stevetrading-live-1", FAKE_PUBKEY) + ("\n#" * 1000),
    }

    redacted = hv.redact_payload(payload)

    assert redacted["ssh_keys"] == ["<operator-key-id>"]
    assert FAKE_PUBKEY not in redacted["user_data"]
    assert "ssh-<REDACTED-OPERATOR-PUBKEY>" in redacted["user_data"]
    assert "<truncated" in redacted["user_data"]


def test_load_env_file_and_get_secret(tmp_path: Path, monkeypatch):
    env_file = tmp_path / ".env"
    env_file.write_text("HCLOUD_TOKEN='from-file'\n")
    monkeypatch.delenv("HCLOUD_TOKEN", raising=False)

    assert hv.get_secret("HCLOUD_TOKEN", env_file=env_file) == "from-file"

    monkeypatch.setenv("HCLOUD_TOKEN", "from-env")
    assert hv.get_secret("HCLOUD_TOKEN", env_file=env_file) == "from-env"


def test_pubkey_fingerprint_shape():
    fp = hv.pubkey_fingerprint(FAKE_PUBKEY)

    assert len(fp.split(":")) == 16
    assert all(len(part) == 2 for part in fp.split(":"))
