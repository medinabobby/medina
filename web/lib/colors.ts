/**
 * Design Tokens - Medina Brand Colors
 *
 * Matches iOS Assets.xcassets color definitions exactly.
 * Use these instead of hardcoded Tailwind colors for brand consistency.
 */

export const colors = {
  // Primary Accent (iOS AccentBlue)
  accentBlue: 'rgb(59, 130, 236)',
  accentBlueHover: 'rgb(37, 99, 235)',
  accentSubtle: 'rgb(239, 246, 255)',

  // Text (iOS PrimaryText, SecondaryText)
  primaryText: 'rgb(26, 26, 26)',
  secondaryText: 'rgb(107, 114, 128)',
  tertiaryText: 'rgb(156, 163, 175)',

  // Backgrounds (iOS BackgroundPrimary, BackgroundSecondary)
  bgPrimary: 'rgb(255, 255, 255)',
  bgSecondary: 'rgb(249, 250, 252)',
  bgTertiary: 'rgb(243, 244, 246)',

  // Status Colors (iOS Success, Warning, Error)
  success: 'rgb(16, 185, 129)',
  successSubtle: 'rgb(236, 253, 245)',
  warning: 'rgb(245, 158, 11)',
  warningSubtle: 'rgb(255, 251, 235)',
  error: 'rgb(239, 68, 68)',
  errorSubtle: 'rgb(254, 242, 242)',

  // Borders (iOS BorderStandard, BorderSubtle)
  borderStandard: 'rgb(209, 213, 219)',
  borderSubtle: 'rgb(243, 244, 246)',

  // Specific UI Elements
  avatarBg: 'rgb(59, 130, 236)',
  avatarText: 'rgb(255, 255, 255)',
};

// Status dot colors for plans/workouts
export const statusColors = {
  active: colors.accentBlue,
  completed: colors.success,
  inProgress: colors.accentBlue,
  scheduled: colors.warning,
  skipped: colors.tertiaryText,
  abandoned: colors.tertiaryText,
  draft: colors.tertiaryText,
};

// Tailwind-compatible CSS custom properties
export const cssVariables = `
  --color-accent-blue: ${colors.accentBlue};
  --color-accent-blue-hover: ${colors.accentBlueHover};
  --color-accent-subtle: ${colors.accentSubtle};
  --color-primary-text: ${colors.primaryText};
  --color-secondary-text: ${colors.secondaryText};
  --color-tertiary-text: ${colors.tertiaryText};
  --color-bg-primary: ${colors.bgPrimary};
  --color-bg-secondary: ${colors.bgSecondary};
  --color-bg-tertiary: ${colors.bgTertiary};
  --color-success: ${colors.success};
  --color-warning: ${colors.warning};
  --color-error: ${colors.error};
  --color-border-standard: ${colors.borderStandard};
  --color-border-subtle: ${colors.borderSubtle};
`;
