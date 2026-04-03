//
//  SatelliteStore.swift
//  GPS Tracker
//
//  Created by Christopher Graham on 4/1/26.
//
// Claude Generated: version 1 - Observable state hub consuming MQTT streams
// Claude Generated: version 2 - Replace showTrails Bool with TrailMode enum
// Claude Generated: version 3 - Auto-connect in configure() instead of relying on onAppear

import Foundation
import SwiftData
import Observation

/// Trail rendering mode for the polar graph.
enum TrailMode {
    case off      // no trails drawn
    case mono     // trails drawn in white/secondary
    case colored  // trails drawn using SNR-based SatelliteColor
}

/// Central state store for the app. Consumes AsyncStreams from MQTTService,
/// maintains live satellite array, writes history to SwiftData (throttled),
/// and prunes entries older than 24 hours.
@Observable
final class SatelliteStore {

    // MARK: - Published State

    private(set) var satellites: [Satellite] = []
    private(set) var connectionState: ConnectionState = .disconnected
    var trailMode: TrailMode = .mono
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
        guard !config.hostname.isEmpty else { return }
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
        satellites = message.satellites.map { sat in
            Satellite(prn: sat.prn, elevation: sat.el, azimuth: sat.az,
                      snr: sat.ss, used: sat.used, seen: sat.seen)
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
