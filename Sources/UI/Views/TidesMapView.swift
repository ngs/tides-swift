import SwiftUI
import MapKit
import TidesCore

/// SwiftUI wrapper for MapKit map view
public struct TidesMapView: View {
  @Binding var position: MapPosition
  let onPositionChange: (MapPosition) -> Void

  @State private var cameraPosition: MapCameraPosition
  @State private var region: MKCoordinateRegion

  public init(
    position: Binding<MapPosition>,
    onPositionChange: @escaping (MapPosition) -> Void
  ) {
    self._position = position
    self.onPositionChange = onPositionChange

    let initialRegion = MKCoordinateRegion(
      center: CLLocationCoordinate2D(
        latitude: position.wrappedValue.lat,
        longitude: position.wrappedValue.lon
      ),
      span: MKCoordinateSpan(
        latitudeDelta: 0.1,
        longitudeDelta: 0.1
      )
    )

    self._cameraPosition = State(initialValue: .region(initialRegion))
    self._region = State(initialValue: initialRegion)
  }

  public var body: some View {
    Map(position: $cameraPosition) {
      // Add a marker at the center
      Marker("", coordinate: CLLocationCoordinate2D(
        latitude: position.lat,
        longitude: position.lon
      ))
      .tint(.blue)
    }
    .mapStyle(.standard)
    .onChange(of: cameraPosition) { _, newValue in
      handleCameraChange(newValue)
    }
  }

  private func handleCameraChange(_ newPosition: MapCameraPosition) {
    // Extract region from camera position
    if case .region(let newRegion) = newPosition {
      let newMapPosition = MapPosition(
        lat: newRegion.center.latitude,
        lon: newRegion.center.longitude,
        zoom: calculateZoom(from: newRegion.span)
      )

      if newMapPosition != position {
        position = newMapPosition
        onPositionChange(newMapPosition)
      }
    }
  }

  private func calculateZoom(from span: MKCoordinateSpan) -> Double {
    // Approximate zoom level from span
    // This is a rough approximation
    let latDelta = span.latitudeDelta
    let zoom = log2(360.0 / latDelta)
    return max(0, min(20, zoom))
  }
}

#Preview {
  @Previewable @State var position = MapPosition.default

  TidesMapView(position: $position) { newPosition in
    position = newPosition
  }
}
