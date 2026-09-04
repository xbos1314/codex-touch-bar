import AppKit

@MainActor
final class StatusWindowController: NSWindowController {
    private let touchBarController: TouchBarController

    init(touchBarController: TouchBarController) {
        self.touchBarController = touchBarController
        let viewController = StatusViewController(touchBarController: touchBarController)
        let window = NSWindow(contentViewController: viewController)
        window.title = "Codex Touch Bar"
        window.setContentSize(NSSize(width: 360, height: 120))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func showAndActivate() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        if let contentView = window?.contentView {
            window?.makeFirstResponder(contentView)
        }
    }
}

@MainActor
private final class StatusViewController: NSViewController {
    private let touchBarController: TouchBarController

    init(touchBarController: TouchBarController) {
        self.touchBarController = touchBarController
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let label = NSTextField(labelWithString: "Codex Touch Bar is running.")
        label.alignment = .center
        let view = TouchBarHostView(touchBarController: touchBarController, frame: NSRect(x: 0, y: 0, width: 360, height: 120))
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        self.view = view
    }

    override func makeTouchBar() -> NSTouchBar? {
        touchBarController.touchBar
    }
}

@MainActor
private final class TouchBarHostView: NSView {
    private let touchBarController: TouchBarController

    init(touchBarController: TouchBarController, frame: NSRect) {
        self.touchBarController = touchBarController
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var acceptsFirstResponder: Bool { true }

    override func makeTouchBar() -> NSTouchBar? {
        touchBarController.touchBar
    }
}
