import Foundation

/// The slice of `NSUbiquitousKeyValueStore` the datum sync needs, so tests
/// can substitute an in-memory store.
public protocol UbiquitousKeyValueStoring: AnyObject {
    func string(forKey aKey: String) -> String?
    func set(_ anObject: Any?, forKey aKey: String)
    @discardableResult
    func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: UbiquitousKeyValueStoring {}

/// Mirrors the datum preference between iCloud's key-value store and the
/// local defaults suite, so a selection made on one device follows the user
/// everywhere — including the watch, which shares no App Group with the
/// phone (App Groups are same-device only).
///
/// The local suite stays the single source of truth for the UI: the
/// `@AppStorage` bindings and `TideDatumSettings.current` are untouched.
/// This object only copies values across when one side changes; identical
/// values are never rewritten, which is also what stops the two observers
/// from feeding each other forever. Conflicts resolve to last-writer-wins,
/// which is plenty for a single toggle.
///
/// Started once at app launch (the widget cannot use the key-value store
/// from an extension; it keeps reading the App Group suite the app writes).
/// Without the `ubiquity-kvstore-identifier` entitlement or an iCloud
/// account the store just never delivers values and the app stays local.
@MainActor
public final class TideDatumSync {
    private let ubiquitous: UbiquitousKeyValueStoring
    private let defaults: UserDefaults
    private let key: String
    /// Mutated on the main actor only; the read in `deinit` happens when no
    /// other reference exists, hence `nonisolated(unsafe)`.
    nonisolated(unsafe) private var observers: [any NSObjectProtocol] = []

    public init(
        ubiquitous: UbiquitousKeyValueStoring = NSUbiquitousKeyValueStore.default,
        defaults: UserDefaults = TideDatumSettings.defaults,
        key: String = TideDatumSettings.storageKey
    ) {
        self.ubiquitous = ubiquitous
        self.defaults = defaults
        self.key = key
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Starts mirroring: pulls the iCloud value once, then follows external
    /// iCloud changes and local edits. Calling it again is a no-op.
    public func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: ubiquitous as? NSUbiquitousKeyValueStore,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pullFromICloud()
            }
        })
        observers.append(center.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pushToICloud()
            }
        })
        ubiquitous.synchronize()
        pullFromICloud()
        pushToICloud()
    }

    /// iCloud → local, dropping values that do not decode to a datum.
    func pullFromICloud() {
        guard
            let raw = ubiquitous.string(forKey: key),
            TideDatum(rawValue: raw) != nil,
            raw != defaults.string(forKey: key)
        else { return }
        defaults.set(raw, forKey: key)
    }

    /// Local → iCloud, dropping values that do not decode to a datum so a
    /// corrupted local suite cannot pollute the shared store. Never clears
    /// the iCloud value: the local suite is only unset before the user has
    /// ever picked a datum.
    func pushToICloud() {
        guard
            let raw = defaults.string(forKey: key),
            TideDatum(rawValue: raw) != nil,
            raw != ubiquitous.string(forKey: key)
        else { return }
        ubiquitous.set(raw, forKey: key)
        ubiquitous.synchronize()
    }
}
