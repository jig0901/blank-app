# Pulse

Native iOS infrastructure command center for the Belani home server ecosystem.

## MVP

- Ubuntu CPU, memory, disk, load and uptime telemetry
- Docker container status, health and restart counts
- Configurable HTTP endpoint checks with latency
- Aggregated system health score
- Native SwiftUI dashboard with pull-to-refresh
- Token-authenticated API

## Repository layout

- `agent/` — Dockerized FastAPI monitoring agent
- `ios/` — Native SwiftUI application, generated with XcodeGen

## Run the agent

```bash
cd agent
cp .env.example .env
cp config.example.yml config.yml
# Set a strong PULSE_API_TOKEN in .env
docker compose up -d --build
curl -H "Authorization: Bearer YOUR_TOKEN" http://localhost:8090/api/v1/overview
```

The container mounts the Docker socket read-only. Pulse exposes only normalized monitoring data; it does not provide arbitrary Docker command execution.

## Generate the iOS project

Install XcodeGen, then:

```bash
cd ios
xcodegen generate
open Pulse.xcodeproj
```

In the app's Settings tab, enter the Pulse Agent base URL and API token.

## Initial deployment target

The project targets iOS 17+ and uses SwiftUI, Swift Charts and async/await.
