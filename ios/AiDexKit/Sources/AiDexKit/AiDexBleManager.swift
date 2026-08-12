// AiDexBleManager.swift — CoreBluetooth port of the streaming-only path from
// Common/src/main/java/tk/glucodata/drivers/aidex/native/ble/AiDexBleManager.kt
//
// Scope: scan -> connect -> F001/F002/F003 key exchange -> decrypt+parse live F003 glucose frames.
// ponytail: history download, calibration read/write, reconnect/watchdog robustness, and default-param
// provisioning are NOT ported — this is the minimal path to a live glucose value. Add them once this
// core loop is proven against real hardware.

import CoreBluetooth
import Foundation

public protocol AiDexBleManagerDelegate: AnyObject {
    func aiDexManager(_ manager: AiDexBleManager, didUpdateStatus status: String)
    func aiDexManager(_ manager: AiDexBleManager, didReceiveGlucose frame: GlucoseFrame)
}

public final class AiDexBleManager: NSObject {
    private static let serviceF000 = CBUUID(string: "0000181f-0000-1000-8000-00805f9b34fb")
    private static let charF001 = CBUUID(string: "0000f001-0000-1000-8000-00805f9b34fb")
    private static let charF002 = CBUUID(string: "0000f002-0000-1000-8000-00805f9b34fb")
    private static let charF003 = CBUUID(string: "0000f003-0000-1000-8000-00805f9b34fb")

    public weak var delegate: AiDexBleManagerDelegate?

    private let serial: String
    private let keyExchange: AiDexKeyExchange
    private let commandBuilder: AiDexCommandBuilder

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var charF001Ref: CBCharacteristic?
    private var charF002Ref: CBCharacteristic?
    private var challengeWritten = false
    private var bondDataRead = false
    private var f001SubscribeRetries = 0
    private var reconnectingForAuth = false
    private var keyFormationSent = false
    private var gattConnectTime: Date?
    private var reconnectCycles = 0
    private var privatePairingAttempted = false

    public init(serial: String) {
        self.serial = serial
        self.keyExchange = AiDexKeyExchange(serial: serial)
        self.commandBuilder = AiDexCommandBuilder(keyExchange: keyExchange)
        super.init()
        self.central = CBCentralManager(delegate: self, queue: nil)
    }

    private func status(_ s: String) {
        print("[AiDexBleManager] \(s)")
        delegate?.aiDexManager(self, didUpdateStatus: s)
    }

    private func matchesSerial(_ name: String) -> Bool {
        let bare = keyExchange.bareSerial
        return name.range(of: bare, options: .caseInsensitive) != nil
            || name.range(of: serial, options: .caseInsensitive) != nil
            || AiDexOpcodes.isAiDexDevice(name)
    }
}

extension AiDexBleManager: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            status("Bluetooth on — scanning for \(serial)")
            central.scanForPeripherals(withServices: nil, options: nil)
        case .poweredOff:
            status("Bluetooth is off")
        case .unauthorized:
            status("Bluetooth permission denied")
        default:
            status("Bluetooth state: \(central.state.rawValue)")
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""
        guard matchesSerial(name) else { return }
        status("Found \(name), connecting...")
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        reconnectingForAuth = false
        keyFormationSent = false
        f001SubscribeRetries = 0
        privatePairingAttempted = false
        gattConnectTime = Date()
        status("Connected — discovering services")
        peripheral.discoverServices([Self.serviceF000])
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        status("Connect failed: \(error?.localizedDescription ?? "unknown")")
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        keyExchange.reset()
        challengeWritten = false
        bondDataRead = false

        if reconnectingForAuth {
            status("Disconnected — reconnecting for fresh security negotiation")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak central] in
                guard let central else { return }
                central.connect(peripheral, options: nil)
            }
        } else {
            status("Disconnected")
        }
    }
}

extension AiDexBleManager: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceF000 }) else {
            status("SERVICE_F000 not found")
            return
        }
        peripheral.discoverCharacteristics([Self.charF001, Self.charF002, Self.charF003], for: service)
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else { return }
        for c in chars {
            status("Found char \(c.uuid): properties=\(c.properties.rawValue)")
            if c.uuid == Self.charF001 { charF001Ref = c }
            if c.uuid == Self.charF002 { charF002Ref = c }
            // F003 first, then F002, then F001 — mirrors the Android CCCD chain order.
            if c.uuid == Self.charF003 || c.uuid == Self.charF002 || c.uuid == Self.charF001 {
                peripheral.setNotifyValue(true, for: c)
            }
        }

        sendKeyFormationIfNeeded(peripheral: peripheral)
    }

    // Ported from iGlucco's AiDexSensorManager.sendB0AndPair(): this sensor firmware apparently
    // requires one specific "key formation" write to F002 within ~8s of GATT connect before it
    // will accept bonding at all. Sent unencrypted/withoutResponse, matching iGlucco exactly.
    private func sendKeyFormationIfNeeded(peripheral: CBPeripheral) {
        guard !keyFormationSent, let f002 = charF002Ref else { return }
        keyFormationSent = true
        let elapsed = gattConnectTime.map { Date().timeIntervalSince($0) } ?? 0
        let keyCmd = Data([0xB0, 0xC5, 0x80, 0x80])
        peripheral.writeValue(keyCmd, for: f002, type: .withoutResponse)
        status("Sent B0 key formation command to F002 (elapsed=\(String(format: "%.1f", elapsed))s since connect)")
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        status("CCCD updated for \(characteristic.uuid): isNotifying=\(characteristic.isNotifying) error=\(error?.localizedDescription ?? "none")")

        if characteristic.uuid == Self.charF001, error != nil {
            #if os(macOS)
            if !privatePairingAttempted {
                privatePairingAttempted = true
                AiDexPrivatePairing.attempt(peripheral: peripheral, centralManager: central) { [weak self] msg in
                    self?.status(msg)
                }
            }
            #endif

            // Mirrors AiDexBleManager.kt's isAuthRelatedCccdFailure() handling: on an auth-related
            // CCCD failure, Android re-queues F001 and polls bond state every
            // DEFERRED_BOND_CHECK_DELAY_MS (2.5s) for up to DEFERRED_BOND_CHECK_MAX_ATTEMPTS (4) —
            // ~10s total — on the SAME live connection, retrying the same write once bonded.
            // CoreBluetooth has no equivalent bondState read, so we poll by retrying the subscribe
            // itself on the same schedule instead of inspecting bond state directly.
            f001SubscribeRetries += 1
            guard f001SubscribeRetries <= 4 else {
                // Mirrors iGlucco's BLEManager-level fallback: their 30s handshake watchdog
                // force-disconnects and reconnects rather than giving up outright, since flaky
                // firmware sometimes only completes SMP pairing after several full connect cycles.
                reconnectCycles += 1
                guard reconnectCycles <= 5 else {
                    status("F001 pairing failed after \(reconnectCycles) full reconnect cycles — giving up for real. This needs HCI packet capture to diagnose further.")
                    return
                }
                status("F001 subscribe failed \(f001SubscribeRetries) times on this connection — doing full reconnect cycle \(reconnectCycles)/5")
                reconnectingForAuth = true
                central.cancelPeripheralConnection(peripheral)
                return
            }
            status("F001 needs pairing — polling in 2.5s (attempt \(f001SubscribeRetries)/4, matches Android's DEFERRED_BOND_CHECK)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self, weak peripheral] in
                guard let self, let peripheral, let f001 = self.charF001Ref else { return }
                peripheral.setNotifyValue(true, for: f001)
            }
            return
        }

        guard characteristic.uuid == Self.charF001, error == nil, !challengeWritten, let f001 = charF001Ref else { return }
        status("Key exchange: writing challenge to F001 (\(AiDexParser.hexString(keyExchange.getChallenge())))")
        let challenge = Data(keyExchange.getChallenge())
        peripheral.writeValue(challenge, for: f001, type: .withResponse)
        challengeWritten = true
    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        status("Write to \(characteristic.uuid) completed, error=\(error?.localizedDescription ?? "none")")
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value, error == nil else { return }
        let bytes = [UInt8](data)

        switch characteristic.uuid {
        case Self.charF001:
            handleF001(bytes, peripheral: peripheral)
        case Self.charF002:
            handleF002(bytes, peripheral: peripheral)
        case Self.charF003:
            handleF003(bytes)
        default:
            break
        }
    }

    // Step 2: F001 notify carries the 16-byte PAIR key.
    private func handleF001(_ data: [UInt8], peripheral: CBPeripheral) {
        status("F001 notify: len=\(data.count) hex=\(AiDexParser.hexString(data)) challengeWritten=\(challengeWritten) pairKeyAlready=\(keyExchange.pairKey != nil)")
        guard data.count >= 16, challengeWritten, keyExchange.pairKey == nil, let f002 = charF002Ref else { return }
        keyExchange.onPairKeyReceived(Array(data[0..<16]))
        status("Key exchange: PAIR key received — reading BOND from F002")
        if charF002Ref?.properties.contains(.read) == false {
            status("F002 lacks .read property (properties=\(f002.properties.rawValue)) — attempting read anyway")
        }
        peripheral.readValue(for: f002)
    }

    // Step 3/4: F002 read returns 17-byte BOND data -> decrypt to session key, then write post-BOND config to F001.
    private func handleF002(_ data: [UInt8], peripheral: CBPeripheral) {
        status("F002 data: len=\(data.count) hex=\(AiDexParser.hexString(data)) bondDataRead=\(bondDataRead)")
        if !bondDataRead, data.count == 17 {
            bondDataRead = true
            guard let pairKey = keyExchange.pairKey else {
                status("BOND decryption skipped: no PAIR key yet")
                return
            }
            guard keyExchange.decryptBond(data) else {
                let decrypted = AesCfb128.decrypt(data, key: pairKey, iv: keyExchange.snIv)
                status("BOND decryption/CRC failed. Raw decrypt attempt: \(decrypted.map(AiDexParser.hexString) ?? "nil")")
                return
            }
            status("Session key established")
            guard let config = keyExchange.getPostBondConfig(), let f001 = charF001Ref else { return }
            peripheral.writeValue(Data(config), for: f001, type: .withResponse)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.enterStreaming(peripheral: peripheral)
            }
            return
        }
        // Encrypted command-response traffic on F002 post-streaming is not decoded in this minimal port.
    }

    private func enterStreaming(peripheral: CBPeripheral) {
        status("Streaming — waiting for live glucose")
        if let f002 = charF002Ref, let cmd = commandBuilder.setAutoUpdateStatus(true) {
            peripheral.writeValue(Data(cmd), for: f002, type: .withResponse)
        }
    }

    // F003 notify: encrypted 17-byte glucose frame or 5-byte status/keepalive frame.
    private func handleF003(_ encryptedData: [UInt8]) {
        let frameType = AiDexParser.classifyFrame(encryptedData)
        status("F003 notify: len=\(encryptedData.count) type=\(frameType) hex=\(AiDexParser.hexString(encryptedData))")
        guard frameType == .data else { return }
        guard let decrypted = keyExchange.decrypt(encryptedData) else {
            status("F003: cannot decrypt — sessionKey=\(keyExchange.sessionKey != nil ? "set" : "nil")")
            return
        }
        guard let frame = AiDexParser.parseDataFrame(decrypted) else { return }

        let frameCrc = Crc16CcittFalse.checksum(Array(decrypted[0..<15]))
        guard frameCrc == frame.crc16 else {
            status("F003: CRC mismatch, dropping frame")
            return
        }

        delegate?.aiDexManager(self, didReceiveGlucose: frame)
    }
}
