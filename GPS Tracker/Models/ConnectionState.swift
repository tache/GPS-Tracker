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
internal enum ConnectionState: Equatable {
  case disconnected
  case connecting
  case connected
  case error(String)
}
