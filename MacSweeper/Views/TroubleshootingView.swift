import SwiftUI

struct TroubleshootingView: View {
    @Environment(\.dismiss) private var dismiss
    private let guides = TroubleshootingGuides.load()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Help")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(MSTheme.pagePadding)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Read-only help. MacSweeper never runs these commands. Copy one and paste it into Terminal yourself. These rarely help on a healthy Mac and none of them free disk space.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    ForEach(guides) { guide in
                        MSCard { TroubleshootingGuideCard(guide: guide) }
                    }
                }
                .padding(.horizontal, MSTheme.pagePadding)
                .padding(.bottom, MSTheme.pagePadding)
            }
        }
        .frame(minWidth: 560, minHeight: 520)
        .background(StageBackground())
    }
}

private struct TroubleshootingGuideCard: View {
    let guide: TroubleshootingGuide
    @State private var copiedCommand: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(guide.symptom).font(.headline)
            labeled("WHEN THIS HELPS", guide.whenItHelps)
            labeled("WHEN IT WON'T HELP", guide.whenItWontHelp)
            if guide.needsAdmin {
                Text("Needs your admin password in Terminal.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(MSTheme.warning)
            }
            ForEach(guide.commands, id: \.self) { command in
                HStack {
                    Text(command)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                    Spacer()
                    Button(copiedCommand == command ? "Copied" : "Copy command") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(command, forType: .string)
                        copiedCommand = command
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func labeled(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(body).font(.callout)
        }
    }
}
