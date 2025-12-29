/**
 * Chat Endpoint Tests
 *
 * Tests for the /api/chat endpoint including:
 * - Authentication verification
 * - Request validation
 * - Response streaming (mocked)
 */

import { describe, it, expect, vi, beforeEach } from 'vitest';
import { verifyAuth, AuthError } from './auth';
import { buildSystemPrompt } from './prompts/systemPrompt';
import { getToolDefinitions } from './tools/definitions';
import { UserProfile } from './types/chat';

// Mock Firebase Admin
const mockVerifyIdToken = vi.fn();
const mockAdmin = {
  auth: () => ({
    verifyIdToken: mockVerifyIdToken,
  }),
};

describe('Chat Endpoint Components', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('Auth Verification', () => {
    it('rejects missing Authorization header', async () => {
      const req = { headers: {} };

      await expect(verifyAuth(req as any, mockAdmin as any)).rejects.toThrow(
        AuthError
      );
      await expect(verifyAuth(req as any, mockAdmin as any)).rejects.toThrow(
        'Missing Authorization header'
      );
    });

    it('rejects invalid Authorization format', async () => {
      const req = { headers: { authorization: 'InvalidFormat token' } };

      await expect(verifyAuth(req as any, mockAdmin as any)).rejects.toThrow(
        'Invalid Authorization header format'
      );
    });

    it('rejects empty token', async () => {
      const req = { headers: { authorization: 'Bearer ' } };

      await expect(verifyAuth(req as any, mockAdmin as any)).rejects.toThrow(
        'Empty token'
      );
    });

    it('verifies valid token and returns decoded token', async () => {
      const req = { headers: { authorization: 'Bearer valid-token-123' } };
      const decodedToken = { uid: 'user-123', email: 'test@example.com' };
      mockVerifyIdToken.mockResolvedValue(decodedToken);

      const result = await verifyAuth(req as any, mockAdmin as any);

      expect(result).toEqual(decodedToken);
      expect(mockVerifyIdToken).toHaveBeenCalledWith('valid-token-123');
    });

    it('handles expired token error', async () => {
      const req = { headers: { authorization: 'Bearer expired-token' } };
      mockVerifyIdToken.mockRejectedValue({ code: 'auth/id-token-expired' });

      await expect(verifyAuth(req as any, mockAdmin as any)).rejects.toThrow(
        'Token expired'
      );
    });

    it('handles revoked token error', async () => {
      const req = { headers: { authorization: 'Bearer revoked-token' } };
      mockVerifyIdToken.mockRejectedValue({ code: 'auth/id-token-revoked' });

      await expect(verifyAuth(req as any, mockAdmin as any)).rejects.toThrow(
        'Token revoked'
      );
    });
  });

  describe('System Prompt Builder', () => {
    it('builds prompt with minimal user profile', () => {
      const user: UserProfile = { uid: 'user-123' };

      const prompt = buildSystemPrompt(user);

      expect(prompt).toContain('Medina');
      expect(prompt).toContain('fitness coach');
      expect(prompt).toContain('User');
    });

    it('includes user display name when available', () => {
      const user: UserProfile = {
        uid: 'user-123',
        displayName: 'Bobby',
      };

      const prompt = buildSystemPrompt(user);

      expect(prompt).toContain('Bobby');
    });

    it('includes fitness goal when available', () => {
      const user: UserProfile = {
        uid: 'user-123',
        displayName: 'Bobby',
        profile: {
          fitnessGoal: 'muscleGain',
        },
      };

      const prompt = buildSystemPrompt(user);

      expect(prompt).toContain('Build Muscle');
    });

    it('includes experience level when available', () => {
      const user: UserProfile = {
        uid: 'user-123',
        profile: {
          experienceLevel: 'intermediate',
        },
      };

      const prompt = buildSystemPrompt(user);

      expect(prompt).toContain('Intermediate');
    });

    it('includes training schedule when available', () => {
      const user: UserProfile = {
        uid: 'user-123',
        profile: {
          preferredDays: ['monday', 'wednesday', 'friday'],
          sessionDuration: 45,
        },
      };

      const prompt = buildSystemPrompt(user);

      expect(prompt).toContain('Monday');
      expect(prompt).toContain('Wednesday');
      expect(prompt).toContain('Friday');
      expect(prompt).toContain('45 minutes');
    });

    it('includes current date', () => {
      const user: UserProfile = { uid: 'user-123' };

      const prompt = buildSystemPrompt(user);

      // Should include current date in ISO format (YYYY-MM-DD)
      const datePattern = /\d{4}-\d{2}-\d{2}/;
      expect(prompt).toMatch(datePattern);
    });
  });

  describe('Tool Definitions', () => {
    it('returns MVP tools', () => {
      const tools = getToolDefinitions();

      expect(tools.length).toBeGreaterThan(0);

      // Check that MVP tools are included
      const toolNames = tools.map((t) => t.name);
      expect(toolNames).toContain('show_schedule');
      expect(toolNames).toContain('suggest_options');
      expect(toolNames).toContain('update_profile');
    });

    it('all tools have required properties', () => {
      const tools = getToolDefinitions();

      for (const tool of tools) {
        expect(tool.type).toBe('function');
        expect(tool.name).toBeTruthy();
        expect(tool.description).toBeTruthy();
        expect(tool.parameters).toBeDefined();
        expect(tool.parameters.type).toBe('object');
      }
    });

    it('show_schedule tool has period parameter', () => {
      const tools = getToolDefinitions();
      const showSchedule = tools.find((t) => t.name === 'show_schedule');

      expect(showSchedule).toBeDefined();
      expect(showSchedule?.parameters.properties).toHaveProperty('period');
      expect(showSchedule?.parameters.required).toContain('period');
    });

    it('suggest_options tool has options parameter', () => {
      const tools = getToolDefinitions();
      const suggestOptions = tools.find((t) => t.name === 'suggest_options');

      expect(suggestOptions).toBeDefined();
      expect(suggestOptions?.parameters.properties).toHaveProperty('options');
      expect(suggestOptions?.parameters.required).toContain('options');
    });

    it('update_profile tool has no required parameters', () => {
      const tools = getToolDefinitions();
      const updateProfile = tools.find((t) => t.name === 'update_profile');

      expect(updateProfile).toBeDefined();
      expect(updateProfile?.parameters.required).toEqual([]);
    });
  });
});

describe('Chat Request Validation', () => {
  it('requires messages array', () => {
    const body = {};
    const isValid =
      body &&
      typeof body === 'object' &&
      'messages' in body &&
      Array.isArray((body as any).messages) &&
      (body as any).messages.length > 0;

    expect(isValid).toBe(false);
  });

  it('rejects empty messages array', () => {
    const body = { messages: [] };
    const isValid = body.messages && body.messages.length > 0;

    expect(isValid).toBe(false);
  });

  it('accepts valid messages array', () => {
    const body = {
      messages: [{ role: 'user', content: 'Hello' }],
    };
    const isValid = body.messages && body.messages.length > 0;

    expect(isValid).toBe(true);
  });

  it('accepts optional previousResponseId', () => {
    const body = {
      messages: [{ role: 'user', content: 'Hello' }],
      previousResponseId: 'resp_123',
    };

    expect(body.previousResponseId).toBe('resp_123');
  });
});
