import Core
import SwiftUI

struct PanelView: View {
    @ObservedObject var model: AppModel
    let openFilters: () -> Void
    @State private var tab = Tab.notifications
    /// Which side the next tab slides in from: 1 when moving right, -1 when moving left.
    @State private var direction: CGFloat = 1
    @Namespace private var indicator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Tab: Int { case notifications, reviews, mine }

    init(model: AppModel, openFilters: @escaping () -> Void) {
        self.model = model
        self.openFilters = openFilters
    }

    #if DEBUG
    /// Snapshots open on a chosen tab. Release builds always open on Unread.
    init(model: AppModel, openFilters: @escaping () -> Void, initialTab: Tab) {
        self.model = model
        self.openFilters = openFilters
        _tab = State(initialValue: initialTab)
    }
    #endif

    static let size = CGSize(width: 460, height: 600)

    var body: some View {
        VStack(spacing: 0) {
            StatusStrip(model: model, openFilters: openFilters)
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
                    MineTab(model: model)
                        .transition(slide)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            // A new id each time the panel opens, so the rows play their entrance again.
            .id(model.panelOpens)
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
            readoutTab(.mine, label: "Mine", count: model.mineCount, dim: false)
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
                MineTelemetry(model: model)
                    .padding(.bottom, 14)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
    }

    private func readoutTab(_ value: Tab, label: String, count: Int, dim: Bool) -> some View {
        let selected = tab == value
        return Button {
            direction = value.rawValue > tab.rawValue ? 1 : -1
            withAnimation(reduceMotion ? nil : .arrive(0.38)) { tab = value }
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
                ZStack(alignment: .leading) {
                    Color.clear.frame(width: 36, height: 2)
                    if selected {
                        Capsule()
                            .fill(Palette.amber)
                            .frame(width: 36, height: 2)
                            .matchedGeometryEffect(id: "indicator", in: indicator)
                    }
                }
            }
            .fixedSize()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(count) \(label)")
        .accessibilityAddTraits(selected ? .isSelected : [])
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

/// Right side of the Mine header: what each of your PRs is waiting on.
private struct MineTelemetry: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let prs = model.mine.flatMap(\.prs).filter { !$0.isDraft }
        let failing = prs.filter { $0.ciState == "FAILURE" || $0.ciState == "ERROR" }
        VStack(alignment: .trailing, spacing: 6) {
            TelemetryLine(label: "Ready", value: prs.filter { $0.reviewDecision == "APPROVED" && !failing.contains($0) }.count, color: Palette.green)
            TelemetryLine(label: "Changes", value: prs.filter { $0.reviewDecision == "CHANGES_REQUESTED" }.count, color: Palette.red)
            TelemetryLine(label: "Failing CI", value: failing.count, color: Palette.red)
        }
    }
}

private struct TelemetryLine: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .readout(size: 8.5, tracking: 1.3)
                .foregroundStyle(Palette.faint)
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
    let openFilters: () -> Void

    private var state: (color: Color, pulsing: Bool) {
        if model.isRefreshing { return (Palette.amber, true) }
        if !model.errors.isEmpty { return (Palette.red, false) }
        return (Palette.green, false)
    }

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(color: state.color, pulsing: state.pulsing)
            TimelineView(.periodic(from: .now, by: 5)) { context in
                Text(statusText(now: context.date))
                    .readout(size: 9, tracking: 1.3)
                    .foregroundStyle(model.errors.isEmpty ? Palette.faint : Palette.red)
                    .lineLimit(1)
                    .help(model.errors.joined(separator: "\n"))
            }
            Spacer(minLength: 8)
            Button { Task { await model.refresh() } } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(model.isRefreshing ? 360 : 0))
                    .animation(model.isRefreshing ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default, value: model.isRefreshing)
            }
            .buttonStyle(ChromeButton())
            .disabled(model.isRefreshing)
            .help("Refresh")
            Menu {
                Button("Review filters…", action: openFilters)
                Button("Open config file") { model.openConfig() }
                Divider()
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
    @State private var phase = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .background(Circle().fill(color.opacity(0.25)).frame(width: 12, height: 12).scaleEffect(pulsing && phase ? 1.4 : 1))
            .opacity(pulsing && phase ? 0.45 : 1)
            .animation(pulsing && !reduceMotion ? .easeInOut(duration: 0.7).repeatForever() : .arrive(0.3), value: phase)
            .onChange(of: pulsing, initial: true) { phase = pulsing }
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
        let groups = DayGroup.group(shown)
        let offsets = groups.indices.map { i in groups[..<i].reduce(0) { $0 + $1.items.count } }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(Array(groups.enumerated()), id: \.element.id) { groupIndex, day in
                    Section {
                        ForEach(Array(day.items.enumerated()), id: \.element.id) { index, item in
                            FeedRow(item: item, open: { model.open(item) }, dismiss: {
                                withAnimation(reduceMotion ? nil : .arrive(0.4)) { model.markRead(item) }
                            })
                            .staggeredReveal(offsets[groupIndex] + index)
                            .transition(.asymmetric(insertion: .opacity, removal: .opacity.combined(with: .offset(x: -40))))
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

/// Feed items that share a calendar day, newest day first.
private struct DayGroup: Identifiable {
    let day: Date
    let items: [FeedItem]
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

    static func group(_ items: [FeedItem]) -> [DayGroup] {
        let calendar = Calendar.current
        let byDay = Dictionary(grouping: items) { calendar.startOfDay(for: $0.createdAt) }
        return byDay.keys.sorted(by: >).map { day in
            DayGroup(day: day, items: byDay[day]!.sorted { $0.createdAt > $1.createdAt })
        }
    }
}

private struct FeedRow: View {
    let item: FeedItem
    let open: () -> Void
    let dismiss: () -> Void
    @State private var hovering = false

    private var kind: (symbol: String, label: String, color: Color) {
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

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 14) {
                Lamp(symbol: kind.symbol, color: kind.color, lit: !item.read)
                VStack(alignment: .leading, spacing: 5) {
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
                            .opacity(hovering && !item.read ? 0 : 1)
                    }
                    .frame(height: 16)
                    Text(item.prTitle)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(item.read || item.isClosed ? Palette.dim : Palette.text)
                        .strikethrough(item.isClosed, color: Palette.faint)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: "\(item.pr.name)#\(item.pr.number)" + (item.isClosed ? " · \(item.prState.lowercased())" : ""))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Palette.faint)
                    if !item.snippet.isEmpty {
                        Text(item.snippet)
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.dim)
                            .lineLimit(2)
                            .lineSpacing(1.5)
                            .padding(.top, 3)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RowHighlight(on: hovering))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableRow())
        .overlay(alignment: .topTrailing) {
            if hovering && !item.read {
                Button(action: dismiss) { Image(systemName: "checkmark") }
                    .buttonStyle(ChromeButton())
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Palette.raised))
                    .help("Mark read without opening")
                    .padding(.top, 8)
                    .padding(.trailing, 10)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .onHover { over in withAnimation(.arrive(0.2)) { hovering = over } }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Mark read", dismiss)
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
                Menu { hideButtons } label: { Image(systemName: "eye.slash") }
                    .menuStyle(.button)
                    .buttonStyle(ChromeButton())
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Hide this PR or its repo")
                    .padding(.top, 6)
                    .padding(.trailing, 10)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        .onHover { over in withAnimation(.arrive(0.2)) { hovering = over } }
        .contextMenu { hideButtons }
    }
}

/// CI status as a lamp: shape and color both carry the state.
private struct CILamp: View {
    let state: String?
    @State private var phase = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var look: (symbol: String, color: Color, label: String, lit: Bool) {
        switch state {
        case "SUCCESS": return ("checkmark", Palette.green, "passing", true)
        case "FAILURE", "ERROR": return ("xmark", Palette.red, "failing", true)
        case "PENDING", "EXPECTED": return ("ellipsis", Palette.amber, "running", true)
        default: return ("minus", Palette.faint, "no checks", false)
        }
    }

    private var running: Bool { look.label == "running" && !reduceMotion }

    var body: some View {
        Lamp(symbol: look.symbol, color: look.color, lit: look.lit)
            .opacity(running && phase ? 0.5 : 1)
            .animation(running ? .easeInOut(duration: 0.9).repeatForever() : nil, value: phase)
            .onAppear { if running { phase = true } }
            .help("CI: \(look.label)")
    }
}

// MARK: - Mine

private struct MineTab: View {
    @ObservedObject var model: AppModel
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
                    // Running position, so the entrance cascades through headers and rows in reading order.
                    let groups = model.mine.map { (group: $0, buckets: buckets($0.prs)) }
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
                                let collapsed = model.collapsedRepos.contains(bucket.repo)
                                RepoHeader(repo: bucket.repo, prs: bucket.prs, showOwner: showOwner, collapsed: collapsed) {
                                    withAnimation(reduceMotion ? nil : .arrive(0.34)) { model.toggleCollapsed(bucket.repo) }
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
                            RuledHeader(title: entry.group.name, count: entry.group.count)
                        }
                    }
                }
                .padding(.bottom, 10)
            }
            .scrollIndicators(.never)
        }
    }
}

/// A repo inside a Mine layer. Click to fold its PRs away; folded, it keeps one CI dot per PR.
private struct RepoHeader: View {
    let repo: String
    let prs: [ReviewPR]
    let showOwner: Bool
    let collapsed: Bool
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
                if collapsed {
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
        .accessibilityLabel("\(repo), \(prs.count) open")
        .accessibilityValue(collapsed ? "collapsed" : "expanded")
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

    private var review: (label: String, color: Color)? {
        switch pr.reviewDecision {
        case "APPROVED": return ("Approved", Palette.green)
        case "CHANGES_REQUESTED": return ("Changes requested", Palette.red)
        case "REVIEW_REQUIRED": return ("Awaiting review", Palette.steel)
        default: return nil
        }
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
                        if pr.isDraft { StatusTag(text: "Draft", color: Palette.dim) }
                        if let review { StatusTag(text: review.label, color: review.color) }
                        Text(verbatim: "#\(pr.number)")
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Palette.faint)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Age(date: pr.createdAt, stale: false)
                    .padding(.top, 3)
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
            .help(date.formatted(date: .abbreviated, time: .shortened) + (stale ? ", waiting longer than your stale limit" : ""))
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
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

                let speed = sweeping ? 1.6 : 0.5
                let heading = reduceMotion ? -Double.pi / 4 : context.date.timeIntervalSinceReferenceDate * speed
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
        .accessibilityHidden(true)
    }
}
