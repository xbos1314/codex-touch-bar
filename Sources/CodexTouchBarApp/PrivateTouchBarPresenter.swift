import AppKit
import CodexTouchBarCore
import Darwin

@MainActor
enum PrivateTouchBarPresentationStatus: Equatable {
    case inactive
    case active
    case unavailable(String)
    case failed(String)

    func menuText(language: DisplayLanguage) -> String {
        switch self {
        case .inactive:
            return language == .english ? "Official host window" : "官方宿主窗口"
        case .active:
            return language == .english ? "Control Strip entry active" : "Control Strip 入口已启用"
        case .unavailable(let reason):
            return language == .english ? "Always-on unavailable: \(reason)" : "常驻不可用：\(reason)"
        case .failed(let reason):
            return language == .english ? "Always-on failed: \(reason)" : "常驻失败：\(reason)"
        }
    }
}

@MainActor
final class PrivateTouchBarPresenter {
    private let presentSelector = NSSelectorFromString("presentSystemModalTouchBar:systemTrayItemIdentifier:")
    private let dismissSelector = NSSelectorFromString("dismissSystemModalTouchBar:")
    private let addSystemTrayItemSelector = NSSelectorFromString("addSystemTrayItem:")
    private let removeSystemTrayItemSelector = NSSelectorFromString("removeSystemTrayItem:")
    private let dfrFoundationPath = "/System/Library/PrivateFrameworks/DFRFoundation.framework"
    private let systemTrayIdentifier: NSString
    private let touchBarItemIdentifier: NSTouchBarItem.Identifier
    private var presentedTouchBar: NSTouchBar?
    private var registeredTouchBar: NSTouchBar?
    private var trayItem: NSTouchBarItem?

    private(set) var status: PrivateTouchBarPresentationStatus = .inactive

    init(systemTrayIdentifier: String = "com.local.codex-touch-bar.always-on") {
        self.systemTrayIdentifier = systemTrayIdentifier as NSString
        self.touchBarItemIdentifier = NSTouchBarItem.Identifier(systemTrayIdentifier)
    }

    @discardableResult
    func present(_ touchBar: NSTouchBar) -> PrivateTouchBarPresentationStatus {
        switch PrivateTouchBarPresentationPolicy.surface {
        case .systemModal:
            return presentSystemModal(touchBar)
        case .controlStripEntry:
            return registerControlStripEntry(for: touchBar)
        }
    }

    func dismiss() {
        if let touchBar = presentedTouchBar {
            dismiss(touchBar)
            presentedTouchBar = nil
        }
        removeControlStripEntry()
        status = .inactive
    }

    @objc private func showTouchBarFromControlStrip(_ sender: Any?) {
        expandFromControlStrip()
    }

    private func expandFromControlStrip() {
        guard let touchBar = registeredTouchBar else { return }
        _ = presentSystemModal(touchBar)
    }

    private func presentSystemModal(_ touchBar: NSTouchBar) -> PrivateTouchBarPresentationStatus {
        let touchBarClass: AnyObject = NSTouchBar.self as AnyObject
        guard touchBarClass.responds(to: presentSelector),
              touchBarClass.responds(to: dismissSelector) else {
            status = .unavailable("missing private NSTouchBar selectors")
            return status
        }

        if let current = presentedTouchBar, current !== touchBar {
            dismiss(current)
        }

        applyCloseButtonPolicy()
        let result = touchBarClass.perform(presentSelector, with: touchBar, with: systemTrayIdentifier)
        guard result != nil else {
            status = .failed("present returned nil")
            return status
        }

        reapplyCloseButtonPolicyAfterPresent()
        presentedTouchBar = touchBar
        status = .active
        return status
    }

    private func registerControlStripEntry(for touchBar: NSTouchBar) -> PrivateTouchBarPresentationStatus {
        let itemClass: AnyObject = NSTouchBarItem.self as AnyObject
        guard itemClass.responds(to: addSystemTrayItemSelector),
              itemClass.responds(to: removeSystemTrayItemSelector),
              controlStripPresenceSymbol() != nil else {
            status = .unavailable("missing Control Strip private APIs")
            return status
        }

        if trayItem == nil {
            let item = NSCustomTouchBarItem(identifier: touchBarItemIdentifier)
            item.view = ControlStripEntryButton(title: "Codex") { [weak self] in
                self?.expandFromControlStrip()
            }
            _ = itemClass.perform(addSystemTrayItemSelector, with: item)
            trayItem = item
        }

        setControlStripPresence(true)
        registeredTouchBar = touchBar
        status = .active
        return status
    }

    private func dismiss(_ touchBar: NSTouchBar) {
        let touchBarClass: AnyObject = NSTouchBar.self as AnyObject
        guard touchBarClass.responds(to: dismissSelector) else { return }
        _ = touchBarClass.perform(dismissSelector, with: touchBar)
    }

    private func removeControlStripEntry() {
        setControlStripPresence(false)
        if let trayItem {
            let itemClass: AnyObject = NSTouchBarItem.self as AnyObject
            if itemClass.responds(to: removeSystemTrayItemSelector) {
                _ = itemClass.perform(removeSystemTrayItemSelector, with: trayItem)
            }
        }
        trayItem = nil
        registeredTouchBar = nil
    }

    private func applyCloseButtonPolicy() {
        guard let symbol = closeButtonSymbol() else { return }
        typealias CloseBoxFunction = @convention(c) (Bool) -> Void
        let setCloseBoxVisible = unsafeBitCast(symbol, to: CloseBoxFunction.self)
        setCloseBoxVisible(PrivateTouchBarPresentationPolicy.showsCloseButton)
    }

    private func reapplyCloseButtonPolicyAfterPresent() {
        guard PrivateTouchBarPresentationPolicy.reappliesCloseButtonPolicyAfterPresent else { return }
        applyCloseButtonPolicy()
        DispatchQueue.main.async { [weak self] in
            self?.applyCloseButtonPolicy()
        }
    }

    private func closeButtonSymbol() -> UnsafeMutableRawPointer? {
        _ = Bundle(path: dfrFoundationPath)?.load()
        return dlsym(UnsafeMutableRawPointer(bitPattern: -2), "DFRSystemModalShowsCloseBoxWhenFrontMost")
    }

    private func setControlStripPresence(_ present: Bool) {
        guard let symbol = controlStripPresenceSymbol() else { return }
        typealias PresenceFunction = @convention(c) (NSString, Bool) -> Void
        let setPresence = unsafeBitCast(symbol, to: PresenceFunction.self)
        setPresence(systemTrayIdentifier, present)
    }

    private func controlStripPresenceSymbol() -> UnsafeMutableRawPointer? {
        _ = Bundle(path: dfrFoundationPath)?.load()
        return dlsym(UnsafeMutableRawPointer(bitPattern: -2), "DFRElementSetControlStripPresenceForIdentifier")
    }
}

@MainActor
private final class ControlStripEntryButton: NSButton {
    private let onPress: () -> Void

    init(title: String, onPress: @escaping () -> Void) {
        self.onPress = onPress
        super.init(frame: NSRect(x: 0, y: 0, width: 64, height: 30))

        self.title = title
        self.target = self
        self.action = #selector(performPress(_:))
        self.isBordered = PrivateTouchBarPresentationPolicy.controlStripEntryIsBordered
        self.bezelStyle = .regularSquare
        self.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        self.alignment = .center
        self.attributedTitle = Self.attributedTitle(title)
        wantsLayer = true
        layer?.cornerRadius = CGFloat(PrivateTouchBarPresentationPolicy.controlStripEntryCornerRadius)
        layer?.masksToBounds = true

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 64),
            heightAnchor.constraint(equalToConstant: 30)
        ])

        updateBackground()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 64, height: 30)
    }

    override var isHighlighted: Bool {
        didSet {
            updateBackground()
        }
    }

    @objc private func performPress(_ sender: Any?) {
        onPress()
    }

    private func updateBackground() {
        guard PrivateTouchBarPresentationPolicy.controlStripEntryDrawsBackground else {
            layer?.backgroundColor = NSColor.clear.cgColor
            return
        }

        let white: CGFloat = isHighlighted ? 0.38 : 0.30
        layer?.backgroundColor = NSColor(calibratedWhite: white, alpha: 1).cgColor
    }

    private static func attributedTitle(_ title: String) -> NSAttributedString {
        NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
        )
    }
}
