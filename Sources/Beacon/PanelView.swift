import Core
import SwiftUI

struct PanelView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: Updater
    let openFilters: () -> Void
    @State private var tab = Tab.notifications
    @State private var mineFilter: MineStatus?
    /// Which side the next tab slides in from: 1 when moving right, -1 when moving left.
    @State private var direction: CGFloat = 1
    @Namespace private var indicator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Tab: Int { case notifications, reviews, mine, merged }

    init(model: AppModel, updater: Updater, openFilters: @escaping () -> Void) {
        self.model = model
        self.updater = updater
        self.openFilters = openFilters
    }

    #if DEBUG
    /// Snapshots open on a chosen tab. Release builds always open on Unread.
    init(model: AppModel, updater: Updater, openFilters: @escaping () -> Void, initialTab: Tab, initialMineStatus: MineStatus? = nil) {
        self.model = model
        self.updater = updater
        self.openFilters = openFilters
        _tab = State(initialValue: initialTab)
        _mineFilter = State(initialValue: initialMineStatus)
    }
    #endif

    static let size = CGSize(width: 460, height: 600)

    var body: some View {
        // An ordered-out panel still lays out and draws every change, and each sync changes most of it.
        // So the hidden panel holds nothing. Opening rebuilds the rows for their entrance anyway.
        Group {
            if model.panelVisible { panel } else { Color.clear }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        // A filter left on from an earlier open would look like missing pull requests.
        .onChange(of: model.panelOpens) { mineFilter = nil }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            StatusStrip(model: model, updater: updater, openFilters: openFilters)
            if model.needsSignIn {
                SignInState(detail: signInDetail) { Task { await model.refresh() } }
            } else {
                header
                TickRuler().frame(height: 7).padding(.horizontal, 18)
                Rectangle().fill(Palette.hairlineStrong).frame(height: 1)

                ZStack {
                    switch tab {
                    case .notifications:
                        NotificationsTab(model: model)
                            .transition(slide)
                    case .reviews:
                        ReviewsTab(model: model, openFilters: openFilters)
                            .transition(slide)
                    case .mine:
                        MineTab(model: model, filter: mineFilter)
                            .transition(slide)
                    case .merged:
                        MergedTab(model: model)
                            .transition(slide)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                // A new id each time the panel opens, so the rows play their entrance again.
                .id(model.panelOpens)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(
            LinearGradient(colors: [Palette.surface, Palette.ink], startPoint: .top, endPoint: .init(x: 0.5, y: 0.35))
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Palette.hairlineStrong, lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
        .tint(Palette.amber)
    }

    private var signInDetail: String {
        if model.errors.contains(where: { $0.contains("gh not found") }) {
            return "Install the GitHub CLI, then sign in."
        }
        return "Sign in again. GitHub did not accept the token."
    }

    private var slide: AnyTransition {
        reduceMotion ? .opacity : .asymmetric(
            insertion: .opacity.combined(with: .offset(x: direction * 24)),
            removal: .opacity
        )
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .bottom, spacing: 26) {
            readoutTab(.notifications, label: "Unread", count: model.unreadCount, dim: false)
            readoutTab(.reviews, label: "To review", count: model.reviewBadge.count, dim: model.reviewBadge.dim)
            mineColumn
            Spacer(minLength: 0)
            if tab == .notifications && model.unreadCount > 0 {
                Button("Mark all read") {
                    withAnimation(reduceMotion ? nil : .arrive(0.45)) { model.markAllRead() }
                }
                .buttonStyle(PillButton())
                .padding(.bottom, 14)
                .transition(.opacity)
            } else if tab == .reviews {
                QueueTelemetry(model: model)
                    .padding(.bottom, 14)
                    .transition(.opacity)
            } else if tab == .mine {
                MineTelemetry(model: model, filter: $mineFilter)
                    .padding(.bottom, 14)
                    .transition(.opacity)
            } else if tab == .merged {
                MergedLayoutToggle(model: model)
                    .padding(.bottom, 14)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
    }

    private func select(_ value: Tab) {
        direction = value.rawValue > tab.rawValue ? 1 : -1
        withAnimation(reduceMotion ? nil : .arrive(0.38)) {
            tab = value
            if value != .mine { mineFilter = nil }
        }
    }

    private func readoutTab(_ value: Tab, label: String, count: Int, dim: Bool) -> some View {
        readoutColumn(value, label: label, count: count, dim: dim, under: { Color.clear })
    }

    /// Mine keeps its count. Merged sits under that count and has none of its own.
    private var mineColumn: some View {
        readoutColumn(.mine, label: "Mine", count: model.mineCount, dim: false) {
            let selected = tab == .merged
            Button {
                select(.merged)
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(selected ? Palette.amber : Palette.faint)
                        .frame(width: 5, height: 5)
                    Text("Merged")
                        .readout(size: 9.5, tracking: 1.6)
                        .foregroundStyle(selected ? Palette.amber : Palette.faint)
                }
                .padding(.top, 2)
                .padding(.bottom, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Merged")
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }

    private func readoutColumn<Under: View>(_ value: Tab, label: String, count: Int, dim: Bool, @ViewBuilder under: () -> Under) -> some View {
        let selected = tab == value
        // The bar stays under Mine when Merged, which lives in that column, is selected.
        let marked = selected || (value == .mine && tab == .merged)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                select(value)
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(selected ? Palette.amber : Palette.faint)
                            .frame(width: 5, height: 5)
                        Text(label)
                            .readout(size: 9.5, tracking: 1.6)
                            .foregroundStyle(selected ? Palette.amber : Palette.faint)
                    }
                    Counter(value: count, generation: model.panelOpens)
                        .font(.system(size: 58, weight: .ultraLight))
                        .monospacedDigit()
                        .foregroundStyle(selected ? (dim ? Palette.dim : Palette.text) : Palette.faint)
                        .padding(.top, -2)
                        .padding(.bottom, 6)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(count) \(label)")
            .accessibilityAddTraits(selected ? .isSelected : [])
            // Same height on every column, so the selection bars stay on one line.
            under()
                .frame(height: 22, alignment: .leading)
            ZStack(alignment: .leading) {
                Color.clear.frame(width: 36, height: 2)
                if marked {
                    Capsule()
                        .fill(Palette.amber)
                        .frame(width: 36, height: 2)
                        .matchedGeometryEffect(id: "indicator", in: indicator)
                }
            }
        }
        .fixedSize()
    }
}

/// Right side of the Reviews header: how many queued PRs are failing CI or past the stale limit.
private struct QueueTelemetry: View {
    @ObservedObject var model: AppModel

    var body: some View {
        // A PR can sit in several categories; count it once.
        let prs = Dictionary(model.categories.flatMap(\.prs).filter { !$0.isSkipped }.map { ($0.id, $0) }) { first, _ in first }.values
        let failing = prs.filter { $0.ciState == "FAILURE" || $0.ciState == "ERROR" }.count
        let staleLimit = Date().addingTimeInterval(-Double(model.config.staleHours) * 3600)
        let stale = prs.filter { $0.createdAt < staleLimit }.count
        VStack(alignment: .trailing, spacing: 6) {
            TelemetryLine(label: "Failing CI", value: failing, color: Palette.red)
            TelemetryLine(label: "Stale", value: stale, color: Palette.amber)
        }
    }
}

/// Right side of the Mine header: every PR on exactly one line. Click a line to filter the list.
private struct MineTelemetry: View {
    @ObservedObject var model: AppModel
    @Binding var filter: MineStatus?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let prs = model.mine.flatMap(\.prs)
        VStack(alignment: .trailing, spacing: 5) {
            line(.ready, prs)
            line(.toFix, prs)
            line(.failingCI, prs)
            // Above the rule is what needs you. Below it is the rest, so the column still sums to the total.
            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 1)
            line(.waiting, prs)
        }
        // Without this the rule takes all the free width in the header.
        .fixedSize(horizontal: true, vertical: false)
    }

    private func line(_ status: MineStatus, _ prs: [ReviewPR]) -> some View {
        MineStatusLine(status: status, value: prs.filter(status.matches).count, on: filter == status) {
            withAnimation(reduceMotion ? nil : .arrive(0.34)) {
                filter = filter == status ? nil : status
            }
        }
    }
}

private struct MineStatusLine: View {
    let status: MineStatus
    let value: Int
    let on: Bool
    let toggle: () -> Void
    @State private var hovering = false

    private var help: String {
        if on { return "Show all pull requests" }
        switch status {
        case .ready: return "Show only pull requests you can merge"
        case .toFix: return "Show only pull requests with changes requested or merge conflicts"
        case .failingCI: return "Show only pull requests with failing checks"
        case .waiting: return "Show only drafts and pull requests waiting on checks or a review"
        }
    }

    /// A zero has nothing to show. It stays clickable when on, so a sync that empties the filter can still clear it.
    private var clickable: Bool { value > 0 || on }

    private var color: Color {
        switch status {
        case .ready: return Palette.green
        case .toFix, .failingCI: return Palette.red
        case .waiting: return Palette.dim
        }
    }

    var body: some View {
        Button {
            if clickable { toggle() }
        } label: {
            TelemetryLine(
                label: status.rawValue,
                value: value,
                color: color,
                labelColor: on || (hovering && clickable) ? Palette.amber : Palette.faint
            )
            // Outside the line's frame, so turning a filter on moves nothing.
            .overlay(alignment: .leading) {
                if on {
                    Circle()
                        .fill(Palette.amber)
                        .frame(width: 5, height: 5)
                        .offset(x: -11)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Not .disabled: that would dim a zero below the faint the other labels use.
        .allowsHitTesting(clickable)
        .onHover { over in withAnimation(.arrive(0.2)) { hovering = over } }
        .help(help)
        .accessibilityLabel("\(value) \(status.rawValue)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Right side of the Merged header: one list by merge date, or one group per repository.
private struct MergedLayoutToggle: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            choice("Latest", on: !model.mergedByRepo, help: "Newest merge first") {
                model.setMergedByRepo(false)
            }
            choice("By repo", on: model.mergedByRepo, help: "Group by repository, newest merge first") {
                model.setMergedByRepo(true)
            }
        }
    }

    private func choice(_ title: String, on: Bool, help: String, set: @escaping () -> Void) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .arrive(0.34)) { set() }
        } label: {
            Text(title)
                .readout(size: 8.5, tracking: 1.3)
                .foregroundStyle(on ? Palette.amber : Palette.faint)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

private struct TelemetryLine: View {
    let label: String
    let value: Int
    let color: Color
    var labelColor = Palette.faint

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .readout(size: 8.5, tracking: 1.3)
                .foregroundStyle(labelColor)
            Text(verbatim: "\(value)")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(value > 0 ? color : Palette.faint)
                .frame(minWidth: 18, alignment: .trailing)
                .contentTransition(.numericText(value: Double(value)))
        }
    }
}

/// A number that rolls up from zero when the panel opens, then follows its value.
private struct Counter: View {
    let value: Int
    let generation: Int
    @State private var shown = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(verbatim: "\(shown)")
            .contentTransition(.numericText(value: Double(shown)))
            .onAppear(perform: powerUp)
            .onChange(of: generation) { powerUp() }
            .onChange(of: value) { withAnimation(.arrive(0.4)) { shown = value } }
    }

    private func powerUp() {
        guard !reduceMotion else { shown = value; return }
        shown = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
            withAnimation(.arrive(0.7)) { shown = value }
        }
    }
}

// MARK: - Status strip

/// Top line: link state, last sync, refresh and the overflow menu.
private struct StatusStrip: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updater: Updater
    let openFilters: () -> Void

    private var state: (color: Color, pulsing: Bool) {
        if model.isRefreshing { return (Palette.amber, true) }
        if model.needsSignIn { return (Palette.amber, false) }
        if !model.errors.isEmpty { return (Palette.red, false) }
        return (Palette.green, false)
    }

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(color: state.color, pulsing: state.pulsing)
            TimelineView(.periodic(from: .now, by: 5)) { context in
                Text(statusText(now: context.date))
                    .readout(size: 9, tracking: 1.3)
                    .foregroundStyle(model.needsSignIn ? Palette.amber : (model.errors.isEmpty ? Palette.faint : Palette.red))
                    .lineLimit(1)
                    .help(model.errors.joined(separator: "\n"))
            }
            Spacer(minLength: 8)
            if updater.updateReady {
                Button(action: updater.checkForUpdates) {
                    Text("Update ready")
                        .readout(size: 9, tracking: 1.3)
                        .foregroundStyle(Palette.amber)
                }
                .buttonStyle(.plain)
                .help("Install the update")
            }
            Button { Task { await model.refresh() } } label: {
                Looping(active: model.isRefreshing, period: 0.9, framesPerSecond: 60) { cycle in
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees((cycle ?? 0) * 360))
                }
            }
            .buttonStyle(ChromeButton())
            .disabled(model.isRefreshing)
            .help("Refresh")
            Menu {
                Button("Review filters…", action: openFilters)
                Button("Open config file") { model.openConfig() }
                Divider()
                Toggle("Open at Login", isOn: Binding(
                    get: { LoginItem.isEnabled },
                    set: { LoginItem.setEnabled($0) }
                ))
                Button("About Beacon") {
                    updater.prepareForUpdateUI?()
                    BeaconActions.showAbout()
                }
                Button("Report a Bug…") {
                    updater.prepareForUpdateUI?()
                    NSWorkspace.shared.open(BeaconActions.bugReportURL())
                }
                Divider()
                Button("Check for Updates…", action: updater.checkForUpdates)
                Button("Quit Beacon") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.button)
            .buttonStyle(ChromeButton())
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
        }
        .padding(.leading, 18)
        .padding(.trailing, 10)
        .frame(height: 36)
    }

    private func statusText(now: Date) -> String {
        if model.isRefreshing { return "Syncing" }
        if model.needsSignIn { return "Sign in" }
        if let error = model.errors.first { return "Link error · \(error)" }
        guard let lastUpdated = model.lastUpdated else { return "Connecting" }
        let seconds = Int(max(0, now.timeIntervalSince(lastUpdated)))
        if seconds < 10 { return "Synced just now" }
        if seconds < 60 { return "Synced \(seconds)s ago" }
        return "Synced \(seconds / 60)m ago"
    }
}

private struct StatusDot: View {
    let color: Color
    let pulsing: Bool

    var body: some View {
        Looping(active: pulsing, period: 1.4) { cycle in
            let level = pulseLevel(cycle)
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
                .background(Circle().fill(color.opacity(0.25)).frame(width: 12, height: 12).scaleEffect(1 + 0.4 * level))
                .opacity(1 - 0.55 * level)
        }
        // Settles from wherever the pulse was when the sync ends.
        .animation(.arrive(0.3), value: pulsing)
        .accessibilityHidden(true)
    }
}

// MARK: - Notifications

private struct NotificationsTab: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shown: [FeedItem] {
        model.showRead ? model.items : model.items.filter { !$0.read }
    }

    private var readCount: Int { model.items.count - model.unreadCount }

    var body: some View {
        Group {
            if model.items.isEmpty {
                AllClear(
                    title: "No signal yet",
                    detail: "Comments on your PRs, replies to your threads and @mentions land here. Review requests live in the other tab.",
                    seed: model.panelOpens
                )
            } else if shown.isEmpty {
                AllClear(title: "All clear", detail: nil, seed: model.panelOpens) {
                    Button("Show \(readCount) read") {
                        withAnimation(.arrive()) { model.showRead = true }
                    }
                    .buttonStyle(PillButton())
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            } else {
                list
            }
        }
        .animation(reduceMotion ? nil : .arrive(0.4), value: shown.isEmpty)
    }

    private var list: some View {
        let days = DayGroup.group(PRThread.group(shown))
        // Running position, so the entrance cascades through headers and rows in reading order.
        let starts = days.indices.map { i in
            days[..<i].reduce(0) { $0 + 1 + $1.threads.reduce(0) { $0 + 1 + $1.items.count } }
        }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(Array(days.enumerated()), id: \.element.id) { dayIndex, day in
                    Section {
                        ForEach(Array(day.threads.enumerated()), id: \.element.id) { threadIndex, thread in
                            let first = starts[dayIndex] + 1 + day.threads[..<threadIndex].reduce(0) { $0 + 1 + $1.items.count }
                            let collapsed = model.collapsedPRs.contains(thread.id)
                            ThreadHeader(
                                thread: thread,
                                collapsed: collapsed,
                                divider: threadIndex > 0,
                                toggle: { withAnimation(reduceMotion ? nil : .arrive(0.34)) { model.toggleCollapsed(thread) } },
                                open: { model.open(thread) },
                                markRead: { withAnimation(reduceMotion ? nil : .arrive(0.4)) { model.markRead(thread) } }
                            )
                            .staggeredReveal(first)
                            .transition(.opacity)
                            if !collapsed {
                                ForEach(Array(thread.items.enumerated()), id: \.element.id) { index, item in
                                    FeedRow(item: item, open: { model.open(item) }, dismiss: {
                                        withAnimation(reduceMotion ? nil : .arrive(0.4)) { model.markRead(item) }
                                    })
                                    .staggeredReveal(first + 1 + index)
                                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: -6)), removal: .opacity.combined(with: .offset(x: -40))))
                                }
                            }
                        }
                    } header: {
                        RuledHeader(title: day.title)
                    }
                }
                if readCount > 0 {
                    Button(model.showRead ? "Hide read" : "Show \(readCount) read") {
                        withAnimation(reduceMotion ? nil : .arrive()) { model.showRead.toggle() }
                    }
                    .buttonStyle(PillButton())
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                }
            }
            .padding(.bottom, 6)
            .animation(reduceMotion ? nil : .arrive(0.4), value: shown.map(\.id))
        }
        .scrollIndicators(.never)
    }
}

/// Pull request threads filed under the day of their newest item, newest day first.
private struct DayGroup: Identifiable {
    let day: Date
    let threads: [PRThread]
    var id: Date { day }

    var title: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        if let days = calendar.dateComponents([.day], from: day, to: .now).day, days < 7 {
            return day.formatted(.dateTime.weekday(.wide))
        }
        return day.formatted(.dateTime.month(.abbreviated).day())
    }

    /// Keeps the order of `threads` inside each day.
    static func group(_ threads: [PRThread]) -> [DayGroup] {
        let calendar = Calendar.current
        let byDay = Dictionary(grouping: threads) { calendar.startOfDay(for: $0.latest) }
        return byDay.keys.sorted(by: >).map { DayGroup(day: $0, threads: byDay[$0]!) }
    }
}

private func kindLook(_ item: FeedItem) -> (symbol: String, label: String, color: Color) {
    switch item.kind {
    case .mention: return ("at", "Mention", Palette.amber)
    case .teamMention: return ("person.2.fill", "@\(item.team ?? "team")", Palette.amber)
    case .reply: return ("arrowshape.turn.up.left.fill", "Reply", Palette.steel)
    case .changesRequested: return ("exclamationmark", "Changes requested", Palette.red)
    case .approvedWithComment: return ("checkmark", "Approved", Palette.green)
    case .reviewed: return ("eye.fill", "Review", Palette.steel)
    case .comment: return ("text.bubble.fill", "Comment", Palette.steel)
    }
}

/// A pull request in the Unread tab. Click to fold its items away; folded, it keeps one dot per item.
private struct ThreadHeader: View {
    let thread: PRThread
    let collapsed: Bool
    /// A hairline above every thread but the first of the day.
    let divider: Bool
    let toggle: () -> Void
    let open: () -> Void
    let markRead: () -> Void
    @State private var hovering = false

    private static let maxDots = 12

    private var unread: Int { thread.unreadCount }

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(hovering ? Palette.amber : Palette.dim)
                    .rotationEffect(.degrees(collapsed ? 0 : 90))
                    .frame(width: 12, height: 18)
                VStack(alignment: .leading, spacing: 4) {
                    Text(thread.title)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(unread == 0 || thread.isClosed ? Palette.dim : Palette.text)
                        .strikethrough(thread.isClosed, color: Palette.faint)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: "\(thread.pr.name)#\(thread.pr.number)" + (thread.isClosed ? " · \(thread.prState.lowercased())" : ""))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Palette.faint)
                }
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    if collapsed {
                        HStack(spacing: 4) {
                            ForEach(thread.items.prefix(Self.maxDots)) { item in
                                Circle()
                                    .fill(item.read ? Palette.faint : kindLook(item).color)
                                    .frame(width: 5, height: 5)
                            }
                        }
                        .transition(.opacity)
                    }
                    // Unread items in amber; once they're all read, the total in grey.
                    Text(verbatim: "\(unread > 0 ? unread : thread.items.count)")
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(unread > 0 ? Palette.amber : Palette.faint)
                        .frame(minWidth: 14, alignment: .trailing)
                        .contentTransition(.numericText(value: Double(unread)))
                }
                .frame(height: 18)
                .opacity(hovering ? 0 : 1)
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, collapsed ? 12 : 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(hovering ? 0.035 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            if divider {
                Rectangle().fill(Palette.hairline).frame(height: 1).padding(.horizontal, 18)
            }
        }
        .overlay(alignment: .topTrailing) {
            if hovering {
                HoverControls {
                    if let url = thread.pr.webURL { CopyLinkButton(url: url.absoluteString) }
                    Button(action: open) { Image(systemName: "arrow.up.right") }
                        .buttonStyle(ChromeButton())
                        .help("Open the pull request")
                    if unread > 0 {
                        Button(action: markRead) { Image(systemName: "checkmark") }
                            .buttonStyle(ChromeButton())
                            .help("Mark \(unread == 1 ? "it" : "all \(unread)") read")
                    }
                }
                .padding(.top, 8)
                .padding(.trailing, 10)
            }
        }
        .onHover { over in withAnimation(.arrive(0.2)) { hovering = over } }
        .contextMenu {
            Button("Open Pull Request", action: open)
            if let url = thread.pr.webURL { Button("Copy Link") { copyLink(url.absoluteString) } }
            if unread > 0 { Button("Mark All Read", action: markRead) }
        }
        .help(thread.pr.repo)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(thread.title), \(thread.pr.name) \(thread.pr.number), \(unread) unread")
        .accessibilityValue(collapsed ? "collapsed" : "expanded")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, toggle)
        .accessibilityAction(named: "Open pull request", open)
        .accessibilityAction(named: "Mark all read", markRead)
    }
}

/// One item under its pull request. The thread header carries the title, so the row is who, what, and when.
private struct FeedRow: View {
    let item: FeedItem
    let open: () -> Void
    let dismiss: () -> Void
    @State private var hovering = false

    var body: some View {
        let kind = kindLook(item)
        Button(action: open) {
            HStack(alignment: .top, spacing: 12) {
                Lamp(symbol: kind.symbol, color: kind.color, lit: !item.read, size: 22)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(kind.label)
                            .readout(size: 9, tracking: 1.2)
                            .foregroundStyle(item.read ? Palette.faint : kind.color)
                            .lineLimit(1)
                        Text(item.actor)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(item.read ? Palette.dim : Palette.text)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Age(date: item.createdAt, stale: false)
                            .opacity(hovering ? 0 : 1)
                    }
                    .frame(height: 22)
                    if !item.snippet.isEmpty {
                        Text(item.snippet)
                            .font(.system(size: 12))
                            .foregroundStyle(item.read ? Palette.faint : Palette.dim)
                            .lineLimit(2)
                            .lineSpacing(1.5)
                    }
                }
            }
            // Indented under the thread header, lamps lined up with its title.
            .padding(.leading, 39)
            .padding(.trailing, 18)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RowHighlight(on: hovering))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableRow())
        .overlay(alignment: .topTrailing) {
            if hovering {
                HoverControls {
                    CopyLinkButton(url: item.url)
                    if !item.read {
                        Button(action: dismiss) { Image(systemName: "checkmark") }
                            .buttonStyle(ChromeButton())
                            .help("Mark read without opening")
                    }
                }
                .padding(.top, 5)
                .padding(.trailing, 10)
            }
        }
        .onHover { over in withAnimation(.arrive(0.2)) { hovering = over } }
        .contextMenu { Button("Copy Link") { copyLink(item.url) } }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Mark read", dismiss)
        .accessibilityAction(named: "Copy link") { copyLink(item.url) }
    }
}

// MARK: - Reviews

private struct ReviewsTab: View {
    @ObservedObject var model: AppModel
    let openFilters: () -> Void

    var body: some View {
        if model.categories.isEmpty {
            if model.isRefreshing || model.lastUpdated == nil {
                AllClear(title: "Scanning", detail: nil, seed: 0, sweeping: true)
            } else {
                AllClear(title: "No categories", detail: "A category is a GitHub search for PRs you review.", seed: 0) {
                    Button("Add one", action: openFilters).buttonStyle(PillButton())
                }
            }
        } else {
            let offsets = model.categories.indices.map { i in model.categories[..<i].reduce(0) { $0 + $1.prs.count + 1 } }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                    ForEach(Array(model.categories.enumerated()), id: \.element.id) { categoryIndex, category in
                        Section {
                            if let note = category.note {
                                Text(note)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Palette.dim)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 10)
                            } else if category.prs.isEmpty {
                                Text("Queue empty")
                                    .readout(size: 9, tracking: 1.3)
                                    .foregroundStyle(Palette.faint)
                                    .padding(.leading, Layout.textInset)
                                    .padding(.vertical, 12)
                                    .staggeredReveal(offsets[categoryIndex])
                            }
                            ForEach(Array(category.prs.enumerated()), id: \.element.id) { index, pr in
                                if pr.id == category.prs.first(where: \.isSkipped)?.id {
                                    Text("Not for review")
                                        .readout(size: 8.5, tracking: 1.3)
                                        .foregroundStyle(Palette.faint)
                                        .padding(.leading, Layout.textInset)
                                        .padding(.top, 12)
                                        .padding(.bottom, 2)
                                }
                                ReviewRow(pr: pr, category: category.name, model: model)
                                    .staggeredReveal(offsets[categoryIndex] + index + 1)
                                    .transition(.asymmetric(insertion: .opacity, removal: .opacity.combined(with: .offset(x: -40))))
                            }
                        } header: {
                            RuledHeader(title: category.name, count: category.count) {
                                HiddenMenu(category: category.name, model: model, openFilters: openFilters)
                            }
                        }
                    }
                }
                .padding(.bottom, 10)
            }
            .scrollIndicators(.never)
        }
    }
}

/// Lists the repos and single PRs hidden from a category, each with a way to show it again.
private struct HiddenMenu: View {
    let category: String
    @ObservedObject var model: AppModel
    let openFilters: () -> Void

    var body: some View {
        let own = model.config.categories.first { $0.name == category }?.excludeRepos ?? []
        let everywhere = model.config.excludeRepos
        let prs = model.hiddenPRs(in: category)
        let count = Set(own + everywhere).count + prs.count
        // With nothing hidden there's nothing to undo here; the overflow menu still opens the filters.
        if count > 0 {
            Menu {
                if !prs.isEmpty {
                    Section("Hidden PRs") {
                        ForEach(prs, id: \.id) { pr in
                            Button("Show \(pr.label.count > 60 ? pr.label.prefix(59) + "…" : pr.label) again") {
                                withAnimation(.arrive()) { model.unhide(prId: pr.id) }
                            }
                        }
                    }
                }
                ForEach(own, id: \.self) { repo in
                    Button("Show \(repo) again") { model.unhide(repo: repo, from: category) }
                }
                if !everywhere.isEmpty {
                    Section("Hidden everywhere") {
                        ForEach(everywhere, id: \.self) { repo in
                            Button("Show \(repo) again") { model.unhide(repo: repo, from: nil) }
                        }
                    }
                }
                Divider()
                Button("Edit filters…", action: openFilters)
            } label: {
                Text("\(count) hidden")
            }
            .menuStyle(.button)
            .buttonStyle(PillButton(compact: true))
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
}

private struct ReviewRow: View {
    let pr: ReviewPR
    let category: String
    @ObservedObject var model: AppModel
    @State private var hovering = false

    private var isStale: Bool { pr.createdAt.timeIntervalSinceNow < -Double(model.config.staleHours) * 3600 }

    @ViewBuilder
    private var hideButtons: some View {
        Button("Hide this PR") { withAnimation(.arrive()) { model.hide(pr: pr) } }
        Divider()
        Button("Hide \(pr.repoName) from \(category)") { withAnimation(.arrive()) { model.hide(repo: pr.repo, from: category) } }
        Button("Hide \(pr.repoName) from all categories") { withAnimation(.arrive()) { model.hide(repo: pr.repo, from: nil) } }
    }

    var body: some View {
        Button { model.open(pr) } label: {
            HStack(alignment: .top, spacing: 14) {
                CILamp(state: pr.ciState)
                VStack(alignment: .leading, spacing: 5) {
                    Text(pr.title)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Palette.text)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if pr.isSkipped {
                        HStack(spacing: 4) {
                            ForEach(pr.skipLabels, id: \.name) { LabelChip(label: $0) }
                        }
                    }
                    Text(verbatim: "\(pr.repoName)#\(pr.number) · \(pr.author)")
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Palette.faint)
                }
                Spacer(minLength: 8)
                Age(date: pr.createdAt, stale: isStale)
                    .padding(.top, 3)
                    .opacity(hovering ? 0 : 1)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RowHighlight(on: hovering))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableRow())
        .opacity(pr.isSkipped ? 0.45 : 1)
        .overlay(alignment: .topTrailing) {
            if hovering {
                HoverControls {
                    CopyLinkButton(url: pr.url)
                    Menu { hideButtons } label: { Image(systemName: "eye.slash") }
                        .menuStyle(.button)
                        .buttonStyle(ChromeButton())
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("Hide this PR or its repo")
                }
                .padding(.top, 6)
                .padding(.trailing, 10)
            }
        }
        .onHover { over in withAnimation(.arrive(0.2)) { hovering = over } }
        .contextMenu {
            Button("Copy Link") { copyLink(pr.url) }
            Divider()
            hideButtons
        }
    }
}

/// CI status as a lamp: shape and color both carry the state.
private struct CILamp: View {
    let state: String?

    private var look: (symbol: String, color: Color, label: String, lit: Bool) {
        switch state {
        case "SUCCESS": return ("checkmark", Palette.green, "passing", true)
        case "FAILURE", "ERROR": return ("xmark", Palette.red, "failing", true)
        case "PENDING", "EXPECTED": return ("ellipsis", Palette.amber, "running", true)
        default: return ("minus", Palette.faint, "no checks", false)
        }
    }

    var body: some View {
        let look = look
        Looping(active: look.label == "running", period: 1.8) { cycle in
            Lamp(symbol: look.symbol, color: look.color, lit: look.lit)
                .opacity(1 - 0.5 * pulseLevel(cycle))
        }
        .help("CI: \(look.label)")
    }
}

// MARK: - Mine

private struct MineTab: View {
    @ObservedObject var model: AppModel
    let filter: MineStatus?
    /// Repos folded while a filter is on. A filter opens every repo, because a folded repo hides the
    /// pull requests the filter asked for. These folds never touch the ones you keep without a filter.
    @State private var filterFolds: Set<String> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// PRs of one repo inside a layer, in the order GitHub returned them (most recently updated first).
    private struct RepoBucket: Identifiable {
        let repo: String
        let prs: [ReviewPR]
        var id: String { repo }
    }

    private func buckets(_ prs: [ReviewPR]) -> [RepoBucket] {
        var order: [String] = []
        var byRepo: [String: [ReviewPR]] = [:]
        for pr in prs {
            if byRepo[pr.repo] == nil { order.append(pr.repo) }
            byRepo[pr.repo, default: []].append(pr)
        }
        return order.map { RepoBucket(repo: $0, prs: byRepo[$0]!) }
    }

    private var shownGroups: [CategoryResult] {
        guard let filter else { return model.mine }
        return model.mine.compactMap { group in
            let prs = group.prs.filter(filter.matches)
            return prs.isEmpty ? nil : CategoryResult(name: group.name, count: prs.count, prs: prs)
        }
    }

    private func isCollapsed(_ repo: String) -> Bool {
        filter == nil ? model.collapsedRepos.contains(repo) : filterFolds.contains(repo)
    }

    private func toggleCollapsed(_ repo: String) {
        if filter == nil {
            model.toggleCollapsed(repo)
        } else if !filterFolds.insert(repo).inserted {
            filterFolds.remove(repo)
        }
    }

    private func setCollapsed(_ repos: [String], _ collapsed: Bool) {
        if filter == nil {
            model.setCollapsed(repos, collapsed)
        } else if collapsed {
            filterFolds.formUnion(repos)
        } else {
            filterFolds.subtract(repos)
        }
    }

    var body: some View {
        if model.mine.allSatisfy(\.prs.isEmpty) {
            if model.lastUpdated == nil {
                AllClear(title: "Scanning", detail: nil, seed: 0, sweeping: true)
            } else {
                AllClear(title: "Nothing in flight", detail: "You have no open PRs. Once you open one it shows up here, in its group from myPRGroups.", seed: 0)
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                    // Only a sync can empty a filter: a line with a zero count can't be turned on.
                    if filter != nil && shownGroups.isEmpty {
                        Text("None right now")
                            .readout(size: 9, tracking: 1.3)
                            .foregroundStyle(Palette.faint)
                            .padding(.leading, 18)
                            .padding(.vertical, 12)
                    }
                    // Running position, so the entrance cascades through headers and rows in reading order.
                    let groups = shownGroups.map { (group: $0, buckets: buckets($0.prs)) }
                    let starts = groups.indices.map { i in
                        groups[..<i].reduce(0) { $0 + 1 + $1.buckets.reduce(0) { $0 + 1 + $1.prs.count } }
                    }
                    ForEach(Array(groups.enumerated()), id: \.element.group.id) { groupIndex, entry in
                        Section {
                            if entry.group.prs.isEmpty {
                                Text("Nothing open")
                                    .readout(size: 9, tracking: 1.3)
                                    .foregroundStyle(Palette.faint)
                                    .padding(.leading, Layout.textInset)
                                    .padding(.vertical, 12)
                                    .staggeredReveal(starts[groupIndex])
                            }
                            let showOwner = Set(entry.group.prs.map { $0.repo.split(separator: "/").first ?? "" }).count > 1
                            ForEach(Array(entry.buckets.enumerated()), id: \.element.id) { bucketIndex, bucket in
                                let first = starts[groupIndex] + 1 + entry.buckets[..<bucketIndex].reduce(0) { $0 + 1 + $1.prs.count }
                                let collapsed = isCollapsed(bucket.repo)
                                RepoHeader(repo: bucket.repo, prs: bucket.prs, showOwner: showOwner, collapsed: collapsed) {
                                    withAnimation(reduceMotion ? nil : .arrive(0.34)) { toggleCollapsed(bucket.repo) }
                                }
                                .staggeredReveal(first)
                                if !collapsed {
                                    ForEach(Array(bucket.prs.enumerated()), id: \.element.id) { index, pr in
                                        MineRow(pr: pr) { model.open(pr) }
                                            .staggeredReveal(first + 1 + index)
                                            .transition(.opacity.combined(with: .offset(y: -6)))
                                    }
                                }
                            }
                        } header: {
                            RuledHeader(title: entry.group.name, count: entry.group.count) {
                                if !entry.buckets.isEmpty {
                                    let repos = entry.buckets.map(\.repo)
                                    // Any open repo means the click folds; only a fully folded group unfolds.
                                    let allCollapsed = repos.allSatisfy(isCollapsed)
                                    FoldAllButton(allCollapsed: allCollapsed) {
                                        withAnimation(reduceMotion ? nil : .arrive(0.34)) {
                                            setCollapsed(repos, !allCollapsed)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, 10)
            }
            .scrollIndicators(.never)
            .onChange(of: filter) { filterFolds = [] }
        }
    }
}

/// A repo inside a Mine layer. Click to fold its PRs away; folded, it keeps one CI dot per PR.
private struct RepoHeader: View {
    let repo: String
    let prs: [ReviewPR]
    let showOwner: Bool
    let collapsed: Bool
    var showsChecks = true
    var unit = "open"
    let toggle: () -> Void
    @State private var hovering = false

    private var owner: String { repo.split(separator: "/").first.map(String.init) ?? "" }
    private var name: String { repo.split(separator: "/").last.map(String.init) ?? repo }

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 9) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(hovering ? Palette.amber : Palette.dim)
                    .rotationEffect(.degrees(collapsed ? 0 : 90))
                    .frame(width: 12)
                Text("\(Text(verbatim: showOwner ? owner + "/" : "").foregroundStyle(Palette.faint))\(Text(verbatim: name).foregroundStyle(Palette.text))")
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if collapsed && showsChecks {
                    HStack(spacing: 4) {
                        ForEach(prs) { pr in
                            Circle()
                                .fill(ciColor(pr.ciState))
                                .frame(width: 5, height: 5)
                        }
                    }
                    .transition(.opacity)
                }
                Text(verbatim: "\(prs.count)")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.dim)
                    .frame(minWidth: 14, alignment: .trailing)
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .padding(.bottom, collapsed ? 10 : 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(hovering ? 0.035 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { over in withAnimation(.arrive(0.2)) { hovering = over } }
        .help(repo)
        .accessibilityLabel("\(repo), \(prs.count) \(unit)")
        .accessibilityValue(collapsed ? "collapsed" : "expanded")
    }
}

/// Folds or unfolds every repo in a Mine group. Faint and small so it reads as part of the header rule.
private struct FoldAllButton: View {
    let allCollapsed: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: allCollapsed ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(hovering ? Palette.amber : Palette.faint)
                .frame(width: 18, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { over in withAnimation(.arrive(0.2)) { hovering = over } }
        .help(allCollapsed ? "Expand all repos" : "Collapse all repos")
        .accessibilityLabel(allCollapsed ? "Expand all repos" : "Collapse all repos")
    }
}

private func ciColor(_ state: String?) -> Color {
    switch state {
    case "SUCCESS": return Palette.green
    case "FAILURE", "ERROR": return Palette.red
    case "PENDING", "EXPECTED": return Palette.amber
    default: return Palette.faint
    }
}

private struct MineRow: View {
    let pr: ReviewPR
    let open: () -> Void
    @State private var hovering = false

    /// In the order `MineStatus` checks them, so the first tag says why the row is on its header line.
    private var tags: [(text: String, color: Color)] {
        var tags: [(text: String, color: Color)] = []
        if pr.isDraft { tags.append(("Draft", Palette.dim)) }
        if pr.ciFailing { tags.append(("Failing CI", Palette.red)) }
        if pr.hasConflicts { tags.append(("Conflicts", Palette.red)) }
        if pr.reviewDecision == "CHANGES_REQUESTED" { tags.append(("Changes requested", Palette.red)) }
        if pr.ciRunning { tags.append(("CI running", Palette.steel)) }
        if pr.reviewDecision == "REVIEW_REQUIRED" { tags.append(("Awaiting review", Palette.steel)) }
        if pr.reviewDecision == "APPROVED" { tags.append(("Approved", Palette.green)) }
        return tags
    }

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 14) {
                CILamp(state: pr.ciState)
                VStack(alignment: .leading, spacing: 6) {
                    Text(pr.title)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(pr.isDraft ? Palette.dim : Palette.text)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        ForEach(tags, id: \.text) { tag in
                            StatusTag(text: tag.text, color: tag.color)
                        }
                        Text(verbatim: "#\(pr.number)")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Palette.faint)
                            .lineLimit(1)
                    }
                }
                // Without this, a row with several tags and a running lamp wraps its title and loses its number.
                .layoutPriority(1)
                Spacer(minLength: 8)
                Age(date: pr.createdAt, stale: false)
                    .padding(.top, 3)
                    .opacity(hovering ? 0 : 1)
            }
            // Indented under the repo header.
            .padding(.leading, 39)
            .padding(.trailing, 18)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RowHighlight(on: hovering))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableRow())
        .overlay(alignment: .topTrailing) {
            if hovering {
                HoverControls { CopyLinkButton(url: pr.url) }
                    .padding(.top, 5)
                    .padding(.trailing, 10)
            }
        }
        .onHover { over in withAnimation(.arrive(0.2)) { hovering = over } }
        .contextMenu { Button("Copy Link") { copyLink(pr.url) } }
        .help(pr.repo)
    }
}

// MARK: - Merged

private struct MergedTab: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showOwner: Bool {
        Set(model.merged.map { $0.repo.split(separator: "/").first ?? "" }).count > 1
    }

    private func repoLabel(_ repo: String) -> String {
        let name = repo.split(separator: "/").last.map(String.init) ?? repo
        let owner = repo.split(separator: "/").first.map(String.init) ?? ""
        return showOwner ? "\(owner)/\(name)" : name
    }

    var body: some View {
        if model.merged.isEmpty {
            if model.lastUpdated == nil {
                AllClear(title: "Scanning", detail: nil, seed: 0, sweeping: true)
            } else {
                AllClear(title: "Nothing merged", detail: "Pull requests you merge show up here, newest first.", seed: 0)
            }
        } else if model.mergedByRepo {
            grouped
        } else {
            latest
        }
    }

    private var latest: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(model.merged.enumerated()), id: \.element.id) { index, pr in
                    MergedRow(pr: pr, repoLabel: repoLabel(pr.repo)) { model.open(pr) }
                        .staggeredReveal(index)
                }
            }
            .padding(.bottom, 10)
        }
        .scrollIndicators(.never)
    }

    private var grouped: some View {
        let groups = MergedPRs.byRepo(model.merged)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(groups.enumerated()), id: \.element.id) { groupIndex, group in
                    let first = groups[..<groupIndex].reduce(0) { $0 + 1 + $1.prs.count }
                    let collapsed = model.collapsedMergedRepos.contains(group.repo)
                    RepoHeader(repo: group.repo, prs: group.prs, showOwner: showOwner, collapsed: collapsed, showsChecks: false, unit: "merged") {
                        withAnimation(reduceMotion ? nil : .arrive(0.34)) { model.toggleCollapsedMerged(group.repo) }
                    }
                    .staggeredReveal(first)
                    if !collapsed {
                        ForEach(Array(group.prs.enumerated()), id: \.element.id) { index, pr in
                            MergedRow(pr: pr, repoLabel: nil) { model.open(pr) }
                                .staggeredReveal(first + 1 + index)
                                .transition(.opacity.combined(with: .offset(y: -6)))
                        }
                    }
                }
            }
            .padding(.bottom, 10)
        }
        .scrollIndicators(.never)
    }
}

private struct MergedRow: View {
    let pr: ReviewPR
    /// Nil when the repository name is already in the group header.
    var repoLabel: String?
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(pr.title)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Palette.text)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        if let repoLabel {
                            Text(verbatim: repoLabel)
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(Palette.dim)
                                .lineLimit(1)
                        }
                        Text(verbatim: "#\(pr.number)")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Palette.faint)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if let mergedAt = pr.mergedAt {
                    Age(date: mergedAt, stale: false, note: ", merged")
                        .padding(.top, 3)
                }
            }
            .padding(.leading, repoLabel == nil ? 39 : 18)
            .padding(.trailing, 18)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RowHighlight(on: hovering))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableRow())
        .onHover { over in withAnimation(.arrive(0.2)) { hovering = over } }
        .help(pr.repo)
    }
}

/// A small outlined state tag, e.g. APPROVED or DRAFT.
private struct StatusTag: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .readout(size: 8, tracking: 1)
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 3).fill(color.opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(color.opacity(0.35)))
            .fixedSize()
    }
}

// MARK: - Shared pieces

private enum Layout {
    /// Where row text starts: padding, lamp, gap.
    static let textInset: CGFloat = 18 + 24 + 14
}

/// Hover wash for rows, with a short amber tick on the leading edge.
private struct RowHighlight: View {
    let on: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(Color.white.opacity(on ? 0.035 : 0))
            Capsule()
                .fill(Palette.amber)
                .frame(width: 2, height: on ? 18 : 0)
                .padding(.leading, 6)
                .opacity(on ? 1 : 0)
        }
    }
}

/// Hover control that puts a GitHub link on the clipboard. The icon turns into an amber check for a moment
/// so the copy registers without a toast.
private struct CopyLinkButton: View {
    let url: String
    @State private var copied = false
    @State private var copies = 0

    var body: some View {
        Button {
            copyLink(url)
            copies += 1
            let copy = copies
            withAnimation(.arrive(0.2)) { copied = true }
            Task {
                try? await Task.sleep(for: .seconds(1.4))
                // A second click restarts the clock instead of being cut short by the first.
                guard copy == copies else { return }
                withAnimation(.leave()) { copied = false }
            }
        } label: {
            // Stacked rather than swapped so the link glyph keeps ChromeButton's hover color.
            ZStack {
                Image(systemName: "link")
                    .opacity(copied ? 0 : 1)
                Image(systemName: "checkmark")
                    .foregroundStyle(Palette.amber)
                    .opacity(copied ? 1 : 0)
                    .scaleEffect(copied ? 1 : 0.6)
            }
        }
        .buttonStyle(ChromeButton())
        .help(copied ? "Copied" : "Copy link")
        .accessibilityLabel("Copy link")
    }
}

private func copyLink(_ url: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(url, forType: .string)
}

/// The cluster of hover controls pinned to a row's top-trailing corner, on a raised backing so they sit
/// cleanly over the row text.
private struct HoverControls<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 2) { content() }
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Palette.raised))
            .transition(.opacity.combined(with: .scale(scale: 0.8)))
    }
}

/// A pinned section header: readout label, optional count, a hairline to the edge, optional trailing control.
private struct RuledHeader<Trailing: View>: View {
    let title: String
    var count: Int?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .readout(size: 9, tracking: 1.6)
                .foregroundStyle(Palette.dim)
            if let count {
                Text(verbatim: "\(count)")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(count > 0 ? Palette.ink : Palette.faint)
                    .padding(.horizontal, 5)
                    .frame(minWidth: 16, minHeight: 14)
                    .background(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(count > 0 ? Palette.amber : Color.white.opacity(0.05))
                    )
            }
            Rectangle().fill(Palette.hairline).frame(height: 1)
            trailing()
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 6)
        .background(Palette.ink.opacity(0.96))
    }
}

extension RuledHeader where Trailing == EmptyView {
    init(title: String, count: Int? = nil) {
        self.init(title: title, count: count) { EmptyView() }
    }
}

/// Compact age: "now", "12m", "5h", "3d", "6w". Amber once a PR is past the stale limit.
private struct Age: View {
    let date: Date
    let stale: Bool
    var note: String? = nil

    private var text: String {
        let seconds = max(0, -date.timeIntervalSinceNow)
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(Int(seconds / 60))m"
        case ..<86_400: return "\(Int(seconds / 3600))h"
        case ..<(86_400 * 14): return "\(Int(seconds / 86_400))d"
        default: return "\(Int(seconds / (86_400 * 7)))w"
        }
    }

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 10.5, weight: stale ? .semibold : .regular, design: .monospaced))
            .foregroundStyle(stale ? Palette.amber : Palette.faint)
            .help(date.formatted(date: .abbreviated, time: .shortened) + (note ?? (stale ? ", waiting longer than your stale limit" : "")))
    }
}

/// Small outlined text button in the readout voice.
private struct PillButton: ButtonStyle {
    var compact = false
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .readout(size: compact ? 8.5 : 9, tracking: 1.2)
            .foregroundStyle(hovering ? Palette.amber : Palette.dim)
            .padding(.horizontal, compact ? 7 : 10)
            .padding(.vertical, compact ? 3 : 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Palette.amber.opacity(configuration.isPressed ? 0.18 : hovering ? 0.08 : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(hovering ? Palette.amber.opacity(0.5) : Palette.hairlineStrong)
            )
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(.arrive(0.2), value: hovering)
    }
}

/// A GitHub label in its own color, like on github.com.
private struct LabelChip: View {
    let label: PRLabel

    private var color: Color {
        Color(hex: UInt32(label.color, radix: 16) ?? 0x888888)
    }

    var body: some View {
        Text(verbatim: label.name)
            .readout(size: 8.5, tracking: 0.8)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 3).fill(color.opacity(0.14)))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(color.opacity(0.45)))
    }
}

/// First launch, or a rejected token. The steps are the ones a new person actually runs.
private struct SignInState: View {
    let detail: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Radar(sweeping: true)
                .frame(width: 168, height: 168)
                .padding(.bottom, 22)
            Text("Sign in")
                .readout(size: 11, tracking: 3)
                .foregroundStyle(Palette.text)
            Text(detail)
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.dim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
                .padding(.top, 8)
            VStack(alignment: .leading, spacing: 8) {
                Text("brew install gh")
                Text("gh auth login")
            }
            .font(.system(size: 12.5, design: .monospaced))
            .foregroundStyle(Palette.text)
            .padding(.top, 18)
            Button("Try again", action: retry)
                .buttonStyle(PillButton())
                .padding(.top, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 24)
    }
}

/// Empty state: a quiet radar scope with no contacts on it.
private struct AllClear<Action: View>: View {
    let title: String
    let detail: String?
    let seed: Int
    var sweeping = false
    @ViewBuilder var action: () -> Action

    private static var lines: [String] {
        [
            "Nothing needs you right now.",
            "Quiet on every channel.",
            "No one's waiting on you. Go build something.",
            "Inbox zero. Enjoy it while it lasts.",
            "All threads answered. Nice.",
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            Radar(sweeping: sweeping)
                .frame(width: 168, height: 168)
                .padding(.bottom, 22)
            Text(title)
                .readout(size: 11, tracking: 3)
                .foregroundStyle(Palette.text)
            Text(detail ?? Self.lines[seed % Self.lines.count])
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.dim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 290)
                .padding(.top, 8)
            action().padding(.top, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 24)
    }
}

extension AllClear where Action == EmptyView {
    init(title: String, detail: String?, seed: Int, sweeping: Bool = false) {
        self.init(title: title, detail: detail, seed: seed, sweeping: sweeping) { EmptyView() }
    }
}

private struct Radar: View {
    var sweeping: Bool

    var body: some View {
        // Scope and beam are each drawn once. Turning the beam only changes its transform.
        ZStack {
            RadarScope()
            Looping(period: 2 * .pi / (sweeping ? 1.6 : 0.5), framesPerSecond: 60) { cycle in
                RadarBeam()
                    .rotationEffect(.radians(cycle.map { $0 * 2 * .pi } ?? -.pi / 4))
            }
        }
        .accessibilityHidden(true)
    }
}

/// Rings, crosshair and bearing ticks.
private struct RadarScope: View {
    var body: some View {
        Canvas { gc, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 1

            for ring in 1...4 {
                let r = radius * CGFloat(ring) / 4
                gc.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                          with: .color(.white.opacity(ring == 4 ? 0.12 : 0.06)), lineWidth: 1)
            }
            var cross = Path()
            cross.move(to: CGPoint(x: center.x - radius, y: center.y))
            cross.addLine(to: CGPoint(x: center.x + radius, y: center.y))
            cross.move(to: CGPoint(x: center.x, y: center.y - radius))
            cross.addLine(to: CGPoint(x: center.x, y: center.y + radius))
            gc.stroke(cross, with: .color(.white.opacity(0.05)), lineWidth: 1)

            // Bearing ticks around the rim.
            for i in 0..<72 {
                let angle = Double(i) / 72 * 2 * .pi
                let inner = radius - (i % 6 == 0 ? 7 : 3)
                var tick = Path()
                tick.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
                tick.addLine(to: CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
                gc.stroke(tick, with: .color(.white.opacity(i % 6 == 0 ? 0.18 : 0.08)), lineWidth: 1)
            }
        }
    }
}

/// The beam pointing along +x, with its trail behind it. `Radar` turns it.
private struct RadarBeam: View {
    var body: some View {
        Canvas { gc, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 1
            let heading = 0.0
            // The trail behind the beam, drawn as thin slices that fade with distance.
            let trail = 1.1, slices = 28
            for i in 0..<slices {
                let from = heading - trail * Double(i + 1) / Double(slices)
                let to = heading - trail * Double(i) / Double(slices)
                var slice = Path()
                slice.move(to: center)
                slice.addArc(center: center, radius: radius - 1, startAngle: .radians(from), endAngle: .radians(to), clockwise: false)
                slice.closeSubpath()
                let fade = 1 - Double(i) / Double(slices)
                gc.fill(slice, with: .color(Palette.amber.opacity(0.2 * fade * fade)))
            }
            var beam = Path()
            beam.move(to: center)
            beam.addLine(to: CGPoint(x: center.x + cos(heading) * radius, y: center.y + sin(heading) * radius))
            gc.stroke(beam, with: .color(Palette.amber.opacity(0.7)), lineWidth: 1)

            gc.fill(Path(ellipseIn: CGRect(x: center.x - 2.5, y: center.y - 2.5, width: 5, height: 5)), with: .color(Palette.amber))
        }
    }
}
