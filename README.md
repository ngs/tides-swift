# Tides

A native iOS, iPadOS, macOS, and visionOS application for viewing tide predictions on an interactive map.

## Features

### Core Functionality
- **Interactive Map**: Apple Maps integration with drag functionality
- **Tide Predictions**: Real-time tide data from https://api.tides.ngs.io/
- **Reverse Geocoding**: Location names using MapKit
- **Tide Graphs**: Visual tide predictions using Swift Charts
- **Responsive Layout**:
  - iPhone: Bottom sheet overlay
  - iPad/Mac: Side-by-side layout
- **State Persistence**: Last viewed location saved to UserDefaults

### Platform Support

| Platform | Minimum Version | Features |
|----------|----------------|----------|
| iOS | 18.0+ | Full feature set with MapKit and Charts |
| iPadOS | 18.0+ | Optimized for larger screens with sidebar layout |
| macOS | 15.0+ | Native Mac app with full functionality |
| visionOS | 2.0+ | Spatial computing support |

## Development

### Prerequisites
- Xcode 16.0 or later
- macOS Sequoia 15.0 or later
- [Tuist](https://tuist.io) (recommended) or Swift Package Manager

### Building the Project

#### Option A: Using Tuist (Recommended)
```bash
# Generate Xcode project
tuist generate

# Open the workspace
open Tides.xcworkspace
```

#### Option B: Using Swift Package Manager
1. Open `Package.swift` in Xcode
2. Add dependencies to Core, Platform, and UI package products

### Project Structure
```
Tides/
├── Sources/
│   ├── App/           # Main app entry point
│   ├── Core/          # Business logic (API client, models)
│   ├── Platform/      # Platform-specific implementations (storage, location)
│   └── UI/            # SwiftUI views and view models
├── Resources/         # Assets and configurations
├── Tests/             # Unit tests
└── .github/           # CI/CD workflows
```

## Architecture

### Modules

- **Core**: Business logic and data models
  - `TideModels.swift`: Data structures for tide predictions
  - `TidesAPIClient.swift`: API client for fetching tide data

- **Platform**: Platform-specific implementations
  - `LastPositionStorage.swift`: UserDefaults-based persistence
  - `GeocodingService.swift`: MapKit reverse geocoding

- **UI**: SwiftUI views and view models
  - `ContentView.swift`: Main responsive layout
  - `TidesMapView.swift`: MapKit integration
  - `TideGraphView.swift`: Charts-based tide graph
  - `TidesViewModel.swift`: State management

## API Integration

Base URL: `https://api.tides.ngs.io/`

Endpoints:
- `GET /v1/tides/predictions?lat={lat}&lon={lon}&start={start}&end={end}&interval=30m&source=fes`
- `GET /v1/constituents`
- `GET /healthz`

## Configuration

### App Settings
- **Bundle ID**: `io.ngs.Tides`
- **Display Name**: Tides
- **Team ID**: Configured via Tuist environment

### Build Configurations
- **Debug**: Development builds with debugging enabled
- **Release**: Production builds with optimizations

## Development Tools

- **SwiftLint**: Code style and quality enforcement
- **Tuist**: Xcode project generation
- **Swift 6**: Latest Swift language features with strict concurrency

## Testing

```bash
# Run tests via Tuist
tuist test

# Run Swift Package Manager tests
swift test
```

## Deployment

### TestFlight Beta
To be configured

## Privacy

Tides respects your privacy:
- Minimal data collection
- No analytics tracking
- API requests only for tide data
- Location data stays on device (used only for reverse geocoding)

## License

Copyright © 2024 Atsushi Nagase. All rights reserved.

---

Built with SwiftUI, MapKit, and Charts
