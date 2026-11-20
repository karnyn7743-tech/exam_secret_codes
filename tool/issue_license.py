import base64
import json
import os
import re
import time
from pathlib import Path

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / ".licenses" / "trial_devices.json"


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


device = os.environ["DEVICE_ID"].strip().upper()
kind = os.environ["LICENSE_TYPE"].strip().lower()
private_pem = os.environ["LICENSE_PRIVATE_KEY_PEM"].encode("utf-8")

if not re.fullmatch(r"[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}", device):
    raise SystemExit("Invalid device ID format.")
if kind not in {"trial", "full"}:
    raise SystemExit("Unsupported license type.")
if not private_pem.strip():
    raise SystemExit("LICENSE_PRIVATE_KEY_PEM is empty.")

now = int(time.time())
expires = now + 30 * 24 * 60 * 60 if kind == "trial" else 0

REGISTRY.parent.mkdir(parents=True, exist_ok=True)
registry = json.loads(REGISTRY.read_text("utf-8")) if REGISTRY.exists() else {}

if kind == "trial" and device in registry:
    raise SystemExit("A trial license has already been issued for this device. A second trial is not allowed.")

payload = {
    "v": 1,
    "app": "exam_secret_codes",
    "device": device,
    "type": kind,
    "issuedAt": now,
    "expiresAt": expires,
}
payload_bytes = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("utf-8")

private_key = serialization.load_pem_private_key(private_pem, password=None)
signature = private_key.sign(payload_bytes, padding.PKCS1v15(), hashes.SHA256())
token = b64url(payload_bytes) + "." + b64url(signature)
Path("license.txt").write_text(token + "\n", encoding="utf-8")

if kind == "trial":
    registry[device] = {"issuedAt": now, "expiresAt": expires}
    REGISTRY.write_text(json.dumps(registry, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

print("License issued successfully.")
print("Device:", device)
print("Type:", kind)
print("Expires:", expires if expires else "never")
