//
//  MenuBarStatusView.swift
//  GPS Tracker
//
//  Created by Christopher Graham on 4/2/26.
//
// Claude Generated: version 1 - Menu bar label with satellite count and receive flash
// Claude Generated: version 2 - Fix icon color (blend mode instead of template rendering); fix open window
// Claude Generated: version 3 - Use Canvas sourceAtop to tint icon; system cannot override flat bitmap
// Claude Generated: version 4 - Replace Canvas with NSViewRepresentable; use NSColor(named:) for asset catalog colors
// Claude Generated: version 5 - Back to simple template image; foregroundStyle on HStack so count text always colors correctly
// Claude Generated: version 6 - Replace custom SVG with SF Symbol; SVG ignores frame constraints in MenuBarExtra label
// Claude Generated: version 7 - Draw SF Symbol into non-template NSImage; NSStatusBarButton cannot override pre-colored pixels
// Claude Generated: version 8 - Simplify to SF Symbol globe; no custom icon

import SwiftUI

// MARK: - Menu Bar Label

/// Globe icon + satellite count shown in the macOS menu bar.
/// Count format: "used|total" e.g. "6|10".
struct MenuBarStatusLabel: View {

  @Environment(SatelliteStore.self) private var store

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: "globe")
      if !store.satellites.isEmpty {
        let used = store.satellites.filter { $0.used }.count
        Text("\(used)|\(store.satellites.count)")
          .font(.system(size: 11, weight: .medium, design: .monospaced))
      }
    }
  }
}

// MARK: - Menu Bar Dropdown

/// Dropdown menu shown when the menu bar item is clicked.
struct MenuBarStatusMenu: View {

  @Environment(SatelliteStore.self) private var store
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Text(statusSummary)
    Divider()
    Button("Open GPS Tracker") {
      openWindow(id: "main")
      NSApp.activate(ignoringOtherApps: true)
    }
  }

  private var statusSummary: String {
    switch store.connectionState {
    case .connected:
      let used = store.satellites.filter { $0.used }.count
      let total = store.satellites.count
      return total == 0 ? "Connected — awaiting data" : "\(used) of \(total) satellites in use"
    case .connecting:
      return "Connecting…"
    case .disconnected:
      return "Disconnected"
    case .error(let msg):
      return "Error: \(msg)"
    }
  }
}
