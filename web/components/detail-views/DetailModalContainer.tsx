'use client';

import { useDetailModal } from './DetailModalContext';
import { PlanDetailModal } from './PlanDetailModal';
import { ProgramDetailModal } from './ProgramDetailModal';
import { WorkoutDetailModal } from './WorkoutDetailModal';
import { ExerciseDetailModal } from './ExerciseDetailModal';

export function DetailModalContainer() {
  const { isOpen, currentEntity, navigationStack, goBack, close } = useDetailModal();

  if (!isOpen || !currentEntity) return null;

  // Build breadcrumb items from navigation stack
  const breadcrumbItems = navigationStack.map((item, index) => ({
    label: item.label,
    onClick: index < navigationStack.length - 1 ? () => {
      // Pop back to this item
      for (let i = navigationStack.length - 1; i > index; i--) {
        goBack();
      }
    } : undefined,
  }));

  const commonProps = {
    onBack: navigationStack.length > 1 ? goBack : undefined,
    onClose: close,
    breadcrumbItems,
  };

  switch (currentEntity.type) {
    case 'plan':
      return (
        <PlanDetailModal
          planId={currentEntity.id}
          {...commonProps}
        />
      );
    case 'program':
      return (
        <ProgramDetailModal
          programId={currentEntity.id}
          planId={currentEntity.parentIds?.planId || ''}
          {...commonProps}
        />
      );
    case 'workout':
      return (
        <WorkoutDetailModal
          workoutId={currentEntity.id}
          {...commonProps}
        />
      );
    case 'exercise':
      return (
        <ExerciseDetailModal
          exerciseId={currentEntity.id}
          {...commonProps}
        />
      );
    default:
      return null;
  }
}
