/**
 * Auth Utilities for Firebase Cloud Functions
 *
 * Provides Firebase ID token verification for authenticated endpoints.
 * Used by chat, user profile, and other protected endpoints.
 */

import * as admin from 'firebase-admin';
import { Request } from 'firebase-functions/v2/https';

// Error types for auth failures
export class AuthError extends Error {
  constructor(
    message: string,
    public statusCode: number = 401
  ) {
    super(message);
    this.name = 'AuthError';
  }
}

/**
 * Verify Firebase ID token from Authorization header
 *
 * @param req - The incoming request with Authorization header
 * @param adminApp - Firebase Admin instance
 * @returns Decoded token with uid and other claims
 * @throws AuthError if token is missing, malformed, or invalid
 *
 * Usage:
 * ```typescript
 * const decoded = await verifyAuth(req, admin);
 * const uid = decoded.uid;
 * ```
 */
export async function verifyAuth(
  req: Request,
  adminApp: typeof admin
): Promise<admin.auth.DecodedIdToken> {
  const authHeader = req.headers.authorization;

  if (!authHeader) {
    throw new AuthError('Missing Authorization header');
  }

  if (!authHeader.startsWith('Bearer ')) {
    throw new AuthError('Invalid Authorization header format. Expected: Bearer <token>');
  }

  const idToken = authHeader.split('Bearer ')[1];

  if (!idToken || idToken.trim() === '') {
    throw new AuthError('Empty token in Authorization header');
  }

  try {
    const decodedToken = await adminApp.auth().verifyIdToken(idToken);
    return decodedToken;
  } catch (error) {
    // Firebase auth errors have a 'code' property
    const firebaseError = error as { code?: string; message?: string };

    if (firebaseError.code === 'auth/id-token-expired') {
      throw new AuthError('Token expired', 401);
    }

    if (firebaseError.code === 'auth/id-token-revoked') {
      throw new AuthError('Token revoked', 401);
    }

    if (firebaseError.code === 'auth/invalid-id-token') {
      throw new AuthError('Invalid token', 401);
    }

    // Log unexpected errors for debugging
    console.error('Token verification failed:', firebaseError.message || error);
    throw new AuthError('Token verification failed', 401);
  }
}

/**
 * Extract user ID from request, verifying auth in the process
 *
 * Convenience wrapper that just returns the uid
 */
export async function getAuthenticatedUserId(
  req: Request,
  adminApp: typeof admin
): Promise<string> {
  const decoded = await verifyAuth(req, adminApp);
  return decoded.uid;
}
