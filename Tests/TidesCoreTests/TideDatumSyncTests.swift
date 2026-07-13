import Foundation
import Testing
import TidesCore

/// The datum preference mirrors between the local defaults suite and
/// iCloud's key-value store; these tests drive the mirroring with an
/// in-memory store standing in for iCloud.
@MainActor
struct TideDatumSyncTests {
    private final class FakeUbiquitousStore: UbiquitousKeyValueStoring {
        var storage: [String: String] = [:]
        private(set) var synchronizeCount = 0

        func string(forKey aKey: String) -> String? {
            storage[aKey]
        }

        func set(_ anObject: Any?, forKey aKey: String) {
            storage[aKey] = anObject as? String
        }

        func synchronize() -> Bool {
            synchronizeCount += 1
            return true
        }
    }

    private let key = TideDatumSettings.storageKey

    /// A throwaway suite: notifications still fire, nothing persists between
    /// tests.
    private func makeDefaults() throws -> UserDefaults {
        let name = "TideDatumSyncTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// The observers hop to the main actor with a `Task`; yielding lets
    /// those enqueued mirror jobs run before the assertions.
    private func drainMainActor() async {
        for _ in 0..<5 {
            await Task.yield()
        }
    }

    @Test
    func startPullsTheICloudValueIntoTheLocalSuite() throws {
        let store = FakeUbiquitousStore()
        store.storage[key] = TideDatum.meanSeaLevel.rawValue
        let defaults = try makeDefaults()
        let sync = TideDatumSync(ubiquitous: store, defaults: defaults, key: key)

        sync.start()

        #expect(defaults.string(forKey: key) == TideDatum.meanSeaLevel.rawValue)
    }

    @Test
    func localChangesPushToICloud() async throws {
        let store = FakeUbiquitousStore()
        let defaults = try makeDefaults()
        let sync = TideDatumSync(ubiquitous: store, defaults: defaults, key: key)
        sync.start()

        // What @AppStorage does when the user flips the datum picker.
        defaults.set(TideDatum.meanSeaLevel.rawValue, forKey: key)
        await drainMainActor()

        #expect(store.storage[key] == TideDatum.meanSeaLevel.rawValue)
    }

    @Test
    func externalICloudChangesReachTheLocalSuite() async throws {
        let store = FakeUbiquitousStore()
        let defaults = try makeDefaults()
        defaults.set(TideDatum.chartDatum.rawValue, forKey: key)
        let sync = TideDatumSync(ubiquitous: store, defaults: defaults, key: key)
        sync.start()

        store.storage[key] = TideDatum.meanSeaLevel.rawValue
        NotificationCenter.default.post(
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: nil
        )
        await drainMainActor()

        #expect(defaults.string(forKey: key) == TideDatum.meanSeaLevel.rawValue)
    }

    @Test
    func garbageInICloudIsIgnored() throws {
        let store = FakeUbiquitousStore()
        store.storage[key] = "not-a-datum"
        let defaults = try makeDefaults()
        defaults.set(TideDatum.chartDatum.rawValue, forKey: key)
        let sync = TideDatumSync(ubiquitous: store, defaults: defaults, key: key)

        sync.start()

        #expect(defaults.string(forKey: key) == TideDatum.chartDatum.rawValue)
        // The valid local value overwrites the garbage on the way back.
        #expect(store.storage[key] == TideDatum.chartDatum.rawValue)
    }

    @Test
    func garbageInTheLocalSuiteIsNotPushed() async throws {
        let store = FakeUbiquitousStore()
        let defaults = try makeDefaults()
        let sync = TideDatumSync(ubiquitous: store, defaults: defaults, key: key)
        sync.start()

        defaults.set("not-a-datum", forKey: key)
        await drainMainActor()

        #expect(store.storage[key] == nil)
    }

    /// The two observers must not feed each other: a pull writes the same
    /// value back, which the push observer sees and drops as identical.
    @Test
    func mirroringSettlesWithoutRewriting() async throws {
        let store = FakeUbiquitousStore()
        store.storage[key] = TideDatum.meanSeaLevel.rawValue
        let defaults = try makeDefaults()
        let sync = TideDatumSync(ubiquitous: store, defaults: defaults, key: key)
        sync.start()
        await drainMainActor()
        let settled = store.synchronizeCount

        defaults.set(TideDatum.meanSeaLevel.rawValue, forKey: key)
        await drainMainActor()

        // Same value: no push, no extra synchronize.
        #expect(store.synchronizeCount == settled)
    }
}
