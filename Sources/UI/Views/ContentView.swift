import SwiftUI
import TidesCore
import TidesPlatform

/// Main content view that combines map and tide graph
public struct ContentView: View {
  @StateObject private var viewModel = TidesViewModel()

  public init() {}

  public var body: some View {
    GeometryReader { geometry in
      if geometry.size.width > 600 {
        // iPad/Mac layout: Side-by-side
        HStack(spacing: 0) {
          // Map on the left
          TidesMapView(position: $viewModel.mapPosition) { newPosition in
            viewModel.handlePositionChange(newPosition)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)

          Divider()

          // Graph on the right
          ScrollView {
            TideGraphView(
              predictions: viewModel.predictions,
              highs: viewModel.highs,
              lows: viewModel.lows,
              loading: viewModel.loading,
              error: viewModel.error,
              locationName: viewModel.locationName,
              selectedDate: $viewModel.selectedDate
            )
          }
          .frame(width: 400)
          .background(.background)
        }
      } else {
        // iPhone layout: Map on top, bottom sheet
        ZStack(alignment: .bottom) {
          // Map fills the screen
          TidesMapView(position: $viewModel.mapPosition) { newPosition in
            viewModel.handlePositionChange(newPosition)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .ignoresSafeArea(.all, edges: .top)

          // Bottom sheet with graph
          VStack(spacing: 0) {
            // Drag handle
            RoundedRectangle(cornerRadius: 2.5)
              .fill(.secondary.opacity(0.5))
              .frame(width: 40, height: 5)
              .padding(.top, 8)
              .padding(.bottom, 12)

            ScrollView {
              TideGraphView(
                predictions: viewModel.predictions,
                highs: viewModel.highs,
                lows: viewModel.lows,
                loading: viewModel.loading,
                error: viewModel.error,
                locationName: viewModel.locationName,
                selectedDate: $viewModel.selectedDate
              )
            }
          }
          .frame(height: geometry.size.height * 0.5)
          .background(.regularMaterial)
          .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
          .shadow(radius: 10)
        }
      }
    }
  }
}

#Preview("iPhone") {
  ContentView()
    .previewDevice(PreviewDevice(rawValue: "iPhone 16 Pro"))
}

#Preview("iPad") {
  ContentView()
    .previewDevice(PreviewDevice(rawValue: "iPad Pro (12.9-inch)"))
}
