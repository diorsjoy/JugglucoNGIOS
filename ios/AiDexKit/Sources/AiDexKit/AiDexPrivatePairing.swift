// AiDexPrivatePairing.swift — macOS-only private-API SMP pairing trigger, ported from
// iGlucco's AiDexSensorManager.attemptPrivateAPIPairing() (github.com/ctqvva/iglucco).
//
// macOS's CoreBluetooth has no public createBond(). CBPairingAgent is an undocumented class
// that exists only on macOS (backed by IOBluetooth/bluetoothd) — iOS's CoreBluetooth has no
// equivalent, so this file is compiled out entirely on iOS.
//
// ponytail: private API, dev-only, will break on OS updates and would fail App Store review.
// Only exists to unblock local testing against real hardware.

#if os(macOS)
import CoreBluetooth
import ObjectiveC

enum AiDexPrivatePairing {
    static func attempt(peripheral: CBPeripheral, centralManager: CBCentralManager, log: @escaping (String) -> Void) {
        log("[AIDEX-PAIR] Attempting private-API SMP pairing (macOS CBPairingAgent)")

        var agent: AnyObject?
        let sharedSel = NSSelectorFromString("sharedPairingAgent")
        if centralManager.responds(to: sharedSel) {
            agent = centralManager.perform(sharedSel)?.takeUnretainedValue()
        }
        if agent == nil, let agentClass = NSClassFromString("CBPairingAgent") as? NSObject.Type {
            let allocSel = NSSelectorFromString("alloc")
            let initSel = NSSelectorFromString("initWithParentManager:")
            if let allocated = agentClass.perform(allocSel)?.takeUnretainedValue(), allocated.responds(to: initSel) {
                agent = allocated.perform(initSel, with: centralManager)?.takeUnretainedValue()
            }
        }

        guard let agent else {
            log("[AIDEX-PAIR] Could not obtain CBPairingAgent — private API unavailable on this macOS version")
            return
        }

        let agentClass: AnyClass = type(of: agent)
        let isPairedSel = NSSelectorFromString("isPeerPaired:")
        func checkIsPaired() -> Bool {
            guard agent.responds(to: isPairedSel), let imp = class_getMethodImplementation(agentClass, isPairedSel) else { return false }
            typealias IsPairedFn = @convention(c) (AnyObject, Selector, AnyObject) -> Bool
            return unsafeBitCast(imp, to: IsPairedFn.self)(agent, isPairedSel, peripheral)
        }

        let wasPaired = checkIsPaired()
        log("[AIDEX-PAIR] isPeerPaired: \(wasPaired)")

        if wasPaired {
            // Stale pairing cache short-circuits pairPeer: without a real SMP exchange. Clear it first.
            log("[AIDEX-PAIR] Clearing stale pairing cache before re-pairing")
            let unpairSel = NSSelectorFromString("unpairPeer:")
            if agent.responds(to: unpairSel) { agent.perform(unpairSel, with: peripheral) }
            let removeBondSel = NSSelectorFromString("removeBondForPeer:")
            if agent.responds(to: removeBondSel) { agent.perform(removeBondSel, with: peripheral) }
        }

        let pairDelay: TimeInterval = wasPaired ? 0.2 : 0.0
        DispatchQueue.main.asyncAfter(deadline: .now() + pairDelay) {
            let pairMITMSel = NSSelectorFromString("pairPeer:useMITM:")
            if agent.responds(to: pairMITMSel), let imp = class_getMethodImplementation(agentClass, pairMITMSel) {
                typealias PairMITMFn = @convention(c) (AnyObject, Selector, AnyObject, Bool) -> Void
                log("[AIDEX-PAIR] Calling pairPeer:useMITM:false (Just Works)")
                unsafeBitCast(imp, to: PairMITMFn.self)(agent, pairMITMSel, peripheral, false)
            } else {
                let pairSel = NSSelectorFromString("pairPeer:")
                if agent.responds(to: pairSel) {
                    log("[AIDEX-PAIR] Fallback: calling pairPeer:")
                    agent.perform(pairSel, with: peripheral)
                }
            }
        }
    }
}
#endif
