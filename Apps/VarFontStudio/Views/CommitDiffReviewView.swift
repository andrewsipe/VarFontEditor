import SwiftUI
import VarFontCore

// MARK: - Review (tabbed presentation)

struct CommitDiffReviewView: View {
    @EnvironmentObject private var editor: EditorViewModel
    let session: CommitPreflightSession
    var fillsAvailableHeight: Bool = false
    private let actionBar: AnyView

    init(session: CommitPreflightSession, fillsAvailableHeight: Bool = false) {
        self.session = session
        self.fillsAvailableHeight = fillsAvailableHeight
        self.actionBar = AnyView(EmptyView())
    }

    init<ActionBar: View>(
        session: CommitPreflightSession,
        fillsAvailableHeight: Bool = false,
        @ViewBuilder actionBar: () -> ActionBar
    ) {
        self.session = session
        self.fillsAvailableHeight = fillsAvailableHeight
        self.actionBar = AnyView(actionBar())
    }

    private var projectID: String { session.projectID }
    private var uiState: SaveReviewUIState { editor.saveReviewUIState(forProjectID: projectID) }

    private var selectedTab: SaveReviewTableTab {
        uiState.selectedTableTab
    }

    private var activeTab: SaveReviewTabPresentation? {
        session.presentation.tabs.first { $0.id == selectedTab }
            ?? session.presentation.tabs.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            pinnedChrome
            if let activeTab, !session.presentation.tabs.isEmpty {
                headlineView(for: activeTab)
                    .padding(.horizontal, SaveReviewLayout.horizontalPadding)
                    .padding(.top, 10)
                    .padding(.bottom, 2)
                rowScrollContent(for: activeTab)
                    .layoutPriority(1)
            } else if session.preflight.ok {
                Text("No changes to review — this export won't modify anything.")
                    .font(StudioTypography.body)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, SaveReviewLayout.horizontalPadding)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .preferredColorScheme(.dark)
        .frame(maxHeight: fillsAvailableHeight ? .infinity : nil, alignment: .top)
    }

    // MARK: - Pinned chrome

    private var pinnedChrome: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: SaveReviewLayout.chromeSectionGap) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: SaveReviewLayout.chromeSectionGap) {
                        header
                        fileClarifiersBanner
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    actionBar
                }
                if let summary = session.preflight.summary {
                    summaryMetrics(summary, diffReport: session.diffReport)
                }
                if !session.preflight.warnings.isEmpty {
                    warningsCard(session.preflight.warnings)
                }
                if !session.preflight.errors.isEmpty {
                    errorsCard(session.preflight.errors)
                }
                if !session.presentation.tabs.isEmpty {
                    filterBadges
                        .padding(.bottom, 2)
                }
            }
            .padding(.horizontal, SaveReviewLayout.horizontalPadding)
            .padding(.bottom, SaveReviewLayout.chromeSectionGap)

            if !session.presentation.tabs.isEmpty {
                tabChrome
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Review")
                .font(StudioTypography.emphasis)
            Text("Planned write preview — after values with change context")
                .font(StudioTypography.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var fileClarifiersBanner: some View {
        let clarifiers = editor.clarifierLabels(for: session.fontID)
        let psPrefix = editor.familyPSPrefix(for: session.fontID)
        if !clarifiers.isEmpty || !psPrefix.isEmpty {
            HStack(spacing: 6) {
                if !psPrefix.isEmpty {
                    Text("PS prefix")
                        .font(StudioTypography.meta)
                        .foregroundStyle(.secondary)
                    Text(psPrefix)
                        .font(StudioTypography.meta.monospaced())
                }
                if !clarifiers.isEmpty {
                    Text("Clarifiers")
                        .font(StudioTypography.meta)
                        .foregroundStyle(.secondary)
                    ForEach(clarifiers) { clarifier in
                        StudioClarifierPill(label: clarifier.label, compact: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func summaryMetrics(_ summary: CommitSummary, diffReport: CommitDiffReport) -> some View {
        let nameRemoved = diffReport.nameIDRows.filter { $0.change == .removed && !$0.reflowSuppressed }.count
        let nameAdded = diffReport.nameIDRows.filter { $0.change == .added && $0.reflowedFromNameID == nil }.count

        HStack(spacing: SaveReviewLayout.summaryCardGap) {
            StudioMetricCard(value: "\(summary.instancesWritten)", label: "Instances", minWidth: 0, accentValue: true, fillsWidth: true, prominent: true)
            StudioMetricCard(value: "\(summary.statValuesWritten)", label: "STAT values", minWidth: 0, accentValue: true, fillsWidth: true, prominent: true)
            StudioMetricCard(value: "\(summary.nameIDsAllocated.count)", label: "New name IDs", minWidth: 0, accentValue: true, fillsWidth: true, prominent: true)
            StudioMetricCard(value: "\(nameRemoved)", label: "Removed", minWidth: 0, accentValue: true, fillsWidth: true, prominent: true)
            StudioMetricCard(value: "\(nameAdded)", label: "Added", minWidth: 0, accentValue: true, fillsWidth: true, prominent: true)
        }
    }

    @ViewBuilder
    private var filterBadges: some View {
        if let activeTab {
            let counts = categoryCounts(for: activeTab)
            HStack(spacing: SaveReviewLayout.filterBadgeGap) {
                ForEach(SaveReviewDisplayCategory.filterOrder, id: \.self) { category in
                    let count = counts[category, default: 0]
                    if count > 0 {
                        StudioFilterBadge(
                            category: category,
                            count: count,
                            isHidden: isCategoryHidden(category),
                            isIsolated: uiState.isolateCategory == category
                        ) { commandClick in
                            toggleCategory(category, commandClick: commandClick)
                        }
                    }
                }
                Spacer(minLength: 8)
                Text("click to show/hide · ⌘-click to isolate")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var tabChrome: some View {
        VStack(alignment: .leading, spacing: 0) {
            StudioSaveReviewTabBar(
                tabs: session.presentation.tabs,
                selectedTab: Binding(
                    get: { selectedTab },
                    set: { newTab in
                        editor.updateSaveReviewUIState(forProjectID: projectID) {
                            $0.selectedTableTab = newTab
                            $0.userPickedTableTab = true
                        }
                    }
                )
            )
            .padding(.horizontal, SaveReviewLayout.horizontalPadding)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .overlay(alignment: .bottom) {
                Rectangle().fill(StudioColors.surfaceStroke).frame(height: 0.5)
            }

            HStack(spacing: 12) {
                StudioSearchField(
                    text: Binding(
                        get: { uiState.searchQuery },
                        set: { query in
                            editor.updateSaveReviewUIState(forProjectID: projectID) {
                                $0.searchQuery = query
                            }
                        }
                    ),
                    placeholder: "Search rows"
                )
                .frame(maxWidth: 220)

                if let activeTab {
                    Text(rowCountLabel(for: activeTab))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }

                Spacer(minLength: 0)

                nameidStrategyPreference
            }
            .padding(.horizontal, SaveReviewLayout.horizontalPadding)
            .padding(.vertical, 6)
            .frame(minHeight: 34)
            .overlay(alignment: .bottom) {
                Rectangle().fill(StudioColors.surfaceStroke).frame(height: 0.5)
            }
        }
        .background(StudioColors.surfaceSubtle.opacity(0.5))
    }

    private var nameidStrategyPreference: some View {
        let strategy = Binding<NameIDStrategy>(
            get: { editor.nameidStrategy(forProjectID: projectID) },
            set: { editor.setNameIDStrategy(forProjectID: projectID, strategy: $0) }
        )
        return HStack(spacing: 8) {
            Text("OpenType labels")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize()
            Picker("OpenType labels", selection: strategy) {
                Text("Preserve IDs").tag(NameIDStrategy.preserve)
                Text("Repack to 256+").tag(NameIDStrategy.reflow)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .disabled(editor.isSaveReviewLoading(forProjectID: projectID, fontID: session.fontID))
        }
        .layoutPriority(1)
        .help("Preserve keeps existing feature name IDs. Repack renumbers them to start at 256, avoiding conflicts with reserved low IDs.")
    }

    @ViewBuilder
    private func headlineView(for tab: SaveReviewTabPresentation) -> some View {
        let headline = tab.headline
        if headline.hasPrefix(tab.label) {
            let suffix = String(headline.dropFirst(tab.label.count))
                .trimmingCharacters(in: .whitespaces)
            HStack(spacing: 4) {
                Text(tab.label)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                if !suffix.isEmpty {
                    Text(suffix)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 11.5))
        } else {
            Text(headline)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
    }

    private func rowCountLabel(for tab: SaveReviewTabPresentation) -> String {
        let visible = visibleRowCount(in: tab)
        let total = tab.sections.reduce(0) { $0 + $1.rows.count }
        return "\(visible) of \(total) rows shown"
    }

    // MARK: - Scrollable rows

    @ViewBuilder
    private func rowScrollContent(for tab: SaveReviewTabPresentation) -> some View {
        let sections = filteredSections(for: tab)
        if sections.isEmpty {
            Text("No rows match the current filters.")
                .font(StudioTypography.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
                .frame(minHeight: fillsAvailableHeight ? 200 : 420, maxHeight: fillsAvailableHeight ? .infinity : 420)
        } else {
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(sections) { section in
                        Section {
                            ForEach(section.rows) { row in
                                StudioStreamlinedDiffRow(row: row)
                            }
                        } header: {
                            StudioSaveReviewPhaseHeader(title: section.title)
                        }
                    }
                }
                .padding(.bottom, 6)
            }
            .background(SaveReviewLayout.canvasBackground)
            .scrollContentBackground(.hidden)
            .frame(minHeight: fillsAvailableHeight ? 200 : 420, maxHeight: fillsAvailableHeight ? .infinity : 420)
        }
    }

    // MARK: - Filtering

    private func categoryCounts(for tab: SaveReviewTabPresentation) -> [SaveReviewDisplayCategory: Int] {
        var counts: [SaveReviewDisplayCategory: Int] = [:]
        for row in tab.sections.flatMap(\.rows) {
            counts[row.category, default: 0] += 1
        }
        return counts
    }

    private func isCategoryHidden(_ category: SaveReviewDisplayCategory) -> Bool {
        if let isolate = uiState.isolateCategory {
            return category != isolate
        }
        return uiState.hiddenCategories.contains(category)
    }

    private func toggleCategory(_ category: SaveReviewDisplayCategory, commandClick: Bool) {
        editor.updateSaveReviewUIState(forProjectID: projectID) { state in
            if commandClick {
                if state.isolateCategory == category {
                    state.isolateCategory = nil
                } else {
                    state.isolateCategory = category
                    state.hiddenCategories.removeAll()
                }
                return
            }
            state.isolateCategory = nil
            if state.hiddenCategories.contains(category) {
                state.hiddenCategories.remove(category)
            } else {
                state.hiddenCategories.insert(category)
            }
        }
    }

    private func rowIsVisible(_ row: SaveReviewRowPresentation) -> Bool {
        if let isolate = uiState.isolateCategory {
            return row.category == isolate
        }
        return !uiState.hiddenCategories.contains(row.category)
    }

    private func rowMatchesSearch(_ row: SaveReviewRowPresentation) -> Bool {
        let query = uiState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }
        return row.searchText.contains(query)
    }

    private func filteredSections(for tab: SaveReviewTabPresentation) -> [SaveReviewSectionPresentation] {
        tab.sections.compactMap { section in
            let rows = section.rows.filter { rowIsVisible($0) && rowMatchesSearch($0) }
            guard !rows.isEmpty else { return nil }
            return SaveReviewSectionPresentation(title: section.title, rows: rows)
        }
    }

    private func visibleRowCount(in tab: SaveReviewTabPresentation) -> Int {
        filteredSections(for: tab).reduce(0) { $0 + $1.rows.count }
    }

    // MARK: - Cards

    @ViewBuilder
    private func warningsCard(_ warnings: [PlanWarning]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Warnings")
                .font(StudioTypography.sectionLabel)
                .foregroundStyle(.secondary)
            ForEach(Array(warnings.enumerated()), id: \.offset) { _, warning in
                StudioWarningMessage(message: warning.message)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: StudioRadius.chip)
                .strokeBorder(StudioColors.warningStroke, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func errorsCard(_ errors: [CommitError]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Cannot export")
                .font(StudioTypography.sectionLabel)
                .foregroundStyle(.secondary)
            ForEach(Array(errors.enumerated()), id: \.offset) { _, error in
                Text(error.message)
                    .font(StudioTypography.caption)
                    .foregroundStyle(StudioColors.errorForeground)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: StudioRadius.chip)
                .strokeBorder(StudioColors.errorStroke, lineWidth: 1)
        )
    }
}
