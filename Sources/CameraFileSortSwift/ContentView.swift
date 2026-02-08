import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var datePatternDraft: String = ""
    
    private func sanitizeDatePattern(_ input: String) -> String {
        let allowed = Set("dmyDMY-_")
        let filtered = input.filter { allowed.contains($0) }
        return filtered.replacingOccurrences(of: "m", with: "M")
            .replacingOccurrences(of: "d", with: "d")
            .replacingOccurrences(of: "y", with: "y")
    }

    var body: some View {
        VStack(spacing: 10) {
            headerView
            cardsView
            settingsView
                .frame(maxWidth: .infinity, alignment: .leading)
            actionRow
            progressView
        }
        .padding(14)
        .onAppear {
            _ = appState.validateDestination()
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
            Text("Camera Media Transfer Wizard")
                .font(.title)
                .fontWeight(.semibold)
            Spacer()
        }
    }

    var cardsView: some View {
        GroupBox(label: Text("Cards")) {
            VStack(alignment: .leading, spacing: 8) {
                List {
                    if appState.detectedCards.isEmpty {
                        Text("No camera cards detected in /Volumes.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(appState.detectedCards, id: \.path) { card in
                            Text(card.path)
                        }
                    }
                }
                .frame(height: 80)

                HStack {
                    Button("Refresh") { appState.refreshCards() }
                    Button("Scan Media") { appState.scanMediaCounts() }
                    Spacer()
                    Text("Selected: \(appState.selectedCards.count)")
                        .foregroundStyle(.secondary)
                }
                Text(appState.lastScanSummary)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .padding(6)
        }
    }

    var settingsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            GroupBox(label: HStack {
                Text("Destination")
                Spacer()
                Button("Reset to Default") { appState.resetDestinationDefaults() }
            }) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Target Destination")
                            .frame(width: 110, alignment: .leading)
                        TextField("Destination root", text: $appState.settings.destinationRoot)
                        Button("Choose…") { appState.chooseDestination() }
                        Button(appState.hasDefaultRoot ? "Default set" : "Set default") {
                            appState.setDefaultRoot()
                        }
                        .disabled(appState.hasDefaultRoot)
                    }
                    .onChange(of: appState.settings.destinationRoot) { _ in
                        _ = appState.validateDestination()
                    }
                HStack {
                    Text("Status")
                        .frame(width: 110, alignment: .leading)
                    Text(appState.destinationValid ? "OK" : "Invalid path")
                        .foregroundColor(appState.destinationValid ? .secondary : .red)
                }

                HStack {
                    Text("Location")
                        .frame(width: 110, alignment: .leading)
                    Picker("", selection: $appState.settings.destinationMode) {
                        ForEach(DestinationMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                HStack {
                    Text("Date source")
                        .frame(width: 110, alignment: .leading)
                    Picker("", selection: $appState.settings.dateSource) {
                        ForEach(DateSource.allCases) { source in
                            Text(source.displayName).tag(source)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                if appState.settings.dateSource != .none {
                    HStack {
                        Text("Date pattern")
                            .frame(width: 110, alignment: .leading)
                        TextField("MMddyyyy", text: $datePatternDraft)
                            .onChange(of: datePatternDraft) { newValue in
                                let cleaned = sanitizeDatePattern(newValue)
                                if cleaned != datePatternDraft {
                                    datePatternDraft = cleaned
                                }
                                appState.settings.importDateFormat = cleaned
                            }
                    }
                }

                    Text(appState.destinationPreview())
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .padding(.leading, 110)

                    if appState.settings.destinationMode == .custom {
                        HStack {
                            Text("Photo folder")
                                .frame(width: 110, alignment: .leading)
                            TextField("photo", text: $appState.settings.photoFolderName)
                        }
                        HStack {
                            Text("Video folder")
                                .frame(width: 110, alignment: .leading)
                            TextField("video", text: $appState.settings.videoFolderName)
                        }
                    }
                    if appState.settings.destinationMode == .same {
                        HStack {
                            Text("Folder name")
                                .frame(width: 110, alignment: .leading)
                            TextField("media", text: $appState.settings.sameFolderName)
                        }
                    }
                }
                .padding(6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            GroupBox(label: HStack {
                Text("Transfer")
                Spacer()
                Button("Reset to Default") { appState.resetTransferDefaults() }
            }) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Media")
                            .frame(width: 110, alignment: .leading)
                        Picker("", selection: $appState.settings.mediaSelection) {
                            ForEach(MediaSelection.allCases) { selection in
                                Text(selection.displayName).tag(selection)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    HStack {
                        Text("Action")
                            .frame(width: 110, alignment: .leading)
                        Picker("", selection: $appState.settings.action) {
                            ForEach(TransferAction.allCases) { action in
                                Text(action.rawValue.capitalized).tag(action)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    HStack {
                        Text("Duplicates")
                            .frame(width: 110, alignment: .leading)
                        Picker("", selection: $appState.settings.duplicatePolicy) {
                            ForEach(DuplicatePolicy.allCases) { policy in
                                Text(policy.displayName).tag(policy)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    Toggle("Eject after transfer", isOn: $appState.settings.ejectAfter)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var actionRow: some View {
        HStack {
            Text(appState.isImporting ? "Importing \(appState.processedCount)/\(appState.totalCount)" : appState.statusMessage)
                .foregroundStyle(.secondary)
            Spacer()
            Button(appState.isImporting ? "Importing..." : "Import") {
                appState.saveSettings()
                appState.startImport()
            }
            .disabled(appState.isImporting)
        }
    }

    var progressView: some View {
        GroupBox(label: Text("Progress")) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Card")
                        .frame(width: 80, alignment: .leading)
                    Text(appState.currentCardName.isEmpty ? "—" : appState.currentCardName)
                        .font(.system(size: 12, design: .monospaced))
                }
                ProgressView(value: appState.cardProgress)

                HStack {
                    Text("File")
                        .frame(width: 80, alignment: .leading)
                    Text(appState.currentFileName.isEmpty ? "—" : appState.currentFileName)
                        .font(.system(size: 12, design: .monospaced))
                }
                ProgressView(value: appState.overallProgress)
            }
            .padding(6)
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
    }
}
