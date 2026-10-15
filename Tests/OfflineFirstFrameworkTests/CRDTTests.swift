import Foundation
import Testing
@testable import OfflineFirstFramework

/// A small seeded generator (SplitMix64) so the property tests are repeatable.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Checks the three CRDT laws on three replicas.
func expectMergeLaws<T: Mergeable & Equatable>(_ a: T, _ b: T, _ c: T, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(a.merged(with: b) == b.merged(with: a), "commutative", sourceLocation: sourceLocation)
    #expect(a.merged(with: b).merged(with: c) == a.merged(with: b.merged(with: c)), "associative", sourceLocation: sourceLocation)
    #expect(a.merged(with: a) == a, "idempotent", sourceLocation: sourceLocation)
}

@Suite("CRDTs")
struct CRDTTests {
    private let nodes = ["a", "b", "c"]

    @Test(arguments: 1...20)
    func lwwRegisterFollowsTheMergeLaws(seed: UInt64) throws {
        var random = SeededGenerator(seed: seed)
        let replicas = nodes.map { node in
            LWWRegister(Int.random(in: 0...3, using: &random), timestamp: HLCTimestamp(wallTime: Int64.random(in: 0...3, using: &random), counter: 0, nodeID: node))
        }
        expectMergeLaws(replicas[0], replicas[1], replicas[2])
    }

    @Test func lwwRegisterKeepsTheNewestWrite() {
        var register = LWWRegister("old", timestamp: HLCTimestamp(wallTime: 10, nodeID: "a"))
        register.set("stale", timestamp: HLCTimestamp(wallTime: 5, nodeID: "b"))
        #expect(register.value == "old")
        register.set("new", timestamp: HLCTimestamp(wallTime: 11, nodeID: "b"))
        #expect(register.value == "new")
        let sameMillisecond = LWWRegister("b wins the tie", timestamp: HLCTimestamp(wallTime: 11, nodeID: "c"))
        #expect(register.merged(with: sameMillisecond).value == "b wins the tie")
    }

    @Test(arguments: 1...20)
    func lwwMapFollowsTheMergeLaws(seed: UInt64) {
        var random = SeededGenerator(seed: seed)
        let replicas = nodes.map { node in
            var map = LWWMap<String, Int>()
            for step in 0..<6 {
                let key = ["x", "y", "z"].randomElement(using: &random)!
                let timestamp = HLCTimestamp(wallTime: Int64.random(in: 0...5, using: &random), counter: UInt32(step), nodeID: node)
                if Bool.random(using: &random) {
                    map.set(Int.random(in: 0...9, using: &random), forKey: key, timestamp: timestamp)
                } else {
                    map.removeValue(forKey: key, timestamp: timestamp)
                }
            }
            return map
        }
        expectMergeLaws(replicas[0], replicas[1], replicas[2])
    }

    @Test func lwwMapNewerRemovalBeatsOlderValueAndBack() {
        var phone = LWWMap<String, String>()
        phone.set("Ada", forKey: "name", timestamp: HLCTimestamp(wallTime: 1, nodeID: "phone"))
        var laptop = phone
        laptop.removeValue(forKey: "name", timestamp: HLCTimestamp(wallTime: 2, nodeID: "laptop"))
        #expect(phone.merged(with: laptop)["name"] == nil)
        phone.set("Grace", forKey: "name", timestamp: HLCTimestamp(wallTime: 3, nodeID: "phone"))
        let merged = phone.merged(with: laptop)
        #expect(merged["name"] == "Grace")
        #expect(merged.keys == ["name"])
        #expect(merged.values == ["name": "Grace"])
    }

    @Test(arguments: 1...20)
    func countersFollowTheMergeLaws(seed: UInt64) {
        var random = SeededGenerator(seed: seed)
        let replicas = nodes.map { node in
            var counter = PNCounter()
            for _ in 0..<5 {
                if Bool.random(using: &random) {
                    counter.increment(by: UInt64.random(in: 1...9, using: &random), node: node)
                } else {
                    counter.decrement(by: UInt64.random(in: 1...9, using: &random), node: node)
                }
            }
            return counter
        }
        expectMergeLaws(replicas[0], replicas[1], replicas[2])
        expectMergeLaws(replicas[0].increments, replicas[1].increments, replicas[2].increments)
    }

    @Test func countersAddUpAcrossReplicas() {
        var phone = PNCounter()
        phone.increment(by: 5, node: "phone")
        var laptop = PNCounter()
        laptop.increment(by: 2, node: "laptop")
        laptop.decrement(by: 4, node: "laptop")
        let merged = phone.merged(with: laptop)
        #expect(merged.value == 3)
        // Merging the same state again does not count it twice.
        #expect(merged.merged(with: laptop).value == 3)
    }

    @Test func countersSaturateInsteadOfTrapping() throws {
        var counter = GCounter(counts: ["a": .max - 1])
        counter.increment(by: 5, node: "a")
        #expect(counter.counts["a"] == .max)
        counter.increment(by: 3, node: "b")
        #expect(counter.value == .max)

        let decoded = try JSONDecoder().decode(PNCounter.self, from: Data(#"""
        {"increments":{"counts":{"a":18446744073709551615}},"decrements":{"counts":{}}}
        """#.utf8))
        #expect(decoded.value == .max)

        var negative = PNCounter()
        negative.decrement(by: .max, node: "a")
        #expect(negative.value == .min)
        // UInt64.max - Int64.max is 2^63, exactly the magnitude of Int64.min.
        negative.increment(by: UInt64(Int64.max), node: "b")
        #expect(negative.value == .min)
        negative.increment(by: 1, node: "c")
        #expect(negative.value == -Int64.max)
    }

    @Test(arguments: 1...20)
    func orSetFollowsTheMergeLaws(seed: UInt64) {
        var random = SeededGenerator(seed: seed)
        var shared = ORSet(["milk", "eggs"])
        if Bool.random(using: &random) { shared.remove("milk") }
        let replicas = nodes.map { _ in
            var set = shared
            for _ in 0..<4 {
                let element = ["milk", "eggs", "bread"].randomElement(using: &random)!
                if Bool.random(using: &random) { set.insert(element) } else { set.remove(element) }
            }
            return set
        }
        expectMergeLaws(replicas[0], replicas[1], replicas[2])
    }

    @Test func orSetConcurrentAddWinsOverRemove() {
        let base = ORSet(["milk"])
        var phone = base
        phone.remove("milk")
        var laptop = base
        laptop.insert("milk")
        let merged = phone.merged(with: laptop)
        #expect(merged.contains("milk"))
        // A remove that has seen every add wins.
        var both = merged
        both.remove("milk")
        #expect(!both.merged(with: laptop).contains("milk"))
        #expect(!both.merged(with: base).contains("milk"))
    }

    @Test func orSetDecodingDropsRemovedTags() throws {
        let tag = UUID()
        let json = Data(#"{"additions":{"milk":["\#(tag.uuidString)"]},"removals":["\#(tag.uuidString)"]}"#.utf8)
        let decoded = try JSONDecoder().decode(ORSet<String>.self, from: json)
        #expect(!decoded.contains("milk"))
        #expect(decoded.elements.isEmpty)
        #expect(decoded == ORSet<String>().merged(with: decoded))
    }

    @Test func mutatingMergeMatchesMerged() {
        var a = GCounter(counts: ["a": 2])
        let b = GCounter(counts: ["a": 1, "b": 4])
        let expected = a.merged(with: b)
        a.merge(with: b)
        #expect(a == expected)
        #expect(a.value == 6)
    }
}
