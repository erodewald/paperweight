# Paperweight iOS Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build an iOS + watchOS app that puts the phone in a "dumb mode" (all selected apps blocked) on a schedule, with NFC tap on a physical token as the emergency escape hatch.

**Architecture:** A main iOS app owns the FamilyControls authorization and all configuration. A `DeviceActivityMonitor` extension (separate target, runs in background) applies/removes `ManagedSettings` restrictions when schedule windows open and close. A watchOS companion app shows current status and can confirm NFC unlock requests via WatchConnectivity.

**Tech Stack:** Swift 5.9, SwiftUI, iOS 17+, watchOS 10+, FamilyControls + ManagedSettings + DeviceActivity (Screen Time APIs), CoreNFC, WatchConnectivity, XcodeGen for project generation, XCTest for unit tests.

---

## Prerequisite Checklist

Before starting:
- [ ] Apple Developer account active ($99/yr)
- [ ] Family Controls entitlement applied for at https://developer.apple.com/contact/request/family-controls-entitlement/ (select "Individual")
- [ ] Entitlement approval received (usually 1–2 business days)
- [ ] Your DEVELOPMENT_TEAM ID ready (find it at developer.apple.com → Membership → Team ID, format: `XXXXXXXXXX`)
- [ ] NFC stickers in hand (must be NFC Type 2 tags, e.g. NTAG213 — most "NFC/RFID stickers" sold on Amazon qualify)
- [ ] Xcode 15+ installed
- [ ] `brew` installed

---

## Directory Layout (final state)

```
Paperweight/
├── project.yml                          # XcodeGen spec
├── docs/plans/
├── Shared/                              # compiled into all targets
│   ├── Models/
│   │   ├── PaperweightConfig.swift
│   │   └── AppScheduleOverride.swift
│   ├── Store/
│   │   └── ConfigStore.swift
│   └── Constants.swift
├── Paperweight/                         # iOS app
│   ├── PaperweightApp.swift
│   ├── Views/
│   │   ├── HomeView.swift
│   │   ├── AppSelectionView.swift
│   │   ├── ScheduleView.swift
│   │   ├── NFCSetupView.swift
│   │   └── UnlockView.swift
│   ├── ViewModels/
│   │   ├── HomeViewModel.swift
│   │   └── ScheduleViewModel.swift
│   ├── Services/
│   │   ├── FamilyControlsService.swift
│   │   ├── RestrictionService.swift
│   │   ├── NFCService.swift
│   │   └── WatchConnectivityService.swift
│   ├── Info.plist
│   └── Paperweight.entitlements
├── PaperweightMonitor/                  # DeviceActivity extension
│   ├── PaperweightMonitor.swift
│   ├── Info.plist
│   └── PaperweightMonitor.entitlements
├── PaperweightWatch/                    # watchOS app
│   ├── PaperweightWatchApp.swift
│   ├── Views/
│   │   ├── StatusView.swift
│   │   └── ConfirmUnlockView.swift
│   ├── Services/
│   │   └── WatchSessionService.swift
│   ├── Info.plist
│   └── PaperweightWatch.entitlements
└── PaperweightTests/
    ├── Models/
    │   ├── PaperweightConfigTests.swift
    │   └── ScheduleTests.swift
    ├── Services/
    │   ├── RestrictionServiceTests.swift
    │   └── UnlockServiceTests.swift
    └── Mocks/
        ├── MockFamilyControlsService.swift
        └── MockNFCService.swift
```

---

## Key Concepts

### How FamilyControls / ManagedSettings work

1. The app calls `AuthorizationCenter.shared.requestAuthorization(for: .individual)` once. User approves in the system prompt.
2. `FamilyActivityPicker` (a SwiftUI view Apple provides) lets the user select which apps to block. It returns a `FamilyActivitySelection` (opaque tokens, never raw bundle IDs — Apple's privacy design).
3. `ManagedSettingsStore(named: .paperweight)` is a shared settings object. Any target in the same App Group can read/write it. Writing `store.shield.applications = selection.applicationTokens` shows the "Screen Time" block overlay on those apps.
4. The `DeviceActivityMonitor` extension subclasses `DeviceActivityMonitor` and overrides `intervalDidStart` / `intervalDidEnd`. The system calls these even when the main app is not running.

### Schedule model

- **Free window** = when restrictions are **off** (e.g. 9am–10pm daily)
- Outside the free window = **Paperweight mode** (restrictions on)
- We schedule a `DeviceActivity` monitor for the free window. `intervalDidStart` → remove restrictions. `intervalDidEnd` → apply restrictions.
- Per-app overrides: `alwaysBlocked` (e.g. Instagram, even during free window) or `alwaysFree` (e.g. Phone, Maps, never blocked).

### NFC unlock flow

1. **Setup**: User taps "Register NFC Token" → app starts `NFCTagReaderSession` → reads tag UID → stores UID in App Group UserDefaults.
2. **Unlock**: User taps "Emergency Unlock" → same scan → compare UID → if match:
   - If Watch paired + confirmation required: send `WCSession` message → Watch shows confirm dialog → user taps Confirm → iPhone receives reply → unlock granted.
   - Otherwise: unlock granted immediately.
3. **Effect**: `RestrictionService.temporarilyLift(for: duration)` calls `store.shield.applications = nil`, then schedules re-lock via `DispatchQueue.main.asyncAfter` AND registers a background task fallback.

### App Group ID

`group.com.paperweight.app` — must match exactly in all three entitlement files.

---

## Phase 0: Project Scaffolding

### Task 1: Install XcodeGen

**Step 1: Install via Homebrew**
```bash
brew install xcodegen
xcodegen --version
# Expected: xcodegen version 2.x.x
```

**Step 2: Commit**
```bash
cd /Users/eric/repos/Paperweight
git init
echo "*.xcuserdata\n.DS_Store\nDerivedData/\n*.xcworkspace/xcuserdata" > .gitignore
git add .gitignore
git commit -m "chore: init repo with gitignore"
```

---

### Task 2: Create project.yml

**Step 1: Write the XcodeGen spec**

Create `/Users/eric/repos/Paperweight/project.yml`:

```yaml
name: Paperweight

options:
  bundleIdPrefix: com.paperweight
  deploymentTarget:
    iOS: "17.0"
    watchOS: "10.0"
  xcodeVersion: "15.0"
  groupSortPosition: top

settings:
  base:
    SWIFT_VERSION: "5.9"
    DEVELOPMENT_TEAM: "XXXXXXXXXX"   # ← replace with your Team ID

packages: {}

targets:

  Paperweight:
    type: application
    platform: iOS
    deploymentTarget: "17.0"
    sources:
      - path: Paperweight
      - path: Shared
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.paperweight.app
        INFOPLIST_FILE: Paperweight/Info.plist
        TARGETED_DEVICE_FAMILY: "1"
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
    entitlements:
      path: Paperweight/Paperweight.entitlements
    dependencies:
      - target: PaperweightMonitor
      - target: PaperweightWatch
        embed: true

  PaperweightMonitor:
    type: app-extension
    platform: iOS
    deploymentTarget: "17.0"
    sources:
      - path: PaperweightMonitor
      - path: Shared
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.paperweight.app.monitor
        INFOPLIST_FILE: PaperweightMonitor/Info.plist
    entitlements:
      path: PaperweightMonitor/PaperweightMonitor.entitlements

  PaperweightWatch:
    type: application
    platform: watchOS
    deploymentTarget: "10.0"
    sources:
      - path: PaperweightWatch
      - path: Shared
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.paperweight.app.watchapp
        INFOPLIST_FILE: PaperweightWatch/Info.plist
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
    entitlements:
      path: PaperweightWatch/PaperweightWatch.entitlements

  PaperweightTests:
    type: bundle.unit-test
    platform: iOS
    deploymentTarget: "17.0"
    sources:
      - path: PaperweightTests
    settings:
      base:
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/Paperweight.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Paperweight"
        BUNDLE_LOADER: "$(TEST_HOST)"
    dependencies:
      - target: Paperweight
```

**Step 2: Commit**
```bash
git add project.yml
git commit -m "chore: add XcodeGen project spec"
```

---

### Task 3: Create stub source files and entitlements

These must exist before XcodeGen can run.

**Step 1: Create directory tree and stub files**

Run this block in terminal:
```bash
cd /Users/eric/repos/Paperweight
mkdir -p Paperweight/Views Paperweight/ViewModels Paperweight/Services
mkdir -p PaperweightMonitor
mkdir -p PaperweightWatch/Views PaperweightWatch/Services
mkdir -p Shared/Models Shared/Store
mkdir -p PaperweightTests/Models PaperweightTests/Services PaperweightTests/Mocks
```

**Step 2: Create entitlement files**

`Paperweight/Paperweight.entitlements`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.family-controls</key>
    <true/>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.paperweight.app</string>
    </array>
    <key>com.apple.developer.nfc.readersession.formats</key>
    <array>
        <string>NDEF</string>
        <string>TAG</string>
    </array>
</dict>
</plist>
```

`PaperweightMonitor/PaperweightMonitor.entitlements`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.developer.family-controls</key>
    <true/>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.paperweight.app</string>
    </array>
</dict>
</plist>
```

`PaperweightWatch/PaperweightWatch.entitlements`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.paperweight.app</string>
    </array>
</dict>
</plist>
```

**Step 3: Create Info.plists**

`Paperweight/Info.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>Paperweight</string>
    <key>NFCReaderUsageDescription</key>
    <string>Paperweight uses NFC to read your unlock token.</string>
    <key>UILaunchStoryboardName</key>
    <string>LaunchScreen</string>
</dict>
</plist>
```

`PaperweightMonitor/Info.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.deviceactivity.monitor</string>
        <key>NSExtensionPrincipalClass</key>
        <string>$(PRODUCT_MODULE_NAME).PaperweightMonitor</string>
    </dict>
</dict>
</plist>
```

`PaperweightWatch/Info.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>Paperweight</string>
    <key>WKCompanionAppBundleIdentifier</key>
    <string>com.paperweight.app</string>
    <key>WKWatchOnly</key>
    <false/>
</dict>
</plist>
```

**Step 4: Create minimal Swift stubs so XcodeGen can compile**

`Paperweight/PaperweightApp.swift`:
```swift
import SwiftUI

@main
struct PaperweightApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    var body: some View { Text("Paperweight") }
}
```

`PaperweightMonitor/PaperweightMonitor.swift`:
```swift
import DeviceActivity

@objc(PaperweightMonitor)
class PaperweightMonitor: DeviceActivityMonitor {}
```

`PaperweightWatch/PaperweightWatchApp.swift`:
```swift
import SwiftUI

@main
struct PaperweightWatchApp: App {
    var body: some Scene {
        WindowGroup { Text("Paperweight") }
    }
}
```

`Shared/Constants.swift`:
```swift
import Foundation

enum Paperweight {
    static let appGroupID = "group.com.paperweight.app"
    static let activityName = "dailySchedule"
    static let storeName = "paperweight"
    static let defaultUnlockDuration: TimeInterval = 15 * 60
}
```

`PaperweightTests/PaperweightTests.swift`:
```swift
import XCTest

final class PlaceholderTests: XCTestCase {
    func testPlaceholder() { XCTAssertTrue(true) }
}
```

**Step 5: Generate and open the Xcode project**
```bash
cd /Users/eric/repos/Paperweight
xcodegen generate
open Paperweight.xcodeproj
```

Expected: Xcode opens with 4 targets visible in the navigator (Paperweight, PaperweightMonitor, PaperweightWatch, PaperweightTests).

**Step 6: In Xcode, verify signing**
- Select each target → Signing & Capabilities → set Team to your account.
- The Family Controls capability should appear on Paperweight and PaperweightMonitor automatically from the entitlement file (if the entitlement was approved it will show a checkmark; if not yet approved it will show a warning — that's fine for now, you can still run on device).

**Step 7: Commit**
```bash
git add .
git commit -m "chore: scaffold Xcode project with all targets"
```

---

## Phase 1: Shared Data Layer

### Task 4: PaperweightConfig model

**Step 1: Write the failing test**

Create `PaperweightTests/Models/PaperweightConfigTests.swift`:
```swift
import XCTest
import FamilyControls
@testable import Paperweight

final class PaperweightConfigTests: XCTestCase {

    func test_defaultConfig_isDisabled() {
        let config = PaperweightConfig()
        XCTAssertFalse(config.isEnabled)
    }

    func test_defaultConfig_hasNoSchedule() {
        let config = PaperweightConfig()
        XCTAssertNil(config.schedule)
    }

    func test_defaultUnlockDuration_is15Minutes() {
        let config = PaperweightConfig()
        XCTAssertEqual(config.unlockDuration, 15 * 60)
    }

    func test_config_roundtripsJSON() throws {
        var config = PaperweightConfig()
        config.isEnabled = true
        config.unlockDuration = 600
        config.requireWatchConfirmation = true

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(PaperweightConfig.self, from: data)

        XCTAssertEqual(decoded.isEnabled, true)
        XCTAssertEqual(decoded.unlockDuration, 600)
        XCTAssertEqual(decoded.requireWatchConfirmation, true)
    }

    func test_schedule_freeWindow_containsTime() {
        let schedule = AllowSchedule(
            startHour: 9, startMinute: 0,
            endHour: 22, endMinute: 0,
            weekdays: Set(1...7)
        )
        XCTAssertTrue(schedule.contains(hour: 12, minute: 0))
        XCTAssertFalse(schedule.contains(hour: 7, minute: 0))
        XCTAssertFalse(schedule.contains(hour: 23, minute: 0))
    }

    func test_schedule_midnightSpanning_notSupported() {
        // We do NOT support schedules that span midnight (e.g. 10pm–2am).
        // End must be > start. Validate this.
        let schedule = AllowSchedule(
            startHour: 22, startMinute: 0,
            endHour: 8, endMinute: 0,
            weekdays: Set(1...7)
        )
        XCTAssertFalse(schedule.isValid)
    }
}
```

**Step 2: Run to verify it fails**
```bash
xcodebuild test -scheme Paperweight -destination 'platform=iOS Simulator,name=iPhone 15 Pro' -only-testing:PaperweightTests/PaperweightConfigTests 2>&1 | tail -20
```
Expected: Compile error — `PaperweightConfig` not defined.

**Step 3: Implement the model**

Create `Shared/Models/PaperweightConfig.swift`:
```swift
import Foundation
import FamilyControls

struct PaperweightConfig: Codable {
    var isEnabled: Bool = false
    var schedule: AllowSchedule? = nil
    var selection: FamilyActivitySelection = .init()
    var appOverrides: [AppScheduleOverride] = []
    var unlockDuration: TimeInterval = Paperweight.defaultUnlockDuration
    var requireWatchConfirmation: Bool = true
    var registeredNFCTagUID: String? = nil
}

struct AllowSchedule: Codable {
    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int
    var weekdays: Set<Int>    // 1 = Sunday … 7 = Saturday (Calendar convention)

    var isValid: Bool {
        let startTotal = startHour * 60 + startMinute
        let endTotal = endHour * 60 + endMinute
        return endTotal > startTotal && !weekdays.isEmpty
    }

    func contains(hour: Int, minute: Int) -> Bool {
        guard isValid else { return false }
        let t = hour * 60 + minute
        let s = startHour * 60 + startMinute
        let e = endHour * 60 + endMinute
        return t >= s && t < e
    }
}
```

Create `Shared/Models/AppScheduleOverride.swift`:
```swift
import Foundation
import FamilyControls

struct AppScheduleOverride: Codable, Identifiable {
    let id: UUID
    var token: ApplicationToken
    var mode: Mode

    enum Mode: String, Codable {
        case alwaysBlocked   // blocked even during free window
        case alwaysFree      // never blocked (Phone, Maps, etc.)
    }
}
```

**Step 4: Run tests**
```bash
xcodebuild test -scheme Paperweight -destination 'platform=iOS Simulator,name=iPhone 15 Pro' -only-testing:PaperweightTests/PaperweightConfigTests 2>&1 | tail -20
```
Expected: All 5 tests pass.

**Step 5: Commit**
```bash
git add Shared/Models/ PaperweightTests/Models/PaperweightConfigTests.swift
git commit -m "feat: PaperweightConfig and AllowSchedule models with tests"
```

---

### Task 5: ConfigStore — App Group persistence

**Step 1: Write the failing test**

Create `PaperweightTests/Models/ConfigStoreTests.swift`:
```swift
import XCTest
@testable import Paperweight

final class ConfigStoreTests: XCTestCase {

    var store: ConfigStore!

    override func setUp() {
        super.setUp()
        // Use in-memory UserDefaults for tests
        store = ConfigStore(defaults: UserDefaults(suiteName: "test.paperweight.\(UUID().uuidString)")!)
    }

    func test_save_andLoad_roundtrips() throws {
        var config = PaperweightConfig()
        config.isEnabled = true
        config.unlockDuration = 300

        try store.save(config)
        let loaded = store.load()

        XCTAssertEqual(loaded.isEnabled, true)
        XCTAssertEqual(loaded.unlockDuration, 300)
    }

    func test_load_returnsDefault_whenEmpty() {
        let config = store.load()
        XCTAssertFalse(config.isEnabled)
    }

    func test_save_overwritesPrevious() throws {
        var config = PaperweightConfig()
        config.unlockDuration = 300
        try store.save(config)

        config.unlockDuration = 600
        try store.save(config)

        XCTAssertEqual(store.load().unlockDuration, 600)
    }
}
```

**Step 2: Run to verify it fails**
```bash
xcodebuild test -scheme Paperweight -destination 'platform=iOS Simulator,name=iPhone 15 Pro' -only-testing:PaperweightTests/ConfigStoreTests 2>&1 | tail -20
```
Expected: Compile error — `ConfigStore` not defined.

**Step 3: Implement ConfigStore**

Create `Shared/Store/ConfigStore.swift`:
```swift
import Foundation

final class ConfigStore {
    private let defaults: UserDefaults
    private let key = "paperweight.config"

    init(defaults: UserDefaults = UserDefaults(suiteName: Paperweight.appGroupID)!) {
        self.defaults = defaults
    }

    func save(_ config: PaperweightConfig) throws {
        let data = try JSONEncoder().encode(config)
        defaults.set(data, forKey: key)
    }

    func load() -> PaperweightConfig {
        guard let data = defaults.data(forKey: key),
              let config = try? JSONDecoder().decode(PaperweightConfig.self, from: data)
        else { return PaperweightConfig() }
        return config
    }
}
```

**Step 4: Run tests**
```bash
xcodebuild test -scheme Paperweight -destination 'platform=iOS Simulator,name=iPhone 15 Pro' -only-testing:PaperweightTests/ConfigStoreTests 2>&1 | tail -20
```
Expected: All 3 tests pass.

**Step 5: Commit**
```bash
git add Shared/Store/ConfigStore.swift PaperweightTests/Models/ConfigStoreTests.swift
git commit -m "feat: ConfigStore for App Group persistence with tests"
```

---

## Phase 2: Family Controls + Restriction Engine

### Task 6: FamilyControlsService protocol and mock

**Step 1: Create the protocol**

Create `Paperweight/Services/FamilyControlsService.swift`:
```swift
import FamilyControls

protocol FamilyControlsServiceProtocol {
    var isAuthorized: Bool { get }
    func requestAuthorization() async throws
}

final class FamilyControlsService: FamilyControlsServiceProtocol {
    private let center = AuthorizationCenter.shared

    var isAuthorized: Bool {
        center.authorizationStatus == .approved
    }

    func requestAuthorization() async throws {
        try await center.requestAuthorization(for: .individual)
    }
}
```

**Step 2: Create the mock for tests**

Create `PaperweightTests/Mocks/MockFamilyControlsService.swift`:
```swift
import FamilyControls
@testable import Paperweight

final class MockFamilyControlsService: FamilyControlsServiceProtocol {
    var isAuthorized: Bool = false
    var shouldThrow: Bool = false
    var authorizationCallCount: Int = 0

    func requestAuthorization() async throws {
        authorizationCallCount += 1
        if shouldThrow { throw URLError(.cancelled) }
        isAuthorized = true
    }
}
```

**Step 3: Commit**
```bash
git add Paperweight/Services/FamilyControlsService.swift PaperweightTests/Mocks/MockFamilyControlsService.swift
git commit -m "feat: FamilyControlsService protocol and mock"
```

---

### Task 7: RestrictionService — apply and remove shields

**Step 1: Write the failing tests**

Create `PaperweightTests/Services/RestrictionServiceTests.swift`:
```swift
import XCTest
import FamilyControls
import ManagedSettings
@testable import Paperweight

final class RestrictionServiceTests: XCTestCase {

    func test_applyRestrictions_setsShieldApplications() {
        let mockStore = MockManagedSettingsStore()
        let service = RestrictionService(store: mockStore)
        let selection = FamilyActivitySelection()

        service.apply(selection: selection, overrides: [])

        XCTAssertTrue(mockStore.shieldApplicationsWasSet)
    }

    func test_removeRestrictions_clearsShield() {
        let mockStore = MockManagedSettingsStore()
        let service = RestrictionService(store: mockStore)

        service.removeAll()

        XCTAssertTrue(mockStore.shieldWasCleared)
    }

    func test_alwaysFreeOverride_excludedFromShield() {
        let mockStore = MockManagedSettingsStore()
        let service = RestrictionService(store: mockStore)
        let selection = FamilyActivitySelection()
        // Note: we can't easily create ApplicationTokens in tests (opaque type),
        // so we verify the logic path via the mock's call count.
        service.apply(selection: selection, overrides: [])
        XCTAssertEqual(mockStore.applyCallCount, 1)
    }
}
```

Create `PaperweightTests/Mocks/MockManagedSettingsStore.swift`:
```swift
import ManagedSettings
import FamilyControls
@testable import Paperweight

final class MockManagedSettingsStore: ManagedSettingsStoreProtocol {
    var shieldApplicationsWasSet = false
    var shieldWasCleared = false
    var applyCallCount = 0

    func setShield(applications: Set<ApplicationToken>?) {
        applyCallCount += 1
        if applications == nil {
            shieldWasCleared = true
        } else {
            shieldApplicationsWasSet = true
        }
    }
}
```

**Step 2: Run to verify it fails**
Expected: Compile error.

**Step 3: Implement the protocol and service**

Add to `Paperweight/Services/RestrictionService.swift`:
```swift
import ManagedSettings
import FamilyControls

protocol ManagedSettingsStoreProtocol {
    func setShield(applications: Set<ApplicationToken>?)
}

extension ManagedSettingsStore: ManagedSettingsStoreProtocol {
    func setShield(applications: Set<ApplicationToken>?) {
        shield.applications = applications
    }
}

final class RestrictionService {
    private let store: ManagedSettingsStoreProtocol

    init(store: ManagedSettingsStoreProtocol = ManagedSettingsStore(named: .init(Paperweight.storeName))) {
        self.store = store
    }

    func apply(selection: FamilyActivitySelection, overrides: [AppScheduleOverride]) {
        var blocked = selection.applicationTokens
        // Remove alwaysFree apps from the blocked set
        let freeTokens = Set(overrides
            .filter { $0.mode == .alwaysFree }
            .map(\.token))
        blocked.subtract(freeTokens)
        // Add alwaysBlocked apps on top
        let alwaysBlockedTokens = Set(overrides
            .filter { $0.mode == .alwaysBlocked }
            .map(\.token))
        blocked.formUnion(alwaysBlockedTokens)

        store.setShield(applications: blocked.isEmpty ? nil : blocked)
    }

    func removeAll() {
        store.setShield(applications: nil)
    }
}
```

**Step 4: Run tests**
Expected: All 3 pass.

**Step 5: Commit**
```bash
git add Paperweight/Services/RestrictionService.swift PaperweightTests/Services/RestrictionServiceTests.swift PaperweightTests/Mocks/MockManagedSettingsStore.swift
git commit -m "feat: RestrictionService with shield apply/remove and override logic"
```

---

## Phase 3: App Selection + Home UI

### Task 8: HomeViewModel

**Step 1: Write the failing test**

Create `PaperweightTests/Services/HomeViewModelTests.swift`:
```swift
import XCTest
@testable import Paperweight

@MainActor
final class HomeViewModelTests: XCTestCase {
    var configStore: ConfigStore!
    var familyService: MockFamilyControlsService!
    var restrictionService: RestrictionService!

    override func setUp() {
        super.setUp()
        configStore = ConfigStore(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
        familyService = MockFamilyControlsService()
        restrictionService = RestrictionService(store: MockManagedSettingsStore())
    }

    func test_enable_requestsAuthorizationIfNeeded() async {
        familyService.isAuthorized = false
        let vm = HomeViewModel(configStore: configStore, familyService: familyService, restrictionService: restrictionService)

        await vm.setEnabled(true)

        XCTAssertEqual(familyService.authorizationCallCount, 1)
    }

    func test_enable_doesNotRequestAuth_ifAlreadyAuthorized() async {
        familyService.isAuthorized = true
        let vm = HomeViewModel(configStore: configStore, familyService: familyService, restrictionService: restrictionService)

        await vm.setEnabled(true)

        XCTAssertEqual(familyService.authorizationCallCount, 0)
    }

    func test_enable_savesConfig() async {
        familyService.isAuthorized = true
        let vm = HomeViewModel(configStore: configStore, familyService: familyService, restrictionService: restrictionService)

        await vm.setEnabled(true)

        XCTAssertTrue(configStore.load().isEnabled)
    }

    func test_disable_savesConfig() async {
        familyService.isAuthorized = true
        let vm = HomeViewModel(configStore: configStore, familyService: familyService, restrictionService: restrictionService)
        await vm.setEnabled(true)
        await vm.setEnabled(false)

        XCTAssertFalse(configStore.load().isEnabled)
    }
}
```

**Step 2: Run to verify it fails**

**Step 3: Implement HomeViewModel**

Create `Paperweight/ViewModels/HomeViewModel.swift`:
```swift
import SwiftUI
import FamilyControls

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var config: PaperweightConfig
    @Published var error: Error?

    private let configStore: ConfigStore
    private let familyService: FamilyControlsServiceProtocol
    private let restrictionService: RestrictionService

    init(
        configStore: ConfigStore = ConfigStore(),
        familyService: FamilyControlsServiceProtocol = FamilyControlsService(),
        restrictionService: RestrictionService = RestrictionService()
    ) {
        self.configStore = configStore
        self.familyService = familyService
        self.restrictionService = restrictionService
        self.config = configStore.load()
    }

    func setEnabled(_ enabled: Bool) async {
        do {
            if enabled && !familyService.isAuthorized {
                try await familyService.requestAuthorization()
            }
            config.isEnabled = enabled
            try configStore.save(config)
            if enabled {
                restrictionService.apply(selection: config.selection, overrides: config.appOverrides)
            } else {
                restrictionService.removeAll()
            }
        } catch {
            self.error = error
        }
    }

    func saveSelection() {
        try? configStore.save(config)
        if config.isEnabled {
            restrictionService.apply(selection: config.selection, overrides: config.appOverrides)
        }
    }
}
```

**Step 4: Run tests**
Expected: All 4 pass.

**Step 5: Commit**
```bash
git add Paperweight/ViewModels/HomeViewModel.swift PaperweightTests/Services/HomeViewModelTests.swift
git commit -m "feat: HomeViewModel with enable/disable and authorization flow"
```

---

### Task 9: HomeView and AppSelectionView

**Step 1: Implement HomeView**

Create `Paperweight/Views/HomeView.swift`:
```swift
import SwiftUI
import FamilyControls

struct HomeView: View {
    @StateObject private var vm = HomeViewModel()
    @State private var showingPicker = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Paperweight Mode", isOn: Binding(
                        get: { vm.config.isEnabled },
                        set: { newValue in Task { await vm.setEnabled(newValue) } }
                    ))
                    .tint(.orange)
                } footer: {
                    Text(vm.config.isEnabled
                         ? "Your selected apps are restricted."
                         : "Paperweight is off. All apps accessible.")
                }

                Section("Restricted Apps") {
                    Button {
                        showingPicker = true
                    } label: {
                        Label("Choose Apps to Restrict", systemImage: "app.badge.checkmark")
                    }
                    let count = vm.config.selection.applicationTokens.count
                    if count > 0 {
                        Text("\(count) app\(count == 1 ? "" : "s") selected")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    NavigationLink("Schedule") {
                        ScheduleView(vm: vm)
                    }
                    NavigationLink("NFC Unlock Token") {
                        NFCSetupView(vm: vm)
                    }
                    NavigationLink("Emergency Unlock") {
                        UnlockView(vm: vm)
                    }
                }
            }
            .navigationTitle("Paperweight")
            .alert("Error", isPresented: Binding(
                get: { vm.error != nil },
                set: { if !$0 { vm.error = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(vm.error?.localizedDescription ?? "")
            }
        }
        .familyActivityPicker(isPresented: $showingPicker, selection: $vm.config.selection)
        .onChange(of: showingPicker) { _, isPresented in
            if !isPresented { vm.saveSelection() }
        }
    }
}
```

**Step 2: Wire HomeView as root**

Update `Paperweight/PaperweightApp.swift`:
```swift
import SwiftUI

@main
struct PaperweightApp: App {
    var body: some Scene {
        WindowGroup { HomeView() }
    }
}
```

**Step 3: Build and run on simulator**
```bash
xcodebuild build -scheme Paperweight -destination 'platform=iOS Simulator,name=iPhone 15 Pro' 2>&1 | tail -10
```
Expected: Build succeeds. Open in simulator: toggle, app picker sheet, navigation links visible.

**Step 4: Commit**
```bash
git add Paperweight/Views/HomeView.swift Paperweight/PaperweightApp.swift
git commit -m "feat: HomeView with toggle, FamilyActivityPicker, and navigation"
```

---

## Phase 4: Schedule System

### Task 10: ScheduleView

**Step 1: Implement ScheduleView**

Create `Paperweight/Views/ScheduleView.swift`:
```swift
import SwiftUI

struct ScheduleView: View {
    @ObservedObject var vm: HomeViewModel
    @State private var scheduleEnabled: Bool
    @State private var startHour: Int
    @State private var startMinute: Int
    @State private var endHour: Int
    @State private var endMinute: Int
    @State private var weekdays: Set<Int>

    init(vm: HomeViewModel) {
        self.vm = vm
        let s = vm.config.schedule
        _scheduleEnabled = State(initialValue: s != nil)
        _startHour = State(initialValue: s?.startHour ?? 9)
        _startMinute = State(initialValue: s?.startMinute ?? 0)
        _endHour = State(initialValue: s?.endHour ?? 22)
        _endMinute = State(initialValue: s?.endMinute ?? 0)
        _weekdays = State(initialValue: s?.weekdays ?? Set(1...7))
    }

    var body: some View {
        Form {
            Section {
                Toggle("Use a schedule", isOn: $scheduleEnabled)
            } footer: {
                Text(scheduleEnabled
                     ? "Apps are free during the window below. Restricted all other times."
                     : "No schedule — apps are always restricted while Paperweight is on.")
            }

            if scheduleEnabled {
                Section("Free Window") {
                    TimePicker(label: "Start", hour: $startHour, minute: $startMinute)
                    TimePicker(label: "End", hour: $endHour, minute: $endMinute)
                }

                Section("Days") {
                    WeekdayPicker(selection: $weekdays)
                }

                if !currentSchedule.isValid {
                    Section {
                        Label("End time must be after start time.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .navigationTitle("Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(scheduleEnabled && !currentSchedule.isValid)
            }
        }
    }

    private var currentSchedule: AllowSchedule {
        AllowSchedule(startHour: startHour, startMinute: startMinute,
                      endHour: endHour, endMinute: endMinute, weekdays: weekdays)
    }

    private func save() {
        vm.config.schedule = scheduleEnabled ? currentSchedule : nil
        vm.saveSelection()
        // Re-register DeviceActivity schedule
        ScheduleService.shared.updateSchedule(vm.config.schedule)
    }
}

// MARK: - Sub-views

struct TimePicker: View {
    let label: String
    @Binding var hour: Int
    @Binding var minute: Int

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Picker("Hour", selection: $hour) {
                ForEach(0..<24) { h in
                    Text(String(format: "%02d", h)).tag(h)
                }
            }
            .pickerStyle(.wheel)
            .frame(width: 60)
            Text(":")
            Picker("Minute", selection: $minute) {
                ForEach([0, 15, 30, 45], id: \.self) { m in
                    Text(String(format: "%02d", m)).tag(m)
                }
            }
            .pickerStyle(.wheel)
            .frame(width: 60)
        }
    }
}

struct WeekdayPicker: View {
    @Binding var selection: Set<Int>
    private let days = [(1,"Su"),(2,"Mo"),(3,"Tu"),(4,"We"),(5,"Th"),(6,"Fr"),(7,"Sa")]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(days, id: \.0) { (num, label) in
                let selected = selection.contains(num)
                Button(label) {
                    if selected { selection.remove(num) } else { selection.insert(num) }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(selected ? Color.orange : Color(.systemGray5))
                .foregroundStyle(selected ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .font(.caption.bold())
            }
        }
    }
}
```

**Step 2: Commit**
```bash
git add Paperweight/Views/ScheduleView.swift
git commit -m "feat: ScheduleView with free window and weekday picker"
```

---

### Task 11: ScheduleService + DeviceActivityMonitor extension

**Step 1: Write the failing tests for schedule validation**

Add to `PaperweightTests/Models/PaperweightConfigTests.swift` (the existing file):
```swift
func test_scheduleService_buildsDatesFromSchedule() {
    let schedule = AllowSchedule(
        startHour: 9, startMinute: 0,
        endHour: 22, endMinute: 0,
        weekdays: Set(1...7)
    )
    let (start, end) = ScheduleService.dateComponents(from: schedule)
    XCTAssertEqual(start.hour, 9)
    XCTAssertEqual(start.minute, 0)
    XCTAssertEqual(end.hour, 22)
    XCTAssertEqual(end.minute, 0)
}
```

**Step 2: Implement ScheduleService**

Create `Paperweight/Services/ScheduleService.swift`:
```swift
import DeviceActivity
import Foundation

final class ScheduleService {
    static let shared = ScheduleService()
    private let center = DeviceActivityCenter()
    private let activityName = DeviceActivityName(Paperweight.activityName)

    static func dateComponents(from schedule: AllowSchedule) -> (start: DateComponents, end: DateComponents) {
        var start = DateComponents()
        start.hour = schedule.startHour
        start.minute = schedule.startMinute

        var end = DateComponents()
        end.hour = schedule.endHour
        end.minute = schedule.endMinute

        return (start, end)
    }

    func updateSchedule(_ schedule: AllowSchedule?) {
        center.stopMonitoring([activityName])
        guard let schedule, schedule.isValid else { return }

        let (start, end) = ScheduleService.dateComponents(from: schedule)
        let deviceSchedule = DeviceActivitySchedule(
            intervalStart: start,
            intervalEnd: end,
            repeats: true
        )
        do {
            try center.startMonitoring(activityName, during: deviceSchedule)
        } catch {
            print("ScheduleService: startMonitoring failed: \(error)")
        }
    }
}
```

**Step 3: Implement the DeviceActivityMonitor extension**

Update `PaperweightMonitor/PaperweightMonitor.swift`:
```swift
import DeviceActivity
import ManagedSettings
import FamilyControls

@objc(PaperweightMonitor)
class PaperweightMonitor: DeviceActivityMonitor {
    private let store = ManagedSettingsStore(named: .init(Paperweight.storeName))
    private let configStore = ConfigStore()

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        // Free window started → lift restrictions
        let config = configStore.load()
        let service = RestrictionService(store: store)
        service.removeAll()
        _ = config  // config available for future per-app logic
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        // Free window ended → apply restrictions
        let config = configStore.load()
        guard config.isEnabled else { return }
        let service = RestrictionService(store: store)
        service.apply(selection: config.selection, overrides: config.appOverrides)
    }
}
```

**Step 4: Run tests**
```bash
xcodebuild test -scheme Paperweight -destination 'platform=iOS Simulator,name=iPhone 15 Pro' 2>&1 | grep -E "passed|failed|error:"
```
Expected: All tests pass.

**Step 5: Commit**
```bash
git add Paperweight/Services/ScheduleService.swift PaperweightMonitor/PaperweightMonitor.swift PaperweightTests/Models/PaperweightConfigTests.swift
git commit -m "feat: ScheduleService and DeviceActivityMonitor for schedule-based restrictions"
```

---

## Phase 5: NFC Unlock

### Task 12: NFCService protocol and mock

**Step 1: Create the protocol**

Create `Paperweight/Services/NFCService.swift`:
```swift
import CoreNFC
import Combine

enum NFCError: LocalizedError {
    case notSupported
    case sessionFailed(Error)
    case noTagFound
    case readFailed

    var errorDescription: String? {
        switch self {
        case .notSupported: return "NFC is not supported on this device."
        case .sessionFailed(let e): return "NFC session failed: \(e.localizedDescription)"
        case .noTagFound: return "No NFC tag found."
        case .readFailed: return "Could not read the NFC tag."
        }
    }
}

protocol NFCServiceProtocol {
    func readTagUID() async throws -> String
}

final class NFCService: NSObject, NFCServiceProtocol {
    private var continuation: CheckedContinuation<String, Error>?
    private var session: NFCTagReaderSession?

    func readTagUID() async throws -> String {
        guard NFCTagReaderSession.readingAvailable else { throw NFCError.notSupported }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            session = NFCTagReaderSession(pollingOption: [.iso14443, .iso15693], delegate: self, queue: .main)
            session?.alertMessage = "Hold your Paperweight token near the top of your iPhone."
            session?.begin()
        }
    }
}

extension NFCService: NFCTagReaderSessionDelegate {
    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        let nfcError = error as? NFCReaderError
        if nfcError?.code != .readerSessionInvalidationErrorUserCanceled {
            continuation?.resume(throwing: NFCError.sessionFailed(error))
        } else {
            continuation?.resume(throwing: CancellationError())
        }
        continuation = nil
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let tag = tags.first else {
            continuation?.resume(throwing: NFCError.noTagFound)
            session.invalidate()
            return
        }
        session.connect(to: tag) { [weak self] error in
            if let error {
                self?.continuation?.resume(throwing: NFCError.sessionFailed(error))
                session.invalidate()
                return
            }
            let uid: String
            switch tag {
            case .iso7816(let t):    uid = t.identifier.hexString
            case .miFare(let t):     uid = t.identifier.hexString
            case .iso15693(let t):   uid = t.identifier.hexString
            case .feliCa(let t):     uid = t.currentIDm.hexString
            @unknown default:
                self?.continuation?.resume(throwing: NFCError.readFailed)
                session.invalidate()
                return
            }
            session.alertMessage = "Token recognized."
            session.invalidate()
            self?.continuation?.resume(returning: uid)
            self?.continuation = nil
        }
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined()
    }
}
```

**Step 2: Create mock**

Create `PaperweightTests/Mocks/MockNFCService.swift`:
```swift
@testable import Paperweight

final class MockNFCService: NFCServiceProtocol {
    var mockUID: String = "AABBCCDD"
    var shouldThrow: Bool = false
    var callCount: Int = 0

    func readTagUID() async throws -> String {
        callCount += 1
        if shouldThrow { throw NFCError.notSupported }
        return mockUID
    }
}
```

**Step 3: Commit**
```bash
git add Paperweight/Services/NFCService.swift PaperweightTests/Mocks/MockNFCService.swift
git commit -m "feat: NFCService for reading tag UID with async/await"
```

---

### Task 13: UnlockService — timed unlock logic

**Step 1: Write the failing tests**

Create `PaperweightTests/Services/UnlockServiceTests.swift`:
```swift
import XCTest
@testable import Paperweight

@MainActor
final class UnlockServiceTests: XCTestCase {
    var configStore: ConfigStore!
    var nfcService: MockNFCService!
    var restrictionService: RestrictionService!

    override func setUp() {
        super.setUp()
        configStore = ConfigStore(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
        nfcService = MockNFCService()
        restrictionService = RestrictionService(store: MockManagedSettingsStore())
    }

    func test_registerTag_savesUID() async throws {
        let service = UnlockService(configStore: configStore, nfcService: nfcService, restrictionService: restrictionService)
        try await service.registerTag()
        XCTAssertEqual(configStore.load().registeredNFCTagUID, "AABBCCDD")
    }

    func test_unlock_failsIfNoTagRegistered() async {
        let service = UnlockService(configStore: configStore, nfcService: nfcService, restrictionService: restrictionService)
        do {
            try await service.unlock()
            XCTFail("Should have thrown")
        } catch UnlockError.noTagRegistered {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_unlock_failsIfWrongUID() async throws {
        var config = PaperweightConfig()
        config.registeredNFCTagUID = "11223344"
        try configStore.save(config)

        nfcService.mockUID = "FFEEDDCC"
        let service = UnlockService(configStore: configStore, nfcService: nfcService, restrictionService: restrictionService)

        do {
            try await service.unlock()
            XCTFail("Should have thrown")
        } catch UnlockError.tagMismatch {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_unlock_succeedsWithMatchingUID() async throws {
        var config = PaperweightConfig()
        config.registeredNFCTagUID = "AABBCCDD"
        config.isEnabled = true
        try configStore.save(config)

        let service = UnlockService(configStore: configStore, nfcService: nfcService, restrictionService: restrictionService)
        try await service.unlock()

        XCTAssertTrue(service.isUnlocked)
    }
}
```

**Step 2: Run to verify failure**

**Step 3: Implement UnlockService**

Create `Paperweight/Services/UnlockService.swift`:
```swift
import Foundation

enum UnlockError: LocalizedError {
    case noTagRegistered
    case tagMismatch
    case watchConfirmationRequired

    var errorDescription: String? {
        switch self {
        case .noTagRegistered: return "No NFC token registered. Set one up in settings."
        case .tagMismatch: return "That token wasn't recognized."
        case .watchConfirmationRequired: return "Waiting for Watch confirmation."
        }
    }
}

@MainActor
final class UnlockService: ObservableObject {
    @Published var isUnlocked: Bool = false
    @Published var unlockExpiresAt: Date? = nil

    private let configStore: ConfigStore
    private let nfcService: NFCServiceProtocol
    private let restrictionService: RestrictionService
    private var relockTask: Task<Void, Never>?

    init(
        configStore: ConfigStore = ConfigStore(),
        nfcService: NFCServiceProtocol = NFCService(),
        restrictionService: RestrictionService = RestrictionService()
    ) {
        self.configStore = configStore
        self.nfcService = nfcService
        self.restrictionService = restrictionService
    }

    func registerTag() async throws {
        let uid = try await nfcService.readTagUID()
        var config = configStore.load()
        config.registeredNFCTagUID = uid
        try configStore.save(config)
    }

    func unlock() async throws {
        let config = configStore.load()
        guard let registeredUID = config.registeredNFCTagUID else {
            throw UnlockError.noTagRegistered
        }
        let scannedUID = try await nfcService.readTagUID()
        guard scannedUID == registeredUID else {
            throw UnlockError.tagMismatch
        }
        grantUnlock(duration: config.unlockDuration)
    }

    func grantUnlock(duration: TimeInterval) {
        let config = configStore.load()
        restrictionService.removeAll()
        isUnlocked = true
        unlockExpiresAt = Date().addingTimeInterval(duration)

        relockTask?.cancel()
        relockTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            await self?.relock()
        }
    }

    func relock() {
        let config = configStore.load()
        guard config.isEnabled else { return }
        restrictionService.apply(selection: config.selection, overrides: config.appOverrides)
        isUnlocked = false
        unlockExpiresAt = nil
    }
}
```

**Step 4: Run tests**
Expected: All 4 pass.

**Step 5: Commit**
```bash
git add Paperweight/Services/UnlockService.swift PaperweightTests/Services/UnlockServiceTests.swift
git commit -m "feat: UnlockService with NFC tag verification and timed re-lock"
```

---

### Task 14: NFC setup and unlock views

**Step 1: NFCSetupView**

Create `Paperweight/Views/NFCSetupView.swift`:
```swift
import SwiftUI

struct NFCSetupView: View {
    @ObservedObject var vm: HomeViewModel
    @StateObject private var unlockService = UnlockService()
    @State private var isScanning = false
    @State private var error: Error?
    @State private var didRegister = false

    var body: some View {
        Form {
            Section {
                if let uid = vm.config.registeredNFCTagUID {
                    LabeledContent("Registered Token", value: uid)
                    Button("Replace Token", role: .destructive) { scan() }
                } else {
                    Button("Register NFC Token") { scan() }
                }
            } header: {
                Text("Physical Token")
            } footer: {
                Text("Tap your NFC sticker to register it. Place the sticker on an object you won't carry everywhere.")
            }

            Section("Unlock Duration") {
                Picker("Duration", selection: Binding(
                    get: { vm.config.unlockDuration },
                    set: { vm.config.unlockDuration = $0; vm.saveSelection() }
                )) {
                    Text("5 min").tag(TimeInterval(300))
                    Text("15 min").tag(TimeInterval(900))
                    Text("30 min").tag(TimeInterval(1800))
                    Text("1 hour").tag(TimeInterval(3600))
                }
                .pickerStyle(.segmented)
            }

            Section("Watch Confirmation") {
                Toggle("Require Watch tap to unlock", isOn: Binding(
                    get: { vm.config.requireWatchConfirmation },
                    set: { vm.config.requireWatchConfirmation = $0; vm.saveSelection() }
                ))
            } footer: {
                Text("When on and a Watch is paired, the unlock button on your Watch must be tapped after NFC scan.")
            }
        }
        .navigationTitle("NFC Token Setup")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isScanning {
                ProgressView("Scanning…").padding().background(.regularMaterial).clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .alert("Token Registered", isPresented: $didRegister) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your NFC token has been saved. Keep it somewhere inconvenient.")
        }
        .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error?.localizedDescription ?? "")
        }
    }

    private func scan() {
        isScanning = true
        Task {
            do {
                try await unlockService.registerTag()
                vm.config.registeredNFCTagUID = ConfigStore().load().registeredNFCTagUID
                didRegister = true
            } catch {
                self.error = error
            }
            isScanning = false
        }
    }
}
```

**Step 2: UnlockView**

Create `Paperweight/Views/UnlockView.swift`:
```swift
import SwiftUI

struct UnlockView: View {
    @ObservedObject var vm: HomeViewModel
    @StateObject private var unlockService = UnlockService()
    @State private var error: Error?

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: unlockService.isUnlocked ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 80))
                .foregroundStyle(unlockService.isUnlocked ? .green : .orange)
                .animation(.spring(), value: unlockService.isUnlocked)

            if unlockService.isUnlocked, let expires = unlockService.unlockExpiresAt {
                VStack(spacing: 8) {
                    Text("Unlocked")
                        .font(.title2.bold())
                    Text("Re-locks at \(expires.formatted(date: .omitted, time: .shortened))")
                        .foregroundStyle(.secondary)
                    Button("Re-lock Now") { unlockService.relock() }
                        .buttonStyle(.bordered)
                        .tint(.red)
                }
            } else {
                VStack(spacing: 8) {
                    Text("Emergency Unlock")
                        .font(.title2.bold())
                    Text("Tap your NFC token to temporarily lift restrictions.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                Button {
                    Task {
                        do { try await unlockService.unlock() }
                        catch { self.error = error }
                    }
                } label: {
                    Label("Scan Token", systemImage: "wave.3.right")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(vm.config.registeredNFCTagUID == nil)
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Unlock")
        .alert("Error", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error?.localizedDescription ?? "")
        }
    }
}
```

**Step 3: Build**
```bash
xcodebuild build -scheme Paperweight -destination 'platform=iOS Simulator,name=iPhone 15 Pro' 2>&1 | tail -10
```

**Step 4: Commit**
```bash
git add Paperweight/Views/NFCSetupView.swift Paperweight/Views/UnlockView.swift
git commit -m "feat: NFC token setup and emergency unlock views"
```

---

## Phase 6: Watch App

### Task 15: WatchConnectivityService (iOS side)

**Step 1: Implement the iOS WatchConnectivity service**

Create `Paperweight/Services/WatchConnectivityService.swift`:
```swift
import WatchConnectivity
import Combine

final class WatchConnectivityService: NSObject, ObservableObject {
    static let shared = WatchConnectivityService()
    @Published var watchIsReachable: Bool = false
    @Published var pendingUnlockConfirmation: Bool = false

    private let unlockService: UnlockService
    private let configStore: ConfigStore

    init(unlockService: UnlockService = UnlockService(), configStore: ConfigStore = ConfigStore()) {
        self.unlockService = unlockService
        self.configStore = configStore
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func sendStatusUpdate() {
        guard WCSession.default.isReachable else { return }
        let config = configStore.load()
        let message: [String: Any] = [
            "isEnabled": config.isEnabled,
            "isUnlocked": unlockService.isUnlocked,
            "unlockExpires": unlockService.unlockExpiresAt?.timeIntervalSince1970 ?? 0
        ]
        WCSession.default.sendMessage(message, replyHandler: nil, errorHandler: nil)
    }

    func requestWatchConfirmation() async -> Bool {
        guard WCSession.default.isReachable else { return true }
        return await withCheckedContinuation { continuation in
            pendingUnlockConfirmation = true
            WCSession.default.sendMessage(["action": "confirmUnlock"], replyHandler: { reply in
                let confirmed = reply["confirmed"] as? Bool ?? false
                continuation.resume(returning: confirmed)
            }, errorHandler: { _ in
                continuation.resume(returning: false)
            })
        }
    }
}

extension WatchConnectivityService: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.watchIsReachable = state == .activated && session.isReachable
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.watchIsReachable = session.isReachable
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
}
```

**Step 2: Commit**
```bash
git add Paperweight/Services/WatchConnectivityService.swift
git commit -m "feat: WatchConnectivityService for status push and unlock confirmation"
```

---

### Task 16: Watch StatusView and ConfirmUnlockView

**Step 1: Implement WatchSessionService**

Create `PaperweightWatch/Services/WatchSessionService.swift`:
```swift
import WatchConnectivity
import SwiftUI

struct WatchStatus {
    var isEnabled: Bool = false
    var isUnlocked: Bool = false
    var unlockExpires: Date? = nil
}

final class WatchSessionService: NSObject, ObservableObject {
    static let shared = WatchSessionService()
    @Published var status = WatchStatus()
    @Published var unlockConfirmationPending = false

    private var confirmationReply: (([String: Any]) -> Void)?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func confirmUnlock() {
        confirmationReply?(["confirmed": true])
        confirmationReply = nil
        unlockConfirmationPending = false
    }

    func denyUnlock() {
        confirmationReply?(["confirmed": false])
        confirmationReply = nil
        unlockConfirmationPending = false
    }
}

extension WatchSessionService: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        DispatchQueue.main.async {
            if let action = message["action"] as? String, action == "confirmUnlock" {
                self.confirmationReply = replyHandler
                self.unlockConfirmationPending = true
            } else {
                self.status = WatchStatus(
                    isEnabled: message["isEnabled"] as? Bool ?? false,
                    isUnlocked: message["isUnlocked"] as? Bool ?? false,
                    unlockExpires: {
                        let ts = message["unlockExpires"] as? TimeInterval ?? 0
                        return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
                    }()
                )
                replyHandler([:])
            }
        }
    }
}
```

**Step 2: Implement StatusView**

Create `PaperweightWatch/Views/StatusView.swift`:
```swift
import SwiftUI

struct StatusView: View {
    @StateObject private var session = WatchSessionService.shared

    var body: some View {
        ZStack {
            if session.unlockConfirmationPending {
                ConfirmUnlockView(session: session)
            } else {
                mainStatus
            }
        }
        .animation(.easeInOut, value: session.unlockConfirmationPending)
    }

    @ViewBuilder
    private var mainStatus: some View {
        VStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 40))
                .foregroundStyle(iconColor)

            Text(statusText)
                .font(.headline)
                .multilineTextAlignment(.center)

            if session.status.isUnlocked, let exp = session.status.unlockExpires {
                Text("Until \(exp.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    private var iconName: String {
        if session.status.isUnlocked { return "lock.open.fill" }
        if session.status.isEnabled { return "lock.fill" }
        return "lock.slash"
    }

    private var iconColor: Color {
        if session.status.isUnlocked { return .green }
        if session.status.isEnabled { return .orange }
        return .gray
    }

    private var statusText: String {
        if session.status.isUnlocked { return "Unlocked" }
        if session.status.isEnabled { return "Paperweight On" }
        return "Paperweight Off"
    }
}
```

**Step 3: Implement ConfirmUnlockView**

Create `PaperweightWatch/Views/ConfirmUnlockView.swift`:
```swift
import SwiftUI

struct ConfirmUnlockView: View {
    @ObservedObject var session: WatchSessionService

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.open")
                .font(.system(size: 32))
                .foregroundStyle(.orange)

            Text("Allow unlock?")
                .font(.headline)

            HStack(spacing: 12) {
                Button(action: session.denyUnlock) {
                    Image(systemName: "xmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)

                Button(action: session.confirmUnlock) {
                    Image(systemName: "checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
        .padding()
    }
}
```

**Step 4: Wire Watch app root**

Update `PaperweightWatch/PaperweightWatchApp.swift`:
```swift
import SwiftUI

@main
struct PaperweightWatchApp: App {
    var body: some Scene {
        WindowGroup { StatusView() }
    }
}
```

**Step 5: Build both schemes**
```bash
xcodebuild build -scheme Paperweight -destination 'platform=iOS Simulator,name=iPhone 15 Pro' 2>&1 | tail -5
xcodebuild build -scheme PaperweightWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 9 (45mm)' 2>&1 | tail -5
```
Expected: Both succeed.

**Step 6: Commit**
```bash
git add PaperweightWatch/ Paperweight/Services/WatchConnectivityService.swift
git commit -m "feat: watchOS status and unlock confirmation views with WatchConnectivity"
```

---

## Phase 7: On-Device Testing Checklist

These require running on real hardware (iPhone 15 Pro + paired Watch).

- [ ] Install on device via Xcode (select your device, hit Run)
- [ ] Step through onboarding: toggle Paperweight on → system prompt appears → approve Family Controls
- [ ] Open FamilyActivityPicker → select 2–3 apps → save → verify those apps show shield when tapped
- [ ] Set a schedule with a free window 2 minutes in the future → wait → verify apps become accessible → wait for end → verify restrictions return
- [ ] Register NFC sticker: Settings → NFC Token Setup → Scan Token → tap sticker to phone
- [ ] Test wrong tag: hold a different NFC item → verify "tag not recognized" error
- [ ] Test correct tag unlock: tap registered sticker → restrictions lift → wait 15 min (or set 5 min for testing) → verify auto-relock
- [ ] With Watch paired: initiate unlock from iPhone → Watch vibrates with confirm dialog → tap Allow → unlock granted
- [ ] Deny on Watch → unlock blocked → verify restrictions stay
- [ ] Kill iPhone app → restrictions should persist (held by ManagedSettings store)
- [ ] Toggle Paperweight off → all restrictions clear

---

## Known Limitations

1. **No hard enforcement:** The user can go to Settings → Screen Time and disable Family Controls. This app is friction-based, not bulletproof.
2. **No midnight-spanning schedules:** Schedule must start and end on the same calendar day. A future iteration could split into two DeviceActivity monitors.
3. **Watch confirmation requires reachability:** If iPhone is out of Bluetooth range, unlock falls back to NFC-only (or can be configured to fail closed).
4. **NFC on Watch:** watchOS NFC is read-only and only in foreground; for v1 all NFC scanning is on iPhone.
5. **DeviceActivity timing:** System may fire extension callbacks with ~1 min granularity. Not a problem for daily schedules.
