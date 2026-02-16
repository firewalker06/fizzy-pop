# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Fizzy Pop is a Ruby polling daemon that watches [Fizzy](https://app.fizzy.do) for unread notifications and forwards them to an [OpenClaw](https://docs.openclaw.ai) webhook. It replaces OpenClaw's built-in heartbeat mechanism with a more efficient dedicated polling service.

## Commands

```bash
# Install dependencies
bundle install

# Run with config file (multi-agent mode)
ruby bin/fizzy-pop --config config.yml

# Run single agent
ruby bin/fizzy-pop --url https://app.fizzy.do --token TOKEN --webhook-url URL --webhook-token TOKEN

# Dry run (validates payloads without sending webhooks)
ruby bin/fizzy-pop --config config.yml --dry-run

# Verbose logging (shows HTTP requests/responses with redacted auth)
ruby bin/fizzy-pop --config config.yml --verbose

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

The application is organized under `lib/fizzy_pop/` with a single entry point at `bin/fizzy-pop`. It uses Ruby's standard library plus the `httpx` HTTP client.

### File Structure

```
bin/
  fizzy-pop               # executable entry point (~40 lines)
lib/
  fizzy_pop.rb            # main require file (requires all sub-files)
  fizzy_pop/
    config.rb             # CLI parsing + YAML loading + merging
    fizzy_client.rb       # Fizzy API client (identity, notifications, mark-read)
    webhook_client.rb     # OpenClaw webhook delivery
    agent.rb              # Agent: owns a FizzyClient, polls accounts
    debug.rb              # Logging, breadcrumbs, color output
```

### Key Classes

- **FizzyPop::Config** — Parses CLI args (`OptionParser`) and loads YAML config. Two modes: single-agent via `--token`, or multi-agent via `--config`. CLI flags override config file values.
- **FizzyPop::FizzyClient** — HTTP client for the Fizzy API. Methods: `identity`, `notifications(slug)`, `mark_read(slug, id)`.
- **FizzyPop::WebhookClient** — HTTP client for OpenClaw webhook delivery. Sends `POST /hooks/agent` with `agentId`, `message`, `mode`, `deliver` fields.
- **FizzyPop::Agent** — Owns a `FizzyClient`, fetches identity/accounts on startup, polls for unread notifications. Contains the prompt template.
- **FizzyPop::Debug** — Module with class-level state for verbose/dry_run flags, breadcrumb tracking, and color-coded HTTP request/response logging.

### Execution Flow

1. **Parse CLI args** — `Config` handles `--url`, `--token`, `--config`, `--webhook-url`, `--webhook-token`, `--polling`, `--dry-run`, `--verbose`
2. **Load config** — Two modes: single-agent via `--token` flag, or multi-agent via `--config` pointing to a YAML file. CLI flags override config file values.
3. **Initialize agents** — Creates per-agent `FizzyClient` with Bearer auth, fetches identity from `GET /my/identity`, extracts account slugs. Agents without valid accounts are removed.
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
