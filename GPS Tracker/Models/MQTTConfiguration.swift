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
final class MQTTConfiguration: Sendable {
  var hostname: String
  var port: Int // default 8883 (standard MQTT TLS port)

  init(hostname: String = "", port: Int = 8883) {
    self.hostname = hostname
    self.port = port
  }
}
