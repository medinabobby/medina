'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { isSignInWithEmailLink, signInWithEmailLink } from 'firebase/auth';
import { getFirebaseAuth } from '@/lib/firebase';

export default function AuthPage() {
  const router = useRouter();
  const [status, setStatus] = useState<'loading' | 'success' | 'error'>('loading');
  const [errorMessage, setErrorMessage] = useState<string>('');

  useEffect(() => {
    async function handleMagicLink() {
      // Check if this is a sign-in link
      const auth = getFirebaseAuth();
      if (!isSignInWithEmailLink(auth, window.location.href)) {
        setStatus('error');
        setErrorMessage('Invalid sign-in link');
        return;
      }

      // Get email from localStorage (saved when user requested the link)
      let email = window.localStorage.getItem('emailForSignIn');

      if (!email) {
        // If no email in storage, prompt for it (iOS app flow)
        email = window.prompt('Please enter your email for confirmation');
      }

      if (!email) {
        setStatus('error');
        setErrorMessage('Email is required to complete sign-in');
        return;
      }

      try {
        await signInWithEmailLink(auth, email, window.location.href);
        window.localStorage.removeItem('emailForSignIn');
        setStatus('success');

        // Redirect to app after short delay
        setTimeout(() => {
          router.push('/app');
        }, 1500);
      } catch (error) {
        console.error('Sign-in error:', error);
        setStatus('error');
        setErrorMessage('Failed to sign in. The link may have expired.');
      }
    }

    handleMagicLink();
  }, [router]);

  return (
    <main className="min-h-screen bg-gray-50 flex items-center justify-center px-4">
      <div className="max-w-md w-full text-center">
        <div className="bg-white rounded-2xl shadow-lg p-8">
          {/* Logo */}
          <div className="flex justify-center mb-6">
            <div className="w-16 h-16 bg-gradient-to-br from-blue-500 to-blue-600 rounded-2xl flex items-center justify-center">
              <span className="text-white font-bold text-2xl">M</span>
            </div>
          </div>

          {status === 'loading' && (
            <>
              <h1 className="text-xl font-semibold text-gray-900 mb-2">
                Signing you in...
              </h1>
              <div className="flex justify-center">
                <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600" />
              </div>
            </>
          )}

          {status === 'success' && (
            <>
              <h1 className="text-xl font-semibold text-gray-900 mb-2">
                Success!
              </h1>
              <p className="text-gray-600">
                Redirecting to your dashboard...
              </p>
            </>
          )}

          {status === 'error' && (
            <>
              <h1 className="text-xl font-semibold text-red-600 mb-2">
                Sign-in Failed
              </h1>
              <p className="text-gray-600 mb-4">
                {errorMessage}
              </p>
              <button
                onClick={() => router.push('/login')}
                className="px-6 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors"
              >
                Back to Login
              </button>
            </>
          )}
        </div>
      </div>
    </main>
  );
}
