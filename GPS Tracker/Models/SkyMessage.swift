//
//  SkyMessage.swift
//  GPS Tracker
//
//  Created by Christopher Graham on 4/1/26.
//
// Claude Generated: version 1 - Codable structs for gps_monitor/sky MQTT payload
// Claude Generated: version 2 - Added swiftlint disable/enable for short GPS wire-format identifiers

import Foundation

/// Top-level payload for the `gps_monitor/sky` MQTT topic.
/// nsat and usat fields from the wire format are intentionally omitted —
/// satUsed/satVisible carry the same information.
struct SkyMessage: Codable, Sendable {
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
struct SkyMessageSatellite: Codable, Sendable {
  let prn: Int
  let el: Int // elevation degrees
  let az: Int // azimuth degrees, true north
  let ss: Int // signal-to-noise ratio dBHz; becomes Satellite.snr
  let used: Bool
  let seen: Int
  let gnssid: Int? // GNSS constellation ID; nil for MTK-3301 (GPS-only)
  let svid: Int? // satellite vehicle ID within constellation; nil for MTK-3301
}
