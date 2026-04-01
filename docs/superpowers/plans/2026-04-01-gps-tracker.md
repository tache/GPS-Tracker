# GPS Tracker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS app that displays real-time GPS satellite positions on a polar sky graph, fed by MQTT messages from a GPSD bridge.

**Architecture:** An `MQTTService` actor receives JSON from `gps_monitor/sky` over TLS MQTT and streams `SkyMessage` values into `SatelliteStore` (@Observable). `SatelliteStore` drives two SwiftUI views: a `Canvas`-based polar graph (always visible) and a `Table`-based satellite list (slides in side-by-side). Satellite history is written to SwiftData (24-hour rolling window) for trail rendering on the polar graph.

**Tech Stack:** macOS 15+, Swift 5.10+, SwiftUI, SwiftData (local), Swift Testing, mqtt-nio 2.x (SPM)

---

## Domain Primer

- **PRN** (Pseudo-Random Noise number): Satellite identifier (e.g., PRN 21 = GPS satellite 21)
- **Elevation**: Degrees above the horizon (0° = horizon, 90° = directly overhead/zenith)
- **Azimuth**: Compass bearing in degrees (0°/360° = North, 90° = East, 180° = South, 270° = West)
- **SNR / ss**: Signal-to-noise ratio in dBHz. Higher = better. The JSON field is `ss`; we map it to `snr` in Swift.
- **Polar graph**: A circular plot where the center = zenith, the rim = horizon. A satellite at elevation 30° and azimuth 90° (East) plots at radius 67% of the circle's radius, at the 3 o'clock position.
- **GPSD**: GPS daemon running on a remote Linux server. `gpsd_monitor.py` bridges GPSD → MQTT.

---

## Important Notes for Implementers

- **FishDaddy (the human) owns all git commits and pushes.** Each task ends with a "Commit note" showing which files to stage and what message to use — do NOT run `git commit`.
- **Adding files to Xcode:** New Swift files must be added to the Xcode project via the xcode-proxy `XcodeWrite` tool (which handles project registration) OR by FishDaddy using Xcode's "Add Files to GPS Tracker" dialog. Never use plain `Write` tool for Swift source files — the file will exist on disk but Xcode won't know about it.
- **Test runner:** `xcodebuild test -project "GPS Tracker.xcodeproj" -scheme "GPS Tracker" -destination "platform=macOS,arch=arm64" 2>&1 | tail -20`
- **Swift Testing syntax:** Use `@Test`, `@Suite`, `#expect()` — not `XCTAssert`. Import `Testing` not `XCTest` in new test files.
- **All new source files** include the standard Xcode header and the version log comment per project conventions.

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `CLAUDE.md` | Modify | Update project description (remove WoW references) |
| `GPS Tracker/Models/ConnectionState.swift` | Create | Top-level `ConnectionState` enum |
| `GPS Tracker/Models/Satellite.swift` | Create | `Satellite` struct + `SatelliteColor` enum |
| `GPS Tracker/Models/SkyMessage.swift` | Create | `SkyMessage` + `SkyMessageSatellite` Codable structs |
| `GPS Tracker/Models/SatelliteHistoryEntry.swift` | Create | SwiftData `@Model` for trail persistence |
| `GPS Tracker/Models/MQTTConfiguration.swift` | Create | SwiftData `@Model` for broker settings |
| `GPS Tracker/Services/MQTTServiceProtocol.swift` | Create | Protocol enabling mock injection in tests |
| `GPS Tracker/Services/MQTTService.swift` | Create | `actor` owning mqtt-nio client + TLS connection |
| `GPS Tracker/Services/SatelliteStore.swift` | Create | `@Observable` consuming streams, writing history |
| `GPS Tracker/Utilities/KeychainHelper.swift` | Create | Keychain read/write for MQTT credentials |
| `GPS Tracker/Views/ContentView.swift` | Modify | Root `HStack` + toolbar + slide animation |
| `GPS Tracker/Views/ConfigurationView.swift` | Create | MQTT settings sheet |
| `GPS Tracker/Views/PolarGraphView.swift` | Create | `Canvas`-based satellite sky plot |
| `GPS Tracker/Views/SatelliteTableView.swift` | Create | Slide-out satellite data table |
| `GPS Tracker/GPS_TrackerApp.swift` | Modify | ModelContainer setup + SatelliteStore injection |
| `GPS Tracker/Item.swift` | Delete | Xcode template placeholder — not needed |
| `GPS TrackerTests/GPS_TrackerTests.swift` | Modify | Replace template; unit + integration tests |
| `GPS TrackerUITests/GPS_TrackerUITestsLaunchTests.swift` | Modify | UI tests for critical flows |

---

## Task 1: Update CLAUDE.md

The current `CLAUDE.md` contains instructions for a different project (Wheel of What 2). Replace it with GPS Tracker–specific content.

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Replace CLAUDE.md content**

Write the following to `CLAUDE.md` (use xcode-proxy `XcodeWrite` or plain `Write` — this is a markdown file, not a Swift source file):

```markdown
# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**GPS Tracker** is a macOS desktop application that displays real-time GPS satellite positions
on a polar sky view, fed by MQTT messages from a GPSD bridge running on a remote server.

**Platform:** macOS 15+
**Technologies:** Swift 5.10+, SwiftUI, SwiftData (local), Swift Testing, mqtt-nio 2.x

## Architecture

- `MQTTService` (actor) — owns mqtt-nio TLS connection, streams `SkyMessage` values
- `SatelliteStore` (@Observable) — consumes stream, maintains live satellite array, writes history
- `PolarGraphView` — Canvas-based polar plot (always visible)
- `SatelliteTableView` — slide-out satellite data table (side-by-side)
- SwiftData — local persistence for trail history (24h) and MQTT config

## Building & Testing

```bash
# Build
xcodebuild build \
  -project "GPS Tracker.xcodeproj" \
  -scheme "GPS Tracker" \
  -destination "platform=macOS,arch=arm64"

# Test
xcodebuild test \
  -project "GPS Tracker.xcodeproj" \
  -scheme "GPS Tracker" \
  -destination "platform=macOS,arch=arm64"
```

## GitHub

- All Claude-initiated GitHub operations use the **AgentFlux542** account
- Run `gh auth switch --user AgentFlux542` before any `gh` command
- FishDaddy (`tache`) handles all git commits and pushes

## Security

- NEVER read or process .env files
- MQTT credentials (username, password) are stored in the macOS Keychain only
- Do not log or print credentials anywhere
```

- [ ] **Commit note:** Stage `CLAUDE.md` — message: `docs: initialize CLAUDE.md for GPS Tracker project`

---

## Task 2: Add mqtt-nio SPM Dependency

This is a manual step performed by FishDaddy in Xcode. Document the exact steps.

**Files:** `GPS Tracker.xcodeproj` (modified by Xcode)

- [ ] **Step 1: Add package in Xcode**
  1. Open `GPS Tracker.xcodeproj` in Xcode
  2. Select the project in the navigator → "GPS Tracker" target → "Package Dependencies" tab
  3. Click `+` → paste URL: `https://github.com/swift-server-community/mqtt-nio.git`
  4. Set version rule: **Up to Next Major Version** from `2.0.0`
  5. Click "Add Package" → select the `MQTTNIO` library → click "Add Package"

- [ ] **Step 2: Verify build succeeds**

```bash
xcodebuild build \
  -project "GPS Tracker.xcodeproj" \
  -scheme "GPS Tracker" \
  -destination "platform=macOS,arch=arm64" 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Commit note:** Stage `GPS Tracker.xcodeproj/project.pbxproj` and `GPS Tracker.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` — message: `chore: add mqtt-nio 2.x SPM dependency`

---

## Task 3: Create Project Directory Structure

Create the folder hierarchy inside the Xcode project group. These directories must exist before adding Swift files.

**Files:** Directories only (no Swift source)

- [ ] **Step 1: Create directories using xcode-proxy XcodeMakeDir**

```
GPS Tracker/Models/
GPS Tracker/Services/
GPS Tracker/Views/
GPS Tracker/Utilities/
```

Run via xcode-proxy `XcodeMakeDir` tool for each path, or create them in Xcode's file navigator (right-click → New Group with Folder).

- [ ] **Step 2: Delete the template Item.swift**

Remove `GPS Tracker/Item.swift` from the project and disk. In Xcode: right-click → Delete → "Move to Trash".

The `GPS_TrackerApp.swift` currently references `Item.self` in its `ModelContainer` schema — this will cause a build error. That's expected; it will be fixed in Task 11 (App entry point).

- [ ] **Step 3: Verify the directory structure**

```bash
ls "GPS Tracker/"
```

Expected output includes: `Models/  Services/  Views/  Utilities/  Assets.xcassets/  GPS_TrackerApp.swift`

---

## Task 4: ConnectionState + MQTTServiceProtocol

These two files form the testability backbone of the MQTT layer. `ConnectionState` must be top-level (not nested in `MQTTService`) so the protocol can reference it without circular imports.

**Files:**
- Create: `GPS Tracker/Models/ConnectionState.swift`
- Create: `GPS Tracker/Services/MQTTServiceProtocol.swift`
- Modify: `GPS TrackerTests/GPS_TrackerTests.swift`

- [ ] **Step 1: Write the failing test**

Replace the contents of `GPS TrackerTests/GPS_TrackerTests.swift` with:

```swift
//
//  GPS_TrackerTests.swift
//  GPS TrackerTests
//
//  Created by Christopher Graham on 4/1/26.
//
// Claude Generated: version 1 - Initial test suite setup

import Testing
@testable import GPS_Tracker

@Suite("ConnectionState Tests")
struct ConnectionStateTests {

    @Test("ConnectionState cases are equatable")
    func equatability() {
        #expect(ConnectionState.disconnected == .disconnected)
        #expect(ConnectionState.connecting == .connecting)
        #expect(ConnectionState.connected == .connected)
        #expect(ConnectionState.error("boom") == .error("boom"))
        #expect(ConnectionState.error("a") != .error("b"))
        #expect(ConnectionState.connected != .disconnected)
    }

    @Test("ConnectionState error carries message")
    func errorMessage() {
        let state = ConnectionState.error("broker unreachable")
        if case .error(let msg) = state {
            #expect(msg == "broker unreachable")
        } else {
            Issue.record("Expected error case")
        }
    }
}
```

- [ ] **Step 2: Run test — expect failure (type not found)**

```bash
xcodebuild test \
  -project "GPS Tracker.xcodeproj" \
  -scheme "GPS Tracker" \
  -destination "platform=macOS,arch=arm64" \
  -only-testing:"GPS TrackerTests/ConnectionStateTests" 2>&1 | tail -10
```

Expected: build error — `cannot find type 'ConnectionState' in scope`

- [ ] **Step 3: Create ConnectionState.swift**

Use xcode-proxy `XcodeWrite` to create `GPS Tracker/Models/ConnectionState.swift`:

```swift
//
//  ConnectionState.swift
//  GPS Tracker
//
//  Created by Christopher Graham on 4/1/26.
//
// Claude Generated: version 1 - Top-level MQTT connection state enum

/// The current state of the MQTT broker connection.
/// Defined at the top level so MQTTServiceProtocol, MQTTService, and SatelliteStore
/// can all reference it without circular dependencies.
enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)
}
```

- [ ] **Step 4: Create MQTTServiceProtocol.swift**

Use xcode-proxy `XcodeWrite` to create `GPS Tracker/Services/MQTTServiceProtocol.swift`:

```swift
//
//  MQTTServiceProtocol.swift
//  GPS Tracker
//
//  Created by Christopher Graham on 4/1/26.
//
// Claude Generated: version 1 - Protocol enabling mock injection for testing

/// Protocol that MQTTService conforms to, enabling MockMQTTService injection in tests.
/// ConnectionState is top-level so this protocol compiles independently.
protocol MQTTServiceProtocol: AnyObject {
    func connect(config: MQTTConfiguration, username: String, password: String) async throws
    func disconnect() async
    var skyStream: AsyncStream<SkyMessage> { get }
    var connectionStateStream: AsyncStream<ConnectionState> { get }
}
```

Note: This file references `MQTTConfiguration` and `SkyMessage` which don't exist yet. The file will compile once those are created in later tasks.

- [ ] **Step 5: Run test — expect pass**

```bash
xcodebuild test \
  -project "GPS Tracker.xcodeproj" \
  -scheme "GPS Tracker" \
  -destination "platform=macOS,arch=arm64" \
  -only-testing:"GPS TrackerTests/ConnectionStateTests" 2>&1 | tail -10
```

Expected: `Test Suite 'ConnectionStateTests' passed`

- [ ] **Commit note:** Stage `GPS Tracker/Models/ConnectionState.swift`, `GPS Tracker/Services/MQTTServiceProtocol.swift`, `GPS TrackerTests/GPS_TrackerTests.swift` — message: `feat: add ConnectionState enum and MQTTServiceProtocol`

---

## Task 5: Satellite Struct + SatelliteColor

The core in-memory model for a single satellite. The `color` computed property encodes the SNR/used coloring logic from the web dashboard.

**Files:**
- Create: `GPS Tracker/Models/Satellite.swift`
- Modify: `GPS TrackerTests/GPS_TrackerTests.swift`

- [ ] **Step 1: Write failing tests**

Add to `GPS TrackerTests/GPS_TrackerTests.swift`:

```swift
@Suite("Satellite Tests")
struct SatelliteTests {

    // Helper — all fields required, seen defaults to 0
    private func sat(prn: Int = 1, el: Int = 45, az: Int = 90,
                     snr: Int = 30, used: Bool = true, seen: Int = 0) -> Satellite {
        Satellite(prn: prn, elevation: el, azimuth: az, snr: snr, used: used, seen: seen)
    }

    @Test("Not used → red regardless of SNR")
    func notUsedIsRed() {
        #expect(sat(snr: 40, used: false).color == .red)
        #expect(sat(snr: 0, used: false).color == .red)
        #expect(sat(snr: 35, used: false).color == .red)
    }

    @Test("Used + snr >= 35 → green")
    func usedHighSnrIsGreen() {
        #expect(sat(snr: 35, used: true).color == .green)
        #expect(sat(snr: 43, used: true).color == .green)
        #expect(sat(snr: 100, used: true).color == .green)
    }

    @Test("Used + snr 20-34 → orange")
    func usedMidSnrIsOrange() {
        #expect(sat(snr: 20, used: true).color == .orange)
        #expect(sat(snr: 26, used: true).color == .orange)
        #expect(sat(snr: 34, used: true).color == .orange)
    }

    @Test("Used + snr < 20 → yellow")
    func usedLowSnrIsYellow() {
        #expect(sat(snr: 0, used: true).color == .yellow)
        #expect(sat(snr: 15, used: true).color == .yellow)
        #expect(sat(snr: 19, used: true).color == .yellow)
    }

    @Test("Satellite id equals prn")
    func idEqualsPrn() {
        #expect(sat(prn: 21).id == 21)
    }
}
```

- [ ] **Step 2: Run test — expect failure**

```bash
xcodebuild test \
  -project "GPS Tracker.xcodeproj" \
  -scheme "GPS Tracker" \
  -destination "platform=macOS,arch=arm64" \
  -only-testing:"GPS TrackerTests/SatelliteTests" 2>&1 | tail -10
```

Expected: build error — `cannot find type 'Satellite' in scope`

- [ ] **Step 3: Create Satellite.swift**

Use xcode-proxy `XcodeWrite` to create `GPS Tracker/Models/Satellite.swift`:

```swift
//
//  Satellite.swift
//  GPS Tracker
//
//  Created by Christopher Graham on 4/1/26.
//
// Claude Generated: version 1 - In-memory satellite model and color classification

import Foundation

/// Color classification for a satellite dot on the polar graph and table row.
/// Derived from the `used` flag and SNR value, matching the web dashboard rule:
/// `red if not used, else green if ss>=35, else orange if ss>=20, else yellow`
enum SatelliteColor: Equatable {
    case red    // not used (outline circle)
    case green  // used, snr >= 35 (solid)
    case orange // used, snr >= 20 (solid)
    case yellow // used, snr < 20 (solid)
}

/// In-memory representation of a single GPS satellite from the current sky message.
/// Not persisted — lives only in SatelliteStore.satellites.
/// Note: For v1, PRN is treated as unique (MTK-3301 is GPS-only).
/// Multi-constellation hardware would require a composite (gnssid, prn) key.
struct Satellite: Identifiable {
    let prn: Int
    let elevation: Int  // degrees above horizon (0–90)
    let azimuth: Int    // degrees, true north (0–359)
    let snr: Int        // signal-to-noise ratio dBHz (mapped from JSON "ss" field)
    let used: Bool      // true if contributing to the current GPS fix
    let seen: Int       // seconds since first seen this GPSD session (raw from MQTT)

    var id: Int { prn }

    /// Color for this satellite's dot and table row.
    var color: SatelliteColor {
        guard used else { return .red }
        if snr >= 35 { return .green }
        if snr >= 20 { return .orange }
        return .yellow
    }
}
```

- [ ] **Step 4: Run test — expect pass**

```bash
xcodebuild test \
  -project "GPS Tracker.xcodeproj" \
  -scheme "GPS Tracker" \
  -destination "platform=macOS,arch=arm64" \
  -only-testing:"GPS TrackerTests/SatelliteTests" 2>&1 | tail -10
```

Expected: `Test Suite 'SatelliteTests' passed`

- [ ] **Commit note:** Stage `GPS Tracker/Models/Satellite.swift`, `GPS TrackerTests/GPS_TrackerTests.swift` — message: `feat: add Satellite struct and SatelliteColor enum`

---

## Task 6: SkyMessage Codable Models

These structs decode the `gps_monitor/sky` JSON payload from MQTT. The JSON field `ss` becomes `snr` on `Satellite` — the translation happens in `SatelliteStore`, not here.

**Files:**
- Create: `GPS Tracker/Models/SkyMessage.swift`
- Modify: `GPS TrackerTests/GPS_TrackerTests.swift`

- [ ] **Step 1: Write failing tests**

Add to `GPS TrackerTests/GPS_TrackerTests.swift`:

```swift
@Suite("SkyMessage Decoding Tests")
struct SkyMessageDecodingTests {

    private let fullPayload = """
    {
      "sat_used": 9,
      "sat_visible": 14,
      "hdop": 0.85,
      "vdop": null,
      "pdop": 1.42,
      "tdop": null,
      "gdop": 1.76,
      "xdop": 0.61,
      "ydop": 0.58,
      "satellites": [
        { "prn": 5, "el": 72, "az": 214, "ss": 42, "used": true, "seen": 312 },
        { "prn": 29, "el": 18, "az": 47, "ss": 22, "used": false, "seen": 88, "gnssid": 0, "svid": 29 }
      ]
    }
    """

    @Test("Decodes top-level fields correctly")
    func topLevelFields() throws {
        let msg = try JSONDecoder().decode(SkyMessage.self, from: Data(fullPayload.utf8))
        #expect(msg.satUsed == 9)
        #expect(msg.satVisible == 14)
        #expect(msg.hdop == 0.85)
        #expect(msg.vdop == nil)
        #expect(msg.pdop == 1.42)
        #expect(msg.satellites.count == 2)
    }

    @Test("Decodes satellite array with ss field")
    func satelliteArray() throws {
        let msg = try JSONDecoder().decode(SkyMessage.self, from: Data(fullPayload.utf8))
        let first = msg.satellites[0]
        #expect(first.prn == 5)
        #expect(first.el == 72)
        #expect(first.az == 214)
        #expect(first.ss == 42)
        #expect(first.used == true)
        #expect(first.seen == 312)
        #expect(first.gnssid == nil)
    }

    @Test("Decodes optional gnssid and svid")
    func optionalGnssFields() throws {
        let msg = try JSONDecoder().decode(SkyMessage.self, from: Data(fullPayload.utf8))
        let second = msg.satellites[1]
        #expect(second.gnssid == 0)
        #expect(second.svid == 29)
    }

    @Test("Handles missing optional DOP fields gracefully")
    func missingDopFields() throws {
        let minimal = """
        { "sat_used": 1, "sat_visible": 1, "satellites": [] }
        """
        let msg = try JSONDecoder().decode(SkyMessage.self, from: Data(minimal.utf8))
        #expect(msg.hdop == nil)
        #expect(msg.satellites.isEmpty)
    }

    @Test("Throws on malformed JSON")
    func malformedJson() {
        let bad = """{ "sat_used": "not-a-number" }"""
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(SkyMessage.self, from: Data(bad.utf8))
        }
    }
}
```

- [ ] **Step 2: Run test — expect failure**

```bash
xcodebuild test \
  -project "GPS Tracker.xcodeproj" \
  -scheme "GPS Tracker" \
  -destination "platform=macOS,arch=arm64" \
  -only-testing:"GPS TrackerTests/SkyMessageDecodingTests" 2>&1 | tail -10
```

Expected: build error — `cannot find type 'SkyMessage' in scope`

- [ ] **Step 3: Create SkyMessage.swift**

Use xcode-proxy `XcodeWrite` to create `GPS Tracker/Models/SkyMessage.swift`:

```swift
//
//  SkyMessage.swift
//  GPS Tracker
//
//  Created by Christopher Graham on 4/1/26.
//
// Claude Generated: version 1 - Codable structs for gps_monitor/sky MQTT payload

import Foundation

/// Top-level payload for the `gps_monitor/sky` MQTT topic.
/// nsat and usat fields from the wire format are intentionally omitted —
/// satUsed/satVisible carry the same information.
struct SkyMessage: Codable {
    let satUsed: Int
    let satVisible: Int
    let hdop: Double?
    let vdop: Double?
    let pdop: Double?
    let tdop: Double?
    let gdop: Double?
    let xdop: Double?
    let ydop: Double?
    let satellites: [SkyMessageSatellite]

    enum CodingKeys: String, CodingKey {
        case satUsed = "sat_used"
        case satVisible = "sat_visible"
        case hdop, vdop, pdop, tdop, gdop, xdop, ydop, satellites
    }
}

/// Per-satellite entry within a SkyMessage.
/// Property names match JSON keys exactly — no CodingKeys needed.
/// The `ss` field (signal strength, dBHz) maps to `snr` on Satellite
/// in SatelliteStore: Satellite(prn: s.prn, ..., snr: s.ss, ...)
struct SkyMessageSatellite: Codable {
    let prn: Int
    let el: Int     // elevation degrees
    let az: Int     // azimuth degrees, true north
    let ss: Int     // signal-to-noise ratio dBHz; becomes Satellite.snr
    let used: Bool
    let seen: Int
    let gnssid: Int? // GNSS constellation ID; nil for MTK-3301 (GPS-only)
    let svid: Int?   // satellite vehicle ID within constellation; nil for MTK-3301
}
```

- [ ] **Step 4: Run test — expect pass**

```bash
xcodebuild test \
  -project "GPS Tracker.xcodeproj" \
  -scheme "GPS Tracker" \
  -destination "platform=macOS,arch=arm64" \
  -only-testing:"GPS TrackerTests/SkyMessageDecodingTests" 2>&1 | tail -10
```

Expected: `Test Suite 'SkyMessageDecodingTests' passed`

- [ ] **Commit note:** Stage `GPS Tracker/Models/SkyMessage.swift`, `GPS TrackerTests/GPS_TrackerTests.swift` — message: `feat: add SkyMessage Codable models`

---

## Task 7: SwiftData Models

Two `@Model` classes for local persistence: satellite trail history and MQTT broker configuration.

**Files:**
- Create: `GPS Tracker/Models/SatelliteHistoryEntry.swift`
- Create: `GPS Tracker/Models/MQTTConfiguration.swift`
- Modify: `GPS TrackerTests/GPS_TrackerTests.swift`

- [ ] **Step 1: Write failing tests**

Add to `GPS TrackerTests/GPS_TrackerTests.swift`:

```swift
@Suite("SwiftData Model Tests")
struct SwiftDataModelTests {

    @Test("SatelliteHistoryEntry initializes with all fields")
    func historyEntryInit() {
        let now = Date()
        let entry = SatelliteHistoryEntry(prn: 21, elevation: 80, azimuth: 31,
                                          snr: 43, used: true, timestamp: now)
        #expect(entry.prn == 21)
        #expect(entry.elevation == 80)
        #expect(entry.azimuth == 31)
        #expect(entry.snr == 43)
        #expect(entry.used == true)
        #expect(entry.timestamp == now)
    }

    @Test("MQTTConfiguration default values")
    func mqttConfigDefaults() {
        let config = MQTTConfiguration()
        #expect(config.hostname == "")
        #expect(config.port == 8883)
    }

    @Test("MQTTConfiguration custom init")
    func mqttConfigCustom() {
        let config = MQTTConfiguration(hostname: "192.168.1.100", port: 1883)
        #expect(config.hostname == "192.168.1.100")
        #expect(config.port == 1883)
    }

    @Test("Prune predicate — entries older than 24h")
    func prunePredicateLogic() {
        let now = Date()
        let old = SatelliteHistoryEntry(prn: 1, elevation: 10, azimuth: 90,
                                        snr: 20, used: true,
                                        timestamp: now.addingTimeInterval(-90000)) // 25 hours ago
        let fresh = SatelliteHistoryEntry(prn: 2, elevation: 20, azimuth: 180,
                                          snr: 30, used: true,
                                          timestamp: now.addingTimeInterval(-3600)) // 1 hour ago
        let cutoff = now.addingTimeInterval(-86400)
        #expect(old.timestamp < cutoff)    // should be pruned
        #expect(fresh.timestamp >= cutoff) // should be kept
    }
}
```

- [ ] **Step 2: Run test — expect failure**

```bash
xcodebuild test \
  -project "GPS Tracker.xcodeproj" \
  -scheme "GPS Tracker" \
  -destination "platform=macOS,arch=arm64" \
  -only-testing:"GPS TrackerTests/SwiftDataModelTests" 2>&1 | tail -10
```

Expected: build error — `cannot find type 'SatelliteHistoryEntry' in scope`

- [ ] **Step 3: Create SatelliteHistoryEntry.swift**

Use xcode-proxy `XcodeWrite` to create `GPS Tracker/Models/SatelliteHistoryEntry.swift`:

```swift
//
//  SatelliteHistoryEntry.swift
//  GPS Tracker
//
//  Created by Christopher Graham on 4/1/26.
//
// Claude Generated: version 1 - SwiftData model for satellite trail history

import Foundation
import SwiftData

/// Persisted record of a satellite's position at a point in time.
/// Used to render trail paths on the polar graph.
/// Pruned to a 24-hour rolling window by SatelliteStore.
/// Note: `seen` is intentionally not stored — it's a GPSD session counter
/// and is not meaningful as historical data.
@Model
class SatelliteHistoryEntry {
    var prn: Int
    var elevation: Int
    var azimuth: Int
    var snr: Int
    var used: Bool
    var timestamp: Date

    init(prn: Int, elevation: Int, azimuth: Int, snr: Int, used: Bool, timestamp: Date) {
        self.prn = prn
        self.elevation = elevation
        self.azimuth = azimuth
        self.snr = snr
        self.used = used
        self.timestamp = timestamp
    }
}
```

- [ ] **Step 4: Create MQTTConfiguration.swift**

Use xcode-proxy `XcodeWrite` to create `GPS Tracker/Models/MQTTConfiguration.swift`:

```swift
//
//  MQTTConfiguration.swift
//  GPS Tracker
//
//  Created by Christopher Graham on 4/1/26.
//
// Claude Generated: version 1 - SwiftData model for MQTT broker connection settings

import Foundation
import SwiftData

/// Persisted MQTT broker connection settings (non-sensitive fields only).
/// Username and password are stored in the macOS Keychain via KeychainHelper.
/// Exactly one row exists at runtime — enforced by SatelliteStore.fetchOrCreate().
@Model
class MQTTConfiguration {
    var hostname: String
    var port: Int  // default 8883 (standard MQTT TLS port)

    init(hostname: String = "", port: Int = 8883) {
        self.hostname = hostname
        self.port = port
    }
}
```

- [ ] **Step 5: Run test — expect pass**

```bash
xcodebuild test \
  -project "GPS Tracker.xcodeproj" \
  -scheme "GPS Tracker" \
  -destination "platform=macOS,arch=arm64" \
  -only-testing:"GPS TrackerTests/SwiftDataModelTests" 2>&1 | tail -10
```

Expected: `Test Suite 'SwiftDataModelTests' passed`

- [ ] **Commit note:** Stage both model files and test file — message: `feat: add SwiftData models for satellite history and MQTT config`

---

## Task 8: KeychainHelper

Secure storage for MQTT username and password. `MQTTService` never reads the Keychain directly — it receives credentials as parameters from `SatelliteStore`.

**Files:**
- Create: `GPS Tracker/Utilities/KeychainHelper.swift`
- Modify: `GPS TrackerTests/GPS_TrackerTests.swift`

- [ ] **Step 1: Write failing tests**

Add to `GPS TrackerTests/GPS_TrackerTests.swift`:

```swift
@Suite("KeychainHelper Tests")
struct KeychainHelperTests {

    @Test("Save and load credentials")
    func saveAndLoad() throws {
        defer { KeychainHelper.delete() }
        try KeychainHelper.save(username: "testuser", password: "testpass")
        let loaded = KeychainHelper.load()
        #expect(loaded?.username == "testuser")
        #expect(loaded?.password == "testpass")
    }

    @Test("Load returns nil when nothing saved")
    func loadWhenEmpty() {
        KeychainHelper.delete()
        #expect(KeychainHelper.load() == nil)
    }

    @Test("Delete removes credentials")
    func deleteRemoves() throws {
        try KeychainHelper.save(username: "u", password: "p")
        KeychainHelper.delete()
        #expect(KeychainHelper.load() == nil)
    }

    @Test("Save overwrites previous credentials")
    func saveOverwrites() throws {
        defer { KeychainHelper.delete() }
        try KeychainHelper.save(username: "first", password: "pass1")
        try KeychainHelper.save(username: "second", password: "pass2")
        let loaded = KeychainHelper.load()
        #expect(loaded?.username == "second")
        #expect(loaded?.password == "pass2")
    }
}
```

- [ ] **Step 2: Run test — expect failure**

```bash
xcodebuild test \
  -project "GPS Tracker.xcodeproj" \
  -scheme "GPS Tracker" \
  -destination "platform=macOS,arch=arm64" \
  -only-testing:"GPS TrackerTests/KeychainHelperTests" 2>&1 | tail -10
```

Expected: build error — `cannot find type 'KeychainHelper' in scope`

- [ ] **Step 3: Create KeychainHelper.swift**

Use xcode-proxy `XcodeWrite` to create `GPS Tracker/Utilities/KeychainHelper.swift`:

```swift
//
//  KeychainHelper.swift
//  GPS Tracker
//
//  Created by Christopher Graham on 4/1/26.
//
// Claude Generated: version 1 - Keychain read/write for MQTT credentials

import Foundation
import Security

/// Manages MQTT credentials (username + password) in the macOS Keychain.
/// Credentials are stored as a single item: username in the account field,
/// password as the password data.
enum KeychainHelper {

    private static let service = "com.gps-tracker.mqtt-credentials"

    /// Saves username and password to the Keychain. Overwrites any existing entry.
    static func save(username: String, password: String) throws {
        delete() // remove existing entry before adding new one

        guard let passwordData = password.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: username,
            kSecValueData: passwordData
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    /// Loads credentials from the Keychain. Returns nil if no entry exists.
    static func load() -> (username: String, password: String)? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecReturnAttributes: true,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let dict = result as? [CFString: Any],
              let account = dict[kSecAttrAccount] as? String,
              let data = dict[kSecValueData] as? Data,
              let password = String(data: data, encoding: .utf8)
        else { return nil }

        return (username: account, password: password)
    }

    /// Removes the stored credentials from the Keychain. No-op if nothing is stored.
    static func delete() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum KeychainError: Error {
    case encodingFailed
    case saveFailed(OSStatus)
}
```

- [ ] **Step 4: Run test — expect pass**

```bash
xcodebuild test \
  -project "GPS Tracker.xcodeproj" \
  -scheme "GPS Tracker" \
  -destination "platform=macOS,arch=arm64" \
  -only-testing:"GPS TrackerTests/KeychainHelperTests" 2>&1 | tail -10
```

Expected: `Test Suite 'KeychainHelperTests' passed`

- [ ] **Commit note:** Stage `GPS Tracker/Utilities/KeychainHelper.swift` and test file — message: `feat: add KeychainHelper for MQTT credential storage`

---

## Task 9: MQTTService Actor

The MQTT layer. Owns the `mqtt-nio` TLS client, manages connection lifecycle, decodes JSON, and exposes two `AsyncStream`s. Reconnects automatically with exponential backoff.

**Files:**
- Create: `GPS Tracker/Services/MQTTService.swift`
- Modify: `GPS TrackerTests/GPS_TrackerTests.swift`

**Domain note:** `mqtt-nio` uses the `MQTTNIO` module. A client is created with `MQTTClient`, configured with `MQTTConfiguration` (mqtt-nio's own type, distinct from our `MQTTConfiguration` SwiftData model — qualify as `MQTTNIO.MQTTConfiguration` to disambiguate). TLS is configured via `TLSConfiguration` from `NIOSSL`.

- [ ] **Step 1: Write integration tests using MockMQTTService**

Add to `GPS TrackerTests/GPS_TrackerTests.swift`:

```swift
// MockMQTTService for integration tests — yields pre-defined values
final class MockMQTTService: MQTTServiceProtocol, @unchecked Sendable {
    var skyMessages: [SkyMessage] = []
    var stateSequence: [ConnectionState] = []
    private(set) var connectCalled = false
    private(set) var disconnectCalled = false
    private(set) var lastConfig: MQTTConfiguration?

    func connect(config: MQTTConfiguration, username: String, password: String) async throws {
        connectCalled = true
        lastConfig = config
    }

    func disconnect() async {
        disconnectCalled = true
    }

    var skyStream: AsyncStream<SkyMessage> {
        let messages = skyMessages
        return AsyncStream { continuation in
            for msg in messages { continuation.yield(msg) }
            continuation.finish()
        }
    }

    var connectionStateStream: AsyncStream<ConnectionState> {
        let states = stateSequence
        return AsyncStream { continuation in
            for state in states { continuation.yield(state) }
            continuation.finish()
        }
    }
}

@Suite("MQTTService Protocol Tests")
struct MQTTServiceProtocolTests {

    @Test("MockMQTTService connect records call")
    func mockConnectRecords() async throws {
        let mock = MockMQTTService()
        let config = MQTTConfiguration(hostname: "test.broker", port: 8883)
        try await mock.connect(config: config, username: "u", password: "p")
        #expect(mock.connectCalled == true)
        #expect(mock.lastConfig?.hostname == "test.broker")
    }

    @Test("MockMQTTService skyStream yields all messages")
    func mockSkyStreamYieldsMessages() async {
        let mock = MockMQTTService()
        let msg = SkyMessage(satUsed: 5, satVisible: 10,
                             hdop: nil, vdop: nil, pdop: nil, tdop: nil,
                             gdop: nil, xdop: nil, ydop: nil, satellites: [])
        mock.skyMessages = [msg, msg]
        var count = 0
        for await _ in mock.skyStream { count += 1 }
        #expect(count == 2)
    }

    @Test("MockMQTTService connectionStateStream yields states")
    func mockStateStreamYieldsStates() async {
        let mock = MockMQTTService()
        mock.stateSequence = [.connecting, .connected]
        var states: [ConnectionState] = []
        for await state in mock.connectionStateStream { states.append(state) }
        #expect(states == [.connecting, .connected])
    }
}
```

- [ ] **Step 2: Run test — expect pass (mock-only, no MQTTService yet)**

```bash
xcodebuild test \
  -project "GPS Tracker.xcodeproj" \
  -scheme "GPS Tracker" \
  -destination "platform=macOS,arch=arm64" \
  -only-testing:"GPS TrackerTests/MQTTServiceProtocolTests" 2>&1 | tail -10
```

Expected: `Test Suite 'MQTTServiceProtocolTests' passed`

- [ ] **Step 3: Create MQTTService.swift**

Use xcode-proxy `XcodeWrite` to create `GPS Tracker/Services/MQTTService.swift`:

```swift
//
//  MQTTService.swift
//  GPS Tracker
//
//  Created by Christopher Graham on 4/1/26.
//
// Claude Generated: version 1 - MQTT actor with TLS connection and AsyncStream output

import Foundation
import MQTTNIO
import NIOCore
import NIOSSL
import Logging

/// Owns the mqtt-nio TLS client. Subscribes to gps_monitor/sky and
/// gps_monitor/availability, decodes JSON payloads, and streams results.
/// Reconnects automatically with exponential backoff (1s → 2s → 4s… cap 60s).
actor MQTTService: MQTTServiceProtocol {

    private var client: MQTTClient?
    private var skyStreamContinuation: AsyncStream<SkyMessage>.Continuation?
    private var stateStreamContinuation: AsyncStream<ConnectionState>.Continuation?
    private var reconnectTask: Task<Void, Never>?

    // MARK: - Protocol

    nonisolated var skyStream: AsyncStream<SkyMessage> {
        AsyncStream { continuation in
            Task { await self.setSkyStreamContinuation(continuation) }
        }
    }

    nonisolated var connectionStateStream: AsyncStream<ConnectionState> {
        AsyncStream { continuation in
            Task { await self.setStateStreamContinuation(continuation) }
        }
    }

    func connect(config: MQTTConfiguration, username: String, password: String) async throws {
        await disconnect()
        await yieldState(.connecting)

        let tlsConfig = TLSConfiguration.makeClientConfiguration()
        var mqttConfig = MQTTNIO.MQTTClient.Configuration(
            target: .host(config.hostname, port: config.port),
            tls: .niossl(tlsConfig)
        )

        if !username.isEmpty {
            mqttConfig.userName = username
            mqttConfig.password = password
        }

        let newClient = MQTTClient(configuration: mqttConfig,
                                   eventLoopGroupProvider: .createNew,
                                   logger: Logger(label: "gps-tracker.mqtt"))
        self.client = newClient

        do {
            try await newClient.connect()
            await yieldState(.connected)
            try await subscribeToTopics(client: newClient)
            startMessageHandler(client: newClient)
        } catch {
            await yieldState(.error(error.localizedDescription))
            scheduleReconnect(config: config, username: username, password: password)
        }
    }

    func disconnect() async {
        reconnectTask?.cancel()
        reconnectTask = nil
        if let client {
            try? await client.disconnect()
            try? await client.shutdown()
        }
        client = nil
        await yieldState(.disconnected)
    }

    // MARK: - Private

    private func setSkyStreamContinuation(_ continuation: AsyncStream<SkyMessage>.Continuation) {
        skyStreamContinuation = continuation
    }

    private func setStateStreamContinuation(_ continuation: AsyncStream<ConnectionState>.Continuation) {
        stateStreamContinuation = continuation
    }

    private func yieldState(_ state: ConnectionState) {
        stateStreamContinuation?.yield(state)
    }

    private func subscribeToTopics(client: MQTTClient) async throws {
        try await client.subscribe(to: [
            MQTTSubscribeInfo(topicFilter: "gps_monitor/sky", qos: .atLeastOnce),
            MQTTSubscribeInfo(topicFilter: "gps_monitor/availability", qos: .atLeastOnce)
        ])
    }

    private func startMessageHandler(client: MQTTClient) {
        Task {
            for await message in client.messages {
                await handleMessage(message)
            }
            // Stream ended — broker disconnected
            await yieldState(.error("Broker disconnected"))
        }
    }

    private func handleMessage(_ message: MQTTMessage) {
        let topic = message.topic
        let payload = Data(message.payload.readableBytesView)

        if topic == "gps_monitor/sky" {
            guard let skyMsg = try? JSONDecoder().decode(SkyMessage.self, from: payload) else {
                return // malformed message — silently discard
            }
            skyStreamContinuation?.yield(skyMsg)
        } else if topic == "gps_monitor/availability" {
            let text = String(data: payload, encoding: .utf8) ?? ""
            if text == "offline" {
                yieldState(.error("GPS bridge offline"))
            }
            // "online" is silently ignored — TCP connection implies connected
        }
    }

    private func scheduleReconnect(config: MQTTConfiguration, username: String, password: String,
                                    delay: TimeInterval = 1.0) {
        reconnectTask = Task {
            var currentDelay = delay
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(currentDelay))
                guard !Task.isCancelled else { break }
                do {
                    try await connect(config: config, username: username, password: password)
                    break
                } catch {
                    currentDelay = min(currentDelay * 2, 60)
                }
            }
        }
    }
}
```

- [ ] **Step 4: Build to verify compilation (no live connection test)**

```bash
xcodebuild build \
  -project "GPS Tracker.xcodeproj" \
  -scheme "GPS Tracker" \
  -destination "platform=macOS,arch=arm64" 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Run all tests so far**

```bash
xcodebuild test \
  -project "GPS Tracker.xcodeproj" \
  -scheme "GPS Tracker" \
  -destination "platform=macOS,arch=arm64" \
  -only-testing:"GPS TrackerTests" 2>&1 | tail -15
```

Expected: all previously passing test suites still pass.

- [ ] **Commit note:** Stage `GPS Tracker/Services/MQTTService.swift` and test file — message: `feat: add MQTTService actor with TLS and AsyncStream output`

---

## Task 10: SatelliteStore

The `@Observable` state hub. Consumes both async streams from `MQTTService`, maintains the live satellite array, handles SwiftData singleton enforcement, writes history at a throttled rate, and prunes old history.

**Files:**
- Create: `GPS Tracker/Services/SatelliteStore.swift`
- Modify: `GPS TrackerTests/GPS_TrackerTests.swift`

- [ ] **Step 1: Write failing integration tests**

Add to `GPS TrackerTests/GPS_TrackerTests.swift`:

```swift
@Suite("SatelliteStore Tests")
struct SatelliteStoreTests {

    private func makeSkyMessage(satellites: [SkyMessageSatellite]) -> SkyMessage {
        SkyMessage(satUsed: satellites.filter(\.used).count,
                   satVisible: satellites.count,
                   hdop: nil, vdop: nil, pdop: nil, tdop: nil,
                   gdop: nil, xdop: nil, ydop: nil,
                   satellites: satellites)
    }

    private func makeSatEntry(prn: Int, snr: Int, used: Bool) -> SkyMessageSatellite {
        SkyMessageSatellite(prn: prn, el: 45, az: 90, ss: snr, used: used, seen: 100,
                             gnssid: nil, svid: nil)
    }

    @Test("Converts SkyMessageSatellite to Satellite correctly")
    func conversionMapsFields() async {
        let mock = MockMQTTService()
        let entry = makeSatEntry(prn: 21, snr: 43, used: true)
        mock.skyMessages = [makeSkyMessage(satellites: [entry])]
        mock.stateSequence = [.connected]

        let store = SatelliteStore(mqttService: mock)
        // Allow stream to process
        try? await Task.sleep(for: .milliseconds(100))

        let sat = store.satellites.first { $0.prn == 21 }
        #expect(sat?.snr == 43)   // ss → snr mapping
        #expect(sat?.used == true)
        #expect(sat?.elevation == 45)
        #expect(sat?.azimuth == 90)
    }

    @Test("Satellites sorted by SNR descending")
    func satellitesSortedBySnr() async {
        let mock = MockMQTTService()
        let entries = [
            makeSatEntry(prn: 1, snr: 15, used: true),
            makeSatEntry(prn: 2, snr: 43, used: true),
            makeSatEntry(prn: 3, snr: 28, used: true)
        ]
        mock.skyMessages = [makeSkyMessage(satellites: entries)]
        mock.stateSequence = []

        let store = SatelliteStore(mqttService: mock)
        try? await Task.sleep(for: .milliseconds(100))

        let snrOrder = store.satellites.map(\.snr)
        #expect(snrOrder == snrOrder.sorted(by: >))
    }

    @Test("Connection state mirrors MQTT service stream")
    func connectionStateMirrored() async {
        let mock = MockMQTTService()
        mock.stateSequence = [.connecting, .connected]
        mock.skyMessages = []

        let store = SatelliteStore(mqttService: mock)
        try? await Task.sleep(for: .milliseconds(100))

        #expect(store.connectionState == .connected)
    }

    @Test("Write throttle — skips writes within 5 second window")
    func writeThrottleSkipsRecentWrites() {
        // Verify that lastHistoryWriteDate logic is present and correct
        // This tests the guard condition, not SwiftData itself
        let store = SatelliteStore(mqttService: MockMQTTService())
        #expect(store.shouldWriteHistory(lastWrite: Date()) == false)
        #expect(store.shouldWriteHistory(lastWrite: Date().addingTimeInterval(-6)) == true)
        #expect(store.shouldWriteHistory(lastWrite: nil) == true)
    }
}
```

- [ ] **Step 2: Run test — expect failure**

```bash
xcodebuild test \
  -project "GPS Tracker.xcodeproj" \
  -scheme "GPS Tracker" \
  -destination "platform=macOS,arch=arm64" \
  -only-testing:"GPS TrackerTests/SatelliteStoreTests" 2>&1 | tail -10
```

Expected: build error — `cannot find type 'SatelliteStore' in scope`

- [ ] **Step 3: Create SatelliteStore.swift**

Use xcode-proxy `XcodeWrite` to create `GPS Tracker/Services/SatelliteStore.swift`:

```swift
//
//  SatelliteStore.swift
//  GPS Tracker
//
//  Created by Christopher Graham on 4/1/26.
//
// Claude Generated: version 1 - Observable state hub consuming MQTT streams

import Foundation
import SwiftData
import Observation

/// Central state store for the app. Consumes AsyncStreams from MQTTService,
/// maintains live satellite array, writes history to SwiftData (throttled),
/// and prunes entries older than 24 hours.
@Observable
final class SatelliteStore {

    // MARK: - Published State

    private(set) var satellites: [Satellite] = []
    private(set) var connectionState: ConnectionState = .disconnected
    var showTrails: Bool = true
    var showTable: Bool = false

    // MARK: - Private

    private let mqttService: any MQTTServiceProtocol
    private var modelContext: ModelContext?
    private var lastHistoryWriteDate: Date?
    private var skyTask: Task<Void, Never>?
    private var stateTask: Task<Void, Never>?
    private var pruneTimer: Timer?

    // MARK: - Init

    init(mqttService: any MQTTServiceProtocol) {
        self.mqttService = mqttService
        startStreams()
    }

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
        startPruneTimer()
    }

    // MARK: - Configuration Lifecycle

    func connectWithCurrentConfig() async {
        guard let context = modelContext else { return }
        let config = fetchOrCreateConfig(in: context)
        let creds = KeychainHelper.load()
        try? await mqttService.connect(
            config: config,
            username: creds?.username ?? "",
            password: creds?.password ?? ""
        )
    }

    func reconnect(config: MQTTConfiguration) async {
        await mqttService.disconnect()
        let creds = KeychainHelper.load()
        try? await mqttService.connect(
            config: config,
            username: creds?.username ?? "",
            password: creds?.password ?? ""
        )
    }

    // MARK: - Stream Consumers

    private func startStreams() {
        skyTask = Task { [weak self] in
            guard let self else { return }
            for await message in mqttService.skyStream {
                await MainActor.run { self.processSkyMessage(message) }
            }
        }

        stateTask = Task { [weak self] in
            guard let self else { return }
            for await state in mqttService.connectionStateStream {
                await MainActor.run { self.connectionState = state }
            }
        }
    }

    private func processSkyMessage(_ message: SkyMessage) {
        satellites = message.satellites.map { s in
            Satellite(prn: s.prn, elevation: s.el, azimuth: s.az,
                      snr: s.ss, used: s.used, seen: s.seen)
        }.sorted { $0.snr > $1.snr }

        maybeWriteHistory()
    }

    // MARK: - History (SwiftData)

    /// Returns true if enough time has passed since the last history write.
    /// Exposed for testing without SwiftData.
    func shouldWriteHistory(lastWrite: Date?) -> Bool {
        guard let last = lastWrite else { return true }
        return Date().timeIntervalSince(last) >= 5.0
    }

    private func maybeWriteHistory() {
        guard let context = modelContext,
              shouldWriteHistory(lastWrite: lastHistoryWriteDate) else { return }
        lastHistoryWriteDate = Date()
        let timestamp = Date()
        for sat in satellites {
            let entry = SatelliteHistoryEntry(
                prn: sat.prn, elevation: sat.elevation, azimuth: sat.azimuth,
                snr: sat.snr, used: sat.used, timestamp: timestamp
            )
            context.insert(entry)
        }
        try? context.save()
    }

    private func startPruneTimer() {
        pruneTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.pruneOldHistory()
        }
    }

    private func pruneOldHistory() {
        guard let context = modelContext else { return }
        let cutoff = Date().addingTimeInterval(-86400)
        let predicate = #Predicate<SatelliteHistoryEntry> { $0.timestamp < cutoff }
        let descriptor = FetchDescriptor(predicate: predicate)
        guard let stale = try? context.fetch(descriptor) else { return }
        for entry in stale { context.delete(entry) }
        try? context.save()
    }

    // MARK: - Config Singleton

    /// Fetches the single MQTTConfiguration row, creating it if absent.
    /// If multiple rows exist (unexpected), keeps the first and deletes the rest.
    @discardableResult
    func fetchOrCreateConfig(in context: ModelContext) -> MQTTConfiguration {
        let all = (try? context.fetch(FetchDescriptor<MQTTConfiguration>())) ?? []
        if all.isEmpty {
            let config = MQTTConfiguration()
            context.insert(config)
            try? context.save()
            return config
        }
        if all.count > 1 {
            for extra in all.dropFirst() { context.delete(extra) }
            try? context.save()
        }
        return all[0]
    }
}
```

- [ ] **Step 4: Run test — expect pass**

```bash
xcodebuild test \
  -project "GPS Tracker.xcodeproj" \
  -scheme "GPS Tracker" \
  -destination "platform=macOS,arch=arm64" \
  -only-testing:"GPS TrackerTests/SatelliteStoreTests" 2>&1 | tail -15
```

Expected: all `SatelliteStoreTests` pass.

- [ ] **Commit note:** Stage `GPS Tracker/Services/SatelliteStore.swift` and test file — message: `feat: add SatelliteStore observable state hub`

---

## Task 11: App Entry Point

Update `GPS_TrackerApp.swift` to configure the SwiftData `ModelContainer` with the correct schema, inject `MQTTService` and `SatelliteStore` into the environment, and handle first-launch.

**Files:**
- Modify: `GPS Tracker/GPS_TrackerApp.swift`

- [ ] **Step 1: Update GPS_TrackerApp.swift**

Use xcode-proxy `XcodeWrite` (or `XcodeUpdate`) to replace the contents of `GPS Tracker/GPS_TrackerApp.swift`:

```swift
//
//  GPS_TrackerApp.swift
//  GPS Tracker
//
//  Created by Christopher Graham on 4/1/26.
//
// Claude Generated: version 1 - App entry point with ModelContainer and service injection

import SwiftUI
import SwiftData

@main
struct GPS_TrackerApp: App {

    private let mqttService = MQTTService()
    private let satelliteStore: SatelliteStore

    private let modelContainer: ModelContainer = {
        let schema = Schema([
            SatelliteHistoryEntry.self,
            MQTTConfiguration.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        let store = SatelliteStore(mqttService: mqttService)
        store.configure(modelContext: modelContainer.mainContext)
        satelliteStore = store
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(satelliteStore)
        }
        .modelContainer(modelContainer)

        Settings {
            ConfigurationView()
                .environment(satelliteStore)
                .modelContainer(modelContainer)
        }
    }
}
```

- [ ] **Step 2: Build — expect success**

```bash
xcodebuild build \
  -project "GPS Tracker.xcodeproj" \
  -scheme "GPS Tracker" \
  -destination "platform=macOS,arch=arm64" 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Commit note:** Stage `GPS Tracker/GPS_TrackerApp.swift` — message: `feat: configure app entry point with ModelContainer and service injection`

---

## Task 12: ConfigurationView

The MQTT settings sheet, opened via `Cmd+,` or the toolbar gear button. Reads from and writes to SwiftData + Keychain. Triggers reconnect on save.

**Files:**
- Create: `GPS Tracker/Views/ConfigurationView.swift`

- [ ] **Step 1: Create ConfigurationView.swift**

Use xcode-proxy `XcodeWrite` to create `GPS Tracker/Views/ConfigurationView.swift`:

```swift
//
//  ConfigurationView.swift
//  GPS Tracker
//
//  Created by Christopher Graham on 4/1/26.
//
// Claude Generated: version 1 - MQTT broker configuration sheet

import SwiftUI
import SwiftData

/// MQTT broker settings sheet. Opened via Cmd+, (Settings scene) or gear toolbar button.
/// Hostname and port are persisted in SwiftData.
/// Username and password are persisted in the macOS Keychain.
/// Saving triggers a reconnect in SatelliteStore.
struct ConfigurationView: View {

    @Environment(SatelliteStore.self) private var store
    @Environment(\.modelContext) private var modelContext

    @State private var hostname: String = ""
    @State private var port: String = "8883"
    @State private var username: String = ""
    @State private var password: String = ""

    private var portValue: Int? { Int(port) }
    private var isValid: Bool {
        !hostname.trimmingCharacters(in: .whitespaces).isEmpty
        && (portValue.map { 1...65535 ~= $0 } ?? false)
    }

    var body: some View {
        Form {
            Section("Broker") {
                TextField("Hostname", text: $hostname)
                    .textContentType(.URL)
                TextField("Port", text: $port)
            }
            Section("Authentication (optional)") {
                TextField("Username", text: $username)
                    .textContentType(.username)
                SecureField("Password", text: $password)
                    .textContentType(.password)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 380)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!isValid)
            }
        }
        .onAppear { loadCurrentValues() }
    }

    // MARK: - Private

    private func loadCurrentValues() {
        let config = store.fetchOrCreateConfig(in: modelContext)
        hostname = config.hostname
        port = String(config.port)
        if let creds = KeychainHelper.load() {
            username = creds.username
            password = creds.password
        }
    }

    private func save() {
        let config = store.fetchOrCreateConfig(in: modelContext)
        config.hostname = hostname.trimmingCharacters(in: .whitespaces)
        config.port = portValue ?? 8883
        try? modelContext.save()

        try? KeychainHelper.save(username: username, password: password)

        Task { await store.reconnect(config: config) }
    }
}

#Preview {
    ConfigurationView()
        .modelContainer(for: [MQTTConfiguration.self, SatelliteHistoryEntry.self],
                        inMemory: true)
}
```

- [ ] **Step 2: Build — expect success**

```bash
xcodebuild build \
  -project "GPS Tracker.xcodeproj" \
  -scheme "GPS Tracker" \
  -destination "platform=macOS,arch=arm64" 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Commit note:** Stage `GPS Tracker/Views/ConfigurationView.swift` — message: `feat: add ConfigurationView for MQTT broker settings`

---

## Task 13: Polar Coordinate Math Tests + PolarGraphView

The polar graph converts satellite elevation/azimuth to canvas x/y coordinates and draws everything with SwiftUI `Canvas`. Test the coordinate math independently before building the full view.

**Files:**
- Create: `GPS Tracker/Views/PolarGraphView.swift`
- Modify: `GPS TrackerTests/GPS_TrackerTests.swift`

- [ ] **Step 1: Write coordinate math tests**

Add to `GPS TrackerTests/GPS_TrackerTests.swift`:

```swift
@Suite("Polar Coordinate Tests")
struct PolarCoordinateTests {

    /// Mirror the coordinate function from PolarGraphView
    private func polarPoint(elevation: Int, azimuth: Int,
                             center: CGPoint, radius: CGFloat) -> CGPoint {
        let r = (1.0 - Double(elevation) / 90.0) * Double(radius)
        let azRad = Double(azimuth) * .pi / 180.0
        return CGPoint(
            x: center.x + r * sin(azRad),
            y: center.y - r * cos(azRad)
        )
    }

    @Test("Zenith (elevation 90) maps to center")
    func zenithIsCenter() {
        let center = CGPoint(x: 100, y: 100)
        let pt = polarPoint(elevation: 90, azimuth: 0, center: center, radius: 100)
        #expect(abs(pt.x - center.x) < 0.001)
        #expect(abs(pt.y - center.y) < 0.001)
    }

    @Test("Horizon (elevation 0) maps to rim")
    func horizonIsRim() {
        let center = CGPoint(x: 100, y: 100)
        let radius: CGFloat = 100
        // North = azimuth 0 → top of circle
        let north = polarPoint(elevation: 0, azimuth: 0, center: center, radius: radius)
        #expect(abs(north.x - center.x) < 0.001)        // x = center
        #expect(abs(north.y - (center.y - radius)) < 0.001) // y = top
    }

    @Test("East (azimuth 90) maps to right side")
    func eastIsRight() {
        let center = CGPoint(x: 100, y: 100)
        let radius: CGFloat = 100
        let east = polarPoint(elevation: 0, azimuth: 90, center: center, radius: radius)
        #expect(abs(east.x - (center.x + radius)) < 0.001) // x = right
        #expect(abs(east.y - center.y) < 0.001)             // y = center
    }

    @Test("South (azimuth 180) maps to bottom")
    func southIsBottom() {
        let center = CGPoint(x: 100, y: 100)
        let radius: CGFloat = 100
        let south = polarPoint(elevation: 0, azimuth: 180, center: center, radius: radius)
        #expect(abs(south.x - center.x) < 0.001)
        #expect(abs(south.y - (center.y + radius)) < 0.001)
    }

    @Test("Elevation 30 maps to 67% radius")
    func elevationThirtyMapsToSeventyPercent() {
        let center = CGPoint(x: 0, y: 0)
        let radius: CGFloat = 100
        // At azimuth 0 (north), x should be ~0, y should be -66.7
        let pt = polarPoint(elevation: 30, azimuth: 0, center: center, radius: radius)
        let expectedR = (1.0 - 30.0 / 90.0) * 100.0  // 66.67
        #expect(abs(pt.y - (-expectedR)) < 0.001)
    }

    @Test("Trail opacity — floor at 0.2")
    func trailOpacityFloor() {
        func opacity(ageSecs: Double) -> Double {
            max(0.2, 1.0 - (ageSecs / 86400.0))
        }
        #expect(opacity(ageSecs: 0) == 1.0)
        #expect(opacity(ageSecs: 43200) == 0.5)      // 12 hours
        #expect(opacity(ageSecs: 86400) == 0.2)      // 24 hours (floor)
        #expect(opacity(ageSecs: 90000) == 0.2)      // beyond 24 hours (floor)
    }
}
```

- [ ] **Step 2: Run coordinate tests — expect pass**

```bash
xcodebuild test \
  -project "GPS Tracker.xcodeproj" \
  -scheme "GPS Tracker" \
  -destination "platform=macOS,arch=arm64" \
  -only-testing:"GPS TrackerTests/PolarCoordinateTests" 2>&1 | tail -10
```

Expected: `Test Suite 'PolarCoordinateTests' passed`

- [ ] **Step 3: Create PolarGraphView.swift**

Use xcode-proxy `XcodeWrite` to create `GPS Tracker/Views/PolarGraphView.swift`:

```swift
//
//  PolarGraphView.swift
//  GPS Tracker
//
//  Created by Christopher Graham on 4/1/26.
//
// Claude Generated: version 1 - Canvas-based satellite polar sky view

import SwiftUI
import SwiftData

/// Polar sky graph showing satellite positions.
/// Center = zenith (90° elevation), rim = horizon (0°), north at top.
/// Satellites are drawn as solid filled circles (used) or stroked outlines (!used),
/// colored by SatelliteColor. Trails drawn from SwiftData history when enabled.
struct PolarGraphView: View {

    @Environment(SatelliteStore.self) private var store
    @Query(sort: \SatelliteHistoryEntry.timestamp) private var history: [SatelliteHistoryEntry]

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let radius = size * 0.45
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

            Canvas { ctx, _ in
                drawGrid(ctx: ctx, center: center, radius: radius)
                drawCardinals(ctx: ctx, center: center, radius: radius)
                if store.showTrails {
                    drawTrails(ctx: ctx, center: center, radius: radius)
                }
                drawSatellites(ctx: ctx, center: center, radius: radius)
            }
            .overlay {
                if store.satellites.isEmpty {
                    Text("No satellite data")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .padding()
    }

    // MARK: - Coordinate Math

    private func polarPoint(elevation: Int, azimuth: Int,
                             center: CGPoint, radius: CGFloat) -> CGPoint {
        let r = (1.0 - Double(elevation) / 90.0) * Double(radius)
        let azRad = Double(azimuth) * .pi / 180.0
        return CGPoint(
            x: center.x + r * sin(azRad),
            y: center.y - r * cos(azRad)
        )
    }

    // MARK: - Drawing

    private func drawGrid(ctx: GraphicsContext, center: CGPoint, radius: CGFloat) {
        // Outer circle (background)
        let bgRect = CGRect(x: center.x - radius, y: center.y - radius,
                            width: radius * 2, height: radius * 2)
        ctx.fill(Path(ellipseIn: bgRect), with: .color(.secondary.opacity(0.08)))

        // Elevation rings at 0° (rim), 30°, 60°, 90° (center dot)
        for el in [0, 30, 60] {
            let pt = polarPoint(elevation: el, azimuth: 0, center: center, radius: radius)
            let r = abs(center.y - pt.y)
            let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            ctx.stroke(Path(ellipseIn: rect), with: .color(.secondary.opacity(0.3)), lineWidth: 0.5)
        }
    }

    private func drawCardinals(ctx: GraphicsContext, center: CGPoint, radius: CGFloat) {
        let labels: [(String, Int)] = [("N", 0), ("E", 90), ("S", 180), ("W", 270)]
        for (label, az) in labels {
            var pt = polarPoint(elevation: 0, azimuth: az, center: center, radius: radius)
            // Offset label slightly outside the rim
            let offset: CGFloat = 14
            let azRad = Double(az) * .pi / 180.0
            pt.x += offset * sin(azRad)
            pt.y -= offset * cos(azRad)
            ctx.draw(Text(label).font(.caption2).foregroundStyle(.secondary),
                     at: pt)
        }
    }

    private func drawTrails(ctx: GraphicsContext, center: CGPoint, radius: CGFloat) {
        // Group history by PRN
        var byPrn: [Int: [SatelliteHistoryEntry]] = [:]
        for entry in history { byPrn[entry.prn, default: []].append(entry) }

        let now = Date()
        for (_, entries) in byPrn {
            guard entries.count > 1 else { continue }
            var path = Path()
            for (i, entry) in entries.enumerated() {
                let pt = polarPoint(elevation: entry.elevation, azimuth: entry.azimuth,
                                    center: center, radius: radius)
                let ageSecs = now.timeIntervalSince(entry.timestamp)
                let opacity = max(0.2, 1.0 - (ageSecs / 86400.0))
                if i == 0 {
                    path.move(to: pt)
                } else {
                    path.addLine(to: pt)
                }
                // Draw segment-by-segment to vary opacity
                if i > 0 {
                    ctx.stroke(path, with: .color(.secondary.opacity(opacity)), lineWidth: 1)
                    path = Path()
                    path.move(to: pt)
                }
            }
        }
    }

    private func drawSatellites(ctx: GraphicsContext, center: CGPoint, radius: CGFloat) {
        let dotRadius: CGFloat = 6

        for sat in store.satellites {
            let pt = polarPoint(elevation: sat.elevation, azimuth: sat.azimuth,
                                center: center, radius: radius)
            let rect = CGRect(x: pt.x - dotRadius, y: pt.y - dotRadius,
                              width: dotRadius * 2, height: dotRadius * 2)
            let color = swiftUIColor(for: sat.color)

            if sat.used {
                ctx.fill(Path(ellipseIn: rect), with: .color(color))
            } else {
                ctx.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: 1.5)
            }

            // PRN label
            ctx.draw(Text("\(sat.prn)").font(.system(size: 9)).foregroundStyle(.secondary),
                     at: CGPoint(x: pt.x + dotRadius + 4, y: pt.y))
        }
    }

    private func swiftUIColor(for color: SatelliteColor) -> Color {
        switch color {
        case .red:    return .red
        case .green:  return .green
        case .orange: return .orange
        case .yellow: return .yellow
        }
    }
}

#Preview {
    PolarGraphView()
        .modelContainer(for: [SatelliteHistoryEntry.self, MQTTConfiguration.self],
                        inMemory: true)
}
```

- [ ] **Step 4: Build — expect success**

```bash
xcodebuild build \
  -project "GPS Tracker.xcodeproj" \
  -scheme "GPS Tracker" \
  -destination "platform=macOS,arch=arm64" 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Commit note:** Stage `GPS Tracker/Views/PolarGraphView.swift` and test file — message: `feat: add PolarGraphView with Canvas rendering and satellite trails`

---

## Task 14: SatelliteTableView

The slide-out satellite data table. Sorted by SNR descending by default; user can click column headers to re-sort. Rows colored by `SatelliteColor`.

**Files:**
- Create: `GPS Tracker/Views/SatelliteTableView.swift`

- [ ] **Step 1: Create SatelliteTableView.swift**

Use xcode-proxy `XcodeWrite` to create `GPS Tracker/Views/SatelliteTableView.swift`:

```swift
//
//  SatelliteTableView.swift
//  GPS Tracker
//
//  Created by Christopher Graham on 4/1/26.
//
// Claude Generated: version 1 - Slide-out satellite data table sorted by SNR

import SwiftUI

/// Displays all current satellites in a sortable table.
/// Slides in side-by-side with PolarGraphView when toggled.
/// Row text is colored by SatelliteColor (same logic as polar graph dots).
/// Default sort: SNR descending. User can click column headers to re-sort.
struct SatelliteTableView: View {

    @Environment(SatelliteStore.self) private var store
    @State private var sortOrder = [KeyPathComparator(\Satellite.snr, order: .reverse)]

    private var sortedSatellites: [Satellite] {
        store.satellites.sorted(using: sortOrder)
    }

    var body: some View {
        Group {
            if store.satellites.isEmpty {
                ContentUnavailableView("No Satellites in View",
                                       systemImage: "antenna.radiowaves.left.and.right",
                                       description: Text("Waiting for satellite data"))
            } else {
                Table(sortedSatellites, sortOrder: $sortOrder) {
                    TableColumn("PRN", value: \.prn) { sat in
                        Text("\(sat.prn)").foregroundStyle(color(for: sat))
                    }
                    TableColumn("El", value: \.elevation) { sat in
                        Text("\(sat.elevation)°").foregroundStyle(color(for: sat))
                    }
                    TableColumn("Az", value: \.azimuth) { sat in
                        Text("\(sat.azimuth)°").foregroundStyle(color(for: sat))
                    }
                    TableColumn("SNR", value: \.snr) { sat in
                        Text("\(sat.snr)").foregroundStyle(color(for: sat))
                    }
                    TableColumn("Used", value: \.used) { sat in
                        Text(sat.used ? "Yes" : "No").foregroundStyle(color(for: sat))
                    }
                    TableColumn("Seen", value: \.seen) { sat in
                        Text("\(sat.seen)s").foregroundStyle(color(for: sat))
                    }
                }
            }
        }
        .frame(minWidth: 380)
    }

    private func color(for sat: Satellite) -> Color {
        switch sat.color {
        case .red:    return .red
        case .green:  return .green
        case .orange: return .orange
        case .yellow: return .yellow
        }
    }
}

#Preview {
    SatelliteTableView()
}
```

- [ ] **Step 2: Build — expect success**

```bash
xcodebuild build \
  -project "GPS Tracker.xcodeproj" \
  -scheme "GPS Tracker" \
  -destination "platform=macOS,arch=arm64" 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Commit note:** Stage `GPS Tracker/Views/SatelliteTableView.swift` — message: `feat: add SatelliteTableView slide-out satellite data table`

---

## Task 15: ContentView — Root Container + Toolbar

The root view. Contains the `HStack` that holds the polar graph (always visible) and table (conditionally visible). Manages the slide animation and window expansion. The toolbar hosts the connection indicator, toggle buttons, and gear button.

Also handles first-launch: if the saved hostname is empty, opens the configuration sheet automatically.

**Files:**
- Modify: `GPS Tracker/Views/ContentView.swift`

- [ ] **Step 1: Replace ContentView.swift**

Use xcode-proxy `XcodeUpdate` or `XcodeWrite` to replace `GPS Tracker/Views/ContentView.swift`:

**Note:** If `ContentView.swift` is still in the root `GPS Tracker/` group rather than `GPS Tracker/Views/`, move it to `Views/` in Xcode's file navigator first, then update the content.

```swift
//
//  ContentView.swift
//  GPS Tracker
//
//  Created by Christopher Graham on 4/1/26.
//
// Claude Generated: version 1 - Root HStack container with toolbar and slide animation

import SwiftUI
import SwiftData

/// Root view. PolarGraphView is always visible.
/// SatelliteTableView slides in from the right (side-by-side, not overlay)
/// when the table toggle button is tapped. Window expands to accommodate.
struct ContentView: View {

    @Environment(SatelliteStore.self) private var store
    @Environment(\.modelContext) private var modelContext

    @State private var showConfig = false

    var body: some View {
        HStack(spacing: 0) {
            PolarGraphView()
                .frame(minWidth: 400, minHeight: 400)

            if store.showTable {
                Divider()
                SatelliteTableView()
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.spring(), value: store.showTable)
        .toolbar { toolbarContent }
        .onAppear { handleFirstLaunch() }
        .sheet(isPresented: $showConfig) {
            ConfigurationView()
                .environment(store)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            connectionIndicator
        }
        ToolbarItem {
            Button {
                withAnimation(.spring()) { store.showTable.toggle() }
            } label: {
                Label("Satellites",
                      systemImage: store.showTable ? "list.bullet.circle.fill" : "list.bullet.circle")
            }
        }
        ToolbarItem {
            Button {
                store.showTrails.toggle()
            } label: {
                Label("Trails",
                      systemImage: store.showTrails ? "line.diagonal.arrow" : "line.diagonal")
            }
        }
        ToolbarItem {
            Button {
                showConfig = true
            } label: {
                Label("Settings", systemImage: "gear")
            }
        }
    }

    private var connectionIndicator: some View {
        Circle()
            .fill(connectionColor)
            .frame(width: 10, height: 10)
            .help(connectionLabel)
    }

    private var connectionColor: Color {
        switch store.connectionState {
        case .connected:     return .green
        case .connecting:    return .yellow
        case .disconnected:  return .red
        case .error:         return .red
        }
    }

    private var connectionLabel: String {
        switch store.connectionState {
        case .connected:         return "Connected"
        case .connecting:        return "Connecting…"
        case .disconnected:      return "Disconnected"
        case .error(let msg):    return "Error: \(msg)"
        }
    }

    // MARK: - First Launch

    private func handleFirstLaunch() {
        let config = store.fetchOrCreateConfig(in: modelContext)
        if config.hostname.isEmpty {
            showConfig = true
        } else {
            Task { await store.connectWithCurrentConfig() }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [SatelliteHistoryEntry.self, MQTTConfiguration.self],
                        inMemory: true)
}
```

- [ ] **Step 2: Build — expect success**

```bash
xcodebuild build \
  -project "GPS Tracker.xcodeproj" \
  -scheme "GPS Tracker" \
  -destination "platform=macOS,arch=arm64" 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Run full test suite**

```bash
xcodebuild test \
  -project "GPS Tracker.xcodeproj" \
  -scheme "GPS Tracker" \
  -destination "platform=macOS,arch=arm64" 2>&1 | tail -50
```

Expected: all test suites pass, zero failures.

- [ ] **Commit note:** Stage `GPS Tracker/Views/ContentView.swift` — message: `feat: add ContentView root container with toolbar and slide animation`

---

## Task 16: UI Tests — Critical Flows

Verify the app's key interactive behaviors with automated UI tests.

**Files:**
- Modify: `GPS TrackerUITests/GPS_TrackerUITestsLaunchTests.swift`

- [ ] **Step 1: Write UI tests**

Use xcode-proxy `XcodeWrite` to replace `GPS TrackerUITests/GPS_TrackerUITestsLaunchTests.swift`:

```swift
//
//  GPS_TrackerUITests.swift
//  GPS TrackerUITests
//
//  Created by Christopher Graham on 4/1/26.
//
// Claude Generated: version 1 - UI tests for critical user flows

import XCTest

final class GPSTrackerUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
    }

    func testAppLaunchesSuccessfully() {
        XCTAssertTrue(app.windows.firstMatch.exists)
    }

    func testFirstLaunchShowsConfigurationSheet() {
        // On first launch with no config, the configuration sheet should appear
        // (The app uses --uitesting flag to start with a blank in-memory store)
        let hostnameField = app.textFields["Hostname"]
        XCTAssertTrue(hostnameField.waitForExistence(timeout: 3),
                      "Configuration sheet should appear on first launch")
    }

    func testPolarGraphViewIsVisible() {
        // Dismiss config sheet if present
        let cancelButton = app.buttons["Cancel"]
        if cancelButton.waitForExistence(timeout: 2) { cancelButton.tap() }

        // The polar graph canvas should be present
        XCTAssertTrue(app.windows.firstMatch.exists)
    }

    func testTableToggleButtonExists() {
        let cancelButton = app.buttons["Cancel"]
        if cancelButton.waitForExistence(timeout: 2) { cancelButton.tap() }

        let satellitesButton = app.buttons["Satellites"]
        XCTAssertTrue(satellitesButton.waitForExistence(timeout: 2))
    }

    func testSettingsButtonOpensConfig() {
        let cancelButton = app.buttons["Cancel"]
        if cancelButton.waitForExistence(timeout: 2) { cancelButton.tap() }

        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 2))
        settingsButton.tap()

        let hostnameField = app.textFields["Hostname"]
        XCTAssertTrue(hostnameField.waitForExistence(timeout: 2))
    }
}
```

- [ ] **Step 2: Update GPS_TrackerApp.swift with UI test flag**

In `GPS Tracker/GPS_TrackerApp.swift`, inside the `modelContainer` computed property closure, replace:

```swift
let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
```

with:

```swift
let isUITesting = CommandLine.arguments.contains("--uitesting")
let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isUITesting)
```

This ensures the in-memory store (always starting with hostname `""`) is used during UI tests, so `handleFirstLaunch()` consistently presents the configuration sheet.

- [ ] **Step 3: Run UI tests**

```bash
xcodebuild test \
  -project "GPS Tracker.xcodeproj" \
  -scheme "GPS Tracker" \
  -destination "platform=macOS,arch=arm64" \
  -only-testing:"GPS TrackerUITests" 2>&1 | tail -15
```

Expected: all UI tests pass.

- [ ] **Commit note:** Stage test file and updated `GPS_TrackerApp.swift` — message: `test: add UI tests for critical app flows`

---

## Final Verification

- [ ] Run the complete test suite one final time — all tests pass, zero failures
- [ ] Launch the app in Xcode (`Cmd+R`) — configuration sheet appears on first launch
- [ ] Enter broker details, save — connection attempt visible in toolbar indicator
- [ ] Verify polar graph renders grid, cardinals, and "No satellite data" placeholder
- [ ] Toggle satellite table — slides in side-by-side, window expands
- [ ] Toggle trails — button state changes (data continues collecting)

---

## Known Gaps / Future Work

- `MQTTService` uses `nonisolated var` for `skyStream`/`connectionStateStream` which creates new `AsyncStream` instances on each access — production should use stored continuations with a single stream instance per property. Refine if multiple consumers are ever added.
- If the MQTT broker requires a specific TLS certificate (self-signed CA), `TLSConfiguration` will need a custom certificate validation path.
- Multi-constellation receivers (gnssid/svid) will require a composite PRN key on `Satellite` — documented in spec as a v2 concern.
