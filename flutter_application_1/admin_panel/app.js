const API_BASE_URL = 'http://127.0.0.1:8000';
const tokenKey = 'financialcoach_admin_token';
const emailKey = 'financialcoach_admin_email';

const loginView = document.querySelector('#login-view');
const dashboardView = document.querySelector('#dashboard-view');
const loginForm = document.querySelector('#login-form');
const loginError = document.querySelector('#login-error');
const dashboardError = document.querySelector('#dashboard-error');
const adminEmail = document.querySelector('#admin-email');

function showDashboard() {
  loginView.classList.add('hidden');
  dashboardView.classList.remove('hidden');
  adminEmail.textContent = localStorage.getItem(emailKey) || 'Admin';
  loadOverview();
}

function showLogin() {
  dashboardView.classList.add('hidden');
  loginView.classList.remove('hidden');
}

async function login(email, password) {
  loginError.textContent = '';
  const response = await fetch(`${API_BASE_URL}/auth/login`, {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({email, password}),
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(body.detail || 'Giriş yapılamadı');
  if (body.user?.role !== 'admin') throw new Error('Bu hesap admin yetkisine sahip değil.');
  localStorage.setItem(tokenKey, body.access_token);
  localStorage.setItem(emailKey, email);
  showDashboard();
}

function setMetric(label, value, icon) {
  return `<article class="metric"><span class="metric-icon">${icon}</span><strong class="metric-value">${value ?? 0}</strong><span class="metric-label">${label}</span></article>`;
}

function renderOverview(data) {
  const total = Number(data.users || 0);
  const premium = Number(data.premium_users || 0);
  const free = Number(data.free_users || 0);
  document.querySelector('#metric-grid').innerHTML = [
    setMetric('Toplam kullanıcı', total, '◉'),
    setMetric('Premium kullanıcı', premium, '✦'),
    setMetric('PDF yükleme', data.pdf_uploads, '▣'),
    setMetric('Kaydedilen işlem', data.transactions, '≡'),
  ].join('');
  document.querySelector('#premium-label').textContent = premium;
  document.querySelector('#free-label').textContent = free;
  document.querySelector('#premium-bar').style.width = `${total ? (premium / total) * 100 : 0}%`;
  document.querySelector('#free-bar').style.width = `${total ? (free / total) * 100 : 0}%`;
  document.querySelector('#pending-label').textContent = data.pending_pdf_items || 0;
  document.querySelector('#plans-label').textContent = data.plans || 0;
  document.querySelector('#transactions-label').textContent = data.transactions || 0;
}

async function loadOverview() {
  dashboardError.classList.add('hidden');
  try {
    const response = await fetch(`${API_BASE_URL}/admin/overview`, {
      headers: {Authorization: `Bearer ${localStorage.getItem(tokenKey)}`},
    });
    const body = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(body.detail || 'Panel verisi alınamadı');
    renderOverview(body);
  } catch (error) {
    dashboardError.textContent = error.message;
    dashboardError.classList.remove('hidden');
  }
}

loginForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  const button = loginForm.querySelector('button');
  button.disabled = true;
  button.textContent = 'Giriş yapılıyor...';
  try {
    await login(document.querySelector('#email').value.trim(), document.querySelector('#password').value);
  } catch (error) {
    loginError.textContent = error.message;
  } finally {
    button.disabled = false;
    button.textContent = "CRM'e giriş yap";
  }
});

document.querySelector('#refresh-button').addEventListener('click', loadOverview);
document.querySelector('#logout-button').addEventListener('click', () => {
  localStorage.removeItem(tokenKey);
  localStorage.removeItem(emailKey);
  showLogin();
});

if (localStorage.getItem(tokenKey)) showDashboard(); else showLogin();
