export default function TermsPage() {
  return (
    <main className="min-h-screen bg-gray-50">
      <div className="max-w-3xl mx-auto px-4 py-12">
        <div className="bg-white rounded-2xl shadow-lg p-8">
          {/* Header */}
          <div className="flex items-center gap-3 mb-8">
            <div className="w-10 h-10 bg-gradient-to-br from-blue-500 to-blue-600 rounded-xl flex items-center justify-center">
              <span className="text-white font-bold text-lg">M</span>
            </div>
            <h1 className="text-2xl font-bold text-gray-900">Terms of Service</h1>
          </div>

          <p className="text-sm text-gray-500 mb-8">Last Updated: December 2025</p>

          <div className="space-y-8">
            <Section title="1. Acceptance of Terms">
              By accessing or using Medina (&quot;the App&quot;), you agree to be bound by these Terms of Service. If you do not agree to these terms, please do not use the App.
            </Section>

            <Section title="2. Description of Service">
              Medina is an AI-powered fitness coaching application that helps users create training plans, execute workouts, and track fitness progress. The App provides personalized workout recommendations based on user input and preferences.
            </Section>

            <Section title="3. Beta Program">
              You acknowledge that Medina is currently in beta testing. The App may contain bugs, errors, or incomplete features. We make no guarantees about the availability, reliability, or functionality of the App during the beta period.
            </Section>

            <Section title="4. User Responsibilities">
              <ul className="list-disc list-inside space-y-1">
                <li>You must be at least 18 years old to use the App</li>
                <li>You are responsible for maintaining the confidentiality of your account</li>
                <li>You agree to provide accurate information when creating your profile</li>
                <li>You acknowledge that fitness activities carry inherent risks</li>
                <li>You should consult a healthcare provider before starting any exercise program</li>
              </ul>
            </Section>

            <Section title="5. Health Disclaimer">
              Medina is not a substitute for professional medical advice, diagnosis, or treatment. The workout recommendations provided by the App are for informational purposes only. Always consult with a qualified healthcare provider before beginning any fitness program, especially if you have pre-existing health conditions.
            </Section>

            <Section title="6. Intellectual Property">
              All content, features, and functionality of the App are owned by Medina and are protected by copyright, trademark, and other intellectual property laws.
            </Section>

            <Section title="7. Limitation of Liability">
              To the maximum extent permitted by law, Medina shall not be liable for any indirect, incidental, special, consequential, or punitive damages resulting from your use of the App, including but not limited to physical injury, property damage, or data loss.
            </Section>

            <Section title="8. Changes to Terms">
              We reserve the right to modify these Terms of Service at any time. Continued use of the App after changes constitutes acceptance of the new terms.
            </Section>

            <Section title="9. Contact">
              For questions about these Terms of Service, please contact us at{' '}
              <a href="mailto:support@medina.app" className="text-blue-600 hover:underline">
                support@medina.app
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
