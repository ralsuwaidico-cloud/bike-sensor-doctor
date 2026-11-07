import SwiftUI
import MapKit
import CoreLocation

/// Checkpoint F (owner-approved Ride prototype, 7 Nov 2026): the three adaptive ride views that replace the five
/// manual layouts. Cockpit = lead metric + zone rail + tiles + mini map; Map = full-screen Apple Maps with the route
/// so far and the essentials over it; Performance = trends, time in zones, interval target vs actual, rolling averages.
/// Switching views only changes `RideTabView.view`; the recorder, the hub and the coach are untouched (RA-15).
enum RideViewKind: String, CaseIterable, Identifiable {
    case cockpit, map, performance
    var id: String { rawValue }
    var title: String { switch self { case .cockpit: return "Cockpit"; case .map: return "Map"; case .performance: return "Performance" } }
}

struct RideViewSwitcher: View {
    @Binding var selection: RideViewKind
    var body: some View {
        HStack(spacing: 4) {
            ForEach(RideViewKind.allCases) { k in
                Button { withAnimation(.easeInOut(duration: 0.15)) { selection = k } } label: {
                    Text(k.title).font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(selection == k ? D7.ink : D7.fg)
                        .frame(minHeight: 36).padding(.horizontal, 14)
                        .background(selection == k ? D7.fg : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("rideView.\(k.rawValue)")
                .accessibilityAddTraits(selection == k ? [.isSelected] : [])
            }
        }
        .padding(3).background(D7.panel, in: Capsule())
        .accessibilityElement(children: .contain).accessibilityLabel("Ride view")
    }
}

// MARK: - Cockpit

struct RideCockpitView: View {
    let model: RideCockpitModel
    let steps: [RideStep]
    var stepFTP: Int? = nil
    var stepHRZones: [(lo: Int, hi: Int?)]? = nil
    let elapsedS: Int
    let coords: [CLLocationCoordinate2D]
    let gps: RideGPSState
    let routeLine: String
    let paused: Bool
    var onExpandMap: () -> Void

    var body: some View {
        VStack(spacing: D7.gap + 2) {
            if !steps.isEmpty { RideStepCard(steps: steps, elapsedS: elapsedS, ftp: stepFTP, hrZones: stepHRZones) }
            lead
            tiles
            miniMap
        }
    }
    private var lead: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.lead.label).font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(0.8).foregroundStyle(D7.mut)
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text(model.lead.value).font(.system(size: 72, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(paused ? D7.mut : D7.fg)
                            .lineLimit(1).minimumScaleFactor(0.85)
                        Text(model.lead.unit).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(D7.mut)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    Text("TARGET").font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(0.8).foregroundStyle(D7.mut)
                    Text(model.lead.target).font(.system(size: model.lead.targetKnown ? 17 : 14, weight: .bold, design: .rounded)).foregroundStyle(model.lead.targetKnown ? D7.green : D7.fg)
                        .multilineTextAlignment(.trailing).lineLimit(2).minimumScaleFactor(0.85)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(model.lead.label.capitalized) \(model.lead.value) \(model.lead.unit), target \(model.lead.target)")
            if model.zonesShown, let pos = model.railPosition { RideZoneRail(position: pos) }
            if let n = model.zoneNote { Text(n).font(.system(size: 12)).foregroundStyle(D7.mut).fixedSize(horizontal: false, vertical: true) }
        }
    }
    private var tiles: some View {
        HStack(spacing: 8) {
            ForEach(model.tiles, id: \.key) { t in
                VStack(alignment: .leading, spacing: 0) {
                    Text(t.label).font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(0.6).foregroundStyle(D7.mut).lineLimit(1).minimumScaleFactor(0.85)
                    HStack(alignment: .lastTextBaseline, spacing: 3) {
                        Text(t.value).font(.system(size: 23, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(D7.fg).lineLimit(1).minimumScaleFactor(0.85)
                        if !t.unit.isEmpty { Text(t.unit).font(.system(size: 12, weight: .semibold)).foregroundStyle(D7.mut) }
                    }
                    Text(t.note).font(.system(size: 11.5)).foregroundStyle(t.note.contains("lost") ? D7.amber : D7.mut).lineLimit(1).minimumScaleFactor(0.85)
                }
                .padding(.horizontal, 10).padding(.vertical, 7).frame(maxWidth: .infinity, alignment: .leading)
                .background(D7.panel, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityElement(children: .combine).accessibilityLabel("\(t.label.capitalized) \(t.value) \(t.unit), \(t.note)")
            }
        }
    }
    private var miniMap: some View {
        Button(action: onExpandMap) {
            ZStack(alignment: .topLeading) {
                RideRouteMap(coords: coords, interactive: false, gps: gps).allowsHitTesting(false)
                Text(routeLine).font(.system(size: 11, weight: .bold, design: .monospaced)).foregroundStyle(D7.fg)
                    .padding(.horizontal, 8).padding(.vertical, 3).background(D7.panel.opacity(0.85), in: RoundedRectangle(cornerRadius: 8)).padding(8)
                VStack { Spacer(); HStack { Spacer(); Text("Expand").font(.system(size: 12, weight: .bold)).foregroundStyle(D7.cyan).padding(.horizontal, 8).padding(.vertical, 3).background(D7.panel.opacity(0.85), in: RoundedRectangle(cornerRadius: 8)) } }.padding(8)
            }
            .frame(maxWidth: .infinity, minHeight: 90).frame(maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Map: \(routeLine). Opens the Map view").accessibilityIdentifier("rideMiniMap")
    }
}

/// Compact step card: current step, time left, the step bar, the next step (RA-08).
struct RideStepCard: View {
    let steps: [RideStep]; let elapsedS: Int
    /// For the step target line and its accessibility label: watts only with a known FTP (never from an assumed one).
    var ftp: Int? = nil
    var hrZones: [(lo: Int, hi: Int?)]? = nil
    var body: some View {
        if let p = RideStepStrip.position(steps, at: elapsedS) {
            let s = steps[p.index]
            let next = p.index + 1 < steps.count ? steps[p.index + 1] : nil
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(s.name).font(.system(size: 14.5, weight: .bold, design: .rounded)).foregroundStyle(D7.fg).lineLimit(1).minimumScaleFactor(0.85)
                    if let z = s.hrZone { Text("· Zone \(z)").font(.system(size: 14.5, weight: .bold, design: .rounded)).foregroundStyle(D7.green) }
                    Spacer()
                    Text(RideCockpitModel.clock(p.left)).font(.system(size: 14.5, weight: .bold, design: .monospaced)).foregroundStyle(D7.fg)
                    Text("LEFT").font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(D7.mut)
                }
                GeometryReader { g in
                    HStack(spacing: 2) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { i, st in
                            Capsule().fill(D7.hrZoneColors[min(4, max(0, (st.hrZone ?? 1) - 1))].opacity(i < p.index ? 0.35 : i == p.index ? 1 : 0.55))
                                .frame(width: max(2, g.size.width * CGFloat(st.minutes) / CGFloat(max(1, steps.reduce(0) { $0 + $1.minutes })) - 2))
                        }
                    }
                }.frame(height: 5)
                HStack(spacing: 6) {
                    Text(s.targetText(ftp: ftp, hrZones: hrZones)).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(D7.fg).lineLimit(1).minimumScaleFactor(0.85).accessibilityIdentifier("rideStepTarget")
                    Spacer(minLength: 4)
                    if let n = next { Text("Next: \(n.name) · \(n.minutes) min").font(.system(size: 12.5)).foregroundStyle(D7.mut).lineLimit(1).minimumScaleFactor(0.85) }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8).background(D7.panel, in: RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(s.name): \(s.targetText(ftp: ftp, hrZones: hrZones)), \(RideCockpitModel.clock(p.left)) left" + (next.map { ", next \($0.name)" } ?? ""))
            .accessibilityIdentifier("rideStepStrip")
        } else {
            Text("Workout complete — ride on or end when ready").font(.system(size: 13, weight: .semibold)).foregroundStyle(D7.mut)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).padding(.vertical, 10).background(D7.panel, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

/// Z1…Z5 rail with the current position marker; the target zone is the bright segment.
struct RideZoneRail: View {
    let position: Double
    var body: some View {
        VStack(spacing: 2) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    HStack(spacing: 2) { ForEach(0..<5, id: \.self) { i in RoundedRectangle(cornerRadius: 3).fill(D7.hrZoneColors[i].opacity(0.55)).frame(maxWidth: .infinity) } }.frame(height: 6).padding(.vertical, 4)
                    RoundedRectangle(cornerRadius: 2).fill(D7.fg).frame(width: 4, height: 14).offset(x: max(0, min(g.size.width - 4, g.size.width * position - 2)))
                }
            }.frame(height: 14)
            HStack { ForEach(1...5, id: \.self) { z in Text("Z\(z)").font(.system(size: 11, design: .monospaced)).foregroundStyle(D7.mut); if z < 5 { Spacer() } } }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Map

/// Apple Maps with the route so far (polyline) and the live position. `interactive` false = the mini map (no gestures).
/// Offline: MapKit shows whatever tiles it has cached; the polyline is always drawn (RA-18). GPS lost: hollow marker.
struct RideRouteMap: View {
    let coords: [CLLocationCoordinate2D]
    let interactive: Bool
    let gps: RideGPSState
    @State private var camera: MapCameraPosition = .automatic
    var body: some View {
        Map(position: $camera, interactionModes: interactive ? .all : []) {
            if coords.count >= 2 { MapPolyline(coordinates: coords).stroke(D7.cyan, lineWidth: 5) }
            if let last = coords.last {
                Annotation("", coordinate: last) {
                    Circle().fill(gps == .lost ? Color.clear : D7.cyan).stroke(gps == .lost ? D7.amber : D7.bg, lineWidth: 3).frame(width: 16, height: 16)
                }
            }
            if interactive { UserAnnotation() }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
        .onChange(of: coords.count) { _, _ in if !interactive, let last = coords.last { camera = .region(MKCoordinateRegion(center: last, latitudinalMeters: 1200, longitudinalMeters: 1200)) } }
        .onAppear { if let last = coords.last { camera = .region(MKCoordinateRegion(center: last, latitudinalMeters: interactive ? 2500 : 1200, longitudinalMeters: interactive ? 2500 : 1200)) } }
        .accessibilityHidden(true)
    }
}

struct RideMapView: View {
    let coords: [CLLocationCoordinate2D]
    let gps: RideGPSState
    let tiles: [RideCockpitModel.Tile]
    var body: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                ForEach(tiles.prefix(3), id: \.key) { t in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(t.label).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(D7.mut).lineLimit(1).minimumScaleFactor(0.85)
                        HStack(alignment: .lastTextBaseline, spacing: 3) {
                            Text(t.value).font(.system(size: 23, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(D7.fg).lineLimit(1).minimumScaleFactor(0.85)
                            if !t.unit.isEmpty { Text(t.unit).font(.system(size: 12, weight: .semibold)).foregroundStyle(D7.mut) }
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7).frame(maxWidth: .infinity, alignment: .leading)
                    .background(D7.panel.opacity(0.88), in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityElement(children: .combine).accessibilityLabel("\(t.label.capitalized) \(t.value) \(t.unit)")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(alignment: .center) { RideRouteMap(coords: coords, interactive: true, gps: gps).clipShape(RoundedRectangle(cornerRadius: 18)) }
        .accessibilityIdentifier("rideMapView")
    }
}

// MARK: - Performance

struct RidePerformanceView: View {
    let model: RidePerformanceModel
    let steps: [RideStep]
    var body: some View {
        VStack(spacing: 8) {
            trends
            rolling
            if !model.zoneSeconds.isEmpty { zones }
            intervals
        }
    }
    private var trends: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text("Trends · last 20 min").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(D7.fg); Spacer(); Text(model.series.map { $0.key.uppercased() }.joined(separator: " · ")).font(.system(size: 11, design: .monospaced)).foregroundStyle(D7.mut) }
            if model.series.isEmpty { Text("No live sensor yet: trends appear as samples arrive.").font(.system(size: 12.5)).foregroundStyle(D7.mut) }
            else { RideTrendChart(series: model.series).frame(height: 84) }
        }
        .padding(12).background(D7.panel, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine).accessibilityLabel("Trends for the last 20 minutes: " + model.series.map(\.key).joined(separator: ", "))
    }
    private var rolling: some View {
        HStack(spacing: 6) {
            ForEach(model.rolling, id: \.key) { r in
                VStack(alignment: .leading, spacing: 0) {
                    Text(r.label).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(D7.mut).lineLimit(1).minimumScaleFactor(0.85)
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(r.value).font(.system(size: 18, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(D7.fg).lineLimit(1).minimumScaleFactor(0.85)
                        Text(r.unit).font(.system(size: 11, weight: .semibold)).foregroundStyle(D7.mut)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading).background(D7.panel, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .combine).accessibilityLabel("\(r.label.capitalized) \(r.value) \(r.unit)")
            }
        }
    }
    private var zones: some View {
        let total = max(1, model.zoneSeconds.reduce(0, +))
        return VStack(alignment: .leading, spacing: 6) {
            HStack { Text("Time in zones").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(D7.fg); Spacer(); Text(model.zoneBasis ?? "").font(.system(size: 11, design: .monospaced)).foregroundStyle(D7.mut) }
            GeometryReader { g in
                HStack(spacing: 2) { ForEach(0..<5, id: \.self) { i in RoundedRectangle(cornerRadius: 3).fill(D7.hrZoneColors[i]).frame(width: max(2, g.size.width * CGFloat(model.zoneSeconds[i]) / CGFloat(total) - 2)) } }
            }.frame(height: 10)
            HStack { ForEach(0..<5, id: \.self) { i in Text("Z\(i + 1) \(model.zoneSeconds[i] / 60)m").font(.system(size: 11, design: .monospaced)).foregroundStyle(D7.mut); if i < 4 { Spacer() } } }
        }
        .padding(12).background(D7.panel, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine).accessibilityLabel("Time in zones: " + (0..<5).map { "zone \($0 + 1) \(model.zoneSeconds[$0] / 60) minutes" }.joined(separator: ", "))
    }
    private var intervals: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text("Intervals · target vs actual").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(D7.fg); Spacer() }
            if model.intervals.isEmpty { Text("Free ride: no planned steps.").font(.system(size: 12.5)).foregroundStyle(D7.mut) }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(Array(model.intervals.enumerated()), id: \.offset) { i, r in
                        HStack(spacing: 8) {
                            Circle().fill(D7.hrZoneColors[min(4, max(0, (steps.indices.contains(i) ? (steps[i].hrZone ?? 1) : 1) - 1))]).frame(width: 8, height: 8)
                            Text(r.name).font(.system(size: 13)).foregroundStyle(r.done ? D7.fg : D7.mut).lineLimit(1).minimumScaleFactor(0.85)
                            Spacer(minLength: 6)
                            Text(r.target).font(.system(size: 13, design: .monospaced)).foregroundStyle(D7.mut).lineLimit(1).minimumScaleFactor(0.85)
                            Text(r.actual).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(r.inBand == false ? D7.amber : r.inBand == true ? D7.green : D7.fg).frame(minWidth: 64, alignment: .trailing).lineLimit(1).minimumScaleFactor(0.85)
                        }
                        .frame(minHeight: 24)
                        .accessibilityElement(children: .combine).accessibilityLabel("\(r.name), target \(r.target), actual \(r.actual)")
                    }
                }
            }
        }
        .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(D7.panel, in: RoundedRectangle(cornerRadius: 16))
    }
}

/// Lines for every series, each scaled to its own range so shapes stay readable; no axis labels (the rolling tiles carry the numbers).
struct RideTrendChart: View {
    let series: [RidePerformanceModel.Series]
    private func color(_ k: String) -> Color { switch k { case "power": return D7.fg; case "hr": return D7.red; case "cad": return D7.violet; default: return D7.cyan } }
    var body: some View {
        Canvas { ctx, size in
            for s in series {
                let vals = s.points.compactMap { $0 }
                guard let lo = vals.min(), let hi = vals.max(), s.points.count > 1 else { continue }
                let span = max(1, hi - lo)
                var p = Path(); var pen = false
                for (i, v) in s.points.enumerated() {
                    let x = size.width * CGFloat(i) / CGFloat(s.points.count - 1)
                    guard let v else { pen = false; continue }
                    let y = size.height - 6 - (size.height - 12) * CGFloat((v - lo) / span)
                    if pen { p.addLine(to: CGPoint(x: x, y: y)) } else { p.move(to: CGPoint(x: x, y: y)); pen = true }
                }
                ctx.stroke(p, with: .color(color(s.key)), lineWidth: s.key == "power" ? 2 : 1.5)
            }
        }
        .accessibilityHidden(true)
    }
}
