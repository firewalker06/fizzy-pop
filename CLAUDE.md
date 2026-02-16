# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Fizzy Pop is a Ruby polling daemon that watches [Fizzy](https://app.fizzy.do) for unread notifications and forwards them to an [OpenClaw](https://docs.openclaw.ai) webhook. It replaces OpenClaw's built-in heartbeat mechanism with a more efficient dedicated polling service.

## Commands

```bash
# Install dependencies
bundle install

# Run with config file (multi-agent mode)
ruby app.rb --config config.yml

# Run single agent
ruby app.rb --url https://app.fizzy.do --token TOKEN --webhook-url URL --webhook-token TOKEN

# Dry run (validates payloads without sending webhooks)
ruby app.rb --config config.yml --dry-run

# Verbose logging (shows HTTP requests/responses with redacted auth)
ruby app.rb --config config.yml --verbose

# Docker build and run
docker build -t fizzy-pop .
docker run --rm -v $(pwd)/config.yml:/app/config.yml:ro fizzy-pop --config /app/config.yml

# Deploy with Kamal
bin/kamal setup    # first-time
bin/kamal deploy   # subsequent
bin/kamal app logs
```

There are no tests or linting configured.

## Architecture

The entire application is a single file: **app.rb** (~260 lines). There is no framework — it uses Ruby's standard library plus the `httpx` HTTP client.

### Execution Flow

1. **Parse CLI args** — `OptionParser` handles `--url`, `--token`, `--config`, `--webhook-url`, `--webhook-token`, `--polling`, `--dry-run`, `--verbose`
2. **Load config** — Two modes: single-agent via `--token` flag, or multi-agent via `--config` pointing to a YAML file. CLI flags override config file values.
3. **Initialize agents** — Creates per-agent HTTPX clients with Bearer auth, fetches identity from `GET /my/identity`, extracts account slugs. Agents without valid accounts are removed.
4. **Polling loop** — Infinite loop (default 10s interval) that for each agent/account:
   - Fetches unread notifications (`GET /{slug}/notifications`)
   - Finds first notification with a creator (comments/mentions)
   - Marks it as read (`POST /{slug}/notifications/{id}/reading`)
   - Builds a prompt message with Fizzy command references
   - Sends to OpenClaw webhook (`POST /hooks/agent`) with `agentId`, `message`, `mode`, `deliver` fields

### Configuration

- **config.yml** (gitignored) — YAML with `url`, `webhook_url`, `webhook_token`, `polling`, and an `agents` array (each with `name` and `token`). See `config.example.yml` for the template.
- **.env** (gitignored) — Used by `bin/kamal` for deployment variables (`HOSTS`, `URL`, `TOKEN`, `WEBHOOK_URL`, `WEBHOOK_TOKEN`).

### Debugging

- **Breadcrumbs** — Tracks execution path (e.g., `get_identity:agent-name`, `send_webhook:agent-name`), printed on Ctrl+C or exceptions.
- **Verbose mode** — Color-coded HTTP logging with redacted Authorization headers.
- **Dry run** — Skips webhook delivery, prints payload instead.

### Deployment

Uses Kamal 2.10+ with Docker. The container mounts `config.yml` from the host. Uses `host.docker.internal` to reach OpenClaw running on the host machine. Config in `config/deploy.yml` (gitignored, template at `config/deploy.yml.sample`).
