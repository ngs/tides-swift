import Charts
import SwiftData
import SwiftUI
import TidesCore
import TidesPlatform

/// Tide detail screen: two-day tide curve panned continuously around a
/// center cursor, the tide at the cursor, and the high/low water list.
/// Works fully offline from the saved parameters, and lets the location be
/// renamed, moved or deleted.
struct LocationDetailView: View {
    let location: SavedLocation
    /// Cleared by the parent when this location is deleted.
    @Binding var selection: SavedLocation?

    var body: some View {
        if let parameters = location.parameters {
            LocationDetailContentView(
                location: location,
                parameters: parameters,
                selection: $selection
            )
        } else {
            ContentUnavailableView(
                "Tide Data Unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text("The saved parameters for this location could not be read.")
            )
        }
    }
}

/// Live pan offset of the chart, in seconds of chart time. A separate
/// observable (rather than state on the screen's root view) so the per-frame
/// updates while dragging only invalidate the views that follow the cursor —
/// not the whole list.
@MainActor
@Observable
private final class ChartPanState {
    var offsetSeconds: TimeInterval = 0
}

private struct LocationDetailContentView: View {
    let location: SavedLocation
    @Binding var selection: SavedLocation?
    @Environment(\.modelContext)
    private var modelContext
    @AppStorage(TideDatumSettings.storageKey, store: TideDatumSettings.defaults)
    private var datum: TideDatum = TideDatumSettings.defaultDatum
    @State private var viewModel: LocationDetailViewModel
    @State private var pan = ChartPanState()
    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var isShowingCalendar = false

    init(
        location: SavedLocation,
        parameters: HarmonicParameters,
        selection: Binding<SavedLocation?>
    ) {
        self.location = location
        _selection = selection
        _viewModel = State(initialValue: LocationDetailViewModel(
            parameters: parameters,
            latitude: location.latitude,
            longitude: location.longitude
        ))
    }

    var body: some View {
        List {
            Section {
                CurrentTideRow(viewModel: viewModel, pan: pan)
            } header: {
                Text("Current Tide")
            }

            Section {
                DayNavigator(viewModel: viewModel, pan: pan) {
                    isShowingCalendar = true
                }
                TideChartPane(viewModel: viewModel, pan: pan)
            } header: {
                Text("Tide Chart")
            }

            HighLowSection(viewModel: viewModel, pan: pan)

            Section {
                LabeledContent("Coordinates") {
                    Text(String(format: "%.4f, %.4f", location.latitude, location.longitude))
                        .monospacedDigit()
                }
                LabeledContent("Datum") {
                    Text(viewModel.datum.displayName)
                }
                if let depth = viewModel.parameters.seabedDepthMeters {
                    LabeledContent("Seabed Depth") {
                        Text(heightText(depth))
                            .monospacedDigit()
                    }
                }
                LabeledContent("Fetched") {
                    Text(location.fetchedAt, format: .dateTime)
                }
            } footer: {
                Text(viewModel.datum.explanation)
                    .font(.caption)
            }
        }
        .navigationTitle(location.name)
        .toolbar {
            ToolbarItem {
                Button("Calendar", systemImage: "calendar") {
                    isShowingCalendar = true
                }
                .accessibilityIdentifier(TideAccessibilityID.calendar)
            }
            ToolbarItem {
                Menu("Location Options", systemImage: "ellipsis.circle") {
                    Button("Edit Location", systemImage: "pencil") {
                        isEditing = true
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        isConfirmingDelete = true
                    }
                    // The inline picker renders its own "Datum" header, so
                    // an untitled section just draws the divider above it.
                    Section {
                        DatumPicker()
                    }
                }
                .accessibilityIdentifier(TideAccessibilityID.locationOptions)
            }
        }
        .sheet(isPresented: $isEditing) {
            EditLocationView(location: location)
        }
        .sheet(isPresented: $isShowingCalendar) {
            calendarSheet
        }
        .confirmationDialog(
            "Delete Location",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                delete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(location.name) and its offline tide data will be removed.")
        }
        .onAppear {
            viewModel.setDatum(datum)
            viewModel.reloadIfStale()
        }
        .onChange(of: datum) { _, newDatum in
            viewModel.setDatum(newDatum)
        }
        .onChange(of: location.parametersJSON) { _, _ in
            // The location was moved: recompute from the new parameters and
            // coordinate (sun times depend on the latter).
            if let parameters = location.parameters {
                viewModel.replace(
                    parameters: parameters,
                    latitude: location.latitude,
                    longitude: location.longitude
                )
            }
        }
    }

    private func delete() {
        selection = nil
        modelContext.delete(location)
    }

    /// The month calendar doubles as a date picker: tapping a day recenters
    /// the chart behind the sheet, and Done closes it.
    private var calendarSheet: some View {
        NavigationStack {
            TideCalendarView(
                location: location,
                parameters: viewModel.parameters,
                initialDate: viewModel.centerDate
            ) { day in
                withAnimation {
                    viewModel.center(onDay: day)
                }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isShowingCalendar = false
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 620)
        #endif
    }
}

/// The high and low waters inside the visible window.
///
/// Takes `pan` so the list follows the cursor while the drag is still in
/// flight, like the cursor readout and the day navigator, and lives in its
/// own view so a pan frame invalidates this section alone rather than the
/// whole surrounding `List`.
private struct HighLowSection: View {
    let viewModel: LocationDetailViewModel
    let pan: ChartPanState

    /// `extrema` is chronological, so the window is taken by binary search:
    /// a pan frame stays O(log n + k) as the computed range grows.
    private var visibleExtrema: ArraySlice<LocationDetailViewModel.ExtremumItem> {
        let center = viewModel.centerDate.addingTimeInterval(pan.offsetSeconds)
        let half = viewModel.visibleSpanSeconds / 2
        return viewModel.extrema.slice(
            in: center.addingTimeInterval(-half)...center.addingTimeInterval(half),
            by: \.time
        )
    }

    var body: some View {
        Section("High and Low Tides") {
            if visibleExtrema.isEmpty {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("No high or low tides in this period.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(visibleExtrema) { extremum in
                    extremumRow(extremum)
                }
            }
        }
    }

    private func extremumRow(_ extremum: LocationDetailViewModel.ExtremumItem) -> some View {
        HStack {
            Label {
                Text(extremum.kind == .high ? "High Tide" : "Low Tide")
            } icon: {
                Image(systemName: extremum.kind == .high ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                    .foregroundStyle(extremum.kind == .high ? Color.blue : Color.orange)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(extremum.time, format: .dateTime.weekday().hour().minute())
                Text(heightText(extremum.heightMeters))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
        }
    }
}

/// The tide at the center cursor: height, time and the Moon that day.
/// Shows the present moment until the chart is panned.
private struct CurrentTideRow: View {
    let viewModel: LocationDetailViewModel
    let pan: ChartPanState

    private var centerTime: Date {
        viewModel.centerDate.addingTimeInterval(pan.offsetSeconds)
    }

    var body: some View {
        HStack(alignment: .center) {
            Image(systemName: "water.waves")
                .foregroundStyle(.tint)
            Text(heightText(viewModel.height(at: centerTime)))
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .monospacedDigit()
            tideTrend
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(centerTime, format: .dateTime.hour().minute())
                    .foregroundStyle(.secondary)
                moonSummary
            }
        }
    }

    /// Flood or ebb at the cursor, as an oblique arrow next to the height.
    /// Colors match the high/low marks on the chart.
    private var tideTrend: some View {
        let rising = viewModel.isRising(at: centerTime)
        return Image(systemName: rising ? "arrow.up.forward" : "arrow.down.forward")
            .font(.title3.weight(.semibold))
            .foregroundStyle(rising ? Color.blue : Color.orange)
            .accessibilityLabel(Text(rising ? "Rising Tide" : "Falling Tide"))
    }

    /// The Moon on the centered day: icon, phase name and lunar age, the other
    /// half of a tide table.
    private var moonSummary: some View {
        let moon = MoonPhase(date: centerTime)
        return HStack(spacing: 4) {
            Image(systemName: moon.phase.systemImageName)
            moon.namedAge
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }
}

/// Date readout and the day-step / recenter buttons. The date itself is a
/// button that opens the month calendar to pick a day visually.
private struct DayNavigator: View {
    let viewModel: LocationDetailViewModel
    let pan: ChartPanState
    let openCalendar: () -> Void

    private var centerTime: Date {
        viewModel.centerDate.addingTimeInterval(pan.offsetSeconds)
    }

    var body: some View {
        HStack(spacing: 12) {
            Button("Previous Day", systemImage: "chevron.backward") {
                withAnimation {
                    viewModel.step(byDays: -1)
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)

            Button {
                openCalendar()
            } label: {
                Text(centerTime, format: .dateTime.year().month().day().weekday())
                    .monospacedDigit()
            }
            .buttonStyle(.borderless)
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityLabel(Text("Calendar"))
            // The visible label is the centered date, which the label above
            // would otherwise hide from VoiceOver.
            .accessibilityValue(Text(centerTime, format: .dateTime.year().month().day().weekday()))

            Button("Next Day", systemImage: "chevron.forward") {
                withAnimation {
                    viewModel.step(byDays: 1)
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)

            Button("Now") {
                withAnimation {
                    viewModel.goToNow()
                }
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isCenteredOnNow)
        }
        .lineLimit(1)
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }
}

/// The pannable tide chart plus the sun events strip aligned under its time
/// axis.
private struct TideChartPane: View {
    let viewModel: LocationDetailViewModel
    let pan: ChartPanState
    @Environment(\.colorScheme)
    private var colorScheme
    /// Horizontal insets of the chart's plot area, so the sun events strip
    /// below the chart lines up with the time axis.
    @State private var plotLeadingInset: CGFloat = 0
    @State private var plotTrailingInset: CGFloat = 0
    /// Width of the plot area, which sets the visible span at the fixed
    /// time scale.
    @State private var plotWidth: CGFloat = 0

    /// Fixed time scale: one hour of chart time occupies this many points.
    /// The visible span follows from the width, so a narrow screen shows
    /// fewer hours instead of squeezing whole days in.
    private static let pointsPerHour: CGFloat = 16

    /// The instant at the chart's center, following the finger mid-pan.
    private var centerTime: Date {
        viewModel.centerDate.addingTimeInterval(pan.offsetSeconds)
    }

    /// Seconds the plot can show at the fixed scale (two days until the
    /// first layout pass reports the width).
    private var visibleSeconds: TimeInterval {
        guard plotWidth > 0 else { return 2 * 86_400 }
        return Double(plotWidth / Self.pointsPerHour) * 3_600
    }

    /// The visible window around the (possibly mid-pan) center.
    private var chartDomain: ClosedRange<Date> {
        let half = visibleSeconds / 2
        return centerTime.addingTimeInterval(-half)...centerTime.addingTimeInterval(half)
    }

    /// Fixed plot height, and the chart's total height with the label zone
    /// reserved. Both constant, so axis labels appearing or disappearing
    /// mid-pan can never resize or shift the plot.
    private static let plotHeight: CGFloat = 220
    private static let chartHeight: CGFloat = 244

    var body: some View {
        VStack(spacing: 4) {
            chart
                .frame(height: Self.chartHeight, alignment: .top)
                .padding(.vertical, 8)
                .overlay {
                    if viewModel.isLoading {
                        ProgressView()
                    }
                }
            sunEventsStrip
        }
        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
    }

    private var chart: some View {
        Chart {
            // Day/night bands go first so every other mark draws above them.
            ForEach(shadedIntervals, id: \.start) { interval in
                RectangleMark(
                    xStart: .value("Time", interval.start),
                    xEnd: .value("Time", interval.end)
                )
                .foregroundStyle(shadeFill)
            }

            ForEach(chartLevels, id: \.time) { level in
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

            ForEach(chartExtrema) { extremum in
                PointMark(
                    x: .value("Time", extremum.time),
                    y: .value("Height", extremum.heightMeters)
                )
                .foregroundStyle(extremum.kind == .high ? Color.blue : Color.orange)
                .symbolSize(40)
            }

            // The center cursor the Current Tide section reads out.
            RuleMark(x: .value("Time", centerTime))
                .foregroundStyle(.secondary.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1))
            PointMark(
                x: .value("Time", centerTime),
                y: .value("Height", viewModel.height(at: centerTime))
            )
            .foregroundStyle(.tint)
            .symbolSize(60)

            if isNowVisible {
                RuleMark(x: .value("Now", TideClock.now))
                    .foregroundStyle(.red.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Now")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                if let height = viewModel.currentHeightMeters {
                    PointMark(
                        x: .value("Now", TideClock.now),
                        y: .value("Height", height)
                    )
                    .foregroundStyle(.red)
                    .symbolSize(60)
                }
            }
        }
        .chartXScale(domain: chartDomain)
        .chartYScale(domain: viewModel.heightDomain)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.day().month(), centered: true)
            }
        }
        .chartPlotStyle { plot in
            plot.frame(height: Self.plotHeight)
        }
        .chartYAxisLabel(String(localized: "Tide Height (m)"))
        .chartBackground { proxy in
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        updatePlotInsets(proxy: proxy, geometry: geometry)
                    }
                    .onChange(of: geometry.size) { _, _ in
                        updatePlotInsets(proxy: proxy, geometry: geometry)
                    }
            }
        }
        .chartOverlay { proxy in
            Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .gesture(panGesture(plotWidth: proxy.plotSize.width))
        }
    }

    /// The visible window plus a day of margin on each side: what the chart
    /// draws, so panning and the settle animation never reveal a gap while
    /// the mark count stays small enough to redraw every frame.
    private var drawnRange: ClosedRange<Date> {
        let margin: TimeInterval = 24 * 60 * 60
        let start = chartDomain.lowerBound.addingTimeInterval(-margin)
        let end = chartDomain.upperBound.addingTimeInterval(margin)
        return start...end
    }

    /// The curve points the chart actually draws. Both arrays are in
    /// chronological order, so the window is taken by binary search: the
    /// per-frame cost stays O(log n + k) even as the computed range grows
    /// with panning.
    private var chartLevels: ArraySlice<TideLevel> {
        viewModel.levels.slice(in: drawnRange, by: \.time)
    }

    /// The highs and lows within the drawn window.
    private var chartExtrema: ArraySlice<LocationDetailViewModel.ExtremumItem> {
        viewModel.extrema.slice(in: drawnRange, by: \.time)
    }

    /// Pans the chart through time: the domain follows the finger while the
    /// gesture is active and stays exactly where it is released — no
    /// momentum, no snapping. The cursor is continuous.
    private func panGesture(plotWidth: CGFloat) -> some Gesture {
        let visibleSeconds = chartDomain.upperBound.timeIntervalSince(chartDomain.lowerBound)
        return DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard plotWidth > 0 else { return }
                pan.offsetSeconds = clampedPanOffset(
                    -Double(value.translation.width) / Double(plotWidth) * visibleSeconds
                )
            }
            .onEnded { _ in
                settlePan()
            }
    }

    /// Keeps the panned domain inside the computed prediction range.
    private func clampedPanOffset(_ seconds: TimeInterval) -> TimeInterval {
        let minOffset = viewModel.rangeStart.timeIntervalSince(viewModel.windowStart)
        let maxOffset = viewModel.rangeEnd.timeIntervalSince(viewModel.windowEnd)
        return min(max(seconds, minOffset), maxOffset)
    }

    /// Commits the cursor where the pan was released, rounded to the whole
    /// minute so the readout is clean. Committing the center and
    /// compensating the offset in the same update keeps the domain
    /// continuous; only the sub-minute rounding is animated.
    private func settlePan() {
        let landing = viewModel.centerDate.addingTimeInterval(pan.offsetSeconds)
        let roundedLanding = Date(
            timeIntervalSinceReferenceDate: (landing.timeIntervalSinceReferenceDate / 60).rounded() * 60
        )
        let committed = pan.offsetSeconds + roundedLanding.timeIntervalSince(landing)
        viewModel.pan(bySeconds: committed)
        pan.offsetSeconds -= committed
        withAnimation(.snappy) {
            pan.offsetSeconds = 0
        }
    }

    /// Sunrises and sunsets of the visible window, laid out under the chart
    /// at the horizontal position of their time.
    private var sunEventsStrip: some View {
        GeometryReader { geometry in
            ForEach(visibleSunEvents) { event in
                sunEventLabel(event)
                    .position(
                        x: geometry.size.width * xFraction(of: event.time),
                        y: geometry.size.height / 2
                    )
            }
        }
        .frame(height: 24)
        .padding(.leading, plotLeadingInset)
        .padding(.trailing, plotTrailingInset)
        .clipped()
    }

    /// The sunrises and sunsets inside the visible window. `sunEvents` is
    /// chronological (built day by day in `rangeData`), so this takes the same
    /// binary-searched slice as the curve rather than filtering the whole
    /// array on every pan frame.
    private var visibleSunEvents: ArraySlice<LocationDetailViewModel.SunEvent> {
        viewModel.sunEvents.slice(in: chartDomain, by: \.time)
    }

    private func sunEventLabel(_ event: LocationDetailViewModel.SunEvent) -> some View {
        HStack(spacing: 4) {
            Image(systemName: event.kind == .sunrise ? "sunrise.fill" : "sunset.fill")
                .foregroundStyle(event.kind == .sunrise ? Color.orange : Color.indigo)
            Text(event.time, format: .dateTime.hour().minute())
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .monospacedDigit()
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(event.kind == .sunrise ? "Sunrise" : "Sunset"))
        .accessibilityValue(Text(event.time, format: .dateTime.hour().minute()))
    }

    /// Horizontal position of a time within the visible window, 0...1.
    private func xFraction(of date: Date) -> CGFloat {
        let total = chartDomain.upperBound.timeIntervalSince(chartDomain.lowerBound)
        guard total > 0 else { return 0 }
        return CGFloat(date.timeIntervalSince(chartDomain.lowerBound) / total)
    }

    /// Records where the plot area sits inside the chart — for the sun
    /// events strip alignment and for the visible span — and tells the view
    /// model how much time the plot now shows.
    private func updatePlotInsets(proxy: ChartProxy, geometry: GeometryProxy) {
        guard let anchor = proxy.plotFrame else { return }
        let frame = geometry[anchor]
        plotLeadingInset = frame.minX
        plotTrailingInset = geometry.size.width - frame.maxX
        plotWidth = frame.width
        viewModel.setVisibleSpan(visibleSeconds)
    }

    /// Day always reads brighter than night: on a light background the
    /// night intervals are darkened, but on a dark background any overlay
    /// lightens, so there the *daylight* intervals get a warm wash instead.
    private var shadedIntervals: [DateInterval] {
        colorScheme == .dark ? viewModel.daylight : viewModel.nightIntervals
    }

    private var shadeFill: Color {
        colorScheme == .dark ? Self.daylightFill : Self.nightFill
    }

    /// Dark, bluish night for light backgrounds.
    private static let nightFill = Color.indigo.opacity(0.14)
    /// Warm sunlit wash for dark backgrounds.
    private static let daylightFill = Color(red: 1, green: 0.95, blue: 0.8).opacity(0.08)

    private var isNowVisible: Bool {
        chartDomain.contains(TideClock.now)
    }
}

private extension Array {
    /// The elements whose time falls inside `range`, for an array already in
    /// chronological order. Binary search, so a pan frame costs
    /// O(log n + k) no matter how far the computed range has grown.
    func slice(in range: ClosedRange<Date>, by time: (Element) -> Date) -> ArraySlice<Element> {
        let start = partitionPoint { time($0) >= range.lowerBound }
        let end = partitionPoint { time($0) > range.upperBound }
        return self[start..<Swift.max(start, end)]
    }

    /// The first index whose element satisfies `predicate`, for an array
    /// partitioned so that every later element satisfies it too.
    private func partitionPoint(_ predicate: (Element) -> Bool) -> Int {
        var low = startIndex
        var high = endIndex
        while low < high {
            let mid = low + (high - low) / 2
            if predicate(self[mid]) {
                high = mid
            } else {
                low = mid + 1
            }
        }
        return low
    }
}

/// Meters with two decimals, e.g. "2.20 m".
private func heightText(_ meters: Double) -> String {
    Measurement(value: meters, unit: UnitLength.meters)
        .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(2))))
}
