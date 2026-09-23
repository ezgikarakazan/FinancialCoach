import { expect, test } from '@playwright/test';

test('user can register, login and read the current profile', async ({ request }) => {
  const email = `playwright-${Date.now()}@example.com`;
  const password = 'Test1234!';

  const registerResponse = await request.post('/auth/register', {
    data: {
      name: 'Playwright Test User',
      email,
      password,
    },
  });

  expect(registerResponse.status()).toBe(201);

  const loginResponse = await request.post('/auth/login', {
    data: { email, password },
  });

  expect(loginResponse.status()).toBe(200);
  const loginBody = await loginResponse.json();
  expect(loginBody.access_token).toBeTruthy();

  const profileResponse = await request.get('/auth/me', {
    headers: {
      Authorization: `Bearer ${loginBody.access_token}`,
    },
  });

  expect(profileResponse.status()).toBe(200);
  await expect(profileResponse).toHaveJSON({
    email,
    name: 'Playwright Test User',
  });
});
