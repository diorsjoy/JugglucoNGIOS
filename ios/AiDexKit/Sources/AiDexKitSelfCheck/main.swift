// Mirrors the decode assertions from
// Common/src/test/java/tk/glucodata/drivers/aidex/native/protocol/AiDexParserDataFrameTests.kt
// so the Swift and Kotlin parsers agree on real captured frames.
// Run with `swift run` (Debug config — asserts are stripped in Release).

import AiDexKit

func buildFrame(offsetMinutes: Int, glucosePacked: Int, i1Raw: Int, i2Raw: Int) -> [UInt8] {
    var frame = [UInt8](repeating: 0, count: 17)
    frame[0] = 0x01
    frame[4] = UInt8(offsetMinutes & 0xFF)
    frame[5] = UInt8((offsetMinutes >> 8) & 0xFF)
    frame[6] = UInt8(glucosePacked & 0xFF)
    frame[7] = UInt8((glucosePacked >> 8) & 0xFF)
    frame[8] = UInt8(i1Raw & 0xFF)
    frame[9] = UInt8((i1Raw >> 8) & 0xFF)
    frame[10] = UInt8(i2Raw & 0xFF)
    frame[11] = UInt8((i2Raw >> 8) & 0xFF)
    return frame
}

func approxEqual(_ a: Float, _ b: Float, _ tol: Float = 0.001) -> Bool { abs(a - b) <= tol }

// 43 minutes into the session, glucose 63 mg/dL, i1 8.47, i2 29.50.
let documentedFrame = AiDexParser.dataFromHex("01 00 02 00 2B 00 3F 84 4F 03 86 0B 43 02 00 7D CE")
let docParsed = AiDexParser.parseDataFrame(documentedFrame)!
assert(docParsed.timeOffsetMinutes == 43)
assert(approxEqual(docParsed.glucoseMgDl, 63))
assert(approxEqual(docParsed.i1, 8.47))
assert(approxEqual(docParsed.i2, 29.50))
assert(docParsed.isValid)

let f = buildFrame(offsetMinutes: 2285, glucosePacked: 0x8051, i1Raw: 1013, i2Raw: 3400)
let fParsed = AiDexParser.parseDataFrame(f)!
assert(fParsed.timeOffsetMinutes == 2285)
assert(f[4] == 0xED && f[5] == 0x08)
assert(approxEqual(fParsed.glucoseMgDl, 81))

let f1 = buildFrame(offsetMinutes: 2285, glucosePacked: 0x8051, i1Raw: 1013, i2Raw: 3400)
let f2 = buildFrame(offsetMinutes: 2286, glucosePacked: 0x8052, i1Raw: 1025, i2Raw: 3400)
let f3 = buildFrame(offsetMinutes: 2287, glucosePacked: 0x8053, i1Raw: 1025, i2Raw: 3400)
assert(AiDexParser.parseDataFrame(f1)!.timeOffsetMinutes == 2285)
assert(AiDexParser.parseDataFrame(f2)!.timeOffsetMinutes == 2286)
assert(AiDexParser.parseDataFrame(f3)!.timeOffsetMinutes == 2287)

assert(AiDexParser.parseStatusFrame([0x02, 0, 0, 0, 0]) == StatusFrame(header: 2))
assert(AiDexParser.parseStatusFrame([0x02, 0]) == nil)

// startOffset = 10, two rows: (glucose 300, status set), (sentinel 1023)
let historyPayload = AiDexParser.dataFromHex("0A 00 2C 05 FF 03")
let historyRows = AiDexParser.parseHistoryResponse(historyPayload)
assert(historyRows.count == 2)
assert(historyRows[0].timeOffsetMinutes == 10)
assert(historyRows[0].glucoseMgDl == 300)
assert(historyRows[0].statusBit)
assert(!historyRows[0].isSentinel)
assert(historyRows[1].glucoseMgDl == AiDexOpcodes.SENTINEL_GLUCOSE)
assert(historyRows[1].isSentinel)

// startOffset = 0, row0 all-zero (skipped), row1 i1=847 i2=2950 vc=50
let briefPayload = AiDexParser.dataFromHex("00 00 00 00 00 00 00 4F 03 86 0B 32")
let briefRows = AiDexParser.parseBriefHistoryResponse(briefPayload)
assert(briefRows.count == 1)
assert(briefRows[0].timeOffsetMinutes == 1)
assert(approxEqual(briefRows[0].i1, 8.47))
assert(approxEqual(briefRows[0].i2, 29.50))

assert(AiDexParser.isHandshakeEcho([0x10, 0x01], [0x10, 0xFF]))
assert(!AiDexParser.isHandshakeEcho([0x10], [0x11]))
assert(!AiDexParser.isHandshakeEcho([], [0x10]))

let hexBytes: [UInt8] = [0x01, 0xAB, 0xFF]
assert(AiDexParser.dataFromHex(AiDexParser.hexString(hexBytes)) == hexBytes)
assert(AiDexParser.compactHex(hexBytes) == "01ABFF")

assert(AiDexOpcodes.isAiDexDevice("AiDex-1234"))
assert(AiDexOpcodes.isAiDexDevice("LINX-9"))
assert(!AiDexOpcodes.isAiDexDevice("Dexcom7"))
assert(!AiDexOpcodes.isAiDexDevice(nil))

// Documented test vector from SerialCrypto.kt, verified against a real HCI trace for sensor 2222267V4E.
let secret = SerialCrypto.deriveSecret("2222267V4E")
let iv = SerialCrypto.deriveIv("2222267V4E")
assert(AiDexParser.compactHex(secret).lowercased() == "4b76169576da80e4eeacf886230873d2")
assert(AiDexParser.compactHex(iv).lowercased() == "14cb6a3a39b96c448ebc39185f70f8aa")
assert(SerialCrypto.stripPrefix("AiDEX X-2222267V4E") == "2222267V4E")
assert(SerialCrypto.stripPrefix("X-2222267V4E") == "2222267V4E")

// Crc16CcittFalse documented commands from Crc16CcittFalse.kt.
assert(Crc16CcittFalse.makeCommand(0x10, []) == [0x10, 0xC1, 0xF3])
assert(Crc16CcittFalse.makeCommand(0x11, []) == [0x11, 0xE0, 0xE3])
assert(Crc16CcittFalse.makeCommand(0xF2, []) == [0xF2, 0xAD, 0x2E])

// AES-CFB128 round trip + BOND decrypt/CRC-8 gate.
let key = [UInt8](repeating: 0x42, count: 16)
let roundTripIv = [UInt8](repeating: 0x07, count: 16)
let plaintext: [UInt8] = Array("AiDex protocol!!".utf8) // 16 bytes
let ciphertext = AesCfb128.encrypt(plaintext, key: key, iv: roundTripIv)!
assert(AesCfb128.decrypt(ciphertext, key: key, iv: roundTripIv)! == plaintext)

var bondPlaintext = [UInt8](repeating: 0xAB, count: 16)
bondPlaintext.append(UInt8(Crc8Maxim.checksum(bondPlaintext)))
let bondCiphertextGeneric = AesCfb128.encrypt(bondPlaintext, key: key, iv: roundTripIv)!
let recoveredSessionKey = AesCfb128.decryptBondData(bondCiphertextGeneric, pairKey: key, iv: roundTripIv)
assert(recoveredSessionKey == Array(bondPlaintext[0..<16]))

let exchange = AiDexKeyExchange(serial: "X-2222267V4E")
exchange.onPairKeyReceived(key)
let bondCiphertextForSerial = AesCfb128.encrypt(bondPlaintext, key: key, iv: exchange.snIv)!
assert(exchange.decryptBond(bondCiphertextForSerial))
assert(exchange.isComplete)
assert(exchange.getPostBondConfig() != nil)

print("AiDexKit self-check: all assertions passed")
