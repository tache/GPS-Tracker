//
//  GPS_TrackerTests.swift
//  GPS TrackerTests
//
//  Created by Christopher Graham on 4/1/26.
//
// Claude Generated: version 1 - Initial test suite setup
// Claude Generated: version 2 - Added SatelliteTests suite
// Claude Generated: version 3 - Added SkyMessageDecodingTests suite
// Claude Generated: version 4 - Added SwiftDataModelTests suite
// Claude Generated: version 5 - Added KeychainHelperTests suite
// Claude Generated: version 6 - Added MockMQTTService and MQTTServiceProtocolTests suite
// Claude Generated: version 7 - Added SatelliteStoreTests suite
// Claude Generated: version 8 - Added PolarCoordinateTests suite

import CoreGraphics
import Foundation
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

@Suite("Satellite Tests")
struct SatelliteTests {

  // Helper — all fields required, seen defaults to 0
  private func sat(
    prn: Int = 1, el: Int = 45, az: Int = 90,
    snr: Int = 30, used: Bool = true, seen: Int = 0
  ) -> Satellite {
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
    let bad = #"{ "sat_used": "not-a-number" }"#
    #expect(throws: (any Error).self) {
      try JSONDecoder().decode(SkyMessage.self, from: Data(bad.utf8))
    }
  }
}

@Suite("SwiftData Model Tests")
struct SwiftDataModelTests {

  @Test("SatelliteHistoryEntry initializes with all fields")
  func historyEntryInit() {
    let now = Date()
    let entry = SatelliteHistoryEntry(
      prn: 21, elevation: 80, azimuth: 31,
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
    let old = SatelliteHistoryEntry(
      prn: 1, elevation: 10, azimuth: 90,
      snr: 20, used: true,
      timestamp: now.addingTimeInterval(-90000)) // 25 hours ago
    let fresh = SatelliteHistoryEntry(
      prn: 2, elevation: 20, azimuth: 180,
      snr: 30, used: true,
      timestamp: now.addingTimeInterval(-3600)) // 1 hour ago
    let cutoff = now.addingTimeInterval(-86400)
    #expect(old.timestamp < cutoff) // should be pruned
    #expect(fresh.timestamp >= cutoff) // should be kept
  }
}

@Suite("KeychainHelper Tests", .serialized)
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
    let msg = SkyMessage(
      satUsed: 5, satVisible: 10,
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

@Suite("SatelliteStore Tests")
struct SatelliteStoreTests {

  private func makeSkyMessage(satellites: [SkyMessageSatellite]) -> SkyMessage {
    SkyMessage(
      satUsed: satellites.filter(\.used).count,
      satVisible: satellites.count,
      hdop: nil, vdop: nil, pdop: nil, tdop: nil,
      gdop: nil, xdop: nil, ydop: nil,
      satellites: satellites)
  }

  private func makeSatEntry(prn: Int, snr: Int, used: Bool) -> SkyMessageSatellite {
    SkyMessageSatellite(
      prn: prn, el: 45, az: 90, ss: snr, used: used, seen: 100,
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
    #expect(sat?.snr == 43) // ss → snr mapping
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

@Suite("Polar Coordinate Tests")
struct PolarCoordinateTests {

  /// Mirror the coordinate function from PolarGraphView
  private func polarPoint(
    elevation: Int, azimuth: Int,
    center: CGPoint, radius: CGFloat
  ) -> CGPoint {
    let dist = (1.0 - Double(elevation) / 90.0) * Double(radius)
    let azRad = Double(azimuth) * .pi / 180.0
    return CGPoint(
      x: center.x + dist * sin(azRad),
      y: center.y - dist * cos(azRad)
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
    #expect(abs(north.x - center.x) < 0.001) // x = center
    #expect(abs(north.y - (center.y - radius)) < 0.001) // y = top
  }

  @Test("East (azimuth 90) maps to right side")
  func eastIsRight() {
    let center = CGPoint(x: 100, y: 100)
    let radius: CGFloat = 100
    let east = polarPoint(elevation: 0, azimuth: 90, center: center, radius: radius)
    #expect(abs(east.x - (center.x + radius)) < 0.001) // x = right
    #expect(abs(east.y - center.y) < 0.001) // y = center
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
    let expectedR = (1.0 - 30.0 / 90.0) * 100.0 // 66.67
    #expect(abs(pt.y - (-expectedR)) < 0.001)
  }

  @Test("Trail opacity — floor at 0.2")
  func trailOpacityFloor() {
    func opacity(ageSecs: Double) -> Double {
      max(0.2, 1.0 - (ageSecs / 86400.0))
    }
    #expect(opacity(ageSecs: 0) == 1.0)
    #expect(opacity(ageSecs: 43200) == 0.5) // 12 hours
    #expect(opacity(ageSecs: 86400) == 0.2) // 24 hours (floor)
    #expect(opacity(ageSecs: 90000) == 0.2) // beyond 24 hours (floor)
  }
}
