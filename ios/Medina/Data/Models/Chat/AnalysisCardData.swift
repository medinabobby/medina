//
// AnalysisCardData.swift
// Medina
//
// v108.0: Analysis card data for training progress visualizations
// Displayed in chat alongside AI text responses
//

import Foundation
import SwiftUI

// MARK: - Analysis Card Types

/// Types of analysis visualizations available
enum AnalysisCardType {
    case progressionChart      // Line chart showing exercise 1RM over time
    case periodComparison      // Side-by-side bars comparing two periods
    case strengthTrends        // List of improving/regressing exercises with arrows
    case volumeBreakdown       // Muscle group volume distribution
}

// MARK: - Analysis Card Data

/// Data for rendering analysis cards in chat
/// Similar pattern to SummaryCardData but for training analysis visualizations
struct AnalysisCardData {
    let type: AnalysisCardType
    let title: String
    let subtitle: String?

    // Type-specific data (only one will be populated based on type)
    let progressionData: ProgressionChartData?
    let comparisonData: PeriodComparisonData?
    let trendsData: StrengthTrendsData?
    let volumeData: VolumeBreakdownData?

    // MARK: - Convenience Initializers

    /// Create a progression chart card
    static func progression(
        exerciseName: String,
        dataPoints: [ProgressionPoint],
        trend: ChartTrendDirection,
        percentChange: Double
    ) -> AnalysisCardData {
        AnalysisCardData(
            type: .progressionChart,
            title: "\(exerciseName) Progression",
            subtitle: "\(trend.arrow) \(String(format: "%.1f", abs(percentChange)))% \(trend.description)",
            progressionData: ProgressionChartData(
                exerciseName: exerciseName,
                dataPoints: dataPoints,
                trend: trend,
                percentChange: percentChange
            ),
            comparisonData: nil,
            trendsData: nil,
            volumeData: nil
        )
    }

    /// Create a period comparison card
    static func comparison(
        periodALabel: String,
        periodBLabel: String,
        metrics: [ComparisonMetric]
    ) -> AnalysisCardData {
        AnalysisCardData(
            type: .periodComparison,
            title: "\(periodALabel) vs \(periodBLabel)",
            subtitle: nil,
            progressionData: nil,
            comparisonData: PeriodComparisonData(
                periodALabel: periodALabel,
                periodBLabel: periodBLabel,
                metrics: metrics
            ),
            trendsData: nil,
            volumeData: nil
        )
    }

    /// Create a strength trends card
    static func trends(
        improving: [TrendExercise],
        maintaining: [TrendExercise],
        regressing: [TrendExercise]
    ) -> AnalysisCardData {
        let improvingCount = improving.count
        let regressingCount = regressing.count
        let subtitle = improvingCount > regressingCount
            ? "\(improvingCount) improving, \(regressingCount) regressing"
            : "\(regressingCount) regressing, \(improvingCount) improving"

        return AnalysisCardData(
            type: .strengthTrends,
            title: "Strength Trends",
            subtitle: subtitle,
            progressionData: nil,
            comparisonData: nil,
            trendsData: StrengthTrendsData(
                improving: improving,
                maintaining: maintaining,
                regressing: regressing
            ),
            volumeData: nil
        )
    }

    /// Create a volume breakdown card
    static func volume(
        muscleGroups: [MuscleVolumeData],
        totalVolume: Double
    ) -> AnalysisCardData {
        AnalysisCardData(
            type: .volumeBreakdown,
            title: "Volume Distribution",
            subtitle: formatVolume(totalVolume) + " total",
            progressionData: nil,
            comparisonData: nil,
            trendsData: nil,
            volumeData: VolumeBreakdownData(
                muscleGroups: muscleGroups,
                totalVolume: totalVolume
            )
        )
    }

    private static func formatVolume(_ volume: Double) -> String {
        if volume >= 1000 {
            return String(format: "%.1fK lbs", volume / 1000)
        }
        return "\(Int(volume)) lbs"
    }
}

// MARK: - Chart Data Types

/// Data point for progression line chart
struct ProgressionPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double  // Estimated 1RM or weight
    let label: String? // Optional label (e.g., "PR")
}

/// Data for progression line chart
struct ProgressionChartData {
    let exerciseName: String
    let dataPoints: [ProgressionPoint]
    let trend: ChartTrendDirection
    let percentChange: Double
}

/// Trend direction for chart visualizations
enum ChartTrendDirection {
    case improving
    case maintaining
    case regressing

    var arrow: String {
        switch self {
        case .improving: return "↑"
        case .maintaining: return "→"
        case .regressing: return "↓"
        }
    }

    var description: String {
        switch self {
        case .improving: return "improvement"
        case .maintaining: return "maintained"
        case .regressing: return "decline"
        }
    }

    var color: Color {
        switch self {
        case .improving: return .green
        case .maintaining: return .blue
        case .regressing: return .orange
        }
    }
}

/// Single metric for period comparison
struct ComparisonMetric: Identifiable {
    let id = UUID()
    let label: String       // e.g., "Volume", "Workouts", "Adherence"
    let periodAValue: Double
    let periodBValue: Double
    let unit: String        // e.g., "lbs", "", "%"
    let formatAsPercent: Bool

    var change: Double {
        guard periodAValue > 0 else { return 0 }
        return ((periodBValue - periodAValue) / periodAValue) * 100
    }

    var changeText: String {
        let prefix = change >= 0 ? "+" : ""
        return "\(prefix)\(String(format: "%.1f", change))%"
    }
}

/// Data for period comparison card
struct PeriodComparisonData {
    let periodALabel: String
    let periodBLabel: String
    let metrics: [ComparisonMetric]
}

/// Exercise with trend data
struct TrendExercise: Identifiable {
    let id = UUID()
    let exerciseName: String
    let percentChange: Double
    let startValue: Double?  // Starting 1RM
    let endValue: Double?    // Current 1RM
}

/// Data for strength trends card
struct StrengthTrendsData {
    let improving: [TrendExercise]
    let maintaining: [TrendExercise]
    let regressing: [TrendExercise]
}

/// Muscle group volume data
struct MuscleVolumeData: Identifiable {
    let id = UUID()
    let muscleGroup: String
    let volume: Double
    let percentage: Double  // Of total volume
    let color: Color
}

/// Data for volume breakdown card
struct VolumeBreakdownData {
    let muscleGroups: [MuscleVolumeData]
    let totalVolume: Double
}
