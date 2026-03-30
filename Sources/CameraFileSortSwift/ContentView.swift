import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var datePatternDraft: String = ""

    private let accentTint = Color(red: 0.16, green: 0.43, blue: 0.68)

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

            HStack(alignment: .top, spacing: 0) {
                sidebar
                    .frame(minWidth: 320, idealWidth: 340, maxWidth: 360)

                Divider()

                detailView
                    .frame(minWidth: 600, idealWidth: 620, maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .fixedSize(horizontal: false, vertical: true)
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
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Camera Media Transfer Wizard")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                Text(appState.isImporting ? "Processing \(appState.processedCount) of \(appState.totalCount)" : appState.statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(.bar)
    }

    var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Sources")
                    .font(.headline)

                HStack(spacing: 8) {
                    Button("Refresh") { appState.refreshCards() }
                    Button("Choose Source…") { appState.chooseSource() }
                }

                Button("Scan Media") { appState.scanMediaCounts() }
                    .buttonStyle(.borderedProminent)

                if appState.detectedCards.isEmpty {
                    Text("No camera cards detected in /Volumes.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(appState.detectedCards, id: \.path) { card in
                                sourceRow(for: card)
                            }
                        }
                    }
                    .frame(height: 180)
                }
            }
            .padding(16)
            .background(sidebarCardBackground)

            VStack(alignment: .leading, spacing: 12) {
                Text("Summary")
                    .font(.headline)

                summaryLine(label: "Cards", value: "\(appState.detectedCards.count)")
                summaryLine(label: "Selected", value: "\(appState.selectedCards.count)")
                summaryLine(label: "Media", value: appState.settings.mediaSelection.displayName)
                summaryLine(label: "Scan", value: appState.lastScanSummary)
            }
            .padding(16)
            .background(sidebarCardBackground)

            progressCard
        }
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    func sourceRow(for card: URL) -> some View {
        let isSelected = appState.selectedCards.contains(card)
        return Button {
            toggleSelection(for: card)
        } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? accentTint.opacity(0.14) : Color.secondary.opacity(0.08))
                    .frame(width: 34, height: 34)
                    .overlay {
                        Image(systemName: "externaldrive.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(isSelected ? accentTint : .secondary)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(card.lastPathComponent)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(sourceSubtitle(for: card))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isSelected ? accentTint : .secondary.opacity(0.8))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? accentTint.opacity(0.09) : Color.primary.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? accentTint.opacity(0.28) : Color.black.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    func sourceSubtitle(for card: URL) -> String {
        if card.deletingLastPathComponent().path == "/Volumes" {
            return card.path
        }
        return "Mounted at \(card.path)"
    }

    var detailView: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsCard
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    var settingsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 18) {
                Text("Import Setup")
                    .font(.title3.weight(.semibold))

                VStack(alignment: .leading, spacing: 12) {
                    Text("Destination")
                        .font(.headline)

                    HStack(spacing: 8) {
                        TextField("Browse or paste a destination folder", text: $appState.settings.destinationRoot)
                            .textFieldStyle(.roundedBorder)
                        Button("Choose…") { appState.chooseDestination() }
                        Button(appState.isCurrentDefaultRoot ? "Default set" : "Set default") {
                            appState.setDefaultRoot()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            appState.isCurrentDefaultRoot ||
                            appState.settings.destinationRoot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                    }
                    .onChange(of: appState.settings.destinationRoot) { _ in
                        appState.destinationRootDidChange()
                    }

                    HStack(spacing: 10) {
                        statusPill(
                            title: appState.destinationValid ? "Destination OK" : "Invalid path",
                            tint: appState.destinationValid ? .green : .red
                        )
                        statusPill(
                            title: appState.hasDefaultRoot ? "Saved default" : "No default",
                            tint: appState.hasDefaultRoot ? accentTint : .secondary
                        )
                        Spacer()
                        Button("Clear default") {
                            appState.resetDestinationDefaults()
                        }
                        .buttonStyle(.borderless)
                    }

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
                                .frame(maxWidth: 160, alignment: .leading)
                                .onChange(of: datePatternDraft) { newValue in
                                    let cleaned = sanitizeDatePattern(newValue)
                                    if cleaned != datePatternDraft {
                                        datePatternDraft = cleaned
                                    }
                                    appState.settings.importDateFormat = cleaned
                                }
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

                    Text(appState.destinationPreview().isEmpty ? "Choose a destination folder to see the transfer layout." : appState.destinationPreview())
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Transfer")
                        .font(.headline)

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

                    Toggle("Eject cards after transfer", isOn: $appState.settings.ejectAfter)

                    Divider()

                    HStack {
                        Button("Reset transfer defaults") {
                            appState.resetTransferDefaults()
                        }
                        .buttonStyle(.borderless)

                        Spacer()

                        Button("Open Destination") {
                            appState.openDestination()
                        }
                        .buttonStyle(.bordered)
                        .disabled(!appState.canOpenDestination || appState.isImporting)

                        Button(appState.isImporting ? "Importing..." : "Import") {
                            appState.saveSettings()
                            appState.startImport()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(appState.isImporting)
                    }
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 18)
            .padding(.horizontal, 18)
            .padding(.bottom, 12)
        }
    }

    var progressCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                Text("Progress")
                    .font(.title3.weight(.semibold))

                HStack(spacing: 10) {
                    progressStat(title: "Status", value: statusHeadline)
                    progressStat(title: "Done", value: "\(appState.processedCount)/\(appState.totalCount)")
                    progressStat(title: "Card", value: appState.currentCardName.isEmpty ? "—" : appState.currentCardName)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Card progress")
                        Spacer()
                        Text(progressLabel(for: appState.cardProgress))
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: appState.cardProgress)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Overall progress")
                        Spacer()
                        Text(progressLabel(for: appState.overallProgress))
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: appState.overallProgress)
                }

                Text(appState.currentFileName.isEmpty ? "No file in progress" : appState.currentFileName)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
        }
        .frame(maxWidth: .infinity)
    }

    var sidebarCardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(nsColor: .windowBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
    }

    func summaryLine(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    func statusPill(title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12), in: Capsule())
    }

    func formRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .frame(width: 62, alignment: .leading)
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

    func progressLabel(for value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}
