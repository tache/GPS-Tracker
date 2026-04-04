//
//  SatelliteStore.swift
//  GPS Tracker
//
//  Created by Christopher Graham on 4/1/26.
//
// Claude Generated: version 1 - Observable state hub consuming MQTT streams
// Claude Generated: version 2 - Replace showTrails Bool with TrailMode enum
// Claude Generated: version 3 - Auto-connect in configure() instead of relying on onAppear
// Claude Generated: version 4 - Add isReceivingMessage pulse for connection indicator
// Claude Generated: version 5 - Auto-delete trail history for satellites that leave view
// Claude Generated: version 6 - Debounce view updates to reduce Canvas redraws at 5Hz message rate
// Claude Generated: version 7 - Move SwiftData operations (writes/prunes/cleanups) to background threads
// Claude Generated: version 8 - Assign QoS priorities to background tasks to prevent priority inversion
// Claude Generated: version 9 - Reduce history write frequency from 5s to 60s to prevent memory bloat

import Foundation
import Observation
import SwiftData

/// Trail rendering mode for the polar graph.
enum TrailMode {
  case off // no trails drawn
  case mono // trails drawn in white/secondary
  case colored // trails drawn using SNR-based SatelliteColor
}

/// Central state store for the app. Consumes AsyncStreams from MQTTService,
/// maintains live satellite array, writes history to SwiftData (throttled),
/// and prunes entries older than 24 hours.
@Observable
final class SatelliteStore {

  // MARK: - Published State

  private(set) var satellites: [Satellite] = []
  private(set) var connectionState: ConnectionState = .disconnected
  private(set) var isReceivingMessage: Bool = false
  var trailMode: TrailMode = .mono
  var showTable: Bool = false

  // MARK: - Private

  private let mqttService: any MQTTServiceProtocol
  private var modelContext: ModelContext?
  private var lastHistoryWriteDate: Date?
  private var skyTask: Task<Void, Never>?
  private var stateTask: Task<Void, Never>?
  private var messageFlashTask: Task<Void, Never>?
  private var pruneTimer: Timer?
  private var trailCleanupTimer: Timer?
  private var updateDebounceTask: Task<Void, Never>?

  // Track satellites that have gone out of view and their last elevation
  // Key: PRN, Value: (lastElevation, lastSeenDate)
  private var outOfViewSatellites: [Int: (elevation: Int, date: Date)] = [:]

  // Pending message waiting to be processed after debounce
  private var pendingMessage: SkyMessage?

  // Configuration for trail cleanup
  private let outOfViewDurationSeconds: TimeInterval = 300 // 5 minutes
  private let lowElevationThreshold: Int = 15 // degrees
  private let updateDebounceInterval: TimeInterval = 0.2 // 200ms, batches ~1 msg at 5Hz

  // MARK: - Init

  init(mqttService: any MQTTServiceProtocol) {
    self.mqttService = mqttService
    startStreams()
  }

  func configure(modelContext: ModelContext) {
    self.modelContext = modelContext
    startPruneTimer()
    startTrailCleanupTimer()
  }

  deinit {
    pruneTimer?.invalidate()
    trailCleanupTimer?.invalidate()
    updateDebounceTask?.cancel()
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
        await MainActor.run { self.queueSkyMessage(message) }
      }
    }

    stateTask = Task { [weak self] in
      guard let self else { return }
      for await state in mqttService.connectionStateStream {
        await MainActor.run { self.connectionState = state }
      }
    }
  }

  /// Queues a message for debounced processing.
  /// If a previous message is pending, it's replaced (only keep the latest).
  /// A debounce timer ensures the batch is processed after updateDebounceInterval.
  private func queueSkyMessage(_ message: SkyMessage) {
    pendingMessage = message
    updateDebounceTask?.cancel()
    updateDebounceTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .milliseconds(Int(self?.updateDebounceInterval ?? 0.2) * 1000))
      guard !Task.isCancelled else { return }
      if let pending = self?.pendingMessage {
        self?.processSkyMessage(pending)
      }
    }
  }

  private func processSkyMessage(_ message: SkyMessage) {
    let newSatellites = message.satellites.map { sat in
      Satellite(
        prn: sat.prn, elevation: sat.el, azimuth: sat.az,
        snr: sat.ss, used: sat.used, seen: sat.seen)
    }.sorted { $0.snr > $1.snr }

    // Track satellites that just left view
    let previousPRNs = Set(satellites.map { $0.prn })
    let currentPRNs = Set(newSatellites.map { $0.prn })
    let nowOutOfView = previousPRNs.subtracting(currentPRNs)

    for prn in nowOutOfView {
      // Find the last elevation for this satellite
      if let satellite = satellites.first(where: { $0.prn == prn }) {
        outOfViewSatellites[prn] = (elevation: satellite.elevation, date: Date())
      }
    }

    // Satellites that are back in view should be removed from the out-of-view tracking
    for satellite in newSatellites {
      outOfViewSatellites.removeValue(forKey: satellite.prn)
    }

    satellites = newSatellites
    maybeWriteHistory()
    pulseMessageIndicator()
  }

  /// Briefly sets isReceivingMessage for the connection indicator flash.
  /// Cancels any pending reset so rapid messages extend the flash rather than stacking tasks.
  private func pulseMessageIndicator() {
    isReceivingMessage = true
    messageFlashTask?.cancel()
    messageFlashTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .milliseconds(200))
      guard !Task.isCancelled else { return }
      self?.isReceivingMessage = false
    }
  }

  // MARK: - History (SwiftData)

  /// Returns true if enough time has passed since the last history write.
  /// Exposed for testing without SwiftData.
  func shouldWriteHistory(lastWrite: Date?) -> Bool {
    guard let last = lastWrite else { return true }
    return Date().timeIntervalSince(last) >= 60.0 // Write every 60 seconds instead of 5
  }

  private func maybeWriteHistory() {
    guard let context = modelContext,
      shouldWriteHistory(lastWrite: lastHistoryWriteDate)
    else { return }
    lastHistoryWriteDate = Date()
    let timestamp = Date()
    let satCopy = satellites

    // Move database write to background with userInitiated priority to avoid blocking main thread
    Task.detached(priority: .userInitiated) {
      for sat in satCopy {
        let entry = SatelliteHistoryEntry(
          prn: sat.prn, elevation: sat.elevation, azimuth: sat.azimuth,
          snr: sat.snr, used: sat.used, timestamp: timestamp
        )
        context.insert(entry)
      }
      try? context.save()
    }
  }

  private func startPruneTimer() {
    pruneTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
      self?.pruneOldHistory()
    }
  }

  private func startTrailCleanupTimer() {
    trailCleanupTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
      self?.cleanupOutOfViewTrails()
    }
  }

  private func pruneOldHistory() {
    guard let context = modelContext else { return }

    // Move database cleanup to background with utility priority
    Task.detached(priority: .utility) {
      let cutoff = Date().addingTimeInterval(-86400)
      let predicate = #Predicate<SatelliteHistoryEntry> { $0.timestamp < cutoff }
      let descriptor = FetchDescriptor(predicate: predicate)
      guard let stale = try? context.fetch(descriptor) else { return }
      for entry in stale { context.delete(entry) }
      try? context.save()
    }
  }

  /// Deletes trail history for satellites that have been out of view for long enough
  /// and were last seen at a low elevation angle.
  /// This prevents deleting data during brief intermittent dips while still cleaning up
  /// old trails when satellites have clearly left the sky.
  private func cleanupOutOfViewTrails() {
    guard let context = modelContext else { return }
    let now = Date()
    var prnToDelete: [Int] = []

    for (prn, info) in outOfViewSatellites {
      let outOfViewDuration = now.timeIntervalSince(info.date)
      // Only delete if out of view for long enough AND was at low elevation
      if outOfViewDuration >= outOfViewDurationSeconds && info.elevation <= lowElevationThreshold {
        prnToDelete.append(prn)
      }
    }

    if prnToDelete.isEmpty { return }

    // Move database cleanup to background with utility priority
    Task.detached(priority: .utility) { [weak self] in
      for prn in prnToDelete {
        let predicate = #Predicate<SatelliteHistoryEntry> { $0.prn == prn }
        let descriptor = FetchDescriptor(predicate: predicate)
        if let entries = try? context.fetch(descriptor) {
          for entry in entries {
            context.delete(entry)
          }
        }
      }
      try? context.save()
      // Update the tracking dictionary on main thread
      await MainActor.run { [weak self] in
        guard let self else { return }
        for prn in prnToDelete {
          self.outOfViewSatellites.removeValue(forKey: prn)
        }
      }
    }
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
