import Combine
import SwiftUI
import UIKit
import WaoTyping

final class KeyboardViewController: UIInputViewController {
    private let model = KeyboardModel()
    private var host: UIHostingController<KeyboardView>?
    private var heightFollowsMode: AnyCancellable?
    private var emojiFaceFollowsPage: AnyCancellable?

    override func loadView() {
        view = ClickingInputView(frame: .zero, inputViewStyle: .keyboard)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        model.hostInsert = { [weak self] in
            self?.textDocumentProxy.insertText($0)
            self?.model.refreshContext()
        }
        model.hostDelete = { [weak self] in
            self?.textDocumentProxy.deleteBackward()
            self?.model.refreshContext()
        }
        model.adjustCursor = { [weak self] in self?.textDocumentProxy.adjustTextPosition(byCharacterOffset: $0) }
        model.readCursorText = { [weak self] in
            CursorText(before: self?.textDocumentProxy.documentContextBeforeInput ?? "",
                       after: self?.textDocumentProxy.documentContextAfterInput ?? "")
        }
        model.readContext = { [weak self] in self?.textDocumentProxy.documentContextBeforeInput ?? "" }
        model.openApp = { [weak self] in self?.openContainingApp() ?? false }
        model.screenWidth = UIScreen.main.bounds.width

        let host = UIHostingController(rootView: KeyboardView(model: model, globe: { [weak self] in self?.globeButton() }))
        // iOS hands a touch on a fully transparent part of a keyboard to the app behind it, so the touch surface
        // and the suggestion bar, which draw nothing of their own, would never see one.
        host.view.backgroundColor = UIColor(white: 0, alpha: 0.001)
        host.sizingOptions = []
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        self.host = host

        // As tall as the system keyboard on this screen, so switching keyboards does not move the host app; the
        // emoji page, search included, is taller, as Apple's is. `mode` publishes before it changes, so the new
        // height and the new page land in the same layout pass.
        let width = UIScreen.main.bounds.width
        let height = view.heightAnchor.constraint(equalToConstant: KeyMetrics(width: width).height)
        height.isActive = true
        heightFollowsMode = model.$mode
            .map { $0.isEmojiPage ? EmojiMetrics(width: width).height : KeyMetrics(width: width).height }
            .removeDuplicates()
            .sink { height.constant = $0 }
        emojiFaceFollowsPage = model.$mode
            .map(\.isEmojiPage)
            .removeDuplicates()
            .filter { !$0 }
            .sink { _ in EmojiFace.drop() }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.hasFullAccess = hasFullAccess
        KeyFeedback.shared.refresh(hasFullAccess: hasFullAccess)
        model.activate()
        model.refreshContext()
    }

    /// The cursor moved, or the host changed the text.
    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        model.hostChanged()
    }

    /// `needsInputModeSwitchKey` is only reliable once layout starts; on devices where iOS draws its own globe
    /// below the keyboard it is false.
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        if model.showsGlobe != needsInputModeSwitchKey { model.showsGlobe = needsInputModeSwitchKey }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        model.deactivate()
    }

    private func globeButton() -> UIView {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "globe"), for: .normal)
        button.tintColor = .label
        button.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        return button
    }

    /// Keyboards cannot call `UIApplication.shared`; walking the responder chain to the app object is the
    /// remaining way to open our own app, and it needs Full Access.
    private func openContainingApp() -> Bool {
        guard let url = URL(string: "wao://session") else { return false }
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        typealias OpenURL = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
        var responder: UIResponder? = self
        while let current = responder {
            if current is UIApplication, current.responds(to: selector) {
                let open = unsafeBitCast(current.method(for: selector), to: OpenURL.self)
                open(current, selector, url as NSURL, NSDictionary(), nil)
                return true
            }
            responder = current.next
        }
        return false
    }
}
