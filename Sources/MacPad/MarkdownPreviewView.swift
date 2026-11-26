import AppKit
import WebKit

/// Rendered Markdown in a web view. Read-only (split preview) or editable (WYSIWYG "Rendered" mode).
/// Content updates are injected with JavaScript so scroll position and caret survive.
final class MarkdownPreviewView: NSView {
    let editable: Bool
    private let webView: WKWebView
    private let messageProxy = MessageProxy()
    private var isReady = false
    private var isLoading = false
    private var pendingBody: String?
    private var scrollFraction: CGFloat = 0
    var baseURL: URL?

    /// Called (debounced) with the document converted back to Markdown after edits in editable mode.
    var onMarkdownEdited: ((String) -> Void)?

    init(frame: NSRect, editable: Bool) {
        self.editable = editable
        let config = WKWebViewConfiguration()
        config.userContentController.add(messageProxy, name: "macpad")
        webView = WKWebView(frame: NSRect(origin: .zero, size: frame.size), configuration: config)
        super.init(frame: frame)
        webView.autoresizingMask = [.width, .height]
        addSubview(webView)
        messageProxy.onMessage = { [weak self] body in self?.handle(body) }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "macpad")
    }

    /// Renders markdown. `reload` forces a full page load (e.g. when the base folder changed).
    func update(markdown: String, reload: Bool = false) {
        let body = Markdown.toHTML(markdown, baseURL: baseURL)
        if reload || (!isReady && !isLoading) {
            isReady = false
            isLoading = true
            pendingBody = nil
            webView.loadHTMLString(Markdown.page(body: body, interactive: true, editable: editable), baseURL: baseURL)
        } else if isLoading {
            pendingBody = body
        } else {
            webView.evaluateJavaScript("macpadSetContent(\(Markdown.jsonString(body)));", completionHandler: nil)
        }
    }

    /// Scrolls to the same relative position as the editor (0…1). Only used by the split preview.
    func scroll(toFraction fraction: CGFloat) {
        scrollFraction = min(1, max(0, fraction))
        guard isReady, !editable else { return }
        let js = "window.scrollTo(0, (document.documentElement.scrollHeight - window.innerHeight) * \(Double(scrollFraction)));"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    func focusEditor() {
        window?.makeFirstResponder(webView)
        if isReady && editable { webView.evaluateJavaScript("macpadFocus();", completionHandler: nil) }
    }

    var containsFirstResponder: Bool {
        guard let responder = window?.firstResponder as? NSView else { return false }
        return responder === webView || responder.isDescendant(of: webView)
    }

    /// Runs a formatting command in editable mode (bold, italic, h1, ul, link, undo…).
    func runCommand(_ name: String) {
        guard editable, isReady else { return }
        webView.evaluateJavaScript("macpadCmd(\(Markdown.jsonString(name)));", completionHandler: nil)
    }

    /// Gets any edits not yet delivered by the debounce, then calls `completion`.
    func flushEdits(_ completion: @escaping () -> Void) {
        guard editable, isReady else { completion(); return }
        webView.evaluateJavaScript("macpadFlush();") { [weak self] result, _ in
            if let markdown = result as? String { self?.onMarkdownEdited?(markdown) }
            completion()
        }
    }

    func find(_ text: String, backwards: Bool, caseSensitive: Bool, wraps: Bool, completion: @escaping (Bool) -> Void) {
        let config = WKFindConfiguration()
        config.backwards = backwards
        config.caseSensitive = caseSensitive
        config.wraps = wraps
        webView.find(text, configuration: config) { result in completion(result.matchFound) }
    }

    // MARK: - Messages from the page

    private func handle(_ body: Any) {
        guard let dict = body as? [String: Any], let type = dict["type"] as? String else { return }
        switch type {
        case "ready":
            isLoading = false
            isReady = true
            if let pending = pendingBody {
                pendingBody = nil
                webView.evaluateJavaScript("macpadSetContent(\(Markdown.jsonString(pending)));", completionHandler: nil)
            }
            scroll(toFraction: scrollFraction)
        case "link":
            if let href = dict["href"] as? String, let url = URL(string: href) {
                NSWorkspace.shared.open(url)
            }
        case "markdown":
            if let text = dict["text"] as? String { onMarkdownEdited?(text) }
        case "askLink":
            askForLink(current: dict["href"] as? String ?? "")
        default:
            break
        }
    }

    private func askForLink(current: String) {
        let alert = NSAlert()
        alert.messageText = current.isEmpty ? "Insert Link" : "Edit Link"
        alert.informativeText = "Enter the web address (leave empty to remove the link)."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        var initial = current
        if initial.isEmpty, let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           clip.hasPrefix("http://") || clip.hasPrefix("https://") || clip.hasPrefix("mailto:") {
            initial = clip
        }
        field.stringValue = initial
        field.placeholderString = "https://"
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { focusEditor(); return }
        let url = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        window?.makeFirstResponder(webView)
        webView.evaluateJavaScript("macpadApplyLink(\(Markdown.jsonString(url)));", completionHandler: nil)
    }
}

/// Avoids the retain cycle WKUserContentController creates with its message handlers.
private final class MessageProxy: NSObject, WKScriptMessageHandler {
    var onMessage: ((Any) -> Void)?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        onMessage?(message.body)
    }
}
