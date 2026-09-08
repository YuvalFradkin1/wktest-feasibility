import AppKit
import WebKit

let CONTROL_HTML = "<html><body style='height:5000px'><h1>CONTROL</h1></body></html>"

let TRIGGER_HTML = """
<!DOCTYPE html><html><head><style>
body { height: 5000px; }
.mover { position:absolute; top:50px; left:50px; width:40px; height:40px;
         will-change:transform; animation: move auto linear;
         animation-timeline: scroll(root); }
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
let dir=1,count=0;
function pump(){window.scrollBy(0,dir*800);
if(window.scrollY>3000||window.scrollY<=0)dir=-dir;
count++;if(count<500)requestAnimationFrame(pump);}
window.addEventListener('load',()=>requestAnimationFrame(pump));
</script></body></html>
"""

class PhaseB: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    var windows:[NSWindow]=[]
    var webViews:[WKWebView]=[]
    var iteration=0
    let maxIterations=5

    func applicationDidFinishLaunching(_ n:Notification) {
        print("=== Phase B: AcceleratedEffect polygon cache race ===")
        print("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        runControl()
    }

    func runControl() {
        print("\n--- CONTROL: static page, no animation ---")
        let wv=makeWebView(); wv.loadHTMLString(CONTROL_HTML,baseURL:nil)
        DispatchQueue.main.asyncAfter(deadline:.now()+8){ print("CONTROL: ok"); self.runTrigger() }
    }

    func runTrigger() {
        iteration+=1
        print("\n--- TRIGGER \(iteration)/\(maxIterations): two WKWebView + polygon scroll ---")
        for _ in 0..<2 { let wv=makeWebView(); wv.loadHTMLString(TRIGGER_HTML,baseURL:nil) }
        DispatchQueue.main.asyncAfter(deadline:.now()+25){
            print("TRIGGER \(self.iteration): no crash in 25s")
            self.webViews.forEach{$0.stopLoading()}
            self.webViews.removeAll(); self.windows.removeAll()
            if self.iteration < self.maxIterations { self.runTrigger() }
            else { print("\nRESULT: INCONCLUSIVE — race not triggered in \(self.maxIterations) iterations"); exit(0) }
        }
    }

    func makeWebView()->WKWebView {
        let wv=WKWebView(frame:NSRect(x:0,y:0,width:800,height:600))
        wv.navigationDelegate=self
        let win=NSWindow(contentRect:NSRect(x:0,y:0,width:800,height:600),
                         styleMask:[.titled],backing:.buffered,defer:false)
        win.contentView=wv; windows.append(win); webViews.append(wv); return wv
    }
    func webView(_ wv:WKWebView,didFail n:WKNavigation!,withError e:Error){print("err:\(e)")}
}

let app=NSApplication.shared
let d=PhaseB(); app.delegate=d; app.run()
