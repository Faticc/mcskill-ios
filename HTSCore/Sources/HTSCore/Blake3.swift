import Foundation

/**
 * BLAKE3 with the default 32-byte output: the file hash of the McSkill launcher (BouncyCastle's
 * Blake3Digest over the whole file, lowercase hex) and of `FileNode.hash` in its manifests.
 * Streaming; a port of the Android app's sync/Blake3.java.
 */
public struct Blake3 {
    private static let iv: [UInt32] = [
        0x6A09_E667, 0xBB67_AE85, 0x3C6E_F372, 0xA54F_F53A, 0x510E_527F, 0x9B05_688C, 0x1F83_D9AB, 0x5BE0_CD19,
    ]
    private static let chunkStart: UInt32 = 1, chunkEnd: UInt32 = 2, parent: UInt32 = 4, root: UInt32 = 8
    private static let blockLen = 64, chunkLen = 1024
    /** Message word order of each of the 7 rounds. */
    private static let schedule: [[Int]] = {
        let perm = [2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8]
        var order = Array(0..<16)
        var rounds: [[Int]] = []
        for _ in 0..<7 {
            rounds.append(order)
            order = perm.map { order[$0] }
        }
        return rounds
    }()

    private var chunkCv = Blake3.iv
    private var block = [UInt8](repeating: 0, count: 64)
    private var blockFill = 0
    private var blocksCompressed = 0
    private var chunkCounter: UInt64 = 0
    /** Chaining values of completed subtrees. */
    private var cvStack: [[UInt32]] = []

    public init() {}

    public mutating func update(_ data: Data) {
        data.withUnsafeBytes { raw in
            update(raw.bindMemory(to: UInt8.self))
        }
    }

    public mutating func update(_ bytes: UnsafeBufferPointer<UInt8>) {
        var offset = 0
        var left = bytes.count
        while left > 0 {
            // A full chunk that isn't the end of the input so far is finished before taking more
            if chunkLength == Blake3.chunkLen {
                let cv = chunkOutputCv()
                addChunkCv(cv, totalChunks: chunkCounter + 1)
                resetChunk(counter: chunkCounter + 1)
            }
            let take = min(Blake3.chunkLen - chunkLength, left)
            chunkUpdate(bytes, offset, take)
            offset += take
            left -= take
        }
    }

    /** 32-byte digest of everything so far. */
    public func digest() -> [UInt8] {
        var blockWords = Blake3.words(block, count: blockFill)
        var flags = (blocksCompressed == 0 ? Blake3.chunkStart : 0) | Blake3.chunkEnd
        var cv = chunkCv
        var counter = chunkCounter
        var len = UInt32(blockFill)
        for level in stride(from: cvStack.count - 1, through: 0, by: -1) {
            let out = Blake3.compress(cv, blockWords, counter, len, flags)
            blockWords = cvStack[level] + Array(out[0..<8])
            cv = Blake3.iv
            counter = 0
            len = UInt32(Blake3.blockLen)
            flags = Blake3.parent
        }
        let out = Blake3.compress(cv, blockWords, counter, len, flags | Blake3.root)
        var digest = [UInt8]()
        digest.reserveCapacity(32)
        for w in out[0..<8] {
            digest.append(UInt8(truncatingIfNeeded: w))
            digest.append(UInt8(truncatingIfNeeded: w >> 8))
            digest.append(UInt8(truncatingIfNeeded: w >> 16))
            digest.append(UInt8(truncatingIfNeeded: w >> 24))
        }
        return digest
    }

    public func hexDigest() -> String {
        Blake3.hex(digest())
    }

    public static func hex<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
        let digits = Array("0123456789abcdef".utf8)
        var text = [UInt8]()
        for b in bytes {
            text.append(digits[Int(b >> 4)])
            text.append(digits[Int(b & 15)])
        }
        return String(decoding: text, as: UTF8.self)
    }

    public static func hash(_ data: Data) -> String {
        var h = Blake3()
        h.update(data)
        return h.hexDigest()
    }

    /** Hex hash of a file, read in 256 KB pieces. */
    public static func hashFile(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var h = Blake3()
        while true {
            let piece = try handle.read(upToCount: 256 * 1024) ?? Data()
            if piece.isEmpty { break }
            h.update(piece)
        }
        return h.hexDigest()
    }

    // MARK: - chunk

    private var chunkLength: Int { blocksCompressed * Blake3.blockLen + blockFill }

    private mutating func resetChunk(counter: UInt64) {
        chunkCv = Blake3.iv
        chunkCounter = counter
        blockFill = 0
        blocksCompressed = 0
    }

    private mutating func chunkUpdate(_ input: UnsafeBufferPointer<UInt8>, _ offset: Int, _ count: Int) {
        var offset = offset
        var left = count
        while left > 0 {
            // The last block of a chunk stays buffered: it gets CHUNK_END (and maybe ROOT) later
            if blockFill == Blake3.blockLen {
                let flags = blocksCompressed == 0 ? Blake3.chunkStart : 0
                let out = Blake3.compress(chunkCv, Blake3.words(block, count: Blake3.blockLen), chunkCounter,
                                          UInt32(Blake3.blockLen), flags)
                chunkCv = Array(out[0..<8])
                blocksCompressed += 1
                blockFill = 0
            }
            let take = min(Blake3.blockLen - blockFill, left)
            for i in 0..<take { block[blockFill + i] = input[offset + i] }
            blockFill += take
            offset += take
            left -= take
        }
    }

    private func chunkOutputCv() -> [UInt32] {
        let flags = (blocksCompressed == 0 ? Blake3.chunkStart : 0) | Blake3.chunkEnd
        let out = Blake3.compress(chunkCv, Blake3.words(block, count: blockFill), chunkCounter, UInt32(blockFill), flags)
        return Array(out[0..<8])
    }

    /** Pushes a finished chunk's value, merging completed subtrees (trailing zeros of totalChunks). */
    private mutating func addChunkCv(_ cv: [UInt32], totalChunks: UInt64) {
        var newCv = cv
        var total = totalChunks
        while total & 1 == 0 {
            let left = cvStack.removeLast()
            newCv = Array(Blake3.compress(Blake3.iv, left + newCv, 0, UInt32(Blake3.blockLen), Blake3.parent)[0..<8])
            total >>= 1
        }
        cvStack.append(newCv)
    }

    private static func words(_ bytes: [UInt8], count: Int) -> [UInt32] {
        var w = [UInt32](repeating: 0, count: 16)
        for i in 0..<count {
            w[i >> 2] |= UInt32(bytes[i]) << (8 * UInt32(i & 3))
        }
        return w
    }

    @inline(__always)
    private static func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 {
        (x >> n) | (x << (32 - n))
    }

    private static func compress(_ cv: [UInt32], _ m: [UInt32], _ counter: UInt64, _ blockLen: UInt32,
                                 _ flags: UInt32) -> [UInt32] {
        var v: [UInt32] = [
            cv[0], cv[1], cv[2], cv[3], cv[4], cv[5], cv[6], cv[7],
            iv[0], iv[1], iv[2], iv[3],
            UInt32(truncatingIfNeeded: counter), UInt32(truncatingIfNeeded: counter >> 32), blockLen, flags,
        ]
        @inline(__always)
        func g(_ a: Int, _ b: Int, _ c: Int, _ d: Int, _ x: UInt32, _ y: UInt32) {
            v[a] = v[a] &+ v[b] &+ x
            v[d] = rotr(v[d] ^ v[a], 16)
            v[c] = v[c] &+ v[d]
            v[b] = rotr(v[b] ^ v[c], 12)
            v[a] = v[a] &+ v[b] &+ y
            v[d] = rotr(v[d] ^ v[a], 8)
            v[c] = v[c] &+ v[d]
            v[b] = rotr(v[b] ^ v[c], 7)
        }
        for s in schedule {
            g(0, 4, 8, 12, m[s[0]], m[s[1]])
            g(1, 5, 9, 13, m[s[2]], m[s[3]])
            g(2, 6, 10, 14, m[s[4]], m[s[5]])
            g(3, 7, 11, 15, m[s[6]], m[s[7]])
            g(0, 5, 10, 15, m[s[8]], m[s[9]])
            g(1, 6, 11, 12, m[s[10]], m[s[11]])
            g(2, 7, 8, 13, m[s[12]], m[s[13]])
            g(3, 4, 9, 14, m[s[14]], m[s[15]])
        }
        var out = [UInt32](repeating: 0, count: 16)
        for i in 0..<8 {
            out[i] = v[i] ^ v[i + 8]
            out[i + 8] = v[i + 8] ^ cv[i]
        }
        return out
    }
}
