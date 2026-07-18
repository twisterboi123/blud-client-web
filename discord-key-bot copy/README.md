# Discord Key Bot

Simple Discord bot (BLUD) + HTTP API to generate and validate access keys for your client.

Setup:

1. Copy `.env.example` to `.env` and set `DISCORD_TOKEN`.
2. Install dependencies:

```bash
npm install
```

3. Run the bot:

```bash
npm start
```

- Usage:
- In Discord: `!genkey <days>` generates a key valid for `<days>` days (bot will reply as BLUD).
- HTTP API:
  - `GET /validate?key=KEY` -> `{ valid: true|false, expiresAt?: timestamp }`
  - `POST /create` with JSON `{ "days": 7, "label": "VIP" }` -> creates a key

Notes:
- Make the server reachable from Roblox by hosting publicly or using a tunnel (ngrok).
- In Roblox, enable `HttpService` in the game's settings to allow validation requests.
