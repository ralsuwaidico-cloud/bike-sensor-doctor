import SwiftUI

/// E1 data integrity: shown INSTEAD of the app when store.json could not be read, was written by a newer build, or holds
/// records that could not be set aside. Nothing is written while this screen is up; the athlete decides what happens.
struct StorageRecoveryView: View {
    @EnvironmentObject private var store: Store
    @State private var confirmFresh = false
    @State private var failed: String? = nil

    private var unreadableCopy: URL? {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: store.dir.path)) ?? []).filter { $0.hasPrefix("store.unreadable-") }.sorted()
        return names.last.map { store.dir.appendingPathComponent($0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange).accessibilityHidden(true)
                Text(title).font(.title2.bold()).accessibilityIdentifier("storageRecoveryTitle")
                Text(store.storageNotice ?? store.storage.explanation).font(.body)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                if let failed { Text(failed).font(.callout).foregroundStyle(.red) }
                if store.storage == .unreadable {
                    Button { if !store.retryOpeningStore() { failed = "Still not readable. Nothing was changed." } } label: { Text("Try again").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered).accessibilityIdentifier("storageRetry")
                    if store.canRestorePreviousCopy {
                        Button { if !store.restorePreviousCopy() { failed = "The previous copy could not be restored. Nothing was changed." } } label: { Text("Restore the previous copy").frame(maxWidth: .infinity) }
                            .buttonStyle(.borderedProminent).accessibilityIdentifier("storageRestorePrevious")
                        Text("The previous copy was made the last time Cyclift opened your data successfully. Sessions saved after that are not in it.").font(.footnote).foregroundStyle(.secondary)
                    }
                    if let u = unreadableCopy { ShareLink(item: u) { Text("Send the unreadable file").frame(maxWidth: .infinity) }.buttonStyle(.bordered) }
                    Button(role: .destructive) { confirmFresh = true } label: { Text("Start again with no data").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered).accessibilityIdentifier("storageStartFresh")
                }
            }.padding(24)
        }
        .background(Color(.systemBackground))
        .onAppear { store.retryOpeningStore() }      // e.g. the file was unreadable only because the iPhone was locked at launch
        .alert("Start again with no data?", isPresented: $confirmFresh) {
            Button("Start again", role: .destructive) { if !store.startFreshAfterUnreadableStore() { failed = "Cyclift could not keep a copy of the unreadable file, so nothing was changed." } }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Your plan, rides and strength history will not be shown. The unreadable file stays on this iPhone so it can still be examined.") }
    }

    private var title: String {
        switch store.storage {
        case .newerVersion: return "Update Cyclift to open your data"
        default: return "Your data could not be opened"
        }
    }
    private var detail: String {
        switch store.storage {
        case .newerVersion: return "Install the newer version of Cyclift again. Until then this version shows nothing and saves nothing, so your data stays exactly as it is."
        case .cannotSetAside: return "Free some storage on this iPhone and open Cyclift again."
        default: return "This can happen after an interrupted save or when storage is full. Cyclift has not replaced the file."
        }
    }
}

/// E1: one line above every screen while something about storage needs the athlete's attention. A failing write stays
/// until a write succeeds; a launch notice (records set aside, previous copy restored) stays until OK is tapped.
struct StorageBanner: View {
    @EnvironmentObject private var store: Store
    var body: some View {
        if store.storage.isWritable, let text = store.lastSaveError.map({ "Your latest changes could not be saved: \($0)" }) ?? store.storageNotice {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).accessibilityHidden(true)
                Text(text).font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
                if store.lastSaveError == nil { Button("OK") { store.dismissStorageNotice() }.font(.footnote.bold()).accessibilityIdentifier("storageBannerOK") }
            }
            .padding(10).background(Color(.secondarySystemBackground)).accessibilityIdentifier("storageBanner")
        }
    }
}
