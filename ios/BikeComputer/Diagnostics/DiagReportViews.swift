import SwiftUI

/// Section for Connections › BikeComputer and Connections › Diagnostics: transfer state, last saved report, the list.
/// Nothing at all for firmware without report transfer and no saved reports.
struct BoardDiagReportSection: View {
    @EnvironmentObject private var diag: DiagReportCenter
    var body: some View {
        if diag.boardSupports || !diag.reports.isEmpty {
          Section("BikeComputer diagnostic reports") {
            if let p = diag.transferring {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Diagnostic report ready", systemImage: "arrow.down.doc").font(.subheadline.weight(.semibold)).foregroundStyle(BC.accent)
                    ProgressView(value: Double(p.received), total: Double(max(p.size, 1)))
                    Text("Receiving \(BCLink.DiagKind(rawValue: p.kindRaw)?.title.lowercased() ?? "report") from the BikeComputer · \(DiagFormat.bytes(p.received)) of \(DiagFormat.bytes(p.size))").font(.caption2).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("diagReportReceiving")
            } else if let m = diag.savedThisSession.last, let cur = diag.reports.first(where: { $0.id == m.id }) {
                NavigationLink { DiagReportDetailView(meta: cur) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Report saved", systemImage: "checkmark.circle.fill").font(.subheadline.weight(.semibold)).foregroundStyle(BC.live)
                        Text(DiagFormat.summary(cur)).font(.caption2).foregroundStyle(.secondary)
                        if !cur.summary.isEmpty { Text(cur.summary).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(2) }
                    }
                }
                .accessibilityIdentifier("diagReportSaved")
            }
            if let e = diag.lastError { Text(e).font(.caption2).foregroundStyle(BC.stale) }
            NavigationLink { DiagReportListView() } label: {
                LabeledContent { Text(diag.reports.isEmpty ? "none" : "\(diag.reports.count)") } label: { Label("BikeComputer reports", systemImage: "doc.text.magnifyingglass") }
            }
            .accessibilityIdentifier("diagReportList")
          }
        }
    }
}

enum DiagFormat {
    static func bytes(_ n: UInt32) -> String { n < 1024 ? "\(n) B" : String(format: "%.1f KB", Double(n) / 1024) }
    /// "Crash · firmware 0.7.3 · 26 Oct 2026 14:02 · 3.2 KB"
    static func summary(_ m: DiagReportMeta) -> String {
        var parts = [m.kindTitle]
        if !m.firmware.isEmpty { parts.append("firmware \(m.firmware)") }
        parts.append(m.created.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "time unknown")
        parts.append(m.sizeText)
        return parts.joined(separator: " · ")
    }
}

/// Connections › … › BikeComputer reports: every report saved on this phone, newest first.
struct DiagReportListView: View {
    @EnvironmentObject private var diag: DiagReportCenter
    @State private var uploadConsent = DiagUploadHook.consent
    var body: some View {
        List {
            Section {
                if diag.reports.isEmpty { Text("No reports yet. When the BikeComputer saves a report (for example after a crash), it arrives here by itself while the board is connected.").font(.footnote).foregroundStyle(.secondary) }
                ForEach(diag.reports) { m in
                    NavigationLink { DiagReportDetailView(meta: m) } label: { DiagReportRow(meta: m) }
                }
                .onDelete { idx in let gone = idx.map { diag.reports[$0] }; gone.forEach { diag.delete($0) } }
            } footer: {
                Text("Reports are technical: versions, restart reason, crash location, memory and sensor states — no names, e-mail, Wi-Fi passwords or locations. They stay on this iPhone until you delete them; Share sends one wherever you choose.")
            }
            if ReleaseFlags.diagUploadEnabled {
                Section {
                    Toggle("Send reports to the developer", isOn: $uploadConsent).onChange(of: uploadConsent) { _, v in DiagUploadHook.consent = v }
                } footer: { Text("Off unless you switch it on.") }
            }
        }
        .navigationTitle("BikeComputer reports").navigationBarTitleDisplayMode(.inline)
        .onAppear { diag.reload() }
    }
}

struct DiagReportRow: View {
    let meta: DiagReportMeta
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Image(systemName: meta.isCrash ? "exclamationmark.triangle.fill" : "doc.text").foregroundStyle(meta.isCrash ? BC.warn : .secondary)
                Text(meta.kindTitle).font(.subheadline.weight(.semibold))
                if !meta.seen { Circle().fill(BC.accent).frame(width: 7, height: 7).accessibilityLabel("new") }
                Spacer()
                Text("#\(meta.reportId)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
            Text(DiagFormat.summary(meta)).font(.caption2).foregroundStyle(.secondary)
            if !meta.summary.isEmpty { Text(meta.summary).font(.caption2.monospaced()).lineLimit(1) }
        }
    }
}

/// Full text of one report, Share and Delete.
struct DiagReportDetailView: View {
    @EnvironmentObject private var diag: DiagReportCenter
    @Environment(\.dismiss) private var dismiss
    let meta: DiagReportMeta
    @State private var text: String?
    @State private var confirmDelete = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(meta.kindTitle).font(.headline)
                    Text(DiagFormat.summary(meta)).font(.caption).foregroundStyle(.secondary)
                    if !meta.summary.isEmpty { Text(meta.summary).font(.caption.monospaced()) }
                    Text("Report #\(meta.reportId) · checksum \(meta.crcHex) verified · received \(meta.receivedAt.formatted(date: .abbreviated, time: .shortened))" + (meta.boardAcknowledged ? " · confirmed by the board" : "")).font(.caption2).foregroundStyle(.secondary)
                }
                HStack {
                    ShareLink(item: diag.fileURL(meta), preview: SharePreview("BikeComputer report #\(meta.reportId)")) { Label("Share", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.borderedProminent)
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }.buttonStyle(.bordered)
                }
                Divider()
                Text(text ?? "The report file could not be read.")
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
        .navigationTitle("Report #\(meta.reportId)").navigationBarTitleDisplayMode(.inline)
        .onAppear { text = diag.text(meta); diag.markSeen(meta) }
        .alert("Delete this report?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { diag.delete(meta); dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("It is removed from this iPhone and will not be downloaded again. Share it first if someone should see it.") }
    }
}

/// Home: the ONE short banner, only while a newly arrived crash report has not been looked at.
struct DiagCrashBanner: View {
    @EnvironmentObject private var diag: DiagReportCenter
    var body: some View {
        if let m = diag.unseenCrash {
            HStack(spacing: 8) {
                NavigationLink { DiagReportDetailView(meta: m) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(BC.warn)
                        Text("BikeComputer crashed earlier — report saved").font(.subheadline.weight(.semibold)).foregroundStyle(.primary).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
                Button { diag.dismissCrashBanner() } label: { Image(systemName: "xmark").font(.caption.bold()).foregroundStyle(.secondary).frame(width: 32, height: 32) }
                    .accessibilityLabel("Dismiss")
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(BC.warn.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityIdentifier("diagCrashBanner")
        }
    }
}
