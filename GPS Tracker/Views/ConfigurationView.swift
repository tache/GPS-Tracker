//
//  ConfigurationView.swift
//  GPS Tracker
//
//  Created by Christopher Graham on 4/1/26.
//
// Claude Generated: version 1 - MQTT broker configuration sheet
// Claude Generated: version 2 - Add save error alert and SatelliteStore in preview
// Claude Generated: version 3 - Dismiss on successful save

import SwiftUI
import SwiftData

/// MQTT broker settings sheet. Opened via Cmd+, (Settings scene) or gear toolbar button.
/// Hostname and port are persisted in SwiftData.
/// Username and password are persisted in the macOS Keychain.
/// Saving triggers a reconnect in SatelliteStore.
struct ConfigurationView: View {

    @Environment(SatelliteStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var hostname: String = ""
    @State private var port: String = "8883"
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var saveError: String?

    private var portValue: Int? { Int(port) }
    private var isValid: Bool {
        !hostname.trimmingCharacters(in: .whitespaces).isEmpty
        && (portValue.map { 1...65535 ~= $0 } ?? false)
    }

    var body: some View {
        Form {
            Section("Broker") {
                TextField("Hostname", text: $hostname)
                    .textContentType(.URL)
                TextField("Port", text: $port)
            }
            Section("Authentication (optional)") {
                TextField("Username", text: $username)
                    .textContentType(.username)
                SecureField("Password", text: $password)
                    .textContentType(.password)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 380)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!isValid)
            }
        }
        .onAppear { loadCurrentValues() }
        .alert("Save Failed", isPresented: .init(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(saveError ?? "")
        }
    }

    // MARK: - Private

    private func loadCurrentValues() {
        let config = store.fetchOrCreateConfig(in: modelContext)
        hostname = config.hostname
        port = String(config.port)
        if let creds = KeychainHelper.load() {
            username = creds.username
            password = creds.password
        }
    }

    private func save() {
        let config = store.fetchOrCreateConfig(in: modelContext)
        config.hostname = hostname.trimmingCharacters(in: .whitespaces)
        config.port = portValue ?? 8883
        do {
            try modelContext.save()
        } catch {
            saveError = "Failed to save configuration: \(error.localizedDescription)"
            return
        }
        do {
            try KeychainHelper.save(username: username, password: password)
        } catch {
            saveError = "Failed to save credentials to Keychain: \(error.localizedDescription)"
            return
        }
        Task { await store.reconnect(config: config) }
        dismiss()
    }
}

#Preview {
    ConfigurationView()
        .environment(SatelliteStore(mqttService: MQTTService()))
        .modelContainer(for: [MQTTConfiguration.self, SatelliteHistoryEntry.self],
                        inMemory: true)
}
