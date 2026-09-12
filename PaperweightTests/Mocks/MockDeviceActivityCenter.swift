#if os(iOS)
import Foundation
import DeviceActivity

final class MockDeviceActivityCenter: DeviceActivityMonitoring {
    private(set) var registered: [DeviceActivityName: DeviceActivitySchedule] = [:]
    private(set) var stopCallCount = 0

    var activities: [DeviceActivityName] { Array(registered.keys) }

    func startMonitoring(_ activity: DeviceActivityName, during schedule: DeviceActivitySchedule) throws {
        registered[activity] = schedule
    }

    func stopMonitoring(_ activities: [DeviceActivityName]) {
        stopCallCount += 1
        for a in activities { registered.removeValue(forKey: a) }
    }

    func schedule(named name: String) -> DeviceActivitySchedule? {
        registered[DeviceActivityName(name)]
    }

    var names: Set<String> { Set(registered.keys.map(\.rawValue)) }
}
#endif
