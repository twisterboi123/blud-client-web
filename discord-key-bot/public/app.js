const loginBtn = document.getElementById('login-btn');
const discordJoin = document.getElementById('discord-join');
const generateBtn = document.getElementById('generate-btn');
const validityInput = document.getElementById('validity-input');
const labelInput = document.getElementById('label-input');
const resultBox = document.getElementById('result-box');
const memberBadge = document.getElementById('member-badge');
const adminCard = document.getElementById('admin-card');
const unlimitedBtn = document.getElementById('unlimited-btn');
const revokeBtn = document.getElementById('revoke-btn');
const adminForm = document.getElementById('admin-form');
const revokeInput = document.getElementById('revoke-input');
const confirmRevoke = document.getElementById('confirm-revoke');
const adminList = document.getElementById('admin-list');

let session = null;
let config = null;

async function loadConfig() {
  const res = await fetch('/config');
  config = await res.json();
  discordJoin.href = config.discordInvite;
}

async function loadSession() {
  const res = await fetch('/session');
  session = await res.json();
  renderSession();
}

function renderSession() {
  if (!session?.loggedIn) {
    loginBtn.textContent = 'Login with Discord';
    memberBadge.textContent = 'Login required';
    memberBadge.classList.remove('badge-alt');
    adminCard.classList.add('hidden');
    return;
  }

  if (session.memberOfGuild) {
    memberBadge.textContent = 'Discord member';
    memberBadge.classList.add('badge-alt');
  } else {
    memberBadge.textContent = 'Join the Discord first';
    memberBadge.classList.remove('badge-alt');
  }

  loginBtn.textContent = session.user.username + '#' + session.user.discriminator;
  if (session.isAdmin) {
    adminCard.classList.remove('hidden');
    loadAdminKeys();
  }
}

loginBtn.addEventListener('click', () => {
  window.location.href = '/auth/discord';
});

generateBtn.addEventListener('click', async () => {
  resultBox.classList.remove('hidden');
  resultBox.textContent = 'Generating...';

  if (!session?.loggedIn) {
    resultBox.textContent = 'You must log in with Discord first.';
    return;
  }
  if (!session.memberOfGuild) {
    resultBox.textContent = 'You must join the Discord server before generating a key.';
    return;
  }

  const response = await fetch('/web-create', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ days: Number(validityInput.value), label: labelInput.value })
  });

  const data = await response.json();
  if (!response.ok) {
    resultBox.textContent = data.error || 'Failed to generate key.';
    return;
  }

  resultBox.innerHTML = `<strong>Your key:</strong><br>${data.key}<br><small>Expires: ${new Date(data.expiresAt).toLocaleString()}</small>`;
});

unlimitedBtn.addEventListener('click', async () => {
  const label = prompt('Unlimited key label (optional)');
  if (label === null) return;
  adminList.innerHTML = 'Generating unlimited key...';
  const response = await fetch('/admin/create', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ label, unlimited: true })
  });
  const data = await response.json();
  if (!response.ok) {
    adminList.textContent = data.error || 'Failed to create key.';
    return;
  }
  adminList.innerHTML = `<div class="result-box"><strong>Unlimited key:</strong><br>${data.key}</div>`;
  loadAdminKeys();
});

revokeBtn.addEventListener('click', () => {
  adminForm.classList.toggle('hidden');
});

confirmRevoke.addEventListener('click', async () => {
  const key = revokeInput.value.trim();
  if (!key) return;
  const response = await fetch('/admin/revoke', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ key })
  });
  const data = await response.json();
  if (!response.ok) {
    adminList.textContent = data.error || 'Failed to revoke key.';
    return;
  }
  adminList.textContent = `Revoked ${data.key}`;
  loadAdminKeys();
});

async function loadAdminKeys() {
  if (!session?.isAdmin) return;
  const response = await fetch('/admin/keys');
  const keys = await response.json();
  adminList.innerHTML = '';
  const entries = Object.entries(keys).slice(0, 10);
  if (entries.length === 0) {
    adminList.textContent = 'No keys yet.';
    return;
  }
  entries.forEach(([key, info]) => {
    const item = document.createElement('div');
    item.className = 'result-box';
    item.innerHTML = `<strong>${key}</strong><br>${info.label || 'No label'} · ${info.active === false ? 'Revoked' : info.unlimited ? 'Unlimited' : 'Expires ' + new Date(info.expiresAt).toLocaleString()}`;
    adminList.appendChild(item);
  });
}

(async () => {
  await loadConfig();
  await loadSession();
})();