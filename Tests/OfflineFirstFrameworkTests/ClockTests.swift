import Foundation
import Testing
@testable import OfflineFirstFramework

@Suite("Hybrid logical clock")
struct HybridLogicalClockTests {
    private func date(milliseconds: Int64) -> Date {
        Date(timeIntervalSince1970: Double(milliseconds) / 1000)
    }

    @Test func tickUsesTheDeviceTimeWhenItMovesForward() throws {
        var clock = HybridLogicalClock(nodeID: "a")
        let first = try clock.tick(at: date(milliseconds: 1_000))
        let second = try clock.tick(at: date(milliseconds: 2_000))
        #expect(first == HLCTimestamp(wallTime: 1_000, counter: 0, nodeID: "a"))
        #expect(second == HLCTimestamp(wallTime: 2_000, counter: 0, nodeID: "a"))
    }

    @Test func tickNeverGoesBackwardsWhenTheDeviceTimeDoes() throws {
        var clock = HybridLogicalClock(nodeID: "a")
        let late = try clock.tick(at: date(milliseconds: 5_000))
        let afterRewind = try clock.tick(at: date(milliseconds: 1_000))
        let again = try clock.tick(at: date(milliseconds: 1_000))
        #expect(late < afterRewind)
        #expect(afterRewind < again)
        #expect(again == HLCTimestamp(wallTime: 5_000, counter: 2, nodeID: "a"))
    }

    @Test func fullCounterMovesTheWallTimeInsteadOfOverflowing() throws {
        let start = HLCTimestamp(wallTime: 10, counter: .max, nodeID: "a")
        var clock = HybridLogicalClock(nodeID: "a", latest: start)
        let next = try clock.tick(at: date(milliseconds: 10))
        #expect(next == HLCTimestamp(wallTime: 11, counter: 0, nodeID: "a"))
        #expect(start < next)
    }

    @Test func clockAtTheLastTimestampThrowsExhausted() {
        let end = HLCTimestamp(wallTime: .max, counter: .max, nodeID: "a")
        var clock = HybridLogicalClock(nodeID: "a", latest: end)
        #expect(throws: HybridLogicalClock.Failure.exhausted) {
            try clock.tick(at: Date.distantFuture)
        }
    }

    @Test func receiveMovesPastTheRemoteTimestamp() throws {
        var clock = HybridLogicalClock(nodeID: "a")
        _ = try clock.tick(at: date(milliseconds: 1_000))
        let remote = HLCTimestamp(wallTime: 1_500, counter: 7, nodeID: "b")
        let merged = try clock.receive(remote, at: date(milliseconds: 1_200))
        #expect(merged == HLCTimestamp(wallTime: 1_500, counter: 8, nodeID: "a"))
        let next = try clock.tick(at: date(milliseconds: 1_200))
        #expect(remote < next)
    }

    @Test func receiveWithEqualWallTimesUsesTheLargerCounter() throws {
        var clock = HybridLogicalClock(nodeID: "a", latest: HLCTimestamp(wallTime: 100, counter: 3, nodeID: "a"))
        let merged = try clock.receive(HLCTimestamp(wallTime: 100, counter: 9, nodeID: "b"), at: date(milliseconds: 50))
        #expect(merged == HLCTimestamp(wallTime: 100, counter: 10, nodeID: "a"))
    }

    @Test func receiveOfAnOldTimestampUsesTheDeviceTime() throws {
        var clock = HybridLogicalClock(nodeID: "a")
        let merged = try clock.receive(HLCTimestamp(wallTime: 10, counter: 4, nodeID: "b"), at: date(milliseconds: 900))
        #expect(merged == HLCTimestamp(wallTime: 900, counter: 0, nodeID: "a"))
    }

    @Test(arguments: [Int64.max, Int64(61_001)])
    func receiveRefusesTimestampsTooFarAhead(remoteWallTime: Int64) throws {
        var clock = HybridLogicalClock(nodeID: "a", maximumDrift: .seconds(60))
        let before = try clock.tick(at: date(milliseconds: 1_000))
        let remote = HLCTimestamp(wallTime: remoteWallTime, counter: 0, nodeID: "evil")
        #expect(throws: HybridLogicalClock.Failure.self) {
            try clock.receive(remote, at: date(milliseconds: 1_000))
        }
        #expect(clock.latest == before)
    }

    @Test func receiveAcceptsTimestampsWithinTheDrift() throws {
        var clock = HybridLogicalClock(nodeID: "a", maximumDrift: .seconds(60))
        let merged = try clock.receive(HLCTimestamp(wallTime: 61_000, counter: 0, nodeID: "b"), at: date(milliseconds: 1_000))
        #expect(merged.wallTime == 61_000)
    }

    @Test func receiveOfTheSmallestWallTimeDoesNotOverflow() throws {
        var clock = HybridLogicalClock(nodeID: "a")
        let merged = try clock.receive(HLCTimestamp(wallTime: .min, counter: 0, nodeID: "b"), at: date(milliseconds: 5))
        #expect(merged.wallTime == 5)
    }

    @Test func millisecondsClampInsteadOfTrapping() {
        #expect(HybridLogicalClock.milliseconds(since1970: Date(timeIntervalSince1970: .nan)) == 0)
        #expect(HybridLogicalClock.milliseconds(since1970: Date(timeIntervalSince1970: .infinity)) == 0)
        #expect(HybridLogicalClock.milliseconds(since1970: Date(timeIntervalSince1970: 1e300)) == .max)
        #expect(HybridLogicalClock.milliseconds(since1970: Date(timeIntervalSince1970: -1e300)) == .min)
        #expect(HybridLogicalClock.milliseconds(since1970: Date(timeIntervalSince1970: 1.2349)) == 1_235)
    }

    @Test(arguments: [Int64(0), 900, 1_234, 1_760_000_000_123, -42])
    func wallTimeSurvivesTheRoundTripThroughDate(wallTime: Int64) {
        let timestamp = HLCTimestamp(wallTime: wallTime, nodeID: "a")
        #expect(HybridLogicalClock.milliseconds(since1970: timestamp.date) == wallTime)
    }

    @Test func timestampsOrderByWallTimeThenCounterThenNode() {
        let ordered = [
            HLCTimestamp(wallTime: 1, counter: 5, nodeID: "z"),
            HLCTimestamp(wallTime: 2, counter: 0, nodeID: "a"),
            HLCTimestamp(wallTime: 2, counter: 1, nodeID: "a"),
            HLCTimestamp(wallTime: 2, counter: 1, nodeID: "b")
        ]
        #expect(ordered.shuffled().sorted() == ordered)
    }

    @Test func restoredClockTakesItsOwnNodeID() throws {
        var clock = HybridLogicalClock(nodeID: "new", latest: HLCTimestamp(wallTime: 50, counter: 0, nodeID: "old"))
        let next = try clock.tick(at: date(milliseconds: 10))
        #expect(next == HLCTimestamp(wallTime: 50, counter: 1, nodeID: "new"))
    }

    @Test func durationToMillisecondsClamps() {
        #expect(Duration.seconds(2).clampedMilliseconds == 2_000)
        #expect(Duration.milliseconds(1_500).clampedMilliseconds == 1_500)
        #expect(Duration.seconds(Int64.max).clampedMilliseconds == .max)
        #expect(Duration.seconds(Int64.min).clampedMilliseconds == .min)
    }
}

@Suite("Vector clock")
struct VectorClockTests {
    @Test func incrementAndCompare() {
        var a = VectorClock()
        a.increment("a")
        var b = a
        b.increment("b")
        #expect(a.compare(to: b) == .before)
        #expect(b.compare(to: a) == .after)
        #expect(a.happened(before: b))
        #expect(a.compare(to: a) == .equal)
    }

    @Test func concurrentEditsAreDetected() {
        var a = VectorClock()
        a.increment("a")
        var b = VectorClock()
        b.increment("b")
        #expect(a.isConcurrent(with: b))
        let merged = a.merged(with: b)
        #expect(a.happened(before: merged))
        #expect(b.happened(before: merged))
        #expect(merged == VectorClock(counters: ["a": 1, "b": 1]))
    }

    @Test func incrementSaturatesAtTheMaximum() {
        var clock = VectorClock(counters: ["a": .max])
        clock.increment("a")
        #expect(clock["a"] == .max)
    }

    @Test func zeroCountersDoNotChangeEquality() throws {
        let data = Data(#"{"counters":{"a":0,"b":2}}"#.utf8)
        let decoded = try JSONDecoder().decode(VectorClock.self, from: data)
        #expect(decoded == VectorClock(counters: ["b": 2]))
        let roundTrip = try JSONDecoder().decode(VectorClock.self, from: JSONEncoder().encode(decoded))
        #expect(roundTrip == decoded)
    }
}
