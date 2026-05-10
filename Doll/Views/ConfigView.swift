//
//  ConfigView.swift
//  Doll
//
//  Created by huikai on 2022/6/10.
//

import SwiftUI
import LaunchAtLogin
import Monitor
import KeyboardShortcuts

struct ConfigView: View {
    private static let intervalPresets: [Double] = [1, 2, 5, 10]

    @State private var failedToSetupObservers = false
    @State private var presentingPermissionGuidline = false
    @State private var items: [MonitoredApp] = []
    @State private var showingSetupView = false
    @State private var showAboutPage = false

    @State private var startAtLogin = false
    @State private var hideWhenAppNotRunning = AppSettings.hideWhenAppNotRunning
    @State private var hideWhenNothingComing = AppSettings.hideWhenNothingComing
    @State private var grayoutIconWhenNothingComing = AppSettings.grayoutIconWhenNothingComing
    @State private var showAlertInFullScreenMode = AppSettings.showAlertInFullScreenMode
    @State private var showAsRedBadge = AppSettings.showAsRedBadge
    @State private var showOnlyAppIcon = AppSettings.showOnlyAppIcon
    @State private var selectedInterval = ConfigView.intervalPresets.contains(AppSettings.badgeCheckInterval) ? String(format: "%.0f", AppSettings.badgeCheckInterval) : "custom"
    @State private var customIntervalText = String(format: "%.0f", AppSettings.badgeCheckInterval)

    var body: some View {
        NavigationView {
            VStack {
                if items.isEmpty {
                    Text("Add monitor guideline")
                        .font(.title)
                        .padding()
                        .frame(minWidth: 250)
                } else {
                    List {
                        ForEach(Array(items.enumerated()), id: \.element.id) { (itemIndex, item) in
                            NavigationLink {
                                let statusBar = MonitorEngine.shared.statusBars.first {
                                    $0.monitoredApp == item
                                }
                                MonitorConfigView(itemIndex: itemIndex, statusBar: statusBar, selectedApp: item)
                            } label: {
                                MonitoredAppItemView(appItem: item)
                            }
                        }
                    }.frame(minWidth: 250)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 12) {
                    LaunchAtLogin.Toggle {
                                Text("Launch at login")
                            }
                            .padding([.top])

                    Group {
                        Toggle("Hide icon if monitored app isn't running", isOn: $hideWhenAppNotRunning)
                            .disabled(showOnlyAppIcon)
                            .onChange(of: hideWhenAppNotRunning) { enabled in
                                AppSettings.hideWhenAppNotRunning = enabled
                            }
                        Toggle("Hide icons when there are no new notifications", isOn: $hideWhenNothingComing)
                            .disabled(showOnlyAppIcon)
                            .onChange(of: hideWhenNothingComing) { enabled in
                                AppSettings.hideWhenNothingComing = enabled
                            }
                        Toggle("Grayout icons when there are no new notifications", isOn: $grayoutIconWhenNothingComing)
                            .onChange(of: grayoutIconWhenNothingComing) { enabled in
                                AppSettings.grayoutIconWhenNothingComing = enabled
                                MonitorEngine.shared.statusBars.forEach {
                                    $0.refreshDisplayMode()
                                }
                            }
                        Toggle("Show notification on full screen mode", isOn: $showAlertInFullScreenMode)
                            .disabled(showOnlyAppIcon)
                            .onChange(of: showAlertInFullScreenMode) { enabled in
                                AppSettings.showAlertInFullScreenMode = enabled
                            }
                        Toggle("Show as red badge", isOn: $showAsRedBadge)
                            .disabled(showOnlyAppIcon)
                            .onChange(of: showAsRedBadge) { enabled in
                                AppSettings.showAsRedBadge = enabled
                                MonitorEngine.shared.statusBars.forEach {
                                    $0.refreshDisplayMode()
                                }
                            }
                    }
                    .fixedSize()
                    
                    Toggle("Show only app icon", isOn: $showOnlyAppIcon)
                            .onChange(of: showOnlyAppIcon) { enabled in
                                AppSettings.showOnlyAppIcon = enabled
                                MonitorEngine.shared.statusBars.forEach {
                                    $0.refreshDisplayMode()
                                }
                            }
                            .fixedSize()

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Badge check interval")
                            .fixedSize()

                        HStack {
                            Picker("", selection: $selectedInterval) {
                                ForEach(ConfigView.intervalPresets, id: \.self) { interval in
                                    Text("\(Int(interval))s").tag(String(format: "%.0f", interval))
                                }
                                Text("Custom").tag("custom")
                            }
                            .pickerStyle(.segmented)
                            .fixedSize()
                            .onChange(of: selectedInterval) { value in
                                if value == "custom" {
                                    applyCustomInterval()
                                } else if let interval = Double(value) {
                                    applyCheckInterval(interval)
                                }
                            }

                            if selectedInterval == "custom" {
                                TextField("Seconds", text: $customIntervalText)
                                    .frame(width: 70)
                                    .textFieldStyle(.roundedBorder)
                                    .onChange(of: customIntervalText) { _ in
                                        applyCustomInterval()
                                    }
                                Text("s")
                            }
                        }
                    }

                    Text("Hotkey to open this config window")
                        .fixedSize()
                    KeyboardShortcuts
                        .Recorder("", name: .toggleConfigWindow)
                }
                        .padding()

                HStack {
                    NavigationLink {
                        MonitorConfigView(isAddMode: true, itemIndex: nil, statusBar: nil)
                    } label: {
                        Image(systemName: "plus")
                    }

                    if failedToSetupObservers {
                        Button {
                            presentingPermissionGuidline = true
                        } label: {
                            Image(systemName: "eye.trianglebadge.exclamationmark")
                                .foregroundColor(Color.yellow)
                        }.sheet(isPresented: $presentingPermissionGuidline) {
                            VStack {
                                Text("Permission grant guideline")
                                    .font(.title)
                                    .padding()

                                HStack {
                                    Button("Open System Preferences") {
                                        presentingPermissionGuidline = false
                                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                                    }

                                    Button("OK") {
                                        presentingPermissionGuidline = false
                                    }
                                }
                            }.padding()
                        }
                    }

                    Spacer()

                    NavigationLink {
                        AboutView()
                    } label: {
                        Text("About")
                    }
                    Button("Quit") {
                        exit(0)
                    }
                }.padding()
            }
        }.onReceive(MonitorEngine.shared.$monitoredApps) { monitoredApps in
            items = monitoredApps
        }.onReceive(MonitorService.observerStatus) { attached in
            failedToSetupObservers = !attached
        }

    }

    private func applyCustomInterval() {
        guard let interval = Double(customIntervalText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return
        }

        applyCheckInterval(interval)
    }

    private func applyCheckInterval(_ interval: Double) {
        let clampedInterval = min(max(interval, 1), 60)
        AppSettings.badgeCheckInterval = clampedInterval
        MonitorService.updateCheckInterval(clampedInterval)

        let formattedInterval = String(format: "%.0f", clampedInterval)
        if customIntervalText != formattedInterval {
            customIntervalText = formattedInterval
        }
    }
}
