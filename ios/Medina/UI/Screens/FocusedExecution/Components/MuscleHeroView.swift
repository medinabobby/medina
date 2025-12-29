//
// MuscleHeroView.swift
// Medina
//
// v76.0: Hero area showing muscle diagram for focused execution
// v78.1: Blue-only color palette, horizontal muscle pills
// Created: December 2025
// Purpose: Visual muscle indicator showing primary/secondary muscles being worked
//

import SwiftUI

/// Hero view displaying front and back body diagrams with highlighted muscles
struct MuscleHeroView: View {
    let muscles: [MuscleGroup]
    let primaryMuscle: MuscleGroup?

    var body: some View {
        VStack(spacing: 16) {
            // Front and back body diagrams side by side
            HStack(spacing: 32) {
                BodyDiagram(view: .front, highlighted: muscles, primary: primaryMuscle)
                BodyDiagram(view: .back, highlighted: muscles, primary: primaryMuscle)
            }
            .frame(height: 200)

            // v78.1: Horizontal muscle pills (replaces vertical legend)
            if !muscles.isEmpty {
                musclePills
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    /// v78.1: Horizontal pills showing primary and secondary muscles
    private var musclePills: some View {
        // Use FlowLayout-style wrapping for multiple muscles
        HStack(spacing: 8) {
            ForEach(muscles, id: \.self) { muscle in
                Text(muscle.displayName)
                    .font(.system(size: 13, weight: muscle == primaryMuscle ? .semibold : .regular))
                    .foregroundColor(muscle == primaryMuscle ? .white : Color("PrimaryText"))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(muscle == primaryMuscle ? Color.blue : Color.blue.opacity(0.15))
                    .cornerRadius(16)
            }
        }
    }
}

// MARK: - Body Diagram View

/// Single body diagram (front or back view)
struct BodyDiagram: View {
    enum ViewAngle {
        case front
        case back
    }

    let view: ViewAngle
    let highlighted: [MuscleGroup]
    let primary: MuscleGroup?

    var body: some View {
        ZStack {
            // Body outline
            bodyOutline

            // Highlighted muscle regions
            ForEach(highlighted, id: \.self) { muscle in
                if shouldShowMuscle(muscle) {
                    muscleRegion(for: muscle)
                        .fill(muscleColor(for: muscle).opacity(muscle == primary ? 0.8 : 0.4))
                }
            }
        }
        .frame(width: 100, height: 200)
    }

    /// Check if this muscle should be shown on this view angle
    private func shouldShowMuscle(_ muscle: MuscleGroup) -> Bool {
        switch view {
        case .front:
            return frontMuscles.contains(muscle)
        case .back:
            return backMuscles.contains(muscle)
        }
    }

    /// Muscles visible from front
    private var frontMuscles: Set<MuscleGroup> {
        [.chest, .shoulders, .biceps, .triceps, .forearms, .quadriceps, .core, .abs]
    }

    /// Muscles visible from back
    private var backMuscles: Set<MuscleGroup> {
        [.back, .lats, .traps, .shoulders, .triceps, .hamstrings, .glutes, .calves]
    }

    /// Body outline shape
    private var bodyOutline: some View {
        BodyOutlineShape()
            .stroke(Color.gray.opacity(0.3), lineWidth: 2)
    }

    /// Get the shape path for a specific muscle region
    private func muscleRegion(for muscle: MuscleGroup) -> Path {
        switch muscle {
        case .chest:
            return chestPath
        case .back, .lats:
            return backPath
        case .shoulders:
            return shouldersPath
        case .biceps:
            return bicepsPath
        case .triceps:
            return tricepsPath
        case .quadriceps:
            return quadsPath
        case .hamstrings:
            return hamstringsPath
        case .glutes:
            return glutesPath
        case .core, .abs:
            return corePath
        case .traps:
            return trapsPath
        case .calves:
            return calvesPath
        case .forearms:
            return forearmsPath
        case .fullBody:
            return Path() // Empty for full body
        }
    }

    /// v78.1: Blue-only color for all muscle groups
    /// Primary vs secondary distinction handled via opacity in the fill call
    private func muscleColor(for muscle: MuscleGroup) -> Color {
        return .blue
    }

    // MARK: - Muscle Paths (relative to 100x200 frame)

    private var chestPath: Path {
        Path { path in
            // Upper chest region (front view)
            path.move(to: CGPoint(x: 35, y: 45))
            path.addQuadCurve(to: CGPoint(x: 65, y: 45), control: CGPoint(x: 50, y: 38))
            path.addLine(to: CGPoint(x: 68, y: 60))
            path.addQuadCurve(to: CGPoint(x: 32, y: 60), control: CGPoint(x: 50, y: 65))
            path.closeSubpath()
        }
    }

    private var backPath: Path {
        Path { path in
            // Upper back / lats region (back view)
            path.move(to: CGPoint(x: 32, y: 45))
            path.addLine(to: CGPoint(x: 68, y: 45))
            path.addLine(to: CGPoint(x: 72, y: 75))
            path.addQuadCurve(to: CGPoint(x: 28, y: 75), control: CGPoint(x: 50, y: 80))
            path.closeSubpath()
        }
    }

    private var shouldersPath: Path {
        Path { path in
            // Left shoulder
            path.move(to: CGPoint(x: 22, y: 40))
            path.addQuadCurve(to: CGPoint(x: 32, y: 50), control: CGPoint(x: 22, y: 50))
            path.addLine(to: CGPoint(x: 32, y: 42))
            path.closeSubpath()

            // Right shoulder
            path.move(to: CGPoint(x: 78, y: 40))
            path.addQuadCurve(to: CGPoint(x: 68, y: 50), control: CGPoint(x: 78, y: 50))
            path.addLine(to: CGPoint(x: 68, y: 42))
            path.closeSubpath()
        }
    }

    private var bicepsPath: Path {
        Path { path in
            // Left bicep (front view)
            path.move(to: CGPoint(x: 18, y: 52))
            path.addQuadCurve(to: CGPoint(x: 18, y: 72), control: CGPoint(x: 12, y: 62))
            path.addLine(to: CGPoint(x: 26, y: 72))
            path.addQuadCurve(to: CGPoint(x: 26, y: 52), control: CGPoint(x: 26, y: 62))
            path.closeSubpath()

            // Right bicep
            path.move(to: CGPoint(x: 74, y: 52))
            path.addQuadCurve(to: CGPoint(x: 74, y: 72), control: CGPoint(x: 80, y: 62))
            path.addLine(to: CGPoint(x: 82, y: 72))
            path.addQuadCurve(to: CGPoint(x: 82, y: 52), control: CGPoint(x: 88, y: 62))
            path.closeSubpath()
        }
    }

    private var tricepsPath: Path {
        Path { path in
            // Left tricep (back view, inner arm)
            path.move(to: CGPoint(x: 20, y: 52))
            path.addLine(to: CGPoint(x: 28, y: 52))
            path.addLine(to: CGPoint(x: 28, y: 72))
            path.addLine(to: CGPoint(x: 20, y: 72))
            path.closeSubpath()

            // Right tricep
            path.move(to: CGPoint(x: 72, y: 52))
            path.addLine(to: CGPoint(x: 80, y: 52))
            path.addLine(to: CGPoint(x: 80, y: 72))
            path.addLine(to: CGPoint(x: 72, y: 72))
            path.closeSubpath()
        }
    }

    private var quadsPath: Path {
        Path { path in
            // Left quad (front view)
            path.move(to: CGPoint(x: 35, y: 95))
            path.addLine(to: CGPoint(x: 48, y: 95))
            path.addLine(to: CGPoint(x: 46, y: 140))
            path.addLine(to: CGPoint(x: 37, y: 140))
            path.closeSubpath()

            // Right quad
            path.move(to: CGPoint(x: 52, y: 95))
            path.addLine(to: CGPoint(x: 65, y: 95))
            path.addLine(to: CGPoint(x: 63, y: 140))
            path.addLine(to: CGPoint(x: 54, y: 140))
            path.closeSubpath()
        }
    }

    private var hamstringsPath: Path {
        Path { path in
            // Left hamstring (back view)
            path.move(to: CGPoint(x: 35, y: 95))
            path.addLine(to: CGPoint(x: 48, y: 95))
            path.addLine(to: CGPoint(x: 46, y: 140))
            path.addLine(to: CGPoint(x: 37, y: 140))
            path.closeSubpath()

            // Right hamstring
            path.move(to: CGPoint(x: 52, y: 95))
            path.addLine(to: CGPoint(x: 65, y: 95))
            path.addLine(to: CGPoint(x: 63, y: 140))
            path.addLine(to: CGPoint(x: 54, y: 140))
            path.closeSubpath()
        }
    }

    private var glutesPath: Path {
        Path { path in
            // Glute region (back view)
            path.move(to: CGPoint(x: 35, y: 80))
            path.addQuadCurve(to: CGPoint(x: 65, y: 80), control: CGPoint(x: 50, y: 75))
            path.addQuadCurve(to: CGPoint(x: 65, y: 95), control: CGPoint(x: 68, y: 88))
            path.addLine(to: CGPoint(x: 35, y: 95))
            path.addQuadCurve(to: CGPoint(x: 35, y: 80), control: CGPoint(x: 32, y: 88))
            path.closeSubpath()
        }
    }

    private var corePath: Path {
        Path { path in
            // Core/abs region (front view)
            path.move(to: CGPoint(x: 38, y: 62))
            path.addLine(to: CGPoint(x: 62, y: 62))
            path.addLine(to: CGPoint(x: 60, y: 90))
            path.addLine(to: CGPoint(x: 40, y: 90))
            path.closeSubpath()
        }
    }

    private var trapsPath: Path {
        Path { path in
            // Trapezius (back view, upper back/neck)
            path.move(to: CGPoint(x: 40, y: 30))
            path.addLine(to: CGPoint(x: 60, y: 30))
            path.addQuadCurve(to: CGPoint(x: 68, y: 45), control: CGPoint(x: 65, y: 35))
            path.addLine(to: CGPoint(x: 32, y: 45))
            path.addQuadCurve(to: CGPoint(x: 40, y: 30), control: CGPoint(x: 35, y: 35))
            path.closeSubpath()
        }
    }

    private var calvesPath: Path {
        Path { path in
            // Left calf (back view)
            path.move(to: CGPoint(x: 38, y: 145))
            path.addQuadCurve(to: CGPoint(x: 38, y: 175), control: CGPoint(x: 34, y: 160))
            path.addLine(to: CGPoint(x: 46, y: 175))
            path.addQuadCurve(to: CGPoint(x: 46, y: 145), control: CGPoint(x: 46, y: 160))
            path.closeSubpath()

            // Right calf
            path.move(to: CGPoint(x: 54, y: 145))
            path.addQuadCurve(to: CGPoint(x: 54, y: 175), control: CGPoint(x: 54, y: 160))
            path.addLine(to: CGPoint(x: 62, y: 175))
            path.addQuadCurve(to: CGPoint(x: 62, y: 145), control: CGPoint(x: 66, y: 160))
            path.closeSubpath()
        }
    }

    private var forearmsPath: Path {
        Path { path in
            // Left forearm (front view)
            path.move(to: CGPoint(x: 16, y: 74))
            path.addLine(to: CGPoint(x: 24, y: 74))
            path.addLine(to: CGPoint(x: 22, y: 92))
            path.addLine(to: CGPoint(x: 18, y: 92))
            path.closeSubpath()

            // Right forearm
            path.move(to: CGPoint(x: 76, y: 74))
            path.addLine(to: CGPoint(x: 84, y: 74))
            path.addLine(to: CGPoint(x: 82, y: 92))
            path.addLine(to: CGPoint(x: 78, y: 92))
            path.closeSubpath()
        }
    }
}

// MARK: - Body Outline Shape

/// Basic human body outline shape
struct BodyOutlineShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height

        return Path { path in
            // Head
            path.addEllipse(in: CGRect(x: w * 0.38, y: h * 0.02, width: w * 0.24, height: h * 0.12))

            // Neck
            path.move(to: CGPoint(x: w * 0.44, y: h * 0.13))
            path.addLine(to: CGPoint(x: w * 0.44, y: h * 0.17))
            path.move(to: CGPoint(x: w * 0.56, y: h * 0.13))
            path.addLine(to: CGPoint(x: w * 0.56, y: h * 0.17))

            // Torso
            path.move(to: CGPoint(x: w * 0.30, y: h * 0.20))
            path.addQuadCurve(to: CGPoint(x: w * 0.70, y: h * 0.20), control: CGPoint(x: w * 0.50, y: h * 0.17))
            path.addLine(to: CGPoint(x: w * 0.72, y: h * 0.45))
            path.addQuadCurve(to: CGPoint(x: w * 0.65, y: h * 0.48), control: CGPoint(x: w * 0.70, y: h * 0.47))
            path.addLine(to: CGPoint(x: w * 0.35, y: h * 0.48))
            path.addQuadCurve(to: CGPoint(x: w * 0.28, y: h * 0.45), control: CGPoint(x: w * 0.30, y: h * 0.47))
            path.closeSubpath()

            // Left arm
            path.move(to: CGPoint(x: w * 0.28, y: h * 0.20))
            path.addQuadCurve(to: CGPoint(x: w * 0.18, y: h * 0.28), control: CGPoint(x: w * 0.20, y: h * 0.22))
            path.addLine(to: CGPoint(x: w * 0.15, y: h * 0.48))
            path.addLine(to: CGPoint(x: w * 0.22, y: h * 0.48))
            path.addLine(to: CGPoint(x: w * 0.25, y: h * 0.30))

            // Right arm
            path.move(to: CGPoint(x: w * 0.72, y: h * 0.20))
            path.addQuadCurve(to: CGPoint(x: w * 0.82, y: h * 0.28), control: CGPoint(x: w * 0.80, y: h * 0.22))
            path.addLine(to: CGPoint(x: w * 0.85, y: h * 0.48))
            path.addLine(to: CGPoint(x: w * 0.78, y: h * 0.48))
            path.addLine(to: CGPoint(x: w * 0.75, y: h * 0.30))

            // Hips/pelvis
            path.move(to: CGPoint(x: w * 0.32, y: h * 0.45))
            path.addLine(to: CGPoint(x: w * 0.68, y: h * 0.45))
            path.addLine(to: CGPoint(x: w * 0.65, y: h * 0.52))
            path.addLine(to: CGPoint(x: w * 0.35, y: h * 0.52))
            path.closeSubpath()

            // Left leg
            path.move(to: CGPoint(x: w * 0.35, y: h * 0.50))
            path.addLine(to: CGPoint(x: w * 0.48, y: h * 0.50))
            path.addLine(to: CGPoint(x: w * 0.46, y: h * 0.75))
            path.addLine(to: CGPoint(x: w * 0.44, y: h * 0.92))
            path.addLine(to: CGPoint(x: w * 0.38, y: h * 0.92))
            path.addLine(to: CGPoint(x: w * 0.37, y: h * 0.75))
            path.closeSubpath()

            // Right leg
            path.move(to: CGPoint(x: w * 0.52, y: h * 0.50))
            path.addLine(to: CGPoint(x: w * 0.65, y: h * 0.50))
            path.addLine(to: CGPoint(x: w * 0.63, y: h * 0.75))
            path.addLine(to: CGPoint(x: w * 0.62, y: h * 0.92))
            path.addLine(to: CGPoint(x: w * 0.56, y: h * 0.92))
            path.addLine(to: CGPoint(x: w * 0.54, y: h * 0.75))
            path.closeSubpath()
        }
    }
}

// MARK: - Preview

#Preview("Chest & Triceps") {
    MuscleHeroView(
        muscles: [.chest, .triceps, .shoulders],
        primaryMuscle: .chest
    )
    .background(Color("Background"))
}

#Preview("Back & Biceps") {
    MuscleHeroView(
        muscles: [.back, .biceps, .lats],
        primaryMuscle: .back
    )
    .background(Color("Background"))
}

#Preview("Legs") {
    MuscleHeroView(
        muscles: [.quadriceps, .hamstrings, .glutes],
        primaryMuscle: .quadriceps
    )
    .background(Color("Background"))
}
