# Xamt

Traditional Mongolian community & realtime chat.

**Stack:** Phoenix LiveView · PostgreSQL · PWA · `mgl-web-ime.js` · `richtext-editor.js`

## Setup

```bash
mix setup
mix phx.server
```

Open [http://localhost:4002](http://localhost:4002).

Demo account (from seeds):

- email: `demo@xamt.local`
- password: `hello world!!`
- server: `/servers/mongol-bichig/general`

IME candidate backend (optional): `http://dev1:3003` — configure via `data-ime-base-url` on composer / inputs.

## Spec routes

| Path | Page |
|------|------|
| `/` | Home |
| `/login` `/register` | Auth |
| `/servers/:slug` | Server |
| `/servers/:slug/:channel` | Channel chat |
| `/profile/:username` | Profile |
| `/settings` | Settings |

## Mongolian input

- Plain inputs: LiveView hook `MongolianIME` or `<mgl-ime>`
- Message composer: `richtext-editor.js` + `mgl-web-ime.js` (hook `MessageComposer`, `phx-update="ignore"`)

## PWA

Manifest and service worker under `priv/static/pwa/`.
