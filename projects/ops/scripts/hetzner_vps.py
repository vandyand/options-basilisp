#!/usr/bin/env python3
"""Project-local Hetzner VPS provisioning for SteveTrading.

This intentionally does not depend on the Ascolais repo. The Ascolais
provisioner was used as a reference for the safe shape: idempotent SSH key
registration, cheapest-fit server selection, cloud-init rendering, leases,
dry-run redaction, and explicit create/destroy commands.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import re
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any


BASE_URL = "https://api.hetzner.cloud/v1"
DEFAULT_LEASES = Path(".hetzner/stevetrading-leases.json")


class HetznerError(RuntimeError):
    def __init__(self, message: str, *, status: int | None = None, code: str | None = None):
        super().__init__(message)
        self.status = status
        self.code = code


@dataclass(frozen=True)
class ServerType:
    name: str
    memory: int
    disk: int
    cores: int
    arch: str
    price_monthly: float
    location: str
    type_id: int


def load_env_file(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    out: dict[str, str] = {}
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        out[k.strip()] = v.strip().strip('"').strip("'")
    return out


def get_secret(name: str, *, env_file: Path | None = None, alternatives: tuple[str, ...] = ()) -> str:
    names = (name,) + alternatives
    file_env = load_env_file(env_file) if env_file else {}
    for key in names:
        val = os.environ.get(key) or file_env.get(key)
        if val:
            return val.strip()
    joined = " / ".join(names)
    source = f" or {env_file}" if env_file else ""
    raise SystemExit(f"error: {joined} not set in environment{source}")


def request(api_key: str, method: str, path: str, body: dict[str, Any] | None = None) -> dict[str, Any]:
    data = None if body is None else json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        BASE_URL + path,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Accept": "application/json",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read().decode("utf-8")
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8", "replace")
        try:
            parsed = json.loads(raw)
            err = parsed.get("error") or {}
            msg = err.get("message") or raw
            code = err.get("code")
        except json.JSONDecodeError:
            msg = raw
            code = None
        raise HetznerError(f"hetzner {method} {path} failed: {msg}", status=exc.code, code=code) from exc
    except urllib.error.URLError as exc:
        raise HetznerError(f"hetzner {method} {path} failed: {exc.reason}") from exc


def local_pubkey(path: Path | None = None) -> str:
    candidates = [path] if path else [Path.home() / ".ssh/id_ed25519.pub", Path.home() / ".ssh/id_rsa.pub"]
    for candidate in candidates:
        if candidate and candidate.exists():
            text = candidate.read_text().strip()
            if text:
                return text
    raise SystemExit("error: no SSH pubkey found; expected ~/.ssh/id_ed25519.pub or ~/.ssh/id_rsa.pub")


def pubkey_fingerprint(pubkey: str) -> str:
    parts = pubkey.strip().split()
    if len(parts) < 2:
        raise ValueError("malformed OpenSSH public key")
    blob = base64.b64decode(parts[1])
    digest = hashlib.md5(blob).hexdigest()
    return ":".join(digest[i : i + 2] for i in range(0, len(digest), 2))


def operator_key_name() -> str:
    host = socket.gethostname().split(".")[0] or "workstation"
    return f"stevetrading-operator-{host}"


def register_ssh_key(api_key: str, pubkey: str) -> int:
    fp = pubkey_fingerprint(pubkey)
    query = urllib.parse.urlencode({"fingerprint": fp})
    keys = request(api_key, "GET", f"/ssh_keys?{query}").get("ssh_keys", [])
    if keys:
        return int(keys[0]["id"])
    try:
        created = request(api_key, "POST", "/ssh_keys", {"name": operator_key_name(), "public_key": pubkey})
        return int(created["ssh_key"]["id"])
    except HetznerError as exc:
        if exc.status == 409:
            keys = request(api_key, "GET", f"/ssh_keys?{query}").get("ssh_keys", [])
            if keys:
                return int(keys[0]["id"])
        raise


def normalize_arch(value: str) -> str:
    v = value.lower()
    if v in {"amd", "x86", "x86_64"}:
        return "x86"
    if v in {"arm", "aarch64"}:
        return "arm"
    raise ValueError(f"unsupported arch: {value}")


def server_catalog(api_key: str, location: str) -> list[ServerType]:
    types = request(api_key, "GET", "/server_types").get("server_types", [])
    datacenters = request(api_key, "GET", "/datacenters").get("datacenters", [])
    available_ids: set[int] = set()
    for dc in datacenters:
        loc = ((dc.get("location") or {}).get("name") or "").lower()
        if loc == location.lower():
            st = dc.get("server_types") or {}
            available_ids.update(int(x) for x in st.get("available", []))
    out: list[ServerType] = []
    for item in types:
        type_id = int(item["id"])
        if available_ids and type_id not in available_ids:
            continue
        price = None
        for p in item.get("prices", []):
            if p.get("location") == location:
                price = float((p.get("price_monthly") or {}).get("gross"))
                break
        if price is None:
            continue
        out.append(
            ServerType(
                name=item["name"],
                memory=int(item["memory"]),
                disk=int(item["disk"]),
                cores=int(item["cores"]),
                arch=normalize_arch(item["architecture"]),
                price_monthly=price,
                location=location,
                type_id=type_id,
            )
        )
    return out


def choose_server_type(
    catalog: list[ServerType],
    *,
    min_ram: int,
    min_disk: int,
    arch: str,
    max_price_monthly: float | None,
) -> ServerType | None:
    normalized = normalize_arch(arch)
    matches = [
        st
        for st in catalog
        if st.memory >= min_ram
        and st.disk >= min_disk
        and st.arch == normalized
        and (max_price_monthly is None or st.price_monthly <= max_price_monthly)
    ]
    return min(matches, key=lambda st: (st.price_monthly, st.memory, st.disk, st.cores), default=None)


def render_cloud_init(hostname: str, pubkey: str) -> str:
    return f"""#!/bin/bash
set -euxo pipefail

hostnamectl set-hostname {hostname}
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl git jq rsync sqlite3 unzip python3 python3-venv python3-pip openjdk-21-jre-headless ufw

useradd -m -s /bin/bash bot || true
mkdir -p /home/bot/.ssh
cat > /home/bot/.ssh/authorized_keys <<'EOF'
{pubkey}
EOF
chown -R bot:bot /home/bot/.ssh
chmod 700 /home/bot/.ssh
chmod 600 /home/bot/.ssh/authorized_keys
echo 'bot ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/bot
chmod 440 /etc/sudoers.d/bot

sed -i 's/^#\\?PasswordAuthentication .*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\\?PermitRootLogin .*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
systemctl reload ssh || systemctl reload sshd || true

ufw allow OpenSSH
ufw --force enable

mkdir -p /opt/stevetrading/releases /opt/stevetrading/shared /var/log/stevetrading
chown -R bot:bot /opt/stevetrading /var/log/stevetrading
"""


def redact_payload(payload: dict[str, Any]) -> dict[str, Any]:
    copy = dict(payload)
    user_data = str(copy.get("user_data", ""))
    user_data = re.sub(r"(?m)^ssh-[^\n]+$", "ssh-<REDACTED-OPERATOR-PUBKEY>", user_data)
    if len(user_data) > 900:
        user_data = user_data[:900] + f"... <truncated {len(user_data) - 900} chars>"
    copy["user_data"] = user_data
    copy["ssh_keys"] = ["<operator-key-id>"]
    return copy


def leases_read(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    return json.loads(path.read_text())


def leases_write(path: Path, leases: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(leases, indent=2, sort_keys=True) + "\n")
    tmp.replace(path)


def add_lease(path: Path, server: dict[str, Any], selection: ServerType) -> None:
    leases = leases_read(path)
    sid = str(server["id"])
    leases[sid] = {
        "id": server["id"],
        "name": server["name"],
        "type": selection.name,
        "location": selection.location,
        "price_monthly_eur": selection.price_monthly,
        "ipv4": (((server.get("public_net") or {}).get("ipv4") or {}).get("ip")),
        "primary_ip_id": (((server.get("public_net") or {}).get("ipv4") or {}).get("id")),
        "status": server.get("status"),
        "created_at": server.get("created"),
    }
    leases_write(path, leases)


def remove_lease(path: Path, server_id: int) -> None:
    leases = leases_read(path)
    leases.pop(str(server_id), None)
    leases_write(path, leases)


def wait_running(api_key: str, server_id: int, timeout_seconds: int = 180) -> dict[str, Any]:
    deadline = time.time() + timeout_seconds
    last: dict[str, Any] = {}
    while time.time() < deadline:
        last = request(api_key, "GET", f"/servers/{server_id}").get("server", {})
        if last.get("status") in {"running", "error"}:
            return last
        time.sleep(3)
    return last


def wait_ssh(host: str, timeout_seconds: int = 300) -> bool:
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        probe = subprocess.run(
            [
                "ssh",
                "-o",
                "BatchMode=yes",
                "-o",
                "StrictHostKeyChecking=accept-new",
                "-o",
                "ConnectTimeout=10",
                f"bot@{host}",
                "true",
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        if probe.returncode == 0:
            return True
        try:
            with socket.create_connection((host, 22), timeout=3):
                # SSH is listening but cloud-init may not have created bot or
                # authorized_keys yet. Keep polling for authenticated access.
                pass
        except OSError:
            pass
        time.sleep(5)
    return False


def build_payload(args: argparse.Namespace, selection: ServerType, pubkey: str, ssh_key_id: int) -> dict[str, Any]:
    return {
        "name": args.hostname,
        "server_type": selection.name,
        "location": args.location,
        "image": args.image,
        "ssh_keys": [ssh_key_id],
        "user_data": render_cloud_init(args.hostname, pubkey),
        "public_net": {"enable_ipv4": True, "enable_ipv6": True},
        "labels": {"project": "stevetrading", "role": "live-paper-trading"},
        "start_after_create": True,
    }


def do_provision(args: argparse.Namespace) -> int:
    api_key = get_secret("HCLOUD_TOKEN", env_file=args.env_file, alternatives=("HETZNER_API_KEY",))
    pubkey = local_pubkey(args.pubkey)
    catalog = server_catalog(api_key, args.location)
    selection = choose_server_type(
        catalog,
        min_ram=args.min_ram,
        min_disk=args.min_disk,
        arch=args.arch,
        max_price_monthly=args.max_price_monthly,
    )
    if not selection:
        print("no Hetzner server type matches requested constraints", file=sys.stderr)
        return 4
    monthly = selection.price_monthly + 0.50
    print(
        f"selected {selection.name} {selection.location}: {selection.cores} vCPU, "
        f"{selection.memory}GB RAM, {selection.disk}GB disk, €{monthly:.2f}/mo incl IPv4"
    )
    ssh_key_id = 0 if args.dry_run else register_ssh_key(api_key, pubkey)
    payload = build_payload(args, selection, pubkey, ssh_key_id)
    if args.dry_run:
        print("dry-run: would POST /servers with body:")
        print(json.dumps(redact_payload(payload), indent=2, sort_keys=True))
        return 0
    existing = request(api_key, "GET", f"/servers?{urllib.parse.urlencode({'name': args.hostname})}").get("servers", [])
    if existing:
        raise SystemExit(f"error: Hetzner already has a server named {args.hostname}")
    created = request(api_key, "POST", "/servers", payload)
    server = created["server"]
    server_id = int(server["id"])
    print(f"created server id={server_id}; waiting for running")
    running = wait_running(api_key, server_id)
    add_lease(args.leases, running or server, selection)
    if running.get("status") == "error":
        print(f"server entered error state; lease recorded in {args.leases}", file=sys.stderr)
        return 4
    ip = (((running.get("public_net") or {}).get("ipv4") or {}).get("ip"))
    if ip:
        print(f"public ipv4: {ip}; waiting for ssh")
        if wait_ssh(ip):
            print(f"ready: ssh bot@{ip}")
            return 0
        print(f"server is running but SSH did not become reachable; inspect cloud-init. lease={args.leases}", file=sys.stderr)
        return 4
    print(f"server is running but no IPv4 found; lease={args.leases}", file=sys.stderr)
    return 4


def do_list(args: argparse.Namespace) -> int:
    api_key = get_secret("HCLOUD_TOKEN", env_file=args.env_file, alternatives=("HETZNER_API_KEY",))
    leases = leases_read(args.leases)
    servers = request(api_key, "GET", "/servers").get("servers", [])
    tracked = {str(k) for k in leases.keys()}
    print("NAME                         ID          STATUS       TYPE      IPV4")
    for s in servers:
        labels = s.get("labels") or {}
        if labels.get("project") != "stevetrading" and str(s.get("id")) not in tracked:
            continue
        ip = (((s.get("public_net") or {}).get("ipv4") or {}).get("ip")) or "-"
        stype = (s.get("server_type") or {}).get("name") or "-"
        print(f"{s.get('name','-'):<28} {s.get('id','-'):<11} {s.get('status','-'):<12} {stype:<9} {ip}")
    return 0


def do_destroy(args: argparse.Namespace) -> int:
    api_key = get_secret("HCLOUD_TOKEN", env_file=args.env_file, alternatives=("HETZNER_API_KEY",))
    leases = leases_read(args.leases)
    target = None
    for sid, lease in leases.items():
        if args.hostname_or_id in {sid, str(lease.get("name"))}:
            target = int(sid)
            break
    if target is None and args.hostname_or_id.isdigit():
        target = int(args.hostname_or_id)
    if target is None:
        servers = request(api_key, "GET", f"/servers?{urllib.parse.urlencode({'name': args.hostname_or_id})}").get("servers", [])
        if servers:
            target = int(servers[0]["id"])
    if target is None:
        print(f"not found: {args.hostname_or_id}")
        return 0
    request(api_key, "DELETE", f"/servers/{target}")
    remove_lease(args.leases, target)
    print(f"destroyed server id={target}; lease removed")
    return 0


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="SteveTrading Hetzner VPS operations")
    p.add_argument("--env-file", type=Path, default=None, help="optional env file containing HCLOUD_TOKEN")
    p.add_argument("--leases", type=Path, default=DEFAULT_LEASES)
    sub = p.add_subparsers(dest="command", required=True)

    provision = sub.add_parser("provision", help="create a non-Tailscale SteveTrading VPS")
    provision.add_argument("hostname")
    provision.add_argument("--location", default="ash", help="Hetzner location, e.g. ash, hil, nbg1")
    provision.add_argument("--min-ram", type=int, default=4)
    provision.add_argument("--min-disk", type=int, default=40)
    provision.add_argument("--arch", default="amd", choices=["amd", "arm", "x86", "x86_64", "aarch64"])
    provision.add_argument("--image", default="ubuntu-24.04")
    provision.add_argument("--max-price-monthly", type=float, default=25.0)
    provision.add_argument("--pubkey", type=Path, default=None)
    provision.add_argument("--dry-run", action="store_true")
    provision.set_defaults(func=do_provision)

    list_cmd = sub.add_parser("list", help="list SteveTrading Hetzner servers")
    list_cmd.set_defaults(func=do_list)

    destroy = sub.add_parser("destroy", help="destroy by hostname or server id")
    destroy.add_argument("hostname_or_id")
    destroy.set_defaults(func=do_destroy)
    return p


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        return int(args.func(args))
    except HetznerError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 4


if __name__ == "__main__":
    raise SystemExit(main())
