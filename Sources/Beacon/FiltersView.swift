import Core
import SwiftUI

/// Edits review categories. Works on a copy of the config and writes it on Save.
struct FiltersView: View {
    @ObservedObject var model: AppModel
    let close: () -> Void

    @State private var categories: [Core.Category]
    @State private var globalExcludes: [String]
    @State private var originalNames: [UUID: String]
    @State private var selection: Selection?
    @State private var error: String?

    enum Selection: Hashable {
        case everywhere
        case category(UUID)
    }

    init(model: AppModel, close: @escaping () -> Void) {
        self.model = model
        self.close = close
        let config = (try? ConfigStore.load()) ?? Config()
        _categories = State(initialValue: config.categories)
        _globalExcludes = State(initialValue: config.excludeRepos)
        _originalNames = State(initialValue: Dictionary(uniqueKeysWithValues: config.categories.map { ($0.id, $0.name) }))
        _selection = State(initialValue: config.categories.first.map { .category($0.id) } ?? .everywhere)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar.frame(width: 210)
                Rectangle().fill(Palette.hairlineStrong).frame(width: 1)
                detail.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Rectangle().fill(Palette.hairlineStrong).frame(height: 1)
            HStack {
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Palette.red)
                        .font(.callout)
                }
                Spacer()
                Button("Cancel", action: close).keyboardShortcut(.cancelAction)
                Button("Save", action: save).keyboardShortcut(.defaultAction)
            }
            .padding(14)
            .background(Palette.surface)
        }
        .frame(minWidth: 720, minHeight: 520)
        .background(Palette.ink)
        .environment(\.colorScheme, .dark)
        .tint(Palette.amber)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Label("Hidden everywhere", systemImage: "eye.slash").tag(Selection.everywhere)
                Section("Categories") {
                    ForEach(categories) { category in
                        Text(category.name.isEmpty ? "Untitled" : category.name).tag(Selection.category(category.id))
                    }
                    .onMove { categories.move(fromOffsets: $0, toOffset: $1) }
                }
            }
            .scrollContentBackground(.hidden)
            HStack(spacing: 4) {
                Menu {
                    ForEach(Core.Category.presets, id: \.query) { preset in
                        Button(preset.label) { addCategory(query: preset.query) }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Add a category")
                Button {
                    removeSelected()
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(.borderless)
                .disabled(selectedIndex == nil)
                .help("Delete the selected category")
                Spacer()
            }
            .padding(8)
        }
        .background(Palette.surface)
    }

    @ViewBuilder
    private var detail: some View {
        if selection == .everywhere {
            Form {
                Section {
                    RepoTokens(repos: $globalExcludes, suggestions: model.knownRepos, emptyText: "No repos hidden")
                } header: {
                    Text("Hidden from every category")
                } footer: {
                    Text("PRs from these repos never show in Reviews or count toward the badge.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        } else if let index = selectedIndex {
            CategoryEditor(category: $categories[index], globalExcludes: globalExcludes, model: model)
                .id(categories[index].id)
        } else {
            Text("Select a category").foregroundStyle(.secondary)
        }
    }

    private var selectedIndex: Int? {
        guard case .category(let id) = selection else { return nil }
        return categories.firstIndex { $0.id == id }
    }

    private func addCategory(query: String) {
        let category = Core.Category(name: "New category", query: query)
        categories.append(category)
        selection = .category(category.id)
    }

    private func removeSelected() {
        guard let index = selectedIndex else { return }
        categories.remove(at: index)
        selection = categories.indices.contains(index) ? .category(categories[index].id) : categories.last.map { .category($0.id) }
    }

    private func save() {
        let names = categories.map { $0.name.trimmingCharacters(in: .whitespaces) }
        if names.contains("") { error = "Every category needs a name."; return }
        if Set(names).count != names.count { error = "Category names must be unique."; return }
        if categories.contains(where: { $0.query.trimmingCharacters(in: .whitespaces).isEmpty }) {
            error = "Every category needs a search query."
            return
        }
        let renames = categories.compactMap { category -> (String, String)? in
            guard let old = originalNames[category.id], old != category.name else { return nil }
            return (old, category.name)
        }
        model.editConfig { config in
            config.categories = categories
            config.excludeRepos = globalExcludes
            for (old, new) in renames {
                for i in config.badgeChain.indices where config.badgeChain[i].category == old {
                    config.badgeChain[i].category = new
                }
            }
        }
        close()
    }
}

private struct CategoryEditor: View {
    @Binding var category: Core.Category
    let globalExcludes: [String]
    @ObservedObject var model: AppModel
    @State private var matches: Int?
    @State private var counting = false

    /// The query as GitHub will see it, with `{teammates}` left as a placeholder.
    private var preview: String {
        var shown = category
        shown.query = category.query.replacingOccurrences(of: "{teammates}", with: "<teammates>")
        return shown.searchQuery(teammates: [], alsoExcluding: globalExcludes) ?? category.query
    }

    private var presetLabel: String {
        Core.Category.presets.first { $0.query == category.query }?.label ?? "Custom query"
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $category.name)
                Picker("Show PRs", selection: Binding(
                    get: { category.query },
                    set: { category.query = $0 }
                )) {
                    ForEach(Core.Category.presets, id: \.query) { preset in
                        Text(preset.label).tag(preset.query)
                    }
                    if presetLabel == "Custom query" {
                        Text("Custom query").tag(category.query)
                    }
                }
            }

            Section {
                RepoTokens(repos: $category.includeRepos, suggestions: model.knownRepos, emptyText: "Any repo")
            } header: {
                Text("Only these repos")
            }

            Section {
                RepoTokens(repos: $category.excludeRepos, suggestions: model.knownRepos, emptyText: "No repos hidden")
            } header: {
                Text("Hide these repos")
            } footer: {
                if !globalExcludes.isEmpty {
                    Text("Also hidden everywhere: \(globalExcludes.map(shortName).joined(separator: ", "))")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                TextField("Search query", text: $category.query, axis: .vertical)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(2...4)
                LabeledContent("Sent to GitHub") {
                    Text(preview)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Palette.amber.opacity(0.85))
                        .textSelection(.enabled)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Matches") {
                    if counting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(matches.map { "\($0) open PRs" } ?? "–")
                    }
                }
            } header: {
                Text("Advanced")
            } footer: {
                Text("Any GitHub search works here. {teammates} expands to author: for each teammate.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .task(id: preview) {
            counting = true
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            matches = await model.matchCount(category, globalExcludes: globalExcludes)
            counting = false
        }
    }
}

/// A list of repos shown as removable chips, with a text field and a menu of suggestions to add more.
private struct RepoTokens: View {
    @Binding var repos: [String]
    let suggestions: [String]
    let emptyText: String
    @State private var input = ""
    @State private var message: String?

    private var available: [String] {
        let query = input.trimmingCharacters(in: .whitespaces).lowercased()
        return suggestions.filter { !repos.contains($0) && (query.isEmpty || $0.lowercased().contains(query)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if repos.isEmpty {
                Text(emptyText).foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(repos, id: \.self) { repo in
                        HStack(spacing: 4) {
                            Text(shortName(repo))
                            Button {
                                repos.removeAll { $0 == repo }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.leading, 9)
                        .padding(.trailing, 4)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Palette.amber.opacity(0.12)))
                        .overlay(Capsule().strokeBorder(Palette.amber.opacity(0.35)))
                        .help(repo)
                    }
                }
            }
            HStack {
                TextField("repo or org/repo", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { add(input) }
                Menu("Add") {
                    ForEach(available, id: \.self) { repo in
                        Button(repo) { add(repo) }
                    }
                }
                .fixedSize()
                .disabled(available.isEmpty)
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(Palette.red)
            }
        }
    }

    private func add(_ text: String) {
        let typed = text.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return }
        // "frontend" resolves to "octo-org/frontend" when a known repo has that name.
        let repo = typed.contains("/") ? typed : suggestions.first { shortName($0).lowercased() == typed.lowercased() }
        guard let repo else {
            message = "Don't know \(typed). Type it as org/repo."
            return
        }
        if !repos.contains(repo) { repos.append(repo) }
        input = ""
        message = nil
    }
}

private func shortName(_ repo: String) -> String {
    repo.split(separator: "/").last.map(String.init) ?? repo
}

/// Lays children out left to right, wrapping to a new row when one runs out of width.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, maxWidth: proposal.width ?? .infinity)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.map { $0.height }.reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, maxWidth: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : spacing + size.width
            if rows[rows.count - 1].width + extra > maxWidth && !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let isFirst = rows[rows.count - 1].indices.isEmpty
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += isFirst ? size.width : spacing + size.width
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}
