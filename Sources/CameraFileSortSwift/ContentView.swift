import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var datePatternDraft: String = ""

    private let accentTint = Color(red: 0.16, green: 0.43, blue: 0.68)
    private let panelRadius: CGFloat = 8
    private let surfaceTint = Color(red: 0.95, green: 0.97, blue: 0.98)

    private func sanitizeDatePattern(_ input: String) -> String {
        let allowed = Set("dmyDMY-_")
        let filtered = input.filter { allowed.contains($0) }
        return filtered.replacingOccurrences(of: "m", with: "M")
            .replacingOccurrences(of: "d", with: "d")
            .replacingOccurrences(of: "y", with: "y")
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView

            GeometryReader { proxy in
                let compact = proxy.size.width < 980
                let sidebarWidth = min(max(proxy.size.width * 0.28, 260), 320)
                let runPanelWidth = min(max(proxy.size.width * 0.24, 260), 320)

                if compact {
                    VStack(spacing: 0) {
                        HStack(alignment: .top, spacing: 0) {
                            workflowSection(title: "Sources", systemImage: "externaldrive") {
                                sidebar
                            }
                                .frame(width: sidebarWidth)

                            Divider()

                            workflowSection(title: "Destination", systemImage: "folder") {
                                detailView
                            }
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }

                        Divider()

                        compactTransferBar
                    }
                } else {
                    HStack(alignment: .top, spacing: 0) {
                        workflowSection(title: "Sources", systemImage: "externaldrive") {
                            sidebar
                        }
                            .frame(width: sidebarWidth)

                        Divider()

                        workflowSection(title: "Destination", systemImage: "folder") {
                            detailView
                        }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                        Divider()

                        workflowSection(title: "Run", systemImage: "play.circle") {
                            transferPanel
                        }
                            .frame(width: runPanelWidth)
                    }
                }
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(accentTint)
        .onAppear {
            _ = appState.validateDestination(allowCreatablePath: true)
            datePatternDraft = appState.settings.importDateFormat
        }
        .onChange(of: appState.settings.importDateFormat) { newValue in
            if datePatternDraft != newValue {
                datePatternDraft = newValue
            }
        }
        .alert(
            item: Binding<AppAlert?>(
                get: { appState.alert?.buttons.isEmpty == true ? appState.alert : nil },
                set: { _ in appState.alert = nil }
            )
        ) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .confirmationDialog(
            appState.alert?.title ?? "",
            isPresented: Binding<Bool>(
                get: { appState.alert?.buttons.isEmpty == false },
                set: { newValue in
                    if !newValue {
                        appState.alert = nil
                        appState.isImporting = false
                        appState.statusMessage = "Ready"
                    }
                }
            ),
            actions: {
                if let alert = appState.alert {
                    ForEach(alert.buttons, id: \.title) { button in
                        Button(button.title) { alert.onSelect?(button.policy) }
                    }
                    Button("Cancel", role: .cancel) {
                        appState.alert = nil
                        appState.isImporting = false
                        appState.statusMessage = "Ready"
                    }
                }
            },
            message: {
                if let alert = appState.alert {
                    Text(alert.message)
                }
            }
        )
    }
}

private extension ContentView {
    var headerView: some View {
        HStack(spacing: 14) {
            Image(systemName: "camera.aperture")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(accentTint)
                .frame(width: 30, height: 30)
                .background(accentTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text("Camera Media Importer")
                    .font(.system(size: 18, weight: .semibold))
                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                appState.saveSettings()
                appState.startImport()
            } label: {
                Label(appState.isImporting ? "Importing" : "Import", systemImage: "arrow.down.doc.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(importButtonDisabled)
            .help(importDisabledReason)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.bar)
    }

    var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Button {
                    appState.refreshCards()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(appState.isImporting)
                .help("Refresh mounted sources")

                Button {
                    appState.chooseSource()
                } label: {
                    Label("Choose", systemImage: "folder.badge.plus")
                }
                .disabled(appState.isImporting)
                .help("Choose a source folder or drive")
            }
            .labelStyle(.iconOnly)

            Button {
                appState.scanMediaCounts()
            } label: {
                Label("Scan Media", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(appState.selectedCards.isEmpty || appState.isImporting)

            if appState.detectedCards.isEmpty {
                emptySourcesView
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(appState.detectedCards, id: \.path) { card in
                            sourceRow(for: card)
                        }
                    }
                    .padding(.vertical, 1)
                }
                .frame(minHeight: 180, maxHeight: .infinity)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                summaryLine(label: "Available", value: "\(appState.detectedCards.count)")
                summaryLine(label: "Selected", value: "\(appState.selectedCards.count)")
                summaryLine(label: "Media", value: appState.settings.mediaSelection.displayName)
                summaryLine(label: "Last scan", value: appState.lastScanSummary)
            }
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    var emptySourcesView: some View {
        VStack(spacing: 10) {
            Image(systemName: "externaldrive.badge.questionmark")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(.secondary)
            Text("No camera cards detected")
                .font(.subheadline.weight(.semibold))
            Text("Mounted camera volumes and manually chosen folders will appear here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .padding(14)
        .background(panelFill, in: RoundedRectangle(cornerRadius: panelRadius, style: .continuous))
        .overlay(panelStroke)
    }

    func sourceRow(for card: URL) -> some View {
        let isSelected = appState.selectedCards.contains(card)
        return Button {
            toggleSelection(for: card)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "externaldrive.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? accentTint : .secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        (isSelected ? accentTint.opacity(0.12) : Color.secondary.opacity(0.08)),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(card.lastPathComponent)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(sourceSubtitle(for: card))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? accentTint : .secondary.opacity(0.75))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(
                isSelected ? accentTint.opacity(0.08) : Color(nsColor: .windowBackgroundColor),
                in: RoundedRectangle(cornerRadius: panelRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: panelRadius, style: .continuous)
                    .stroke(isSelected ? accentTint.opacity(0.35) : Color.black.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(appState.isImporting)
    }

    func sourceSubtitle(for card: URL) -> String {
        if card.deletingLastPathComponent().path == "/Volumes" {
            return card.path
        }
        return "Mounted at \(card.path)"
    }

    var detailView: some View {
        ViewThatFits(in: .vertical) {
            detailContent

            ScrollView {
                detailContent
            }
        }
    }

    var detailContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            destinationSection
                .disabled(appState.isImporting)
            organizationSection
                .disabled(appState.isImporting)
            outputPreviewSection
            transferSettingsSection
                .disabled(appState.isImporting)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    var destinationSection: some View {
        setupSection(title: "Destination", systemImage: "folder") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    TextField("Browse or paste a destination folder", text: $appState.settings.destinationRoot)
                        .textFieldStyle(.roundedBorder)

                    Button("Choose...") { appState.chooseDestination() }

                    Button(appState.isCurrentDefaultRoot ? "Default set" : "Set default") {
                        appState.setDefaultRoot()
                    }
                    .buttonStyle(.bordered)
                    .disabled(
                        appState.isCurrentDefaultRoot ||
                        appState.settings.destinationRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
                .onChange(of: appState.settings.destinationRoot) { _ in
                    appState.destinationRootDidChange()
                }

                HStack(spacing: 8) {
                    statusBadge(
                        title: appState.destinationValid ? "Destination OK" : "Invalid path",
                        tint: appState.destinationValid ? .green : .red
                    )
                    statusBadge(
                        title: appState.hasDefaultRoot ? "Saved default" : "No default",
                        tint: appState.hasDefaultRoot ? accentTint : Color.secondary
                    )

                    Spacer()

                    Button("Clear default") {
                        appState.resetDestinationDefaults()
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    var organizationSection: some View {
        setupSection(title: "Organization", systemImage: "rectangle.split.2x1") {
            VStack(alignment: .leading, spacing: 12) {
                formRow(title: "Layout") {
                    Picker("", selection: $appState.settings.destinationMode) {
                        ForEach(DestinationMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                formRow(title: "Date") {
                    Picker("", selection: $appState.settings.dateSource) {
                        ForEach(DateSource.allCases) { source in
                            Text(source.displayName).tag(source)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if appState.settings.dateSource != .none {
                    formRow(title: "Pattern") {
                        TextField("MMddyyyy", text: $datePatternDraft)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 160, alignment: .leading)
                            .onChange(of: datePatternDraft) { newValue in
                                let cleaned = sanitizeDatePattern(newValue)
                                if cleaned != datePatternDraft {
                                    datePatternDraft = cleaned
                                }
                                appState.settings.importDateFormat = cleaned
                            }

                        Text(appState.importDatePreview())
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                if appState.settings.destinationMode == .custom {
                    HStack(spacing: 12) {
                        formRow(title: "Photo") {
                            TextField("photo", text: $appState.settings.photoFolderName)
                                .textFieldStyle(.roundedBorder)
                        }
                        formRow(title: "Video") {
                            TextField("video", text: $appState.settings.videoFolderName)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }

                if appState.settings.destinationMode == .same {
                    formRow(title: "Folder") {
                        TextField("media", text: $appState.settings.sameFolderName)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
        }
    }

    var outputPreviewSection: some View {
        setupSection(title: "Output Preview", systemImage: "arrow.triangle.branch") {
            VStack(alignment: .leading, spacing: 8) {
                if appState.settings.destinationRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Choose a destination folder to preview the transfer layout.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(panelFill, in: RoundedRectangle(cornerRadius: panelRadius, style: .continuous))
                } else {
                    ForEach(destinationPreviewLines, id: \.self) { line in
                        HStack(spacing: 8) {
                            Image(systemName: "folder.fill")
                                .foregroundStyle(accentTint)
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(panelFill, in: RoundedRectangle(cornerRadius: panelRadius, style: .continuous))
                        .overlay(panelStroke)
                    }
                }
            }
        }
    }

    var transferSettingsSection: some View {
        setupSection(title: "Transfer", systemImage: "arrow.left.arrow.right") {
            VStack(alignment: .leading, spacing: 12) {
                formRow(title: "Media") {
                    Picker("", selection: $appState.settings.mediaSelection) {
                        ForEach(MediaSelection.allCases) { selection in
                            Text(selection.displayName).tag(selection)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                formRow(title: "Action") {
                    Picker("", selection: $appState.settings.action) {
                        ForEach(TransferAction.allCases) { action in
                            Text(action.rawValue.capitalized).tag(action)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                formRow(title: "Duplicates") {
                    Picker("", selection: $appState.settings.duplicatePolicy) {
                        ForEach(DuplicatePolicy.allCases) { policy in
                            Text(policy.displayName).tag(policy)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                HStack {
                    Toggle("Eject cards after transfer", isOn: $appState.settings.ejectAfter)
                    Spacer()
                    Button("Reset transfer defaults") {
                        appState.resetTransferDefaults()
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    var transferPanel: some View {
        ViewThatFits(in: .vertical) {
            transferPanelContent(pinActionsToBottom: true)

            ScrollView {
                transferPanelContent(pinActionsToBottom: false)
            }
        }
    }

    func transferPanelContent(pinActionsToBottom: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                progressStat(title: "Status", value: statusHeadline)
                progressStat(title: "Files", value: appState.totalCount > 0 ? "\(appState.processedCount) / \(appState.totalCount)" : "Not started")
                progressStat(title: "Card", value: appState.currentCardName.isEmpty ? "None" : appState.currentCardName)
            }

            Divider()

            progressBlock(title: "Current card", value: appState.cardProgress)
            progressBlock(title: "Overall", value: appState.overallProgress)

            VStack(alignment: .leading, spacing: 6) {
                Text("Current file")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(appState.currentFileName.isEmpty ? "No file in progress" : appState.currentFileName)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)
            }

            if pinActionsToBottom {
                Spacer(minLength: 12)
            } else {
                Divider()
            }

            runActions
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: pinActionsToBottom ? .infinity : nil, alignment: .topLeading)
    }

    var runActions: some View {
        VStack(spacing: 10) {
            Button {
                appState.saveSettings()
                appState.startImport()
            } label: {
                Label(appState.isImporting ? "Importing..." : "Import Selected Media", systemImage: "arrow.down.doc.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(importButtonDisabled)
            .help(importDisabledReason)

            Button {
                appState.openDestination()
            } label: {
                Label("Open Destination", systemImage: "arrow.up.forward.app")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!canOpenDestination)
        }
    }

    var compactTransferBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(statusHeadline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(statusTint)
                Text(compactRunDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(minWidth: 160, maxWidth: 260, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Overall")
                    Spacer()
                    Text(progressLabel(for: appState.overallProgress))
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                ProgressView(value: appState.overallProgress)
            }
            .frame(maxWidth: .infinity)

            Button {
                appState.openDestination()
            } label: {
                Label("Open Destination", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.bordered)
            .disabled(!canOpenDestination)

            Button {
                appState.saveSettings()
                appState.startImport()
            } label: {
                Label(appState.isImporting ? "Importing" : "Import", systemImage: "arrow.down.doc.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(importButtonDisabled)
            .help(importDisabledReason)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.bar)
    }

    func workflowSection<Content: View>(title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accentTint)
                    .frame(width: 18)
                Text(title)
                    .font(.headline)

                Spacer()

                if title == "Sources" {
                    statusDot
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(sectionHeaderFill)

            Divider()

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(sectionFill)
    }

    func setupSection<Content: View>(title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title, systemImage: systemImage)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(panelFill, in: RoundedRectangle(cornerRadius: panelRadius, style: .continuous))
        .overlay(panelStroke)
    }

    func sectionHeader(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accentTint)
                .frame(width: 18)
            Text(title)
                .font(.headline)
        }
    }

    func summaryLine(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.subheadline)
    }

    func progressStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(panelFill, in: RoundedRectangle(cornerRadius: panelRadius, style: .continuous))
        .overlay(panelStroke)
    }

    func progressBlock(title: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                Text(progressLabel(for: value))
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            ProgressView(value: value)
        }
    }

    func statusBadge(title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
    }

    var statusDot: some View {
        Circle()
            .fill(statusTint)
            .frame(width: 8, height: 8)
            .help(statusHeadline)
    }

    func formRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)
            content()
        }
    }

    func toggleSelection(for card: URL) {
        if appState.selectedCards.contains(card) {
            appState.selectedCards.remove(card)
        } else {
            appState.selectedCards.insert(card)
        }
    }

    var statusHeadline: String {
        if appState.isImporting {
            return "Importing"
        }
        if appState.processedCount > 0 && appState.processedCount == appState.totalCount {
            return "Complete"
        }
        return "Ready"
    }

    var headerSubtitle: String {
        if appState.isImporting {
            return "Processing \(appState.processedCount) of \(appState.totalCount)"
        }
        let selected = appState.selectedCards.count
        let sourceText = selected == 1 ? "1 source selected" : "\(selected) sources selected"
        return "\(sourceText) • \(appState.settings.mediaSelection.displayName)"
    }

    var compactRunDetail: String {
        if appState.isImporting {
            return appState.currentFileName.isEmpty ? "Processing \(appState.processedCount) of \(appState.totalCount)" : appState.currentFileName
        }
        if appState.totalCount > 0 {
            return "\(appState.processedCount) of \(appState.totalCount) files"
        }
        return appState.statusMessage
    }

    var statusTint: Color {
        if appState.isImporting {
            return accentTint
        }
        if statusHeadline == "Complete" {
            return .green
        }
        return .secondary
    }

    var importButtonDisabled: Bool {
        appState.isImporting || appState.selectedCards.isEmpty || !appState.destinationValid
    }

    var canOpenDestination: Bool {
        !appState.isImporting &&
            appState.destinationValid &&
            !appState.settings.destinationRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var importDisabledReason: String {
        if appState.isImporting {
            return "Import is already running"
        }
        if appState.selectedCards.isEmpty {
            return "Select at least one source"
        }
        if !appState.destinationValid {
            return "Choose a valid destination"
        }
        return "Start importing selected media"
    }

    var destinationPreviewLines: [String] {
        let preview = appState.destinationPreview()
        guard !preview.isEmpty else { return [] }
        return preview.components(separatedBy: "  and  ")
    }

    var panelFill: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    var sectionFill: Color {
        Color(nsColor: .controlBackgroundColor).opacity(0.72)
    }

    var sectionHeaderFill: Color {
        surfaceTint.opacity(0.55)
    }

    var panelStroke: some View {
        RoundedRectangle(cornerRadius: panelRadius, style: .continuous)
            .stroke(Color.black.opacity(0.08), lineWidth: 1)
    }

    func progressLabel(for value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}
