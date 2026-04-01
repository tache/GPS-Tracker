# GPS MQTT Message Reference

This document describes the MQTT topics published by `gpsd_monitor.py`, the GPSD-to-MQTT bridge running on the GPS/NTP server (`hawk`). All payloads are JSON. The broker uses TLS (default port 8883).

---

## Connection

| Parameter | Value |
|-----------|-------|
| Broker | Home Assistant MQTT broker |
| Port | 8883 (TLS) |
| Auth | Username + password (via env vars) |
| Client ID | `gps_monitor_bridge_<hostname>` |

### Availability

| Topic | Payload | Notes |
|-------|---------|-------|
| `gps_monitor/availability` | `online` / `offline` | Retained. `offline` is set by the broker Last Will if the bridge disconnects ungracefully. |

---

## Topics Overview

| Topic | GPSD Source | Description |
|-------|-------------|-------------|
| `gps_monitor/version` | `VERSION` message | GPSD daemon version info |
| `gps_monitor/sky` | `SKY` message | Satellite visibility, counts, DOPs |
| `gps_monitor/tpv` | `TPV` message | Time, position, velocity fix data |
| `gps_monitor/toff` | `TOFF` message | Serial time-of-fix offset (GPS vs system clock) |
| `gps_monitor/pps` | `PPS` message | Pulse-Per-Second timing offset |

Each topic is published independently. Topics can be rate-limited or disabled on the bridge via environment variables (see the end of this document).

---

## `gps_monitor/version`

Published once on startup when GPSD sends its `VERSION` response.

```json
{
  "release": "3.27.5",
  "proto": "3.14"
}
```

| Field | Type | Description |
|-------|------|-------------|
| `release` | string | GPSD release version string (max 64 chars) |
| `proto` | string | GPSD JSON protocol version, `"<major>.<minor>"` |

---

## `gps_monitor/sky`

Published on every GPSD `SKY` message. Contains satellite counts, all DOP values, and a full per-satellite array.

```json
{
  "sat_used": 9,
  "sat_visible": 14,
  "nsat": 14,
  "usat": 9,
  "hdop": 0.85,
  "vdop": 1.12,
  "pdop": 1.42,
  "tdop": 0.93,
  "gdop": 1.76,
  "xdop": 0.61,
  "ydop": 0.58,
  "satellites": [
    {
      "prn": 5,
      "el": 72,
      "az": 214,
      "ss": 42,
      "used": true,
      "seen": 312
    },
    {
      "prn": 29,
      "el": 18,
      "az": 47,
      "ss": 22,
      "used": false,
      "seen": 88
    }
  ]
}
```

### Top-level fields

| Field | Type | Unit | Description |
|-------|------|------|-------------|
| `sat_used` | integer | satellites | Number of satellites used in the current fix |
| `sat_visible` | integer | satellites | Total number of satellites visible (in the array) |
| `nsat` | integer or null | satellites | GPSD `nSat` field (total tracked); null if not present |
| `usat` | integer or null | satellites | GPSD `uSat` field (used in fix); null if not present |
| `hdop` | float or null | HDOP | Horizontal Dilution of Precision |
| `vdop` | float or null | VDOP | Vertical Dilution of Precision |
| `pdop` | float or null | PDOP | Position (3D) Dilution of Precision |
| `tdop` | float or null | TDOP | Time Dilution of Precision |
| `gdop` | float or null | GDOP | Geometric Dilution of Precision |
| `xdop` | float or null | XDOP | Longitudinal Dilution of Precision |
| `ydop` | float or null | YDOP | Latitudinal Dilution of Precision |
| `satellites` | array | — | Per-satellite detail (see below) |

### `satellites` array entry

Sorted: used satellites first, then descending by SNR.

| Field | Type | Unit | Description |
|-------|------|------|-------------|
| `prn` | integer | — | Satellite PRN / ID number |
| `el` | integer | degrees | Elevation above horizon |
| `az` | integer | degrees | Azimuth (0–359°, true north) |
| `ss` | integer | dBHz | Signal-to-noise ratio |
| `used` | boolean | — | `true` if contributing to current fix |
| `seen` | integer | seconds | Seconds since this PRN was first seen in this session |
| `gnssid` | integer | — | GNSS constellation ID (optional — not emitted by MTK-3301) |
| `svid` | integer | — | Satellite vehicle ID within constellation (optional) |

**GNSS ID values** (when present): 0=GPS, 2=Galileo, 3=BeiDou, 5=QZSS, 6=GLONASS, 7=NavIC.

> **Note:** The current receiver (MTK-3301, GPS-only) does not emit `gnssid` or `svid`. Those fields only appear if the receiver supports them.

---

## `gps_monitor/tpv`

Published on every GPSD `TPV` (Time-Position-Velocity) message. When there is no fix (`mode` ≤ 1), position/velocity fields are set to `null`.

```json
{
  "fix": "3D Fix",
  "time": "2026-04-01T18:32:10Z",
  "lat": 37.774929,
  "lon": -122.419416,
  "alt": 15.42,
  "alt_hae": 18.67,
  "speed": 0.012345,
  "climb": 0.001234,
  "track": 241.234567,
  "magtrack": 243.012345,
  "ept": 0.005000,
  "sep": 3.21,
  "eph": 2.14,
  "geoid_sep": -28.50,
  "last_error": "ok"
}
```

| Field | Type | Unit | Description |
|-------|------|------|-------------|
| `fix` | string | — | Fix quality: `"No Fix"`, `"2D Fix"`, or `"3D Fix"` |
| `time` | string or null | — | GPS time as ISO 8601, truncated to whole seconds, e.g. `"2026-04-01T18:32:10Z"` |
| `lat` | float or null | degrees | Latitude (positive = north), 6 decimal places |
| `lon` | float or null | degrees | Longitude (positive = east), 6 decimal places |
| `alt` | float or null | meters | Altitude above Mean Sea Level (MSL), 2 decimal places |
| `alt_hae` | float or null | meters | Altitude above WGS84 ellipsoid (HAE), 2 decimal places |
| `speed` | float or null | m/s | Ground speed, 6 decimal places |
| `climb` | float or null | m/s | Vertical climb rate (positive = ascending), 6 decimal places |
| `track` | float or null | degrees | Course over ground, true north, 6 decimal places |
| `magtrack` | float or null | degrees | Course over ground, magnetic north, 6 decimal places |
| `ept` | float or null | seconds | Estimated time error, 6 decimal places |
| `sep` | float or null | meters | Estimated spherical (3D) position error, 2 decimal places |
| `eph` | float or null | meters | Estimated horizontal position error, 2 decimal places |
| `geoid_sep` | float or null | meters | Geoid separation (MSL minus HAE), 2 decimal places |
| `last_error` | string | — | Last GPSD `ERROR` message text, or `"ok"` if none |

---

## `gps_monitor/toff`

Published on every GPSD `TOFF` message. TOFF captures the serial latency between GPS time and the moment the system clock received the fix. The typical offset is ~500ms for a serial receiver.

```json
{
  "real_sec": 1743528730,
  "real_nsec": 0,
  "clock_sec": 1743528730,
  "clock_nsec": 498123456,
  "offset_ns": -498123456,
  "precision": -20,
  "shm": "SHM(0)"
}
```

| Field | Type | Unit | Description |
|-------|------|------|-------------|
| `real_sec` | integer | seconds | GPS time — whole seconds (Unix epoch) |
| `real_nsec` | integer | nanoseconds | GPS time — nanosecond remainder |
| `clock_sec` | integer | seconds | System clock at receipt — whole seconds (Unix epoch) |
| `clock_nsec` | integer | nanoseconds | System clock at receipt — nanosecond remainder |
| `offset_ns` | integer | nanoseconds | Computed offset: `(real_sec - clock_sec) * 1e9 + (real_nsec - clock_nsec)` |
| `precision` | integer or null | — | GPSD precision exponent (log2 seconds), if present |
| `shm` | string or null | — | Shared memory segment name (e.g. `"SHM(0)"`), max 64 chars |

> **Note:** TOFF requires GPSD to be started with `pps:true` in the `WATCH` command. This is set automatically by the bridge.

---

## `gps_monitor/pps`

Published on every GPSD `PPS` message. PPS is the hardware Pulse-Per-Second signal from the GPS receiver — it is the most precise timing reference available and is used by NTPd for sub-microsecond synchronization.

```json
{
  "real_sec": 1743528731,
  "real_nsec": 0,
  "clock_sec": 1743528731,
  "clock_nsec": 312,
  "offset_ns": -312,
  "precision": -20,
  "shm": "SHM(1)"
}
```

| Field | Type | Unit | Description |
|-------|------|------|-------------|
| `real_sec` | integer | seconds | GPS PPS time — whole seconds (Unix epoch) |
| `real_nsec` | integer | nanoseconds | GPS PPS time — nanosecond remainder (typically 0) |
| `clock_sec` | integer | seconds | System clock at PPS edge — whole seconds (Unix epoch) |
| `clock_nsec` | integer | nanoseconds | System clock at PPS edge — nanosecond remainder |
| `offset_ns` | integer | nanoseconds | Computed offset: `(real_sec - clock_sec) * 1e9 + (real_nsec - clock_nsec)` |
| `precision` | integer or null | — | GPSD precision exponent (log2 seconds), if present |
| `shm` | string or null | — | Shared memory segment name (e.g. `"SHM(1)"`), max 64 chars |

> **Note:** PPS offsets should be very small — single-digit to low hundreds of nanoseconds on a well-disciplined system.

---

## Null Values

Fields set to `null` in any payload mean the value was not available or not yet received from GPSD. Consumers should treat `null` as "no data" and not display or calculate with it.

---

## Per-Group Enable / Rate-Limit Controls

Each topic group can be independently enabled and rate-limited on the bridge via environment variables in the service config file.

| Env var | Default | Description |
|---------|---------|-------------|
| `GPS_PUBLISH_VERSION` | `true` | Enable/disable the `version` group |
| `GPS_PUBLISH_VERSION_INTERVAL` | `0` | Publish interval in seconds (0 = every message) |
| `GPS_PUBLISH_SKY` | `true` | Enable/disable the `sky` group |
| `GPS_PUBLISH_SKY_INTERVAL` | `0` | Publish interval in seconds |
| `GPS_PUBLISH_TPV` | `true` | Enable/disable the `tpv` group |
| `GPS_PUBLISH_TPV_INTERVAL` | `0` | Publish interval in seconds |
| `GPS_PUBLISH_TOFF` | `true` | Enable/disable the `toff` group |
| `GPS_PUBLISH_TOFF_INTERVAL` | `0` | Publish interval in seconds |
| `GPS_PUBLISH_PPS` | `true` | Enable/disable the `pps` group |
| `GPS_PUBLISH_PPS_INTERVAL` | `0` | Publish interval in seconds |

If a group is disabled, its HA discovery configs are cleared from the broker on startup (empty retained message). Disabled groups publish nothing until re-enabled and the bridge is restarted.
