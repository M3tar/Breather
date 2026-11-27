import SwiftUI

extension RestDay {
    func message(today: Bool) -> (String, String) {
        if events.isEmpty {
            return (L.tr(today ? "今天还没有休息记录" : "当天没有休息记录"), "")
        }
        if clean {
            let copy = onlyRecognized
                ? (today ? "今天也有好好休息，太厉害了吧！" : "那天也有好好休息，太厉害了吧！")
                : (today ? "今天居然一次没漏全打卡，太厉害了吧！" : "那天居然一次没漏全打卡，太厉害了吧！")
            return ("Awesome! 🎉", L.tr(copy))
        }
        if completed == 0 {
            return (today ? "GOGOGO!" : "Busy Day!", L.tr(today ? "今天坐得有点久啦，快起来溜达两步吧！" : "那天一定忙飞了吧！下次记得起来溜达两步！"))
        }
        return ("Nice Move!", L.tr(today ? "忙归忙，今天也记得多起来透透气，继续保持！" : "那天再忙也没一直粘在椅子上，必须点赞！"))
    }
}

struct RestHistoryScreen: View {
    @EnvironmentObject private var history: RestHistory
    @State var range = 7
    @State var selection: Date?
    @State private var cellPointer: UnitPoint?
    @State private var hoveredBar: Date?
    @State private var cardPointer: UnitPoint?
    @Environment(\.colorScheme) private var scheme
    private var palette: RestHistoryPalette { RestHistoryPalette(scheme: scheme, month: range == 30) }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    static func recordTime(_ date: Date, locale: Locale) -> String {
        switch locale.hourCycle {
        case .zeroToTwentyThree, .oneToTwentyFour:
            return date.formatted(.dateTime.locale(locale).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        default:
            return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale))
        }
    }

    private var tracksCells: Bool { !reduceMotion && !reduceTransparency }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)
    private var locale: Locale { Locale(identifier: AppLanguage.effective.rawValue) }

    private func date(_ day: Date, _ style: Date.FormatStyle) -> String {
        day.formatted(style.locale(locale))
    }

    var body: some View {
        let days = history.days(range)
        let selected = days.first { $0.id == selection } ?? days[days.count - 1]
        GeometryReader { geometry in
            let content = VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(L.tr("休息记录")).font(.system(size: 14, weight: .semibold))
                    Spacer()
                    HStack(spacing: 2) {
                        ForEach([7, 30], id: \.self) { value in
                            Button(L.tr(value == 7 ? "最近 7 天" : "最近 30 天")) { range = value }
                                .buttonStyle(.plain).font(.system(size: 12))
                                .padding(.horizontal, geometry.size.width < 400 ? 6 : 12).padding(.vertical, 3)
                                .foregroundStyle(value == range ? palette.rangeSelectionText : palette.ink)
                                .background(value == range ? palette.rangeSelection : .clear, in: RoundedRectangle(cornerRadius: 4))
                                .accessibilityAddTraits(value == range ? .isSelected : [])
                        }
                    }
                    .padding(2).background(palette.panel, in: RoundedRectangle(cornerRadius: 7))
                    .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(palette.line) }
                }
                if history.unavailable {
                    HStack {
                        Text(L.tr("暂时无法读写休息记录"))
                        Button(L.tr("重试")) { history.retry() }
                    }
                }
                VStack(alignment: .leading, spacing: 9) {
                    let period = Text(date(days[0].id, .dateTime.month().day()) + " – " + date(history.today, .dateTime.month().day()))
                    let totals = Text(summary(days.reduce(0) { $0 + $1.completed }, days.reduce(0) { $0 + $1.skipped }))
                    ViewThatFits(in: .horizontal) {
                        HStack { period; Spacer(); totals }
                        VStack(alignment: .leading, spacing: 3) { period; totals }
                    }.font(.system(size: 13)).foregroundStyle(palette.muted)
                    if range == 7 {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 14) {
                                legend(L.tr("休息", context: "restHistory"), color: palette.completeBar)
                                legend(L.tr("跳过", context: "restHistory"), color: palette.skipBar, textColor: palette.skipText)
                            }
                            week(days, selected: selected.id)
                        }
                    } else {
                        monthLegend
                        calendar(days, selected: selected.id, availableHeight: geometry.size.height)
                            .padding(.top, 7)
                    }
                }.padding(16).background(palette.panel, in: RoundedRectangle(cornerRadius: 12))
                TiltedRestDetailCard(content: detail(selected), pointer: reduceMotion ? nil : cardPointer, animated: !reduceMotion)
                    .background {
                        RestHistoryPointerArea { point in
                            if cardPointer != point { cardPointer = point }
                        }.allowsHitTesting(false)
                    }
                    .layoutPriority(-1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, SettingsWindowMetrics.contentHorizontalPadding)
            .padding(.vertical, 16)
            .frame(maxWidth: SettingsWindowMetrics.contentMaxWidth + 2 * SettingsWindowMetrics.contentHorizontalPadding)
            if geometry.size.width < 400 && range == 30 {
                ScrollView { content.fixedSize(horizontal: false, vertical: true) }
            } else {
                content.frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            }
        }
        .foregroundStyle(palette.ink)
        .background(palette.paper)
        .onChange(of: tracksCells) { cellPointer = nil }
        .onChange(of: history.today) { cellPointer = nil }
        .onChange(of: range) { _, value in
            cellPointer = nil
            if !history.days(value).contains(where: { $0.id == selection }) { selection = nil }
        }
    }

    private func breaksTaken(_ count: Int) -> String {
        count == 1 ? L.tr("休息 1 次") : String(format: L.tr("休息 %ld 次"), count)
    }

    private func skippedCount(_ count: Int) -> String {
        String(format: L.tr("跳过 %ld 次"), count)
    }

    private func statistics(_ completed: Int, _ skipped: Int) -> String {
        String(format: L.tr("%@，%@"), breaksTaken(completed), skippedCount(skipped))
    }

    private func summary(_ completed: Int, _ skipped: Int) -> AttributedString {
        let sentence = statistics(completed, skipped)
        var text = AttributedString(sentence)
        for number in sentence.matches(of: /[0-9]+/) {
            if let range = Range(number.range, in: text) {
                text[range].font = .system(size: 13, weight: .semibold)
                text[range].foregroundColor = palette.ink
            }
        }
        return text
    }

    private func legend(_ title: String, color: Color, textColor: Color? = nil) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 7, height: 7)
            Text(title).font(.system(size: 12)).foregroundStyle(textColor ?? palette.muted)
        }
    }

    private var monthLegend: some View {
        let counts = HStack(spacing: 5) {
            Text(L.tr("休息", context: "restHistory")).foregroundStyle(palette.completeText)
            Text("/")
            Text(L.tr("跳过", context: "restHistory")).foregroundStyle(palette.skipText)
            Text(L.tr("（次）"))
        }
        let badges = HStack(spacing: 5) {
            RestHistoryMark.completed.frame(width: 16, height: 16).foregroundStyle(palette.completeText)
            Text(L.tr("零跳过"))
            RestHistoryMark.skipped.frame(width: 16, height: 16).foregroundStyle(palette.skipText).padding(.leading, 6)
            Text(L.tr("全部跳过"))
        }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 5) { counts; badges }
            VStack(alignment: .leading, spacing: 4) { counts; badges }
        }.font(.system(size: 12)).foregroundStyle(palette.muted)
    }

    private func dayButton<Content: View>(_ day: RestDay, selected: Date, @ViewBuilder content: () -> Content) -> some View {
        let fullDate = date(day.id, .dateTime.year().month().day().weekday())
        let counts = statistics(day.completed, day.skipped)
        return Button {
            cardPointer = nil
            cellPointer = nil
            selection = day.id
        } label: {
            content().frame(maxWidth: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay {
            if range == 30 && day.id == selected {
                RoundedRectangle(cornerRadius: 5).strokeBorder(palette.selectionBorder, lineWidth: 1.5)
                    .shadow(color: .black.opacity(scheme == .dark ? 0.33 : 0.15), radius: 2.5, y: 2).allowsHitTesting(false)
            }
        }
        .help(fullDate + "\n" + counts)
        .accessibilityLabel(fullDate)
        .accessibilityValue(counts)
        .accessibilityAddTraits(day.id == selected ? .isSelected : [])
    }

    private func week(_ days: [RestDay], selected: Date) -> some View {
        let maximum = max(1, days.map { $0.events.count }.max() ?? 0)
        let crossesMonth = !Calendar.current.isDate(days[0].id, equalTo: history.today, toGranularity: .month)
        return HStack(alignment: .bottom, spacing: 6) {
            ForEach(days) { day in
                GeometryReader { column in
                    let barWidth = min(28, max(18, column.size.width * 0.25))
                    let showsMonth = crossesMonth && (day.id == days.first?.id || Calendar.current.component(.day, from: day.id) == 1)
                    dayButton(day, selected: selected) {
                        let active = day.id == selected
                        VStack(spacing: 5) {
                            weekBar(day, maximum: maximum, barWidth: barWidth, columnWidth: column.size.width)
                                .frame(maxWidth: .infinity, minHeight: 90, maxHeight: 90, alignment: .bottom)
                            Text(date(day.id, showsMonth ? (column.size.width < 45 ? .dateTime.month(.defaultDigits).day() : .dateTime.month().day()) : .dateTime.day()))
                                .lineLimit(1).minimumScaleFactor(0.8)
                                .fontWeight(active ? .semibold : .regular)
                                .foregroundStyle(active ? palette.ink : palette.muted)
                                .padding(.vertical, 3.5)
                                .overlay(alignment: .bottom) {
                                    if active {
                                        Capsule().fill(palette.weekUnderline).frame(width: 14, height: 2)
                                    }
                                }
                            Text(date(day.id, .dateTime.weekday(.abbreviated)))
                                .font(.system(size: 11)).foregroundStyle(palette.muted)
                        }.font(.system(size: 12)).padding(.vertical, 5)
                        .frame(maxWidth: .infinity)
                        .background {
                            if active {
                                palette.weekSelection
                            } else if hoveredBar == day.id {
                                palette.weekHover
                            }
                        }.clipShape(RoundedRectangle(cornerRadius: 6))
                        .onHover { inside in
                            if inside { hoveredBar = day.id } else if hoveredBar == day.id { hoveredBar = nil }
                        }
                    }
                }
            }
        }.frame(height: 142)
    }

    private func weekBar(_ day: RestDay, maximum: Int, barWidth: CGFloat, columnWidth: CGFloat) -> some View {
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        // Leave room above the tallest bar for one line, or two in very narrow columns.
        let scale = min(12, (columnWidth < 50 ? 54 : 70) / CGFloat(maximum))
        let completed = day.completed
        let skipped = day.skipped
        let height = CGFloat(completed + skipped) * scale
        let labelWidth = [completed, skipped].map {
            (String($0) as NSString).size(withAttributes: [.font: font]).width
        }.max() ?? 0
        let crowded = completed > 0 && skipped > 0 && height / 2 < ceil(font.capHeight) + 2
        let above = crowded || labelWidth + 4 > (columnWidth - barWidth) / 2

        return VStack(spacing: 3) {
            if day.events.isEmpty {
                Text("0").font(.system(size: 11, weight: .medium)).foregroundStyle(palette.muted)
                Capsule().fill(palette.line).frame(width: 18, height: 2)
            } else {
                if above {
                    let taken = Text(String(completed)).foregroundStyle(palette.completeText)
                    let missed = Text(String(skipped)).foregroundStyle(palette.skipText)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 2) {
                            if completed > 0 { taken }
                            if completed > 0 && skipped > 0 { Text("/").foregroundStyle(palette.muted) }
                            if skipped > 0 { missed }
                        }.fixedSize()
                        VStack(spacing: 0) {
                            if skipped > 0 { missed }
                            if completed > 0 { taken }
                        }.lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
                VStack(spacing: 0) {
                    segment(skipped, scale: scale, width: barWidth, skipped: true, isTop: true, sideLabel: !above)
                    segment(completed, scale: scale, width: barWidth, skipped: false, isTop: skipped == 0, sideLabel: !above)
                }
            }
        }.font(.system(size: 12, weight: .medium))
    }

    @ViewBuilder private func segment(_ value: Int, scale: CGFloat, width: CGFloat, skipped: Bool, isTop: Bool, sideLabel: Bool) -> some View {
        if value > 0 {
            let radius: CGFloat = isTop ? 3 : 0
            UnevenRoundedRectangle(topLeadingRadius: radius, topTrailingRadius: radius, style: .circular)
                .fill(skipped ? palette.skipBar : palette.completeBar)
                .frame(width: width, height: CGFloat(value) * scale)
                .overlay(alignment: .trailing) {
                    if sideLabel {
                        Text(String(value)).fixedSize()
                            .foregroundStyle(skipped ? palette.skipText : palette.ink)
                            .frame(width: 0, alignment: .leading)
                            .offset(x: 4)
                    }
                }
        }
    }

    private func calendar(_ days: [RestDay], selected: Date, availableHeight: CGFloat) -> some View {
        let leading = (Calendar.current.component(.weekday, from: days[0].id) + 5) % 7
        let rows = (leading + days.count + 6) / 7
        let cellHeight = min(44, max(34, (availableHeight - 324) / CGFloat(rows)))
        return LazyVGrid(columns: columns, spacing: 5) {
            ForEach(0..<7) { i in
                Text(Calendar.current.localizedWeekday(i, locale: locale)).font(.system(size: 12)).foregroundStyle(palette.muted)
            }
            ForEach(0..<leading, id: \.self) { _ in Color.clear.frame(height: 1) }
            ForEach(days) { day in
                let active = day.id == selected
                let pointer = active && tracksCells ? cellPointer : nil
                dayButton(day, selected: selected) {
                    VStack(spacing: 1) {
                        let firstOfMonth = Calendar.current.component(.day, from: day.id) == 1
                        Text(firstOfMonth ? date(day.id, .dateTime.month(.defaultDigits).day())
                             : String(Calendar.current.component(.day, from: day.id)))
                            .font(.system(size: 14, weight: .semibold))
                        HStack(spacing: 3) {
                            if day.completed > 0 { Text(String(day.completed)).foregroundStyle(palette.completeText) }
                            if day.completed > 0 && day.skipped > 0 { Text("/").font(.system(size: 12)).foregroundStyle(palette.muted) }
                            if day.skipped > 0 { Text(String(day.skipped)).foregroundStyle(palette.skipText) }
                            if day.events.isEmpty { Text("—").font(.system(size: 12)).foregroundStyle(palette.muted) }
                        }.font(.system(size: 11))
                    }
                    .frame(maxWidth: .infinity).frame(height: cellHeight)
                    .background(RestHistorySurface(day: day, palette: palette, selected: active, highlight: pointer))
                    .overlay(alignment: .topTrailing) { badge(day).padding(2).offset(x: ((pointer?.x ?? 0.5) - 0.5) * 3, y: ((pointer?.y ?? 0.5) - 0.5) * 3) }
                    .overlay(alignment: .bottomLeading) {
                        if day.clean && active {
                            MonthCellStarLight(pointer: pointer ?? UnitPoint(x: 0.82, y: 0.20), palette: palette)
                                .mask(alignment: .bottomLeading) {
                                    RestHistoryMark.glints.frame(width: 49, height: 32)
                                        .padding(.leading, 3).padding(.bottom, 2)
                                }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .modifier(RestCardTilt(pointer: pointer, degrees: 22, perspective: 480)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.18)))
                .overlay {
                    if active && tracksCells {
                        RestHistoryPointerArea { cellPointer = $0 }
                    }
                }
            }
        }
    }

    @ViewBuilder private func badge(_ day: RestDay) -> some View {
        if day.clean { RestHistoryMark.completed.frame(width: 12, height: 12).foregroundStyle(palette.completeText) }
        else if day.completed == 0 && day.skipped > 0 { RestHistoryMark.skipped.frame(width: 12, height: 12).foregroundStyle(palette.skipText) }
    }

    private func detail(_ day: RestDay) -> some View {
        let message = day.message(today: day.id == history.today)
        let heading = Text(date(day.id, .dateTime.month().day()) + " " + date(day.id, .dateTime.weekday(.abbreviated)))
            .font(.system(size: 14, weight: .semibold))
        let counts = HStack(spacing: 12) {
            if !day.events.isEmpty {
                legend(breaksTaken(day.completed), color: palette.completeBar)
                legend(skippedCount(day.skipped), color: palette.skipBar, textColor: palette.skipText)
            }
        }
        return VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { heading; counts; Spacer(minLength: 0) }
                VStack(alignment: .leading, spacing: 4) { heading; counts }
            }
            .padding(.trailing, day.clean ? 60 : 0)
            VStack(alignment: .leading, spacing: 4) {
                Text(message.0).font(.system(size: day.events.isEmpty ? 13 : 16, weight: day.events.isEmpty ? .regular : .bold))
                    .foregroundStyle(day.clean ? palette.awardTitle : day.events.isEmpty ? palette.muted : palette.ink)
                if !message.1.isEmpty {
                    Text(message.1).fixedSize(horizontal: false, vertical: true).font(.system(size: 13)).foregroundStyle(day.clean ? palette.awardBody : palette.muted)
                        .padding(.trailing, day.clean ? 60 : 0)
                }
            }
            if !day.events.isEmpty {
                RestHistoryEventList(events: day.events, range: range, palette: palette)
                    .padding(.top, 5)
                    .id(day.id)
            }
        }
        .padding(16)
        .background { cardSurface(day) }
    }

    private func cardSurface(_ day: RestDay) -> some View {
        RestHistorySurface(day: day, palette: palette, card: true, highlight: cardPointer)
            .overlay(alignment: .topTrailing) {
                if day.clean {
                    ZStack(alignment: .topTrailing) {
                        CompletedCardStarLight(pointer: cardPointer)
                            .id(day.id)
                            .mask(alignment: .topTrailing) {
                                RestHistoryMark.glints.frame(width: 90, height: 58)
                                    .padding(.top, 6).padding(.trailing, 12)
                            }
                            .transition(.identity)
                        RestHistoryMark.seal.frame(width: 80, height: 80).foregroundStyle(palette.seal)
                            .offset(x: 11, y: -11)
                    }.allowsHitTesting(false)
                }
            }
            .overlay {
                RestGlassEdge(palette: palette, card: true)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(scheme == .dark ? 0.20 : 0.07), radius: 4, y: 3)
            .allowsHitTesting(false)
    }
}

private struct RestHistoryEventList: View {
    let events: [RestEvent]
    let range: Int
    let palette: RestHistoryPalette
    @Environment(\.locale) private var systemLocale
    @State private var hasMoreBelow = false
    private let rowHeight: CGFloat = 30

    var body: some View {
        RestHistoryListViewport(rowHeight: rowHeight, count: events.count, rowLimit: range == 7 ? 8.5 : 4.5) {
            ScrollView {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 0) {
                    ForEach(events) { event in
                        GridRow(alignment: .firstTextBaseline) {
                            Text(RestHistoryScreen.recordTime(event.date, locale: systemLocale))
                                .font(.system(size: 13)).monospacedDigit().foregroundStyle(palette.muted)
                                .fixedSize()
                                .gridColumnAlignment(.trailing)
                            Text(event.source.title)
                                .font(.system(size: 14))
                                .foregroundStyle(event.source == .skipped ? palette.skipText : palette.recordInk)
                                .frame(minHeight: rowHeight, alignment: .leading)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentSize.height - geometry.visibleRect.maxY > 0.5
            } action: { _, more in
                hasMoreBelow = more
            }
            .mask {
                VStack(spacing: 0) {
                    Rectangle()
                    if hasMoreBelow {
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: 10)
                    }
                }
            }
        }
    }
}

/// Leave half a row visible when the surrounding chart compresses a long list.
private struct RestHistoryListViewport: Layout {
    let rowHeight: CGFloat
    let count: Int
    let rowLimit: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let contentHeight = CGFloat(count) * rowHeight
        let limit = min(rowLimit * rowHeight, proposal.height ?? .infinity)
        var height = min(contentHeight, max(rowHeight, limit))
        if height < contentHeight && height >= 1.5 * rowHeight {
            height = (floor(height / rowHeight - 0.5) + 0.5) * rowHeight
        }
        let width = proposal.width ?? subviews[0].sizeThatFits(.unspecified).width
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
    }
}

private extension Calendar {
    func localizedWeekday(_ mondayOffset: Int, locale: Locale) -> String {
        var localized = self
        localized.locale = locale
        return localized.shortStandaloneWeekdaySymbols[(mondayOffset + 1) % 7]
    }
}
