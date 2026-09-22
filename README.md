# Xamt

Traditional Mongolian community & realtime chat.

**Stack:** Phoenix LiveView · PostgreSQL · PWA · `mgl-web-ime.js` · `richtext-editor.js`

## Setup

Requires [libvips](https://www.libvips.org) for gallery thumbnails (`brew install vips` or your distro package). If libvips is missing, uploads still succeed and thumb URLs fall back to the original.

```bash
mix setup
mix phx.server
```

Open [http://localhost:4002](http://localhost:4002).

Demo account (from seeds):

- email: `demo@xamt.local`
- password: `hello world!!`
- server: `/servers/mongol-bichig/general`

IME candidate backend: development defaults to `http://dev1:3003`. Override with
`XAMT_IME_BASE_URL`; set it to empty or `local` to stay on the bundled dictionary.
The host must be reachable from the client device — `localhost` will not work from
a phone on the LAN.

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
