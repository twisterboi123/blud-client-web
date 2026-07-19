const loginBtn = document.getElementById('login-btn');
const logoutBtn = document.getElementById('logout-btn');
const discordJoin = document.getElementById('discord-join');
const generateBtn = document.getElementById('generate-btn');
const resultBox = document.getElementById('result-box');
const memberBadge = document.getElementById('member-badge');
const adminCard = document.getElementById('admin-card');
const unlimitedBtn = document.getElementById('unlimited-btn');
const revokeBtn = document.getElementById('revoke-btn');
const revokeAllBtn = document.getElementById('revoke-all-btn');
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
    loginBtn.classList.remove('hidden');
    logoutBtn.classList.add('hidden');
    memberBadge.textContent = 'Login required';
    memberBadge.classList.remove('badge-alt');
    adminCard.classList.add('hidden');
    return;
  }

  loginBtn.classList.add('hidden');
  logoutBtn.classList.remove('hidden');

  if (session.memberOfGuild) {
    memberBadge.textContent = 'Discord member';
    memberBadge.classList.add('badge-alt');
  } else {
    memberBadge.textContent = 'Join the Discord first';
    memberBadge.classList.remove('badge-alt');
  }

  logoutBtn.textContent = 'Logout (' + session.user.username + ')';
  if (session.isAdmin) {
    adminCard.classList.remove('hidden');
    loadAdminKeys();
  }
}

loginBtn.addEventListener('click', () => {
  window.location.href = '/auth/discord';
});

logoutBtn.addEventListener('click', () => {
  window.location.href = '/logout';
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
    body: JSON.stringify({ days: 1 })
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

revokeAllBtn.addEventListener('click', async () => {
  if (!confirm('Revoke all active keys? This cannot be undone.')) return;
  adminList.innerHTML = 'Revoking all keys...';
  const response = await fetch('/admin/revoke-all', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' }
  });
  const data = await response.json();
  if (!response.ok) {
    adminList.textContent = data.error || 'Failed to revoke all keys.';
    return;
  }
  adminList.textContent = `Revoked ${data.count} keys.`;
  loadAdminKeys();
});

adminList.addEventListener('click', async (event) => {
  const button = event.target.closest('.revoke-key-btn');
  if (!button) return;
  const key = button.dataset.key;
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
  loadAdminKeys();
});

function formatRemainingTime(info) {
  if (info.unlimited) return 'Unlimited';
  if (info.active === false) return 'Revoked';
  if (!info.expiresAt) return 'No expiry';
  const delta = info.expiresAt - Date.now();
  if (delta <= 0) return 'Expired';
  const seconds = Math.floor(delta / 1000);
  const days = Math.floor(seconds / 86400);
  const hours = Math.floor((seconds % 86400) / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const parts = [];
  if (days) parts.push(`${days}d`);
  if (hours) parts.push(`${hours}h`);
  if (minutes) parts.push(`${minutes}m`);
  if (!parts.length) parts.push(`${seconds % 60}s`);
  return parts.join(' ');
}

async function loadAdminKeys() {
  if (!session?.isAdmin) return;
  const response = await fetch('/admin/keys');
  const keys = await response.json();
  adminList.innerHTML = '';
  const entries = Object.entries(keys)
    .sort(([, a], [, b]) => (b.createdAt || 0) - (a.createdAt || 0));
  if (entries.length === 0) {
    adminList.textContent = 'No keys yet.';
    return;
  }

  entries.forEach(([key, info]) => {
    const item = document.createElement('div');
    item.className = 'admin-item';

    const status = info.active === false ? 'Revoked' : info.unlimited ? 'Unlimited' : 'Active';
    const remaining = formatRemainingTime(info);
    const createdBy = info.createdBy || 'Unknown';
    const label = info.label || 'No label';

    item.innerHTML = `
      <div class="admin-item-main">
        <div class="admin-item-title"><strong>${key}</strong></div>
        <div class="admin-item-meta">
          <span>${label}</span>
          <span>${status}</span>
          <span>Left: ${remaining}</span>
          <span>Created by: ${createdBy}</span>
        </div>
      </div>
      <button class="button button-danger button-small revoke-key-btn" data-key="${key}">Revoke</button>
    `;

    adminList.appendChild(item);
  });
}

(async () => {
  await loadConfig();
  await loadSession();
})();