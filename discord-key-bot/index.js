const fs = require('fs');
const path = require('path');
const express = require('express');
const cookieSession = require('cookie-session');
const { Client, GatewayIntentBits, PermissionsBitField } = require('discord.js');
require('dotenv').config();

const KEYS_FILE = path.join(__dirname, 'keys.json');
const KEY_TEXT_FILE = path.join(__dirname, 'keys.txt');
const SITE_HTML_PATH = path.join(__dirname, '..', 'new', 'index.html');
const PORT = process.env.PORT || 3000;
const storage = globalThis.__bludStorage || (globalThis.__bludStorage = { keys: {}, keyText: '' });

function ensureKeyTextFile(){
  if (process.env.VERCEL) {
    storage.keyText = storage.keyText || '';
    return;
  }
  try {
    if (!fs.existsSync(KEY_TEXT_FILE)) {
      fs.writeFileSync(KEY_TEXT_FILE, '');
    }
  } catch (err) {
    if (err && err.code !== 'EROFS' && err.code !== 'EPERM') {
      throw err;
    }
  }
}
const DISCORD_TOKEN = process.env.DISCORD_TOKEN || '';
const GUILD_ID = process.env.GUILD_ID || '';
const DISCORD_CLIENT_ID = process.env.DISCORD_CLIENT_ID || '';
const DISCORD_CLIENT_SECRET = process.env.DISCORD_CLIENT_SECRET || '';
const DISCORD_REDIRECT_URI = process.env.DISCORD_REDIRECT_URI || `http://localhost:${PORT}/auth/discord/callback`;
const DISCORD_INVITE = process.env.DISCORD_INVITE || 'https://discord.gg/zyWPA4zjDd';
const ADMIN_USER_IDS = (process.env.ADMIN_USER_IDS || '').split(',').map(id => id.trim()).filter(Boolean);
const COOKIE_SECRET = process.env.COOKIE_SECRET || 'blud_cookie_secret_2026';
const KEY_SECRET = process.env.KEY_SECRET || 'BLUD_SECRET_2026';

function loadKeys(){
  try {
    const keys = JSON.parse(fs.readFileSync(KEYS_FILE, 'utf8') || '{}');
    pruneExpiredKeys(keys);
    saveKeys(keys);
    return keys;
  } catch(e) {
    ensureKeyTextFile();
    const keys = storage.keys || {};
    pruneExpiredKeys(keys);
    storage.keys = keys;
    return keys;
  }
}
function saveKeys(obj){
  storage.keys = obj;
  ensureKeyTextFile();
  try {
    fs.writeFileSync(KEYS_FILE, JSON.stringify(obj, null, 2));
  } catch (err) {
    if (err && err.code !== 'EROFS' && err.code !== 'EPERM') {
      throw err;
    }
  }
  syncActiveKeyTextFile(obj);
}
function pruneExpiredKeys(keys){
  const now = Date.now();
  let changed = false;
  for (const [key, entry] of Object.entries(keys)) {
    if (entry && entry.active !== false && entry.expiresAt !== null && entry.expiresAt <= now) {
      delete keys[key];
      changed = true;
    }
  }
  return changed;
}
function syncActiveKeyTextFile(keys){
  ensureKeyTextFile();
  const now = Date.now();
  const lines = Object.entries(keys)
    .filter(([, entry]) => entry && entry.active !== false && (entry.expiresAt === null || entry.expiresAt > now))
    .map(([key]) => key);
  storage.keyText = lines.join('\n');
  try {
    fs.writeFileSync(KEY_TEXT_FILE, storage.keyText);
  } catch (err) {
    if (err && err.code !== 'EROFS' && err.code !== 'EPERM') {
      throw err;
    }
  }
}

function startKeyCleanupLoop(){
  if (process.env.VERCEL) return;
  setInterval(() => {
    loadKeys();
  }, 60000);
}
function checksumValue(str){
  let sum = 0;
  for (let i = 0; i < str.length; i++) {
    sum += str.charCodeAt(i);
  }
  return sum;
}
function toBase36(value, width){
  const chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  let out = '';
  do {
    out = chars[value % 36] + out;
    value = Math.floor(value / 36);
  } while (value > 0);
  return out.padStart(width, '0');
}
function randomPayload(length){
  const chars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  let out = '';
  for (let i = 0; i < length; i++) {
    out += chars[Math.floor(Math.random() * chars.length)];
  }
  return out;
}
function genKey(){
  const payload = randomPayload(8);
  const hash = checksumValue(payload + KEY_SECRET) % (36 ** 4);
  const suffix = toBase36(hash, 4);
  return `${payload}-${suffix}`;
}

// Express HTTP API
const app = express();
app.set('trust proxy', true);
ensureKeyTextFile();
startKeyCleanupLoop();
app.use(express.json());
app.use(cookieSession({
  name: 'blud_session',
  keys: [COOKIE_SECRET],
  maxAge: 24 * 60 * 60 * 1000,
  secure: process.env.NODE_ENV === 'production' || process.env.VERCEL === '1',
  httpOnly: true,
  sameSite: 'lax'
}));

app.get('/', (req, res) => {
  res.sendFile(SITE_HTML_PATH);
});
app.use(express.static(path.join(__dirname, 'public')));

app.get('/keys.txt', (req, res) => {
  ensureKeyTextFile();
  loadKeys();
  res.type('text/plain');
  res.send(storage.keyText || '');
});

app.get('/loader.lua', (req, res) => {
  const publicBase = `${req.protocol}://${req.get('host')}`;
  const loaderScript = `-- Blud Client loader\nlocal keyListUrl = "${publicBase}/keys.txt"\nlocal ok, body = pcall(function()\n  return game:HttpGet(keyListUrl)\nend)\nif ok then\n  print("Blud Client key list loaded from " .. keyListUrl)\n  print(body)\nelse\n  warn("Blud Client could not reach the key server")\nend\n`;
  res.type('text/plain');
  res.send(loaderScript);
});

app.get('/config', (req, res) => {
  res.json({
    discordInvite: DISCORD_INVITE,
    guildId: GUILD_ID,
    loginEnabled: Boolean(DISCORD_CLIENT_ID && DISCORD_CLIENT_SECRET && GUILD_ID)
  });
});

app.get('/session', (req, res) => {
  const data = {
    loggedIn: Boolean(req.session && req.session.user),
    user: req.session?.user || null,
    memberOfGuild: Boolean(req.session?.memberOfGuild),
    isAdmin: Boolean(req.session?.isAdmin)
  };
  res.json(data);
});

app.post('/validate-key', (req, res) => {
  const { key } = req.body;
  
  if (!key || typeof key !== 'string') {
    return res.json({ valid: false });
  }
  
  const keys = loadKeys();
  const now = Date.now();
  const entry = keys[key.trim()];
  
  if (!entry) {
    return res.json({ valid: false });
  }
  
  // Check if key is active and not expired
  if (entry.active === false) {
    return res.json({ valid: false });
  }
  
  if (entry.expiresAt !== null && entry.expiresAt <= now) {
    return res.json({ valid: false });
  }
  
  return res.json({ valid: true });
});

app.get('/auth/discord', (req, res) => {
  const state = Math.random().toString(36).slice(2);
  const params = new URLSearchParams({
    client_id: DISCORD_CLIENT_ID,
    redirect_uri: DISCORD_REDIRECT_URI,
    response_type: 'code',
    scope: 'identify guilds',
    state
  });
  res.redirect(`https://discord.com/api/oauth2/authorize?${params.toString()}`);
});

async function discordApi(path, token, method = 'GET', body) {
  const url = `https://discord.com/api${path}`;
  const headers = { Authorization: `Bearer ${token}` };
  if (body) headers['Content-Type'] = 'application/json';
  const response = await fetch(url, { method, headers, body: body ? JSON.stringify(body) : undefined });
  if (!response.ok) {
    throw new Error(`Discord API ${response.status}`);
  }
  return response.json();
}

async function exchangeCode(code) {
  const body = new URLSearchParams({
    client_id: DISCORD_CLIENT_ID,
    client_secret: DISCORD_CLIENT_SECRET,
    grant_type: 'authorization_code',
    code,
    redirect_uri: DISCORD_REDIRECT_URI,
    scope: 'identify guilds'
  });

  const response = await fetch('https://discord.com/api/oauth2/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: body.toString()
  });

  if (!response.ok) {
    throw new Error('Discord token exchange failed');
  }
  return response.json();
}

app.get('/auth/discord/callback', async (req, res) => {
  try {
    const { code } = req.query;
    if (!code) throw new Error('Missing code');
    const tokenData = await exchangeCode(code.toString());
    const user = await discordApi('/users/@me', tokenData.access_token);
    const guilds = await discordApi('/users/@me/guilds', tokenData.access_token);
    req.session.user = { id: user.id, username: user.username, discriminator: user.discriminator };
    req.session.guilds = guilds.map(g => g.id);
    req.session.memberOfGuild = !!GUILD_ID && guilds.some(g => g.id === GUILD_ID);
    req.session.isAdmin = ADMIN_USER_IDS.includes(user.id);
    res.redirect('/');
  } catch (err) {
    res.status(500).send(`Login failed: ${err.message}`);
  }
});

app.get('/logout', (req, res) => {
  req.session = null;
  res.redirect('/');
});

function requireLogin(req, res, next) {
  if (!req.session || !req.session.user) {
    return res.status(401).json({ error: 'Login required' });
  }
  next();
}

function requireGuildMember(req, res, next) {
  if (GUILD_ID && !req.session?.memberOfGuild) {
    return res.status(403).json({ error: 'You must join the Discord server to generate keys.' });
  }
  next();
}

function requireAdmin(req, res, next) {
  if (!req.session?.isAdmin) {
    return res.status(403).json({ error: 'Admin access required.' });
  }
  next();
}

app.post('/web-create', requireLogin, requireGuildMember, (req, res) => {
  const days = Math.max(1, Number(req.body.days) || 7);
  const label = req.body.label || '';
  const keys = loadKeys();

  if (!req.session.isAdmin) {
    const existing = Object.values(keys).filter(k => k.createdBy === req.session.user.id && k.active !== false && (k.expiresAt === null || Date.now() < k.expiresAt));
    if (existing.length >= 1) {
      return res.status(403).json({ error: 'Normal members may only generate one active key.' });
    }
  }

  const key = genKey();
  keys[key] = {
    createdAt: Date.now(),
    expiresAt: Date.now() + days * 24 * 60 * 60 * 1000,
    label,
    createdBy: req.session.user.id,
    active: true
  };
  saveKeys(keys);
  res.json({ key, expiresAt: keys[key].expiresAt });
});

app.get('/admin/keys', requireLogin, requireAdmin, (req, res) => {
  res.json(loadKeys());
});

app.post('/admin/revoke', requireLogin, requireAdmin, (req, res) => {
  const key = (req.body.key || '').toString().toUpperCase();
  const keys = loadKeys();
  if (!keys[key]) {
    return res.status(404).json({ error: 'Key not found' });
  }
  keys[key].active = false;
  saveKeys(keys);
  res.json({ success: true, key });
});

app.post('/admin/create', requireLogin, requireAdmin, (req, res) => {
  const label = req.body.label || '';
  const unlimited = Boolean(req.body.unlimited);
  const days = unlimited ? 0 : Math.max(1, Number(req.body.days) || 7);
  const key = genKey();
  const keys = loadKeys();
  keys[key] = {
    createdAt: Date.now(),
    expiresAt: unlimited ? null : Date.now() + days * 24 * 60 * 60 * 1000,
    label,
    createdBy: req.session.user.id,
    active: true,
    unlimited: unlimited
  };
  saveKeys(keys);
  res.json({ key, expiresAt: keys[key].expiresAt, unlimited });
});

app.get('/validate', (req, res) => {
  const key = (req.query.key || '').toString().toUpperCase();
  const keys = loadKeys();
  const entry = keys[key];
  if (entry && entry.active !== false && (entry.expiresAt === null || Date.now() < entry.expiresAt)) {
    return res.json({ valid: true, expiresAt: entry.expiresAt, active: entry.active !== false, unlimited: entry.unlimited || false });
  }
  return res.json({ valid: false });
});

app.post('/create', (req, res) => {
  const days = Math.max(1, Number(req.body.days) || 7);
  const label = req.body.label || '';
  const key = genKey();
  const keys = loadKeys();
  keys[key] = { createdAt: Date.now(), expiresAt: Date.now() + days * 24 * 60 * 60 * 1000, label, active: true };
  saveKeys(keys);
  res.json({ key, expiresAt: keys[key].expiresAt });
});

if (!process.env.VERCEL) {
  app.listen(PORT, () => console.log(`Key API listening on http://localhost:${PORT}`));
}

module.exports = app;

// Discord Bot (simple command: !genkey <days>)
if (DISCORD_TOKEN && !process.env.VERCEL) {
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
    // Register slash command in a specific guild for fast availability (optional)
    if (GUILD_ID) {
      client.guilds.fetch(GUILD_ID).then(guild => {
        guild.commands.create({
          name: 'genkey',
          description: 'Generate an access key',
          options: [
            { name: 'days', type: 4, description: 'Number of days (default 7)', required: false },
            { name: 'label', type: 3, description: 'Label for the key', required: false }
          ]
        }).then(() => console.log('Registered /genkey in guild', GUILD_ID)).catch(err => console.warn('Command register failed:', err.message));
      }).catch(err => console.warn('Failed to fetch guild for command registration:', err.message));
    }
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

  // Slash command handler
  client.on('interactionCreate', async (interaction) => {
    if (!interaction.isChatInputCommand()) return;
    if (interaction.commandName === 'genkey') {
      // Permission: require Manage Guild or Administrator
      if (!interaction.memberPermissions || !interaction.memberPermissions.has(PermissionsBitField.Flags.ManageGuild)) {
        return interaction.reply({ content: 'You need Manage Guild permission to use this command.', ephemeral: true });
      }
      const days = interaction.options.getInteger('days') || 7;
      const label = interaction.options.getString('label') || '';
      const key = genKey();
      const keys = loadKeys();
      keys[key] = { createdAt: Date.now(), expiresAt: Date.now() + days * 24 * 60 * 60 * 1000, createdBy: interaction.user.id, label };
      saveKeys(keys);
      await interaction.reply({ content: `BLUD generated key: **${key}** (valid ${days} day(s))` });
    }
  });

  client.login(DISCORD_TOKEN).catch(err => console.error('Discord login failed:', err));
} else {
  console.log('DISCORD_TOKEN not set; Discord bot disabled. Only HTTP API is available.');
}
