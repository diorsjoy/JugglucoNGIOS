import SwiftUI

struct ContentView: View {
    @StateObject private var vm = SensorViewModel()
    @State private var serial = ""

    var body: some View {
        VStack(spacing: 24) {
            if let glucose = vm.glucoseMgDl {
                Text("\(Int(glucose))")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                Text("mg/dL")
                    .foregroundStyle(.secondary)
                if let updated = vm.lastUpdate {
                    Text(updated, style: .relative)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            } else {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
            }

            Text(vm.status)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            if vm.glucoseMgDl == nil {
                TextField("AiDex serial (e.g. X-2222267V4E)", text: $serial)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled(true)
                    .padding(.horizontal)
                    .frame(maxWidth: 320)

                Button(vm.isConnecting ? "Connecting..." : "Connect") {
                    vm.connect(serial: serial)
                }
                .buttonStyle(.borderedProminent)
                .disabled(serial.isEmpty || vm.isConnecting)
            }
        }
        .padding()
    }
}
