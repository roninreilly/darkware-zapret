import SwiftUI
import AppKit

@main
struct DarkwareZapretApp: App {
    @StateObject private var zapretManager = ZapretManager()
    @StateObject private var installerManager = InstallerManager()
    @StateObject private var diagnosticsManager = DiagnosticsManager()
    
    var body: some Scene {
        MenuBarExtra {
            ContentView(zapretManager: zapretManager, installerManager: installerManager, diagnosticsManager: diagnosticsManager)
        } label: {
            Image(systemName: zapretManager.isRunning ? "checkmark.shield.fill" : "xmark.shield.fill")
        }
        .menuBarExtraStyle(.window)
    }
}

struct ContentView: View {
    @ObservedObject var zapretManager: ZapretManager
    @ObservedObject var installerManager: InstallerManager
    @ObservedObject var diagnosticsManager: DiagnosticsManager
    
    var body: some View {
        VStack(spacing: 0) {
            // 1. Header Row
            HStack {
                Text("Darkware Zapret")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                if installerManager.isInstalled {
                    Toggle("", isOn: Binding(
                        get: { zapretManager.isRunning },
                        set: { _ in 
                            withAnimation(.easeInOut(duration: 0.2)) {
                                zapretManager.toggleZapret()
                            }
                        }
                    ))
                    .toggleStyle(.switch)
                    .disabled(zapretManager.isLoading)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            
            Divider()
            
            // 2. Main Content
            VStack(spacing: 0) {
                if installerManager.isInstalled {
                    // Status Row
                    HStack(spacing: 12) {
                        Image(systemName: zapretManager.isRunning ? "checkmark.shield.fill" : "xmark.shield.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(zapretManager.isRunning ? .green : .secondary)
                            .frame(width: 20)
                            .animation(.easeInOut, value: zapretManager.isRunning)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Status")
                                .font(.body)
                                .foregroundColor(.primary)
                            Text(zapretManager.isRunning ? "Active" : "Inactive")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if zapretManager.isLoading {
                            ProgressView().controlSize(.small)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    
                    Divider()
                    
                    // Settings (Engine & Strategy)
                    VStack(spacing: 6) {
                        // Engine Selection
                        HStack {
                            Text("Engine")
                                .font(.body)
                            Spacer()
                            Picker("", selection: Binding(
                                get: { zapretManager.currentEngine },
                                set: { zapretManager.setEngine($0) }
                            )) {
                                ForEach(Engine.allCases) { engine in
                                    Text(engine.rawValue).tag(engine)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 160, alignment: .trailing) // Force alignment to right
                            .disabled(zapretManager.isLoading)
                        }
                        
                        // Strategy Selection
                        HStack {
                            Text("Strategy")
                                .font(.body)
                            Spacer()
                            
                            Group {
                                if zapretManager.currentEngine == .tpws {
                                    Picker("", selection: Binding(
                                        get: { zapretManager.currentStrategy },
                                        set: { zapretManager.setStrategy($0) }
                                    )) {
                                        ForEach(ZapretStrategy.allCases) { strategy in
                                            Text(strategy.rawValue).tag(strategy)
                                        }
                                    }
                                } else {
                                    Picker("", selection: Binding(
                                        get: { zapretManager.currentByeDPIStrategy },
                                        set: { zapretManager.setByeDPIStrategy($0) }
                                    )) {
                                        ForEach(ByeDPIStrategy.allCases) { strategy in
                                            Text(strategy.rawValue).tag(strategy)
                                        }
                                    }
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 160, alignment: .trailing) // Force alignment to right
                            .disabled(zapretManager.isLoading)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                } else {
                    // Install Row
                    Button(action: { installerManager.install() }) {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 16))
                                .foregroundColor(.blue)
                                .frame(width: 20)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Install Service")
                                    .font(.body)
                                    .foregroundColor(.primary)
                                Text("Required for DPI bypass")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if installerManager.isInstalling {
                                ProgressView().controlSize(.small)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    
                    if let error = installerManager.errorMessage {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .padding(.bottom, 8)
                            .padding(.horizontal, 14)
                    }
                }
            }
            
            Divider()
            
            // 3. Footer
            HStack {
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(.primary)
                
                if installerManager.isInstalled {
                    Text("•")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                    
                    Button("Diagnostics") {
                        openDiagnosticsWindow()
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Dev"
                Text(installerManager.isInstalled ? "v\(appVersion)" : "")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 320)
        .background(.regularMaterial)
        .task {
            installerManager.checkInstallation()
            await zapretManager.updateStatus()
            
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                if installerManager.isInstalled {
                    await zapretManager.updateStatus()
                }
            }
        }
        .onChange(of: installerManager.isInstalled) { newValue in
            if newValue {
                Task { await zapretManager.updateStatus() }
            }
        }
    }
    
    private func openDiagnosticsWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 650, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Diagnostics"
        window.isReleasedWhenClosed = false  // Не закрывать приложение при закрытии окна
        window.contentView = NSHostingView(rootView: DiagnosticsView(diagnosticsManager: diagnosticsManager))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Engines

enum Engine: String, CaseIterable, Identifiable {
    case tpws = "tpws"
    case byedpi = "ciadpi" // Renamed as requested
    
    var id: String { self.rawValue }
    
    var description: String {
        switch self {
        case .tpws:
            return "Transparent proxy (TCP only)"
        case .byedpi:
            return "SOCKS5 proxy (TCP + UDP)"
        }
    }
}

// MARK: - tpws Strategies (existing)

enum TpwsStrategy: String, CaseIterable, Identifiable {
    case splitDisorder = "Split+Disorder"
    case tlsrecSplit = "TLSRec+Split"
    case tlsrecMidsld = "TLSRec MidSLD"
    case tlsrecOob = "TLSRec+OOB"
    
    var id: String { self.rawValue }
    
    var configContent: String {
        let commonVars = """
        MODE_FILTER=autohostlist
        TPWS_ENABLE=1
        TPWS_SOCKS_ENABLE=1
        TPWS_PORTS=80,443
        INIT_APPLY_FW=1
        DISABLE_IPV6=1
        GZIP_LISTS=0
        GETLIST=get_refilter_domains.sh
        """
        
        switch self {
        case .splitDisorder:
            return """
            \(commonVars)
            TPWS_OPT="
            --filter-tcp=80 --methodeol <HOSTLIST> --new
            --filter-tcp=443 --split-pos=1,midsld --disorder <HOSTLIST>
            "
            """
        case .tlsrecSplit:
            return """
            \(commonVars)
            TPWS_OPT="
            --filter-tcp=80 --methodeol <HOSTLIST> --new
            --filter-tcp=443 --tlsrec=sniext --split-pos=1,midsld --disorder <HOSTLIST>
            "
            """
        case .tlsrecMidsld:
            return """
            \(commonVars)
            TPWS_OPT="
            --filter-tcp=80 --methodeol <HOSTLIST> --new
            --filter-tcp=443 --tlsrec=midsld --split-pos=midsld --disorder <HOSTLIST>
            "
            """
        case .tlsrecOob:
            return """
            \(commonVars)
            TPWS_OPT="
            --filter-tcp=80 --methodeol --hostdot <HOSTLIST> --new
            --filter-tcp=443 --tlsrec=sniext --split-pos=1,midsld --disorder --oob <HOSTLIST>
            "
            """
        }
    }
}

// MARK: - ciadpi Strategies

enum ByeDPIStrategy: String, CaseIterable, Identifiable {
    case disorder = "Disorder (Simple)"
    case disorderSNI = "Disorder (SNI)"
    case fake = "Fake Packets"
    case auto = "Auto (Torst)"
    
    var id: String { self.rawValue }
    
    var arguments: [String] {
        switch self {
        case .disorder:
            // Simple disorder at byte 1 (classic)
            return ["-d", "1"]
        case .disorderSNI:
            // Disorder at SNI position
            return ["-d", "1+s"]
        case .fake:
            // Fake packets strategy (using OOB + Disorder)
            return ["-d", "1", "--oob", "1"]
        case .auto:
            // Auto detection
            return ["-A", "torst", "-d", "1"]
        }
    }
    
    var description: String {
        switch self {
        case .disorder:
            return "Split at byte 1 & reverse order"
        case .disorderSNI:
            return "Split at SNI & reverse order"
        case .fake:
            return "Injects fake data (OOB) to fool DPI"
        case .auto:
            return "Auto-detect blocking type"
        }
    }
}



// MARK: - Legacy ZapretStrategy (for backward compatibility)

enum ZapretStrategy: String, CaseIterable, Identifiable {
    case splitDisorder = "Split+Disorder"
    case discordFix = "TLSRec+Split"
    case tlsrecSplit = "TLSRec MidSLD"
    case aggressive = "TLSRec+OOB"
    
    var id: String { self.rawValue }
    
    // Convert to new TpwsStrategy
    var asTpwsStrategy: TpwsStrategy {
        switch self {
        case .splitDisorder: return .splitDisorder
        case .discordFix: return .tlsrecSplit
        case .tlsrecSplit: return .tlsrecMidsld
        case .aggressive: return .tlsrecOob
        }
    }
    
    var configContent: String {
        return asTpwsStrategy.configContent
    }
}

@MainActor
class ZapretManager: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var currentEngine: Engine = .tpws
    @Published var currentStrategy: ZapretStrategy = .splitDisorder
    @Published var currentByeDPIStrategy: ByeDPIStrategy = .disorder
    
    private let startCommand = "sudo /opt/darkware-zapret/init.d/macos/zapret start"
    private let stopCommand = "sudo /opt/darkware-zapret/init.d/macos/zapret stop"
    private let restartCommand = "sudo /opt/darkware-zapret/init.d/macos/zapret restart"
    private let configPath = "/opt/darkware-zapret/config_custom"
    
    init() {
        // Load saved engine
        if let savedEngine = UserDefaults.standard.string(forKey: "Engine"),
           let engine = Engine(rawValue: savedEngine) {
            self.currentEngine = engine
        }
        // Load saved tpws strategy
        if let saved = UserDefaults.standard.string(forKey: "ZapretStrategy"),
           let strategy = ZapretStrategy(rawValue: saved) {
            self.currentStrategy = strategy
        }
        // Load saved ByeDPI strategy
        if let savedByeDPI = UserDefaults.standard.string(forKey: "ByeDPIStrategy"),
           let strategy = ByeDPIStrategy(rawValue: savedByeDPI) {
            self.currentByeDPIStrategy = strategy
        }
    }
    
    func updateStatus() async {
        let running = checkProcessRunning()
        if self.isRunning != running {
            self.isRunning = running
        }
    }
    
    func setStrategy(_ strategy: ZapretStrategy) {
        guard strategy != currentStrategy else { return }
        
        isLoading = true
        currentStrategy = strategy
        UserDefaults.standard.set(strategy.rawValue, forKey: "ZapretStrategy")
        
        // Write config command
        let writeConfig = "echo '\(strategy.configContent)' > \(configPath)"
        
        // If running, write config AND restart. If not running, just write config.
        let script = self.isRunning ? "\(writeConfig) && \(restartCommand)" : writeConfig
        
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.launchPath = "/bin/sh"
            task.arguments = ["-c", script]
            
            do {
                try task.run()
                task.waitUntilExit()
                
                DispatchQueue.main.async {
                    self.isLoading = false
                    Task { await self.updateStatus() }
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    func setEngine(_ engine: Engine) {
        guard engine != currentEngine else { return }
        
        let wasRunning = isRunning
        
        // If service is running, stop ALL engines first
        if wasRunning {
            stopAllEngines()
        }
        
        currentEngine = engine
        UserDefaults.standard.set(engine.rawValue, forKey: "Engine")
        
        // Auto-start new engine if was running before
        if wasRunning {
            // Use toggleZapret to start, since isRunning is now false
            toggleZapret()
        }
    }
    
    private func stopCurrentEngine() {
        isLoading = true
        
        let command: String
        switch currentEngine {
        case .tpws:
            command = stopCommand
        case .byedpi:
            command = "pkill -f ciadpi 2>/dev/null || true"
            // Disable system SOCKS proxy when stopping ByeDPI
            disableSystemProxy()
        }
        
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", command]
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            errorMessage = "Failed to stop: \(error.localizedDescription)"
        }
        
        isRunning = false
        isLoading = false
    }
    
    private func startCurrentEngine() {
        isLoading = true
        
        switch currentEngine {
        case .tpws:
            // Use existing tpws start logic
            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                task.launchPath = "/bin/sh"
                task.arguments = ["-c", self.startCommand]
                task.standardOutput = Pipe()
                task.standardError = Pipe()
                
                do {
                    try task.run()
                    task.waitUntilExit()
                    DispatchQueue.main.async {
                        self.isRunning = task.terminationStatus == 0
                        self.isLoading = false
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.errorMessage = "Failed to start: \(error.localizedDescription)"
                        self.isLoading = false
                    }
                }
            }
            
        case .byedpi:
            // Start ByeDPI as SOCKS5 proxy
            startByeDPI()
        }
    }
    
    private func startByeDPI() {
        let byedpiPath = "/opt/darkware-zapret/byedpi/ciadpi"
        let port = "1080"
        let logFile = "/tmp/ciadpi.log"
        
        // Ensure log file exists/reset
        let p = Process()
        p.launchPath = "/bin/sh"
        p.arguments = ["-c", "echo 'Starting ciadpi...' > \(logFile)"]
        try? p.run()
        p.waitUntilExit()
        
        let args = ["-p", port] + currentByeDPIStrategy.arguments
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Start ByeDPI process
            let task = Process()
            task.launchPath = byedpiPath
            task.arguments = args
            
            // Redirect output to log file
            task.standardOutput = FileHandle(forWritingAtPath: logFile) ?? Pipe().fileHandleForWriting
            task.standardError = FileHandle(forWritingAtPath: logFile) ?? Pipe().fileHandleForWriting
            
            do {
                try task.run()
                
                // Give it a moment to start
                Thread.sleep(forTimeInterval: 0.5)
                
                // Enable system SOCKS proxy automatically
                self.enableSystemProxy(port: port)
                
                DispatchQueue.main.async {
                    self.isRunning = true
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to start ciadpi: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    private func enableSystemProxy(port: String) {
        // Get active network service (Wi-Fi or Ethernet)
        let services = ["Wi-Fi", "Ethernet", "USB 10/100/1000 LAN"]
        
        for service in services {
            let checkTask = Process()
            checkTask.launchPath = "/usr/sbin/networksetup"
            checkTask.arguments = ["-getinfo", service]
            checkTask.standardOutput = Pipe()
            checkTask.standardError = Pipe()
            
            do {
                try checkTask.run()
                checkTask.waitUntilExit()
                
                if checkTask.terminationStatus == 0 {
                    // This service exists, configure SOCKS proxy
                    let setProxy = Process()
                    setProxy.launchPath = "/usr/sbin/networksetup"
                    setProxy.arguments = ["-setsocksfirewallproxy", service, "127.0.0.1", port]
                    setProxy.standardOutput = Pipe()
                    setProxy.standardError = Pipe()
                    try setProxy.run()
                    setProxy.waitUntilExit()
                    
                    let enableProxy = Process()
                    enableProxy.launchPath = "/usr/sbin/networksetup"
                    enableProxy.arguments = ["-setsocksfirewallproxystate", service, "on"]
                    enableProxy.standardOutput = Pipe()
                    enableProxy.standardError = Pipe()
                    try enableProxy.run()
                    enableProxy.waitUntilExit()
                }
            } catch {}
        }
    }
    
    private func disableSystemProxy() {
        let services = ["Wi-Fi", "Ethernet", "USB 10/100/1000 LAN"]
        
        for service in services {
            let disableProxy = Process()
            disableProxy.launchPath = "/usr/sbin/networksetup"
            disableProxy.arguments = ["-setsocksfirewallproxystate", service, "off"]
            disableProxy.standardOutput = Pipe()
            disableProxy.standardError = Pipe()
            
            do {
                try disableProxy.run()
                disableProxy.waitUntilExit()
            } catch {}
        }
    }
    
    func setByeDPIStrategy(_ strategy: ByeDPIStrategy) {
        guard strategy != currentByeDPIStrategy else { return }
        
        currentByeDPIStrategy = strategy
        UserDefaults.standard.set(strategy.rawValue, forKey: "ByeDPIStrategy")
        
        // If ByeDPI is running, restart with new strategy
        if currentEngine == .byedpi && isRunning {
            toggleZapret() // Stop
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.toggleZapret() // Start again with new strategy
            }
        }
    }
    
    nonisolated private func checkProcessRunning() -> Bool {
        // Check for tpws
        let tpwsTask = Process()
        tpwsTask.launchPath = "/usr/bin/pgrep"
        tpwsTask.arguments = ["-f", "/opt/darkware-zapret/tpws/tpws"]
        tpwsTask.standardOutput = Pipe()
        tpwsTask.standardError = Pipe()
        
        do {
            try tpwsTask.run()
            tpwsTask.waitUntilExit()
            if tpwsTask.terminationStatus == 0 {
                return true
            }
        } catch {}
        
        // Check for ByeDPI
        let byedpiTask = Process()
        byedpiTask.launchPath = "/usr/bin/pgrep"
        byedpiTask.arguments = ["-f", "ciadpi"]
        byedpiTask.standardOutput = Pipe()
        byedpiTask.standardError = Pipe()
        
        do {
            try byedpiTask.run()
            byedpiTask.waitUntilExit()
            return byedpiTask.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    func toggleZapret() {
        isLoading = true
        errorMessage = nil
        
        let wasRunning = isRunning
        let targetState = !wasRunning
        
        if wasRunning {
            // Stop ALL engines (both tpws and byedpi)
            stopAllEngines()
        } else {
            // Start current engine
            switch currentEngine {
            case .tpws:
                isRunning = targetState
                let command = startCommand
                
                DispatchQueue.global(qos: .userInitiated).async {
                    let task = Process()
                    task.launchPath = "/bin/sh"
                    task.arguments = ["-c", command]
                    
                    let pipe = Pipe()
                    task.standardOutput = pipe
                    task.standardError = pipe
                    
                    do {
                        try task.run()
                        task.waitUntilExit()
                        
                        let data = pipe.fileHandleForReading.readDataToEndOfFile()
                        let output = String(data: data, encoding: .utf8) ?? ""
                        
                        DispatchQueue.main.async {
                            if task.terminationStatus != 0 {
                                self.errorMessage = "Failed: \(output)"
                                self.isRunning = false
                            }
                            self.isLoading = false
                        }
                    } catch {
                        DispatchQueue.main.async {
                            self.errorMessage = "Exec failed: \(error.localizedDescription)"
                            self.isRunning = false
                            self.isLoading = false
                        }
                    }
                }
                
            case .byedpi:
                startByeDPI()
            }
        }
    }
    
    private func stopAllEngines() {
        // Stop tpws
        let tpwsStop = Process()
        tpwsStop.launchPath = "/bin/sh"
        tpwsStop.arguments = ["-c", stopCommand]
        tpwsStop.standardOutput = Pipe()
        tpwsStop.standardError = Pipe()
        try? tpwsStop.run()
        tpwsStop.waitUntilExit()
        
        // Stop ByeDPI
        let byedpiStop = Process()
        byedpiStop.launchPath = "/bin/sh"
        byedpiStop.arguments = ["-c", "pkill -9 ciadpi 2>/dev/null || true"]
        byedpiStop.standardOutput = Pipe()
        byedpiStop.standardError = Pipe()
        try? byedpiStop.run()
        byedpiStop.waitUntilExit()
        
        // Disable system proxy
        disableSystemProxy()
        
        isRunning = false
        isLoading = false
    }
}

@MainActor
class InstallerManager: ObservableObject {
    @Published var isInstalled: Bool = false
    @Published var isInstalling: Bool = false
    @Published var errorMessage: String? = nil
    
    private let installPath = "/opt/darkware-zapret"
    private let sudoersFile = "/etc/sudoers.d/darkware-zapret"
    
    func checkInstallation() {
        let fileManager = FileManager.default
        let hasDir = fileManager.fileExists(atPath: installPath)
        let hasSudoers = fileManager.fileExists(atPath: sudoersFile)
        
        self.isInstalled = hasDir && hasSudoers
    }
    
    func install() {
        self.isInstalling = true
        self.errorMessage = nil
        
        guard let resourcePath = Bundle.main.resourcePath else {
            self.errorMessage = "Resources not found"
            self.isInstalling = false
            return
        }
        
        // Prepare temporary directory for installation to bypass App Translocation/Quarantine issues
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("darkware_installer_temp")
        let fileManager = FileManager.default
        
        do {
            // Clean up old temp dir
            if fileManager.fileExists(atPath: tempDir.path) {
                try fileManager.removeItem(at: tempDir)
            }
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
            
            // Copy resources to temp
            let sourceZapret = URL(fileURLWithPath: resourcePath).appendingPathComponent("zapret")
            let sourceScript = URL(fileURLWithPath: resourcePath).appendingPathComponent("install_darkware.sh")
            
            let destZapret = tempDir.appendingPathComponent("zapret")
            let destScript = tempDir.appendingPathComponent("install_darkware.sh")
            
            try fileManager.copyItem(at: sourceZapret, to: destZapret)
            try fileManager.copyItem(at: sourceScript, to: destScript)
            
            // Execute from temp
            let scriptPath = destScript.path
            let quotedScriptPath = "'\(scriptPath)'"
            
            // We pass temp path to script, though script now self-detects, passing it doesn't hurt
            let command = "\(quotedScriptPath)"
            
            // Make executable just in case
            try? fileManager.setAttributes([.posixPermissions: 0o777], ofItemAtPath: scriptPath)
            
            let scriptSource = "do shell script \"\(command)\" with administrator privileges"
            
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                if let scriptObject = NSAppleScript(source: scriptSource) {
                    scriptObject.executeAndReturnError(&error)
                }
                
                // Cleanup temp after run (optional, maybe keep for debug?)
                // try? fileManager.removeItem(at: tempDir)
                
                DispatchQueue.main.async {
                    if let error = error {
                        self.errorMessage = (error[NSAppleScript.errorMessage] as? String) ?? "Installation failed"
                    } else {
                        self.checkInstallation()
                    }
                    self.isInstalling = false
                }
            }
        } catch {
            self.errorMessage = "Prep failed: \(error.localizedDescription)"
            self.isInstalling = false
        }
    }
}

// MARK: - Diagnostics

@MainActor
class DiagnosticsManager: ObservableObject {
    @Published var isRunning = false
    @Published var output = ""
    @Published var testDomain = "discord.com"
    
    private var process: Process?
    
    func runDiagnostics() {
        guard !isRunning else { return }
        isRunning = true
        output = ""
        
        let zapretPath = "/opt/darkware-zapret"
        let blockcheckPath = "\(zapretPath)/macos_blockcheck.sh"
        
        // Check if macos_blockcheck exists
        guard FileManager.default.fileExists(atPath: blockcheckPath) else {
            output += "Error: macos_blockcheck.sh not found at \(blockcheckPath)\n"
            output += "Please reinstall Darkware Zapret.\n"
            isRunning = false
            return
        }
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", """
                cd "\(zapretPath)" && \
                ./macos_blockcheck.sh --domain="\(self.testDomain)" --timeout=5 2>&1
                """]
            
            process.currentDirectoryURL = URL(fileURLWithPath: zapretPath)
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            self.process = process
            
            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                if data.isEmpty { return }
                if let str = String(data: data, encoding: .utf8) {
                    DispatchQueue.main.async {
                        self?.output += str
                    }
                }
            }
            
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                DispatchQueue.main.async {
                    self.output += "\nError running diagnostics: \(error.localizedDescription)\n"
                }
            }
            
            DispatchQueue.main.async {
                self.output += "\n--- Diagnostics finished ---\n"
                self.isRunning = false
                self.process = nil
            }
        }
    }
    
    func stopDiagnostics() {
        process?.terminate()
        isRunning = false
        output += "\n--- Diagnostics cancelled ---\n"
    }
    
    func copyResults() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
    }
}

struct DiagnosticsView: View {
    @ObservedObject var diagnosticsManager: DiagnosticsManager
    @Environment(\.dismiss) var dismiss
    @State private var copied = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Settings
            
            // Settings
            HStack {
                Text("Domain:")
                    .font(.subheadline)
                TextField("Domain to test", text: $diagnosticsManager.testDomain)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .disabled(diagnosticsManager.isRunning)
                
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            Divider()
            
            // Output
            ScrollViewReader { proxy in
                ScrollView {
                    Text(diagnosticsManager.output)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .id("output")
                }
                .onChange(of: diagnosticsManager.output) { _ in
                    withAnimation {
                        proxy.scrollTo("output", anchor: .bottom)
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .padding(8)
            .background(Color(NSColor.textBackgroundColor))
            
            Divider()
            
            // Actions
            HStack {
                if diagnosticsManager.isRunning {
                    Button("Stop") {
                        diagnosticsManager.stopDiagnostics()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    
                    ProgressView()
                        .controlSize(.small)
                        .padding(.leading, 8)
                } else {
                    Button("Run Diagnostics") {
                        diagnosticsManager.runDiagnostics()
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                Spacer()
                
                Button {
                    diagnosticsManager.copyResults()
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copied = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? "Copied!" : "Copy Results")
                    }
                }
                .disabled(diagnosticsManager.output.isEmpty)
            }
            .padding()
        }
        .frame(width: 600, height: 500)
    }
}
