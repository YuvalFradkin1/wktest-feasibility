import AppKit
import WebKit

// Phase B extended — 7224709bf0
// KEY FIX: add commitTimer (document.title = ++n every 33ms)
// This forces renderingUpdateComplete() on main thread
// while ScrollingThread runs didRefreshDisplay()
// = the actual race condition Apple reproduced

let TRIGGER_HTML = """
<!DOCTYPE html><html><head><style>
body { height: 5000px; }
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
// Distinct polygons from popup to force LRU eviction churn
// (forces cache misses → more concurrent access)

// CRITICAL: commitTimer forces renderingUpdateComplete() on main thread
// while ScrollingThread runs didRefreshDisplay()
let n = 0;
let commitTimer = setInterval(() => { document.title = ++n; }, 33);

// Scroll pump — drives ScrollingThread::didRefreshDisplay
let dir = 1;
function pump() {
    let y = scrollY + dir * 600;
    if (y > 3800) { dir = -1; y = 3800; }
    if (y < 10)   { dir =  1; y = 10; }
    scrollTo({ top: y, behavior: 'smooth' });
}
let scrollTimer = setInterval(pump, 60);
pump();
window.webkit.messageHandlers.ready.postMessage('ready');
</script></body></html>
"""

// Popup page — distinct polygons to churn LRU cache
let POPUP_HTML = """
<!DOCTYPE html><html><head><style>
body { height: 5000px; }
.mover {
    position: absolute; top: 50px; left: 50px;
    width: 40px; height: 40px; will-change: transform;
    animation: move auto linear;
    animation-timeline: scroll(root);
}
@keyframes move { from{offset-distance:0%} to{offset-distance:100%} }
#n0{offset-path:polygon(0% 0%,23% 2%,5% 10%,10% 48%,94% 13%)}
#n1{offset-path:polygon(0% 0%,48% 4%,30% 35%,35% 23%,87% 38%)}
#n2{offset-path:polygon(0% 0%,73% 7%,55% 60%,60% 73%,77% 63%)}
#n3{offset-path:polygon(0% 0%,98% 9%,80% 85%,85% 98%,67% 88%)}
#n4{offset-path:polygon(0% 0%,100% 12%,100% 100%,100% 100%,57% 100%)}
#n5{offset-path:polygon(0% 0%,100% 14%,100% 100%,100% 100%,47% 100%)}
</style></head><body>
<div class="mover" id="n0"></div><div class="mover" id="n1"></div>
<div class="mover" id="n2"></div><div class="mover" id="n3"></div>
<div class="mover" id="n4"></div><div class="mover" id="n5"></div>
<script>
let m = 0;
let commitTimer = setInterval(() => { document.title = ++m; }, 33);
let dir = 1;
function pump() {
    let y = scrollY + dir * 600;
    if (y > 3800) { dir = -1; y = 3800; }
    if (y < 10)   { dir =  1; y = 10; }
    scrollTo({ top: y, behavior: 'smooth' });
}
setInterval(pump, 60);
pump();
</script></body></html>
"""

let CONTROL_HTML = "<html><body style='height:5000px'><h1>CONTROL</h1></body></html>"

class PhaseB: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    var windows: [NSWindow] = []
    var webViews: [WKWebView] = []
    var iteration = 0
    let maxIterations = 30
    var startTime = Date()

    func applicationDidFinishLaunching(_ n: Notification) {
        startTime = Date()
        print("=== Phase B extended: 7224709bf0 + commitTimer ===")
        print("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        print("KEY: commitTimer forces renderingUpdateComplete/ScrollingThread race")
        print("Config: 2 WKWebViews (opener+popup pattern), \(maxIterations) iterations")
        runControl()
    }

    func makeWebView(name: String) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "ready")
        let wv = WKWebView(frame: NSRect(x:0,y:0,width:900,height:700), configuration: config)
        wv.navigationDelegate = self
        let win = NSWindow(contentRect: NSRect(x:0,y:0,width:900,height:700),
                          styleMask: [.titled,.resizable], backing: .buffered, defer: false)
        win.title = name
        win.contentView = wv
        win.makeKeyAndOrderFront(nil)
        windows.append(win)
        webViews.append(wv)
        return wv
    }

    func runControl() {
        print("\n--- CONTROL ---")
        let wv = makeWebView(name: "Control")
        wv.loadHTMLString(CONTROL_HTML, baseURL: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            print("CONTROL: ok")
            self.cleanup()
            self.runIteration()
        }
    }

    func runIteration() {
        iteration += 1
        print("\n--- TRIGGER \(iteration)/\(maxIterations) (opener+popup, commitTimer) ---")
        // Opener window
        let opener = makeWebView(name: "Opener-\(iteration)")
        opener.loadHTMLString(TRIGGER_HTML, baseURL: URL(string:"https://localhost/")!)
        // Popup window — distinct polygons, same UIProcess
        let popup = makeWebView(name: "Popup-\(iteration)")
        popup.loadHTMLString(POPUP_HTML, baseURL: URL(string:"https://localhost/popup")!)

        DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
            print("TRIGGER \(self.iteration): no crash (25s)")
            self.cleanup()
            if self.iteration < self.maxIterations {
                self.runIteration()
            } else {
                let elapsed = Int(Date().timeIntervalSince(self.startTime))
                print("\n=== RESULT: INCONCLUSIVE — no crash after \(self.maxIterations) iterations (\(elapsed)s) ===")
                exit(0)
            }
        }
    }

    func cleanup() {
        webViews.forEach { $0.stopLoading() }
        webViews.removeAll()
        windows.removeAll()
    }

    func userContentController(_ c: WKUserContentController, didReceive msg: WKScriptMessage) {}
    func webView(_ wv: WKWebView, didFail n: WKNavigation!, withError e: Error) {}
}

signal(SIGCHLD) { _ in print("*** SIGCHLD ***") }

let app = NSApplication.shared
let d = PhaseB()
app.delegate = d
app.run()
