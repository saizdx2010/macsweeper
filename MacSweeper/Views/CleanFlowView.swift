import AppKit
import SwiftUI

struct CleanFlowView: View {
    let results: [ScanResult]
    @Binding var navigationPath: NavigationPath

    @EnvironmentObject private var auditLog: AuditLogService
    @EnvironmentObject private var settings: AppSettings

    @State private var phase: Phase = .confirm
    @State private var outcome: CleanupService.Outcome?
    @State private var showConfirmation = false
    @State private var showFDAPrompt = false
    @State private var errorMessage: String?
    @State private var isRestoring = false
    @State private var didUndo = false
    @State private var showDoneCelebration = false
    @State private var cleanProgress: CleanupService.Progress?
    @State private var freeSpaceBeforeClean: Int64?
    @State private var observedGainBytes: Int64?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let cleanup = CleanupService()
    private let diskSpace = DiskSpaceService()

    private var totalBytes: Int64 {
        results.reduce(0) { $0 + $1.totalBytes }
    }

    private var totalItems: Int {
        results.reduce(0) { $0 + $1.paths.count }
    }

    private var sizeLabel: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    private var includesEmptyTrash: Bool {
        results.contains { $0.category.action == .emptyTrash }
    }

    private var includesMoveToTrash: Bool {
        results.contains { $0.category.action != .emptyTrash }
    }

    /// When the user opted into immediate deletion, cleaned items are permanently
    /// removed right after the move instead of resting in Trash for undo.
    private var deletesPermanently: Bool {
        settings.deleteImmediately
    }

    private var needsExtraConfirmation: Bool {
        CleanConfirmPolicy.requiresConfirmation(results: results)
    }

    private var categoryWord: String {
        results.count == 1 ? "category" : "categories"
    }

    enum Phase {
        case confirm
        case working
        case done
    }

    var body: some View {
        ZStack {
            StageBackground()

            Group {
                switch phase {
                case .confirm:
                    confirmView
                case .working:
                    workingView
                case .done:
                    doneView
                }
            }
        }
        .appDestinationChrome(
            title: "Clean",
            showsBack: phase == .confirm,
            onBack: { AppNavigation.popLast($navigationPath) }
        )
        .confirmationDialog(
            confirmationTitle,
            isPresented: $showConfirmation,
            titleVisibility: .visible
        ) {
            Button(primaryConfirmButtonTitle, role: .destructive) {
                Task { await performClean() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmationMessage)
        }
        .alert("Full Disk Access needed", isPresented: $showFDAPrompt) {
            Button("Open System Settings") {
                FullDiskAccessService.openSystemSettings()
            }
            Button("Continue anyway", role: .destructive) {
                showConfirmation = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("We need Full Disk Access to empty Trash completely. Files never leave your Mac.")
        }
        .alert("Clean failed", isPresented: Binding(
            get: { errorMessage != nil && phase == .confirm },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var workingLabel: String {
        let verb = deletesPermanently ? "Deleting" : "Moving"
        if isRestoring { return "Restoring…" }
        if let progress = cleanProgress {
            if includesEmptyTrash && progress.label.lowercased().contains("trash") {
                return "Emptying Trash…"
            }
            return "\(verb) \(progress.label)…"
        }
        if includesEmptyTrash && !includesMoveToTrash { return "Emptying Trash…" }
        if includesEmptyTrash { return "Cleaning \(results.count) \(categoryWord)…" }
        return "\(verb) \(results.count) \(categoryWord)…"
    }

    private var workingSubtitle: String {
        if isRestoring {
            return "This usually only takes a moment"
        }
        if let progress = cleanProgress, progress.total > 0 {
            return "\(progress.current) of \(progress.total)"
        }
        return "This usually only takes a moment"
    }

    private var confirmationTitle: String {
        if includesEmptyTrash && !includesMoveToTrash {
            return "Permanently empty Trash (\(sizeLabel))?"
        }
        if includesEmptyTrash {
            return "Clean \(sizeLabel)? Some items are permanent."
        }
        if case .largeModerate = CleanConfirmPolicy.confirmationReason(results: results) {
            return deletesPermanently
                ? "Permanently delete \(sizeLabel)? Includes large Moderate items."
                : "Move \(sizeLabel) to Trash? Includes large Moderate items."
        }
        return deletesPermanently
            ? "Permanently delete \(sizeLabel)?"
            : "Move \(sizeLabel) to Trash?"
    }

    private var primaryConfirmButtonTitle: String {
        if includesEmptyTrash && !includesMoveToTrash {
            return "Empty Trash"
        }
        if includesEmptyTrash {
            return "Clean"
        }
        return deletesPermanently ? "Delete" : "Move to Trash"
    }

    private var confirmationMessage: String {
        let itemWord = totalItems == 1 ? "item" : "items"
        if includesEmptyTrash && !includesMoveToTrash {
            return "This permanently deletes \(totalItems) \(itemWord) in Trash. It cannot be undone."
        }
        if includesEmptyTrash {
            let moveTo = deletesPermanently
                ? "Other items are permanently deleted too."
                : "Other items move to Trash."
            return "\(results.count) \(categoryWord) · \(totalItems) \(itemWord). Empty Trash cannot be undone; \(moveTo)"
        }
        if case .largeModerate(let bytes) = CleanConfirmPolicy.confirmationReason(results: results) {
            let moderateLabel = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            if deletesPermanently {
                return "\(results.count) \(categoryWord) · \(totalItems) \(itemWord), including \(moderateLabel) Moderate-risk. They are permanently deleted and may need re-download or re-login."
            }
            return "\(results.count) \(categoryWord) · \(totalItems) \(itemWord), including \(moderateLabel) Moderate-risk. These may need re-download or re-login."
        }
        return deletesPermanently
            ? "\(results.count) \(categoryWord) · \(totalItems) \(itemWord). Items are permanently deleted right away. This cannot be undone."
            : "\(results.count) \(categoryWord) · \(totalItems) \(itemWord). Items move to Trash and can be restored anytime."
    }

    private var confirmHeadline: String {
        if includesEmptyTrash && !includesMoveToTrash {
            return "Empty Trash · \(sizeLabel)"
        }
        if includesEmptyTrash {
            return "Clean \(results.count) \(categoryWord) · \(sizeLabel)"
        }
        return deletesPermanently
            ? "Permanently delete \(results.count) \(categoryWord) · \(sizeLabel)"
            : "Move \(results.count) \(categoryWord) · \(sizeLabel) to Trash"
    }

    private var confirmView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: MSTheme.sectionSpacing) {
                    Text(confirmHeadline)
                        .font(MSTheme.titleFont)

                    MSGroupedRows(items: results) { _, result in
                        CategorySummaryRow(result: result)
                    }

                    Text(confirmFootnote)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(MSTheme.pagePadding)
            }

            VStack(spacing: 0) {
                Rectangle().fill(MSTheme.hairline).frame(height: 1)
                HStack(spacing: 12) {
                    SecondaryCTAButton(title: "Cancel", expands: false) {
                        AppNavigation.popLast($navigationPath)
                    }
                    Spacer()
                    PrimaryCTAButton(title: primaryActionTitle, icon: .clean, isEnabled: !results.isEmpty, expands: false) {
                        requestClean()
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                }
                .padding(.horizontal, MSTheme.pagePadding)
                .padding(.vertical, 14)
            }
        }
    }

    private var workingView: some View {
        VStack(spacing: 20) {
            ScanSweepRing(progress: workingFraction, size: 150) {
                Text(workingPercent)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(MSMotion.fast, value: workingPercent)
            }
            .animation(MSMotion.base, value: workingFraction)
            Text(workingLabel)
                .font(MSTheme.titleFont)
                .multilineTextAlignment(.center)
                .animation(.easeInOut(duration: 0.2), value: cleanProgress?.label)
            Text(workingSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .animation(.easeInOut(duration: 0.2), value: cleanProgress?.current)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var workingFraction: Double {
        guard let progress = cleanProgress, progress.total > 0 else { return 0 }
        return Double(progress.current) / Double(progress.total)
    }

    private var workingPercent: String {
        guard cleanProgress != nil else { return "…" }
        return "\(Int((workingFraction * 100).rounded()))%"
    }

    private var primaryActionTitle: String {
        if includesEmptyTrash && !includesMoveToTrash {
            return "Empty Trash"
        }
        return "Clean \(sizeLabel)"
    }

    private var confirmFootnote: String {
        if includesEmptyTrash && !includesMoveToTrash {
            return "Emptying Trash permanently deletes files. This cannot be undone."
        }
        if includesEmptyTrash {
            return deletesPermanently
                ? "Selected items are permanently deleted, including Empty Trash."
                : "Selected items move to Trash except Empty Trash, which permanently deletes."
        }
        if case .largeModerate = CleanConfirmPolicy.confirmationReason(results: results) {
            return deletesPermanently
                ? "Large Moderate selection — review carefully. Items are permanently deleted."
                : "Large Moderate selection — review carefully. Items still move to Trash and can be restored."
        }
        return deletesPermanently
            ? "Items are permanently deleted right away — space is freed immediately. This cannot be undone."
            : "Items move to Trash. You can restore them from Trash anytime."
    }

    private var doneView: some View {
        VStack(spacing: 20) {
            Spacer()

            DoneCheckView(isUndo: didUndo)

            if didUndo {
                Text("Restored \(outcome?.itemCount ?? 0) items")
                    .font(MSTheme.displayFont)
                    .opacity(showDoneCelebration ? 1 : 0)
                Text(auditLog.undoMessage ?? "Files were moved back from Trash.")
                    .foregroundStyle(.secondary)
            } else {
                CountingBytesText(
                    bytes: showDoneCelebration ? Double(outcome?.freedBytes ?? 0) : 0,
                    prefix: "Freed "
                )
                .font(MSTheme.displayFont)
                .opacity(showDoneCelebration ? 1 : 0)
                .accessibilityLabel("Freed \(ByteCountFormatter.string(fromByteCount: outcome?.freedBytes ?? 0, countStyle: .file))")

                if let gain = observedGainBytes, gain > 0 {
                    Text("Finder now shows about +\(ByteCountFormatter.string(fromByteCount: gain, countStyle: .file)) free")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .accessibilityLabel("Finder now shows about \(ByteCountFormatter.string(fromByteCount: gain, countStyle: .file)) more free space")
                }

                if outcome?.emptiedTrash == true && !(outcome?.moved.isEmpty == false) {
                    Text("\(outcome?.itemCount ?? 0) items permanently deleted from Trash")
                        .foregroundStyle(.secondary)
                } else if outcome?.emptiedTrash == true {
                    Text("\(outcome?.itemCount ?? 0) items cleaned (including Empty Trash)")
                        .foregroundStyle(.secondary)
                } else if outcome?.permanentlyDeleted == true {
                    Text("\(outcome?.itemCount ?? 0) items deleted — space freed")
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(outcome?.itemCount ?? 0) items moved to Trash")
                        .foregroundStyle(.secondary)
                }

                if let failures = outcome?.failures, !failures.isEmpty {
                    Text("\(failures.count) item\(failures.count == 1 ? "" : "s") could not be cleaned.")
                        .font(.footnote)
                        .foregroundStyle(MSTheme.warning)
                }

                if outcome?.permanentlyDeleted == true && outcome?.emptiedTrash != true {
                    Text("Items were permanently deleted, so there is nothing to undo.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                } else if outcome?.emptiedTrash != true {
                    Text("Undo restores items still in Trash, or open Trash in Finder.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                } else if outcome?.moved.isEmpty == false {
                    Text("Undo restores moved items still in Trash. Emptied Trash cannot be undone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
            }

            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                if !didUndo {
                    if outcome?.emptiedTrash != true || !(outcome?.moved.isEmpty ?? true) {
                        SecondaryCTAButton(title: "Open Trash", expands: false) {
                            openTrash()
                        }
                    }

                    if let moved = outcome?.moved, !moved.isEmpty,
                       outcome?.permanentlyDeleted != true {
                        SecondaryCTAButton(title: "Undo last clean", expands: false) {
                            Task { await performUndo() }
                        }
                    }
                }

                PrimaryCTAButton(title: "Done", expands: false) {
                    dismissToHome()
                }
                .keyboardShortcut(.defaultAction)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(MSTheme.pagePadding)
        .onAppear {
            showDoneCelebration = false
            withAnimation(MSMotion.resolve(.smooth(duration: 1.1), reduceMotion: reduceMotion).delay(0.3)) {
                showDoneCelebration = true
            }
        }
        .onChange(of: didUndo) { _, _ in
            showDoneCelebration = false
            withAnimation(MSMotion.resolve(.smooth(duration: 1.1), reduceMotion: reduceMotion).delay(0.3)) {
                showDoneCelebration = true
            }
        }
    }

    private func requestClean() {
        if includesEmptyTrash && !FullDiskAccessService.isGranted() {
            showFDAPrompt = true
        } else if needsExtraConfirmation {
            showConfirmation = true
        } else {
            Task { await performClean() }
        }
    }

    private func performClean() async {
        phase = .working
        errorMessage = nil
        didUndo = false
        cleanProgress = nil
        observedGainBytes = nil
        freeSpaceBeforeClean = diskSpace.currentSnapshot()?.freeBytes
        do {
            let result = try await cleanup.moveToTrash(
                results,
                deleteImmediately: settings.deleteImmediately
            ) { progress in
                await MainActor.run {
                    cleanProgress = progress
                }
            }
            outcome = result
            auditLog.finishClean(outcome: result)
            // Re-read free space so the done screen can show what Finder sees.
            observedGainBytes = FreeSpaceDelta.gainBytes(
                before: freeSpaceBeforeClean,
                after: diskSpace.currentSnapshot()?.freeBytes
            )
            phase = .done
        } catch is CancellationError {
            phase = .confirm
        } catch {
            errorMessage = error.localizedDescription
            phase = .confirm
        }
    }

    private func performUndo() async {
        guard !auditLog.lastUndoItems.isEmpty else { return }
        isRestoring = true
        phase = .working
        defer { isRestoring = false }

        if let restored = await auditLog.undoLastClean() {
            outcome = restored
            didUndo = true
        } else {
            errorMessage = auditLog.undoMessage
        }
        phase = .done
    }

    private func openTrash() {
        let trash = URL(fileURLWithPath: "\(NSHomeDirectory())/.Trash", isDirectory: true)
        NSWorkspace.shared.open(trash)
    }

    private func dismissToHome() {
        AppNavigation.popToRoot($navigationPath)
    }
}

#Preview {
    NavigationStack {
        CleanFlowView(results: [], navigationPath: .constant(NavigationPath()))
            .environmentObject(AuditLogService())
            .environmentObject(AppSettings())
    }
}
