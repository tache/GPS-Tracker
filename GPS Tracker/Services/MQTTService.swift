//
//  MQTTService.swift
//  GPS Tracker
//
//  Created by Christopher Graham on 4/1/26.
//
// Claude Generated: version 1 - MQTT actor with TLS connection and AsyncStream output
// Claude Generated: version 2 - Fix backoff loop and initialize streams at init time
// Claude Generated: version 3 - Fix self-cancelling reconnect, store message handler task, reconnect on listener failure

import Foundation
import Logging
import MQTTNIO
import NIOCore
import NIOSSL

/// Owns the mqtt-nio TLS client. Subscribes to gps_monitor/sky and
/// gps_monitor/availability, decodes JSON payloads, and streams results.
/// Reconnects automatically with exponential backoff (1s → 2s → 4s… cap 60s).
actor MQTTService: MQTTServiceProtocol {

  // MARK: - Protocol (stored properties, initialized once)

  nonisolated let skyStream: AsyncStream<SkyMessage>
  nonisolated let connectionStateStream: AsyncStream<ConnectionState>

  // MARK: - Private State

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
    do {
      try await _connectOnce(config: config, username: username, password: password)
    } catch {
      yieldState(.error(error.localizedDescription))
      scheduleReconnect(config: config, username: username, password: password)
    }
  }

  func disconnect() async {
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
    if let client {
      try? await client.disconnect()
      try? await client.shutdown()
    }
    client = nil
    messageHandlerTask?.cancel()
    messageHandlerTask = nil
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
    let newClient = MQTTClient(
      host: config.hostname,
      port: config.port,
      identifier: identifier,
      eventLoopGroupProvider: .createNew,
      logger: Logger(label: "gps-tracker.mqtt"),
      configuration: mqttConfig
    )
    self.client = newClient

    // These throw on failure — no internal catch so callers receive the error.
    try await newClient.connect()
    yieldState(.connected)
    try await subscribeToTopics(client: newClient)
    startMessageHandler(client: newClient)
  }

  private func yieldState(_ state: ConnectionState) {
    stateStreamContinuation?.yield(state)
  }

  private func subscribeToTopics(client: MQTTClient) async throws {
    try await client.subscribe(to: [
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
          await handlePublishInfo(publishInfo)
        case .failure(let error):
          // listener error — broker may have disconnected
          await yieldState(.error(error.localizedDescription))
        }
      }
      // Sequence ended — broker disconnected mid-session; schedule reconnect.
      await yieldState(.error("Broker disconnected"))
      if let config = await lastConfig {
        await scheduleReconnect(
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
      guard let skyMsg = try? JSONDecoder().decode(SkyMessage.self, from: data) else {
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
    reconnectTask?.cancel()
    reconnectTask = Task {
      var currentDelay = delay
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(currentDelay))
        guard !Task.isCancelled else { break }
        do {
          try await _connectOnce(config: config, username: username, password: password)
          break
        } catch {
          currentDelay = min(currentDelay * 2, 60)
        }
      }
    }
  }
}
