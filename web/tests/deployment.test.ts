/**
 * Deployment Verification Tests
 *
 * Run AFTER deploying to verify production is working.
 * Command: npm run test:deploy
 *
 * These tests hit the actual deployed site to verify:
 * - Routes are accessible (cleanUrls working)
 * - Static assets load
 * - API endpoint responds
 */

import { describe, it, expect } from 'vitest';

const PRODUCTION_URL = 'https://medinaintelligence.web.app';

async function fetchWithTimeout(
  url: string,
  options: RequestInit = {},
  timeout = 10000
): Promise<Response> {
  const controller = new AbortController();
  const id = setTimeout(() => controller.abort(), timeout);
  try {
    const response = await fetch(url, { ...options, signal: controller.signal });
    return response;
  } finally {
    clearTimeout(id);
  }
}

describe('Production Deployment', () => {
  it('root page loads (200)', async () => {
    const response = await fetchWithTimeout(PRODUCTION_URL);
    expect(response.status).toBe(200);
  });

  it('/login page loads (200) and contains app shell', async () => {
    const response = await fetchWithTimeout(`${PRODUCTION_URL}/login`);
    expect(response.status).toBe(200);

    // React app is client-side rendered, so we check for:
    // - The HTML shell exists
    // - React hydration scripts are present
    const html = await response.text();
    expect(html).toContain('<!DOCTYPE html>');
    expect(html).toContain('__next_f'); // Next.js hydration
  });

  it('/app page loads (200) and contains Medina branding', async () => {
    const response = await fetchWithTimeout(`${PRODUCTION_URL}/app`);
    expect(response.status).toBe(200);

    const html = await response.text();
    expect(html).toContain('Medina');
  });

  it('/api/chat endpoint exists (401 without auth, not 404)', async () => {
    // Without auth token, should get 401, NOT 404
    // 404 would mean the endpoint isn't configured
    const response = await fetchWithTimeout(
      `${PRODUCTION_URL}/api/chat`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ messages: [{ role: 'user', content: 'test' }] }),
      },
      15000
    );

    // 401 or 403 = endpoint exists but needs auth (correct)
    // 404 = endpoint not configured (bug)
    expect([401, 403]).toContain(response.status);
  });

  it('CSS loads (not 404)', async () => {
    // First get the page to find a CSS link
    const pageResponse = await fetchWithTimeout(`${PRODUCTION_URL}/app`);
    const html = await pageResponse.text();

    // Find a CSS file reference
    const cssMatch = html.match(/href="(\/_next\/static\/[^"]+\.css)"/);
    if (cssMatch) {
      const cssUrl = `${PRODUCTION_URL}${cssMatch[1]}`;
      const cssResponse = await fetchWithTimeout(cssUrl);
      expect(cssResponse.status).toBe(200);
    }
  });
});

describe('No Marketing Pages', () => {
  it('/trainers returns 404 (removed)', async () => {
    const response = await fetchWithTimeout(`${PRODUCTION_URL}/trainers`);
    expect(response.status).toBe(404);
  });

  it('/gyms returns 404 (removed)', async () => {
    const response = await fetchWithTimeout(`${PRODUCTION_URL}/gyms`);
    expect(response.status).toBe(404);
  });
});
