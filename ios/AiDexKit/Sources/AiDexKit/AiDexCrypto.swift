// AiDexCrypto.swift — ported 1:1 from
// Common/src/main/java/tk/glucodata/drivers/aidex/native/crypto/{Crc8Maxim,Crc16CcittFalse,SerialCrypto,AesCfb128}.kt
// AES-ECB/MD5 building blocks come from CommonCrypto instead of reinventing them.

import Foundation
import CommonCrypto

public enum Crc16CcittFalse {
    public static func checksum(_ data: [UInt8]) -> Int {
        var crc = 0xFFFF
        for b in data {
            crc ^= (Int(b) << 8)
            for _ in 0..<8 {
                crc = (crc & 0x8000) != 0 ? (crc << 1) ^ 0x1021 : crc << 1
            }
            crc &= 0xFFFF
        }
        return crc
    }

    public static func makeCommand(_ opcode: Int, _ params: [Int] = []) -> [UInt8] {
        var payload: [UInt8] = [UInt8(opcode & 0xFF)]
        payload.append(contentsOf: params.map { UInt8($0 & 0xFF) })
        let crc = checksum(payload)
        payload.append(UInt8(crc & 0xFF))
        payload.append(UInt8((crc >> 8) & 0xFF))
        return payload
    }

    public static func makeCommandWithU16(_ opcode: Int, _ param: Int) -> [UInt8] {
        makeCommand(opcode, [param & 0xFF, (param >> 8) & 0xFF])
    }
}

public enum Crc8Maxim {
    private static let table: [Int] = [
        0x00, 0x5e, 0xbc, 0xe2, 0x61, 0x3f, 0xdd, 0x83, 0xc2, 0x9c, 0x7e, 0x20, 0xa3, 0xfd, 0x1f, 0x41,
        0x9d, 0xc3, 0x21, 0x7f, 0xfc, 0xa2, 0x40, 0x1e, 0x5f, 0x01, 0xe3, 0xbd, 0x3e, 0x60, 0x82, 0xdc,
        0x23, 0x7d, 0x9f, 0xc1, 0x42, 0x1c, 0xfe, 0xa0, 0xe1, 0xbf, 0x5d, 0x03, 0x80, 0xde, 0x3c, 0x62,
        0xbe, 0xe0, 0x02, 0x5c, 0xdf, 0x81, 0x63, 0x3d, 0x7c, 0x22, 0xc0, 0x9e, 0x1d, 0x43, 0xa1, 0xff,
        0x46, 0x18, 0xfa, 0xa4, 0x27, 0x79, 0x9b, 0xc5, 0x84, 0xda, 0x38, 0x66, 0xe5, 0xbb, 0x59, 0x07,
        0xdb, 0x85, 0x67, 0x39, 0xba, 0xe4, 0x06, 0x58, 0x19, 0x47, 0xa5, 0xfb, 0x78, 0x26, 0xc4, 0x9a,
        0x65, 0x3b, 0xd9, 0x87, 0x04, 0x5a, 0xb8, 0xe6, 0xa7, 0xf9, 0x1b, 0x45, 0xc6, 0x98, 0x7a, 0x24,
        0xf8, 0xa6, 0x44, 0x1a, 0x99, 0xc7, 0x25, 0x7b, 0x3a, 0x64, 0x86, 0xd8, 0x5b, 0x05, 0xe7, 0xb9,
        0x8c, 0xd2, 0x30, 0x6e, 0xed, 0xb3, 0x51, 0x0f, 0x4e, 0x10, 0xf2, 0xac, 0x2f, 0x71, 0x93, 0xcd,
        0x11, 0x4f, 0xad, 0xf3, 0x70, 0x2e, 0xcc, 0x92, 0xd3, 0x8d, 0x6f, 0x31, 0xb2, 0xec, 0x0e, 0x50,
        0xaf, 0xf1, 0x13, 0x4d, 0xce, 0x90, 0x72, 0x2c, 0x6d, 0x33, 0xd1, 0x8f, 0x0c, 0x52, 0xb0, 0xee,
        0x32, 0x6c, 0x8e, 0xd0, 0x53, 0x0d, 0xef, 0xb1, 0xf0, 0xae, 0x4c, 0x12, 0x91, 0xcf, 0x2d, 0x73,
        0xca, 0x94, 0x76, 0x28, 0xab, 0xf5, 0x17, 0x49, 0x08, 0x56, 0xb4, 0xea, 0x69, 0x37, 0xd5, 0x8b,
        0x57, 0x09, 0xeb, 0xb5, 0x36, 0x68, 0x8a, 0xd4, 0x95, 0xcb, 0x29, 0x77, 0xf4, 0xaa, 0x48, 0x16,
        0xe9, 0xb7, 0x55, 0x0b, 0x88, 0xd6, 0x34, 0x6a, 0x2b, 0x75, 0x97, 0xc9, 0x4a, 0x14, 0xf6, 0xa8,
        0x74, 0x2a, 0xc8, 0x96, 0x15, 0x4b, 0xa9, 0xf7, 0xb6, 0xe8, 0x0a, 0x54, 0xd7, 0x89, 0x6b, 0x35,
    ]

    public static func checksum(_ data: [UInt8]) -> Int {
        var acc = 0
        for b in data { acc = table[Int(b) ^ acc] }
        return acc & 0xFF
    }
}

public enum SerialCrypto {
    public static func charToNumeric(_ c: Character) -> Int {
        guard let ascii = c.asciiValue else { return 0 }
        switch ascii {
        case 48...57: return Int(ascii) - 48        // '0'-'9'
        case 65...90: return Int(ascii) - 65 + 10    // 'A'-'Z'
        case 97...122: return Int(ascii) - 97 + 10   // 'a'-'z'
        default: return 0
        }
    }

    public static func snToBytes(_ sn: String) -> [UInt8] {
        sn.map { UInt8(charToNumeric($0) & 0xFF) }
    }

    public static func deriveSecret(_ sn: String) -> [UInt8] {
        md5(snToBytes(sn).map { UInt8((Int($0) &* 13 &+ 61) & 0xFF) })
    }

    public static func deriveIv(_ sn: String) -> [UInt8] {
        md5(snToBytes(sn).map { UInt8((Int($0) &* 17 &+ 19) & 0xFF) })
    }

    public static func stripPrefix(_ serial: String) -> String {
        let prefixes = ["AiDEX X-", "AIDEX X-", "aidex x-", "AiDex X-", "X-"]
        for prefix in prefixes where serial.hasPrefix(prefix) {
            return String(serial.dropFirst(prefix.count))
        }
        if let range = serial.range(of: "X-", options: .caseInsensitive) {
            let afterDash = String(serial[range.upperBound...])
            if (8...14).contains(afterDash.count), afterDash.allSatisfy({ $0.isLetter || $0.isNumber }) {
                return afterDash
            }
        }
        return serial
    }

    private static func md5(_ data: [UInt8]) -> [UInt8] {
        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        _ = data.withUnsafeBufferPointer { buf in
            CC_MD5(buf.baseAddress, CC_LONG(data.count), &digest)
        }
        return digest
    }
}

public enum AesCfb128 {
    private static let blockSize = 16

    public static func decrypt(_ ciphertext: [UInt8], key: [UInt8], iv: [UInt8]) -> [UInt8]? {
        guard key.count == 16, iv.count == 16, !ciphertext.isEmpty else { return nil }
        var result = [UInt8](repeating: 0, count: ciphertext.count)
        var feedback = iv
        var offset = 0
        while offset < ciphertext.count {
            let chunkSize = min(blockSize, ciphertext.count - offset)
            guard let encryptedFeedback = ecbEncrypt(feedback, key: key) else { return nil }
            for i in 0..<chunkSize {
                result[offset + i] = ciphertext[offset + i] ^ encryptedFeedback[i]
            }
            if chunkSize == blockSize {
                feedback = Array(ciphertext[offset..<(offset + blockSize)])
            }
            offset += chunkSize
        }
        return result
    }

    public static func encrypt(_ plaintext: [UInt8], key: [UInt8], iv: [UInt8]) -> [UInt8]? {
        guard key.count == 16, iv.count == 16, !plaintext.isEmpty else { return nil }
        var result = [UInt8](repeating: 0, count: plaintext.count)
        var feedback = iv
        var offset = 0
        while offset < plaintext.count {
            let chunkSize = min(blockSize, plaintext.count - offset)
            guard let encryptedFeedback = ecbEncrypt(feedback, key: key) else { return nil }
            for i in 0..<chunkSize {
                result[offset + i] = plaintext[offset + i] ^ encryptedFeedback[i]
            }
            if chunkSize == blockSize {
                feedback = Array(result[offset..<(offset + blockSize)])
            }
            offset += chunkSize
        }
        return result
    }

    public static func decryptBondData(_ bondData: [UInt8], pairKey: [UInt8], iv: [UInt8]) -> [UInt8]? {
        guard bondData.count == 17, pairKey.count == 16, iv.count == 16 else { return nil }
        guard let decrypted = decrypt(bondData, key: pairKey, iv: iv) else { return nil }
        let sessionKey = Array(decrypted[0..<16])
        let checksumByte = Int(decrypted[16])
        guard checksumByte == Crc8Maxim.checksum(sessionKey) else { return nil }
        return sessionKey
    }

    public static func ecbEncrypt(_ block: [UInt8], key: [UInt8]) -> [UInt8]? {
        guard block.count == 16, key.count == 16 else { return nil }
        var output = [UInt8](repeating: 0, count: block.count + kCCBlockSizeAES128)
        var outLength = 0
        let status = CCCrypt(
            CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionECBMode),
            key, key.count, nil,
            block, block.count,
            &output, output.count, &outLength
        )
        guard status == kCCSuccess else { return nil }
        return Array(output.prefix(outLength))
    }
}
