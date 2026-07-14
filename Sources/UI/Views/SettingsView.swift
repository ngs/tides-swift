import SwiftData
import SwiftUI
import TidesCore
import TidesPlatform

/// App-wide settings: the datum heights are measured from, a refresh for the
/// offline tide parameters, support links and app information. Presented as a
/// sheet from the sidebar on iOS and visionOS, and as the standard Settings
/// scene (⌘,) on macOS.
public struct SettingsView: View {
    @AppStorage(TideDatumSettings.storageKey, store: TideDatumSettings.defaults)
    private var datum: TideDatum = TideDatumSettings.defaultDatum
    @Query(sort: [SortDescriptor(\SavedLocation.sortOrder), SortDescriptor(\SavedLocation.createdAt)])
    private var locations: [SavedLocation]
    @State private var refresh: ParametersRefreshViewModel

    public init(client: any TidesAPIClientProtocol = TidesAPIClient()) {
        _refresh = State(initialValue: ParametersRefreshViewModel(client: client))
    }

    public var body: some View {
        Form {
            Section {
                // The section title carries the "Datum" label; the inline
                // picker's own would render as a plain row above the options.
                DatumPicker()
                    .labelsHidden()
            } header: {
                Text("Datum")
            } footer: {
                Text(datum.explanation)
                    .font(.caption)
            }

            Section {
                refreshRow
            } header: {
                Text("Tide Parameters")
            } footer: {
                Text("Downloads the harmonic parameters of every saved location again. They are fetched once when a location is added, so a refresh is what picks up a later improvement to the tidal model.")
                    .font(.caption)
            }

            Section("Support") {
                link(
                    "Report an Issue",
                    systemImage: "ladybug",
                    urlString: "https://github.com/ngs/tides-swift/issues"
                )
                link(
                    "Developer's Website",
                    systemImage: "globe",
                    urlString: "https://ngs.io"
                )
            }

            Section {
                LabeledContent("Version") {
                    Text(versionText)
                        .monospacedDigit()
                }
                link(
                    "App Source Code",
                    systemImage: "chevron.left.forwardslash.chevron.right",
                    urlString: "https://github.com/ngs/tides-swift"
                )
                link(
                    "API Source Code",
                    systemImage: "server.rack",
                    urlString: "https://github.com/ngs/tides-api"
                )
                link(
                    "License (MIT)",
                    systemImage: "doc.text",
                    urlString: "https://github.com/ngs/tides-swift/blob/master/LICENSE"
                )
                link(
                    "FES2014/2022 Tidal Model (AVISO+)",
                    systemImage: "water.waves",
                    urlString: "https://www.aviso.altimetry.fr/en/data/products/auxiliary-products/global-tide-fes.html"
                )
            } header: {
                Text("About")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tide predictions are computed offline from the FES2014/2022 tidal model.")
                    // Prescribed word for word by clause 5.2 of the License to Use
                    // AVISO+ Products, which the FES tidal model ships under: every
                    // product derived from it must carry this exact sentence. It is
                    // a credit line, not UI copy — a translation or a paraphrase
                    // does not satisfy the clause — so it stays out of the String
                    // Catalog and reads the same in every locale.
                    Text(verbatim: "Generated using AVISO+ Products")
                }
                .font(.caption)
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        #endif
        .alert(
            "Error",
            isPresented: Binding(
                get: { refresh.errorMessage != nil },
                set: { if !$0 { refresh.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(refresh.errorMessage ?? "")
        }
    }

    /// The refresh button, with the count of locations already done alongside
    /// it: the walk is serial and a slow network makes it a visible wait.
    private var refreshRow: some View {
        Button {
            Task {
                await refresh.refresh(locations)
            }
        } label: {
            HStack {
                Label("Refresh All Parameters", systemImage: "arrow.clockwise")
                if let progress = refresh.progress {
                    Spacer()
                    Text("\(progress.completed) of \(progress.total)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .disabled(locations.isEmpty || refresh.isRefreshing)
    }

    @ViewBuilder
    private func link(
        _ titleKey: LocalizedStringKey,
        systemImage: String,
        urlString: String
    ) -> some View {
        if let url = URL(string: urlString) {
            Link(destination: url) {
                Label(titleKey, systemImage: systemImage)
            }
        }
    }

    /// Marketing version plus build number, e.g. "1.2 (34)".
    private var versionText: String {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"
        return "\(version) (\(build))"
    }
}
