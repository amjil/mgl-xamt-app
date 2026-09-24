# Xamt

Traditional Mongolian community & realtime chat — servers, channels, and a
vertical-script UI (`mn-Mong`, `vertical-lr`).

**Stack:** Elixir 1.15+ · Phoenix 1.8 / LiveView 1.1 · PostgreSQL · Bandit · PWA ·
`mgl-web-ime.js` · `mongolian-editor.js`

## Features

- Realtime channel chat (text, rich text, image gallery, voice notes, polls)
- Mentions, reactions, pins, reply/edit, server-scoped full-text search
- Public / private servers, invite links, roles & permissions, kick + audit
- Presence, typing indicators, unread watermarks
- Link previews (Open Graph, YouTube, Bilibili)
- Profiles, custom status, system / light / dark theme
- Traditional Mongolian IME + virtual keyboard
- PWA: offline queue + Background Sync, mention Web Push

## Setup

Requires PostgreSQL and [libvips](https://www.libvips.org) for gallery thumbnails
(`brew install vips` or your distro package). If libvips is missing, uploads
still succeed and thumb URLs fall back to the original.

```bash
mix setup
mix phx.server
```

Open [http://localhost:4002](http://localhost:4002). Dev binds all interfaces
(`0.0.0.0:4002`) so other machines on the LAN can reach the server.

Demo account (from seeds):

- email: `demo@xamt.local`
- username: `demo`
- password: `hello world!!`
- role: `creator` (can create servers)
- server: `/servers/mongol-bichig/general`

Before commit: `mix precommit`.

## Environment

| Variable | Notes |
|----------|--------|
| `PORT` | HTTP port (default `4002`) |
| `XAMT_IME_BASE_URL` | IME candidate backend (see below) |
| `VAPID_PUBLIC_KEY` / `VAPID_PRIVATE_KEY` | Web Push; required in prod. Generate with `mix web_push_ex.vapid` |
| `VAPID_SUBJECT` | Push subject (default `mailto:admin@xamt.app`) |
| `DATABASE_URL` | Required in prod |
| `SECRET_KEY_BASE` | Required in prod |
| `PHX_HOST` | Prod host (default `example.com`) |
| `PHX_SERVER` | Set `true` when starting a release |
| `PGUSER` / `PGPASSWORD` | Dev/test Postgres (defaults `amjil` / empty) |

IME candidate backend: development defaults to `http://dev1:3003`. Override with
`XAMT_IME_BASE_URL`; set it to empty or `local` to stay on the bundled dictionary.
The host must be reachable from the client device — `localhost` will not work from
a phone on the LAN.

## Routes

| Path | Page |
|------|------|
| `/` | Home / discover |
| `/login` `/register` | Auth (aliases of `/users/log-in` `/users/register`) |
| `/users/settings` | Email & password |
| `/admin/users/new` | Admin: create a user (site admin only) |
| `/invite/:code` | Redeem invite |
| `/servers/:server_slug` | Server (redirects to first channel) |
| `/servers/:server_slug/:channel_slug` | Channel chat |
| `/servers/:server_slug/:channel_slug/new` | New channel |
| `/profile/:username` | Profile |
| `/settings` | Profile settings |
| `POST /api/messages/sync` | Offline Background Sync replay |

Dev only: `/dev/dashboard`, `/dev/mailbox`.

## Mongolian input

- Plain inputs: LiveView hook `MongolianIME` or `<mgl-ime>`
- Message composer: `mongolian-editor.js` + `mgl-web-ime.js` (hook `MessageComposer`, `phx-update="ignore"`)

## PWA

Manifest and service worker under `priv/static/pwa/` (`standalone`, scope `/`).

Offline composer messages are stored in IndexedDB and flushed via Background
Sync (`sync-messages` → `POST /api/messages/sync`). Mention notifications use
Web Push when the browser has granted permission.
