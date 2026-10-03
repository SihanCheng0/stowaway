import CoreGraphics
import Foundation
import IOKit
import IOKit.ps

struct BatteryInfo: Equatable {
    /// nil on Macs without a battery.
    var percent: Int?
    var onBattery: Bool
    var charging: Bool

    static let none = BatteryInfo(percent: nil, onBattery: false, charging: false)
}

struct SystemSnapshot: Equatable {
    var battery: BatteryInfo
    var thermal: ProcessInfo.ThermalState
    var lidClosed: Bool
    var externalDisplay: Bool
}

protocol SystemMonitoring {
    func snapshot() -> SystemSnapshot
}

struct SystemMonitor: SystemMonitoring {
    func snapshot() -> SystemSnapshot {
        SystemSnapshot(
            battery: Self.battery(),
            thermal: ProcessInfo.processInfo.thermalState,
            lidClosed: Self.lidClosed(),
            externalDisplay: Self.externalDisplayActive()
        )
    }

    static func battery() -> BatteryInfo {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return .none }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }
            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = description[kIOPSMaxCapacityKey] as? Int ?? 100
            return BatteryInfo(
                percent: max > 0 ? current * 100 / max : nil,
                onBattery: description[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue,
                charging: description[kIOPSIsChargingKey] as? Bool ?? false
            )
        }
        return .none
    }

    static func lidClosed() -> Bool {
        let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard rootDomain != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(rootDomain) }
        let state = IORegistryEntryCreateCFProperty(rootDomain, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
        return state as? Bool ?? false
    }

    static func externalDisplayActive() -> Bool {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return false }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return false }
        return displays.prefix(Int(count)).contains { CGDisplayIsBuiltin($0) == 0 }
    }
}
