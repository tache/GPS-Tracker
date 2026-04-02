//
//  SatelliteTableView.swift
//  GPS Tracker
//
//  Created by Christopher Graham on 4/1/26.
//
// Claude Generated: version 1 - Slide-out satellite data table sorted by SNR

import SwiftUI

/// Displays all current satellites in a sortable table.
/// Slides in side-by-side with PolarGraphView when toggled.
/// Row text is colored by SatelliteColor (same logic as polar graph dots).
/// Default sort: SNR descending. User can click column headers to re-sort.
struct SatelliteTableView: View {

    @Environment(SatelliteStore.self) private var store
    @State private var sortOrder = [KeyPathComparator(\Satellite.snr, order: .reverse)]

    private var sortedSatellites: [Satellite] {
        store.satellites.sorted(using: sortOrder)
    }

    var body: some View {
        Group {
            if store.satellites.isEmpty {
                ContentUnavailableView("No Satellites in View",
                                       systemImage: "antenna.radiowaves.left.and.right",
                                       description: Text("Waiting for satellite data"))
            } else {
                Table(sortedSatellites, sortOrder: $sortOrder) {
                    TableColumn("PRN", value: \.prn) { sat in
                        Text("\(sat.prn)").foregroundStyle(color(for: sat))
                    }
                    TableColumn("El", value: \.elevation) { sat in
                        Text("\(sat.elevation)°").foregroundStyle(color(for: sat))
                    }
                    TableColumn("Az", value: \.azimuth) { sat in
                        Text("\(sat.azimuth)°").foregroundStyle(color(for: sat))
                    }
                    TableColumn("SNR", value: \.snr) { sat in
                        Text("\(sat.snr)").foregroundStyle(color(for: sat))
                    }
                    TableColumn("Used") { sat in
                        Text(sat.used ? "Yes" : "No").foregroundStyle(color(for: sat))
                    }
                    TableColumn("Seen", value: \.seen) { sat in
                        Text("\(sat.seen)s").foregroundStyle(color(for: sat))
                    }
                }
            }
        }
        .frame(minWidth: 380)
    }

    private func color(for sat: Satellite) -> Color {
        switch sat.color {
        case .red:    return .red
        case .green:  return .green
        case .orange: return .orange
        case .yellow: return .yellow
        }
    }
}

#Preview {
    SatelliteTableView()
        .environment(SatelliteStore(mqttService: MQTTService()))
}
