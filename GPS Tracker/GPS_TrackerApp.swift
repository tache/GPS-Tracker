//
//  GPS_TrackerApp.swift
//  GPS Tracker
//
//  Created by Christopher Graham on 4/1/26.
//
// Claude Generated: version 1 - App entry point with ModelContainer and service injection
// Claude Generated: version 2 - Wire ConfigurationView into Settings scene
// Claude Generated: version 3 - Use in-memory store when --uitesting flag is present
// Claude Generated: version 4 - Connect on scenePhase active instead of init-time Task

import SwiftUI
import SwiftData

@main
struct GPSTrackerApp: App {

    @Environment(\.scenePhase) private var scenePhase

    private let mqttService = MQTTService()
    private let satelliteStore: SatelliteStore

    private let modelContainer: ModelContainer = {
        let schema = Schema([
            SatelliteHistoryEntry.self,
            MQTTConfiguration.self
        ])
        let isUITesting = CommandLine.arguments.contains("--uitesting")
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isUITesting)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        let store = SatelliteStore(mqttService: mqttService)
        store.configure(modelContext: modelContainer.mainContext)
        satelliteStore = store
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(satelliteStore)
        }
        .modelContainer(modelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active && satelliteStore.connectionState == .disconnected {
                Task { await satelliteStore.connectWithCurrentConfig() }
            }
        }

        Settings {
            ConfigurationView()
                .environment(satelliteStore)
                .modelContainer(modelContainer)
        }
    }
}
