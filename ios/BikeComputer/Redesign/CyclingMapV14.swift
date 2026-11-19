import SwiftUI
import Combine
import CoreLocation

// Training Hub v1.4 — the cycling recorder's Map view (design sheet 05a C2): the route recorded so far and the current
// position, with the same recording's time, distance and power over it.
//
// WHAT IS DRAWN
// • Redesigned main app: the existing route map (`RideRouteMap`, Ride/RideViews.swift) with the coordinates the ride
//   recorder has stored for this ride. This file reads coordinates it is handed; it owns no location manager and never
//   asks for location. The map is drawn without the system's own "my location" dot, so MapKit has no reason to ask.
// • Cyclift Lab: NOTHING is drawn. Lab has no location, so there is no route; the view says so. No schematic or sample
//   route stands in for it (the sheet shows none for a ride without location). As a second guard the `.route` case is
//   compiled out of Lab: even if Lab were handed coordinates, no MapKit view would be created.

/// The wording for a ride that has no place to draw.
enum CyclingMapCopy {
    static let labTitle = "No map in this demonstration"
    static let labDetail = "Location is not used in Cyclift Lab, so there is no route to draw. Nothing is drawn in its place."
    static let offTitle = "No location for this ride"
    static let offDetail = "The phone's location is not in use, so no route is being drawn."
    static let waitingTitle = "Waiting for GPS"
    static let waitingDetail = "The route appears with the first recorded position."
    static let idleTitle = "No route yet"
    static let idleDetail = "The route is drawn from the positions recorded during the ride."
    static let lostBanner = "GPS signal lost · the route holds until it returns"
}

enum CyclingMapContent {
    /// Nothing can be drawn; say why.
    case unavailable(title: String, detail: String)
    /// The recorded route, oldest first; the last point is the current position. Main app only.
    case route(points: [CLLocationCoordinate2D], gps: RideGPSState)
}

struct CyclingMapV14: View {
    let content: CyclingMapContent
    let tiles: [CyclingMapTile]
    @Environment(\.cyTheme) private var theme

    var body: some View {
        ZStack(alignment: .bottom) {
            canvas
            tileRow.padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous).strokeBorder(theme.cardStroke, lineWidth: 1))
    }

    private var canvas: AnyView {
        switch content {
        case .unavailable(let t, let d): return AnyView(unavailable(t, d))
        case .route(let points, let gps): return routeCanvas(points, gps)
        }
    }

    #if CYCLIFT_LAB
    /// Cyclift Lab never creates a map view, whatever it is handed.
    private func routeCanvas(_ points: [CLLocationCoordinate2D], _ gps: RideGPSState) -> AnyView {
        AnyView(unavailable(CyclingMapCopy.labTitle, CyclingMapCopy.labDetail))
    }
    #else
    private func routeCanvas(_ points: [CLLocationCoordinate2D], _ gps: RideGPSState) -> AnyView {
        guard !points.isEmpty else {
            switch gps {
            case .off: return AnyView(unavailable(CyclingMapCopy.offTitle, CyclingMapCopy.offDetail))
            case .searching, .lost: return AnyView(unavailable(CyclingMapCopy.waitingTitle, CyclingMapCopy.waitingDetail))
            case .good: return AnyView(unavailable(CyclingMapCopy.idleTitle, CyclingMapCopy.idleDetail))
            }
        }
        return AnyView(liveMap(points, gps))
    }
    private func liveMap(_ points: [CLLocationCoordinate2D], _ gps: RideGPSState) -> some View {
        ZStack(alignment: .top) {
            RideRouteMap(coords: points, interactive: false, gps: gps)
            if gps == .lost {
                Text(CyclingMapCopy.lostBanner).font(CyFont.caption).foregroundStyle(theme.textPrimary)
                    .padding(.horizontal, CySpace.m).padding(.vertical, CySpace.s)
                    .background(RoundedRectangle(cornerRadius: CyRadius.s, style: .continuous).fill(theme.surface2))
                    .padding(10)
                    .accessibilityIdentifier("cyclingMapGPSLost")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cyclingMapLive")
    }
    #endif

    private func unavailable(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: CySpace.s) {
            Image(systemName: "location.slash").font(.system(size: 22, weight: .semibold)).foregroundStyle(theme.textSecondary).accessibilityHidden(true)
            Text(title).font(CyFont.title).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
            Text(detail).font(CyFont.callout).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(CySpace.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.surface)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("cyclingMapUnavailable")
    }

    /// Sheet 05a C2: TIME · KM · POWER over the bottom of the map — the same recording, three values.
    private var tileRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(tiles.enumerated()), id: \.offset) { pair in tile(pair.element) }
        }
        .padding(.vertical, CySpace.s)
        .background(RoundedRectangle(cornerRadius: CyRadius.s, style: .continuous).fill(theme.surface2))
        .overlay(RoundedRectangle(cornerRadius: CyRadius.s, style: .continuous).strokeBorder(theme.cardStroke, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cyclingMapTiles")
    }
    private func tile(_ t: CyclingMapTile) -> some View {
        VStack(spacing: 1) {
            Text(t.label).font(CyFont.overline).tracking(1.2).foregroundStyle(theme.textSecondary)
            Text(t.value).font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(theme.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("cyclingMapTile-\(t.label)")
    }
}

// MARK: - Minimise (sheet 05b C7–C9): the value only

/// Holds the one small value a minimised ride would show on the Train ball: elapsed seconds, paused, simulated.
/// The cycling screen publishes it while a ride is recording or paused and clears it when the ride ends.
///
/// Minimising a ride is BLOCKED by the cycling safety gate (sheet 05b, sheet 08 column 3), so nothing reads this and no
/// control minimises the screen. When the gate is passed the dock can observe it with one line:
///     @ObservedObject private var cyclingMini = CyclingMinimise.shared      // then: cyclingMini.state?.label
final class CyclingMinimise: ObservableObject {
    static let shared = CyclingMinimise()
    @Published private(set) var state: CyclingMiniState?
    func set(_ s: CyclingMiniState?) { if state != s { state = s } }
}
