import AppKit
import WebKit
import UniformTypeIdentifiers
import Security
import LocalAuthentication

@MainActor final class OrbitApp: NSObject, NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    var window: NSWindow!
    var dashboard: WKWebView!
    var schoolWindow: NSWindow?
    var schoolView: WKWebView?
    var schoolStatus: NSTextField?
    var syncRunning=false
    var refreshTimer:Timer?
    var assetTimer:Timer?
    var assetStamp:Date?
    let testing = CommandLine.arguments.contains("--self-test")
    let resourceURL = Bundle.main.resourceURL!
    var dataURL: URL {
        FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("org.orbit.school.public-template",isDirectory:true).appendingPathComponent("state.json")
    }
    var legacyDataURL:URL {Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Orbit Data/state.json")}
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = NSAppearance(named: .darkAqua)
        buildMenu()
        window = NSWindow(contentRect: NSRect(x:0,y:0,width:1360,height:900),styleMask:[.titled,.closable,.miniaturizable,.resizable,.fullSizeContentView],backing:.buffered,defer:false)
        window.title="Orbit · 4.3"; window.titlebarAppearsTransparent=true
        window.backgroundColor=NSColor(calibratedRed:0.031,green:0.055,blue:0.14,alpha:1)
        window.minSize=NSSize(width:780,height:620); window.delegate=self; window.isReleasedWhenClosed=false
        let config=WKWebViewConfiguration()
        config.preferences.javaScriptCanOpenWindowsAutomatically=false
        config.userContentController.add(self,name:"orbit")
        var initial = "null",readError=false
        if !testing {
            let candidate=FileManager.default.fileExists(atPath:dataURL.path) ? dataURL:legacyDataURL
            if FileManager.default.fileExists(atPath:candidate.path){
                do {let bytes=try Data(contentsOf:candidate);guard let raw=String(data:bytes,encoding:.utf8) else{throw NSError(domain:"OrbitRead",code:1)};initial=jsLiteral(raw)}catch{readError=true}
            }
        }
        let bootstrap="window.orbitNative=true;window.orbitInitialState=\(initial);window.orbitInitialReadError=\(readError);"
        config.userContentController.addUserScript(WKUserScript(source:bootstrap,injectionTime:.atDocumentStart,forMainFrameOnly:true))
        dashboard=WKWebView(frame:.zero,configuration:config)
        dashboard.navigationDelegate=self; dashboard.uiDelegate=self
        dashboard.underPageBackgroundColor=window.backgroundColor
        window.contentView=dashboard
        // Give content a normal titlebar inset instead of hiding controls under traffic lights.
        window.styleMask.remove(.fullSizeContentView)
        if let screen=NSScreen.main{window.setContentSize(NSSize(width:min(1360,max(780,screen.visibleFrame.width-40)),height:min(900,max(620,screen.visibleFrame.height-60))))}
        window.center(); window.makeKeyAndOrderFront(nil)
        assetStamp=(try? FileManager.default.attributesOfItem(atPath:resourceURL.appendingPathComponent("Orbit.html").path)[.modificationDate]) as? Date
        dashboard.loadFileURL(resourceURL.appendingPathComponent("Orbit.html"),allowingReadAccessTo:resourceURL)
        NSApp.activate(ignoringOtherApps:true)
        if testing { DispatchQueue.main.asyncAfter(deadline:.now()+45){ if NSApp.isRunning { print("SELFTEST_TIMEOUT"); NSApp.terminate(nil) } } }
    }
    func buildMenu(){
        let menu=NSMenu(),appItem=NSMenuItem(),appMenu=NSMenu(); appItem.submenu=appMenu;menu.addItem(appItem)
        appMenu.addItem(withTitle:"O aplikaci Orbit",action:#selector(showAbout),keyEquivalent:"").target=self
        appMenu.addItem(.separator());appMenu.addItem(withTitle:"Skrýt Orbit",action:#selector(NSApplication.hide(_:)),keyEquivalent:"h")
        appMenu.addItem(withTitle:"Ukončit Orbit",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q")
        let editItem=NSMenuItem(title:"Úpravy",action:nil,keyEquivalent:""),edit=NSMenu(title:"Úpravy");editItem.submenu=edit;menu.addItem(editItem)
        for (title,selector,key) in [("Zpět","undo:","z"),("Vyjmout","cut:","x"),("Kopírovat","copy:","c"),("Vložit","paste:","v"),("Vybrat vše","selectAll:","a")] { edit.addItem(withTitle:title,action:Selector(selector),keyEquivalent:key) }
        let winItem=NSMenuItem(title:"Okno",action:nil,keyEquivalent:""),win=NSMenu(title:"Okno");winItem.submenu=win;menu.addItem(winItem);NSApp.windowsMenu=win
        win.addItem(withTitle:"Minimalizovat",action:#selector(NSWindow.miniaturize(_:)),keyEquivalent:"m")
        win.addItem(withTitle:"Zavřít okno",action:#selector(NSWindow.performClose(_:)),keyEquivalent:"w")
        NSApp.mainMenu=menu
    }
    @objc func showAbout(){NSApp.orderFrontStandardAboutPanel(options:[.applicationName:"Orbit",.applicationVersion:"4.3",.credits:NSAttributedString(string:"Školní dashboard · Školní dashboard")])}
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool {if !flag{window.makeKeyAndOrderFront(nil)};return true}
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool {false}
    func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!){
        if webView===dashboard,testing {runSelfTests()}
        if webView===dashboard,!testing {
            refreshIfConnected()
            if assetTimer==nil {assetTimer=Timer.scheduledTimer(withTimeInterval:4,repeats:true){_ in Task { @MainActor in self.checkInterfaceUpdate() }}}
            if refreshTimer==nil{refreshTimer=Timer.scheduledTimer(withTimeInterval:900,repeats:true){_ in Task { @MainActor in self.refreshIfConnected() }}}
        }
        if webView===schoolView{schoolStatus?.stringValue="EduPage · \(webView.url?.host ?? "")"}
    }
    func webView(_ webView:WKWebView,didFailProvisionalNavigation navigation:WKNavigation!,withError error:Error){
        if webView===schoolView {schoolStatus?.stringValue="Stránku se nepodařilo načíst. Zkontroluj připojení a zkus Obnovit."}
        if webView===dashboard {print("DASHBOARD_LOAD_FAILED \(error.localizedDescription)")}
    }
    func webView(_ webView:WKWebView,decidePolicyFor action:WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void){
        guard let url=action.request.url else {decisionHandler(.cancel);return}
        if webView===dashboard {
            if url.isFileURL && url.standardizedFileURL.path.hasPrefix(resourceURL.standardizedFileURL.path+"/"){decisionHandler(.allow);return}
            decisionHandler(.cancel)
            if url.scheme=="https"||url.scheme=="http" {NSWorkspace.shared.open(url)}
        }else{
            if url.scheme=="https"||url.absoluteString=="about:blank" {decisionHandler(.allow)} else {decisionHandler(.cancel)}
        }
    }
    func webView(_ webView:WKWebView,createWebViewWith configuration:WKWebViewConfiguration,for action:WKNavigationAction,windowFeatures:WKWindowFeatures)->WKWebView? {
        guard let url=action.request.url, ["https","http"].contains(url.scheme ?? "") else{return nil}
        if url.host=="\(OrbitConfiguration.school).edupage.org"{openSchool(url)}else{NSWorkspace.shared.open(url)};return nil
    }
    func webView(_ webView:WKWebView,runJavaScriptAlertPanelWithMessage message:String,initiatedByFrame frame:WKFrameInfo,completionHandler:@escaping()->Void){let alert=NSAlert();alert.messageText=message;alert.beginSheetModal(for:webView.window ?? window){_ in completionHandler()}}
    func userContentController(_ userContentController:WKUserContentController,didReceive message:WKScriptMessage){
        guard message.webView===dashboard,message.frameInfo.isMainFrame,
              let source=message.frameInfo.request.url,source.isFileURL,
              source.standardizedFileURL.path.hasPrefix(resourceURL.standardizedFileURL.path+"/"),
              let body=message.body as? [String:Any],let type=body["type"] as? String else{return}
        switch type {
        case "forget-edupage":
            forgetPassword()
        case "sync":
            if let start=body["start"] as? String,start.range(of:"^20[0-9]{2}-[0-9]{2}-[0-9]{2}$",options:.regularExpression) != nil{syncEdupage(start)}
        case "save":
            guard !testing,let raw=body["json"] as? String,raw.utf8.count<8*1024*1024,
                  let bytes=raw.data(using:.utf8), (try? JSONSerialization.jsonObject(with:bytes)) is [String:Any] else{return}
            do {
                try FileManager.default.createDirectory(at:dataURL.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
                if FileManager.default.fileExists(atPath:dataURL.path){
                    let old=try Data(contentsOf:dataURL);try old.write(to:dataURL.deletingLastPathComponent().appendingPathComponent("previous.json"),options:.atomic)
                }
                try bytes.write(to:dataURL,options:.atomic);try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:dataURL.path)
                dashboard.evaluateJavaScript("window.orbitStorageResult?.(true)")
            }catch{dashboard.evaluateJavaScript("window.orbitStorageResult?.(false)")}
        case "external": if let text=body["url"] as? String,let url=URL(string:text),["https","http"].contains(url.scheme ?? ""){NSWorkspace.shared.open(url)}
        case "school": if let text=body["url"] as? String,let url=URL(string:text),url.scheme=="https",url.host=="\(OrbitConfiguration.school).edupage.org"{openSchool(url)}
        case "export":
            guard let text=body["text"] as? String,text.utf8.count<8*1024*1024,let name=body["name"] as? String else{return}
            let panel=NSSavePanel();panel.nameFieldStringValue=URL(fileURLWithPath:name).lastPathComponent
            panel.beginSheetModal(for:window){response in if response == .OK,let url=panel.url{do{try text.write(to:url,atomically:true,encoding:.utf8)}catch{self.showError("Soubor se nepodařilo uložit.")}}}
        case "import":
            let panel=NSOpenPanel();panel.allowsMultipleSelection=false;panel.canChooseDirectories=false;panel.allowedContentTypes=[.json]
            panel.beginSheetModal(for:window){response in if response == .OK,let url=panel.url{do{let bytes=try Data(contentsOf:url);guard bytes.count<=8*1024*1024,let text=String(data:bytes,encoding:.utf8) else{throw NSError(domain:"Orbit",code:1)};self.dashboard.evaluateJavaScript("window.orbitImport(\(self.jsLiteral(text)))")}catch{self.showError("Zálohu se nepodařilo načíst.")}}}
        default:break
        }
    }
    func checkInterfaceUpdate(){
        guard !syncRunning,let stamp=(try? FileManager.default.attributesOfItem(atPath:resourceURL.appendingPathComponent("Orbit.html").path)[.modificationDate]) as? Date,stamp != assetStamp else{return}
        dashboard.evaluateJavaScript("Boolean(document.querySelector('dialog[open]') || document.activeElement?.matches('input,textarea,select,[contenteditable]'))"){value,error in
            guard error==nil,(value as? Bool)==false else{return}
            var initial="null",readError=false
            let candidate=FileManager.default.fileExists(atPath:self.dataURL.path) ? self.dataURL:self.legacyDataURL
            if FileManager.default.fileExists(atPath:candidate.path){if let bytes=try? Data(contentsOf:candidate),let raw=String(data:bytes,encoding:.utf8){initial=self.jsLiteral(raw)}else{readError=true}}
            let script="window.orbitNative=true;window.orbitInitialState=\(initial);window.orbitInitialReadError=\(readError);"
            let controller=self.dashboard.configuration.userContentController;controller.removeAllUserScripts();controller.addUserScript(WKUserScript(source:script,injectionTime:.atDocumentStart,forMainFrameOnly:true))
            self.assetStamp=stamp;self.dashboard.loadFileURL(self.resourceURL.appendingPathComponent("Orbit.html"),allowingReadAccessTo:self.resourceURL)
        }
    }
    func refreshIfConnected(){
        guard !syncRunning,let password=savedPassword() else{return}
        dashboard.evaluateJavaScript("scheduleWeek"){value,error in if let start=value as? String{self.performSync(start,password:password,remember:false)}}
    }
    func savedPassword()->String? {
        let auth=LAContext();auth.interactionNotAllowed=true
        let q:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"org.orbit.school.public-template.edupage",kSecAttrAccount as String:OrbitConfiguration.username,kSecReturnData as String:true,kSecUseAuthenticationContext as String:auth]
        var item:CFTypeRef?;guard SecItemCopyMatching(q as CFDictionary,&item)==errSecSuccess,let data=item as? Data else{return nil};return String(data:data,encoding:.utf8)
    }
    func forgetPassword(){
        guard !syncRunning else{showError("Nejdřív počkej na dokončení synchronizace.");return}
        let alert=NSAlert();alert.messageText="Změnit přihlášení EduPage?";alert.informativeText="Odstraní se uložené heslo z Klíčenky. Načtené známky a rozvrh zůstanou zachované. Při další synchronizaci zadej nové heslo.";alert.addButton(withTitle:"Odstranit uložené heslo");alert.addButton(withTitle:"Zrušit")
        alert.beginSheetModal(for:window){response in if response == .alertFirstButtonReturn{
            let q:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"org.orbit.school.public-template.edupage",kSecAttrAccount as String:OrbitConfiguration.username]
            let status=SecItemDelete(q as CFDictionary)
            self.dashboard.evaluateJavaScript("window.orbitSyncError(\(self.jsLiteral(status==errSecSuccess||status==errSecItemNotFound ? "Uložené přihlášení odstraněno. Spusť synchronizaci a zadej nové heslo.":"Přihlášení se nepodařilo odstranit z Klíčenky.")))")
        }}
    }
    func rememberPassword(_ password:String){
        let q:[String:Any]=[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"org.orbit.school.public-template.edupage",kSecAttrAccount as String:OrbitConfiguration.username]
        let values:[String:Any]=[kSecValueData as String:Data(password.utf8)]
        let status=SecItemUpdate(q as CFDictionary,values as CFDictionary)
        if status==errSecItemNotFound {var add=q;for(k,v)in values{add[k]=v};SecItemAdd(add as CFDictionary,nil)}
    }
    func syncEdupage(_ start:String){
        guard !syncRunning else{return}
        guard !OrbitConfiguration.username.isEmpty,!OrbitConfiguration.school.isEmpty else{showError("Nejprve nastav účet a školu v Configuration.local.swift podle README.");return}
        if let password=savedPassword(){performSync(start,password:password,remember:false);return}
        let alert=NSAlert();alert.messageText="Propojit EduPage s dashboardem";alert.informativeText="Účet nastavený v lokální konfiguraci. Přihlášení pro přenos známek a osobního rozvrhu je oddělené od přihlášení v prohlížeči. Při prvním propojení se stáhne lokální konektor edupage-api."
        alert.addButton(withTitle:"Propojit a načíst");alert.addButton(withTitle:"Zrušit")
        let fields=NSStackView();fields.orientation = .vertical;fields.alignment = .leading;fields.spacing=10
        let secret=NSSecureTextField(frame:NSRect(x:0,y:0,width:360,height:24));secret.placeholderString="Heslo do EduPage"
        let remember=NSButton(checkboxWithTitle:"Uložit heslo do Klíčenky tohoto Macu",target:nil,action:nil);remember.state = .on
        fields.addArrangedSubview(secret);fields.addArrangedSubview(remember);fields.frame=NSRect(x:0,y:0,width:360,height:64);secret.widthAnchor.constraint(equalToConstant:360).isActive=true;alert.accessoryView=fields
        alert.beginSheetModal(for:window){response in if response == .alertFirstButtonReturn,!secret.stringValue.isEmpty{let password=secret.stringValue;secret.stringValue="";self.performSync(start,password:password,remember:remember.state == .on)}}
    }
    func performSync(_ start:String,password:String,remember:Bool){
        syncRunning=true
        dashboard.evaluateJavaScript("window.orbitSyncStatus?.(true)")
        let directory=dataURL.deletingLastPathComponent(),script=resourceURL.appendingPathComponent("edupage_sync.py")
        Task.detached {
            do {
                let data=try Self.fetchEdupage(directory:directory,script:script,start:start,password:password)
                guard let payload=try JSONSerialization.jsonObject(with:data) as? [String:Any],payload["provider"] as? String == "EduPage",let json=String(data:data,encoding:.utf8) else{throw NSError(domain:"OrbitSync",code:2)}
                await MainActor.run {self.syncRunning=false;self.dashboard.evaluateJavaScript("window.orbitSyncStatus?.(false)");if remember{self.rememberPassword(password)};self.dashboard.evaluateJavaScript("window.orbitEdupageReceive(\(json))")}
            }catch{
                await MainActor.run {self.syncRunning=false;self.dashboard.evaluateJavaScript("window.orbitSyncStatus?.(false)");let message="Propojení EduPage selhalo. Ověř internet nebo změň uložené přihlášení v Nastavení. První spuštění vyžaduje Python 3.9+ a stažení konektoru. Původní data zůstala zachována.";self.dashboard.evaluateJavaScript("window.orbitSyncError(\(self.jsLiteral(message)))")}
            }
        }
    }
    nonisolated static func fetchEdupage(directory:URL,script:URL,start:String,password:String)throws->Data {
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let env=directory.appendingPathComponent("connector-venv"),python=env.appendingPathComponent("bin/python3")
        func command(_ exe:String,_ args:[String],input:Data?=nil,capture:Bool=false)throws->Data{
            let p=Process();p.executableURL=URL(fileURLWithPath:exe);p.arguments=args
            var processEnv=ProcessInfo.processInfo.environment;processEnv["PYTHONUNBUFFERED"]="1";processEnv["PYTHONDONTWRITEBYTECODE"]="1";p.environment=processEnv
            p.standardError=FileHandle.nullDevice
            let output=Pipe(),stdin=Pipe();p.standardOutput=capture ? output:FileHandle.nullDevice;p.standardInput=stdin
            try p.run();if let input=input{stdin.fileHandleForWriting.write(input)};try? stdin.fileHandleForWriting.close()
            let timeout=DispatchWorkItem{if p.isRunning{p.terminate()}};DispatchQueue.global().asyncAfter(deadline:.now()+180,execute:timeout)
            let bytes=capture ? output.fileHandleForReading.readDataToEndOfFile():Data();p.waitUntilExit();timeout.cancel()
            guard p.terminationStatus==0,bytes.count<8*1024*1024 else{throw NSError(domain:"OrbitSync",code:1)};return bytes
        }
        if !FileManager.default.fileExists(atPath:python.path){
            let choices=["/usr/local/bin/python3","/opt/homebrew/bin/python3","/usr/bin/python3"]
            guard let system=choices.first(where:{FileManager.default.isExecutableFile(atPath:$0)}) else{throw NSError(domain:"OrbitSync",code:3)}
            _=try command(system,["-m","venv",env.path])
        }
        let marker=env.appendingPathComponent("orbit-ready-0.13.0")
        if !FileManager.default.fileExists(atPath:marker.path){_ = try command(python.path,["-m","pip","install","--disable-pip-version-check","--no-cache-dir","edupage-api==0.13.0"]);try Data().write(to:marker)}
        let input=try JSONSerialization.data(withJSONObject:["username":OrbitConfiguration.username,"password":password,"start":start,"clientVersion":"4.0","subdomain":OrbitConfiguration.school])
        return try command(python.path,[script.path],input:input+Data([10]),capture:true)
    }
    func openSchool(_ url:URL){
        if schoolWindow==nil {
            let win=NSWindow(contentRect:NSRect(x:0,y:0,width:1140,height:820),styleMask:[.titled,.closable,.resizable,.miniaturizable],backing:.buffered,defer:false);win.title="EduPage · Orbit";win.minSize=NSSize(width:760,height:580);win.isReleasedWhenClosed=false
            let container=NSView(),bar=NSStackView();bar.orientation = .horizontal;bar.spacing=8;bar.edgeInsets=NSEdgeInsets(top:9,left:12,bottom:9,right:12)
            for (title,action) in [("Zpět",#selector(sourceBack)),("Obnovit",#selector(sourceReload)),("Rozvrh",#selector(sourceTimetable)),("Suplování",#selector(sourceSubstitutions)),("Známky",#selector(sourceGrades))] {let b=NSButton(title:title,target:self,action:action);b.bezelStyle = .rounded;bar.addArrangedSubview(b)}
            let status=NSTextField(labelWithString:"Přihlášení probíhá přímo v EduPage.");status.font=NSFont.systemFont(ofSize:11);status.textColor = .secondaryLabelColor;bar.addArrangedSubview(status);schoolStatus=status
            let config=WKWebViewConfiguration();config.websiteDataStore = .default();let web=WKWebView(frame:.zero,configuration:config);web.navigationDelegate=self;web.uiDelegate=self
            container.addSubview(bar);container.addSubview(web);bar.translatesAutoresizingMaskIntoConstraints=false;web.translatesAutoresizingMaskIntoConstraints=false
            NSLayoutConstraint.activate([bar.topAnchor.constraint(equalTo:container.topAnchor),bar.leadingAnchor.constraint(equalTo:container.leadingAnchor),bar.trailingAnchor.constraint(equalTo:container.trailingAnchor),web.topAnchor.constraint(equalTo:bar.bottomAnchor),web.leadingAnchor.constraint(equalTo:container.leadingAnchor),web.trailingAnchor.constraint(equalTo:container.trailingAnchor),web.bottomAnchor.constraint(equalTo:container.bottomAnchor)])
            win.contentView=container;win.center();schoolWindow=win;schoolView=web
        }
        schoolView?.load(URLRequest(url:url));schoolWindow?.makeKeyAndOrderFront(nil)
    }
    @objc func sourceBack(){schoolView?.goBack()}
    @objc func sourceReload(){schoolView?.reload()}
    @objc func sourceTimetable(){openSchool(URL(string:"https://\(OrbitConfiguration.school).edupage.org/dashboard/eb.php?mode=timetable")!)}
    @objc func sourceSubstitutions(){openSchool(URL(string:"https://\(OrbitConfiguration.school).edupage.org/substitution/")!)}
    @objc func sourceGrades(){openSchool(URL(string:"https://\(OrbitConfiguration.school).edupage.org/znamky/")!)}
    func showError(_ message:String){let alert=NSAlert();alert.messageText=message;alert.beginSheetModal(for:window)}
    func jsLiteral(_ string:String)->String{let bytes=try! JSONSerialization.data(withJSONObject:[string]);let raw=String(data:bytes,encoding:.utf8)!;return String(raw.dropFirst().dropLast())}
    func runSelfTests(){
        guard let scriptURL=ProcessInfo.processInfo.environment["ORBIT_TEST_SCRIPT"],let script=try? String(contentsOfFile:scriptURL,encoding:.utf8) else {print("SELFTEST_NO_SCRIPT");NSApp.terminate(nil);return}
        dashboard.evaluateJavaScript(script){value,error in
            if let error=error{print("SELFTEST_ERROR \(error.localizedDescription)")}else{print("SELFTEST \(value ?? "null")")}
            if let path=ProcessInfo.processInfo.environment["ORBIT_TEST_SCREENSHOT"] {
                self.dashboard.takeSnapshot(with:nil){image,error in if let data=image?.tiffRepresentation,let bitmap=NSBitmapImageRep(data:data),let png=bitmap.representation(using:.png,properties:[:]) {try? png.write(to:URL(fileURLWithPath:path))};NSApp.terminate(nil)}
            }else{NSApp.terminate(nil)}
        }
    }
}
@main struct OrbitMain {
    @MainActor static func main(){
        let app=NSApplication.shared
        let delegate=OrbitApp()
        app.delegate=delegate
        withExtendedLifetime(delegate){app.run()}
    }
}
