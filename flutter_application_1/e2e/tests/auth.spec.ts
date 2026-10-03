import { expect, test } from '@playwright/test';

test('user can register, login and read the current profile', async ({ request }) => {
  const email = `playwright-${Date.now()}@gmail.com`;
  const password = 'Test1234!';

  const registerResponse = await request.post('/auth/register', {
    data: {
      first_name: 'Playwright',
      last_name: 'Test User',
      email,
      password,
      password_confirmation: password,
    },
  });

  expect(registerResponse.status()).toBe(201);

  const loginResponse = await request.post('/auth/login', {
    data: { email, password },
  });
  expect(loginResponse.status()).toBe(200);
  const loginBody = await loginResponse.json();

  const profileResponse = await request.get('/auth/me', {
    headers: { Authorization: `Bearer ${loginBody.access_token}` },
  });
  expect(profileResponse.status()).toBe(200);
  await expect(profileResponse).toHaveJSON({ email, name: 'Playwright Test User' });
});

test('registration rejects weak passwords', async ({ request }) => {
  const weakPasswordResponse = await request.post('/auth/register', {
    data: {
      first_name: 'Test',
      last_name: 'User',
      email: `weak-password-${Date.now()}@gmail.com`,
      password: 'password',
      password_confirmation: 'password',
    },
  });
  expect(weakPasswordResponse.status()).toBe(400);
});
