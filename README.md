# Fizzy Pop

A Ruby polling daemon that watches [Fizzy](https://app.fizzy.do) for unread notifications and forwards them to an [OpenClaw](https://docs.openclaw.ai) webhook.

## Setup

```bash
bundle install
```

## Usage

```bash
ruby app.rb --url https://app.fizzy.do --token YOUR_FIZZY_TOKEN [options]
```

### Required

| Flag | Description |
|------|-------------|
| `--url URL` | Fizzy base URL |
| `--token TOKEN` | Fizzy personal access token |

### Optional

| Flag | Description | Default |
|------|-------------|---------|
| `--webhook-url URL` | OpenClaw webhook base URL | — |
| `--webhook-token TOKEN` | OpenClaw webhook token | — |
| `--polling SECONDS` | Polling interval | `10` |
| `--dry-run` | Print webhook payload without sending | — |

### Examples

Dry run (no webhook):

```bash
ruby app.rb --url https://app.fizzy.do --token abc123 --dry-run
```

With webhook forwarding:

```bash
ruby app.rb \
  --url https://app.fizzy.do \
  --token abc123 \
  --webhook-url http://localhost:18789 \
  --webhook-token my-secret
```

Run as background daemon:

```bash
nohup ruby app.rb --url https://app.fizzy.do --token abc123 --dry-run > fizzy-pop.log 2>&1 &
```

## OpenClaw webhook setup

Enable webhooks in your OpenClaw gateway config:

```json5
{
  hooks: {
    enabled: true,
    token: "your-shared-secret"
  }
}
```

The `token` value is what you pass as `--webhook-token`. The `--webhook-url` should point to your gateway (e.g. `http://localhost:18789`).

Fizzy Pop posts to `POST /hooks/wake` with `Authorization: Bearer <token>`.

See the [OpenClaw webhook docs](https://docs.openclaw.ai/automation/webhook) for more details.

## How it works

1. Authenticates with Fizzy using a personal access token
2. Polls for unread notifications every N seconds
3. For each unread notification with a creator (comments/mentions):
   - Marks it as read in Fizzy
   - Forwards the notification to the OpenClaw webhook (`POST /hooks/wake`)
4. Ctrl+C or SIGTERM stops the process immediately
