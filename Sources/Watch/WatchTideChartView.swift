import Charts
import SwiftUI
import TidesCore

/// Compact tide curve for the watch: the 24 hours around now, with the
/// high/low waters, a "now" marker and a warm wash over the daylight
/// hours (the watch face is always dark, so day is lightened, matching
/// the phone's dark mode). Static — the phone has the pannable chart.
struct WatchTideChartView: View {
    let predictor: TidePredictor
    let latitude: Double
    let longitude: Double
    let now: Date

    /// 12 hours behind and ahead of now.
    private var windowStart: Date { now.addingTimeInterval(-12 * 3_600) }
    private var windowEnd: Date { now.addingTimeInterval(12 * 3_600) }

    var body: some View {
        let levels = predictor.predictions(from: windowStart, to: windowEnd, interval: 30 * 60)
        let extrema = predictor.extrema(from: windowStart, to: windowEnd)
        let marks = (extrema.highs.map { ($0, true) } + extrema.lows.map { ($0, false) })

        Chart {
            ForEach(daylightIntervals, id: \.start) { interval in
                RectangleMark(
                    xStart: .value("Time", interval.start),
                    xEnd: .value("Time", interval.end)
                )
                .foregroundStyle(Self.daylightFill)
            }

            ForEach(levels, id: \.time) { level in
                LineMark(
                    x: .value("Time", level.time),
                    y: .value("Height", level.heightMeters)
                )
                .interpolationMethod(.catmullRom)
                AreaMark(
                    x: .value("Time", level.time),
                    y: .value("Height", level.heightMeters)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(.linearGradient(
                    colors: [Color.accentColor.opacity(0.3), Color.accentColor.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                ))
            }

            ForEach(marks, id: \.0.time) { level, isHigh in
                PointMark(
                    x: .value("Time", level.time),
                    y: .value("Height", level.heightMeters)
                )
                .foregroundStyle(isHigh ? Color.blue : Color.orange)
                .symbolSize(20)
            }

            RuleMark(x: .value("Now", now))
                .foregroundStyle(.red.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 2]))
            PointMark(
                x: .value("Now", now),
                y: .value("Height", predictor.height(at: now))
            )
            .foregroundStyle(.red)
            .symbolSize(30)
        }
        .chartXScale(domain: windowStart...windowEnd)
        .chartYScale(domain: heightDomain(of: levels))
        .chartXAxis {
            AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3))
        }
    }

    /// Daylight periods clipped to the visible day, for the warm wash.
    private var daylightIntervals: [DateInterval] {
        var intervals: [DateInterval] = []
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: windowStart)
        while day < windowEnd {
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) ?? windowEnd
            switch SunCalculator.day(containing: day, latitude: latitude, longitude: longitude) {
            case let .risesAndSets(rise, set):
                let start = max(rise, windowStart)
                let end = min(set, windowEnd)
                if end > start {
                    intervals.append(DateInterval(start: start, end: end))
                }
            case .alwaysUp:
                let end = min(dayEnd, windowEnd)
                let start = max(day, windowStart)
                if end > start {
                    intervals.append(DateInterval(start: start, end: end))
                }
            case .alwaysDown:
                break
            }
            day = dayEnd
        }
        return intervals
    }

    /// Whole-meter bounds, so the curve sits steady against the axis.
    private func heightDomain(of levels: [TideLevel]) -> ClosedRange<Double> {
        let heights = levels.map(\.heightMeters)
        guard let minHeight = heights.min(), let maxHeight = heights.max() else {
            return 0...1
        }
        let lower = min(0, (minHeight).rounded(.down))
        let upper = max(maxHeight.rounded(.up), lower + 1)
        return lower...upper
    }

    /// Warm sunlit wash on the always-dark watch background.
    private static let daylightFill = Color(red: 1, green: 0.95, blue: 0.8).opacity(0.08)
}
