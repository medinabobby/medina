//
// AnalysisCardView.swift
// Medina
//
// v108.0: Container view for analysis visualizations in chat
// Routes to appropriate chart/card type based on AnalysisCardData
//

import SwiftUI
import Charts

struct AnalysisCardView: View {
    let data: AnalysisCardData

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header - for progression charts, title only (subtitle is dynamic in chart)
            if data.type == .progressionChart {
                Text(data.title)
                    .font(.headline)
                    .foregroundColor(Color("PrimaryText"))
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(data.title)
                        .font(.headline)
                        .foregroundColor(Color("PrimaryText"))

                    if let subtitle = data.subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundColor(Color("SecondaryText"))
                    }
                }
            }

            // Chart/Card content
            Group {
                switch data.type {
                case .progressionChart:
                    if let progressionData = data.progressionData {
                        ProgressionChartView(data: progressionData)
                    }
                case .periodComparison:
                    if let comparisonData = data.comparisonData {
                        PeriodComparisonView(data: comparisonData)
                    }
                case .strengthTrends:
                    if let trendsData = data.trendsData {
                        StrengthTrendsView(data: trendsData)
                    }
                case .volumeBreakdown:
                    if let volumeData = data.volumeData {
                        VolumeBreakdownView(data: volumeData)
                    }
                }
            }
        }
        .padding(16)
        .background(Color("CardBackground"))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color("Border"), lineWidth: 1)
        )
    }
}

// MARK: - Time Frame Selection

enum ChartTimeFrame: String, CaseIterable {
    case oneMonth = "1M"
    case threeMonths = "3M"
    case sixMonths = "6M"
    case oneYear = "1Y"
    case all = "ALL"

    var dateOffset: DateComponents? {
        switch self {
        case .oneMonth: return DateComponents(month: -1)
        case .threeMonths: return DateComponents(month: -3)
        case .sixMonths: return DateComponents(month: -6)
        case .oneYear: return DateComponents(year: -1)
        case .all: return nil
        }
    }
}

// MARK: - Progression Chart (Line Chart)

struct ProgressionChartView: View {
    let data: ProgressionChartData
    @State private var selectedTimeFrame: ChartTimeFrame = .all

    /// Filter data points by selected time frame
    var filteredDataPoints: [ProgressionPoint] {
        guard let offset = selectedTimeFrame.dateOffset,
              let cutoffDate = Calendar.current.date(byAdding: offset, to: Date()) else {
            return data.dataPoints
        }
        return data.dataPoints.filter { $0.date >= cutoffDate }
    }

    /// Calculate percentage change for filtered data
    var filteredPercentChange: Double {
        guard let first = filteredDataPoints.first,
              let last = filteredDataPoints.last,
              first.value > 0 else {
            return data.percentChange
        }
        return ((last.value - first.value) / first.value) * 100
    }

    /// Determine trend direction for filtered data
    var filteredTrend: ChartTrendDirection {
        if filteredPercentChange > 5 {
            return .improving
        } else if filteredPercentChange < -5 {
            return .regressing
        } else {
            return .maintaining
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Apple Finance style header: Current value + percentage
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let last = filteredDataPoints.last {
                    Text("\(Int(last.value))")
                        .font(.system(size: 32, weight: .semibold, design: .rounded))
                        .foregroundColor(Color("PrimaryText"))
                    Text("lbs")
                        .font(.subheadline)
                        .foregroundColor(Color("SecondaryText"))
                }
                Spacer()
                Text("\(filteredTrend.arrow)\(String(format: "%.1f", abs(filteredPercentChange)))%")
                    .font(.subheadline.bold())
                    .foregroundColor(filteredTrend.color)
            }

            // Time frame selector
            HStack(spacing: 6) {
                ForEach(ChartTimeFrame.allCases, id: \.self) { frame in
                    Button(action: { selectedTimeFrame = frame }) {
                        Text(frame.rawValue)
                            .font(.caption2.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(selectedTimeFrame == frame ? Color("AccentBlue") : Color("Border"))
                            .foregroundColor(selectedTimeFrame == frame ? .white : Color("SecondaryText"))
                            .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }

            // Chart (color based on filtered trend)
            Chart(filteredDataPoints) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("1RM", point.value)
                )
                .foregroundStyle(filteredTrend.color.gradient)
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("Date", point.date),
                    y: .value("1RM", point.value)
                )
                .foregroundStyle(filteredTrend.color.opacity(0.1).gradient)
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Date", point.date),
                    y: .value("1RM", point.value)
                )
                .foregroundStyle(filteredTrend.color)
                .symbolSize(30)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let intValue = value.as(Double.self) {
                            Text("\(Int(intValue))")
                                .font(.caption2)
                                .foregroundColor(Color("SecondaryText"))
                        }
                    }
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                        .foregroundStyle(Color("Border"))
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            // Apple Finance style: days for short ranges, months only for longer
                            Text(xAxisLabel(for: date))
                                .font(.caption2)
                                .foregroundColor(Color("SecondaryText"))
                        }
                    }
                }
            }
            .frame(height: 150)
        }
    }

    /// Apple Finance style X-axis labels based on time frame
    private func xAxisLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        switch selectedTimeFrame {
        case .oneMonth:
            // Short range: show day number only (like "11", "18", "25")
            formatter.dateFormat = "d"
        case .threeMonths, .sixMonths:
            // Medium range: show month only (like "Sep", "Oct", "Nov")
            formatter.dateFormat = "MMM"
        case .oneYear, .all:
            // Long range: show month only (like "Mar", "Jun", "Sep")
            formatter.dateFormat = "MMM"
        }
        return formatter.string(from: date)
    }
}

// MARK: - Period Comparison (Bar Chart)

struct PeriodComparisonView: View {
    let data: PeriodComparisonData

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Legend
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color("AccentBlue").opacity(0.6))
                        .frame(width: 8, height: 8)
                    Text(data.periodALabel)
                        .font(.caption)
                        .foregroundColor(Color("SecondaryText"))
                }
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color("AccentBlue"))
                        .frame(width: 8, height: 8)
                    Text(data.periodBLabel)
                        .font(.caption)
                        .foregroundColor(Color("SecondaryText"))
                }
            }

            // Metrics
            ForEach(data.metrics) { metric in
                ComparisonRow(metric: metric, periodALabel: data.periodALabel, periodBLabel: data.periodBLabel)
            }
        }
    }
}

struct ComparisonRow: View {
    let metric: ComparisonMetric
    let periodALabel: String
    let periodBLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(metric.label)
                    .font(.subheadline)
                    .foregroundColor(Color("PrimaryText"))
                Spacer()
                Text(metric.changeText)
                    .font(.caption.bold())
                    .foregroundColor(metric.change >= 0 ? .green : .orange)
            }

            // Bar comparison
            GeometryReader { geometry in
                let maxValue = max(metric.periodAValue, metric.periodBValue)
                let widthA = maxValue > 0 ? (metric.periodAValue / maxValue) * geometry.size.width : 0
                let widthB = maxValue > 0 ? (metric.periodBValue / maxValue) * geometry.size.width : 0

                VStack(spacing: 4) {
                    // Period A bar
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color("AccentBlue").opacity(0.6))
                            .frame(width: widthA, height: 12)
                        Text(formatValue(metric.periodAValue, unit: metric.unit, asPercent: metric.formatAsPercent))
                            .font(.caption2)
                            .foregroundColor(Color("SecondaryText"))
                        Spacer()
                    }

                    // Period B bar
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color("AccentBlue"))
                            .frame(width: widthB, height: 12)
                        Text(formatValue(metric.periodBValue, unit: metric.unit, asPercent: metric.formatAsPercent))
                            .font(.caption2)
                            .foregroundColor(Color("SecondaryText"))
                        Spacer()
                    }
                }
            }
            .frame(height: 32)
        }
        .padding(.vertical, 4)
    }

    private func formatValue(_ value: Double, unit: String, asPercent: Bool) -> String {
        if asPercent {
            return "\(Int(value))%"
        } else if value >= 1000 {
            return String(format: "%.1fK%@", value / 1000, unit.isEmpty ? "" : " \(unit)")
        } else {
            return "\(Int(value))\(unit.isEmpty ? "" : " \(unit)")"
        }
    }
}

// MARK: - Strength Trends (List with Arrows)

struct StrengthTrendsView: View {
    let data: StrengthTrendsData

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Improving
            if !data.improving.isEmpty {
                TrendSection(
                    title: "Improving",
                    exercises: data.improving,
                    color: .green,
                    arrow: "↑"
                )
            }

            // Maintaining
            if !data.maintaining.isEmpty {
                TrendSection(
                    title: "Maintaining",
                    exercises: data.maintaining,
                    color: .blue,
                    arrow: "→"
                )
            }

            // Regressing
            if !data.regressing.isEmpty {
                TrendSection(
                    title: "Needs Attention",
                    exercises: data.regressing,
                    color: .orange,
                    arrow: "↓"
                )
            }
        }
    }
}

struct TrendSection: View {
    let title: String
    let exercises: [TrendExercise]
    let color: Color
    let arrow: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(arrow)
                    .foregroundColor(color)
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundColor(color)
                Text("(\(exercises.count))")
                    .font(.caption)
                    .foregroundColor(Color("SecondaryText"))
            }

            ForEach(exercises.prefix(4)) { exercise in
                HStack {
                    Text(exercise.exerciseName)
                        .font(.caption)
                        .foregroundColor(Color("PrimaryText"))
                    Spacer()
                    if let start = exercise.startValue, let end = exercise.endValue {
                        Text("\(Int(start)) → \(Int(end)) lbs")
                            .font(.caption2)
                            .foregroundColor(Color("SecondaryText"))
                    }
                    Text("\(exercise.percentChange >= 0 ? "+" : "")\(String(format: "%.0f", exercise.percentChange))%")
                        .font(.caption.bold())
                        .foregroundColor(color)
                }
            }

            if exercises.count > 4 {
                Text("+\(exercises.count - 4) more")
                    .font(.caption)
                    .foregroundColor(Color("SecondaryText"))
            }
        }
    }
}

// MARK: - Volume Breakdown (Horizontal Bars)

struct VolumeBreakdownView: View {
    let data: VolumeBreakdownData

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(data.muscleGroups.prefix(6)) { muscle in
                HStack {
                    Text(muscle.muscleGroup)
                        .font(.caption)
                        .foregroundColor(Color("PrimaryText"))
                        .frame(width: 80, alignment: .leading)

                    GeometryReader { geometry in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(muscle.color)
                            .frame(width: geometry.size.width * muscle.percentage / 100, height: 16)
                    }
                    .frame(height: 16)

                    Text("\(Int(muscle.percentage))%")
                        .font(.caption2)
                        .foregroundColor(Color("SecondaryText"))
                        .frame(width: 35, alignment: .trailing)
                }
            }
        }
    }
}

// MARK: - Helper Views

struct StatPill: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(Color("SecondaryText"))
            Text(value)
                .font(.caption.bold())
                .foregroundColor(color)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        AnalysisCardView(data: .progression(
            exerciseName: "Bench Press",
            dataPoints: [
                ProgressionPoint(date: Date().addingTimeInterval(-90*24*3600), value: 185, label: nil),
                ProgressionPoint(date: Date().addingTimeInterval(-60*24*3600), value: 195, label: nil),
                ProgressionPoint(date: Date().addingTimeInterval(-30*24*3600), value: 205, label: "PR"),
                ProgressionPoint(date: Date(), value: 215, label: nil)
            ],
            trend: .improving,
            percentChange: 16.2
        ))

        AnalysisCardView(data: .comparison(
            periodALabel: "Q1 2025",
            periodBLabel: "Q4 2025",
            metrics: [
                ComparisonMetric(label: "Volume", periodAValue: 150000, periodBValue: 177900, unit: "lbs", formatAsPercent: false),
                ComparisonMetric(label: "Adherence", periodAValue: 88, periodBValue: 90, unit: "", formatAsPercent: true)
            ]
        ))

        AnalysisCardView(data: .trends(
            improving: [
                TrendExercise(exerciseName: "Bench Press", percentChange: 12.3, startValue: 185, endValue: 208),
                TrendExercise(exerciseName: "Back Squat", percentChange: 8.7, startValue: 225, endValue: 245)
            ],
            maintaining: [
                TrendExercise(exerciseName: "Deadlift", percentChange: 2.1, startValue: 315, endValue: 322)
            ],
            regressing: [
                TrendExercise(exerciseName: "Overhead Press", percentChange: -5.1, startValue: 115, endValue: 109)
            ]
        ))
    }
    .padding()
    .background(Color("Background"))
}
