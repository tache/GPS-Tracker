//
//  SatelliteHistoryEntry.swift
//  GPS Tracker
//
//  Created by Christopher Graham on 4/1/26.
//
// Claude Generated: version 1 - SwiftData model for satellite trail history
// Claude Generated: version 2 - Conform to Sendable for thread-safe closure capture

import Foundation
import SwiftData

/// Persisted record of a satellite's position at a point in time.
/// Used to render trail paths on the polar graph.
/// Pruned to a 24-hour rolling window by SatelliteStore.
/// Note: `seen` is intentionally not stored — it's a GPSD session counter
/// and is not meaningful as historical data.
@Model
final class SatelliteHistoryEntry: Sendable {
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
