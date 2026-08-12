// Manual hardware test: scans for a real AiDex sensor and prints live glucose readings.
// Usage: swift run AiDexLiveScan <serial-number-printed-on-sensor>

import AiDexKit
import Foundation

guard CommandLine.arguments.count > 1 else {
    print("usage: AiDexLiveScan <serial-number>")
    exit(1)
}

final class PrintDelegate: AiDexBleManagerDelegate {
    func aiDexManager(_ manager: AiDexBleManager, didUpdateStatus status: String) {
        print("[status] \(status)")
    }
    func aiDexManager(_ manager: AiDexBleManager, didReceiveGlucose frame: GlucoseFrame) {
        print("[glucose] \(frame.glucoseMgDl) mg/dL  offset=\(frame.timeOffsetMinutes)min  valid=\(frame.isValid)")
    }
}

let delegate = PrintDelegate()
let manager = AiDexBleManager(serial: CommandLine.arguments[1])
manager.delegate = delegate

print("Scanning for AiDex sensor \(CommandLine.arguments[1])... (Ctrl-C to stop)")
RunLoop.main.run()
