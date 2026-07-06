final class Keccak256 {

    // MARK: - Constants

    private static let rndc: [UInt64] = [
        0x0000000000000001, 0x0000000000008082,
        0x800000000000808a, 0x8000000080008000,
        0x000000000000808b, 0x0000000080000001,
        0x8000000080008081, 0x8000000000008009,
        0x000000000000008a, 0x0000000000000088,
        0x0000000080008009, 0x000000008000000a,
        0x000000008000808b, 0x800000000000008b,
        0x8000000000008089, 0x8000000000008003,
        0x8000000000008002, 0x8000000000000080,
        0x000000000000800a, 0x800000008000000a,
        0x8000000080008081, 0x8000000000008080,
        0x0000000080000001, 0x8000000080008008
    ]

    private static let rotc: [Int] = [
         1,  3,  6, 10, 15, 21, 28, 36, 45, 55,  2, 14,
        27, 41, 56,  8, 25, 43, 62, 18, 39, 61, 20, 44
    ]

    private static let piln: [Int] = [
        10,  7, 11, 17, 18,  3,  5, 16,  8, 21, 24,  4,
        15, 23, 19, 13, 12,  2, 20, 14, 22,  9,  6,  1
    ]

    // MARK: - Keccak Permutation

    private static func rotl64(_ x: UInt64, _ n: Int) -> UInt64 {
        return (x << n) | (x >> (64 - n))
    }

    private static func keccakf(_ st: inout [UInt64]) {
        for round in 0..<24 {
            var bc = [UInt64](repeating: 0, count: 5)

            // Theta
            for i in 0..<5 {
                bc[i] = st[i] ^ st[i + 5] ^ st[i + 10] ^ st[i + 15] ^ st[i + 20]
            }
            for i in 0..<5 {
                let t = bc[(i + 4) % 5] ^ rotl64(bc[(i + 1) % 5], 1)
                for j in stride(from: 0, to: 25, by: 5) {
                    st[j + i] ^= t
                }
            }

            // Rho + Pi
            var t = st[1]
            for i in 0..<24 {
                let j = piln[i]
                let bc0 = st[j]
                st[j] = rotl64(t, rotc[i])
                t = bc0
            }

            // Chi
            for j in stride(from: 0, to: 25, by: 5) {
                let a0 = st[j], a1 = st[j+1], a2 = st[j+2], a3 = st[j+3], a4 = st[j+4]
                st[j + 0] ^= (~a1) & a2
                st[j + 1] ^= (~a2) & a3
                st[j + 2] ^= (~a3) & a4
                st[j + 3] ^= (~a4) & a0
                st[j + 4] ^= (~a0) & a1
            }

            // Iota
            st[0] ^= rndc[round]
        }
    }

    // MARK: - Public API

    /// Computes the Keccak-256 hash of the input string.
    /// Returns a 64-character lowercase hex string.
    static func Keccak256(data: String) -> String {
        let input = Array(data.utf8)
        let hash = keccak256Bytes(input)
        return "0x" + hash.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Core Hash

    internal static func keccak256Bytes(_ input: [UInt8]) -> [UInt8] {
        let rate = 136
        var st = [UInt64](repeating: 0, count: 25)
        var inlen = input.count
        var offset = 0

        // Helper: XOR bytes into the state (little-endian)
        func xorIntoState(_ bytes: [UInt8], from start: Int, count: Int) {
            for i in 0..<count {
                let wordIndex = i / 8
                let byteShift = (i % 8) * 8
                st[wordIndex] ^= UInt64(bytes[start + i]) << byteShift
            }
        }

        // Absorb full blocks
        while inlen >= rate {
            xorIntoState(input, from: offset, count: rate)
            keccakf(&st)
            offset += rate
            inlen  -= rate
        }

        // Final block + padding
        var temp = [UInt8](repeating: 0, count: 144)
        if inlen > 0 {
            temp[0..<inlen] = input[offset..<(offset + inlen)]
        }
        temp[inlen]     = 0x01  // Keccak domain suffix
        temp[rate - 1] |= 0x80  // Multi-rate padding

        xorIntoState(temp, from: 0, count: rate)
        keccakf(&st)

        // Squeeze 32 bytes (little-endian)
        var out = [UInt8](repeating: 0, count: 32)
        for i in 0..<32 {
            out[i] = UInt8((st[i / 8] >> ((i % 8) * 8)) & 0xFF)
        }
        return out
    }
}
