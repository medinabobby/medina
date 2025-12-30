'use client';

interface MedinaIconProps {
  className?: string;
  animate?: boolean;
}

// Medina brand icon - tic-tac-toe / hashtag grid
// Used in greeting and as loading indicator
export function MedinaIcon({ className = '', animate = false }: MedinaIconProps) {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      className={`${animate ? 'animate-spin-slow' : ''} ${className}`}
    >
      {/* Vertical lines */}
      <line x1="8" y1="4" x2="8" y2="20" />
      <line x1="16" y1="4" x2="16" y2="20" />
      {/* Horizontal lines */}
      <line x1="4" y1="8" x2="20" y2="8" />
      <line x1="4" y1="16" x2="20" y2="16" />
    </svg>
  );
}

// Convenience export for animated version
export function MedinaIconAnimated({ className }: { className?: string }) {
  return <MedinaIcon className={className} animate />;
}

export default MedinaIcon;
