import AiDexKit
import Foundation

@MainActor
final class SensorViewModel: ObservableObject {
    @Published var status = "Enter your AiDex serial number and tap Connect"
    @Published var glucoseMgDl: Float?
    @Published var lastUpdate: Date?
    @Published var isConnecting = false

    private var manager: AiDexBleManager?
    private var delegateBridge: DelegateBridge?

    func connect(serial: String) {
        let trimmed = serial.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isConnecting = true
        let bridge = DelegateBridge(viewModel: self)
        delegateBridge = bridge
        let m = AiDexBleManager(serial: trimmed)
        m.delegate = bridge
        manager = m
    }

    fileprivate func onStatus(_ s: String) {
        status = s
        if s.hasPrefix("Streaming") { isConnecting = false }
    }

    fileprivate func onGlucose(_ frame: GlucoseFrame) {
        guard frame.isValid else { return }
        glucoseMgDl = frame.glucoseMgDl
        lastUpdate = Date()
        isConnecting = false
    }
}

// AiDexBleManagerDelegate callbacks land on CoreBluetooth's internal queue; hop to
// MainActor before touching the @Published view-model state.
private final class DelegateBridge: AiDexBleManagerDelegate {
    weak var viewModel: SensorViewModel?
    init(viewModel: SensorViewModel) { self.viewModel = viewModel }

    func aiDexManager(_ manager: AiDexBleManager, didUpdateStatus status: String) {
        Task { @MainActor in self.viewModel?.onStatus(status) }
    }

    func aiDexManager(_ manager: AiDexBleManager, didReceiveGlucose frame: GlucoseFrame) {
        Task { @MainActor in self.viewModel?.onGlucose(frame) }
    }
}
