#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Collect read-only, redacted AutoDL GPU metrics over SSH for WidgetKit."""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


EXTENSION_BUNDLE_ID = "com.example.autodl-native-widget.widget"
RUNTIME_DIR = Path.home() / "Library" / "AutoDLNativeWidget"
DEFAULT_CONFIG = RUNTIME_DIR / "config.json"
SAFE_ID = re.compile(r"^[a-z0-9][a-z0-9-]{0,31}$")
SAFE_TARGET = re.compile(r"^[A-Za-z0-9._@:%+\-\[\]]+$")
SENSITIVE_KEYS = {"password", "passphrase", "token", "cookie", "secret", "private_key"}


REMOTE_PROBE = r'''python3 - <<'PY'
import json
import os
import subprocess

def run(argv):
    try:
        return subprocess.run(argv, text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=False)
    except OSError:
        return subprocess.CompletedProcess(argv, 127, "", "")

def number(value, integer=False):
    try:
        value = value.strip()
        if value in {"", "N/A", "[Not Supported]", "Not Supported"}:
            return None
        return int(float(value)) if integer else round(float(value), 1)
    except (TypeError, ValueError):
        return None

payload = {"protocol": 1, "mode": "cpu_only", "gpus": [], "storage": [], "system": {}}
query = "index,name,uuid,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw,power.limit"
gpu = run(["nvidia-smi", f"--query-gpu={query}", "--format=csv,noheader,nounits"])
process_counts = {}
if gpu.returncode == 0:
    processes = run(["nvidia-smi", "--query-compute-apps=gpu_uuid", "--format=csv,noheader,nounits"])
    if processes.returncode == 0:
        for uuid in processes.stdout.splitlines():
            uuid = uuid.strip()
            if uuid:
                process_counts[uuid] = process_counts.get(uuid, 0) + 1
    for raw in gpu.stdout.splitlines():
        fields = [item.strip() for item in raw.split(",")]
        if len(fields) < 9:
            continue
        index, name, uuid, util, used, total, temp, power, limit = fields[:9]
        payload["gpus"].append({
            "index": number(index, True),
            "name": name[:64],
            "uuid": uuid,
            "utilization_pct": number(util, True),
            "memory_used_mib": number(used, True),
            "memory_total_mib": number(total, True),
            "temperature_c": number(temp, True),
            "power_w": number(power),
            "power_limit_w": number(limit),
            "process_count": process_counts.get(uuid, 0),
        })
    payload["mode"] = "gpu"

for kind, path in (("local", "/root/autodl-tmp"), ("persistent", "/root/autodl-fs")):
    try:
        values = os.statvfs(path)
    except OSError:
        continue
    size = values.f_blocks * values.f_frsize
    available = values.f_bavail * values.f_frsize
    free = values.f_bfree * values.f_frsize
    used = max(0, size - free)
    payload["storage"].append({
        "kind": kind,
        "size_bytes": size,
        "used_bytes": used,
        "available_bytes": available,
        "used_pct": round((used / size) * 100, 1) if size else 0,
    })

try:
    with open("/proc/uptime", "r", encoding="utf-8") as handle:
        payload["uptime_seconds"] = int(float(handle.read().split()[0]))
except (OSError, ValueError, IndexError):
    pass

try:
    values = {}
    with open("/proc/meminfo", "r", encoding="utf-8") as handle:
        for line in handle:
            key, raw = line.split(":", 1)
            values[key] = int(raw.strip().split()[0])
    total = values.get("MemTotal", 0)
    available = values.get("MemAvailable", 0)
    payload["system"]["memory_total_mib"] = total // 1024
    payload["system"]["memory_used_mib"] = max(0, total - available) // 1024
except (OSError, ValueError, IndexError):
    pass

try:
    payload["system"]["load_1m"] = round(os.getloadavg()[0], 2)
    payload["system"]["cpu_count"] = os.cpu_count()
except OSError:
    pass

print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
PY'''


class ConfigError(ValueError):
    pass


def default_snapshot_path() -> Path:
    return (
        Path.home()
        / "Library"
        / "Containers"
        / EXTENSION_BUNDLE_ID
        / "Data"
        / "Library"
        / "Application Support"
        / "AutoDLNativeWidget"
        / "snapshot.json"
    )


def iso_now() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def contains_sensitive_key(value: Any) -> bool:
    if isinstance(value, dict):
        for key, item in value.items():
            if str(key).lower() in SENSITIVE_KEYS or contains_sensitive_key(item):
                return True
    if isinstance(value, list):
        return any(contains_sensitive_key(item) for item in value)
    return False


def load_config(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ConfigError("config_invalid") from error
    if contains_sensitive_key(payload):
        raise ConfigError("config_contains_secret")
    rows = payload.get("instances") if isinstance(payload, dict) else None
    if not isinstance(rows, list):
        raise ConfigError("instances_missing")

    instances: list[dict[str, Any]] = []
    seen: set[str] = set()
    for row in rows:
        if not isinstance(row, dict):
            raise ConfigError("instance_invalid")
        instance_id = str(row.get("id") or "").strip().lower()
        target = str(row.get("ssh_target") or "").strip()
        if not SAFE_ID.fullmatch(instance_id) or instance_id in seen:
            raise ConfigError("instance_id_invalid")
        if not SAFE_TARGET.fullmatch(target):
            raise ConfigError(f"ssh_target_invalid:{instance_id}")
        seen.add(instance_id)
        port = row.get("port")
        try:
            parsed_port = int(port) if port is not None else None
        except (TypeError, ValueError) as error:
            raise ConfigError(f"port_invalid:{instance_id}") from error
        if parsed_port is not None and not (1 <= parsed_port <= 65535):
            raise ConfigError(f"port_invalid:{instance_id}")
        timeout = max(3, min(60, int(row.get("connect_timeout") or 10)))
        identity = row.get("identity_file")
        instances.append(
            {
                "id": instance_id,
                "label": str(row.get("label") or instance_id)[:24],
                "ssh_target": target,
                "port": parsed_port,
                "identity_file": str(Path(str(identity)).expanduser()) if identity else None,
                "connect_timeout": timeout,
            }
        )
    return instances


def config_permissions_warning(path: Path) -> bool:
    if not path.exists():
        return False
    return bool(stat.S_IMODE(path.stat().st_mode) & 0o077)


def classify_ssh_error(stderr: str, timed_out: bool = False) -> str:
    text = stderr.lower()
    if timed_out or "timed out" in text or "operation timeout" in text:
        return "timeout"
    if "permission denied" in text or "authentication failed" in text:
        return "auth_failed"
    if "host key verification failed" in text or "remote host identification has changed" in text:
        return "host_key"
    if "could not resolve hostname" in text or "name or service not known" in text:
        return "dns"
    if "connection refused" in text:
        return "refused"
    if "no route to host" in text or "network is unreachable" in text:
        return "network"
    return "ssh_failed"


def integer(value: Any) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def decimal(value: Any) -> float | None:
    try:
        return round(float(value), 1)
    except (TypeError, ValueError):
        return None


def run_instance(instance: dict[str, Any], ssh_path: str) -> dict[str, Any]:
    command = [
        ssh_path,
        "-T",
        "-o", "BatchMode=yes",
        "-o", f"ConnectTimeout={instance['connect_timeout']}",
        "-o", "ServerAliveInterval=5",
        "-o", "ServerAliveCountMax=1",
        "-o", "LogLevel=ERROR",
    ]
    if instance.get("port"):
        command.extend(["-p", str(instance["port"])])
    if instance.get("identity_file"):
        command.extend(["-i", instance["identity_file"], "-o", "IdentitiesOnly=yes"])
    command.extend([instance["ssh_target"], REMOTE_PROBE])

    started = time.monotonic()
    try:
        proc = subprocess.run(
            command,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=instance["connect_timeout"] + 20,
            check=False,
        )
    except subprocess.TimeoutExpired as error:
        return {
            "id": instance["id"],
            "label": instance["label"],
            "status": "offline",
            "mode": "unknown",
            "error_code": classify_ssh_error(str(error), timed_out=True),
            "gpus": [],
            "storage": [],
        }
    except OSError:
        return {
            "id": instance["id"],
            "label": instance["label"],
            "status": "offline",
            "mode": "unknown",
            "error_code": "ssh_unavailable",
            "gpus": [],
            "storage": [],
        }

    latency_ms = int((time.monotonic() - started) * 1_000)
    if proc.returncode != 0:
        return {
            "id": instance["id"],
            "label": instance["label"],
            "status": "offline",
            "mode": "unknown",
            "latency_ms": latency_ms,
            "error_code": classify_ssh_error(proc.stderr),
            "gpus": [],
            "storage": [],
        }
    try:
        remote = json.loads(proc.stdout.strip().splitlines()[-1])
    except (IndexError, json.JSONDecodeError):
        return {
            "id": instance["id"],
            "label": instance["label"],
            "status": "error",
            "mode": "unknown",
            "latency_ms": latency_ms,
            "error_code": "probe_invalid",
            "gpus": [],
            "storage": [],
        }

    gpus = []
    for position, gpu in enumerate(remote.get("gpus") or []):
        if not isinstance(gpu, dict):
            continue
        utilization = integer(gpu.get("utilization_pct"))
        process_count = integer(gpu.get("process_count"))
        gpus.append(
            {
                "index": integer(gpu.get("index", position)),
                "name": str(gpu.get("name") or "GPU")[:64],
                "utilization_pct": utilization,
                "memory_used_mib": integer(gpu.get("memory_used_mib")),
                "memory_total_mib": integer(gpu.get("memory_total_mib")),
                "temperature_c": integer(gpu.get("temperature_c")),
                "power_w": decimal(gpu.get("power_w")),
                "power_limit_w": decimal(gpu.get("power_limit_w")),
                "process_count": process_count,
                "busy": process_count > 0 or utilization >= 5,
            }
        )

    storage = []
    for disk in remote.get("storage") or []:
        if not isinstance(disk, dict) or disk.get("kind") not in {"local", "persistent"}:
            continue
        storage.append(
            {
                "kind": disk["kind"],
                "size_bytes": integer(disk.get("size_bytes")),
                "used_bytes": integer(disk.get("used_bytes")),
                "available_bytes": integer(disk.get("available_bytes")),
                "used_pct": decimal(disk.get("used_pct")) or 0,
            }
        )

    system = remote.get("system") if isinstance(remote.get("system"), dict) else {}
    return {
        "id": instance["id"],
        "label": instance["label"],
        "status": "online",
        "mode": "gpu" if gpus else "cpu_only",
        "latency_ms": latency_ms,
        "uptime_seconds": integer(remote.get("uptime_seconds")),
        "gpus": gpus,
        "storage": storage,
        "system": {
            "memory_used_mib": integer(system.get("memory_used_mib")),
            "memory_total_mib": integer(system.get("memory_total_mib")),
            "load_1m": decimal(system.get("load_1m")),
            "cpu_count": integer(system.get("cpu_count")),
        },
    }


def summarize(instances: list[dict[str, Any]]) -> dict[str, Any]:
    gpus = [gpu for instance in instances for gpu in instance.get("gpus") or []]
    temperatures = [integer(gpu.get("temperature_c")) for gpu in gpus if gpu.get("temperature_c") is not None]
    return {
        "total_instances": len(instances),
        "online_instances": sum(instance.get("status") == "online" for instance in instances),
        "gpu_instances": sum(instance.get("mode") == "gpu" for instance in instances),
        "total_gpus": len(gpus),
        "busy_gpus": sum(bool(gpu.get("busy")) for gpu in gpus),
        "average_utilization_pct": round(sum(integer(gpu.get("utilization_pct")) for gpu in gpus) / len(gpus)) if gpus else 0,
        "memory_used_mib": sum(integer(gpu.get("memory_used_mib")) for gpu in gpus),
        "memory_total_mib": sum(integer(gpu.get("memory_total_mib")) for gpu in gpus),
        "active_processes": sum(integer(gpu.get("process_count")) for gpu in gpus),
        "max_temperature_c": max(temperatures) if temperatures else 0,
    }


def atomic_write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.chmod(temporary, 0o600)
    temporary.replace(path)


def stable_signature(snapshot: dict[str, Any]) -> str:
    stable = {"instances": snapshot.get("instances"), "summary": snapshot.get("summary"), "error": snapshot.get("error")}
    for instance in stable.get("instances") or []:
        instance.pop("latency_ms", None)
        instance.pop("uptime_seconds", None)
    raw = json.dumps(stable, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def reload_widget() -> None:
    subprocess.run(
        ["open", "-g", "autodl-widget://reload"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )


def write_once(config_path: Path, snapshot_path: Path, instance_filter: str | None) -> dict[str, Any]:
    error = None
    try:
        configured = load_config(config_path)
    except ConfigError as config_error:
        configured = []
        error = str(config_error)
    if instance_filter:
        configured = [row for row in configured if row["id"] == instance_filter]
        if not configured and error is None:
            error = "instance_not_found"
    if not configured and error is None:
        error = "not_configured"

    ssh_path = shutil.which("ssh") or "/usr/bin/ssh"
    instances = [run_instance(instance, ssh_path) for instance in configured]
    snapshot = {
        "version": 1,
        "written_at": iso_now(),
        "instances": instances,
        "summary": summarize(instances),
        "error": error,
    }
    atomic_write_json(snapshot_path, snapshot)
    return snapshot


def locked_write_once(config_path: Path, snapshot_path: Path, instance_filter: str | None) -> dict[str, Any]:
    lock_path = snapshot_path.with_suffix(snapshot_path.suffix + ".lock")
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    with lock_path.open("a+", encoding="utf-8") as handle:
        os.chmod(lock_path, 0o600)
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
        return write_once(config_path, snapshot_path, instance_filter)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", nargs="?", choices=["watch", "once", "check-config", "show"], default="watch")
    parser.add_argument("--config", type=Path, default=Path(os.getenv("AUTODL_WIDGET_CONFIG", DEFAULT_CONFIG)))
    parser.add_argument("--snapshot-path", type=Path, default=Path(os.getenv("AUTODL_WIDGET_SNAPSHOT", default_snapshot_path())))
    parser.add_argument("--instance")
    parser.add_argument("--interval", type=int, default=60)
    parser.add_argument("--active-interval", type=int, default=30)
    parser.add_argument("--max-interval", type=int, default=300)
    parser.add_argument("--no-reload", action="store_true")
    args = parser.parse_args()
    args.interval = max(15, args.interval)
    args.active_interval = max(15, min(args.interval, args.active_interval))
    args.max_interval = max(args.interval, args.max_interval)
    return args


def main() -> int:
    args = parse_args()
    if args.command == "check-config":
        try:
            instances = load_config(args.config)
        except ConfigError as error:
            print(json.dumps({"ok": False, "error": str(error)}, ensure_ascii=False))
            return 2
        print(json.dumps({"ok": bool(instances), "instances": [row["id"] for row in instances], "permissions_warning": config_permissions_warning(args.config)}, ensure_ascii=False))
        return 0 if instances else 2
    if args.command == "show":
        if not args.snapshot_path.exists():
            print(json.dumps({"error": "snapshot_missing"}, ensure_ascii=False))
            return 2
        print(args.snapshot_path.read_text(encoding="utf-8"), end="")
        return 0

    previous: str | None = None
    stable_refreshes = 0
    while True:
        started = time.monotonic()
        snapshot = locked_write_once(args.config, args.snapshot_path, args.instance)
        signature = stable_signature(json.loads(json.dumps(snapshot)))
        changed = signature != previous
        previous = signature
        if changed and not args.no_reload:
            reload_widget()
        summary = snapshot["summary"]
        active = summary["busy_gpus"] > 0
        healthy = summary["online_instances"] == summary["total_instances"] and not snapshot.get("error")
        if active:
            interval = args.active_interval
            stable_refreshes = 0
        elif not healthy or changed:
            interval = args.interval
            stable_refreshes = 0
        else:
            stable_refreshes += 1
            interval = min(args.max_interval, args.interval * (stable_refreshes + 1))
        print(
            f"[autodl-widget] online={summary['online_instances']}/{summary['total_instances']} "
            f"gpus={summary['busy_gpus']}/{summary['total_gpus']} changed={changed} next={interval}s "
            f"error={snapshot.get('error') or '-'}",
            flush=True,
        )
        if args.command == "once":
            return 0
        time.sleep(max(1, interval - (time.monotonic() - started)))


if __name__ == "__main__":
    raise SystemExit(main())
