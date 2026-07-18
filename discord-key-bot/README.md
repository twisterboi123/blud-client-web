# Discord Key Bot

Simple Discord bot (BLUD) + HTTP API to generate and validate access keys for your client.

Setup:

1. Copy `.env.example` to `.env` and set `DISCORD_TOKEN`. Optionally add `GUILD_ID` to register slash commands in a specific guild for faster availability.
2. Install dependencies:

```bash
npm install
```

3. Run the bot:

```bash
npm start
```

- Usage:
- In Discord: `!genkey <days>` or `/genkey` (slash) generates a key valid for `<days>` days (bot will reply as BLUD). The slash command is registered automatically if you set `GUILD_ID` in `.env`.
- HTTP API:
  - `GET /validate?key=KEY` -> `{ valid: true|false, expiresAt?: timestamp }`
  - `POST /create` with JSON `{ "days": 7, "label": "VIP" }` -> creates a key

Notes:
- Make the server reachable from Roblox by hosting publicly or using a tunnel (ngrok).
- In Roblox, enable `HttpService` in the game's settings to allow validation requests.
