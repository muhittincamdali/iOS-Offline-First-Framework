import Foundation
import Testing
@testable import OfflineFirstFramework

/// What the transport reads of an answer before it stops. The outline of a page, which sets a
/// change too large to load aside, used to read without a limit: a change that never ended was
/// read until the sync's deadline, 5.6 GiB in 12 s, and a page that ignored limit=1 was read to
/// its end before it was refused.
@Suite("Reading answers as they stream in")
struct ResponseReaderTests {
    /// Feeds `prefix`, then `filler` again and again, until the reader stops, and returns why
    /// and after how many bytes, or `nil` when it read `cap` bytes without stopping.
    private func feed(_ reader: inout ResponseReader, prefix: String, filler: String, cap: Int = 64 << 20) -> ResponseReader.Stop? {
        do {
            for byte in prefix.utf8 { try reader.read(byte) }
            let bytes = Array(filler.utf8)
            while reader.bytesRead < cap {
                for byte in bytes { try reader.read(byte) }
            }
            return nil
        } catch {
            return error
        }
    }

    @Test func anOutlineStopsWhenASecondChangeStarts() throws {
        var reader = try ResponseReader(expectedLength: -1, maximumResponseSize: 1 << 20, changeLimit: 1, outlining: true)
        let first = #"{"changes":[{"recordID":"a","revision":"1","record":{"text":"x"}}"#
        #expect(feed(&reader, prefix: first, filler: #",{"recordID":"b","revision":"2"}"#) == .tooManyChanges)
        // It stopped at the brace that opens the second change.
        #expect(reader.bytesRead == first.utf8.count + 2)
    }

    @Test func anOutlineReadsAtMostFourTimesTheResponseLimit() throws {
        let limit = 256 * 1024
        var reader = try ResponseReader(expectedLength: -1, maximumResponseSize: limit, changeLimit: 1, outlining: true)
        // One change whose record never ends: the outline stays small, the reading does not.
        let prefix = #"{"changes":[{"recordID":"a","revision":"1","record":{"text":""#
        #expect(feed(&reader, prefix: prefix, filler: String(repeating: "x", count: 4_096)) == .tooLarge)
        #expect(reader.bytesRead == ResponseReader.outlineReadFactor * limit + 1)
        #expect(reader.body.count < 100)
    }

    @Test func anOutlineKeepsAtMostTheResponseLimit() throws {
        let limit = 64 * 1024
        var reader = try ResponseReader(expectedLength: -1, maximumResponseSize: limit, changeLimit: 1, outlining: true)
        // A change whose record ID never ends is kept in the outline, up to the limit.
        #expect(feed(&reader, prefix: #"{"changes":[{"recordID":""#, filler: "y") == .tooLarge)
        #expect(reader.body.count == limit + 1)
    }

    @Test func aPageStopsAtTheChangeAfterTheLimit() throws {
        var reader = try ResponseReader(expectedLength: -1, maximumResponseSize: 16 << 20, changeLimit: 100, outlining: false)
        let change = #"{"recordID":"n","revision":"1"},"#
        #expect(feed(&reader, prefix: #"{"changes":["#, filler: change) == .tooManyChanges)
        #expect(reader.bytesRead == 12 + 100 * change.utf8.count + 1)
    }

    @Test func anAnnouncedLengthBeyondWhatIsReadStopsBeforeTheFirstByte() throws {
        let limit = 1 << 20
        #expect(throws: ResponseReader.Stop.tooLarge) {
            try ResponseReader(expectedLength: Int64(limit) + 1, maximumResponseSize: limit, changeLimit: 100, outlining: false)
        }
        #expect(throws: ResponseReader.Stop.tooLarge) {
            try ResponseReader(expectedLength: Int64(4 * limit) + 1, maximumResponseSize: limit, changeLimit: 1, outlining: true)
        }
        _ = try ResponseReader(expectedLength: Int64(limit), maximumResponseSize: limit, changeLimit: 100, outlining: false)
        _ = try ResponseReader(expectedLength: Int64(4 * limit), maximumResponseSize: limit, changeLimit: 1, outlining: true)
        // A push answer or an error body is read up to the limit, not as a page.
        #expect(throws: ResponseReader.Stop.tooLarge) {
            try ResponseReader(expectedLength: Int64(limit) + 1, maximumResponseSize: limit, changeLimit: nil, outlining: true)
        }
    }

    @Test func aBodyThatIsNotAPageIsNotCounted() throws {
        var reader = try ResponseReader(expectedLength: -1, maximumResponseSize: 1 << 20, changeLimit: nil, outlining: false)
        for byte in #"{"changes":[1,2,3]}"#.utf8 { try reader.read(byte) }
        #expect(reader.body == Data(#"{"changes":[1,2,3]}"#.utf8))
    }

    @Test(arguments: [
        (#"{"changes":[]}"#, 0),
        (#"{"changes":[ ] }"#, 0),
        (#"{"changes":[ 1 , 2 ]}"#, 2),
        (#"{"changes":[[1,2,3],{"a":[1,2],"b":"],["}]}"#, 2),
        (#"{"changes":["a,b",",]\"["]}"#, 2),
        (#"{"other":[1,2,3,4],"token":"changes","x":[5,6],"changes":[{},{}],"after":[7,8,9]}"#, 2),
        (#"{"changes":{"a":1,"b":2}}"#, 0),
        (#"{"chang\#u{5C}u0065s":[1,2,3]}"#, 0),
        ("\u{FEFF}" + #"{"changes":[{}]}"#, 1),
    ])
    func theScannerCountsTheElementsOfTheListOfChangesOnly(page: String, count: Int) {
        var scanner = PageScanner()
        for byte in page.utf8 { _ = scanner.scan(byte) }
        #expect(scanner.changesStarted == count)
    }
}
