//
//  PolarGraphView.swift
//  GPS Tracker
//
//  Created by Christopher Graham on 4/1/26.
//
// Claude Generated: version 1 - Canvas-based satellite polar sky view
// Claude Generated: version 2 - Fix trail segment opacity to fade per-segment not per-path
// Claude Generated: version 3 - Only draw trails for satellites currently in view
// Claude Generated: version 4 - Support mono and SNR-colored trail modes
// Claude Generated: version 5 - Manual trail history fetch (avoids @Query memory overhead)
// Claude Generated: version 6 - Debounce trail fetches to 2-second timer to prevent malloc corruption

import SwiftData
import SwiftUI

/// Polar sky graph showing satellite positions.
/// Center = zenith (90° elevation), rim = horizon (0°), north at top.
/// Satellites are drawn as solid filled circles (used) or stroked outlines (!used),
/// colored by SatelliteColor. Trails currently disabled due to SwiftData memory overhead.
struct PolarGraphView: View {

  @Environment(SatelliteStore.self) private var store
  @Environment(\.modelContext) private var modelContext
  @State private var trailHistory: [SatelliteHistoryEntry] = []
  @State private var trailFetchTimer: Timer?

  var body: some View {
    GeometryReader { geo in
      let size = min(geo.size.width, geo.size.height)
      let radius = size * 0.45
      let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

      Canvas { ctx, _ in
        drawGrid(ctx: ctx, center: center, radius: radius)
        drawCardinals(ctx: ctx, center: center, radius: radius)
        if store.trailMode != .off {
          drawTrails(
            ctx: ctx,
            center: center,
            radius: radius,
            colored: store.trailMode == .colored
          )
        }
        drawSatellites(ctx: ctx, center: center, radius: radius)
      }
      .overlay {
        if store.satellites.isEmpty {
          Text("No satellite data")
            .foregroundStyle(.secondary)
        }
      }
    }
    .aspectRatio(1, contentMode: .fit)
    .padding()
    .onAppear { startTrailFetchTimer() }
    .onDisappear { stopTrailFetchTimer() }
  }

  /// Start timer-based trail history fetching (every 2 seconds).
  /// Prevents excessive database access that causes malloc corruption.
  private func startTrailFetchTimer() {
    stopTrailFetchTimer()
    trailFetchTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
      fetchTrailHistory()
    }
    // Fetch immediately on startup
    fetchTrailHistory()
  }

  /// Stop trail fetch timer when view disappears.
  private func stopTrailFetchTimer() {
    trailFetchTimer?.invalidate()
    trailFetchTimer = nil
  }

  /// Fetch trail history manually to avoid @Query memory overhead.
  /// Only fetches last 2 hours of data at database level.
  /// Called periodically by timer (not on every satellite update) to prevent
  /// rapid-fire database access that corrupts SwiftData's ModelContext.
  private func fetchTrailHistory() {
    let twoHoursAgo = Date().addingTimeInterval(-7200)
    var descriptor = FetchDescriptor<SatelliteHistoryEntry>(
      predicate: #Predicate { $0.timestamp > twoHoursAgo },
      sortBy: [SortDescriptor(\.timestamp)]
    )
    descriptor.fetchLimit = 10000 // Safety limit

    // Fetch on main thread (ModelContext is not thread-safe)
    if let entries = try? modelContext.fetch(descriptor) {
      trailHistory = entries
    }
  }

  // MARK: - Coordinate Math

  private func polarPoint(
    elevation: Int,
    azimuth: Int,
    center: CGPoint,
    radius: CGFloat
  ) -> CGPoint {
    let dist = (1.0 - Double(elevation) / 90.0) * Double(radius)
    let azRad = Double(azimuth) * .pi / 180.0
    return CGPoint(
      x: center.x + dist * sin(azRad),
      y: center.y - dist * cos(azRad)
    )
  }

  // MARK: - Drawing

  private func drawGrid(ctx: GraphicsContext, center: CGPoint, radius: CGFloat) {
    // Outer circle (background)
    let bgRect = CGRect(
      x: center.x - radius,
      y: center.y - radius,
      width: radius * 2,
      height: radius * 2
    )
    ctx.fill(Path(ellipseIn: bgRect), with: .color(.secondary.opacity(0.08)))

    // Elevation rings at 0° (rim), 30°, 60°, 90° (center dot)
    for elevation in [0, 30, 60] {
      let rimPoint = polarPoint(elevation: elevation, azimuth: 0, center: center, radius: radius)
      let ringRadius = abs(center.y - rimPoint.y)
      let rect = CGRect(
        x: center.x - ringRadius,
        y: center.y - ringRadius,
        width: ringRadius * 2,
        height: ringRadius * 2
      )
      ctx.stroke(Path(ellipseIn: rect), with: .color(.secondary.opacity(0.3)), lineWidth: 0.5)
    }
  }

  private func drawCardinals(ctx: GraphicsContext, center: CGPoint, radius: CGFloat) {
    let labels: [(String, Int)] = [("N", 0), ("E", 90), ("S", 180), ("W", 270)]
    for (label, azimuth) in labels {
      var labelPoint = polarPoint(elevation: 0, azimuth: azimuth, center: center, radius: radius)
      // Offset label slightly outside the rim
      let labelOffset: CGFloat = 14
      let azRad = Double(azimuth) * .pi / 180.0
      labelPoint.x += labelOffset * sin(azRad)
      labelPoint.y -= labelOffset * cos(azRad)
      ctx.draw(
        Text(label).font(.caption2).foregroundStyle(.secondary),
        at: labelPoint
      )
    }
  }

  private func drawTrails(
    ctx: GraphicsContext,
    center: CGPoint,
    radius: CGFloat,
    colored: Bool
  ) {
    // Only draw trails for satellites currently in view
    let visiblePRNs = Set(store.satellites.map { $0.prn })

    // Group history by PRN
    var byPrn: [Int: [SatelliteHistoryEntry]] = [:]
    for entry in trailHistory where visiblePRNs.contains(entry.prn) {
      byPrn[entry.prn, default: []].append(entry)
    }

    let now = Date()
    for (_, entries) in byPrn {
      guard entries.count > 1 else { continue }
      for idx in 1..<entries.count {
        let prev = entries[idx - 1]
        let curr = entries[idx]
        let from = polarPoint(
          elevation: prev.elevation,
          azimuth: prev.azimuth,
          center: center,
          radius: radius
        )
        let to = polarPoint(
          elevation: curr.elevation,
          azimuth: curr.azimuth,
          center: center,
          radius: radius
        )
        let ageSecs = now.timeIntervalSince(curr.timestamp)
        let opacity = max(0.2, 1.0 - (ageSecs / 86400.0))
        let segmentColor =
          colored
          ? snrColor(for: curr).opacity(opacity)
          : Color.secondary.opacity(opacity)
        var segment = Path()
        segment.move(to: from)
        segment.addLine(to: to)
        ctx.stroke(segment, with: .color(segmentColor), lineWidth: 1)
      }
    }
  }

  /// Derives a trail color from a history entry's SNR and used flag,
  /// matching the same rules as Satellite.color.
  private func snrColor(for entry: SatelliteHistoryEntry) -> Color {
    guard entry.used else { return .red }
    if entry.snr >= 35 { return .green }
    if entry.snr >= 20 { return .orange }
    return .yellow
  }

  private func drawSatellites(ctx: GraphicsContext, center: CGPoint, radius: CGFloat) {
    let dotRadius: CGFloat = 6

    for sat in store.satellites {
      let point = polarPoint(
        elevation: sat.elevation,
        azimuth: sat.azimuth,
        center: center,
        radius: radius
      )
      let rect = CGRect(
        x: point.x - dotRadius,
        y: point.y - dotRadius,
        width: dotRadius * 2,
        height: dotRadius * 2
      )
      let color = swiftUIColor(for: sat.color)

      if sat.used {
        ctx.fill(Path(ellipseIn: rect), with: .color(color))
      } else {
        ctx.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: 1.5)
      }

      // PRN label
      ctx.draw(
        Text("\(sat.prn)").font(.system(size: 11)).foregroundStyle(.secondary),
        at: CGPoint(x: point.x + dotRadius + 7, y: point.y)
      )
    }
  }

  private func swiftUIColor(for color: SatelliteColor) -> Color {
    switch color {
    case .red: return .red
    case .green: return .green
    case .orange: return .orange
    case .yellow: return .yellow
    }
  }
}

#Preview {
  PolarGraphView()
    .environment(SatelliteStore(mqttService: MQTTService()))
}
