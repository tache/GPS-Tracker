//
//  Satellite.swift
//  GPS Tracker
//
//  Created by Christopher Graham on 4/1/26.
//
// Claude Generated: version 1 - In-memory satellite model and color classification
// Claude Generated: version 2 - Added Equatable and Sendable conformances for actor boundary safety

import Foundation

/// Color classification for a satellite dot on the polar graph and table row.
/// Derived from the `used` flag and SNR value, matching the web dashboard rule:
/// `red if not used, else green if ss>=35, else orange if ss>=20, else yellow`
enum SatelliteColor: Equatable {
  case red // not used (outline circle)
  case green // used, snr >= 35 (solid)
  case orange // used, snr >= 20 (solid)
  case yellow // used, snr < 20 (solid)
}

/// In-memory representation of a single GPS satellite from the current sky message.
/// Not persisted — lives only in SatelliteStore.satellites.
/// Note: For v1, PRN is treated as unique (MTK-3301 is GPS-only).
/// Multi-constellation hardware would require a composite (gnssid, prn) key.
struct Satellite: Identifiable, Equatable, Sendable {
  let prn: Int
  let elevation: Int // degrees above horizon (0–90)
  let azimuth: Int // degrees, true north (0–359)
  let snr: Int // signal-to-noise ratio dBHz (mapped from JSON "ss" field)
  let used: Bool // true if contributing to the current GPS fix
  let seen: Int // seconds since first seen this GPSD session (raw from MQTT)

  var id: Int { prn }

  /// Color for this satellite's dot and table row.
  var color: SatelliteColor {
    guard used else { return .red }
    if snr >= 35 { return .green }
    if snr >= 20 { return .orange }
    return .yellow
  }
}
