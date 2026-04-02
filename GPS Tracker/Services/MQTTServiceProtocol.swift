//
//  MQTTServiceProtocol.swift
//  GPS Tracker
//
//  Created by Christopher Graham on 4/1/26.
//
// Claude Generated: version 1 - Protocol enabling mock injection for testing
// Claude Generated: version 2 - Removed SkyMessage placeholder (real type added in SkyMessage.swift)
// Claude Generated: version 3 - Removed MQTTConfiguration placeholder (real type added in MQTTConfiguration.swift)

/// Protocol that MQTTService conforms to, enabling MockMQTTService injection in tests.
/// ConnectionState is top-level so this protocol compiles independently.
internal protocol MQTTServiceProtocol: AnyObject {
    func connect(config: MQTTConfiguration, username: String, password: String) async throws
    func disconnect() async
    var skyStream: AsyncStream<SkyMessage> { get }
    var connectionStateStream: AsyncStream<ConnectionState> { get }
}
