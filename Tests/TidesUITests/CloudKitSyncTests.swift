import Foundation
import SwiftData
import Testing
import TidesCore
import TidesPlatform

/// CloudKit mirroring puts hard requirements on the SwiftData schema and on the
/// container setup. These tests pin both down: the schema stays mirrorable, and
/// the container still opens where CloudKit is unavailable (unsigned test
/// bundles, simulators without an iCloud account, previews).
@Suite("CloudKit compatibility")
struct CloudKitSchemaTests {
    private var entity: Schema.Entity {
        let schema = Schema([SavedLocation.self])
        guard let entity = schema.entities.first(where: { $0.name == "SavedLocation" }) else {
            Issue.record("SavedLocation is missing from the schema")
            return Schema.Entity("SavedLocation")
        }
        return entity
    }

    /// CloudKit can only mirror attributes it is able to materialize before the
    /// remote record arrives, so each one must be optional or have a default.
    @Test
    func everyAttributeIsOptionalOrHasADefault() {
        let attributes = entity.attributes
        #expect(!attributes.isEmpty)
        for attribute in attributes {
            #expect(
                attribute.isOptional || attribute.defaultValue != nil,
                "\(attribute.name) has neither a default value nor an optional type"
            )
        }
    }

    /// Every property the app actually persists is covered by the check above.
    @Test
    func attributesCoverEveryPersistedProperty() {
        let names = Set(entity.attributes.map(\.name))
        #expect(
            names.isSuperset(of: [
                "name",
                "latitude",
                "longitude",
                "parametersJSON",
                "fetchedAt",
                "createdAt",
                "sortOrder"
            ])
        )
    }

    /// Unique constraints and relationships are rejected by CloudKit mirroring.
    @Test
    func schemaUsesNoUniqueConstraintsOrRelationships() {
        #expect(entity.uniquenessConstraints.isEmpty)
        #expect(entity.relationships.isEmpty)
        #expect(entity.attributes.allSatisfy { !$0.isUnique })
    }

    /// The defaults exist for CloudKit, not for callers: the initializer still
    /// decides every value.
    @Test
    func initializerOverridesTheCloudKitDefaults() throws {
        let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let location = SavedLocation(
            name: "Enoshima",
            latitude: 35.3,
            longitude: 139.48,
            parametersJSON: Data([0x7B, 0x7D]),
            fetchedAt: fetchedAt,
            createdAt: fetchedAt,
            sortOrder: 3
        )
        #expect(location.name == "Enoshima")
        #expect(location.latitude == 35.3)
        #expect(location.fetchedAt == fetchedAt)
        #expect(location.sortOrder == 3)
    }
}

@Suite("CloudKit container fallback")
struct TidesModelContainerFallbackTests {
    /// Tests never have the iCloud entitlement, so mirroring must be off.
    @Test
    func cloudKitIsUnavailableInTests() {
        #expect(TidesCloudKit.isAvailable == false)
        #expect(TidesCloudKit.containerIdentifier == "iCloud.io.ngs.Tides")
    }

    /// CloudKit is tried first, then the plain stores, so a missing entitlement
    /// or a signed-out account only costs a retry.
    @Test
    func cloudKitConfigurationsArePreferredAndFallBack() {
        let withCloudKit = TidesModelContainer.configurations(cloudKit: true)
        let withoutCloudKit = TidesModelContainer.configurations(cloudKit: false)

        let mirrored = withCloudKit.filter {
            $0.cloudKitContainerIdentifier == TidesCloudKit.containerIdentifier
        }
        #expect(mirrored.count == withCloudKit.count - withoutCloudKit.count)
        #expect(!mirrored.isEmpty)
        // Mirrored stores come first; the plain fallbacks follow.
        #expect(withCloudKit.prefix(mirrored.count).allSatisfy {
            $0.cloudKitContainerIdentifier != nil
        })
        #expect(withCloudKit.dropFirst(mirrored.count).allSatisfy {
            $0.cloudKitContainerIdentifier == nil
        })
        #expect(withoutCloudKit.allSatisfy { $0.cloudKitContainerIdentifier == nil })
        // The last rung is always a plain local store, usable with no
        // entitlements at all.
        #expect(withCloudKit.last?.groupAppContainerIdentifier == nil)
        #expect(withoutCloudKit.last?.groupAppContainerIdentifier == nil)
    }

    /// Without CloudKit (and without the App Group entitlement) the app still
    /// gets a usable store.
    @MainActor
    @Test
    func containerOpensWithoutCloudKit() throws {
        let container = TidesModelContainer.make(cloudKit: false)
        let context = ModelContext(container)
        let location = SavedLocation(
            name: "Fallback",
            latitude: 35.0,
            longitude: 139.75,
            parametersJSON: Data()
        )
        context.insert(location)
        let fetched = try context.fetch(
            FetchDescriptor<SavedLocation>(predicate: #Predicate { $0.name == "Fallback" })
        )
        #expect(fetched.count == 1)
        context.delete(location)
        try context.save()
    }
}
