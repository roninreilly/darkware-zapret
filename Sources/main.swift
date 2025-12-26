import SwiftUI
import AppKit

@main
struct DarkwareZapretApp: App {
    @StateObject private var zapretManager = ZapretManager()
    @StateObject private var installerManager = InstallerManager()
    
    var body: some Scene {
        MenuBarExtra {
            ContentView(zapretManager: zapretManager, installerManager: installerManager)
        } label: {
            Image(systemName: zapretManager.isRunning ? "checkmark.shield.fill" : "xmark.shield.fill")
        }
        .menuBarExtraStyle(.window)
    }
}

struct ContentView: View {
    @ObservedObject var zapretManager: ZapretManager
    @ObservedObject var installerManager: InstallerManager
    
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
                            .contentTransition(.symbolEffect(.replace))
                        
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
                    
                    // Strategy Selection
                    HStack {
                        Text("Strategy")
                            .font(.body)
                        Spacer()
                        Picker("", selection: Binding(
                            get: { zapretManager.currentStrategy },
                            set: { zapretManager.setStrategy($0) }
                        )) {
                            ForEach(ZapretStrategy.allCases) { strategy in
                                Text(strategy.rawValue).tag(strategy)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 140)
                        .disabled(zapretManager.isLoading)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    
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
        .onChange(of: installerManager.isInstalled) { _, newValue in
            if newValue {
                Task { await zapretManager.updateStatus() }
            }
        }
    }
}

// Strategies
enum ZapretStrategy: String, CaseIterable, Identifiable {
    case splitDisorder = "Split + Disorder"
    case discordFix = "Discord Fix"
    case tlsrecSplit = "TLSRec + Split"
    case aggressive = "Aggressive"
    
    var id: String { self.rawValue }
    
    var configContent: String {
        // Use exact same format as original zapret config with <HOSTLIST> placeholders
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
            // Original working strategy for YouTube
            return """
            \(commonVars)
            TPWS_OPT="
            --filter-tcp=80 --methodeol <HOSTLIST> --new
            --filter-tcp=443 --split-pos=1,midsld --disorder <HOSTLIST>
            "
            """
        case .discordFix:
            // Strategy with tlsrec for Discord compatibility
            return """
            \(commonVars)
            TPWS_OPT="
            --filter-tcp=80 --methodeol <HOSTLIST> --new
            --filter-tcp=443 --tlsrec=sniext --split-pos=1,midsld --disorder <HOSTLIST>
            "
            """
        case .tlsrecSplit:
            // TLS record split at SNI extension boundary
            return """
            \(commonVars)
            TPWS_OPT="
            --filter-tcp=80 --methodeol <HOSTLIST> --new
            --filter-tcp=443 --tlsrec=midsld --split-pos=midsld --disorder <HOSTLIST>
            "
            """
        case .aggressive:
            // Most aggressive strategy with multiple techniques
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

@MainActor
class ZapretManager: ObservableObject {
    @Published var isRunning: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var currentStrategy: ZapretStrategy = .splitDisorder
    
    private let startCommand = "sudo /opt/darkware-zapret/init.d/macos/zapret start"
    private let stopCommand = "sudo /opt/darkware-zapret/init.d/macos/zapret stop"
    private let restartCommand = "sudo /opt/darkware-zapret/init.d/macos/zapret restart"
    private let configPath = "/opt/darkware-zapret/config_custom"
    
    init() {
        if let saved = UserDefaults.standard.string(forKey: "ZapretStrategy"),
           let strategy = ZapretStrategy(rawValue: saved) {
            self.currentStrategy = strategy
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
    
    nonisolated private func checkProcessRunning() -> Bool {
        let task = Process()
        task.launchPath = "/usr/bin/pgrep"
        task.arguments = ["-f", "/opt/darkware-zapret/tpws/tpws"]
        
        task.standardOutput = Pipe()
        task.standardError = Pipe()
        
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    func toggleZapret() {
        isLoading = true
        errorMessage = nil
        
        let wasRunning = isRunning
        let targetState = !wasRunning
        isRunning = targetState
        
        let command = wasRunning ? stopCommand : startCommand
        
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
                        self.isRunning = wasRunning
                    }
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Exec failed: \(error.localizedDescription)"
                    self.isRunning = wasRunning
                    self.isLoading = false
                }
            }
        }
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
