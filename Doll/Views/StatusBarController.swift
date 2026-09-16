import AppKit
import Monitor
import SwiftUI

let defaultIconSize: CGFloat = 20
let defaultIcon = #imageLiteral(resourceName: "DefaultStatusBarIcon")

class StatusBarController {
    private var statusBar: NSStatusBar!
    private var isDark = false
    private var latestBadgeText = ""
    private var latestMessageCount = 0

    private var giantBadgeController = GiantBadgeViewController()
    private var giantBadgePanel = NSPanel(contentRect: NSRect(origin: .zero, size: defaultWindowSize),
                              styleMask: [.nonactivatingPanel],
                              backing: .buffered, defer: false)
    private var lastTimeShowingGiantBadge = Date()
    private var notificationPanel: NSPanel?

    public var statusItem: NSStatusItem!
    public var monitoredApp: MonitoredApp? {
        didSet {
            refreshIcon()
        }
    }
    private var monitoredAppIcon: NSImage?

    init() {
        setupStatusBar()
    }

    func setupStatusBar(icon: NSImage? = nil) {
        statusBar = .system
        statusItem = statusBar.statusItem(withLength: defaultIconSize)
        if let statusBarButton = statusItem.button {
            statusBarButton.sendAction(on: [.leftMouseUp, .rightMouseUp])
            statusBarButton.image = icon ?? defaultIcon
            statusBarButton.image?.size = NSSize(width: defaultIconSize, height: defaultIconSize)
            statusBarButton.image?.isTemplate = false
            statusBarButton.imagePosition = .imageLeft
            statusBarButton.action = #selector(onIconClicked(sender:))
            statusBarButton.target = self
            statusBarButton.toolTip = NSLocalizedString("Hold option key ⌥ and click to config", comment: "")
        }

        giantBadgePanel.isOpaque = false
        giantBadgePanel.hasShadow = false
        giantBadgePanel.backgroundColor = NSColor.clear
    }

    func refreshIcon() {
        monitoredAppIcon = Storage.appIcon(for: monitoredApp?.bundleId ?? "")

        if(AppSettings.isIconMask(for: monitoredApp?.appName ?? "") && isDark) {
            monitoredAppIcon = monitoredAppIcon?.invert()
        }

        updateBadgeText(latestBadgeText, force: true)
    }

    @objc func onIconClicked(sender: AnyObject) {
        hideGiantBadge()

        let noAppSelected = statusItem.button?.image == defaultIcon
        let isOptionKeyHolding = NSEvent.modifierFlags.contains(.option)
        let isRightClick = NSApp.currentEvent?.isRightClick == true

        if noAppSelected || isOptionKeyHolding || isRightClick {
            MonitorEngine.shared.showConfigWindow()
        } else if let monitoredAppName = monitoredApp?.appName,
                  let monitoredAppBundleId = monitoredApp?.bundleId {
            let appRunning = MonitorService.isMonitoredAppRunning(bundleIdentifier: monitoredAppBundleId)
            if !appRunning {
                guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: monitoredAppBundleId) else {
                    return
                }

                NSWorkspace.shared.open(appURL)
            } else {
                if NSWorkspace.shared.frontmostApplication?.bundleIdentifier == monitoredAppBundleId {
                    // Hide the app
                    NSWorkspace.shared.frontmostApplication?.hide()
                } else {
                    // Send the app window to front most
                    MonitorService.openMonitoredApp(appName: monitoredAppName)
                }
            }
        }
    }

    func monitorApp(app: MonitoredApp) {
        monitoredApp = app

        guard let appFullPath = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleId)?.absoluteURL.path else {
            return
        }

        guard let targetBundle = Bundle(path: appFullPath) else {
            return
        }

        let appName = app.appName
        statusItem.autosaveName = "Doll_\(app.bundleId)"
        updateBadgeText(nil)

        guard let monitoredAppIcon = monitoredAppIcon else {
            return
        }
        updateBadgeIcon(icon: monitoredAppIcon, size: CGSize(width: defaultIconSize, height: defaultIconSize))

        MonitorService.observe(appName: appName) { [weak self] badge in
            let appRunning = MonitorService.isMonitoredAppRunning(bundleIdentifier: targetBundle.bundleIdentifier ?? "")
            let appIsNotRunningAndIconShouldBeHidden = AppSettings.hideWhenAppNotRunning && !appRunning
            let badgeIsEmptyAndIconShouldBeHidden = AppSettings.hideWhenNothingComing && (badge.isNil || badge?.isEmpty == true)

            if appIsNotRunningAndIconShouldBeHidden || badgeIsEmptyAndIconShouldBeHidden {
                self?.hideStatusBar()
            } else {
                let currentIsDark = self?.statusItem.button?.effectiveAppearance.name.rawValue.lowercased().contains("dark") ?? false
                if(self?.isDark != currentIsDark) {
                    self?.isDark = currentIsDark
                    self?.refreshIcon()
                }

                self?.updateBadgeText(badge)
            }

            self?.repositionGiantBadge()
        }
    }

    func hideStatusBar() {
        statusItem.isVisible = false
    }

    func updateBadgeText(_ text: String?, force: Bool = false) {
        statusItem.isVisible = true

        guard !AppSettings.showOnlyAppIcon else {
            latestBadgeText = text ?? ""
            refreshAppIcon()
            return
        }

        guard force || statusItem.button?.title != text else {
            return
        }

        let textWidth = (text ?? "")
            .width(withConstrainedHeight: defaultIconSize, font: .systemFont(ofSize: 14))
        statusItem.length = defaultIconSize + textWidth

        // New notification comes in
        let newText = text ?? ""

        if newText.isEmpty {
            hideGiantBadge()
        }

        guard let monitoredAppIcon = monitoredAppIcon else {
            return
        }

        if AppSettings.showAsRedBadge {
            let defaultIcon = monitoredAppIcon.addBadgeToImage(drawText: newText)
            let adjustedIcon = (newText.isEmpty && AppSettings.grayoutIconWhenNothingComing) ? (defaultIcon.grayOut() ?? defaultIcon) : defaultIcon
            updateBadgeIcon(icon: adjustedIcon)
            statusItem.length = defaultIconSize
            statusItem.button?.title = ""
        } else {
            let defaultIcon = monitoredAppIcon
            let adjustedIcon = (newText.isEmpty && AppSettings.grayoutIconWhenNothingComing) ? (defaultIcon.grayOut() ?? defaultIcon) : defaultIcon
            updateBadgeIcon(icon: adjustedIcon)
            statusItem.length = defaultIconSize + textWidth
            updateBadgeIcon(icon: adjustedIcon, size: CGSize(width: defaultIconSize, height: defaultIconSize))
            statusItem.button?.title = newText
        }

        let newMessageCount = Int(newText) ?? 0
        if latestBadgeText != newText {
            if AppSettings.showAlertInFullScreenMode,
               !newText.isEmpty,
               Int(newText) == nil || newMessageCount > latestMessageCount {
                tryShowTheNewNotificationPanel(newText: newText)
            }

            let frontmostAppIsMonitoredApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == monitoredApp?.bundleId
            if !frontmostAppIsMonitoredApp, AppSettings.isGiantBadgeEnabled(for: monitoredApp?.appName ?? "") {
                // Don't show giant badge when message count is decreasing
                if newMessageCount >= latestMessageCount {
                    tryShowGiantBadge(text)
                } else {
                    hideGiantBadge()
                }
            } else {
                hideGiantBadge()
            }
        }

        latestBadgeText = newText
        latestMessageCount = newMessageCount
    }

    func refreshDisplayMode() {
        if AppSettings.showOnlyAppIcon {
            refreshAppIcon()
        } else {
            updateBadgeText(latestBadgeText, force: true)
        }
    }

    func refreshAppIcon() {
        guard let monitoredAppIcon else { return }
        let adjustedIcon = (latestBadgeText.isEmpty && AppSettings.grayoutIconWhenNothingComing) ? (monitoredAppIcon.grayOut() ?? monitoredAppIcon) : monitoredAppIcon
        statusItem.length = defaultIconSize
        statusItem.button?.title = ""
        updateBadgeIcon(icon: adjustedIcon, size: CGSize(width: defaultIconSize, height: defaultIconSize))
    }

    func updateBadgeIcon(icon: NSImage?, size: CGSize? = nil) {
        statusItem.button?.image = icon
        if let iconSize = size ?? icon?.size {
            statusItem.button?.image?.size = iconSize
        }
    }

    func tryShowGiantBadge(_ text: String?) {
        let now = Date()
        if !giantBadgePanel.isVisible || now.timeIntervalSince(lastTimeShowingGiantBadge) >= 3 {
            lastTimeShowingGiantBadge = now
            let currentActiveWindowIsFullScreen = Utils.currentActiveWindowIsFullScreen

            if giantBadgePanel.contentViewController != nil {
                giantBadgeController.animationFlag.toggle()
            } else {
                let giantBadgeView = GiantBadgeView(controller: giantBadgeController) { [weak self] in
                    guard let self = self else { return }
                    self.onIconClicked(sender: self)
                }
                giantBadgePanel.contentViewController = NSHostingController(rootView: giantBadgeView)
                giantBadgePanel.setContentSize(giantBadgeSize)
            }

            repositionGiantBadge()
            giantBadgePanel.level = .popUpMenu
            giantBadgePanel.setIsVisible(true)
            giantBadgePanel.orderFrontRegardless()
        }
    }

    func repositionGiantBadge() {
        guard let activeScreen = NSScreen.screenWithMouse,
           let iconFrame = statusItem.button?.window?.frame else {
            return
        }

        var menubarOffset: CGFloat = 0
        if Utils.currentActiveWindowIsFullScreen {
            // In mac with notch, the menubar didn't affect window's size
            menubarOffset = activeScreen.hasTopNotchDesign ? 0 : Utils.menubarHeight
        }

        giantBadgePanel.setFrameOrigin(NSPoint(x: iconFrame.midX - giantBadgeSize.width / 2, y: activeScreen.visibleFrame.maxY - giantBadgeSize.height + menubarOffset + giantBadgeYOffset))
    }

    func hideGiantBadge() {
        giantBadgePanel.setIsVisible(false)
    }

    func tryShowTheNewNotificationPanel(newText: String, force: Bool = false) {
        guard (force || Utils.currentActiveWindowIsFullScreen),
              let window = statusItem.button?.window,
              let screen = window.screen else { return }

        notificationPanel?.close()
        let panel = createNotificationPanel(newText: newText)
        let iconFrame = window.frame
        let horizontalMargin: CGFloat = 8
        let centeredX = iconFrame.midX - panel.frame.width / 2
        let x = min(max(centeredX, screen.visibleFrame.minX + horizontalMargin),
                    screen.visibleFrame.maxX - panel.frame.width - horizontalMargin)
        let menuBarBottom = min(screen.visibleFrame.maxY,
                                screen.frame.maxY - screen.safeAreaInsets.top)
        panel.setFrameOrigin(NSPoint(x: x, y: menuBarBottom - panel.frame.height - 6))
        notificationPanel = panel
        panel.orderFrontRegardless()

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self, weak panel] in
            guard self?.notificationPanel === panel else { return }
            panel?.close()
            self?.notificationPanel = nil
        }
    }

    func destroy() {
        if let monitoredApp = monitoredApp {
            MonitorService.unObserve(appName: monitoredApp.appName)
            MonitorEngine.shared.unMonitor(app: monitoredApp)
            statusBar.removeStatusItem(statusItem)
            AppSettings.toggleGiantBadge(for: monitoredApp.appName, value: false)
        }
    }

    private func createNotificationPanel(newText: String) -> NSPanel {
        let textWidth = newText
                .width(withConstrainedHeight: defaultIconSize, font: .systemFont(ofSize: 14))
        let horizonPadding: CGFloat = 32
        let verticalPadding: CGFloat = 16
        let panelSize = NSSize(width: defaultIconSize + textWidth + horizonPadding,
                               height: defaultIconSize + verticalPadding)
        let panel = NSPanel(contentRect: NSRect(origin: .zero,
                                                size: panelSize),
                            styleMask: [.nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.becomesKeyOnlyIfNeeded = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        let targetApp = monitoredApp
        let view = NotificationView(icon: monitoredAppIcon ?? defaultIcon, badgeText: newText) {
            if let monitoredAppName = targetApp?.appName {
                MonitorService.openMonitoredApp(appName: monitoredAppName)
            }
        }
        panel.contentViewController = NSHostingController(rootView: view)
        panel.setContentSize(panelSize)

        return panel
    }
}

extension String {
    func width(withConstrainedHeight height: CGFloat, font: NSFont) -> CGFloat {
        let constraintRect = CGSize(width: .greatestFiniteMagnitude, height: height)
        let boundingBox = self.boundingRect(with: constraintRect, options: .usesLineFragmentOrigin, attributes: [NSAttributedString.Key.font: font], context: nil)

        return ceil(boundingBox.width)
    }
}

extension NSScreen {
    static var screenWithMouse: NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        let screens = NSScreen.screens
        let screenWithMouse = (screens.first {
            NSMouseInRect(mouseLocation, $0.frame, false)
        })

        return screenWithMouse
    }
    var hasTopNotchDesign: Bool {
        guard #available(macOS 12, *) else { return false }
        return safeAreaInsets.top != 0
    }
}
