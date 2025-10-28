import SwiftUI
import Charts
import TidesCore

/// View for displaying tide predictions as a chart
public struct TideGraphView: View {
  let predictions: [TidePrediction]
  let highs: [TideExtreme]
  let lows: [TideExtreme]
  let loading: Bool
  let error: String?
  let locationName: String
  @Binding var selectedDate: Date

  private let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter
  }()

  private let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return formatter
  }()

  public init(
    predictions: [TidePrediction],
    highs: [TideExtreme],
    lows: [TideExtreme],
    loading: Bool,
    error: String?,
    locationName: String,
    selectedDate: Binding<Date>
  ) {
    self.predictions = predictions
    self.highs = highs
    self.lows = lows
    self.loading = loading
    self.error = error
    self.locationName = locationName
    self._selectedDate = selectedDate
  }

  public var body: some View {
    VStack(spacing: 16) {
      // Header
      VStack(spacing: 8) {
        Text(locationName)
          .font(.headline)
          .foregroundStyle(.primary)

        DatePicker(
          "Date",
          selection: $selectedDate,
          displayedComponents: .date
        )
        .datePickerStyle(.compact)
        .labelsHidden()
      }
      .padding(.horizontal)

      // Content
      if loading {
        ProgressView("Loading tide data...")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let error {
        VStack(spacing: 12) {
          Image(systemName: "exclamationmark.triangle")
            .font(.largeTitle)
            .foregroundStyle(.red)
          Text("Error")
            .font(.headline)
          Text(error)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
      } else if predictions.isEmpty {
        VStack(spacing: 12) {
          Image(systemName: "chart.line.uptrend.xyaxis")
            .font(.largeTitle)
            .foregroundStyle(.secondary)
          Text("No tide data available")
            .font(.headline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        chartView
      }
    }
    .padding(.vertical)
  }

  @ViewBuilder
  private var chartView: some View {
    VStack(alignment: .leading, spacing: 8) {
      // Chart
      Chart {
        // Tide predictions line
        ForEach(predictions) { prediction in
          if let date = prediction.date, let depth = prediction.depthM {
            LineMark(
              x: .value("Time", date),
              y: .value("Depth", depth)
            )
            .foregroundStyle(.blue)
            .interpolationMethod(.catmullRom)
          }
        }

        // High tide markers
        ForEach(highs) { high in
          if let date = high.date {
            PointMark(
              x: .value("Time", date),
              y: .value("Depth", high.depthM)
            )
            .foregroundStyle(.red)
            .symbol(.circle)
            .symbolSize(100)

            RuleMark(x: .value("Time", date))
              .foregroundStyle(.red.opacity(0.3))
              .lineStyle(StrokeStyle(dash: [5, 5]))
          }
        }

        // Low tide markers
        ForEach(lows) { low in
          if let date = low.date {
            PointMark(
              x: .value("Time", date),
              y: .value("Depth", low.depthM)
            )
            .foregroundStyle(.green)
            .symbol(.circle)
            .symbolSize(100)

            RuleMark(x: .value("Time", date))
              .foregroundStyle(.green.opacity(0.3))
              .lineStyle(StrokeStyle(dash: [5, 5]))
          }
        }
      }
      .chartXAxis {
        AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
          AxisGridLine()
          AxisTick()
          AxisValueLabel(format: .dateTime.hour())
        }
      }
      .chartYAxis {
        AxisMarks { value in
          AxisGridLine()
          AxisTick()
          AxisValueLabel {
            if let depth = value.as(Double.self) {
              Text("\(depth, specifier: "%.1f")m")
            }
          }
        }
      }
      .frame(height: 250)
      .padding(.horizontal)

      // Legend
      HStack(spacing: 20) {
        Label("High Tide", systemImage: "circle.fill")
          .foregroundStyle(.red)
          .font(.caption)

        Label("Low Tide", systemImage: "circle.fill")
          .foregroundStyle(.green)
          .font(.caption)
      }
      .padding(.horizontal)

      // Extremes list
      if !highs.isEmpty || !lows.isEmpty {
        Divider()
          .padding(.vertical, 8)

        VStack(alignment: .leading, spacing: 12) {
          if !highs.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
              Text("High Tides")
                .font(.subheadline)
                .fontWeight(.semibold)

              ForEach(highs) { high in
                if let date = high.date {
                  HStack {
                    Text(timeFormatter.string(from: date))
                      .font(.caption)
                      .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(high.depthM, specifier: "%.2f")m")
                      .font(.caption)
                      .fontWeight(.medium)
                  }
                }
              }
            }
          }

          if !lows.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
              Text("Low Tides")
                .font(.subheadline)
                .fontWeight(.semibold)

              ForEach(lows) { low in
                if let date = low.date {
                  HStack {
                    Text(timeFormatter.string(from: date))
                      .font(.caption)
                      .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(low.depthM, specifier: "%.2f")m")
                      .font(.caption)
                      .fontWeight(.medium)
                  }
                }
              }
            }
          }
        }
        .padding(.horizontal)
      }
    }
  }
}

#Preview {
  @Previewable @State var selectedDate = Date()

  let predictions = [
    TidePrediction(time: "2024-10-28T00:00:00Z", heightM: 1.5, depthM: 2.5),
    TidePrediction(time: "2024-10-28T06:00:00Z", heightM: -0.5, depthM: 0.5),
    TidePrediction(time: "2024-10-28T12:00:00Z", heightM: 1.8, depthM: 2.8),
    TidePrediction(time: "2024-10-28T18:00:00Z", heightM: -0.3, depthM: 0.7),
  ]

  let highs = [
    TideExtreme(time: "2024-10-28T06:15:00Z", depthM: 2.85),
    TideExtreme(time: "2024-10-28T18:30:00Z", depthM: 2.92),
  ]

  let lows = [
    TideExtreme(time: "2024-10-28T00:45:00Z", depthM: 0.45),
    TideExtreme(time: "2024-10-28T12:20:00Z", depthM: 0.52),
  ]

  TideGraphView(
    predictions: predictions,
    highs: highs,
    lows: lows,
    loading: false,
    error: nil,
    locationName: "Tokyo Bay",
    selectedDate: $selectedDate
  )
}
