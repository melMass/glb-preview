import Cocoa
import QuickLookUI
import WebKit
import os.log

private let log = OSLog(subsystem: "com.laurie.GLBPreview.PreviewExtension", category: "viewer")

// WKUserContentController retains its message handler strongly; a weak wrapper
// breaks the controller → handler → viewController → webView → config cycle.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?
    init(_ delegate: WKScriptMessageHandler) { self.delegate = delegate }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(controller, didReceive: message)
    }
}

class PreviewViewController: NSViewController, QLPreviewingController, WKNavigationDelegate, WKScriptMessageHandler {

    private var webView: WKWebView!
    private var pendingBase64: String?
    private var continuation: CheckedContinuation<Void, Error>?

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let msg = body["msg"] as? String else { return }
        switch body["level"] as? String {
        case "error": os_log("%{public}@", log: log, type: .error, msg)
        case "warn": os_log("%{public}@", log: log, type: .default, msg)
        default: os_log("%{public}@", log: log, type: .info, msg)
        }
    }

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.userContentController.add(WeakScriptMessageHandler(self), name: "log")

        let consoleBridge = """
        (function() {
            function send(level, args) {
                const msg = Array.from(args).map(a => {
                    try { return typeof a === 'object' ? JSON.stringify(a) : String(a); }
                    catch { return String(a); }
                }).join(' ');
                window.webkit?.messageHandlers?.log?.postMessage({ level, msg });
            }
            for (const level of ['log', 'info', 'warn', 'error']) {
                const orig = console[level];
                console[level] = function() { send(level, arguments); orig.apply(console, arguments); };
            }
            window.addEventListener('error', (e) => send('error', [`${e.message} @ ${e.filename}:${e.lineno}`]));
            window.addEventListener('unhandledrejection', (e) => send('error', [`Unhandled rejection: ${e.reason}`]));
        })();
        """
        config.userContentController.addUserScript(
            WKUserScript(source: consoleBridge, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        )

        webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = self
        self.view = webView
    }

    func preparePreviewOfFile(at url: URL) async throws {
        guard let htmlURL = Bundle.main.url(forResource: "viewer", withExtension: "html") else {
            return
        }

        let glbData = try Data(contentsOf: url)
        pendingBase64 = glbData.base64EncodedString()

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            self.continuation = cont
            webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let base64 = pendingBase64 else {
            continuation?.resume()
            continuation = nil
            return
        }
        pendingBase64 = nil

        let js = """
        (function() {
            const binary = atob('\(base64)');
            const bytes = new Uint8Array(binary.length);
            for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
            const blob = new Blob([bytes], { type: 'model/gltf-binary' });
            const url = URL.createObjectURL(blob);
            document.getElementById('viewer').src = url;
        })();
        """

        webView.evaluateJavaScript(js) { [weak self] _, _ in
            self?.continuation?.resume()
            self?.continuation = nil
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
