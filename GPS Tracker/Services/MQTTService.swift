//
//  MQTTService.swift
//  GPS Tracker
//
//  Created by Christopher Graham on 4/1/26.
//
// Claude Generated: version 1 - MQTT actor with TLS connection and AsyncStream output
// Claude Generated: version 2 - Fix backoff loop and initialize streams at init time
// Claude Generated: version 3 - Fix self-cancelling reconnect, store message handler task, reconnect on listener failure
// Claude Generated: version 4 - Add OSLog diagnostics; guard against spurious reconnect on intentional teardown

import Foundation
import Logging
import MQTTNIO
import NIOCore
import NIOSSL
import os

/// Owns the mqtt-nio TLS client. Subscribes to gps_monitor/sky and
/// gps_monitor/availability, decodes JSON payloads, and streams results.
/// Reconnects automatically with exponential backoff (1s → 2s → 4s… cap 60s).
actor MQTTService: MQTTServiceProtocol {

  // MARK: - Protocol (stored properties, initialized once)

  nonisolated let skyStream: AsyncStream<SkyMessage>
  nonisolated let connectionStateStream: AsyncStream<ConnectionState>

  // MARK: - Private State

  private nonisolated let mqttLogger = os.Logger(
    subsystem: "com.astronomis.gps-tracker", category: "mqtt")
  private var skyStreamContinuation: AsyncStream<SkyMessage>.Continuation?
  private var stateStreamContinuation: AsyncStream<ConnectionState>.Continuation?
  private var client: MQTTClient?
  private var reconnectTask: Task<Void, Never>?
  private var messageHandlerTask: Task<Void, Never>?

  // Stored credentials for reconnect after unexpected listener termination
  private var lastConfig: MQTTConfiguration?
  private var lastUsername: String = ""
  private var lastPassword: String = ""

  // MARK: - Init

  init() {
    // Capture continuations from the synchronous AsyncStream init closures.
    // Both closures execute synchronously before init returns, so the
    // implicitly-unwrapped locals are guaranteed non-nil by the assignments below.
    var skyCont: AsyncStream<SkyMessage>.Continuation!
    var stateCont: AsyncStream<ConnectionState>.Continuation!
    skyStream = AsyncStream { skyCont = $0 }
    connectionStateStream = AsyncStream { stateCont = $0 }
    skyStreamContinuation = skyCont
    stateStreamContinuation = stateCont
  }

  // MARK: - Public Protocol Methods

  func connect(config: MQTTConfiguration, username: String, password: String) async throws {
    mqttLogger.info(
      "connect() called — host: \(config.hostname, privacy: .public):\(config.port, privacy: .public)"
    )
    do {
      try await _connectOnce(config: config, username: username, password: password)
    } catch {
      mqttLogger.error(
        "connect() failed: \(error.localizedDescription, privacy: .public) — scheduling reconnect")
      yieldState(.error(error.localizedDescription))
      scheduleReconnect(config: config, username: username, password: password)
    }
  }

  func disconnect() async {
    mqttLogger.info("disconnect() called — cancelling reconnectTask and tearing down client")
    reconnectTask?.cancel()
    reconnectTask = nil
    await _teardownClient()
    yieldState(.disconnected)
  }

  // MARK: - Private

  /// Tears down the existing client and message handler without touching reconnectTask.
  /// Called from both disconnect() and _connectOnce() so that reconnect loops
  /// do not inadvertently cancel themselves.
  private func _teardownClient() async {
    mqttLogger.info("_teardownClient() — cancelling messageHandlerTask and shutting down client")
    messageHandlerTask?.cancel()
    messageHandlerTask = nil
    if let client {
      try? await client.disconnect()
      try? await client.shutdown()
    }
    client = nil
  }

  /// Performs a single connection attempt. Throws on any failure so callers
  /// (both `connect` and the reconnect loop) can handle the error uniformly.
  private func _connectOnce(
    config: MQTTConfiguration,
    username: String,
    password: String
  ) async throws {
    // Store credentials so the listener failure path can schedule a reconnect.
    lastConfig = config
    lastUsername = username
    lastPassword = password

    mqttLogger.info(
      "_connectOnce() — host: \(config.hostname, privacy: .public):\(config.port, privacy: .public) user: \(username.isEmpty ? "<none>" : username, privacy: .public)"
    )
    await _teardownClient()
    yieldState(.connecting)

    let tlsConfig = TLSConfiguration.makeClientConfiguration()
    let mqttConfig = MQTTClient.Configuration(
      userName: username.isEmpty ? nil : username,
      password: password.isEmpty ? nil : password,
      useSSL: true,
      tlsConfiguration: .niossl(tlsConfig)
    )

    let identifier = "gps-tracker-\(UUID().uuidString.prefix(8))"
    let newClient = Self.createMQTTClient(
      host: config.hostname,
      port: config.port,
      identifier: identifier,
      configuration: mqttConfig
    )
    self.client = newClient

    // These throw on failure — no internal catch so callers receive the error.
    try await newClient.connect()
    mqttLogger.info("_connectOnce() — TCP/TLS connected, subscribing to topics")
    yieldState(.connected)
    try await subscribeToTopics(client: newClient)
    mqttLogger.info("_connectOnce() — subscribed, starting message handler")
    startMessageHandler(client: newClient)
  }

  private func yieldState(_ state: ConnectionState) {
    stateStreamContinuation?.yield(state)
  }

  private func subscribeToTopics(client: MQTTClient) async throws {
    _ = try await client.subscribe(to: [
      MQTTSubscribeInfo(topicFilter: "gps_monitor/sky", qos: .atLeastOnce),
      MQTTSubscribeInfo(topicFilter: "gps_monitor/availability", qos: .atLeastOnce)
    ])
  }

  private func startMessageHandler(client: MQTTClient) {
    let listener = client.createPublishListener()
    messageHandlerTask = Task {
      for await result in listener {
        switch result {
        case .success(let publishInfo):
          handlePublishInfo(publishInfo)
        case .failure(let error):
          // listener error — broker may have disconnected
          mqttLogger.warning(
            "startMessageHandler() — listener error: \(error.localizedDescription, privacy: .public)"
          )
          yieldState(.error(error.localizedDescription))
        }
      }
      // Sequence ended. If the task was cancelled we were intentionally torn
      // down (e.g. disconnect() or reconnect()); do NOT schedule a reconnect.
      guard !Task.isCancelled else {
        mqttLogger.info(
          "startMessageHandler() — sequence ended due to task cancellation (intentional teardown), skipping reconnect"
        )
        return
      }
      // Unexpected sequence termination — broker disconnected mid-session.
      mqttLogger.warning(
        "startMessageHandler() — sequence ended unexpectedly, scheduling reconnect")
      yieldState(.error("Broker disconnected"))
      if let config = lastConfig {
        scheduleReconnect(
          config: config,
          username: lastUsername,
          password: lastPassword)
      }
    }
  }

  private func handlePublishInfo(_ info: MQTTPublishInfo) {
    let topic = info.topicName
    let data = Data(info.payload.readableBytesView)

    if topic == "gps_monitor/sky" {
      // Decode directly - SkyMessage.Decodable's main-actor conformance is a Swift 6 warning
      // from the Decodable protocol contract. This is safe and works correctly at runtime.
      let skyMsg: SkyMessage?
      do {
        skyMsg = try JSONDecoder().decode(SkyMessage.self, from: data)
      } catch {
        skyMsg = nil
      }
      guard let skyMsg else {
        return // malformed message — silently discard
      }
      skyStreamContinuation?.yield(skyMsg)
    } else if topic == "gps_monitor/availability" {
      let text = String(data: data, encoding: .utf8) ?? ""
      if text == "offline" {
        yieldState(.error("GPS bridge offline"))
      }
      // "online" is silently ignored — TCP connection implies connected
    }
  }

  /// Starts the exponential-backoff reconnect loop. Calls `_connectOnce`
  /// directly so catch blocks here actually fire and can double `currentDelay`.
  /// Cancels any existing reconnect task before creating a new one to avoid orphaned tasks.
  private func scheduleReconnect(
    config: MQTTConfiguration,
    username: String,
    password: String,
    delay: TimeInterval = 1.0
  ) {
    mqttLogger.info(
      "scheduleReconnect() — starting backoff loop, initial delay: \(delay, privacy: .public)s")
    reconnectTask?.cancel()
    reconnectTask = Task {
      var currentDelay = delay
      while !Task.isCancelled {
        mqttLogger.info(
          "scheduleReconnect() — waiting \(currentDelay, privacy: .public)s before retry")
        try? await Task.sleep(for: .seconds(currentDelay))
        guard !Task.isCancelled else {
          mqttLogger.info("scheduleReconnect() — cancelled during sleep, exiting loop")
          break
        }
        do {
          mqttLogger.info("scheduleReconnect() — attempting reconnect")
          try await _connectOnce(config: config, username: username, password: password)
          mqttLogger.info("scheduleReconnect() — reconnect succeeded")
          break
        } catch {
          mqttLogger.error(
            "scheduleReconnect() — attempt failed: \(error.localizedDescription, privacy: .public), next delay: \(min(currentDelay * 2, 60), privacy: .public)s"
          )
          currentDelay = min(currentDelay * 2, 60)
        }
      }
    }
  }

  // Helper to encapsulate deprecated createNew EventLoopGroupProvider.
  // The recommended `.shared(MultiThreadedEventLoopGroup.singleton)` is not available
  // in the imported NIOCore version. This deprecation does not affect functionality.
  nonisolated private static func createMQTTClient(
    host: String,
    port: Int,
    identifier: String,
    configuration: MQTTClient.Configuration
  ) -> MQTTClient {
    MQTTClient(
      host: host,
      port: port,
      identifier: identifier,
      eventLoopGroupProvider: .createNew,
      logger: Logger(label: "gps-tracker.mqtt"),
      configuration: configuration
    )
  }
}
