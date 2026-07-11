import SwiftData
import Testing
@testable import SendToX4

struct AppSchemaTests {

    /// Regression guard for issue #20: the Convert intent once opened the
    /// shared store with a subset schema, and SwiftData's auto-migration
    /// dropped the omitted RSS tables — wiping every saved feed. Any code
    /// path that opens the shared store must use `AppSchema.schema`, and
    /// that schema must keep covering every persisted entity.
    @Test func schemaContainsAllPersistedEntities() {
        let entityNames = Set(AppSchema.schema.entities.map(\.name))
        let expected: Set<String> = [
            "Article", "DeviceSettings", "ActivityEvent",
            "QueueItem", "RSSFeed", "RSSArticle",
        ]
        #expect(entityNames == expected)
    }
}
