import Foundation
import XCTest
@testable import HTSCore

/** Official BLAKE3 test vectors (BLAKE3-team/BLAKE3 test_vectors.json): input byte i is i % 251. */
final class Blake3Tests: XCTestCase {
    private let vectors: [(Int, String)] = [
        (0, "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262"),
        (1, "2d3adedff11b61f14c886e35afa036736dcd87a74d27b5c1510225d0f592e213"),
        (63, "e9bc37a594daad83be9470df7f7b3798297c3d834ce80ba85d6e207627b7db7b"),
        (64, "4eed7141ea4a5cd4b788606bd23f46e212af9cacebacdc7d1f4c6dc7f2511b98"),
        (65, "de1e5fa0be70df6d2be8fffd0e99ceaa8eb6e8c93a63f2d8d1c30ecb6b263dee"),
        (1023, "10108970eeda3eb932baac1428c7a2163b0e924c9a9e25b35bba72b28f70bd11"),
        (1024, "42214739f095a406f3fc83deb889744ac00df831c10daa55189b5d121c855af7"),
        (1025, "d00278ae47eb27b34faecf67b4fe263f82d5412916c1ffd97c8cb7fb814b8444"),
        (2048, "e776b6028c7cd22a4d0ba182a8bf62205d2ef576467e838ed6f2529b85fba24a"),
        (2049, "5f4d72f40d7a5f82b15ca2b2e44b1de3c2ef86c426c95c1af0b6879522563030"),
        (3072, "b98cb0ff3623be03326b373de6b9095218513e64f1ee2edd2525c7ad1e5cffd2"),
        (4096, "015094013f57a5277b59d8475c0501042c0b642e531b0a1c8f58d2163229e969"),
        (8193, "bab6c09cb8ce8cf459261398d2e7aef35700bf488116ceb94a36d0f5f1b7bc3b"),
        (31744, "62b6960e1a44bcc1eb1a611a8d6235b6b4b78f32e7abc4fb4c6cdcce94895c47"),
        (102400, "bc3e3d41a1146b069abffad3c0d44860cf664390afce4d9661f7902e7943e085"),
    ]

    private func input(_ n: Int) -> Data {
        Data((0..<n).map { UInt8($0 % 251) })
    }

    func testVectors() {
        for (n, hash) in vectors {
            XCTAssertEqual(Blake3.hash(input(n)), hash, "length \(n)")
        }
    }

    /** Fed in odd pieces, as downloads arrive. */
    func testStreaming() {
        for (n, hash) in vectors where n > 100 {
            let data = input(n)
            var h = Blake3()
            var at = 0
            var step = 1
            while at < n {
                let end = min(n, at + step)
                h.update(data.subdata(in: at..<end))
                at = end
                step = step * 3 % 1777 + 1
            }
            XCTAssertEqual(h.hexDigest(), hash, "length \(n) in pieces")
        }
    }

    func testFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("blake3-\(UUID().uuidString)")
        try input(102400).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(try Blake3.hashFile(url), vectors.last!.1)
    }
}
