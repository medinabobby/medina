/**
 * Web Smoke Tests
 *
 * These tests catch deployment issues BEFORE they go live.
 * Run with: npm run test
 *
 * Based on issues fixed in v212:
 * - 404 on routes (cleanUrls configuration)
 * - Chat not responding (SSE parsing)
 * - Intermittent 404 (build output conflicts)
 */

import { describe, it, expect, beforeAll } from 'vitest';
import { readFileSync, existsSync, readdirSync } from 'fs';
import { join } from 'path';

const WEB_ROOT = join(__dirname, '..');

describe('Firebase Hosting Configuration', () => {
  let firebaseConfig: any;

  beforeAll(() => {
    const configPath = join(WEB_ROOT, 'firebase.json');
    const configContent = readFileSync(configPath, 'utf-8');
    firebaseConfig = JSON.parse(configContent);
  });

  it('has cleanUrls enabled (prevents 404 on /app and /login)', () => {
    // Without cleanUrls: true, Firebase won't route /app to app.html
    // This caused all routes to 404 in v212
    expect(firebaseConfig.hosting.cleanUrls).toBe(true);
  });

  it('has trailingSlash disabled (prevents double requests)', () => {
    expect(firebaseConfig.hosting.trailingSlash).toBe(false);
  });

  it('has chat API rewrite configured', () => {
    const rewrites = firebaseConfig.hosting.rewrites || [];
    const chatRewrite = rewrites.find((r: any) => r.source === '/api/chat');

    expect(chatRewrite).toBeDefined();
    expect(chatRewrite.function).toBe('chat');
  });

  it('public directory is set to "out"', () => {
    expect(firebaseConfig.hosting.public).toBe('out');
  });
});

describe('Build Output Validation', () => {
  // This test only runs after a build
  it.skipIf(!existsSync(join(WEB_ROOT, 'out')))('out directory has no conflicting subdirectories', () => {
    // Next.js creates directories like /out/app/ which conflict with app.html
    // Firebase serves /out/app/index.html instead of /out/app.html for /app route
    const outDir = join(WEB_ROOT, 'out');

    if (!existsSync(outDir)) {
      return; // Skip if not built yet
    }

    // Check for conflicting directories
    const conflicts = ['app', 'login'].filter(name => {
      const dirPath = join(outDir, name);
      return existsSync(dirPath) && readdirSync(dirPath).length > 0;
    });

    expect(conflicts).toEqual([]);
  });
});

describe('SSE Event Structure', () => {
  // These tests verify we understand OpenAI's SSE format correctly

  it('delta is at root level, not nested in data', () => {
    // OpenAI sends: { type: "response.output_text.delta", delta: "Hello" }
    // NOT: { type: "...", data: { delta: "Hello" } }
    const sseEvent = {
      type: 'response.output_text.delta',
      delta: 'Hello world',
    };

    // Correct way (what we do now)
    const correctDelta = sseEvent.delta;
    expect(correctDelta).toBe('Hello world');

    // Wrong way (what we did before v212 fix)
    const wrongDelta = (sseEvent as any).data?.delta;
    expect(wrongDelta).toBeUndefined();
  });

  it('response.id is nested in response object', () => {
    const sseEvent = {
      type: 'response.created',
      response: { id: 'resp_123' },
    };

    const responseId = sseEvent.response?.id;
    expect(responseId).toBe('resp_123');
  });

  it('tool calls are in item.type = function_call', () => {
    const sseEvent = {
      type: 'response.output_item.added',
      item: { type: 'function_call', name: 'show_schedule' },
    };

    expect(sseEvent.item.type).toBe('function_call');
    expect(sseEvent.item.name).toBe('show_schedule');
  });
});

describe('Required Pages Exist', () => {
  it('login page exists', () => {
    const loginPage = join(WEB_ROOT, 'app', 'login', 'page.tsx');
    expect(existsSync(loginPage)).toBe(true);
  });

  it('app (chat) page exists', () => {
    const appPage = join(WEB_ROOT, 'app', 'app', 'page.tsx');
    expect(existsSync(appPage)).toBe(true);
  });

  it('root page exists (redirects to login)', () => {
    const rootPage = join(WEB_ROOT, 'app', 'page.tsx');
    expect(existsSync(rootPage)).toBe(true);
  });
});

describe('Chat Component Structure', () => {
  let chatPageContent: string;

  beforeAll(() => {
    const chatPagePath = join(WEB_ROOT, 'app', 'app', 'page.tsx');
    chatPageContent = readFileSync(chatPagePath, 'utf-8');
  });

  it('handles response.output_text.delta events', () => {
    // Must have a case for this event type
    expect(chatPageContent).toContain('response.output_text.delta');
  });

  it('handles response.created events', () => {
    expect(chatPageContent).toContain('response.created');
  });

  it('accesses delta at root level (not event.data.delta)', () => {
    // Should NOT have event.data.delta pattern
    // This was the bug in v212
    expect(chatPageContent).not.toMatch(/event\.data\.delta/);

    // Should access delta directly or via casting
    expect(chatPageContent).toMatch(/\.delta/);
  });

  it('logs SSE events for debugging', () => {
    // Debug logging helps diagnose issues
    expect(chatPageContent).toContain('[Chat]');
    expect(chatPageContent).toContain('SSE event');
  });
});

describe('Critical Dependencies', () => {
  let packageJson: any;

  beforeAll(() => {
    const packagePath = join(WEB_ROOT, 'package.json');
    const content = readFileSync(packagePath, 'utf-8');
    packageJson = JSON.parse(content);
  });

  it('has firebase SDK', () => {
    expect(packageJson.dependencies.firebase).toBeDefined();
  });

  it('has next.js', () => {
    expect(packageJson.dependencies.next).toBeDefined();
  });

  it('has react', () => {
    expect(packageJson.dependencies.react).toBeDefined();
  });
});
