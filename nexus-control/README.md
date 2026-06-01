# Phosphy Nexus Control

This folder contains:

- `index.html` - static dashboard. You can deploy this folder to Vercel.
- `relay-server.js` - long-running WebSocket relay for Nexus clients and the dashboard.
- `autoexec/phosphy-nexus-autoexec.lua` - Roblox autoexec script for each account.

## Connection Model

Use this setup for remote control:

1. Roblox accounts run `autoexec/phosphy-nexus-autoexec.lua`.
2. The autoexec loads Nexus and connects each account to your relay host.
3. The Vercel dashboard connects to the relay as an admin.
4. Commands flow from dashboard -> relay -> account Nexus client.

Vercel can host the dashboard, but it cannot host the WebSocket relay. Put `relay-server.js` on Railway, Render, Fly.io, a VPS, or your home PC with a tunnel.

## Local Test

```powershell
cd C:\Users\kolak\Documents\Codex\2026-06-01\recreate-an-exact-1-on-1\outputs\nexus-control
npm install
$env:NEXUS_ADMIN_KEY="change-me"
npm start
```

Open `index.html` and use:

```text
ws://localhost:8787/admin
```

Admin key:

```text
change-me
```

In the autoexec, leave:

```lua
local RELAY_HOST = "localhost:8787"
```

## Remote Setup

1. Deploy `relay-server.js` to a WebSocket-capable host.
2. Set environment variable:

```text
NEXUS_ADMIN_KEY=your-long-random-password
```

3. Set the autoexec host to the relay domain without `wss://`:

```lua
local RELAY_HOST = "your-relay-host.example.com"
```

4. Deploy this folder to Vercel for the dashboard.
5. In the dashboard, use:

```text
wss://your-relay-host.example.com/admin
```

and the same admin key.

## Notes

- If no account is selected in the UI, commands send to all connected accounts.
- The Phosphy controls use the autoexec bridge command `phosphy:set`.
- Multi-dropdown values can be sent as JSON, for example:

```json
{"ClickPotion":true}
```

