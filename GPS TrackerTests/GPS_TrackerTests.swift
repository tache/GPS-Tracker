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
