import Foundation
import Testing
@testable import OfflineFirstFramework

@Suite("JSON values")
struct JSONValueTests {
    @Test func roundTripsEveryKind() throws {
        let value: JSONValue = [
            "id": 9_007_199_254_740_993,
            "price": 2.5,
            "title": "Milk",
            "done": false,
            "tags": ["a", nil],
            "nested": ["depth": 1]
        ]
        let data = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(JSONValue.self, from: data) == value)
    }

    @Test func largeIntegersKeepEveryDigit() throws {
        let decoded = try JSONDecoder().decode(JSONValue.self, from: Data("9223372036854775807".utf8))
        #expect(decoded == .integer(.max))
    }

    @Test func subscriptReadsAndWritesObjectsOnly() {
        var object: JSONValue = ["a": 1]
        object["b"] = "two"
        object["a"] = nil
        #expect(object == ["b": "two"])
        var number: JSONValue = 3
        number["a"] = 1
        #expect(number == 3)
        #expect(number["a"] == nil)
        #expect(JSONValue.integer(4).doubleValue == 4)
        #expect(JSONValue.string("x").stringValue == "x")
        #expect(JSONValue.bool(true).doubleValue == nil)
    }
}

@Suite("Record migrations")
struct RecordMigrationTests {
    private let renameText = RecordMigration(to: 2) { record in
        record["body"] = record["text"]
        record["text"] = nil
    }
    private let addPinned = RecordMigration(to: 3) { record in
        record["isPinned"] = false
    }

    @Test func runsTheMissingStepsInOrder() throws {
        var records: [JSONValue] = [["id": "1", "text": "Hello"]]
        try RecordMigration.migrate(&records, from: 1, to: 3, using: [addPinned, renameText])
        #expect(records == [["id": "1", "body": "Hello", "isPinned": false]])
    }

    @Test func skipsStepsAlreadyApplied() throws {
        var records: [JSONValue] = [["id": "1", "body": "Hello"]]
        try RecordMigration.migrate(&records, from: 2, to: 3, using: [renameText, addPinned])
        #expect(records == [["id": "1", "body": "Hello", "isPinned": false]])
        try RecordMigration.migrate(&records, from: 3, to: 3, using: [renameText, addPinned])
        #expect(records == [["id": "1", "body": "Hello", "isPinned": false]])
    }

    @Test func refusesDataFromANewerSchema() {
        var records: [JSONValue] = []
        #expect(throws: OfflineFirstError.unsupportedSchemaVersion(found: 4, supported: 3)) {
            try RecordMigration.migrate(&records, from: 4, to: 3, using: [])
        }
    }

    @Test func reportsDuplicateVersionsNonObjectsAndThrowingSteps() {
        struct Broken: Error {}
        var records: [JSONValue] = [["id": "1"]]
        #expect(throws: OfflineFirstError.self) {
            try RecordMigration.migrate(&records, from: 1, to: 2, using: [renameText, renameText])
        }
        var scalars: [JSONValue] = ["just a string"]
        #expect(throws: OfflineFirstError.migrationFailed(toVersion: 2, description: "a stored record is not a JSON object")) {
            try RecordMigration.migrate(&scalars, from: 1, to: 2, using: [renameText])
        }
        let failing = RecordMigration(to: 2) { _ in throw Broken() }
        #expect(throws: OfflineFirstError.self) {
            try RecordMigration.migrate(&records, from: 1, to: 2, using: [failing])
        }
    }
}
