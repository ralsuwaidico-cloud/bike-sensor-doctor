import SwiftUI

/// Settings › BikeComputer › Storage (BLE_CONTRACT.md §7): what the board stores, measured by the board itself
/// (STORAGE_STATUS), the health category in the board's own words (e.g. "Directory corrupted"), what this iPhone keeps,
/// and one safe cleanup that can never remove unsynced rides or unsent crash evidence. No repair over Bluetooth.
struct BoardStorageView: View {
    @EnvironmentObject private var device: DeviceLink
    @EnvironmentObject private var link13: Link13Center
    @EnvironmentObject private var diag: DiagReportCenter
    @State private var confirmClean = false

    private var s: BCLink.StorageStatus? { link13.storage }
    private var supported: Bool { link13.session.storage }
    private var cleanup: BoardStorageModel.Cleanup {
        BoardStorageModel.cleanup(status: s, linkEnabled: supported && device.state == .ready, boardRecording: link13.boardRecording,
                                  unsentReports: s?.reportsUnsent ?? 0, unsyncedRides: link13.unsyncedOnBoard ?? 0)
    }

    var body: some View {
        List {
            boardSection
            if supported, s != nil { detailSections }
            cleanupSection
            phoneSection
        }
        .navigationTitle("Storage").navigationBarTitleDisplayMode(.inline)
        .onAppear { link13.requestStorageStatus(); link13.reloadImported(); diag.reload() }
        .refreshable { link13.requestStorageStatus() }
        .confirmationDialog("Clean up the BikeComputer?", isPresented: $confirmClean, titleVisibility: .visible) {
            Button("Clean up") { link13.clean(cleanup) }.accessibilityIdentifier("storageCleanConfirm")
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes: " + cleanup.removes.joined(separator: "; ") + ".\n\nAlways kept: " + cleanup.keeps.joined(separator: "; ") + ".")
        }
    }

    // MARK: board
    @ViewBuilder private var boardSection: some View {
        Section {
            if device.state != .ready {
                Text(device.remembered ? "Connect the BikeComputer to read its storage." : "No BikeComputer paired.").font(.footnote).foregroundStyle(.secondary)
            } else if !supported {
                Text(link13.session.isWaiting ? "Asking the BikeComputer…" : "Storage status needs a BikeComputer firmware with Link 1.3 (this board has \(device.info?.fw ?? "?")). Diagnostic reports still arrive as before.")
                    .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let l = device.live?.storageState, l != 0 { healthRow(category: BoardStorageModel.category(nil, liveState: l), health: .degraded) }
            } else if s == nil {
                HStack(spacing: 10) { ProgressView(); Text("Reading storage from the BikeComputer…").font(.subheadline) }
            } else {
                healthRow(category: BoardStorageModel.category(s, liveState: device.live?.storageState), health: BoardStorageModel.health(s))
                if let f = BoardStorageModel.usedFraction(s) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { Text("Free space"); Spacer(); Text("\(BoardStorageModel.kb(s?.fsFreeKB)) of \(BoardStorageModel.kb(s?.fsTotalKB))").foregroundStyle(.secondary).monospacedDigit() }
                        ProgressView(value: f).tint(f > 0.9 ? BC.warn : f > 0.75 ? BC.stale : BC.accent)
                            .accessibilityLabel("Storage used").accessibilityValue("\(Int((f * 100).rounded())) percent")
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("storageFreeSpace")
                } else { LabeledContent("Free space", value: "not reported") }
                if let at = link13.storageAt { Text("Measured by the board · \(at.formatted(date: .omitted, time: .shortened))").font(.caption2).foregroundStyle(.secondary) }
                Button { link13.requestStorageStatus() } label: { Label("Read again", systemImage: "arrow.clockwise") }
                    .frame(minHeight: 44).accessibilityIdentifier("storageRefresh")
            }
        } header: { Text("BikeComputer") } footer: {
            Text("Numbers are measured by the BikeComputer itself. A damaged filesystem is never repaired or formatted over Bluetooth — that needs the owner-approved computer procedure.")
        }
    }

    private func healthRow(category: String, health: BoardStorageModel.Health) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            StatusBadge(status: health == .good ? .green : health == .failed ? .red : health == .degraded ? .amber : .gray)
            VStack(alignment: .leading, spacing: 2) {
                Text(category).font(.headline).fixedSize(horizontal: false, vertical: true)
                Text("Storage health: \(health.title)").font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("storageHealth")
    }

    @ViewBuilder private var detailSections: some View {
        Section("Firmware") {
            LabeledContent("Firmware storage", value: s?.appUsedKB.map { "\(BoardStorageModel.kb($0)) of \(BoardStorageModel.kb(s?.appSlotKB))" } ?? "not reported")
            if let u = s?.nvsUsedEntries, let f = s?.nvsFreeEntries { LabeledContent("Settings storage", value: "\(u) used · \(f) free entries") }
        }
        Section {
            LabeledContent("Reports on the board", value: s?.reportsStored.map { "\($0)" } ?? "—")
            LabeledContent("Not yet on this iPhone", value: s?.reportsUnsent.map { "\($0)" } ?? "—")
            LabeledContent("Diagnostic storage", value: BoardStorageModel.bytes(s?.diagBytes))
            LabeledContent("Crash dump area", value: BoardStorageModel.crashPartitionText(s?.crashPartition) + (s?.crashDumpBytes.map { $0 > 0 ? " · \(BoardStorageModel.bytes($0))" : "" } ?? ""))
        } header: { Text("Diagnostics") } footer: { Text("Reports come to this iPhone automatically and stay here; nothing is uploaded.") }
        Section {
            LabeledContent("Rides not yet in Cyclift", value: s?.ridesUnsynced.map { "\($0)" } ?? "—")
            LabeledContent("Their size", value: BoardStorageModel.bytes(s?.rideBytesUnsynced))
            LabeledContent("Already saved in Cyclift", value: BoardStorageModel.bytes(s?.rideBytesSynced))
            if let p = link13.rideProgress {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Importing ride \(p.rideId)…").font(.subheadline)
                    ProgressView(value: Double(p.received), total: Double(max(p.size, 1)))
                }.accessibilityElement(children: .combine).accessibilityIdentifier("storageRideImport")
            }
            ForEach(link13.boardRides.filter { $0.needsImport || $0.state == .recording }, id: \.rideId) { r in
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ride \(r.rideId)" + (r.startEpochS > 0 ? " · \(Date(timeIntervalSince1970: TimeInterval(r.startEpochS)).formatted(date: .abbreviated, time: .shortened))" : "")).font(.subheadline)
                    Text(holdText(r)).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if r.ramOnly && r.needsImport {
                        Label(Link13Center.ramOnlyWarning, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2).foregroundStyle(BC.warn).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if let e = link13.rideError { Text(e).font(.caption2).foregroundStyle(BC.stale) }
        } header: { Text("Offline rides") } footer: { Text("Rides recorded without the phone are copied to Cyclift, checked, and only then released on the board. A ride that is not in Cyclift is never deleted.") }
    }

    private func holdText(_ r: BCLink.RideQueueInfo) -> String {
        switch link13.rideHolds[r.rideId] {
        case .demo?: return "Demo ride — not imported"
        case .recording?: return "Recording"
        case .summaryNotVerified?: return "Saved in Cyclift; waiting to confirm its summary with the board"
        case .conflict?: return "A different ride with this number is already in Cyclift — kept on the board"
        case .failed(let why)?: return "Kept on the board: \(why)"
        case nil: return r.state?.words.capitalizedFirst ?? "State \(r.stateRaw)"
        }
    }

    // MARK: cleanup
    @ViewBuilder private var cleanupSection: some View {
        Section {
            Button { confirmClean = true } label: {
                HStack { Label(link13.cleanPending ? "Cleaning up…" : "Safe cleanup", systemImage: "sparkles"); if link13.cleanPending { Spacer(); ProgressView() } }
            }
            .frame(minHeight: 44)
            .disabled(!cleanup.allowed || link13.cleanPending)
            .accessibilityIdentifier("storageSafeCleanup")
            if let why = cleanup.blockedReason { Text(why).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            if let r = link13.cleanResult {
                Text(r.words + (r.bytesFreed > 0 ? " Freed \(BoardStorageModel.bytes(r.bytesFreed))." : "")).font(.footnote)
                    .foregroundStyle(r.status == .done || r.status == .nothingToDo ? BC.live : BC.stale).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("storageCleanResult")
            }
        } header: { Text("Cleanup") } footer: {
            Text("Removes only what this iPhone already holds and verified. Rides not yet in Cyclift, crash reports not yet received and the crash dump are never removed by the app.")
        }
    }

    // MARK: this iPhone
    @ViewBuilder private var phoneSection: some View {
        Section("On this iPhone") {
            let reports = diag.reports
            LabeledContent("BikeComputer reports", value: reports.isEmpty ? "none" : "\(reports.count) · \(DiagFormat.bytes(UInt32(clamping: reports.reduce(0) { $0 + Int($1.size) })))")
            LabeledContent("Offline rides imported", value: link13.importedRides.isEmpty ? "none" : "\(link13.importedRides.count) · \(BoardStorageModel.bytes(UInt32(clamping: link13.importedRides.reduce(0) { $0 + Int($1.samplesSize) })))")
            Text("Kept with Cyclift's data on this iPhone (and in its backups). Nothing here is sent anywhere.").font(.footnote).foregroundStyle(.secondary)
        }
    }
}

/// Connections › BikeComputer: the phone-first link at a glance (negotiated features, coach mirroring, offline rides).
struct Link13StatusSection: View {
    @EnvironmentObject private var device: DeviceLink
    @EnvironmentObject private var link13: Link13Center
    var body: some View {
        if device.state == .ready {
            Section {
                LabeledContent("Link", value: link13.session.summary).accessibilityIdentifier("link13Summary")
                if !link13.coachStatus.isEmpty { LabeledContent("Coach on the BikeComputer", value: link13.coachStatus) }
                if link13.session.rideQueue {
                    LabeledContent("Offline rides waiting", value: link13.unsyncedOnBoard.map { "\($0)" } ?? "not reported yet")
                    let atRisk = link13.boardRides.filter { $0.ramOnly && $0.needsImport }.count
                    if atRisk > 0 {
                        Label("\(atRisk) ride\(atRisk == 1 ? "" : "s") at risk. " + Link13Center.ramOnlyWarning, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote).foregroundStyle(BC.warn).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("link13RidesAtRisk")
                    }
                }
                NavigationLink { BoardStorageView() } label: { Label("Storage", systemImage: "internaldrive") }.accessibilityIdentifier("boardStorageLink")
            } header: { Text("Phone-first link") } footer: {
                if !(device.info?.hasHello ?? false) { Text("Update the BikeComputer firmware for coach mirroring, offline ride import and storage status. Everything else works as before.") }
            }
        }
    }
}

private extension String { var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() } }
