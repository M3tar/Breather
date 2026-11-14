import SwiftUI

struct SettingsResetReceipt: View {
    let preview: SettingsResetPreview
    let width: CGFloat
    let maximumHeight: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.settingsResetTransition) private var resetTransition
    @State private var contentHeight: CGFloat?
    @State private var feedProgress: CGFloat = 0
    @State private var correctionsStarted = false
    private let paperInset: CGFloat = 6
    private let textInset: CGFloat = 16

    private struct PresentationState: Hashable {
        let measured: Bool
        let reduceMotion: Bool
    }

    private var otherThemes: [SettingsResetChange] {
        preview.changes.filter { change in
            if case let .theme(theme) = change.group {
                return preview.scope == .restOverlay && theme != AppSettings().restOverlayContentMode
            }
            return false
        }
    }

    private var primaryChanges: [SettingsResetChange] {
        preview.changes.filter { change in !otherThemes.contains(where: { $0.id == change.id }) }
    }

    var body: some View {
        let palette = SettingsResetPaperPalette(colorScheme: colorScheme)
        let columns = SettingsResetColumns(changes: preview.changes,
                                          width: width - (paperInset + textInset) * 2)
        let height = min(maximumHeight, contentHeight ?? CGFloat(preview.changes.count) * 62 + 48)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                columnLabels(columns, palette: palette)
                changes(primaryChanges, columns: columns, palette: palette, isOtherTheme: false)
                if !otherThemes.isEmpty {
                    if !primaryChanges.isEmpty { rule(palette).padding(.top, 6).padding(.bottom, 10) }
                    Text(L.tr("其他主题设置"))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(palette.ink)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.bottom, 4)
                    changes(otherThemes, columns: columns, palette: palette, isOtherTheme: true)
                }
            }
            .padding(.horizontal, textInset)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollIndicators(.automatic)
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: height)
        .background(palette.paper)
        .padding(.bottom, 4)
        .background(palette.paper)
        .clipShape(SettingsResetPaperShape())
        .overlay {
            SettingsResetPaperShape().stroke(palette.edge, lineWidth: 0.5).allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.14 : 0.06), radius: 3, y: 2)
        .offset(y: -(height + 9) * (1 - (reduceMotion ? 1 : feedProgress)))
        .padding(.horizontal, paperInset)
        .padding(.top, 2)
        .padding(.bottom, 9)
        .clipped()
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 2)
                .fill(palette.slot)
                .frame(height: 4)
                .overlay(alignment: .top) {
                    RoundedRectangle(cornerRadius: 1).fill(palette.lip).frame(height: 1)
                }
                .padding(.horizontal, 2)
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
        .task(id: PresentationState(measured: contentHeight != nil, reduceMotion: reduceMotion)) {
            // Start from a measured, laid-out sheet. A wall-clock TimelineView can
            // skip most of the feed while native sheet presentation is still busy.
            if reduceMotion {
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    feedProgress = 1
                    correctionsStarted = true
                }
                return
            }
            guard contentHeight != nil else { return }
            // Turning motion back on must not retract a receipt already on screen.
            guard feedProgress == 0 else { correctionsStarted = true; return }
            // The cold JS/texture setup must not block the first pen frame midway
            // through the feed. This shared, UI-independent cache survives dismissal.
            await Task.detached(priority: .userInitiated) { _ = LooseleafResetInk.shared }.value
            guard !Task.isCancelled else { return }
            let generation = resetTransition?.generation
            withAnimation(.smooth(duration: SettingsResetPaperFeed.duration, extraBounce: 0)) {
                feedProgress = 1
            } completion: {
                // Do not compete with the paper feed for main-thread raster time.
                // A late completion from a dismissed receipt cannot prepare a new one.
                if let generation { resetTransition?.confirmationContentReady(generation: generation) }
            }
            do {
                try await Task.sleep(for: .seconds(SettingsResetPaperFeed.correctionStart))
                correctionsStarted = true
            } catch { }
        }
    }

    private func columnLabels(_ columns: SettingsResetColumns, palette: SettingsResetPaperPalette) -> some View {
        VStack(spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: SettingsResetColumns.gap) {
                if let labelWidth = columns.labelWidth {
                    Text(L.tr("设置项")).frame(width: labelWidth, alignment: .leading)
                }
                Text(L.tr("当前值")).frame(width: columns.oldWidth, alignment: .leading)
                Text(L.tr("还原后"))
                    .frame(maxWidth: .infinity, alignment: columns.labelWidth == nil ? .leading : .trailing)
            }
            .font(.caption)
            .foregroundStyle(palette.secondaryInk)
            .accessibilityHidden(true)
            rule(palette)
        }
        .padding(.bottom, 5)
    }

    private func changes(_ changes: [SettingsResetChange], columns: SettingsResetColumns,
                         palette: SettingsResetPaperPalette, isOtherTheme: Bool) -> some View {
        ForEach(Array(changes.enumerated()), id: \.element.id) { index, change in
            if let group = change.contextHeading(after: index == 0 ? nil : changes[index - 1]) {
                Text(group.title)
                    .font(isOtherTheme ? .caption : .callout.weight(.semibold))
                    .foregroundStyle(isOtherTheme ? palette.secondaryInk : palette.ink)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.top, 8)
            }
            SettingsResetChangeRow(change: change, index: index + (isOtherTheme ? primaryChanges.count : 0),
                                   bottomInset: index + 1 < changes.count && changes[index + 1].group == change.group ? 4 : 10,
                                   columns: columns, showCorrections: correctionsStarted,
                                   ink: palette.ink, secondaryInk: palette.secondaryInk)
        }
    }

    private func rule(_ palette: SettingsResetPaperPalette) -> some View {
        Rectangle().stroke(style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
            .foregroundStyle(palette.edge).frame(height: 0.5).accessibilityHidden(true)
    }
}

enum SettingsResetPaperFeed {
    static let duration: TimeInterval = 0.600
    static let correctionStart: TimeInterval = 0.380
    static let correctionDuration: TimeInterval = 0.150

    static func correctionDelay(for index: Int) -> TimeInterval {
        switch index {
        case ...0: 0
        case 1: 0.050
        default: 0.070
        }
    }
}

private struct SettingsResetPaperShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: rect.origin)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 4))
        let teeth = max(1, Int(rect.width / 8))
        let step = rect.width / CGFloat(teeth)
        for tooth in stride(from: teeth, to: 0, by: -1) {
            path.addLine(to: CGPoint(x: rect.minX + (CGFloat(tooth) - 0.5) * step, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + CGFloat(tooth - 1) * step, y: rect.maxY - 4))
        }
        path.closeSubpath()
        return path
    }
}

private struct SettingsResetPaperPalette {
    let paper: Color
    let ink: Color
    let secondaryInk: Color
    let edge: Color
    let slot: Color
    let lip: Color

    init(colorScheme: ColorScheme) {
        let dark = colorScheme == .dark
        paper = dark ? Color(red: 52/255, green: 51/255, blue: 47/255) : Color(red: 1, green: 253/255, blue: 246/255)
        ink = dark ? Color(red: 241/255, green: 238/255, blue: 229/255) : Color(red: 39/255, green: 39/255, blue: 33/255)
        secondaryInk = dark ? Color(red: 192/255, green: 186/255, blue: 173/255) : Color(red: 101/255, green: 97/255, blue: 89/255)
        edge = dark ? Color(red: 98/255, green: 94/255, blue: 83/255) : Color(red: 212/255, green: 204/255, blue: 189/255)
        slot = dark ? Color(red: 21/255, green: 22/255, blue: 24/255) : Color(red: 102/255, green: 99/255, blue: 94/255)
        lip = dark ? Color(red: 91/255, green: 91/255, blue: 94/255) : Color(red: 130/255, green: 126/255, blue: 119/255)
    }
}
