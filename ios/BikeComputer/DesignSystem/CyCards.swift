import SwiftUI

// MARK: - Cyclift design system: composite cards and the tab bar

/// Metric tile: label with icon, big value, unit, sub-line, optional mini chart, honesty tag. `value == nil` renders
/// the unknown state ("—") and the tag says why — nothing is guessed.
struct CyMetricTile<Chart: View>: View {
    let title: String
    var systemImage: String? = nil
    var sport: CySport? = nil
    let value: String?
    var unit: String? = nil
    var sub: String? = nil
    let tag: SourceTag
    @ViewBuilder var chart: Chart

    var body: some View {
        let id = sport.map { CyTheme.identity($0) }
        let fg = id?.tint ?? CyTheme.ink
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(title).font(CyType.secondary.weight(.semibold)).foregroundStyle(fg).lineLimit(1)
                Spacer(minLength: 4)
                if let s = systemImage { Image(systemName: s).font(.body.weight(.semibold)).foregroundStyle(fg).accessibilityHidden(true) }
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value ?? "—").font(CyType.numeral).monospacedDigit().foregroundStyle(value == nil ? fg.opacity(0.5) : fg).lineLimit(1).minimumScaleFactor(0.6)
                if let u = unit, value != nil { Text(u).font(CyType.unit).foregroundStyle(fg.opacity(0.8)) }
            }
            if let s = sub { Text(s).font(CyType.captionSmall).foregroundStyle(fg.opacity(0.85)).lineLimit(2).fixedSize(horizontal: false, vertical: true) }
            chart.frame(maxWidth: .infinity).padding(.top, 2)
            CySourceTagBadge(tag: tag)
        }
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .padding(14)
        .cyCard(tinted: id?.bg)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value.map { "\($0) \(unit ?? "")" } ?? "unknown"), \(tag.spoken)\(sub.map { ", \($0)" } ?? "")")
    }
}

extension CyMetricTile where Chart == EmptyView {
    init(title: String, systemImage: String? = nil, sport: CySport? = nil, value: String?, unit: String? = nil, sub: String? = nil, tag: SourceTag) {
        self.init(title: title, systemImage: systemImage, sport: sport, value: value, unit: unit, sub: sub, tag: tag) { EmptyView() }
    }
}

/// Weekly hero card: title, sport split, progress ring (done ÷ planned).
struct CyHeroRingCard: View {
    let caption: String
    let title: String
    let done: Int
    let planned: Int
    var ridesDone: Int? = nil
    var ridesPlanned: Int? = nil
    var liftsDone: Int? = nil
    var liftsPlanned: Int? = nil
    @Environment(\.dynamicTypeSize) private var type
    var body: some View {
        let f = CyDesign.ringFraction(done: done, planned: planned)
        let id = CyTheme.recovery
        let text = VStack(alignment: .leading, spacing: 4) {
            CyCaption(text: caption, color: id.tint.opacity(0.85))
            Text(title).font(CyType.title).foregroundStyle(id.tint).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                if let rd = ridesDone, let rp = ridesPlanned { split("bicycle", "\(rd)/\(rp) rides") }
                if let ld = liftsDone, let lp = liftsPlanned { split("dumbbell", "\(ld)/\(lp) lifts") }
            }
        }
        let ring = CyProgressRing(fraction: f, size: 76, lineWidth: 9, tint: id.tint, track: id.soft) {
            CyRingLabel(fraction: f, caption: "\(done) of \(planned)", tint: id.tint)
        }
        Group {
            if type.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) { text; ring }
            } else {
                HStack(spacing: 14) { text.frame(maxWidth: .infinity, alignment: .leading); ring }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cyCard(tinted: id.bg, radius: CyTheme.rHero)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(caption). \(title). \(done) of \(planned) sessions, \(CyDesign.percentText(f))")
        .accessibilityIdentifier("cyHeroRing")
    }
    private func split(_ icon: String, _ t: String) -> some View {
        HStack(spacing: 4) { Image(systemName: icon).font(.caption.weight(.semibold)); Text(t).font(CyType.captionSmall) }.foregroundStyle(CyTheme.recovery.tint.opacity(0.9))
    }
}

/// Session card: sport-tinted, title, meta line, one primary action.
struct CySessionCard: View {
    let sport: CySport
    var caption: String = "Today"
    let title: String
    var meta: String? = nil
    var detail: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    var onOpen: (() -> Void)? = nil
    var body: some View {
        let id = CyTheme.identity(sport)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                CyIconBox(systemName: sport.icon, sport: sport)
                VStack(alignment: .leading, spacing: 2) {
                    CyCaption(text: caption, color: id.tint.opacity(0.85))
                    Text(title).font(CyType.section).foregroundStyle(id.tint).lineLimit(2)
                    if let m = meta { Text(m).font(CyType.secondary).foregroundStyle(id.tint.opacity(0.85)).lineLimit(2) }
                }
                Spacer(minLength: 4)
                if let open = onOpen {
                    Button(action: open) { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(id.tint).cyMinTap() }
                        .buttonStyle(.plain).accessibilityLabel("Open \(title)")
                }
            }
            if let d = detail { Text(d).font(CyType.secondary).foregroundStyle(id.tint.opacity(0.85)).fixedSize(horizontal: false, vertical: true) }
            if let t = actionTitle, let a = action { CyPrimaryButton(title: t, systemImage: "play.fill", action: a) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cyCard(tinted: id.bg)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cySessionCard")
    }
}

/// One coach answer: text, source line, honesty tag (Rule answers are deterministic — never generated text).
struct CyCoachAnswer: Identifiable, Equatable {
    var id: Int
    var text: String
    var source: String
    var tag: SourceTag?
    var isRule = true
}

/// Coach card: question + numbered answers, each with its source and tag.
struct CyCoachCard: View {
    var systemImage: String = "sparkles"
    let question: String
    let answers: [CyCoachAnswer]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                CyIconBox(systemName: systemImage, sport: .insight)
                Text(question).font(CyType.section).foregroundStyle(CyTheme.ink)
            }
            ForEach(answers) { a in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(a.id)").font(CyType.captionSmall).foregroundStyle(CyTheme.insight.tint)
                        .frame(width: 22, height: 22).background(CyTheme.insight.bg, in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(a.text).font(CyType.body).foregroundStyle(CyTheme.ink).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 6) {
                            Text(a.source).font(CyType.captionSmall).foregroundStyle(CyTheme.ink3).lineLimit(2)
                            if a.isRule { ruleBadge }
                            if let t = a.tag { CySourceTagBadge(tag: t) }
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cyCard()
        .accessibilityElement(children: .contain)
    }
    private var ruleBadge: some View {
        Text("Rule").font(CyType.captionSmall).foregroundStyle(CyTheme.insight.tint)
            .padding(.horizontal, 7).padding(.vertical, 4).background(CyTheme.insight.bg, in: Capsule())
            .accessibilityLabel("Rule-based")
    }
}

/// Goal indicator: goal name, the indicator that measures it, value with tag, optional progress bar.
struct CyGoalIndicatorCard: View {
    let goal: String
    var isMain = false
    let indicator: String
    let value: String?
    var unit: String? = nil
    var sub: String? = nil
    var progress: Double? = nil
    let tag: SourceTag
    var body: some View {
        let id = CyTheme.goal
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                CyCaption(text: isMain ? "\(goal) · main goal" : goal, color: id.tint.opacity(0.85))
                Spacer()
                CySourceTagBadge(tag: tag)
            }
            Text(indicator).font(CyType.secondary.weight(.semibold)).foregroundStyle(id.tint)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value ?? "—").font(CyType.numeral).monospacedDigit().foregroundStyle(value == nil ? id.tint.opacity(0.5) : id.tint)
                if let u = unit, value != nil { Text(u).font(CyType.unit).foregroundStyle(id.tint.opacity(0.8)) }
            }
            if let s = sub { Text(s).font(CyType.captionSmall).foregroundStyle(id.tint.opacity(0.85)).fixedSize(horizontal: false, vertical: true) }
            if let p = progress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(id.soft)
                        Capsule().fill(id.mid).frame(width: geo.size.width * CGFloat(CyDesign.clampFraction(p)))
                    }
                }
                .frame(height: 8)
                .accessibilityHidden(true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cyCard(tinted: id.bg)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(goal)\(isMain ? ", main goal" : ""). \(indicator): \(value.map { "\($0) \(unit ?? "")" } ?? "unknown"), \(tag.spoken)\(sub.map { ". \($0)" } ?? "")")
        .accessibilityIdentifier("cyGoalCard")
    }
}

/// Floating pill tab bar with the centre Train now action (visual + callbacks only; wiring to screens comes later).
struct CyTabItem: Identifiable, Equatable { var id: Int; var title: String; var systemImage: String }

struct CyFloatingTabBar: View {
    let items: [CyTabItem]          // 4 items: two left of the centre action, two right
    @Binding var selection: Int
    var trainTitle = "Train now"
    let onTrain: () -> Void
    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.prefix(2)) { tab($0) }
            centre
            ForEach(items.dropFirst(2)) { tab($0) }
        }
        .padding(.horizontal, 6)
        .frame(height: 66)
        .background(CyTheme.nav, in: Capsule())
        .shadow(color: Color.black.opacity(0.2), radius: 14, y: 8)
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cyTabBar")
    }
    private func tab(_ t: CyTabItem) -> some View {
        let on = t.id == selection
        return Button { selection = t.id } label: {
            VStack(spacing: 3) {
                Image(systemName: t.systemImage).font(.system(size: 18, weight: .semibold))
                Text(t.title).font(.system(size: 10, weight: .semibold))
                Circle().fill(on ? CyTheme.navOn : Color.clear).frame(width: 4, height: 4)
            }
            .foregroundStyle(on ? CyTheme.navOn : CyTheme.navInk)
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t.title)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("cyTab-\(t.id)")
    }
    private var centre: some View {
        Button(action: onTrain) {
            Image(systemName: "play.fill").font(.system(size: 22, weight: .bold)).foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(LinearGradient(colors: [CyTheme.cycling.mid, CyTheme.strength.mid], startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                .overlay(Circle().stroke(CyTheme.nav, lineWidth: 4))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(trainTitle)
        .accessibilityIdentifier("cyTabTrain")
    }
}

/// Live-ride metric: label with icon, large value, unit, source tag; "—" when the source is absent.
struct CyLiveMetric: View {
    let title: String
    var systemImage: String? = nil
    let value: String?
    var unit: String? = nil
    let tag: SourceTag
    var hero = false
    var tint: Color = CyTheme.ink
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if let s = systemImage { Image(systemName: s).font(.caption.weight(.semibold)).accessibilityHidden(true) }
                Text(title).font(CyType.captionSmall)
            }
            .foregroundStyle(CyTheme.ink2)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value ?? "—").font(hero ? CyType.numeralLarge : CyType.numeral).monospacedDigit().foregroundStyle(value == nil ? CyTheme.ink3 : tint).lineLimit(1).minimumScaleFactor(0.6)
                if let u = unit, value != nil { Text(u).font(CyType.unit).foregroundStyle(CyTheme.ink2) }
            }
            CySourceTagBadge(tag: tag)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cyCard(radius: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value.map { "\($0) \(unit ?? "")" } ?? "no data"), \(tag.spoken)")
    }
}
