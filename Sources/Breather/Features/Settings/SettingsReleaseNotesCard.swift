import AppKit
import SwiftUI

struct SettingsReleaseNotesCard: View {
    @ObservedObject private var localizationRefresh = LocalizationRefresh.shared
    let notes: InstalledReleaseNotes
    let onDismiss: () -> Void
    private let maximumHighlightsHeight: CGFloat = 160
    private let topInset: CGFloat = 4
    private let dismissButtonSize: CGFloat = 22

    var body: some View {
        let _ = localizationRefresh.revision
        VStack(alignment: .leading, spacing: 4) {
            Text(String(format: L.tr("已更新到 %@"), notes.version))
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 3)
                .frame(maxWidth: .infinity, minHeight: dismissButtonSize - topInset, alignment: .bottomLeading)
                .padding(.trailing, dismissButtonSize + 4)
                .accessibilityAddTraits(.isHeader)
                .overlay(alignment: .bottomTrailing) { dismissButton }

            ViewThatFits(in: .vertical) {
                highlights.fixedSize(horizontal: false, vertical: true)
                ScrollView { highlights }
                    .frame(height: maximumHighlightsHeight)
            }
            .frame(maxHeight: maximumHighlightsHeight)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(EdgeInsets(top: topInset, leading: 10, bottom: 10, trailing: 10))
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.quaternary, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
    }

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)
                .frame(width: dismissButtonSize, height: dismissButtonSize, alignment: .bottom)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L.tr("关闭本版更新提示"))
        .accessibilityLabel(L.tr("关闭本版更新提示"))
        .accessibilityIdentifier("dismiss-installed-release-notes")
    }

    private var highlights: some View {
        let lines = notes.localizedHighlights()
        return VStack(alignment: .leading, spacing: 5) {
            ForEach(lines.indices, id: \.self) { index in
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("•").accessibilityHidden(true)
                    Text(lines[index]).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
