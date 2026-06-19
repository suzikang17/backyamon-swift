import XCTest
import AVFoundation
@testable import Backyamon

final class SampleLibraryTests: XCTestCase {
    func test_loadsEveryInstrument() throws {
        let lib = try SampleLibrary()
        for id in InstrumentID.allCases {
            let buf = lib.buffer(for: id)
            XCTAssertNotNil(buf, "missing sample for \(id)")
            XCTAssertGreaterThan(buf!.frameLength, 0)
        }
    }

    func test_pitchedVoicesHaveRootNote() throws {
        let lib = try SampleLibrary()
        XCTAssertNotNil(lib.rootMidiNote(for: .bass))
        XCTAssertNil(lib.rootMidiNote(for: .kick))
    }
}
