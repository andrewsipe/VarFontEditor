import SwiftUI
import VarFontCore

// MARK: - Add stop sheet

struct AddAxisStopSheet: View {
    @EnvironmentObject private var editor: EditorViewModel
    @Environment(\.dismiss) private var dismiss

    let axis: AxisDefinition
    let onComplete: () -> Void

    @State private var statFormat = 1
    @State private var pinText = ""
    @State private var minText = ""
    @State private var maxText = ""
    @State private var nameText = ""
    @State private var codeText = ""
    @State private var linkTargetID: String?
    @State private var tabKeyMonitor: TabKeyMonitor?
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case pin, min, max, name, code
    }

    private var trimmedCode: String? {
        guard editor.isCodeNamingEnabled else { return nil }
        let t = codeText.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpacing.sectionGap) {
            Text("Add Stop")
                .font(StudioTypography.emphasis)

            Text(axisSubtitle)
                .font(StudioTypography.caption)
                .foregroundStyle(.secondary)

            Picker("STAT format", selection: $statFormat) {
                Text("Format 1 — static").tag(1)
                Text("Format 2 — range").tag(2)
                Text("Format 3 — linked").tag(3)
            }
            .pickerStyle(.menu)
            .onChange(of: statFormat) { _, _ in seedDefaults() }

            VStack(alignment: .leading, spacing: StudioSpacing.sectionGap) {
                formatFields
                StudioTextField(
                    placeholder: "Name",
                    text: $nameText,
                    rowHeight: StudioFieldMetrics.bodyRowHeight,
                    onSubmit: editor.isCodeNamingEnabled
                        ? { advanceFocusedField(from: .name) }
                        : addStopIfValid,
                    submitBehavior: editor.isCodeNamingEnabled ? .advance : .commit
                )
                .focused($focusedField, equals: .name)
                if editor.isCodeNamingEnabled {
                    StudioTextField(
                        placeholder: "Code",
                        text: $codeText,
                        font: StudioTypography.monoMeta,
                        rowHeight: StudioFieldMetrics.bodyRowHeight,
                        filledForeground: StudioColors.codeForeground,
                        onSubmit: addStopIfValid
                    )
                    .focused($focusedField, equals: .code)
                    .help("Optional 1–2 character classification code (letters or digits)")
                }
            }

            if let validationMessage {
                Text(validationMessage)
                    .font(StudioTypography.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    onComplete()
                    dismiss()
                }
                Button("Add Stop") {
                    addStopIfValid()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canAdd)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            seedDefaults()
            nameText = "Name"
            focusedField = .pin
            let monitor = TabKeyMonitor { shift in
                guard let focusedField else { return }
                let order = fieldOrder
                guard let index = order.firstIndex(of: focusedField) else { return }
                if shift {
                    if index > 0 { self.focusedField = order[index - 1] }
                } else if index + 1 < order.count {
                    self.focusedField = order[index + 1]
                }
            }
            monitor.start()
            tabKeyMonitor = monitor
        }
        .onDisappear {
            tabKeyMonitor?.stop()
            tabKeyMonitor = nil
        }
    }

    @ViewBuilder
    private var formatFields: some View {
        switch statFormat {
        case 2:
            StudioTextField(
                placeholder: "Min",
                text: $minText,
                font: StudioTypography.monoValue,
                rowHeight: StudioFieldMetrics.monoValueRowHeight,
                onSubmit: { advanceFocusedField(from: .min) },
                submitBehavior: .advance
            )
            .focused($focusedField, equals: .min)
            StudioTextField(
                placeholder: "Nominal (Pin)",
                text: $pinText,
                font: StudioTypography.monoValue,
                rowHeight: StudioFieldMetrics.monoValueRowHeight,
                onSubmit: { advanceFocusedField(from: .pin) },
                submitBehavior: .advance
            )
            .focused($focusedField, equals: .pin)
            StudioTextField(
                placeholder: "Max",
                text: $maxText,
                font: StudioTypography.monoValue,
                rowHeight: StudioFieldMetrics.monoValueRowHeight,
                onSubmit: { advanceFocusedField(from: .max) },
                submitBehavior: .advance
            )
            .focused($focusedField, equals: .max)
        case 3:
            StudioTextField(
                placeholder: "Static (Pin)",
                text: $pinText,
                font: StudioTypography.monoValue,
                rowHeight: StudioFieldMetrics.monoValueRowHeight,
                onSubmit: { advanceFocusedField(from: .pin) },
                submitBehavior: .advance
            )
            .focused($focusedField, equals: .pin)
            Picker("Link to", selection: Binding(
                get: { linkTargetID ?? linkCandidates.first?.id },
                set: { linkTargetID = $0 }
            )) {
                ForEach(linkCandidates) { candidate in
                    Text(candidate.name).tag(Optional(candidate.id))
                }
            }
        default:
            StudioTextField(
                placeholder: "Static (Pin)",
                text: $pinText,
                font: StudioTypography.monoValue,
                rowHeight: StudioFieldMetrics.monoValueRowHeight,
                onSubmit: { advanceFocusedField(from: .pin) },
                submitBehavior: .advance
            )
            .focused($focusedField, equals: .pin)
        }
    }

    private func advanceFocusedField(from field: Field) {
        let order = fieldOrder
        guard let index = order.firstIndex(of: field) else { return }
        if index + 1 < order.count {
            focusedField = order[index + 1]
        } else {
            focusedField = editor.isCodeNamingEnabled ? .code : .name
        }
    }

    private var fieldOrder: [Field] {
        var order: [Field]
        switch statFormat {
        case 2: order = [.min, .pin, .max, .name]
        default: order = [.pin, .name]
        }
        if editor.isCodeNamingEnabled {
            order.append(.code)
        }
        return order
    }

    private var linkCandidates: [AxisValue] {
        axis.values.filter { $0.statFormat != 3 }
    }

    private func seedDefaults() {
        let suggested = editor.suggestedNewStopValue(for: axis)
        pinText = StudioFormatting.axisValue(suggested)
        minText = StudioFormatting.axisValue(max((axis.min ?? suggested) , suggested - 20))
        maxText = StudioFormatting.axisValue(min((axis.max ?? suggested + 20), suggested + 20))
        if linkTargetID == nil {
            linkTargetID = linkCandidates.first?.id
        }
    }

    private var axisSubtitle: String {
        let title = axis.displayName ?? axis.tag
        if let min = axis.min, let max = axis.max {
            return "\(title) · allowed \(StudioFormatting.axisValue(min)) – \(StudioFormatting.axisValue(max))"
        }
        return title
    }

    private var parsedPin: Double? { Double(pinText.trimmingCharacters(in: .whitespacesAndNewlines)) }
    private var parsedMin: Double? { Double(minText.trimmingCharacters(in: .whitespacesAndNewlines)) }
    private var parsedMax: Double? { Double(maxText.trimmingCharacters(in: .whitespacesAndNewlines)) }

    private var trimmedName: String {
        nameText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var validationMessage: String? {
        if trimmedName.isEmpty { return "Name is required." }
        switch statFormat {
        case 2:
            guard let pin = parsedPin, let min = parsedMin, let max = parsedMax else {
                return "Enter valid min, nominal, and max values."
            }
            return editor.validateAxisStopValue(pin, for: axis)
                ?? (min <= pin && pin <= max ? nil : "Min ≤ Pin ≤ Max required.")
        case 3:
            guard parsedPin != nil else { return "Enter a valid static value." }
            guard linkTargetID != nil else { return "Choose a link target." }
            return parsedPin.flatMap { editor.validateAxisStopValue($0, for: axis) }
        default:
            guard let pin = parsedPin else { return "Enter a valid static value." }
            return editor.validateAxisStopValue(pin, for: axis)
        }
    }

    private var canAdd: Bool { validationMessage == nil }

    private func addStopIfValid() {
        guard canAdd else { return }
        let name = trimmedName
        let tag = axis.tag
        let code = trimmedCode
        onComplete()
        dismiss()
        Task { @MainActor in
            switch statFormat {
            case 2:
                guard let pin = parsedPin, let min = parsedMin, let max = parsedMax else { return }
                editor.insertAxisStop(
                    axisTag: tag,
                    value: pin,
                    name: name,
                    statFormat: 2,
                    rangeMin: min,
                    rangeMax: max,
                    code: code
                )
            case 3:
                guard let pin = parsedPin else { return }
                editor.insertAxisStop(
                    axisTag: tag,
                    value: pin,
                    name: name,
                    statFormat: 3,
                    linkedStopID: linkTargetID,
                    code: code
                )
            default:
                guard let pin = parsedPin else { return }
                editor.insertAxisStop(axisTag: tag, value: pin, name: name, code: code)
            }
        }
    }
}

// MARK: - Fill stops sheet

/// Standalone quick-fill tool, reachable anytime from the axis tree (not gated behind a plan
/// warning). Unlike the resolver's empty-axis fix, this replaces whatever stops already exist,
/// so it doubles as a way to re-fill gaps or redo a fill with a different count/interval —
/// just reopen the sheet and apply again, no undo required.
struct FillAxisStopsSheet: View {
    @EnvironmentObject private var editor: EditorViewModel
    @Environment(\.dismiss) private var dismiss

    let axis: AxisDefinition
    let onComplete: () -> Void

    @State private var fillMode: AxisStopFillMode = .evenCount
    @State private var stopCount: Double = 6
    @State private var intervalStep: Double = 1
    @State private var confirmingReplace = false

    private var options: AxisStopFillOptions? {
        AxisStopFillPlanner.options(for: axis)
    }

    private var values: [Double]? {
        switch fillMode {
        case .evenCount:
            return AxisStopFillPlanner.values(for: axis, count: Int(stopCount.rounded()))
        case .fixedInterval:
            return AxisStopFillPlanner.values(for: axis, interval: intervalStep)
        }
    }

    /// Stops whose name doesn't match their bare numeric value have been customized —
    /// replacing without confirmation would silently discard that naming work.
    private var hasCustomNamedStops: Bool {
        axis.values.contains { $0.name != AxisStopSuggestions.formatValue($0.value) }
    }

    private var canApply: Bool {
        (values?.count ?? 0) >= AxisStopFillPlanner.minStopCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpacing.sheetSectionSpacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Fill Stops")
                    .font(StudioTypography.emphasis)
                Text("\(axis.displayName ?? axis.tag) · replaces every stop currently on this axis")
                    .font(StudioTypography.caption)
                    .foregroundStyle(.secondary)
            }

            if let options {
                AxisStopFillControls(
                    axis: axis,
                    options: options,
                    fillMode: $fillMode,
                    stopCount: $stopCount,
                    intervalStep: $intervalStep
                )
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    onComplete()
                    dismiss()
                }
                Button("Fill") {
                    if hasCustomNamedStops {
                        confirmingReplace = true
                    } else {
                        apply()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canApply)
            }
        }
        .padding(20)
        .frame(minWidth: 460)
        .onAppear {
            guard let options else { return }
            stopCount = Double(options.defaultCount)
            intervalStep = options.defaultInterval
        }
        .alert("Replace Named Stops?", isPresented: $confirmingReplace) {
            Button("Replace", role: .destructive, action: apply)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This axis has stops with custom names. Filling will remove them and replace every stop on this axis.")
        }
    }

    private func apply() {
        guard let values else { return }
        editor.replaceAxisStops(axisTag: axis.tag, values: values)
        onComplete()
        dismiss()
    }
}

// MARK: - Change format sheet

struct ChangeAxisStopFormatSheet: View {
    @EnvironmentObject private var editor: EditorViewModel
    @Environment(\.dismiss) private var dismiss

    let axis: AxisDefinition
    let stop: AxisValue
    let onComplete: () -> Void

    @State private var statFormat: Int
    @State private var linkTargetID: String?

    init(axis: AxisDefinition, stop: AxisValue, onComplete: @escaping () -> Void) {
        self.axis = axis
        self.stop = stop
        self.onComplete = onComplete
        _statFormat = State(initialValue: stop.statFormat)
        if stop.statFormat == 3, let linkedValue = stop.linkedValue,
           let target = axis.values.first(where: { $0.id != stop.id && AxisCoordinate.valuesEqual($0.value, linkedValue) }) {
            _linkTargetID = State(initialValue: target.id)
        }
    }

    private var linkCandidates: [AxisValue] {
        axis.values.filter { $0.id != stop.id && $0.statFormat != 3 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpacing.sectionGap) {
            Text("Format · \(stop.name)")
                .font(StudioTypography.emphasis)

            Picker("STAT format", selection: $statFormat) {
                Text("Format 1 — static").tag(1)
                Text("Format 2 — range").tag(2)
                Text("Format 3 — linked").tag(3)
            }
            .pickerStyle(.menu)

            if statFormat == 3 {
                Picker("Link to", selection: Binding(
                    get: { linkTargetID ?? linkCandidates.first?.id },
                    set: { linkTargetID = $0 }
                )) {
                    ForEach(linkCandidates) { candidate in
                        Text(candidate.name).tag(Optional(candidate.id))
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    onComplete()
                    dismiss()
                }
                Button("Apply") {
                    apply()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(statFormat == 3 && linkTargetID == nil && linkCandidates.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 320)
    }

    private func apply() {
        editor.updateAxisStopStatFormat(
            axisTag: axis.tag,
            stopID: stop.id,
            format: statFormat,
            linkTargetStopID: statFormat == 3 ? linkTargetID : nil
        )
        onComplete()
        dismiss()
    }
}

// MARK: - Add naming axis

struct AddFileAxisSheet: View {
    @EnvironmentObject private var editor: EditorViewModel
    @Environment(\.dismiss) private var dismiss

    let onComplete: () -> Void

    private enum Kind: String, CaseIterable, Identifiable {
        case slope, width, optical, custom
        var id: String { rawValue }

        var title: String {
            switch self {
            case .slope: return "Slope (ital)"
            case .width: return "Width (wdth)"
            case .optical: return "Optical (opsz)"
            case .custom: return "Custom tag"
            }
        }

        var template: RegistrationAxisFactory.TemplateKind? {
            switch self {
            case .slope: return .slope
            case .width: return .width
            case .optical: return .optical
            case .custom: return nil
            }
        }

        var policyTitle: String {
            switch self {
            case .slope: return "Slope policy"
            case .width: return "Width policy"
            case .optical: return "Optical policy"
            case .custom: return "Custom tag policy"
            }
        }
    }

    @State private var kind: Kind = .slope
    @State private var tagText = "GRAD"
    @State private var nameText = ""
    @State private var valueText = "0"
    @State private var codeText = ""
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case tag, name, value, code
    }

    private var trimmedCode: String? {
        guard editor.isCodeNamingEnabled else { return nil }
        let t = codeText.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private var sanitizedTag: String {
        RegistrationAxisFactory.sanitizeAxisTag(tagText)
    }

    private var parsedValue: Double? {
        Double(valueText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var isItalicFile: Bool {
        guard let font = editor.selectedFont else { return false }
        return RegistrationAxisSupport.isItalicFile(font: font)
    }

    private var kindEnabled: Bool {
        switch kind {
        case .slope, .width, .optical:
            return kind.template.map { editor.canAddRegistrationTemplate($0) } ?? false
        case .custom:
            return true
        }
    }

    private var disabledReason: String? {
        guard let template = kind.template else { return nil }
        return editor.namingAxisBlockReason(for: template)
    }

    private var familyTagCollision: Bool {
        guard kind == .custom, !sanitizedTag.isEmpty, let fonts = editor.project?.fonts else {
            return false
        }
        return RegistrationAxisFactory.tagExistsInFamily(tag: sanitizedTag, fonts: fonts)
    }

    private var tagLengthInvalid: Bool {
        kind == .custom && !tagText.isEmpty && sanitizedTag.count != 4
    }

    private var previewStopName: String {
        switch kind {
        case .slope:
            return isItalicFile ? "Italic" : "Roman"
        case .width, .optical, .custom:
            let trimmed = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
            switch kind {
            case .width: return "Width"
            case .optical: return "Optical Size"
            case .custom: return sanitizedTag.isEmpty ? "Name" : sanitizedTag
            default: return "Name"
            }
        }
    }

    private var previewTag: String {
        switch kind {
        case .slope: return "ital"
        case .width: return "wdth"
        case .optical: return "opsz"
        case .custom: return sanitizedTag.isEmpty ? "····" : sanitizedTag
        }
    }

    private var previewValue: String {
        switch kind {
        case .slope:
            return isItalicFile ? "1" : "0"
        case .width, .optical, .custom:
            return valueText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "—"
                : valueText
        }
    }

    private var previewCode: String {
        switch kind {
        case .slope: return isItalicFile ? "1" : "0"
        case .width, .optical, .custom:
            return trimmedCode ?? "—"
        }
    }

    private var previewElidable: Bool {
        switch kind {
        case .slope: return !isItalicFile
        case .width, .optical, .custom: return false
        }
    }

    private var previewLinkedLabel: String? {
        guard kind == .slope else { return nil }
        return isItalicFile ? "0" : "1"
    }

    private var previewFmt: String {
        kind == .slope ? "F3" : "F1"
    }

    private var canAdd: Bool {
        guard kindEnabled else { return false }
        switch kind {
        case .slope:
            return true
        case .width, .optical:
            return parsedValue != nil
                && !nameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .custom:
            return sanitizedTag.count == 4
                && !familyTagCollision
                && !nameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && parsedValue != nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: StudioSpacing.sectionGap) {
            Text("Add naming axis")
                .font(StudioTypography.emphasis)

            Text("Naming axes label styles across files without joining the instance grid — no fvar scale, one stop per file.")
                .font(StudioTypography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Kind")
                    .font(StudioTypography.meta)
                    .foregroundStyle(.tertiary)
                kindTabs
                if let disabledReason, !kindEnabled {
                    Label(disabledReason, systemImage: "lock.fill")
                        .font(StudioTypography.meta)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if kindEnabled {
                fieldsRow
            } else {
                Text("Select an available kind to configure a tag and name.")
                    .font(StudioTypography.caption)
                    .foregroundStyle(.tertiary)
            }

            policyBox

            previewSection

            if familyTagCollision {
                Text("Tag “\(sanitizedTag)” is already used by another axis in this family.")
                    .font(StudioTypography.caption)
                    .foregroundStyle(.red)
            } else if tagLengthInvalid {
                Text("Tag must be exactly 4 characters (letters or digits).")
                    .font(StudioTypography.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    onComplete()
                    dismiss()
                }
                Button("Add Axis") {
                    addIfValid()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canAdd)
            }
        }
        .padding(20)
        .frame(width: 540)
        .onAppear {
            selectFirstAvailableKind()
            seedFields(for: kind)
        }
    }

    private var kindTabs: some View {
        HStack(spacing: 6) {
            ForEach(Kind.allCases) { option in
                let enabled = optionEnabled(option)
                let selected = kind == option
                Button {
                    kind = option
                    seedFields(for: option)
                } label: {
                    Text(option.title)
                        .font(StudioTypography.caption)
                        .fontWeight(selected ? .medium : .regular)
                        .foregroundStyle(tabForeground(enabled: enabled, selected: selected))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(tabBackground(enabled: enabled, selected: selected), in: RoundedRectangle(cornerRadius: 6))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(
                                    tabStroke(enabled: enabled, selected: selected),
                                    lineWidth: selected ? 1 : 0.5
                                )
                        }
                }
                .buttonStyle(.plain)
                .help(enabled ? option.title : (option.template.flatMap { editor.namingAxisBlockReason(for: $0) } ?? ""))
            }
        }
    }

    private func optionEnabled(_ option: Kind) -> Bool {
        switch option {
        case .slope, .width, .optical:
            return option.template.map { editor.canAddRegistrationTemplate($0) } ?? false
        case .custom:
            return true
        }
    }

    private func tabForeground(enabled: Bool, selected: Bool) -> Color {
        if !enabled {
            return selected ? .secondary.opacity(0.7) : .secondary.opacity(0.45)
        }
        if selected { return StudioColors.registrationForeground }
        return .primary.opacity(0.85)
    }

    private func tabBackground(enabled: Bool, selected: Bool) -> Color {
        if !enabled {
            return selected ? Color.primary.opacity(0.08) : Color.primary.opacity(0.04)
        }
        if selected { return StudioColors.registrationBackground }
        return Color.primary.opacity(0.06)
    }

    private func tabStroke(enabled: Bool, selected: Bool) -> Color {
        if !enabled {
            return selected ? Color.primary.opacity(0.18) : Color.primary.opacity(0.08)
        }
        if selected { return StudioColors.registrationStroke }
        return Color.primary.opacity(0.12)
    }

    @ViewBuilder
    private var fieldsRow: some View {
        switch kind {
        case .slope:
            EmptyView()
        case .width, .optical:
            HStack(spacing: 10) {
                StudioTextField(
                    placeholder: "Tag",
                    text: .constant(previewTag),
                    font: StudioTypography.monoMeta,
                    rowHeight: StudioFieldMetrics.bodyRowHeight,
                    filledForeground: StudioColors.registrationForeground.opacity(0.55)
                )
                .disabled(true)
                StudioTextField(
                    placeholder: "Display name",
                    text: $nameText,
                    rowHeight: StudioFieldMetrics.bodyRowHeight,
                    filledForeground: StudioColors.registrationForeground
                )
                .focused($focusedField, equals: .name)
                StudioTextField(
                    placeholder: "Value",
                    text: $valueText,
                    font: StudioTypography.monoMeta,
                    rowHeight: StudioFieldMetrics.bodyRowHeight,
                    filledForeground: StudioColors.axisValue
                )
                .frame(width: 72)
                .focused($focusedField, equals: .value)
                if editor.isCodeNamingEnabled {
                    StudioTextField(
                        placeholder: "Code",
                        text: $codeText,
                        font: StudioTypography.monoMeta,
                        rowHeight: StudioFieldMetrics.bodyRowHeight,
                        filledForeground: StudioColors.codeForeground
                    )
                    .frame(width: 56)
                    .focused($focusedField, equals: .code)
                    .help("Optional 1–2 character classification code (letters or digits)")
                }
            }
        case .custom:
            HStack(spacing: 10) {
                StudioTextField(
                    placeholder: "Tag",
                    text: $tagText,
                    font: StudioTypography.monoMeta,
                    rowHeight: StudioFieldMetrics.bodyRowHeight,
                    filledForeground: StudioColors.registrationForeground
                )
                .focused($focusedField, equals: .tag)
                StudioTextField(
                    placeholder: "Display name",
                    text: $nameText,
                    rowHeight: StudioFieldMetrics.bodyRowHeight,
                    filledForeground: StudioColors.registrationForeground
                )
                .focused($focusedField, equals: .name)
                StudioTextField(
                    placeholder: "Value",
                    text: $valueText,
                    font: StudioTypography.monoMeta,
                    rowHeight: StudioFieldMetrics.bodyRowHeight,
                    filledForeground: StudioColors.axisValue
                )
                .frame(width: 72)
                .focused($focusedField, equals: .value)
                if editor.isCodeNamingEnabled {
                    StudioTextField(
                        placeholder: "Code",
                        text: $codeText,
                        font: StudioTypography.monoMeta,
                        rowHeight: StudioFieldMetrics.bodyRowHeight,
                        filledForeground: StudioColors.codeForeground
                    )
                    .frame(width: 56)
                    .focused($focusedField, equals: .code)
                    .help("Optional 1–2 character classification code (letters or digits)")
                }
            }
        }
    }

    private var policyBox: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(kind.policyTitle)
                .font(StudioTypography.caption.weight(.medium))
                .foregroundStyle(kindEnabled ? StudioColors.registrationForeground : .secondary)
            Text(policyCopy)
                .font(StudioTypography.caption)
                .foregroundStyle(kindEnabled ? StudioColors.registrationForeground.opacity(0.9) : .secondary)
                .fixedSize(horizontal: false, vertical: true)
            if kindEnabled {
                Text("Elidable: \(previewElidable ? "yes — name drops when composing" : "no — name stays in the style string"). Naming order: inserts \(editor.namingOrderInsertHint(forNewTag: previewTag)).")
                    .font(StudioTypography.meta)
                    .foregroundStyle(StudioColors.registrationForeground.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (kindEnabled ? StudioColors.registrationBackground : Color.primary.opacity(0.04)),
            in: RoundedRectangle(cornerRadius: StudioRadius.row)
        )
        .overlay {
            RoundedRectangle(cornerRadius: StudioRadius.row)
                .strokeBorder(
                    kindEnabled ? StudioColors.registrationStroke : Color.primary.opacity(0.1),
                    lineWidth: 0.5
                )
        }
    }

    private var policyCopy: String {
        switch kind {
        case .slope:
            if !kindEnabled {
                return disabledReason
                    ?? "One Format 3 stop per file. This tag is already spoken for."
            }
            if isItalicFile {
                return "This file looks italic — you’ll get one Format 3 stop at 1 (Italic), linked to 0. The link is a convention pointer, not a second named stop on this file."
            }
            return "This file looks upright — you’ll get one Format 3 stop at 0 (Roman, elided), linked to 1. The link is a convention pointer, not a second named stop on this file."
        case .width:
            if !kindEnabled {
                return disabledReason
                    ?? "Adds wdth as a naming axis only when Width isn’t already an instance axis."
            }
            return "Adds wdth as a naming axis with an ordinary named stop for this file only — siblings don’t inherit this value. Use Add Stop on other files when you’re ready. Not a 0/1 linked pair."
        case .optical:
            if !kindEnabled {
                return disabledReason
                    ?? "Adds opsz as a naming axis only when Optical Size isn’t already an instance axis."
            }
            return "Adds opsz as a naming axis with an ordinary named stop for this file only — siblings don’t inherit this value. Tag is locked to opsz; set the display name and value that describe this file."
        case .custom:
            return "Must be exactly 4 characters. Uppercase reads as a registered-style tag; lowercase signals private-use. Checked against every file in this family. The stop is written only on this file — siblings stay untouched until you add a stop there."
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Axis tree preview")
                .font(StudioTypography.meta)
                .foregroundStyle(.tertiary)

            VStack(alignment: .leading, spacing: 8) {
                if !kindEnabled {
                    Text(disabledReason ?? "Already exists in the Axis Tree.")
                        .font(StudioTypography.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    HStack(spacing: 8) {
                        Text("N")
                            .font(StudioTypography.tag)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .foregroundStyle(StudioColors.registrationForeground)
                            .background(StudioColors.registrationBackground, in: RoundedRectangle(cornerRadius: StudioRadius.small))
                        Text(previewStopName)
                            .font(StudioTypography.bodyMedium)
                        Text("No fvar scale · this file")
                            .font(StudioTypography.meta)
                            .foregroundStyle(.tertiary)
                        Spacer(minLength: 0)
                        StudioTagPill(text: previewTag, compact: true, role: .registration)
                    }

                    HStack(spacing: 0) {
                        previewColumnHeader("Fmt", width: 36)
                        previewColumnHeader("Value", width: 52)
                        if editor.isCodeNamingEnabled {
                            previewColumnHeader("Code", width: 40)
                        }
                        previewColumnHeader("Name", width: nil)
                        previewColumnHeader("Elid", width: 40)
                    }

                    HStack(spacing: 0) {
                        Text(previewFmt)
                            .font(StudioTypography.tag.weight(.medium))
                            .foregroundStyle(previewFmt == "F3" ? StudioColors.statFormat3 : StudioColors.statFormat1)
                            .frame(width: 36, alignment: .leading)
                        Text(previewValue)
                            .font(StudioTypography.monoMeta)
                            .foregroundStyle(StudioColors.axisValue)
                            .frame(width: 52, alignment: .leading)
                        if editor.isCodeNamingEnabled {
                            Text(previewCode)
                                .font(StudioTypography.monoMeta)
                                .foregroundStyle(StudioColors.codeForeground)
                                .frame(width: 40, alignment: .leading)
                        }
                        HStack(spacing: 4) {
                            Text(previewStopName)
                                .font(StudioTypography.caption)
                            if let linked = previewLinkedLabel {
                                Image(systemName: "link")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                                Text(linked)
                                    .font(StudioTypography.meta)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: previewElidable ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 12))
                            .foregroundStyle(
                                previewElidable
                                    ? StudioColors.registrationForeground
                                    : Color.secondary.opacity(0.45)
                            )
                            .frame(width: 40, alignment: .center)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: StudioRadius.row))
            .overlay {
                RoundedRectangle(cornerRadius: StudioRadius.row)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
            }
        }
    }

    private func previewColumnHeader(_ title: String, width: CGFloat?) -> some View {
        Text(title)
            .font(StudioTypography.meta)
            .foregroundStyle(.tertiary)
            .frame(width: width, alignment: .leading)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
    }

    private func selectFirstAvailableKind() {
        if editor.canAddRegistrationTemplate(.slope) {
            kind = .slope
        } else if editor.canAddRegistrationTemplate(.width) {
            kind = .width
        } else if editor.canAddRegistrationTemplate(.optical) {
            kind = .optical
        } else {
            kind = .custom
        }
    }

    private func seedFields(for option: Kind) {
        switch option {
        case .slope:
            break
        case .width:
            nameText = "Normal"
            valueText = "100"
            focusedField = .name
        case .optical:
            nameText = "Display"
            valueText = "18"
            focusedField = .name
        case .custom:
            if tagText.isEmpty { tagText = "GRAD" }
            if nameText.isEmpty || nameText == "Normal" || nameText == "Display" {
                nameText = "Grade"
            }
            if valueText.isEmpty || valueText == "100" || valueText == "18" {
                valueText = "0"
            }
            focusedField = .tag
        }
    }

    private func addIfValid() {
        guard canAdd else { return }
        let ok: Bool
        switch kind {
        case .slope:
            ok = editor.addRegistrationTemplate(.slope)
        case .width:
            ok = editor.addRegistrationTemplate(
                .width,
                displayName: nameText,
                value: parsedValue,
                code: trimmedCode
            )
        case .optical:
            ok = editor.addRegistrationTemplate(
                .optical,
                displayName: nameText,
                value: parsedValue,
                code: trimmedCode
            )
        case .custom:
            ok = editor.addRegistrationAxis(
                tag: sanitizedTag,
                displayName: nameText,
                value: parsedValue ?? 0,
                elidable: false,
                code: trimmedCode
            )
        }
        guard ok else { return }
        onComplete()
        dismiss()
    }
}
