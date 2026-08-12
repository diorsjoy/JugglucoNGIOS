// AiDexKeyExchange.swift — ported 1:1 from
// Common/src/main/java/tk/glucodata/drivers/aidex/native/protocol/AiDexKeyExchange.kt

import Foundation

public final class AiDexKeyExchange {
    public let bareSerial: String
    public let snSecret: [UInt8]
    public let snIv: [UInt8]

    public private(set) var pairKey: [UInt8]?
    public private(set) var sessionKey: [UInt8]?

    public var isComplete: Bool { sessionKey != nil }

    public init(serial: String) {
        self.bareSerial = SerialCrypto.stripPrefix(serial)
        self.snSecret = SerialCrypto.deriveSecret(bareSerial)
        self.snIv = SerialCrypto.deriveIv(bareSerial)
    }

    public func getChallenge() -> [UInt8] { snSecret }

    public func onPairKeyReceived(_ data: [UInt8]) {
        pairKey = data
    }

    @discardableResult
    public func decryptBond(_ bondData: [UInt8]) -> Bool {
        guard let pk = pairKey, let sk = AesCfb128.decryptBondData(bondData, pairKey: pk, iv: snIv) else { return false }
        sessionKey = sk
        return true
    }

    public func getPostBondConfig() -> [UInt8]? {
        guard let sk = sessionKey else { return nil }
        return AesCfb128.encrypt([0x10, 0xC1, 0xF3], key: sk, iv: snIv)
    }

    public func encrypt(_ plaintext: [UInt8]) -> [UInt8]? {
        guard let sk = sessionKey else { return nil }
        return AesCfb128.encrypt(plaintext, key: sk, iv: snIv)
    }

    public func decrypt(_ ciphertext: [UInt8]) -> [UInt8]? {
        guard let sk = sessionKey else { return nil }
        return AesCfb128.decrypt(ciphertext, key: sk, iv: snIv)
    }

    public func reset() {
        pairKey = nil
        sessionKey = nil
    }
}

// AiDexCommandBuilder.swift — ported 1:1 from
// Common/src/main/java/tk/glucodata/drivers/aidex/native/protocol/AiDexCommandBuilder.kt
public final class AiDexCommandBuilder {
    private let keyExchange: AiDexKeyExchange

    public init(keyExchange: AiDexKeyExchange) {
        self.keyExchange = keyExchange
    }

    public func buildEncrypted(_ opcode: Int, _ params: [Int] = []) -> [UInt8]? {
        keyExchange.encrypt(Crc16CcittFalse.makeCommand(opcode, params))
    }

    public func getStartupDeviceInfo() -> [UInt8]? { buildEncrypted(AiDexOpcodes.GET_STARTUP_DEVICE_INFO) }
    public func getBroadcastData() -> [UInt8]? { buildEncrypted(AiDexOpcodes.GET_BROADCAST_DATA) }
    public func getAutoUpdateStatus() -> [UInt8]? { buildEncrypted(AiDexOpcodes.GET_AUTO_UPDATE_STATUS) }
    public func setAutoUpdateStatus(_ enabled: Bool = true) -> [UInt8]? {
        buildEncrypted(AiDexOpcodes.SET_AUTO_UPDATE_STATUS, [enabled ? 0x01 : 0x00])
    }
    public func getHistoriesRaw(_ offset: Int) -> [UInt8]? {
        buildEncrypted(AiDexOpcodes.GET_HISTORIES_RAW, [offset & 0xFF, (offset >> 8) & 0xFF])
    }
    public func getHistories(_ offset: Int) -> [UInt8]? {
        buildEncrypted(AiDexOpcodes.GET_HISTORIES, [offset & 0xFF, (offset >> 8) & 0xFF])
    }
    public func setCalibration(offsetMinutes: Int, glucoseMgDl: Int) -> [UInt8]? {
        buildEncrypted(AiDexOpcodes.SET_CALIBRATION, [
            offsetMinutes & 0xFF, (offsetMinutes >> 8) & 0xFF,
            glucoseMgDl & 0xFF, (glucoseMgDl >> 8) & 0xFF,
        ])
    }
}
