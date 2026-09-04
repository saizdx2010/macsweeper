import XCTest
import Darwin
@testable import MacSweeper

/// APFS-aware sizing: hard links, clones, and sparse files must be counted the
/// way Finder will show reclaimable space — shared storage counted once.
final class DiskSizingTests: XCTestCase {
    private var tempRoot: URL!

    override func setUp() async throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacSweeperSizing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func makeFile(name: String, bytes: Int) throws -> URL {
        let url = tempRoot.appendingPathComponent(name)
        try Data(repeating: 0x41, count: bytes).write(to: url)
        return url
    }

    // MARK: Hard links

    func testHardLinkInsideOneWalkIsCountedOnce() throws {
        let original = try makeFile(name: "original.bin", bytes: 4_096)
        let link = tempRoot.appendingPathComponent("link.bin")
        try FileManager.default.linkItem(at: original, to: link)

        let dir = tempRoot.appendingPathComponent("linked/", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: original, to: dir.appendingPathComponent("original.bin"))
        try FileManager.default.moveItem(at: link, to: dir.appendingPathComponent("link.bin"))

        var deduper = DiskMeasurement.Deduper()
        let bytes = try DiskMeasurement.measureAllocatedSize(at: dir, deduper: &deduper)

        var freshDeduper = DiskMeasurement.Deduper()
        let single = try DiskMeasurement.measureAllocatedSize(
            at: dir.appendingPathComponent("original.bin"),
            fileManager: .default,
            deduper: &freshDeduper
        )
        XCTAssertEqual(bytes, single, "two hard links to one inode are allocated storage once")
    }

    func testSharedDeduperCountsInodeOnceAcrossMeasureCalls() throws {
        // Mirrors ScanEngine's cross-category dedupe: category A measures one
        // path, category B the other — the shared inode is only counted in A.
        let original = try makeFile(name: "catA.bin", bytes: 4_096)
        let link = tempRoot.appendingPathComponent("catB.bin")
        try FileManager.default.linkItem(at: original, to: link)

        var sharedDeduper = DiskMeasurement.Deduper()
        let firstBytes = try DiskMeasurement.measureAllocatedSize(
            at: original,
            fileManager: .default,
            deduper: &sharedDeduper
        )
        let secondBytes = try DiskMeasurement.measureAllocatedSize(
            at: link,
            fileManager: .default,
            deduper: &sharedDeduper
        )

        XCTAssertGreaterThan(firstBytes, 0)
        XCTAssertEqual(secondBytes, 0, "the same inode in a later category is not double-counted")

        var freshDeduper = DiskMeasurement.Deduper()
        let independentBytes = try DiskMeasurement.measureAllocatedSize(
            at: link,
            fileManager: .default,
            deduper: &freshDeduper
        )
        XCTAssertEqual(independentBytes, firstBytes, "a fresh walk still reports the file")
    }

    // MARK: Free-space delta

    func testFreeSpaceDeltaGainMath() {
        XCTAssertEqual(FreeSpaceDelta.gainBytes(before: Int64(1_000), after: Int64(3_600)), 2_600)
        XCTAssertEqual(
            FreeSpaceDelta.gainBytes(before: Int64(3_600), after: Int64(1_000)),
            -2_600,
            "negative readings stay raw — the done screen only shows gains"
        )
        XCTAssertNil(FreeSpaceDelta.gainBytes(before: nil, after: Int64(5)))
        XCTAssertNil(FreeSpaceDelta.gainBytes(before: Int64(5), after: nil))
    }

    // MARK: APFS clones

    func testAPFSCloneIsCountedOncePerWalk() throws {
        let original = try makeFile(name: "clone-source.bin", bytes: 1_048_576)
        let clone = tempRoot.appendingPathComponent("clone.bin")

        let status = original.withUnsafeFileSystemRepresentation { source in
            clone.withUnsafeFileSystemRepresentation { target in
                clonefile(source, target, 0)
            }
        }
        guard status == 0 else {
            throw XCTSkip("clonefile unavailable on this volume — clone dedupe not exercised here")
        }

        var deduper = DiskMeasurement.Deduper()
        let bothBytes = try DiskMeasurement.measureAllocatedSize(at: tempRoot, deduper: &deduper)

        var freshDeduper = DiskMeasurement.Deduper()
        let singleBytes = try DiskMeasurement.measureAllocatedSize(
            at: original,
            fileManager: .default,
            deduper: &freshDeduper
        )

        XCTAssertEqual(bothBytes, singleBytes, "clones share blocks and are allocated storage once")

        // A clone pair that avoids dedupe would report ~2× the single size.
        XCTAssertGreaterThan(singleBytes, 0)
    }

    // MARK: Sparse files

    func testSparseFileReportsAllocatedNotLogicalSize() throws {
        let logicalBytes = 8 * 1_048_576
        let sparse = tempRoot.appendingPathComponent("sparse.bin")
        let fd = open(sparse.path, O_CREAT | O_WRONLY | O_TRUNC, 0o644)
        defer { close(fd) }
        guard fd >= 0 else { return XCTFail("could not create sparse fixture") }
        guard ftruncate(fd, off_t(logicalBytes)) == 0 else {
            return XCTFail("could not truncate sparse fixture")
        }

        var deduper = DiskMeasurement.Deduper()
        let allocated = try DiskMeasurement.measureAllocatedSize(
            at: sparse,
            fileManager: .default,
            deduper: &deduper
        )

        let logical = (try sparse.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
        XCTAssertEqual(logical, logicalBytes)
        XCTAssertLessThan(
            allocated,
            Int64(logicalBytes),
            "sparse holes must not be counted as allocated storage"
        )
    }
}
