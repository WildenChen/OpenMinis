import SwiftUI
import UIKit
import WebKit

private let avatarShellLogger = AppLogger(category: "AvatarShell")

/// Fullscreen, immersive WKWebView host that renders the bundled SoulNest
/// avatar shell (`Resources/Avatar/index.html` + manifest + clips).
///
/// Mirrors `WebAppWebViewController`'s posture: black immersive canvas, no
/// status bar, and a navigation policy that keeps the page sandboxed to its
/// own bundle folder (file: inside the folder + about: only). Unlike the
/// WebApp host it ships with no JS bridge yet — the backend-to-avatar state
/// bridge (#12) will add the `WKScriptMessageHandler` seam on
/// `cfg.userContentController` when the external backend is wired up.
final class AvatarShellWebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private var webView: WKWebView!
    private var readAccessRoot: URL!

    init() {
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

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
