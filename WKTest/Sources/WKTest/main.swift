import AppKit
import WebKit

class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    var window: NSWindow!
    var webView: WKWebView!

    func applicationDidFinishLaunching(_ n: Notification) {
        webView = WKWebView(frame: NSRect(x:0,y:0,width:800,height:600))
        webView.navigationDelegate = self
        window = NSWindow(contentRect: NSRect(x:0,y:0,width:800,height:600),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = webView
        webView.loadHTMLString("<h1 id='x'>OK</h1>", baseURL: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
            print("TIMEOUT"); exit(1)
        }
    }

    func webView(_ wv: WKWebView, didFinish n: WKNavigation!) {
        wv.evaluateJavaScript("document.getElementById('x').innerText") { r, _ in
            print(r as? String == "OK" ? "PASS" : "FAIL")
            exit(r as? String == "OK" ? 0 : 2)
        }
    }

    func webView(_ wv: WKWebView, didFail n: WKNavigation!, withError e: Error) {
        print("ERR: \(e)"); exit(3)
    }
}

let app = NSApplication.shared
let d = AppDelegate()
app.delegate = d
app.run()
