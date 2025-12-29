export default function PrivacyPage() {
  return (
    <main className="min-h-screen bg-gray-50">
      <div className="max-w-3xl mx-auto px-4 py-12">
        <div className="bg-white rounded-2xl shadow-lg p-8">
          {/* Header */}
          <div className="flex items-center gap-3 mb-8">
            <div className="w-10 h-10 bg-gradient-to-br from-blue-500 to-blue-600 rounded-xl flex items-center justify-center">
              <span className="text-white font-bold text-lg">M</span>
            </div>
            <h1 className="text-2xl font-bold text-gray-900">Privacy Policy</h1>
          </div>

          <p className="text-sm text-gray-500 mb-8">Last Updated: December 2025</p>

          <div className="space-y-8">
            <Section title="1. Information We Collect">
              <p className="mb-3">We collect the following types of information:</p>
              <ul className="list-disc list-inside space-y-1">
                <li>Account information (email, name)</li>
                <li>Fitness data you provide (workouts, goals, measurements)</li>
                <li>Usage data (app interactions, feature usage)</li>
                <li>Device information (device type, operating system)</li>
              </ul>
            </Section>

            <Section title="2. How We Use Your Information">
              <ul className="list-disc list-inside space-y-1">
                <li>Provide and improve our AI coaching services</li>
                <li>Personalize your workout recommendations</li>
                <li>Track your fitness progress</li>
                <li>Communicate with you about your account</li>
                <li>Analyze and improve our App</li>
              </ul>
            </Section>

            <Section title="3. Data Storage and Security">
              Your data is stored securely using Firebase, a Google Cloud service. We implement industry-standard security measures to protect your personal information. Your fitness data is encrypted in transit and at rest.
            </Section>

            <Section title="4. Third-Party Services">
              <p className="mb-3">We use the following third-party services:</p>
              <ul className="list-disc list-inside space-y-1">
                <li>Firebase (authentication, data storage)</li>
                <li>OpenAI (AI coaching features)</li>
                <li>Apple HealthKit (with your permission)</li>
              </ul>
              <p className="mt-3">These services have their own privacy policies governing their use of your data.</p>
            </Section>

            <Section title="5. Apple HealthKit">
              If you choose to connect Apple HealthKit, we access workout and activity data only with your explicit permission. HealthKit data is never shared with third parties or used for advertising. You can revoke HealthKit access at any time in your device settings.
            </Section>

            <Section title="6. Data Sharing">
              We do not sell your personal information. We may share data only in the following circumstances:
              <ul className="list-disc list-inside space-y-1 mt-3">
                <li>With your consent</li>
                <li>To comply with legal obligations</li>
                <li>To protect our rights or safety</li>
              </ul>
            </Section>

            <Section title="7. Your Rights">
              <ul className="list-disc list-inside space-y-1">
                <li>Access your personal data</li>
                <li>Request correction of your data</li>
                <li>Request deletion of your account and data</li>
                <li>Export your fitness data</li>
              </ul>
            </Section>

            <Section title="8. Data Retention">
              We retain your data for as long as your account is active. You may request deletion of your account and associated data at any time by contacting us.
            </Section>

            <Section title="9. Changes to This Policy">
              We may update this Privacy Policy from time to time. We will notify you of significant changes through the App or via email.
            </Section>

            <Section title="10. Contact Us">
              For privacy-related questions or to exercise your rights, contact us at{' '}
              <a href="mailto:privacy@medina.app" className="text-blue-600 hover:underline">
                privacy@medina.app
              </a>
            </Section>
          </div>

          {/* Back link */}
          <div className="mt-12 pt-8 border-t border-gray-200">
            <a href="/login" className="text-blue-600 hover:underline text-sm">
              &larr; Back to Login
            </a>
          </div>
        </div>
      </div>
    </main>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div>
      <h2 className="text-lg font-semibold text-gray-900 mb-2">{title}</h2>
      <div className="text-gray-600 leading-relaxed">{children}</div>
    </div>
  );
}
