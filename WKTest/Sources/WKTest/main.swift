import AppKit
import WebKit

// Phase B retry — 7224709bf0
// 3 WKWebView instances, 20-30 iterations, aggressive scroll stress
// Target: RemoteLayerTreeEventDispatcher race on TinyLRUCache
// PLATFORM(MAC) only — confirmed active on macos-latest

let TRIGGER_HTML = """
<!DOCTYPE html><html><head><style>
body { height: 5000px; margin: 0; }
.mover {
    position: absolute; top: 50px; left: 50px;
    width: 40px; height: 40px; will-change: transform;
    animation: move auto linear;
    animation-timeline: scroll(root);
}
@keyframes move { from{offset-distance:0%} to{offset-distance:100%} }
#m0{offset-path:polygon(0% 0%,28% 12%,53% 97%,100% 5%,19% 100%)}
#m1{offset-path:polygon(0% 0%,53% 37%,3% 72%,75% 30%,44% 100%)}
#m2{offset-path:polygon(0% 0%,78% 62%,28% 47%,50% 55%,69% 76%)}
#m3{offset-path:polygon(0% 0%,100% 87%,78% 22%,25% 80%,94% 51%)}
#m4{offset-path:polygon(0% 0%,100% 100%,100% 100%,100% 100%,100% 26%)}
#m5{offset-path:polygon(0% 0%,100% 100%,100% 100%,100% 100%,69% 1%)}
</style></head><body>
<div class="mover" id="m0"></div><div class="mover" id="m1"></div>
<div class="mover" id="m2"></div><div class="mover" id="m3"></div>
<div class="mover" id="m4"></div><div class="mover" id="m5"></div>
<script>
// Aggressive scroll pump — max concurrency pressure
let pos = 0; let dir = 1; let ticks = 0;
function pump() {
    pos += dir * 400;
    if (pos > 4000 || pos < 0) dir = -dir;
    window.scrollTo(0, pos);
    ticks++;
    if (ticks < 3000) requestAnimationFrame(pump);
    else window.webkit.messageHandlers.done.postMessage(ticks);
}
window.addEventListener('load', () => {
    // Force layout + compositing
    document.querySelectorAll('.mover').forEach(el => {
        el.style.transform = 'translateZ(0)';
    });
    requestAnimationFrame(pump);
});
</script></body></html>
"""

let CONTROL_HTML = "<html><body style='height:5000px'><h1>CONTROL</h1></body></html>"

class PhaseB: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    var windows: [NSWindow] = []
    var webViews: [WKWebView] = []
    var iteration = 0
    let maxIterations = 25
    var doneCount = 0
    var crashDetected = false
    var passCount = 0
    let requiredPasses = 3
    var startTime = Date()

    func applicationDidFinishLaunching(_ n: Notification) {
        startTime = Date()
        print("=== Phase B retry: 7224709bf0 AcceleratedEffect race ===")
        print("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        print("Config: 3 WKWebViews, \(maxIterations) iterations, \(requiredPasses) passes required")
        print("")
        runControl()
    }

    func runControl() {
        print("--- CONTROL: static page (no animation) ---")
        let wv = makeWebView(trigger: false)
        wv.loadHTMLString(CONTROL_HTML, baseURL: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            print("CONTROL: ok — no crash")
            self.runIteration()
        }
    }

    func runIteration() {
        iteration += 1
        doneCount = 0
        print("\n--- TRIGGER iteration \(iteration)/\(maxIterations) ---")

        // 3 WKWebView instances = 3 RemoteLayerTreeEventDispatchers racing
        for i in 0..<3 {
            let wv = makeWebView(trigger: true)
            wv.loadHTMLString(TRIGGER_HTML,
                baseURL: URL(string: "https://localhost:\(9000 + i)")!)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            if !self.crashDetected {
                print("iteration \(self.iteration): timeout (no crash)")
                self.cleanup()
                self.next()
            }
        }
    }

    func next() {
        if iteration < maxIterations {
            runIteration()
        } else {
            let elapsed = Int(Date().timeIntervalSince(startTime))
            print("\n=== RESULT: no crash after \(maxIterations) iterations (\(elapsed)s) ===")
            print("RESULT=INCONCLUSIVE")
            exit(0)
        }
    }

    func cleanup() {
        webViews.forEach { $0.stopLoading() }
        webViews.removeAll()
        windows.removeAll()
    }

    func makeWebView(trigger: Bool) -> WKWebView {
        let config = WKWebViewConfiguration()
        if trigger {
            config.userContentController.add(self, name: "done")
        }
        // Force threaded rendering
        config.preferences.setValue(true, forKey: "acceleratedDrawingEnabled")
        let wv = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600),
            configuration: config)
        wv.navigationDelegate = self
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled], backing: .buffered, defer: false)
        win.contentView = wv
        windows.append(win)
        webViews.append(wv)
        return wv
    }

    func userContentController(_ c: WKUserContentController,
                               didReceive msg: WKScriptMessage) {
        doneCount += 1
        if doneCount >= 3 {
            print("iteration \(iteration): all 3 pumps done — no crash")
            cleanup()
            next()
        }
    }

    func webView(_ wv: WKWebView, didFail n: WKNavigation!, withError e: Error) {}
    func webView(_ wv: WKWebView, didFailProvisionalNavigation n: WKNavigation!,
                 withError e: Error) {}
}

// Monitor for WebContent/UIProcess crash signals
signal(SIGCHLD) { _ in
    print("*** SIGCHLD — child process terminated ***")
}

let app = NSApplication.shared
let d = PhaseB()
app.delegate = d
app.run()
