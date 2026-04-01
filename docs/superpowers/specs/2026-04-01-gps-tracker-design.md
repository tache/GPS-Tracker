# GPS Tracker — Design Specification

**Date:** 2026-04-01
**Platform:** macOS 15+
**Technologies:** Swift 5.10+, SwiftUI, SwiftData (local), Swift Testing, MQTT NIO 2.x

---

## Overview

GPS Tracker is a macOS desktop application that displays a real-time satellite sky view sourced from a GPSD-to-MQTT bridge. The primary screen is a polar graph showing satellite positions across the sky dome. A satellite data table slides in alongside the graph on demand. Data is received over an MQTT connection (TLS, port 8883) and historical satellite positions are stored locally for trail rendering.

---

## Scope (v1)

- Satellite polar graph (sky view)
- Satellite data table (slide-out, side-by-side)
- MQTT connection to `gps_monitor/sky` and `gps_monitor/availability` topics
- Satellite trail history (24-hour rolling window, SwiftData)
- Configuration sheet (MQTT broker settings)
- Dark and light mode support

**Explicitly out of scope for v1:** TPV data (fix quality, position, lat/lon, altitude), CloudKit sync.

---

## Package Dependencies

| Package | URL | Version |
|---------|-----|---------|
| mqtt-nio | https://github.com/swift-server-community/mqtt-nio.git | from: "2.0.0" (2.x, up to next major) |

No other third-party packages. All UI and data layers use Apple frameworks only.

**Note:** SPM resolves `from: "2.0.0"` to the latest 2.x release. The `Package.resolved` lock file must be committed so all builds use the same resolved version. The lock file is the effective version pin.

---

## Architecture

Four distinct layers:

```
GPS_TrackerApp
└── ContentView (HStack)
    ├── PolarGraphView          ← always visible
    └── SatelliteTableView      ← slides in/out with spring animation

MQTTService (actor)
└── AsyncStream<SkyMessage> → SatelliteStore (@Observable)
                                └── SwiftData (SatelliteHistoryEntry, MQTTConfiguration)
```

### MQTT Layer
`MQTTService` is a Swift `actor` that owns the `mqtt-nio` client. It connects to the broker, subscribes to topics, parses JSON payloads into typed Swift structs, and emits `SkyMessage` values via an `AsyncStream`. It handles reconnection automatically with exponential backoff (capped at 60 seconds). The actor exposes its `connectionState` changes by also yielding into a separate `AsyncStream<ConnectionState>` that `SatelliteStore` mirrors into an `@Observable` property for the view layer.

### State Layer
`SatelliteStore` is an `@Observable` class. It:
- Consumes `MQTTService.skyStream` in a `for await` loop, updating `satellites: [Satellite]`
- Mirrors `MQTTService.connectionStateStream` into its own `connectionState` property for views to observe
- Writes history to SwiftData on each message (throttled — see Persistence section)
- Handles pruning of history older than 24 hours

### Persistence Layer
SwiftData, local only, no CloudKit. Two models: `SatelliteHistoryEntry` for trail data, `MQTTConfiguration` for non-sensitive broker settings. MQTT credentials (username, password) are stored in the macOS Keychain.

### View Layer
A root `ContentView` contains an `HStack` with `PolarGraphView` always present. `SatelliteTableView` is conditionally included and animated with `.transition(.move(edge: .trailing))`. A toolbar button toggles the table; a gear icon (or `Cmd+,`) opens the configuration sheet.

---

## Data Models

### `Satellite` (in-memory struct)

The target hardware (MTK-3301) is GPS-only and does not emit `gnssid` or `svid`. For v1, PRN is treated as unique. If multi-constellation hardware is added in a future version, the `id` must change to a composite key.

```swift
struct Satellite: Identifiable {
    let prn: Int
    let elevation: Int      // degrees above horizon (0–90)
    let azimuth: Int        // degrees, true north (0–359)
    let snr: Int            // signal-to-noise ratio, dBHz (mapped from ss field)
    let used: Bool          // contributing to current fix
    let seen: Int           // seconds since first seen this GPSD session
    var id: Int { prn }

    var color: SatelliteColor {
        guard used else { return .red }
        if snr >= 35 { return .green }
        if snr >= 20 { return .orange }
        return .yellow
    }
}
```

### `SatelliteColor` (enum)

| Condition | Color | Visual |
|-----------|-------|--------|
| `!used` | `.red` | Stroked outline circle |
| `used && snr >= 35` | `.green` | Solid filled circle |
| `used && snr >= 20` | `.orange` | Solid filled circle |
| `used && snr < 20` | `.yellow` | Solid filled circle |

### `SkyMessage` (Codable)

Maps to the `gps_monitor/sky` JSON payload. All DOP fields are optional (nullable in the MQTT spec). The `nsat` and `usat` fields from the wire format are intentionally omitted in v1 — the app uses `satUsed`/`satVisible` instead, which carry the same information.

```swift
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

// All property names match their JSON keys exactly, so no CodingKeys enum is needed.
// The `ss` property retains the JSON name; the mapping to `snr` on Satellite happens
// explicitly in SatelliteStore when constructing Satellite from SkyMessageSatellite:
//   Satellite(prn: s.prn, elevation: s.el, azimuth: s.az, snr: s.ss, ...)
struct SkyMessageSatellite: Codable {
    let prn: Int
    let el: Int
    let az: Int
    let ss: Int        // JSON key "ss" = signal strength (dBHz); becomes Satellite.snr
    let used: Bool
    let seen: Int
    let gnssid: Int?   // optional, not emitted by MTK-3301
    let svid: Int?     // optional, not emitted by MTK-3301
}
```

### `SatelliteHistoryEntry` (SwiftData `@Model`)

```swift
@Model class SatelliteHistoryEntry {
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

**`seen` not stored:** The `seen` field (seconds since first seen this GPSD session) is intentionally excluded from `SatelliteHistoryEntry`. It is a live-session counter from GPSD and is not meaningful as historical data. The `Seen` column in the satellite table is populated from the live `satellites: [Satellite]` array only.

**Pruning:** `SatelliteStore` prunes stale entries once per minute via a `Timer` on a background context. Predicate: `timestamp < Date.now - 86400`. This is separate from the write path to avoid write contention.

**Write throttling:** History is written at most once every 5 seconds, not on every MQTT message. `SatelliteStore` tracks the last write timestamp and skips writes if fewer than 5 seconds have elapsed. At 14 satellites and a 5-second floor, the maximum write rate is 14 rows per 5 seconds — acceptable for SwiftData.

### `MQTTConfiguration` (SwiftData `@Model`)

```swift
@Model class MQTTConfiguration {
    var hostname: String
    var port: Int       // default: 8883
    // username + password stored in macOS Keychain

    init(hostname: String = "", port: Int = 8883) {
        self.hostname = hostname
        self.port = port
    }
}
```

**Singleton enforcement:** On app launch, `SatelliteStore` fetches all `MQTTConfiguration` rows. If none exist, it inserts a new default row (`hostname: ""`, `port: 8883`). If more than one exists (unexpected), it deletes extras and keeps the first. This `fetchOrCreate` logic runs once at startup. `ConfigurationView` always reads and writes the single existing row.

---

## MQTT Service

### `ConnectionState` (top-level enum)

`ConnectionState` is defined at the top level (not nested inside `MQTTService`) so that `MQTTServiceProtocol`, `MQTTService`, and `SatelliteStore` can all reference it without circular dependencies.

```swift
enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)
}
```

### Interface

```swift
actor MQTTService: MQTTServiceProtocol {
    func connect(config: MQTTConfiguration, username: String, password: String) async throws
    func disconnect() async
    var skyStream: AsyncStream<SkyMessage> { get }
    var connectionStateStream: AsyncStream<ConnectionState> { get }
}
```

### Behavior

- **Transport:** TLS on port 8883 via NIOSSL. No client certificate — username/password auth.
- **Anonymous connection:** If username is empty string, connect with no credentials (MQTT anonymous mode). If username is non-empty, send username + password in the CONNECT packet.
- **Topics subscribed:** `gps_monitor/sky`, `gps_monitor/availability`
- **`gps_monitor/availability` handling:** When payload is `"offline"`, the actor yields `.error("GPS bridge offline")` to `connectionStateStream`. When payload is `"online"`, no state change — the TCP connection being alive already implies connected.
- **Reconnection:** On unexpected disconnect, retry with exponential backoff: 1s, 2s, 4s, 8s… capped at 60s. Each attempt yields `.connecting` to `connectionStateStream`.
- **Config change:** `SatelliteStore` calls `disconnect()` then `connect(config:username:password:)` when settings are saved.

### State Observability

`MQTTService` is an `actor` and cannot be `@Observable`. `SatelliteStore` (which is `@Observable`) runs a separate `Task` that iterates `connectionStateStream` and writes the value to its own `var connectionState: ConnectionState`. Views observe `SatelliteStore.connectionState` — never the actor directly.

---

## Keychain Helper

```swift
enum KeychainHelper {
    static func save(username: String, password: String) throws
    static func load() -> (username: String, password: String)?
    static func delete()
}
```

Uses `SecItemAdd` / `SecItemCopyMatching` / `SecItemDelete` with service name `"com.gps-tracker.mqtt-credentials"`. `ConfigurationView` calls `load()` on appear and `save(username:password:)` on save. `MQTTService.connect` receives credentials as parameters — it does not read the Keychain directly.

---

## Polar Graph View

Drawn with SwiftUI `Canvas` for full 2D control and efficient real-time updates.

### Coordinate Math

```
r = (1.0 - elevation / 90.0) * radius   // horizon = outer edge, zenith = center
x = centerX + r * sin(azimuth_radians)
y = centerY - r * cos(azimuth_radians)   // north at top
```

### Draw Order

1. Background circle fill
2. Concentric elevation rings at 0°, 30°, 60°, 90° (subtle grid lines)
3. Cardinal direction labels: N, S, E, W at rim
4. Azimuth tick marks every 45°
5. Satellite trails (when enabled): per-PRN `Path` from SwiftData history, with opacity floor
6. Satellite dots: solid filled circle if `used`, stroked outline if `!used`, colored by `SatelliteColor`
7. PRN labels: small text adjacent to each dot

### Trails

- Loaded from SwiftData grouped by PRN, sorted by timestamp ascending
- Drawn as a `Path` connecting historical positions using the same coordinate math
- Opacity formula: `max(0.2, 1.0 - (age_seconds / 86400.0))` — floor of 0.2 so oldest segments remain visible
- Toggled on/off via toolbar button; trail data is always collected regardless of toggle state

### Performance

`Canvas` redraws only when `SatelliteStore` publishes a change (typically every 1–5 seconds per GPSD cycle). No continuous animation loop.

### Empty State

When no satellites are present (e.g., no MQTT connection yet), the polar graph draws the grid and labels only, with a centered text overlay: `"No satellite data"`.

### Appearance

All grid lines, labels, and backgrounds use semantic `Color` values — dark and light mode adapt automatically.

---

## Satellite Table View

### Slide Behavior

```swift
HStack(spacing: 0) {
    PolarGraphView()
        .frame(minWidth: 400)
    if showTable {
        SatelliteTableView()
            .frame(minWidth: 380)
            .transition(.move(edge: .trailing))
    }
}
.animation(.spring(), value: showTable)
```

**Window sizing:** The window has a minimum width of 400pt (graph only) and expands to at least 780pt when the table is shown. The `windowResizability(.contentSize)` modifier allows the window to grow with its content. The window is not constrained to a maximum width — the user may resize freely.

### Table

SwiftUI native `Table` (macOS-native). Columns:

| Column | Field | Notes |
|--------|-------|-------|
| PRN | `prn` | Satellite ID |
| El | `elevation` | Degrees above horizon |
| Az | `azimuth` | Degrees, true north |
| SNR | `snr` | dBHz |
| Used | `used` | "Yes" / "No" |
| Seen | `seen` | Displayed as `{n}s` |

- **Default sort:** Descending SNR
- **Column header click:** Re-sorts the table
- **Row text color:** Same `SatelliteColor` logic as polar graph dots

### Empty State

When `satellites` is empty, the table shows a centered `"No satellites in view"` placeholder instead of an empty `Table`.

---

## Configuration Sheet

Opened via gear toolbar button or `Cmd+,` (macOS `Settings` scene).

### Fields

| Field | Type | Validation | Storage |
|-------|------|------------|---------|
| Broker Hostname | Text field | Non-empty | SwiftData |
| Port | Integer field | 1–65535, default 8883 | SwiftData |
| Username | Text field | Optional (empty = anonymous) | Keychain |
| Password | Secure text field | Optional | Keychain |

### Behavior

- Save button disabled until hostname is non-empty and port is 1–65535
- Saving: writes hostname/port to SwiftData, writes credentials to Keychain, then triggers clean disconnect + reconnect in `MQTTService`
- On appear: loads existing `MQTTConfiguration` from SwiftData and credentials from Keychain
- **First launch:** If hostname is empty string (the default row), the configuration sheet opens automatically on startup before attempting any connection. If the user dismisses the sheet without saving a hostname, the app remains in a disconnected state with the `"No satellite data"` placeholder on the polar graph. No connection attempt is made until a valid hostname is saved.

---

## `seen` Field and Reconnection

The `seen` value in the MQTT payload is "seconds since this PRN was first seen in the current GPSD session." If the MQTT broker disconnects and reconnects, GPSD may reset `seen` to 0 for all satellites. The app does not maintain its own `seen` counter — it displays the raw value from the MQTT message as-is. If a reconnect causes `seen` to reset to 0, the display reflects that.

---

## Toolbar

| Control | Action |
|---------|--------|
| Connection indicator (dot) | Green = connected, Red = disconnected/error |
| Table toggle button | Slides satellite table in/out |
| Trails toggle button | Enables/disables trail rendering on polar graph |
| Gear button | Opens configuration sheet (`Cmd+,`) |

---

## Testing Strategy

Swift Testing (`@Test`, `@Suite`, `#expect`) throughout. Integration tests use a **protocol mock** — `MQTTServiceProtocol` — rather than a live broker, so tests are hermetic and run without network access.

```swift
// ConnectionState is top-level — no qualification needed here
protocol MQTTServiceProtocol {
    func connect(config: MQTTConfiguration, username: String, password: String) async throws
    func disconnect() async
    var skyStream: AsyncStream<SkyMessage> { get }
    var connectionStateStream: AsyncStream<ConnectionState> { get }
}
```

`MQTTService` conforms to this protocol. Tests inject a `MockMQTTService` that yields pre-defined `SkyMessage` values.

### Test Coverage

- **Unit:** `SkyMessage` JSON decoding (including null DOP fields, missing gnssid/svid), `Satellite.color` computed property for all four branches, coordinate math (el/az → canvas x/y), `KeychainHelper` save/load/delete, 24-hour prune predicate logic, write throttle (5-second floor)
- **Integration:** `SatelliteStore` consuming a `MockMQTTService` stream, singleton enforcement for `MQTTConfiguration`, `connectionState` mirroring from actor stream to `@Observable`
- **UI:** Table toggle animation, configuration sheet validation (disabled save state), first-launch auto-open sheet, empty state placeholders

---

## File Structure

```
GPS Tracker/
├── GPS_TrackerApp.swift
├── Models/
│   ├── Satellite.swift              # Satellite struct + SatelliteColor
│   ├── SkyMessage.swift             # Codable MQTT payload + SkyMessageSatellite
│   ├── SatelliteHistoryEntry.swift  # SwiftData @Model
│   └── MQTTConfiguration.swift      # SwiftData @Model
├── Services/
│   ├── MQTTServiceProtocol.swift    # Protocol for testability
│   ├── MQTTService.swift            # Actor, mqtt-nio client
│   └── SatelliteStore.swift         # @Observable, consumes stream, writes history
├── Views/
│   ├── ContentView.swift            # Root HStack container + toolbar
│   ├── PolarGraphView.swift         # Canvas-based sky plot
│   ├── SatelliteTableView.swift     # Slide-out satellite table
│   └── ConfigurationView.swift      # Settings sheet
└── Utilities/
    └── KeychainHelper.swift         # Keychain read/write for credentials
```

---

## MQTT Message Reference

Source: `mqtt-gps-messages.md` in the repository root.

Primary topic: `gps_monitor/sky` — published on every GPSD `SKY` message. Contains `satellites` array with per-satellite `prn`, `el`, `az`, `ss`, `used`, `seen` fields. The JSON key for SNR is `ss` — mapped to `snr` on the Swift `Satellite` struct.

Availability topic: `gps_monitor/availability` — retained, `"online"` / `"offline"`. An `"offline"` payload signals the GPS bridge has disconnected from GPSD and transitions app connection state to `.error("GPS bridge offline")`.
