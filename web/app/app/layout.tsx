export const metadata = {
  title: 'Chat - Medina',
  description: 'Chat with your AI fitness coach',
};

// Full-screen chat layout that overlays the main site navbar/footer
export default function ChatLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div className="fixed inset-0 z-50 bg-gray-50">
      {children}
    </div>
  );
}
