/**
 * Firestore Mock Factory
 *
 * Provides mock implementations for Firebase Admin Firestore
 * Used in unit tests to avoid hitting real Firestore
 */

import { vi } from 'vitest';

// Mock document snapshot
export interface MockDocumentSnapshot {
  exists: boolean;
  id: string;
  data: () => Record<string, unknown> | undefined;
}

// Mock document reference
export interface MockDocumentReference {
  get: ReturnType<typeof vi.fn>;
  set: ReturnType<typeof vi.fn>;
  update: ReturnType<typeof vi.fn>;
  delete: ReturnType<typeof vi.fn>;
  id: string;
}

// Mock query
export interface MockQuery {
  where: ReturnType<typeof vi.fn>;
  orderBy: ReturnType<typeof vi.fn>;
  limit: ReturnType<typeof vi.fn>;
  get: ReturnType<typeof vi.fn>;
}

// Mock collection reference
export interface MockCollectionReference extends MockQuery {
  doc: ReturnType<typeof vi.fn>;
  add: ReturnType<typeof vi.fn>;
}

// Mock Firestore instance
export interface MockFirestore {
  collection: ReturnType<typeof vi.fn>;
  doc: ReturnType<typeof vi.fn>;
  collectionGroup: ReturnType<typeof vi.fn>;
}

/**
 * Create a mock document snapshot
 */
export function createMockDocSnapshot(
  id: string,
  data: Record<string, unknown> | null
): MockDocumentSnapshot {
  return {
    exists: data !== null,
    id,
    data: () => data ?? undefined,
  };
}

/**
 * Create a mock document reference
 */
export function createMockDocRef(id: string): MockDocumentReference {
  return {
    id,
    get: vi.fn(),
    set: vi.fn().mockResolvedValue(undefined),
    update: vi.fn().mockResolvedValue(undefined),
    delete: vi.fn().mockResolvedValue(undefined),
  };
}

/**
 * Create a mock collection reference
 */
export function createMockCollection(): MockCollectionReference {
  const mockQuery: MockQuery = {
    where: vi.fn().mockReturnThis(),
    orderBy: vi.fn().mockReturnThis(),
    limit: vi.fn().mockReturnThis(),
    get: vi.fn().mockResolvedValue({ docs: [], empty: true }),
  };

  return {
    ...mockQuery,
    doc: vi.fn((id: string) => createMockDocRef(id)),
    add: vi.fn().mockResolvedValue({ id: 'new-doc-id' }),
  };
}

/**
 * Create a mock Firestore instance
 *
 * Usage:
 * ```typescript
 * const mockDb = createMockFirestore();
 *
 * // Setup user document
 * const userDoc = createMockDocSnapshot('user123', { name: 'Bobby' });
 * mockDb.collection('users').doc('user123').get.mockResolvedValue(userDoc);
 * ```
 */
export function createMockFirestore(): MockFirestore {
  const collections: Record<string, MockCollectionReference> = {};

  const getOrCreateCollection = (path: string) => {
    if (!collections[path]) {
      collections[path] = createMockCollection();
    }
    return collections[path];
  };

  return {
    collection: vi.fn((path: string) => getOrCreateCollection(path)),
    doc: vi.fn((path: string) => {
      const parts = path.split('/');
      const id = parts[parts.length - 1];
      return createMockDocRef(id);
    }),
    collectionGroup: vi.fn((collectionId: string) => ({
      where: vi.fn().mockReturnThis(),
      orderBy: vi.fn().mockReturnThis(),
      limit: vi.fn().mockReturnThis(),
      get: vi.fn().mockResolvedValue({ docs: [], empty: true }),
    })),
  };
}

/**
 * Helper to setup a user document in mock Firestore
 */
export function setupMockUser(
  mockDb: MockFirestore,
  userId: string,
  userData: Record<string, unknown>
) {
  const userDoc = createMockDocSnapshot(userId, userData);
  const usersCollection = mockDb.collection('users') as MockCollectionReference;
  const userDocRef = usersCollection.doc(userId) as MockDocumentReference;
  userDocRef.get.mockResolvedValue(userDoc);
  return userDocRef;
}

/**
 * Helper to setup workouts in mock Firestore
 */
export function setupMockWorkouts(
  mockDb: MockFirestore,
  userId: string,
  workouts: Array<{ id: string; data: Record<string, unknown> }>
) {
  const workoutDocs = workouts.map(w => createMockDocSnapshot(w.id, w.data));
  const workoutsCollection = mockDb.collection(`users/${userId}/workouts`) as MockCollectionReference;
  workoutsCollection.get.mockResolvedValue({
    docs: workoutDocs,
    empty: workouts.length === 0,
  });
  return workoutsCollection;
}
