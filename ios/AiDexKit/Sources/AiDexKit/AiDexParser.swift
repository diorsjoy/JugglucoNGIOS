// AiDexParser.swift — ported 1:1 from
// Common/src/main/java/tk/glucodata/drivers/aidex/native/protocol/AiDexParser.kt
// Keep in sync with the Kotlin source: both drive the same AiDex wire protocol.

import Foundation

public struct GlucoseFrame: Equatable {
    public let opcode: Int
    public let timeOffsetMinutes: Int
    public let glucoseMgDl: Float
    public let rawGlucosePacked: Int
    public let i1: Float
    public let i2: Float
    public let crc16: Int
    public let isValid: Bool
}

public struct StatusFrame: Equatable {
    public let header: Int
    public init(header: Int) { self.header = header }
}

public struct CalibratedHistoryEntry: Equatable {
    public let timeOffsetMinutes: Int
    public let glucoseMgDl: Int
    public let statusBit: Bool
    public let isSentinel: Bool
}

public struct AdcHistoryEntry: Equatable {
    public let timeOffsetMinutes: Int
    public let i1: Float
    public let i2: Float
    public let vc: Float
    public let rawValue: Float
    public let sensorGlucose: Float
}

public struct CalibrationRecord: Equatable {
    public let index: Int
    public let timeOffsetMinutes: Int
    public let referenceGlucoseMgDl: Int
    public let calibrationFactor: Float
    public let calibrationOffset: Float
}

public enum AiDexParser {

    public struct StartupDeviceInfo: Equatable {
        public let firmwareVersion: String
        public let hardwareVersion: String
        public let wearDays: Int
        public let modelName: String
    }

    public struct LocalStartTime: Equatable {
        public let year: Int
        public let month: Int
        public let day: Int
        public let hour: Int
        public let minute: Int
        public let second: Int
        public let tzQuarters: Int
        public let dstQuarters: Int

        public var isAllZeros: Bool {
            year == 0 && month == 0 && day == 0 && hour == 0 && minute == 0 && second == 0
        }
    }

    public struct DefaultParamChunk: Equatable {
        public let leadByte: Int
        public let totalWords: Int
        public let startIndex: Int
        public let rawChunk: [UInt8]

        public var nextStartIndex: Int { startIndex + rawChunk.count / 2 }
        public var isComplete: Bool { nextStartIndex > totalWords }
    }

    // -- F003 Frame Classification --

    public enum FrameType { case data, status, unknown }

    public static func classifyFrame(_ data: [UInt8]) -> FrameType {
        switch data.count {
        case AiDexOpcodes.DATA_FRAME_LENGTH: return .data
        case AiDexOpcodes.STATUS_FRAME_LENGTH: return .status
        default: return .unknown
        }
    }

    // -- 17-Byte Data Frame Parsing --

    public static func parseDataFrame(_ data: [UInt8]) -> GlucoseFrame? {
        guard data.count == AiDexOpcodes.DATA_FRAME_LENGTH else { return nil }

        let opcode = Int(data[0])
        let timeOffsetMinutes = u16LE(data, 4)
        let glucosePacked = u16LE(data, 6)
        let rawGlucose = glucosePacked & AiDexOpcodes.GLUCOSE_MASK
        let i1Raw = u16LE(data, 8)
        let i2Raw = u16LE(data, 10)
        let crc16 = u16LE(data, 15)

        let i1 = Float(i1Raw) / 100
        let i2 = Float(i2Raw) / 100

        let scaling = AiDexOpcodes.scalingFactor(opcode)
        let glucoseMgDl = scaling != nil ? Float(rawGlucose) * scaling! : Float(rawGlucose)

        let isSentinel = rawGlucose == AiDexOpcodes.SENTINEL_GLUCOSE
        let isInRange = rawGlucose >= AiDexOpcodes.MIN_VALID_GLUCOSE && rawGlucose <= AiDexOpcodes.MAX_VALID_GLUCOSE
        let isValid = !isSentinel && isInRange

        return GlucoseFrame(
            opcode: opcode,
            timeOffsetMinutes: timeOffsetMinutes,
            glucoseMgDl: glucoseMgDl,
            rawGlucosePacked: glucosePacked,
            i1: i1,
            i2: i2,
            crc16: crc16,
            isValid: isValid
        )
    }

    // -- 5-Byte Status Frame Parsing --

    public static func parseStatusFrame(_ data: [UInt8]) -> StatusFrame? {
        guard data.count == AiDexOpcodes.STATUS_FRAME_LENGTH else { return nil }
        return StatusFrame(header: Int(data[0]))
    }

    // -- History Parsing: GET_HISTORIES_RAW (0x23) --

    public static func parseHistoryResponse(_ data: [UInt8]) -> [CalibratedHistoryEntry] {
        guard data.count >= 4 else { return [] }

        let startOffset = u16LE(data, 0)
        let bodyOffset = 2
        let bodySize = data.count - bodyOffset
        let rowCount = bodySize / AiDexOpcodes.HISTORY_RAW_ROW_SIZE

        return (0..<rowCount).map { i in
            let off = bodyOffset + i * AiDexOpcodes.HISTORY_RAW_ROW_SIZE
            let b0 = Int(data[off])
            let b1 = Int(data[off + 1])

            let glucose = b0 | ((b1 & 0x03) << 8)
            let statusBit = (b1 & 0x04) != 0
            let isSentinel = glucose == AiDexOpcodes.SENTINEL_GLUCOSE

            return CalibratedHistoryEntry(
                timeOffsetMinutes: startOffset + i,
                glucoseMgDl: glucose,
                statusBit: statusBit,
                isSentinel: isSentinel
            )
        }
    }

    // -- History Parsing: GET_HISTORIES (0x24) --

    public static func parseBriefHistoryResponse(_ data: [UInt8]) -> [AdcHistoryEntry] {
        guard data.count >= 7 else { return [] }

        let startOffset = u16LE(data, 0)
        let bodyOffset = 2
        let bodySize = data.count - bodyOffset
        let rowCount = bodySize / AiDexOpcodes.HISTORY_BRIEF_ROW_SIZE

        return (0..<rowCount).compactMap { i -> AdcHistoryEntry? in
            let off = bodyOffset + i * AiDexOpcodes.HISTORY_BRIEF_ROW_SIZE
            let i1Raw = u16LE(data, off)
            let i2Raw = u16LE(data, off + 2)
            let vcRaw = Int(data[off + 4])

            if i1Raw == 0 && i2Raw == 0 && vcRaw == 0 { return nil }

            let i1 = Float(i1Raw) / 100
            let i2 = Float(i2Raw) / 100

            return AdcHistoryEntry(
                timeOffsetMinutes: startOffset + i,
                i1: i1,
                i2: i2,
                vc: Float(vcRaw) / 100,
                rawValue: i1 * 10,
                sensorGlucose: i1 * 18.0182
            )
        }
    }

    // -- Calibration Parsing (0x27) --

    public static func parseCalibrationResponse(_ data: [UInt8]) -> [CalibrationRecord] {
        guard data.count >= 10 else { return [] }

        let startIndex = u16LE(data, 0)
        guard startIndex <= 10000 else { return [] }

        let bodyOffset = 2
        let bodySize = data.count - bodyOffset
        guard bodySize % AiDexOpcodes.CALIBRATION_ROW_SIZE == 0 else { return [] }

        let rowCount = bodySize / AiDexOpcodes.CALIBRATION_ROW_SIZE

        return (0..<rowCount).map { i in
            let off = bodyOffset + i * AiDexOpcodes.CALIBRATION_ROW_SIZE
            let timeOffset = u16LE(data, off)
            let reference = u16LE(data, off + 2)
            let cfRaw = u16LE(data, off + 4)
            let offsetRaw = s16LE(data, off + 6)

            return CalibrationRecord(
                index: startIndex + i,
                timeOffsetMinutes: timeOffset,
                referenceGlucoseMgDl: reference,
                calibrationFactor: Float(cfRaw) / 100,
                calibrationOffset: Float(offsetRaw) / 100
            )
        }
    }

    // -- Handshake Echo Validation --

    public static func isHandshakeEcho(_ sent: [UInt8], _ received: [UInt8]) -> Bool {
        guard !sent.isEmpty, !received.isEmpty else { return false }
        return sent[0] == received[0]
    }

    // -- Default Param Parsing (0x31) --

    public static func parseStartupDeviceInfoPayload(_ payload: [UInt8]) -> StartupDeviceInfo? {
        guard payload.count >= 16 else { return nil }
        guard u16LE(payload, 0) == 0 else { return nil }

        let fwMajor = Int(payload[2])
        let fwMinor = Int(payload[3])
        let hwMajor = Int(payload[4])
        let hwMinor = Int(payload[5])
        let wearDays = Int(payload[6])
        let modelBytes = Array(payload[8...])
        let nullIdx = modelBytes.firstIndex(of: 0)
        let modelBytesTrimmed = nullIdx.map { Array(modelBytes[..<$0]) } ?? modelBytes
        let modelName = String(decoding: modelBytesTrimmed, as: UTF8.self)
            .trimmingCharacters(in: .whitespaces)

        guard !modelName.isEmpty else { return nil }

        return StartupDeviceInfo(
            firmwareVersion: "\(fwMajor).\(fwMinor)",
            hardwareVersion: "\(hwMajor).\(hwMinor)",
            wearDays: wearDays,
            modelName: modelName
        )
    }

    public static func parseStartupDeviceInfoFrame(_ frame: [UInt8], payloadEndExclusive: Int? = nil) -> StartupDeviceInfo? {
        let end = payloadEndExclusive ?? frame.count
        guard end > 1, end <= frame.count else { return nil }
        if let info = parseStartupDeviceInfoPayload(Array(frame[1..<end])) { return info }
        guard end > 2 else { return nil }
        return parseStartupDeviceInfoPayload(Array(frame[2..<end]))
    }

    public static func parseLocalStartTimePayload(_ payload: [UInt8]) -> LocalStartTime? {
        guard payload.count >= 7 else { return nil }

        let parsed = LocalStartTime(
            year: u16LE(payload, 0),
            month: Int(payload[2]),
            day: Int(payload[3]),
            hour: Int(payload[4]),
            minute: Int(payload[5]),
            second: Int(payload[6]),
            tzQuarters: payload.count >= 8 ? Int(Int8(bitPattern: payload[7])) : 0,
            dstQuarters: payload.count >= 9 ? Int(payload[8]) : 0
        )

        if parsed.isAllZeros { return parsed }

        let plausibleDate = (2020...2040).contains(parsed.year) &&
            (1...12).contains(parsed.month) &&
            (1...31).contains(parsed.day) &&
            (0...23).contains(parsed.hour) &&
            (0...59).contains(parsed.minute) &&
            (0...59).contains(parsed.second)

        return plausibleDate ? parsed : nil
    }

    public static func parseDefaultParamChunk(_ payload: [UInt8]) -> DefaultParamChunk? {
        guard payload.count >= 5 else { return nil }

        let totalWords = Int(payload[1])
        let startIndex = Int(payload[2])
        let rawChunk = Array(payload[3...])

        guard totalWords > 0, startIndex > 0, startIndex <= totalWords else { return nil }
        guard !rawChunk.isEmpty, rawChunk.count % 2 == 0 else { return nil }

        return DefaultParamChunk(leadByte: Int(payload[0]), totalWords: totalWords, startIndex: startIndex, rawChunk: rawChunk)
    }

    public static func appendDefaultParamChunk(_ buffer: [UInt8]?, _ chunk: DefaultParamChunk) -> [UInt8] {
        let requiredSize = 1 + chunk.totalWords * 2
        var target = (buffer?.count ?? 0) >= requiredSize ? buffer! : [UInt8](repeating: 0, count: requiredSize)
        if chunk.startIndex == 1 {
            target[0] = UInt8(chunk.leadByte)
        }
        let destOffset = chunk.startIndex == 1 ? 1 : max(chunk.startIndex * 2 - 1, 1)
        let copyLen = min(chunk.rawChunk.count, target.count - destOffset)
        if copyLen > 0 {
            target.replaceSubrange(destOffset..<(destOffset + copyLen), with: chunk.rawChunk[0..<copyLen])
        }
        return target
    }

    public static func defaultParamRawHex(_ buffer: [UInt8]?, _ totalWords: Int) -> String? {
        guard let buffer, totalWords > 0 else { return nil }
        let expectedLen = 1 + totalWords * 2
        guard buffer.count >= expectedLen else { return nil }
        return compactHex(Array(buffer[0..<expectedLen]))
    }

    // -- Hex Utilities --

    public static func hexString(_ data: [UInt8]) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    public static func compactHex(_ data: [UInt8]) -> String {
        data.map { String(format: "%02X", $0) }.joined()
    }

    public static func dataFromHex(_ hex: String) -> [UInt8] {
        let clean = hex.replacingOccurrences(of: " ", with: "")
        var result: [UInt8] = []
        var idx = clean.startIndex
        while idx < clean.endIndex {
            let next = clean.index(idx, offsetBy: 2)
            result.append(UInt8(clean[idx..<next], radix: 16)!)
            idx = next
        }
        return result
    }

    // -- Internal helpers --

    private static func u16LE(_ data: [UInt8], _ offset: Int) -> Int {
        Int(data[offset]) | (Int(data[offset + 1]) << 8)
    }

    private static func s16LE(_ data: [UInt8], _ offset: Int) -> Int {
        let unsigned = u16LE(data, offset)
        return unsigned >= 0x8000 ? unsigned - 0x10000 : unsigned
    }
}
