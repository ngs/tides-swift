import SwiftUI

/// Input-blocking overlay shown while harmonic parameters download: a dimmed
/// backdrop with a centered progress indicator. Used by the add and edit
/// location flows.
struct FetchingParametersOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.2)
                .ignoresSafeArea()
            ProgressView("Fetching parameters…")
                .padding(20)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        // Swallow touches so the map cannot be moved mid-download.
        .contentShape(Rectangle())
    }
}
