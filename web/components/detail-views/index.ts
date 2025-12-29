// Shared components
export { BreadcrumbBar } from './shared/BreadcrumbBar';
export type { BreadcrumbItem } from './shared/BreadcrumbBar';
export { HeroSection } from './shared/HeroSection';
export { KeyValueRow } from './shared/KeyValueRow';
export { StatusListRow } from './shared/StatusListRow';
export { DisclosureSection } from './shared/DisclosureSection';
export { StatusBadge } from './shared/StatusBadge';
export { ActionBanner } from './shared/ActionBanner';

// Context and container
export { DetailModalProvider, useDetailModal } from './DetailModalContext';
export { DetailModalContainer } from './DetailModalContainer';
export { default as DetailPanel } from './DetailPanel';

// Modal components
export { PlanDetailModal } from './PlanDetailModal';
export { ProgramDetailModal } from './ProgramDetailModal';
export { WorkoutDetailModal } from './WorkoutDetailModal';
export { ExerciseDetailModal } from './ExerciseDetailModal';
