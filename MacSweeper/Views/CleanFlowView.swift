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

    private let cleanup = CleanupService()

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

                    VStack(spacing: 10) {
                        ForEach(results) { result in
                            CategorySummaryCard(result: result)
                        }
                    }

                    Text(confirmFootnote)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(MSTheme.pagePadding)
            }

            VStack(spacing: 0) {
                Divider().opacity(0.5)
                HStack(spacing: 12) {
                    SecondaryCTAButton(title: "Cancel", expands: false) {
                        AppNavigation.popLast($navigationPath)
                    }
                    Spacer()
                    PrimaryCTAButton(title: primaryActionTitle, isEnabled: !results.isEmpty) {
                        requestClean()
                    }
                    .frame(maxWidth: 240)
                }
                .padding(.horizontal, MSTheme.pagePadding)
                .padding(.vertical, 14)
            }
        }
    }

    private var workingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)
                .tint(MSTheme.accent)
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

            ZStack {
                Circle()
                    .fill(MSTheme.accent.opacity(0.12))
                    .frame(width: 96, height: 96)
                    .scaleEffect(showDoneCelebration ? 1 : 0.7)
                    .opacity(showDoneCelebration ? 1 : 0)

                Image(systemName: didUndo ? "arrow.uturn.backward.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(MSTheme.accent)
                    .symbolRenderingMode(.hierarchical)
                    .scaleEffect(showDoneCelebration ? 1 : 0.7)
                    .opacity(showDoneCelebration ? 1 : 0)
            }

            if didUndo {
                Text("Restored \(outcome?.itemCount ?? 0) items")
                    .font(MSTheme.displayFont)
                    .opacity(showDoneCelebration ? 1 : 0)
                Text("Files were moved back from Trash.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Freed \(ByteCountFormatter.string(fromByteCount: outcome?.freedBytes ?? 0, countStyle: .file))")
                    .font(MSTheme.displayFont)
                    .monospacedDigit()
                    .opacity(showDoneCelebration ? 1 : 0)

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
                        .foregroundStyle(.orange)
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

            HStack(spacing: 12) {
                if !didUndo {
                    if outcome?.emptiedTrash != true || !(outcome?.moved.isEmpty ?? true) {
                        SecondaryCTAButton(title: "Open Trash", expands: false) {
                            openTrash()
                        }
                    }

                    if let moved = outcome?.moved, !moved.isEmpty,
                       outcome?.permanentlyDeleted != true {
                        SecondaryCTAButton(title: "Undo", expands: false) {
                            Task { await performUndo() }
                        }
                    }
                }

                PrimaryCTAButton(title: "Done", expands: false) {
                    dismissToHome()
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(MSTheme.pagePadding)
        .onAppear {
            showDoneCelebration = false
            withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                showDoneCelebration = true
            }
        }
        .onChange(of: didUndo) { _, _ in
            showDoneCelebration = false
            withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
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
            phase = .done
        } catch is CancellationError {
            phase = .confirm
        } catch {
            errorMessage = error.localizedDescription
            phase = .confirm
        }
    }

    private func performUndo() async {
        guard let moved = outcome?.moved, !moved.isEmpty else { return }
        isRestoring = true
        phase = .working
        defer { isRestoring = false }

        do {
            let restored = try await cleanup.restoreFromTrash(moved)
            outcome = restored
            didUndo = restored.itemCount > 0
            phase = .done
        } catch {
            errorMessage = error.localizedDescription
            phase = .done
        }
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
