import SwiftUI

// Lab screen (theme and scenario switches) and the component gallery. Every component is shown in its states:
// normal, selected, disabled, loading, empty / insufficient data, long text and large accessibility text.

struct LabScreen: View {
    @Binding var themeRaw: String
    @Binding var scenario: LabScenario
    let lockedTheme: CyThemeID?
    var bottomInset: CGFloat = 0
    @Environment(\.cyTheme) private var theme
    @State private var path: [String] = LabConfig.screen == "gallery" ? [LabConfig.page ?? "buttons"] : []

    static let pages: [(id: String, title: String, icon: String)] = [
        ("home21", "Home v2.3 components", "sparkles"),
        ("buttons", "Buttons", "hand.tap"),
        ("cards", "Cards", "rectangle.stack"),
        ("rings", "Circular indicators", "circle.dashed"),
        ("charts", "Charts", "chart.xyaxis.line"),
        ("controls", "Strip, lists and controls", "slider.horizontal.3"),
        ("sheets", "Sheets", "rectangle.bottomhalf.inset.filled"),
    ]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: CySpace.l) {
                    Text("UI Lab").font(CyFont.display).foregroundStyle(theme.textPrimary).accessibilityAddTraits(.isHeader).accessibilityIdentifier("labTitle")
                    Text("Prototype only. Sample data. Nothing here is connected to the Cyclift app.").font(CyFont.footnote).foregroundStyle(theme.textSecondary)

                    CyOverline(text: "Theme")
                    ForEach(CyThemeID.allCases) { id in
                        ThemeRow(id: id, isSelected: (lockedTheme ?? CyThemeID(rawValue: themeRaw)) == id) { themeRaw = id.rawValue }
                    }

                    CyOverline(text: "Home scenario")
                    ForEach(LabScenario.allCases) { s in
                        CySelectionCard(title: s.title, isSelected: scenario == s) { scenario = s }.accessibilityIdentifier("scenario-\(s.rawValue)")
                    }

                    CyOverline(text: "Component gallery")
                    ForEach(LabScreen.pages, id: \.id) { p in
                        NavigationLink(value: p.id) {
                            CyCard(padding: CySpace.m) {
                                HStack(spacing: CySpace.m) {
                                    Image(systemName: p.icon).foregroundStyle(theme.accent).frame(width: 28)
                                    Text(p.title).font(CyFont.headline).foregroundStyle(theme.textPrimary)
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(theme.textTertiary)
                                }
                                .frame(minHeight: CyHit.min)
                            }
                        }
                        .buttonStyle(CyCardButtonStyle())
                    }
                }
                .padding(CySpace.l)
                .padding(.bottom, bottomInset)
            }
            .clipped()
            .background(theme.background.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { id in
                GalleryPage(id: id, bottomInset: bottomInset)
            }
        }
    }
}

struct ThemeRow: View {
    let id: CyThemeID
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.cyTheme) private var theme
    var body: some View {
        let t = CyTheme.named(id)
        Button(action: action) {
            CyCard(padding: CySpace.m, isSelected: isSelected) {
                HStack(spacing: CySpace.m) {
                    HStack(spacing: 0) {
                        ForEach(Array([t.background, t.surface2, t.accent, t.endurance, t.strength, t.recovery].enumerated()), id: \.offset) { _, c in
                            Rectangle().fill(c).frame(width: 14, height: 30)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(theme.border, lineWidth: 1))
                    .accessibilityHidden(true)
                    Text(id.title).font(CyFont.headline).foregroundStyle(theme.textPrimary)
                    Spacer()
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle").foregroundStyle(isSelected ? theme.accent : theme.textTertiary)
                }
                .frame(minHeight: CyHit.min)
            }
        }
        .buttonStyle(CyCardButtonStyle())
        .accessibilityLabel("\(id.title) theme")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// One labelled example in the gallery.
struct Example<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content
    @Environment(\.cyTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: CySpace.s) {
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(theme.textTertiary)
            content()
        }
    }
}

struct GalleryPage: View {
    let id: String
    var bottomInset: CGFloat = 0
    @Environment(\.cyTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var segment = 0
    @State private var sports: Set<String> = ["cycling", "strength"]
    @State private var text = ""
    @State private var textFilled = "72"
    @State private var checklist = MockData.newUser.setup
    @State private var picked = 1
    @State private var showConfirm = false
    @State private var showReview = false
    @State private var showBlocked = false
    @State private var note = ""

    private var title: String { LabScreen.pages.first { $0.id == id }?.title ?? id }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CySpace.xl) {
                HStack {
                    CyIconButton(systemName: "chevron.left", label: "Back") { dismiss() }
                    Text(title).font(CyFont.title).foregroundStyle(theme.textPrimary).accessibilityAddTraits(.isHeader)
                }
                if !note.isEmpty { Text(note).font(CyFont.caption).foregroundStyle(theme.accent) }
                switch id {
                case "home21": Gallery21()
                case "buttons": buttons
                case "cards": cards
                case "rings": rings
                case "charts": charts
                case "controls": controls
                default: sheets
                }
            }
            .padding(CySpace.l)
            .padding(.bottom, bottomInset)
        }
        .clipped()
        .background(theme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showConfirm) {
            CyConfirmSheet(title: "Delete this session?", message: "Sample confirmation. In the app this would remove the session from your plan.",
                           confirmTitle: "Delete", isDestructive: true, onConfirm: { showConfirm = false; note = "Confirmed (sample only)" }, onCancel: { showConfirm = false })
                .environment(\.cyTheme, theme).presentationDetents([.medium])
        }
        .sheet(isPresented: $showReview) {
            CyReviewSheet(title: "Review the suggestion", reason: "Two sessions reached the top of the range.", benefit: "Keeps the work challenging.",
                          impact: "Last sets may feel harder.", changes: MockData.changes,
                          onApprove: { showReview = false; note = "Approved (sample only)" }, onPostpone: { showReview = false; note = "Postponed (sample only)" },
                          onDecline: { showReview = false; note = "Declined (sample only)" })
                .environment(\.cyTheme, theme).presentationDetents([.large])
        }
        .sheet(isPresented: $showBlocked) {
            CyReviewSheet(title: "Review the change", reason: "You asked for a longer session.", benefit: "More training time.", impact: "None until applied.",
                          changes: [CyChange(id: "t", label: "Time limit", before: "45 min", after: "90 min")], canApprove: false,
                          blockedReason: "This session uses one of your routines. Choose how to continue before it can be applied.",
                          onApprove: {}, onPostpone: { showBlocked = false }, onDecline: { showBlocked = false })
                .environment(\.cyTheme, theme).presentationDetents([.large])
        }
    }

    // MARK: pages

    @ViewBuilder private var buttons: some View {
        Example(label: "PRIMARY") { CyButton(title: "Start session", icon: "play.fill") { note = "Primary tapped" } }
        Example(label: "SECONDARY") { CyButton(title: "View plan", kind: .secondary) { note = "Secondary tapped" } }
        Example(label: "DESTRUCTIVE") { CyButton(title: "Delete session", icon: "trash", kind: .destructive) { note = "Destructive tapped" } }
        Example(label: "COMPACT ACTION") {
            HStack { CyButton(title: "Why?", kind: .compact, fullWidth: false) { note = "Compact tapped" }; CyButton(title: "Move", kind: .compact, fullWidth: false) {} }
        }
        Example(label: "ICON-ONLY · NORMAL / SELECTED / DISABLED") {
            HStack(spacing: CySpace.m) {
                CyIconButton(systemName: "ellipsis", label: "More") { note = "Icon tapped" }
                CyIconButton(systemName: "star.fill", label: "Favourite", isSelected: true) {}
                CyIconButton(systemName: "ellipsis", label: "More") {}.disabled(true)
            }
        }
        Example(label: "DISABLED") {
            VStack(spacing: CySpace.s) {
                CyButton(title: "Start session") {}.disabled(true)
                CyButton(title: "View plan", kind: .secondary) {}.disabled(true)
                CyButton(title: "Delete session", kind: .destructive) {}.disabled(true)
            }
        }
        Example(label: "LOADING") {
            VStack(spacing: CySpace.s) {
                CyButton(title: "Saving", isLoading: true) {}
                CyButton(title: "Saving", kind: .secondary, isLoading: true) {}
            }
        }
        Example(label: "LONG TEXT") { CyButton(title: MockData.longText, icon: "play.fill") {} }
        Example(label: "LARGE ACCESSIBILITY TEXT") {
            VStack(spacing: CySpace.s) {
                CyButton(title: "Start session", icon: "play.fill") {}
                CyButton(title: "Why?", kind: .compact, fullWidth: false) {}
            }
            .dynamicTypeSize(.accessibility2)
        }
    }

    @ViewBuilder private var cards: some View {
        Example(label: "TRAINING SUMMARY · NORMAL") {
            HStack(alignment: .top, spacing: CySpace.m) {
                CyTrainingSummaryCard(model: MockData.established.endurance, onOpen: { note = "Endurance opened" })
                CyTrainingSummaryCard(model: MockData.established.strength, onOpen: { note = "Strength opened" })
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        Example(label: "TRAINING SUMMARY · EMPTY / LOADING") {
            HStack(alignment: .top, spacing: CySpace.m) {
                CyTrainingSummaryCard(model: MockData.newUser.endurance, emptyMessage: MockData.newUser.enduranceEmpty, onOpen: {})
                CyTrainingSummaryCard(model: nil, onOpen: {})
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        Example(label: "WORKOUT · NORMAL / LONG TEXT / DISABLED ACTION / LOADING") {
            VStack(spacing: CySpace.s) {
                CyWorkoutCard(model: MockData.workout, onAction: { note = "Start tapped" }, onOpen: { note = "Workout opened" })
                CyWorkoutCard(model: MockData.workoutLong, onAction: {}, onOpen: {})
                CyWorkoutCard(model: MockData.workoutLong, isActionEnabled: false, onAction: {}, onOpen: {})
                CyWorkoutCard(model: nil, onAction: {}, onOpen: {})
            }
        }
        Example(label: "RECOVERY · NORMAL / NO READINGS / LOADING") {
            VStack(spacing: CySpace.s) {
                CyRecoveryCard(model: MockData.recovery, onOpen: { note = "Recovery opened" })
                CyRecoveryCard(model: nil, emptyMessage: "No readings. Allow Apple Health to see sleep and resting heart rate against your own usual range.", onOpen: {})
                CyRecoveryCard(model: nil, onOpen: {})
            }
        }
        Example(label: "COACH INSIGHT · CARD / COMPACT ROW / EMPTY / LOADING") {
            VStack(spacing: CySpace.s) {
                CyCoachInsightCard(model: MockData.established.coach, onWhy: { note = "Why tapped" }, onAccept: { note = "Review tapped" }, onNotNow: { note = "Not now tapped" })
                CyCoachInsightCard(model: CyCoachModel(sentence: "Keep this week as planned.", why: "", hasProposal: false), compact: true, onWhy: {})
                CyCoachInsightCard(model: nil, compact: true, emptyMessage: MockData.newUser.coachEmpty, onWhy: {})
                CyCoachInsightCard(model: nil, compact: true, onWhy: {})
            }
        }
        Example(label: "GETTING STARTED · IN PROGRESS / COMPLETE (COLLAPSED)") {
            VStack(spacing: CySpace.s) {
                CyGettingStartedCard(items: checklist) { item in
                    if let i = checklist.firstIndex(where: { $0.id == item.id }) { checklist[i].isDone.toggle() }
                }
                CyGettingStartedCard(items: MockData.established.setup.map { var c = $0; c.isDone = true; return c }, onItem: { _ in })
            }
        }
        Example(label: "METRIC SUMMARY · NORMAL / NO DATA / LOADING") {
            HStack(alignment: .top, spacing: CySpace.s) {
                CyMetricSummaryCard(model: MockData.metric, onOpen: { note = "Metric opened" })
                CyMetricSummaryCard(model: MockData.metricEmpty)
                CyMetricSummaryCard(model: nil)
            }
        }
        Example(label: "EMPTY STATE") {
            CyEmptyStateCard(icon: "calendar.badge.plus", title: "No plan yet", message: "Build a plan or bring the one you already follow.", actionTitle: "Get started", action: { note = "Empty-state action tapped" })
        }
        Example(label: "LARGE ACCESSIBILITY TEXT") {
            VStack(spacing: CySpace.s) {
                CyWorkoutCard(model: MockData.workout, onAction: {}, onOpen: {})
                CyTrainingSummaryCard(model: MockData.established.endurance, onOpen: {})
            }
            .dynamicTypeSize(.accessibility2)
        }
    }

    @ViewBuilder private var rings: some View {
        Example(label: "HOME ROW · NORMAL") { CyCard(padding: CySpace.m) { CyRingRow(rings: MockData.established.rings) { note = "\($0.title) opened" } } }
        Example(label: "MISSING DATA") { CyCard(padding: CySpace.m) { CyRingRow(rings: MockData.newUser.rings) { note = "\($0.title) opened" } } }
        Example(label: "LOADING") {
            CyCard(padding: CySpace.m) { CyRingRow(rings: MockData.established.rings.map { CyRingModel(id: $0.id, title: $0.title, kind: $0.kind, display: .loading) }) { _ in } }
        }
        Example(label: "STATUS LEVELS (WORDS, NOT SCORES)") {
            CyCard(padding: CySpace.m) {
                CyRingRow(rings: [
                    CyRingModel(id: "l1", title: "Load Balance", kind: .loadBalance, display: .status(word: "Below target", level: .neutral, fill: 0.45)),
                    CyRingModel(id: "l2", title: "Load Balance", kind: .loadBalance, display: .status(word: "Elevated", level: .caution, fill: 1.0)),
                    CyRingModel(id: "r1", title: "Recovery", kind: .recovery, display: .status(word: "Take it easier", level: .alert, fill: 0.35)),
                ]) { _ in }
            }
        }
        Example(label: "GENERIC PROGRESS · 0% / 50% / 100% · NOT TAPPABLE") {
            HStack(spacing: CySpace.s) {
                CyRing(model: CyRingModel(id: "g0", title: "Weekly goal", kind: .generic, display: .fraction(0, text: "0%", caption: "0 of 4")))
                CyRing(model: CyRingModel(id: "g1", title: "Weekly goal", kind: .generic, display: .fraction(0.5, text: "50%", caption: "2 of 4")))
                CyRing(model: CyRingModel(id: "g2", title: "Weekly goal", kind: .generic, display: .fraction(1, text: "100%", caption: "4 of 4")))
            }
        }
        Example(label: "LONG TEXT") {
            HStack(alignment: .top, spacing: CySpace.s) {
                CyRing(model: CyRingModel(id: "x1", title: "Consistency across both sports", kind: .consistency, display: .fraction(0.8, text: "80%", caption: "4 of 5 planned sessions completed"))) {}
                CyRing(model: CyRingModel(id: "x2", title: "Load Balance", kind: .loadBalance, display: .missing(reason: "Needs four weeks of rated sessions"))) {}
            }
        }
        Example(label: "LARGE ACCESSIBILITY TEXT (STACKS AS A LIST)") {
            CyCard(padding: CySpace.m) { CyRingRow(rings: MockData.established.rings) { _ in } }
                .dynamicTypeSize(.accessibility2)
        }
    }

    @ViewBuilder private var charts: some View {
        Example(label: "COMBINED TRENDS · LINE + STATUS ROWS · TOUCH TO INSPECT") {
            CyTrendChart(title: "Training & Recovery", series: MockData.established.trendSeries, statusRows: MockData.established.trendRows,
                         dayLabels: MockData.weekdays, yDomain: 0...105, footnote: "Days without data are left empty.")
        }
        Example(label: "MULTI-SERIES · GAPS FOR MISSING DAYS · SERIES SELECTION") {
            CyTrendChart(title: "Minutes by day", series: MockData.multiSeries, dayLabels: MockData.weekdays)
        }
        Example(label: "WEEKLY TREND") { CyWeeklyBars(title: "Endurance minutes per week", points: MockData.weekly, unit: "min", category: .endurance) }
        Example(label: "EMPTY / INSUFFICIENT DATA") {
            VStack(spacing: CySpace.s) {
                CyTrendChart(title: "Training & Recovery", series: [], emptyMessage: MockData.newUser.trendEmpty)
                CyWeeklyBars(title: "Strength sessions per week", points: [CySeriesPoint(id: 0, label: "W1", value: 2)], unit: "sessions", category: .strength)
            }
        }
        Example(label: "LOADING") { CyTrendChart(title: "Training & Recovery", series: [], isLoading: true) }
        Example(label: "LARGE ACCESSIBILITY TEXT") {
            CyTrendChart(title: "Training & Recovery", series: MockData.established.trendSeries, statusRows: MockData.established.trendRows, dayLabels: MockData.weekdays, yDomain: 0...105)
                .dynamicTypeSize(.accessibility2)
        }
    }

    @ViewBuilder private var controls: some View {
        Example(label: "SEVEN-DAY STRIP · NORMAL / NEW USER / EMPTY / LOADING") {
            VStack(spacing: CySpace.s) {
                CyWeekStrip(days: MockData.established.days) { note = "\($0.weekday) opened" }
                CyWeekStrip(days: MockData.newUser.days) { _ in }
                CyWeekStrip(days: []) { _ in }
                CyWeekStrip(days: [], isLoading: true) { _ in }
            }
        }
        Example(label: "SESSION STATUS ICONS") {
            CyCard(padding: CySpace.m) { CyStatusLegend(statuses: [.done, .today, .planned, .missed, .skipped, .rest]) }
        }
        Example(label: "CHECKLIST · NORMAL (TAP TO TOGGLE) / DISABLED") {
            VStack(spacing: CySpace.s) {
                CyCard(padding: CySpace.m) {
                    CyChecklist(items: checklist) { item in
                        if let i = checklist.firstIndex(where: { $0.id == item.id }) { checklist[i].isDone.toggle() }
                    }
                }
                CyCard(padding: CySpace.m) { CyChecklist(items: Array(checklist.prefix(2)), isEnabled: false) { _ in } }
            }
        }
        Example(label: "SEGMENTED · NORMAL / DISABLED") {
            VStack(spacing: CySpace.s) {
                CySegmented(options: ["7 days", "30 days", "12 weeks"], selection: $segment)
                CySegmented(options: ["7 days", "30 days"], selection: .constant(0), isEnabled: false)
            }
        }
        Example(label: "SELECTION CARDS · NORMAL / SELECTED / DISABLED / LONG TEXT") {
            VStack(spacing: CySpace.s) {
                CySelectionCard(title: "Import my plan", subtitle: "Start from what you already do", icon: "square.and.arrow.down", isSelected: picked == 0) { picked = 0 }
                CySelectionCard(title: "Build a new plan", subtitle: "From your goals and time", icon: "wand.and.stars", isSelected: picked == 1) { picked = 1 }
                CySelectionCard(title: "Not available", subtitle: "Shown but cannot be chosen", icon: "lock", isSelected: false, isEnabled: false) {}
                CySelectionCard(title: MockData.longText, subtitle: MockData.longText, icon: "text.alignleft", isSelected: picked == 3) { picked = 3 }
            }
        }
        Example(label: "SPORT SELECTION (SUPPORT LEVEL ALWAYS STATED)") { CySportPicker(options: MockData.sports, selection: $sports) }
        Example(label: "FORM FIELDS · EMPTY / FILLED / ERROR / DISABLED") {
            VStack(spacing: CySpace.m) {
                CyFormField(label: "Weight", text: $text, placeholder: "Optional", help: "Used for power-to-weight only.", unit: "kg")
                CyFormField(label: "Weight", text: $textFilled, unit: "kg")
                CyFormField(label: "Weight", text: .constant("7"), error: "Enter a weight between 30 and 250 kg.", unit: "kg")
                CyFormField(label: "Weight", text: .constant("72"), unit: "kg", isEnabled: false)
            }
        }
        Example(label: "NAVIGATION PROTOTYPE") {
            Text("The floating dock below is the navigation prototype (original Cyclift style): Home is live, Plan and Progress are mock destinations, Profile holds this Lab, and the centre button opens a sample sheet.")
                .font(CyFont.footnote).foregroundStyle(theme.textSecondary)
        }
        Example(label: "LARGE ACCESSIBILITY TEXT") {
            VStack(spacing: CySpace.s) {
                CyWeekStrip(days: MockData.established.days) { _ in }
                CySegmented(options: ["7 days", "30 days"], selection: .constant(0))
                CySelectionCard(title: "Build a new plan", subtitle: "From your goals and time", icon: "wand.and.stars", isSelected: true) {}
            }
            .dynamicTypeSize(.accessibility2)
        }
    }

    @ViewBuilder private var sheets: some View {
        Example(label: "CONFIRMATION SHEET (DESTRUCTIVE)") { CyButton(title: "Show confirmation", kind: .secondary) { showConfirm = true } }
        Example(label: "REVIEW AND APPROVAL SHEET") { CyButton(title: "Show review", kind: .secondary) { showReview = true } }
        Example(label: "REVIEW SHEET · BLOCKED (APPROVE DISABLED WITH REASON)") { CyButton(title: "Show blocked review", kind: .secondary) { showBlocked = true } }
        Example(label: "INLINE PREVIEW OF THE REVIEW CONTENT") {
            CyCard(padding: CySpace.m) {
                VStack(alignment: .leading, spacing: CySpace.s) {
                    ForEach(MockData.changes) { c in
                        HStack { Text(c.label).font(CyFont.caption).foregroundStyle(theme.textSecondary); Spacer(); Text("\(c.before) → \(c.after)").font(CyFont.callout).foregroundStyle(theme.textPrimary) }
                    }
                }
            }
        }
    }
}
