from __future__ import annotations

import asyncio
import os
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import docker
import httpx
import psutil
import yaml
from fastapi import Depends, FastAPI, Header, HTTPException
from pydantic import BaseModel

app = FastAPI(title="Pulse Agent", version="0.1.0")
STARTED_AT = time.time()
CONFIG_PATH = Path(os.getenv("PULSE_CONFIG", "/app/config.yml"))
API_TOKEN = os.getenv("PULSE_API_TOKEN", "change-me")


class EndpointResult(BaseModel):
    id: str
    name: str
    url: str
    status: str
    status_code: int | None = None
    latency_ms: float | None = None
    checked_at: datetime
    detail: str | None = None


def authorize(authorization: str | None = Header(default=None)) -> None:
    if authorization != f"Bearer {API_TOKEN}":
        raise HTTPException(status_code=401, detail="Invalid Pulse API token")


def load_config() -> dict[str, Any]:
    if not CONFIG_PATH.exists():
        return {"endpoints": []}
    with CONFIG_PATH.open("r", encoding="utf-8") as handle:
        return yaml.safe_load(handle) or {"endpoints": []}


def system_metrics() -> dict[str, Any]:
    disk = psutil.disk_usage("/")
    memory = psutil.virtual_memory()
    load = psutil.getloadavg()
    return {
        "hostname": os.uname().nodename,
        "uptime_seconds": int(time.time() - psutil.boot_time()),
        "cpu_percent": psutil.cpu_percent(interval=0.15),
        "memory_percent": memory.percent,
        "memory_used_bytes": memory.used,
        "memory_total_bytes": memory.total,
        "disk_percent": disk.percent,
        "disk_used_bytes": disk.used,
        "disk_total_bytes": disk.total,
        "load_average": {"one": load[0], "five": load[1], "fifteen": load[2]},
    }


def docker_containers() -> list[dict[str, Any]]:
    try:
        client = docker.from_env()
        containers = []
        for container in client.containers.list(all=True):
            container.reload()
            state = container.attrs.get("State", {})
            health = state.get("Health", {}).get("Status")
            containers.append({
                "id": container.short_id,
                "name": container.name,
                "image": container.image.tags[0] if container.image.tags else container.image.short_id,
                "status": container.status,
                "health": health,
                "restart_count": int(container.attrs.get("RestartCount", 0)),
                "started_at": state.get("StartedAt"),
            })
        return sorted(containers, key=lambda item: item["name"].lower())
    except Exception as exc:
        return [{"id": "docker-error", "name": "Docker", "status": "unknown", "detail": str(exc)}]


async def check_endpoint(client: httpx.AsyncClient, endpoint: dict[str, Any]) -> EndpointResult:
    started = time.perf_counter()
    checked_at = datetime.now(timezone.utc)
    expected_status = int(endpoint.get("expected_status", 200))
    try:
        response = await client.get(endpoint["url"], follow_redirects=True)
        latency_ms = round((time.perf_counter() - started) * 1000, 1)
        status = "healthy" if response.status_code == expected_status else "degraded"
        expected_text = endpoint.get("expected_text")
        if expected_text and expected_text not in response.text:
            status = "degraded"
        return EndpointResult(
            id=str(endpoint.get("id", endpoint["name"])),
            name=endpoint["name"],
            url=endpoint["url"],
            status=status,
            status_code=response.status_code,
            latency_ms=latency_ms,
            checked_at=checked_at,
            detail=None if status == "healthy" else "Unexpected response",
        )
    except Exception as exc:
        return EndpointResult(
            id=str(endpoint.get("id", endpoint.get("name", "endpoint"))),
            name=endpoint.get("name", endpoint.get("url", "Endpoint")),
            url=endpoint.get("url", ""),
            status="offline",
            latency_ms=round((time.perf_counter() - started) * 1000, 1),
            checked_at=checked_at,
            detail=str(exc),
        )


async def endpoint_results() -> list[EndpointResult]:
    endpoints = load_config().get("endpoints", [])
    timeout = httpx.Timeout(8.0)
    async with httpx.AsyncClient(timeout=timeout) as client:
        return await asyncio.gather(*(check_endpoint(client, item) for item in endpoints))


def health_score(system: dict[str, Any], containers: list[dict[str, Any]], endpoints: list[EndpointResult]) -> int:
    score = 100
    score -= max(0, int(system["cpu_percent"] - 80) // 2)
    score -= max(0, int(system["memory_percent"] - 80) // 2)
    score -= max(0, int(system["disk_percent"] - 80))
    score -= sum(8 for item in containers if item.get("status") not in {"running", "exited"})
    score -= sum(15 if item.status == "offline" else 6 for item in endpoints if item.status != "healthy")
    return max(0, min(100, score))


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/api/v1/overview", dependencies=[Depends(authorize)])
async def overview() -> dict[str, Any]:
    system = system_metrics()
    containers = docker_containers()
    endpoints = await endpoint_results()
    return {
        "generated_at": datetime.now(timezone.utc),
        "agent_uptime_seconds": int(time.time() - STARTED_AT),
        "score": health_score(system, containers, endpoints),
        "system": system,
        "containers": containers,
        "endpoints": [item.model_dump(mode="json") for item in endpoints],
    }
