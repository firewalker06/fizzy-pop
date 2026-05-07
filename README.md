# Fizzy Pop

<div align="center"><img src="fizzypop_logo.png" alt="Fizzy Pop Logo"></div>

A polling daemon that watches [Fizzy](https://app.fizzy.do) for unread notifications and forwards them to an [OpenClaw](https://docs.openclaw.ai) or [Hermes Agent](https://hermes-agent.nousresearch.com) webhook.

[OpenClaw's heartbeat is costly](https://docs.openclaw.ai/gateway/heartbeat#cost-awareness) for simple notification checking, which is why this separate polling service exists. We can also added more instructions and references in the webhook payload for better result.

## Table of Contents

- [Setup](#setup)
- [Usage](#usage)
  - [Single Agent Mode](#single-agent-mode)
  - [Multi-Agent Mode](#multi-agent-mode)
  - [Options](#options)
  - [Examples](#examples)
- [Docker](#docker)
  - [Build](#build)
  - [Run](#run)
- [Kamal Deployment](#kamal-deployment)
- [OpenClaw Webhook Setup](#openclaw-webhook-setup)
- [Hermes Agent Webhook Setup](#hermes-agent-webhook-setup)
- [How It Works](#how-it-works)

## Setup

```bash
bundle install
```

## Usage

```bash
ruby bin/fizzy-pop [--config FILE | --token TOKEN] [options]
```

### Single Agent Mode

For a single agent, use the `--token` flag:

```bash
ruby bin/fizzy-pop --url https://app.fizzy.do --token abc123 --webhook-url http://localhost:18789 --webhook-token secret
```

### Multi-Agent Mode

For multiple agents, use a YAML config file:

```bash
ruby bin/fizzy-pop --config config.yml
```

Create a `config.yml` (see `config.example.yml`):

```yaml
url: https://app.fizzy.do
webhook_url: http://localhost:18789
webhook_token: your-webhook-token
adapter: openclaw

interval:
  polling: 10
  webhook: 3
  agent_poll: 0.5

agents:
  - name: optimus
    token: optimus-fizzy-token
  - name: wheeljack
    token: wheeljack-fizzy-token
  - name: prowl
    token: prowl-fizzy-token
```

Each agent's notifications are polled independently. The selected adapter maps the universal webhook settings to the target webhook format.

### Options

| Flag | Required | Description | Default |
|------|----------|-------------|---------|
| `--url URL` | Yes* | Fizzy base URL (e.g. `https://app.fizzy.do`) | — |
| `--token TOKEN` | Yes* | Fizzy personal access token (single agent mode) | — |
| `--config FILE` | Yes* | YAML config file for multi-agent mode | — |
| `--adapter ADAPTER` | No | Webhook adapter: `openclaw` or `hermes` | `openclaw` |
| `--webhook-url URL` | No | Webhook base URL | — |
| `--webhook-token TOKEN` | No | Webhook bearer token or HMAC secret | — |
| `--webhook-route ROUTE` | No | Webhook route name for adapters that use routes | — |
| `--polling SECONDS` | No | Polling interval in seconds | `10` |
| `--dry-run` | No | Print webhook payload without sending | — |
| `--verbose` | No | Print full request/response headers and body (redacts Authorization) | — |

*Either `--token` or `--config` is required. When using `--config`, the `url` can be specified in the config file.

Both `--webhook-url` and `--webhook-token` are required unless `--dry-run` is used.

### Examples

Dry run (single agent, no webhook):

```bash
ruby bin/fizzy-pop --url https://app.fizzy.do --token abc123 --dry-run
```

Single agent with webhook forwarding:

```bash
ruby bin/fizzy-pop \
  --url https://app.fizzy.do \
  --token abc123 \
  --webhook-url http://localhost:18789 \
  --webhook-token my-secret
```

Multi-agent with config file:

```bash
ruby bin/fizzy-pop --config config.yml
```

Multi-agent dry run:

```bash
ruby bin/fizzy-pop --config config.yml --dry-run --verbose
```

Hermes Agent delivery:

```bash
ruby bin/fizzy-pop \
  --url https://app.fizzy.do \
  --token abc123 \
  --adapter hermes \
  --webhook-url http://localhost:8644 \
  --webhook-route fizzy \
  --webhook-token my-route-secret
```

Run as background daemon:

```bash
nohup ruby bin/fizzy-pop --config config.yml > fizzy-pop.log 2>&1 &
```

## Docker

### Build

```bash
docker build -t fizzy-pop .
```

### Run

Single agent mode:

```bash
docker run --rm fizzy-pop \
  --url https://app.fizzy.do \
  --token abc123 \
  --webhook-url http://host.docker.internal:18789 \
  --webhook-token my-secret
```

Multi-agent mode (mount config file):

```bash
docker run --rm \
  -v $(pwd)/config.yml:/app/config.yml:ro \
  fizzy-pop \
  --config /app/config.yml
```

If the OpenClaw gateway is running on the host machine, add `--add-host` so the container can reach it:

```bash
docker run --rm \
  --add-host host.docker.internal:host-gateway \
  -v $(pwd)/config.yml:/app/config.yml:ro \
  fizzy-pop \
  --config /app/config.yml \
  --verbose
```

## Kamal Deployment

Fizzy Pop includes a [Kamal](https://kamal-deploy.org) configuration for deploying to a remote server.

### Environment

Create a `.env` file in the project root:

```
HOSTS=your-server-ip
URL=https://app.fizzy.do
TOKEN=your-fizzy-token
ADAPTER=openclaw
WEBHOOK_URL=http://host.docker.internal:18789
WEBHOOK_TOKEN=your-webhook-token
WEBHOOK_ROUTE=fizzy
```

For multi-agent mode, mount your `config.yml` instead of using `TOKEN`.

The `bin/kamal` binstub automatically loads `.env` before running Kamal. Environment variables already set in your shell take precedence.

### Deploy

```bash
bin/kamal setup    # First-time server setup and deploy
bin/kamal deploy   # Subsequent deploys
```

### Other Commands

```bash
bin/kamal app logs     # Tail container logs
bin/kamal app details  # Show running container info
bin/kamal app stop     # Stop the service
bin/kamal app start    # Start the service
```

The deploy config (`config/deploy.yml`) automatically passes `--add-host host.docker.internal:host-gateway` so the container can reach services on the host machine.

## OpenClaw Webhook Setup

Enable webhooks and configure the gateway in your OpenClaw config:

```json5
{
  gateway: {
    port: 18789,
    mode: "local",
    bind: "lan"
  },
  hooks: {
    enabled: true,
    token: "your-webhook-token"
  }
}
```

Setting `bind` to `"lan"` is required when Fizzy Pop runs inside a Docker container, because the default `"loopback"` mode only listens on `127.0.0.1` which is unreachable from within a container. The `"lan"` mode binds to `0.0.0.0` so the container can connect via `host.docker.internal`. Note that `"lan"` mode requires authentication to be configured — the gateway will refuse to start without it.

If you run Fizzy Pop directly on the same host (not in Docker), you can use `bind: "loopback"` instead.

See the [OpenClaw security docs](https://docs.openclaw.ai/gateway/security) for all bind modes (`loopback`, `lan`, `tailnet`, `auto`).

The `hooks.token` value is what you pass as `--webhook-token`. The `--webhook-url` should point to your gateway (e.g. `http://localhost:18789`).

Fizzy Pop posts to `POST /hooks/agent` with `Authorization: Bearer <token>`.

### Agent Routing (Multi-Agent Mode)

When using multi-agent mode, the OpenClaw adapter payload includes an `agentId` field:

```json
{
  "agentId": "optimus",
  "message": "...",
  "mode": "now",
  "deliver": false
}
```

Configure OpenClaw to route based on the agent name. See the [OpenClaw webhook docs](https://docs.openclaw.ai/automation/webhook) for more details.

## Hermes Agent Webhook Setup

Enable the Hermes webhook adapter and create a route that accepts Fizzy Pop payloads:

```yaml
platforms:
  webhook:
    enabled: true
    extra:
      port: 8644
      routes:
        fizzy:
          secret: "my-route-secret"
          prompt: "{message}"
          deliver: "log"
```

Run Fizzy Pop with `adapter: hermes`, `webhook_url`, `webhook_route`, and `webhook_token`. The Hermes adapter posts to `POST /webhooks/<route>` and signs the JSON body with the generic Hermes `X-Webhook-Signature` HMAC-SHA256 header. It also sends `X-Request-ID` so Hermes can de-duplicate retries.

## How It Works

1. Authenticates with Fizzy using personal access token(s)
2. Polls for unread notifications every N seconds (for each agent in multi-agent mode)
3. For each unread notification with a creator (comments/mentions):
   - Marks it as read in Fizzy
   - Forwards the notification through the configured webhook adapter
   - Includes agent identifier in payload (multi-agent mode)
