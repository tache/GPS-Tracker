//
//  ContentView.swift
//  GPS Tracker
//
//  Created by Christopher Graham on 4/1/26.
//
// Claude Generated: version 1 - Root HStack container with toolbar and slide animation
// Claude Generated: version 2 - Trail toggle cycles off/mono/colored states

import SwiftUI
import SwiftData

/// Root view. PolarGraphView is always visible.
/// SatelliteTableView slides in from the right (side-by-side, not overlay)
/// when the table toggle button is tapped. Window expands to accommodate.
struct ContentView: View {

    @Environment(SatelliteStore.self) private var store
    @Environment(\.modelContext) private var modelContext

    @State private var showConfig = false

    var body: some View {
        HStack(spacing: 0) {
            PolarGraphView()
                .frame(minWidth: 400, minHeight: 400)

            if store.showTable {
                Divider()
                SatelliteTableView()
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.spring(), value: store.showTable)
        .toolbar { toolbarContent }
        .onAppear { handleFirstLaunch() }
        .sheet(isPresented: $showConfig) {
            ConfigurationView()
                .environment(store)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            connectionIndicator
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem {
            Button {
                withAnimation(.spring()) { store.showTable.toggle() }
            } label: {
                Label("Satellites",
                      systemImage: store.showTable ? "list.bullet.circle.fill" : "list.bullet.circle")
            }
        }
        ToolbarItem {
            Button {
                switch store.trailMode {
                case .off:     store.trailMode = .mono
                case .mono:    store.trailMode = .colored
                case .colored: store.trailMode = .off
                }
            } label: {
                Label("Trails", systemImage: trailIcon)
            }
        }
        ToolbarItem {
            Button {
                showConfig = true
            } label: {
                Label("Settings", systemImage: "gear")
            }
        }
    }

    private var trailIcon: String {
        switch store.trailMode {
        case .off:     return "line.diagonal"
        case .mono:    return "line.diagonal.arrow"
        case .colored: return "paintbrush.pointed.fill"
        }
    }

    private var connectionIndicator: some View {
        Image("satellite-connection")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: 20, height: 20)
            .foregroundStyle(connectionColor)
            .background(.clear)
            .help(connectionLabel)
    }

    private var connectionColor: Color {
        switch store.connectionState {
        case .connected:     return .green
        case .connecting:    return .yellow
        case .disconnected:  return .red
        case .error:         return .red
        }
    }

    private var connectionLabel: String {
        switch store.connectionState {
        case .connected:         return "Connected"
        case .connecting:        return "Connecting…"
        case .disconnected:      return "Disconnected"
        case .error(let msg):    return "Error: \(msg)"
        }
    }

    // MARK: - First Launch

    private func handleFirstLaunch() {
        // Show config sheet if no hostname saved yet.
        // Connection is initiated in SatelliteStore.configure() at startup.
        let config = store.fetchOrCreateConfig(in: modelContext)
        if config.hostname.isEmpty {
            showConfig = true
        }
    }
}

#Preview {
    ContentView()
        .environment(SatelliteStore(mqttService: MQTTService()))
        .modelContainer(for: [SatelliteHistoryEntry.self, MQTTConfiguration.self],
                        inMemory: true)
}
