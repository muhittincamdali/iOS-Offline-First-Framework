import Foundation

/// A point in time produced by a ``HybridLogicalClock``.
///
/// Timestamps have a total order: first by ``wallTime``, then by ``counter``, then by
/// ``nodeID``. Two devices can therefore always agree which of two writes is newer, even when
/// their system clocks disagree or both writes happened in the same millisecond.
public struct HLCTimestamp: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    /// Milliseconds since 1 January 1970 (UTC), taken from the device clock or a received
    /// timestamp, whichever was later.
    public let wallTime: Int64

    /// Orders events that share the same ``wallTime``.
    public let counter: UInt32

    /// The device or replica that produced the timestamp.
    public let nodeID: String

    /// Creates a timestamp from its parts.
    public init(wallTime: Int64, counter: UInt32 = 0, nodeID: String) {
        self.wallTime = wallTime
        self.counter = counter
        self.nodeID = nodeID
    }

    /// The wall time as a `Date`.
    public var date: Date {
        Date(timeIntervalSince1970: Double(wallTime) / 1000)
    }

    /// The timestamp as `wallTime-counter-nodeID`.
    public var description: String {
        "\(wallTime)-\(counter)-\(nodeID)"
    }

    /// Orders by wall time, then counter, then node ID.
    public static func < (lhs: HLCTimestamp, rhs: HLCTimestamp) -> Bool {
        if lhs.wallTime != rhs.wallTime { return lhs.wallTime < rhs.wallTime }
        if lhs.counter != rhs.counter { return lhs.counter < rhs.counter }
        return lhs.nodeID < rhs.nodeID
    }
}

/// A hybrid logical clock (Kulkarni et al., 2014) that stamps local changes.
///
/// The clock combines the device time with a counter, so its timestamps never go backwards,
/// even when the user changes the system time, and every timestamp received from another
/// device moves the local clock past it. ``OfflineStore`` uses it to order writes for
/// ``ConflictResolver/lastWriteWins``.
///
/// A received timestamp that is further ahead of the device clock than ``maximumDrift`` is
/// refused with ``Failure/driftExceeded(remote:local:maximum:)``. Without that limit a single
/// timestamp from a broken or hostile peer (for example `Int64.max`) would move the clock to
/// the end of time: every later local write would carry that time, and the clock would run out
/// of timestamps.
public struct HybridLogicalClock: Sendable {
    /// Reasons a clock operation fails.
    public enum Failure: Error, Equatable, Sendable {
        /// The received wall time is more than `maximum` milliseconds ahead of the local time.
        case driftExceeded(remote: Int64, local: Int64, maximum: Int64)
        /// The clock reached the largest representable timestamp.
        case exhausted
    }

    /// The node ID written into every timestamp from this clock.
    public let nodeID: String

    /// How far, in milliseconds, a received timestamp may be ahead of the local time.
    public let maximumDrift: Int64

    /// The most recent timestamp this clock produced or received.
    public private(set) var latest: HLCTimestamp

    /// Creates a clock.
    ///
    /// - Parameters:
    ///   - nodeID: A non-empty identifier that is unique to this device or replica.
    ///   - maximumDrift: How far ahead of the local time a received timestamp may be. The
    ///     default is one minute. Negative values count as zero.
    ///   - latest: The last timestamp of a previous run, so the clock continues after it.
    public init(nodeID: String, maximumDrift: Duration = .seconds(60), latest: HLCTimestamp? = nil) {
        precondition(!nodeID.isEmpty, "HybridLogicalClock needs a non-empty node ID")
        self.nodeID = nodeID
        self.maximumDrift = max(0, maximumDrift.clampedMilliseconds)
        if let latest {
            self.latest = HLCTimestamp(wallTime: latest.wallTime, counter: latest.counter, nodeID: nodeID)
        } else {
            self.latest = HLCTimestamp(wallTime: .min, counter: 0, nodeID: nodeID)
        }
    }

    /// Returns a new timestamp for a local event.
    ///
    /// - Parameter date: The current time, normally `Date()`.
    /// - Throws: ``Failure/exhausted`` when no larger timestamp exists.
    public mutating func tick(at date: Date = Date()) throws(Failure) -> HLCTimestamp {
        let physical = Self.milliseconds(since1970: date)
        if physical > latest.wallTime {
            latest = HLCTimestamp(wallTime: physical, counter: 0, nodeID: nodeID)
        } else {
            latest = try Self.advance(wallTime: latest.wallTime, counter: latest.counter, nodeID: nodeID)
        }
        return latest
    }

    /// Merges a timestamp received from another node and returns a local timestamp after both.
    ///
    /// - Parameters:
    ///   - remote: The timestamp that came with a remote change.
    ///   - date: The current time, normally `Date()`.
    /// - Throws: ``Failure/driftExceeded(remote:local:maximum:)`` when `remote` is too far in
    ///   the future (the clock is left unchanged), or ``Failure/exhausted``.
    @discardableResult
    public mutating func receive(_ remote: HLCTimestamp, at date: Date = Date()) throws(Failure) -> HLCTimestamp {
        let physical = Self.milliseconds(since1970: date)
        if remote.wallTime > physical {
            // Only a remote time ahead of the local one can overflow here, and then it is far
            // ahead anyway.
            let (ahead, overflow) = remote.wallTime.subtractingReportingOverflow(physical)
            if overflow || ahead > maximumDrift {
                throw .driftExceeded(remote: remote.wallTime, local: physical, maximum: maximumDrift)
            }
        }
        let wallTime = max(latest.wallTime, remote.wallTime, physical)
        if wallTime == latest.wallTime && wallTime == remote.wallTime {
            latest = try Self.advance(wallTime: wallTime, counter: max(latest.counter, remote.counter), nodeID: nodeID)
        } else if wallTime == latest.wallTime {
            latest = try Self.advance(wallTime: wallTime, counter: latest.counter, nodeID: nodeID)
        } else if wallTime == remote.wallTime {
            latest = try Self.advance(wallTime: wallTime, counter: remote.counter, nodeID: nodeID)
        } else {
            latest = HLCTimestamp(wallTime: wallTime, counter: 0, nodeID: nodeID)
        }
        return latest
    }

    /// Converts a date to milliseconds since 1970, rounded to the nearest millisecond, without
    /// trapping.
    ///
    /// Rounding (rather than truncating) makes ``HLCTimestamp/date`` convert back to the same
    /// ``HLCTimestamp/wallTime``. Dates outside the `Int64` range are clamped to it, and a non-finite time interval
    /// (which `Date` can hold) becomes `0`.
    public static func milliseconds(since1970 date: Date) -> Int64 {
        let milliseconds = (date.timeIntervalSince1970 * 1000).rounded()
        guard milliseconds.isFinite else { return 0 }
        if milliseconds >= Double(Int64.max) { return .max }
        if milliseconds <= Double(Int64.min) { return .min }
        return Int64(milliseconds)
    }

    /// The timestamp right after (`wallTime`, `counter`): the counter grows, and when it is full
    /// the wall time moves one millisecond forward instead.
    private static func advance(wallTime: Int64, counter: UInt32, nodeID: String) throws(Failure) -> HLCTimestamp {
        if counter < .max {
            return HLCTimestamp(wallTime: wallTime, counter: counter + 1, nodeID: nodeID)
        }
        guard wallTime < .max else { throw .exhausted }
        return HLCTimestamp(wallTime: wallTime + 1, counter: 0, nodeID: nodeID)
    }
}

extension Duration {
    /// The duration in whole milliseconds, clamped to the `Int64` range.
    var clampedMilliseconds: Int64 {
        let (seconds, attoseconds) = components
        let (whole, overflow) = seconds.multipliedReportingOverflow(by: 1000)
        if overflow { return seconds < 0 ? .min : .max }
        let (total, sumOverflow) = whole.addingReportingOverflow(attoseconds / 1_000_000_000_000_000)
        if sumOverflow { return seconds < 0 ? .min : .max }
        return total
    }
}
