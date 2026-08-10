import SwiftUI
import UIKit
import WebKit

private let avatarShellLogger = AppLogger(category: "AvatarShell")

extension Notification.Name {
    /// Presentation-only bridge from the native chat lifecycle into the Avatar
    /// shell. It deliberately carries no backend/session/tool configuration.
    static let soulNestAvatarPresentation = Notification.Name("soulnest.avatar.presentation")
}

/// Tiny presentation contract shared by the chat provider and Avatar host.
/// All methods run on the main actor and only affect visual state/subtitles.
/// They cannot change backend routing, memory, tools or credentials.
@MainActor
enum SoulNestAvatarPresentation {
    static func thinking() {
        post(action: "state", value: "thinking")
    }

    static func talking(subtitle: String? = nil) {
        post(action: "state", value: "talk_soft")
        if let subtitle, !subtitle.isEmpty {
            post(action: "subtitle", value: subtitle)
        }
    }

    static func say(_ text: String) {
        guard !text.isEmpty else {
            idle()
            return
        }
        post(action: "say", value: text)
    }

    static func idle(clearSubtitle: Bool = true) {
        post(action: "state", value: "idle_01")
        if clearSubtitle {
            post(action: "clearSubtitle", value: nil)
        }
    }

    private static func post(action: String, value: String?) {
        var info: [String: Any] = ["action": action]
        if let value { info["value"] = value }
        NotificationCenter.default.post(
            name: .soulNestAvatarPresentation,
            object: nil,
            userInfo: info
        )
    }
}

/// Fullscreen, immersive WKWebView host that renders the bundled SoulNest
/// avatar shell (`Resources/Avatar/index.html` + manifest + clips).
///
/// Mirrors `WebAppWebViewController`'s posture: black immersive canvas, no
/// status bar, and a navigation policy that keeps the page sandboxed to its
/// own bundle folder (file: inside the folder + about: only). Native chat
/// lifecycle events are translated into calls on the existing
/// `window.SoulNestAvatar` presentation API; the bridge never exposes backend
/// secrets or native tool objects to JavaScript.
final class AvatarShellWebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private var webView: WKWebView!
    private var readAccessRoot: URL!
    private var pageReady = false
    private var pendingPresentation: [AnyHashable: Any]?

    init() {
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { [.bottom] }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let cfg = WKWebViewConfiguration()
        // No login cookies to keep — a fresh in-memory session is fine and
        // avoids persisting anything the avatar page writes.
        cfg.websiteDataStore = .default()
        cfg.suppressesIncrementalRendering = false
        // The shell drives itself with muted local <video> clips; allow
        // inline playback and autoplay so idle → thinking → talking switch
        // without any user tap.
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        if #available(iOS 14.0, *) {
            cfg.defaultWebpagePreferences.allowsContentJavaScript = true
        }

        let wv = WKWebView(frame: view.bounds, configuration: cfg)
        wv.translatesAutoresizingMaskIntoConstraints = false
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.isOpaque = false
        wv.backgroundColor = .black
        wv.scrollView.backgroundColor = .black
        wv.allowsBackForwardNavigationGestures = false
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        wv.scrollView.automaticallyAdjustsScrollIndicatorInsets = false
        view.addSubview(wv)
        NSLayoutConstraint.activate([
            wv.topAnchor.constraint(equalTo: view.topAnchor),
            wv.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            wv.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        webView = wv

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAvatarPresentation(_:)),
            name: .soulNestAvatarPresentation,
            object: nil
        )

        // Left-edge swipe — iOS-canonical "go back". Belt-and-braces escape
        // hatch alongside the floating close pill.
        let r = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(edgePanned(_:)))
        r.edges = .left
        view.addGestureRecognizer(r)

        installCloseButton()

        guard let folder = Bundle.main.url(forResource: nil, withExtension: nil, subdirectory: "Avatar"),
              let html = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Avatar") else {
            avatarShellLogger.error("Avatar bundle folder missing")
            return
        }
        readAccessRoot = folder
        avatarShellLogger.info("loading avatar shell html=\(html.lastPathComponent)")
        webView.loadFileURL(html, allowingReadAccessTo: folder)
    }

    @objc private func edgePanned(_ r: UIScreenEdgePanGestureRecognizer) {
        guard r.state == .recognized else { return }
        dismiss(animated: true)
    }

    @objc private func handleAvatarPresentation(_ notification: Notification) {
        guard let info = notification.userInfo else { return }
        guard pageReady else {
            pendingPresentation = info
            return
        }
        applyPresentation(info)
    }

    private func applyPresentation(_ info: [AnyHashable: Any]) {
        guard let action = info["action"] as? String else { return }
        let value = info["value"] as? String
        let js: String
        switch action {
        case "state":
            guard let value else { return }
            js = "window.SoulNestAvatar && SoulNestAvatar.setState(\(jsonStringLiteral(value)));"
        case "subtitle":
            guard let value else { return }
            js = "window.SoulNestAvatar && SoulNestAvatar.setSubtitle(\(jsonStringLiteral(value)));"
        case "say":
            guard let value else { return }
            js = "window.SoulNestAvatar && SoulNestAvatar.say(\(jsonStringLiteral(value)));"
        case "clearSubtitle":
            js = "window.SoulNestAvatar && SoulNestAvatar.clearSubtitle();"
        default:
            return
        }
        webView.evaluateJavaScript(js) { _, error in
            if let error {
                avatarShellLogger.warning("presentation JS failed action=\(action): \(error.localizedDescription)")
            }
        }
    }

    /// Encode a Swift string as a JavaScript string literal without manually
    /// escaping quotes/newlines. JSON's string syntax is valid JavaScript.
    private func jsonStringLiteral(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let json = String(data: data, encoding: .utf8),
              json.count >= 2 else { return "\"\"" }
        return String(json.dropFirst().dropLast())
    }

    /// Floating close pill in the top-left. The avatar shell owns its own
    /// bottom controls inside the page, so the native affordance stays a
    /// slim corner pill that doesn't collide with the subtitle/input area.
    private func installCloseButton() {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.layer.shadowColor = UIColor.black.cgColor
        container.layer.shadowOpacity = 0.3
        container.layer.shadowRadius = 10
        container.layer.shadowOffset = CGSize(width: 0, height: 3)

        let bg = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        bg.translatesAutoresizingMaskIntoConstraints = false
        bg.isUserInteractionEnabled = false
        bg.layer.cornerRadius = 20
        bg.layer.masksToBounds = true
        bg.layer.borderWidth = 0.5
        bg.layer.borderColor = UIColor.white.withAlphaComponent(0.18).cgColor

        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        let cfg = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        let glyph = UIImage(systemName: "xmark", withConfiguration: cfg)?
            .withTintColor(.white, renderingMode: .alwaysOriginal)
        button.setImage(glyph, for: .normal)
        button.accessibilityLabel = NSLocalizedString("Close", comment: "")
        button.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        container.addSubview(bg)
        container.addSubview(button)
        view.addSubview(container)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 40),
            container.heightAnchor.constraint(equalToConstant: 40),
            container.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            container.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 14),

            bg.topAnchor.constraint(equalTo: container.topAnchor),
            bg.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            bg.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bg.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            button.topAnchor.constraint(equalTo: container.topAnchor),
            button.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            button.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "about" {
            decisionHandler(.allow)
            return
        }
        if scheme == "file", let root = readAccessRoot {
            let target = url.standardizedFileURL.path
            let base = root.standardizedFileURL.path
            if target.hasPrefix(base + "/") || target == base || target.hasPrefix(base) {
                decisionHandler(.allow)
                return
            }
            avatarShellLogger.warning("blocking file:// nav outside scope target=\(target)")
            decisionHandler(.cancel)
            return
        }
        avatarShellLogger.info("blocking external nav scheme=\(scheme) url=\(url.absoluteString.prefix(120))")
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pageReady = true
        if let pendingPresentation {
            self.pendingPresentation = nil
            applyPresentation(pendingPresentation)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        avatarShellLogger.error("didFail: \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        avatarShellLogger.error("didFailProvisional: \(error.localizedDescription)")
    }

    // MARK: - WKUIDelegate

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        return nil
    }
}

// MARK: - SwiftUI Bridge

/// SwiftUI wrapper presented full-screen from the app root, mirroring
/// `WebAppWebViewScreen`.
struct AvatarShellWebViewScreen: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> AvatarShellWebViewController {
        AvatarShellWebViewController()
    }

    func updateUIViewController(_ uiViewController: AvatarShellWebViewController, context: Context) {
        // No-op — the controller manages its own state.
    }
}
