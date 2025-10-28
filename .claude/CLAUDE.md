# Tides Development Guide

## Project Overview

A native SwiftUI application that displays tide predictions on an interactive map using Apple Maps and MapKit. This is the Swift counterpart to the web-based tides-web application.

## Tech Stack

- **Framework**: SwiftUI
- **Maps**: MapKit (Apple Maps)
- **Charting**: Swift Charts
- **Build Tool**: Tuist + Swift Package Manager
- **Code Quality**: SwiftLint
- **Deployment**: TestFlight / App Store
- **CI/CD**: GitHub Actions

## Project Structure

Based on the LiveClock architecture:

```
Tides/
├── Sources/
│   ├── App/           # App entry point (TidesApp.swift)
│   ├── Core/          # Business logic
│   │   ├── Models/    # TideModels.swift
│   │   └── API/       # TidesAPIClient.swift
│   ├── Platform/      # Platform-specific implementations
│   │   ├── Storage/   # LastPositionStorage.swift
│   │   └── Location/  # GeocodingService.swift
│   └── UI/            # SwiftUI views
│       ├── Views/     # ContentView, TidesMapView, TideGraphView
│       └── ViewModels/# TidesViewModel
├── Resources/         # Assets, entitlements
├── Tests/             # Unit tests
└── .github/workflows/ # CI/CD
```

## Key Features

1. **MapKit Integration**: Apple Maps with reverse geocoding
2. **Tide API Client**: Fetches data from https://api.tides.ngs.io/
3. **Responsive Layout**:
   - iPhone: Bottom sheet
   - iPad/Mac: Sidebar
4. **State Persistence**: UserDefaults for last position
5. **Swift Charts**: Tide graph visualization

## Development Guidelines

- **All comments and documentation MUST be in English**
- Follow SwiftLint rules (see .swiftlint.yml)
- Use Swift 6 with strict concurrency
- Use actors for thread-safe data access
- Prefer @MainActor for UI-related code
- **NEVER include AI signatures or "Generated with Claude Code" in commit messages**

## Building

```bash
# Generate Xcode project
tuist generate

# Open workspace
open Tides.xcworkspace
```

## Testing

```bash
# Via Tuist
tuist test

# Via SPM
swift test
```
