import SwiftUI
import UIKit

// Cyclift UI Lab — one presenter for sheets (prototype only).
//
// Why it exists (run 43244793325): the earlier guards trusted SwiftUI's "dismissed" callback. That callback can
// arrive after a newer sheet was requested, which cleared the busy flag at the wrong moment and let a request go
// straight through during a dismissal; a 1-second fallback timer could fire while the old sheet was still leaving.
//
// How it works: callbacks are only wake-up calls. Every decision is taken from what UIKit reports at that moment —
// is this presenter's sheet still in a window, is a transition running — together with one small phase value.
// There are no timers and no delays.
//   • a request for the sheet that is already open is ignored (double tap);
//   • a request for a different sheet closes the open one and then presents the new one;
//   • a request made while a sheet is leaving is held and presented when UIKit reports the dismissal finished;
//   • every request first re-checks the real state, so a stale phase cannot block or misroute it.
final class SheetPresenter<Item: Identifiable>: ObservableObject where Item.ID == String {
    enum Phase: String { case idle, presenting, presented, dismissing }

    @Published private(set) var item: Item?
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var visibleID: String?          // the sheet whose content is on screen

    private let name: String
    private var queued: Item?
    private var whenIdle: [() -> Void] = []
    private var generation = 0
    private weak var anchor: UIViewController?
    private weak var probe: SheetProbeController?
    private var contentAppearedID: String?
    private var wakePending = false
    private var waitingOnTransition = false
    private var hops = 0
    private var bypassing = false
    private var startedAt = Date.distantPast
    private var muteNext = false          // self-test only: see loseNextPresentation()
    private var muted = false

    init(name: String) { self.name = name }

    // MARK: Use

    /// For `.sheet(item:)`. SwiftUI writes nil here when the athlete swipes the sheet away or taps outside it.
    var binding: Binding<Item?> {
        Binding(get: { self.muted ? nil : self.item }, set: { new in
            if let new { self.request(new) } else { self.systemDismissed() }
        })
    }

    func request(_ new: Item) {
        hops = 0
        reconcile()
        switch phase {
        case .idle:
            if isHostReady && !isMoving {
                start(new)
            } else {
                queued = new
                note("request \(new.id): HELD until the screen is ready (host ready \(isHostReady), transition running \(isMoving))")
                waitForChange()
            }
        case .presenting, .presented:
            if item?.id == new.id {
                if phase == .presenting && !isSheetAlive && !isMoving && Date().timeIntervalSince(startedAt) > 1 {
                    // the state has said "presenting" for over a second, yet UIKit shows nothing and nothing is
                    // moving: the presentation was lost. A repeated request must recover it, not be ignored.
                    // (The one-second figure only tells a lost presentation from one that has just been requested;
                    // it delays nothing.)
                    note("request \(new.id): STALE presentation found (nothing on screen); presenting again")
                    queued = new
                    beginDismissal("stale presentation")
                } else {
                    note("request \(new.id): IGNORED, this sheet is already open (duplicate request)")
                }
            } else {
                note("request \(new.id): QUEUED, it replaces the open sheet \(item?.id ?? "")")
                queued = new
                beginDismissal("replaced by \(new.id)")
            }
        case .dismissing:
            if let q = queued, q.id != new.id { note("queued \(q.id) is superseded by the newer request \(new.id)") }
            queued = new
            note("request \(new.id): QUEUED until the current dismissal has finished")
            if isSheetAlive && !isMoving {
                // the sheet should be leaving but UIKit shows it standing still: dismiss it directly
                note("STALE dismissal found (sheet still on screen, nothing moving); dismissing through UIKit")
                sheetController?.dismiss(animated: true) { [weak self] in self?.wake() }
            }
            waitForChange()
        }
    }

    func dismiss(_ why: String) {
        hops = 0
        guard phase == .presenting || phase == .presented else {
            note("dismiss (\(why)): no sheet is open")
            wake()
            return
        }
        beginDismissal(why)
    }

    /// Runs `work` as soon as no sheet of this presenter is on screen (now, if that is already the case).
    func onNextIdle(_ work: @escaping () -> Void) {
        if phase == .idle { work() } else { whenIdle.append(work) }
    }

    /// True when nothing of this presenter is on screen and nothing is moving.
    var isSettled: Bool { !isSheetAlive && !isMoving && (bypassing || phase == .idle) && queued == nil }
    var isHostReady: Bool { anchor?.viewIfLoaded?.window != nil }

    // MARK: Lifecycle wake-ups (they never decide anything by themselves)

    func attach(anchor c: UIViewController) { anchor = c }
    func swiftUIDismissed() { hops = 0; note("wake-up: SwiftUI reported a dismissal"); wake() }

    func contentEvent(_ id: String, appeared: Bool) {
        hops = 0
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if appeared {
                self.contentAppearedID = id
                if self.visibleID != id { self.visibleID = id }
            } else if self.visibleID == id {
                self.visibleID = nil
            }
            self.reconcile()
        }
    }

    func probeEvent(_ c: SheetProbeController, _ e: SheetProbeController.Event, id: String) {
        hops = 0
        switch e {
        case .created:
            c.sheetID = id
            probe = c
            return                                   // called while SwiftUI builds the view: change nothing published
        case .appeared:
            c.didAppear = true
        case .willDisappear, .disappeared:
            break
        }
        note("wake-up: sheet \(id) \(e.rawValue)")
        wake()
    }

    func wake() {
        guard !wakePending else { return }
        wakePending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.wakePending = false
            self.reconcile()
        }
    }

    // MARK: Prototype self-test only

    /// The next presentation is withheld from SwiftUI: the presenter's state says "presenting" while nothing reaches
    /// the screen — a lost presentation, reproduced on purpose. Used by the "lost" self-test and by nothing else.
    func loseNextPresentation() { muteNext = true }

    // Plain SwiftUI, no presenter logic ("direct" observation)

    func bypass(_ new: Item?) {
        bypassing = true
        queued = nil
        item = new
    }

    // MARK: Views to embed

    /// Goes behind the view that carries `.sheet`: tells the presenter which controller presents.
    func anchorView() -> some View {
        SheetAnchor(attach: { [weak self] c in self?.attach(anchor: c) }, appeared: { [weak self] in self?.wake() })
            .frame(width: 1, height: 1).allowsHitTesting(false).accessibilityHidden(true)
    }
    /// Goes behind the sheet's content: reports the sheet's real appearance and disappearance.
    func probeView(for id: String) -> some View {
        SheetProbe(event: { [weak self] c, e in self?.probeEvent(c, e, id: id) })
            .frame(width: 1, height: 1).allowsHitTesting(false).accessibilityHidden(true)
    }

    // MARK: State from UIKit

    private var host: UIViewController? {
        var v: UIViewController? = anchor
        while let p = v?.parent { v = p }
        return v
    }
    private var sheetController: UIViewController? {
        var v: UIViewController? = probe
        while let p = v?.parent { v = p }
        return v
    }
    private var isSheetAlive: Bool { probe?.viewIfLoaded?.window != nil }
    private var isMoving: Bool {
        if let h = host, h.transitionCoordinator != nil || h.isBeingPresented || h.isBeingDismissed { return true }
        if let s = sheetController, s.isBeingPresented || s.isBeingDismissed { return true }
        return false
    }

    // MARK: Decisions

    private func start(_ new: Item) {
        generation += 1
        startedAt = Date()
        hops = 0
        contentAppearedID = nil
        muted = muteNext
        muteNext = false
        phase = .presenting
        item = new
        note("PRESENT \(new.id) (#\(generation))")
    }

    private func beginDismissal(_ why: String) {
        note("DISMISS \(item?.id ?? "none") (\(why))")
        hops = 0
        phase = .dismissing
        muted = false
        item = nil
        wake()
    }

    private func systemDismissed() {
        hops = 0
        if bypassing { item = nil; return }
        if item != nil, phase == .presenting || phase == .presented {
            note("DISMISSED by iOS (swipe down or tap outside): \(item?.id ?? "")")
            phase = .dismissing
            item = nil
        }
        wake()
    }

    private func reconcile() {
        if bypassing { return }
        switch phase {
        case .idle:
            guard let q = queued else { return }
            if isHostReady && !isMoving { queued = nil; start(q) } else { waitForChange() }
        case .presenting:
            guard let current = item else { return }
            let appeared = (probe?.sheetID == current.id && probe?.didAppear == true) || contentAppearedID == current.id
            if isSheetAlive && appeared {
                hops = 0
                phase = .presented
                if visibleID != current.id { visibleID = current.id }
                note("PRESENTED \(current.id)")
            }
        case .presented:
            if !isSheetAlive && !isMoving {
                note("sheet \(item?.id ?? "") is no longer on screen; state corrected")
                phase = .dismissing
                item = nil
                finish()
            }
        case .dismissing:
            if !isSheetAlive && !isMoving { finish() } else { waitForChange() }
        }
    }

    private func finish() {
        hops = 0
        phase = .idle
        if visibleID != nil { visibleID = nil }
        note("IDLE")
        let work = whenIdle
        whenIdle = []
        work.forEach { $0() }
        if let q = queued, isHostReady, !isMoving { queued = nil; start(q) } else if queued != nil { waitForChange() }
    }

    /// Asks to be woken when the running transition ends. Without a transition to wait on it re-checks on the next
    /// turns of the main run loop, a bounded number of times; after that the next lifecycle event or request re-checks.
    private func waitForChange() {
        if let c = host?.transitionCoordinator ?? sheetController?.transitionCoordinator {
            if waitingOnTransition { return }
            waitingOnTransition = true
            let queuedOK = c.animate(alongsideTransition: nil) { [weak self] _ in
                self?.waitingOnTransition = false
                self?.wake()
            }
            if !queuedOK { waitingOnTransition = false; hop() }
        } else {
            hop()
        }
    }
    private func hop() {
        if hops < 240 { hops += 1; wake() }
        else if hops == 240 { hops += 1; note("still waiting; the next lifecycle event or request will re-check") }
    }

    private func note(_ text: String) { SheetLog.note("\(name) \(text) [\(phase.rawValue)]") }
}

// MARK: - UIKit pieces

final class SheetProbeController: UIViewController {
    enum Event: String { case created, appeared, willDisappear = "will disappear", disappeared }
    var sheetID: String = ""
    var didAppear = false
    var onEvent: ((SheetProbeController, Event) -> Void)?
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); onEvent?(self, .appeared) }
    override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); onEvent?(self, .willDisappear) }
    override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); onEvent?(self, .disappeared) }
}

struct SheetProbe: UIViewControllerRepresentable {
    let event: (SheetProbeController, SheetProbeController.Event) -> Void
    func makeUIViewController(context: Context) -> SheetProbeController {
        let c = SheetProbeController()
        c.view.backgroundColor = .clear
        c.view.isUserInteractionEnabled = false
        c.onEvent = event
        event(c, .created)
        return c
    }
    func updateUIViewController(_ c: SheetProbeController, context: Context) { c.onEvent = event }
}

final class SheetAnchorController: UIViewController {
    var onAppear: (() -> Void)?
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); onAppear?() }
}

struct SheetAnchor: UIViewControllerRepresentable {
    let attach: (UIViewController) -> Void
    let appeared: () -> Void
    func makeUIViewController(context: Context) -> SheetAnchorController {
        let c = SheetAnchorController()
        c.view.backgroundColor = .clear
        c.view.isUserInteractionEnabled = false
        c.onAppear = appeared
        attach(c)
        return c
    }
    func updateUIViewController(_ c: SheetAnchorController, context: Context) { c.onAppear = appeared }
}
