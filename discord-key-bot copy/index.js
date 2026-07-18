const fs = require('fs');
const path = require('path');
const express = require('express');
const { Client, GatewayIntentBits } = require('discord.js');
require('dotenv').config();

const KEYS_FILE = path.join(__dirname, 'keys.json');
const PORT = process.env.PORT || 3000;
const DISCORD_TOKEN = process.env.DISCORD_TOKEN || '';

function loadKeys(){
  try { return JSON.parse(fs.readFileSync(KEYS_FILE, 'utf8') || '{}'); } catch(e) { return {}; }
}
function saveKeys(obj){ fs.writeFileSync(KEYS_FILE, JSON.stringify(obj, null, 2)); }
function genKey(){ return (Math.random().toString(36).substr(2,8) + '-' + Math.random().toString(36).substr(2,4)).toUpperCase(); }

// Express HTTP API
const app = express();
app.use(express.json());

app.get('/validate', (req, res) => {
  const key = (req.query.key || '').toString().toUpperCase();
  const keys = loadKeys();
  const entry = keys[key];
  if (entry && Date.now() < entry.expiresAt) {
    return res.json({ valid: true, expiresAt: entry.expiresAt });
  }
  return res.json({ valid: false });
});

app.post('/create', (req, res) => {
  const days = Math.max(1, Number(req.body.days) || 7);
  const label = req.body.label || '';
  const key = genKey();
  const keys = loadKeys();
  keys[key] = { createdAt: Date.now(), expiresAt: Date.now() + days * 24 * 60 * 60 * 1000, label };
  saveKeys(keys);
  res.json({ key, expiresAt: keys[key].expiresAt });
});

app.listen(PORT, () => console.log(`Key API listening on http://localhost:${PORT}`));

// Discord Bot (simple command: !genkey <days>)
if (DISCORD_TOKEN) {
  const client = new Client({ intents: [GatewayIntentBits.Guilds, GatewayIntentBits.GuildMessages, GatewayIntentBits.MessageContent] });

  client.on('ready', () => {
    console.log('BLUD bot ready as', client.user.tag);
    // Set presence to show BLUD branding
    try {
      client.user.setPresence({ activities: [{ name: 'BLUD' }], status: 'online' });
    } catch (e) {
      console.warn('Failed to set presence:', e.message);
    }
    // Try to set nickname to BLUD in guilds where bot has permission
    client.guilds.cache.forEach(guild => {
      guild.members.fetch(client.user.id).then(member => {
        member.setNickname('BLUD').catch(() => {});
      }).catch(() => {});
    });
  });

  client.on('messageCreate', async (message) => {
    if (message.author.bot) return;
    const content = message.content.trim();
    if (!content.startsWith('!genkey')) return;
    const parts = content.split(/\s+/);
    const days = Math.max(1, Number(parts[1]) || 7);
    const label = parts.slice(2).join(' ') || '';
    const key = genKey();
    const keys = loadKeys();
    keys[key] = { createdAt: Date.now(), expiresAt: Date.now() + days * 24 * 60 * 60 * 1000, createdBy: message.author.id, label };
    saveKeys(keys);
    await message.reply(`BLUD generated key: **${key}** (valid ${days} day(s))`);
  });

  client.login(DISCORD_TOKEN).catch(err => console.error('Discord login failed:', err));
} else {
  console.log('DISCORD_TOKEN not set; Discord bot disabled. Only HTTP API is available.');
}
