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
                                    // TPWS picker with custom strategies
                                    Picker("", selection: Binding(
                                        get: {
                                            if zapretManager.useCustomStrategy, let custom = zapretManager.selectedCustomStrategy, custom.engine == "tpws" {
                                                return "custom_\(custom.id)"
                                            }
                                            return "preset_\(zapretManager.currentStrategy.rawValue)"
                                        },
                                        set: { newValue in
                                            if newValue.hasPrefix("preset_") {
                                                let presetName = String(newValue.dropFirst(7))
                                                if let strategy = ZapretStrategy.allCases.first(where: { $0.rawValue == presetName }) {
                                                    zapretManager.setStrategy(strategy)
                                                }
                                            } else if newValue.hasPrefix("custom_") {
                                                let customId = String(newValue.dropFirst(7))
                                                if let custom = zapretManager.customStrategies.first(where: { $0.id == customId && $0.engine == "tpws" }) {
                                                    zapretManager.setCustomStrategy(custom)
                                                }
                                            }
                                        }
                                    )) {
                                        // Preset strategies
                                        ForEach(ZapretStrategy.allCases) { strategy in
                                            Text(strategy.rawValue).tag("preset_\(strategy.rawValue)")
                                        }
                                        // Custom strategies from bruteforce
                                        let tpwsCustom = zapretManager.customStrategies.filter { $0.engine == "tpws" }
                                        if !tpwsCustom.isEmpty {
                                            Divider()
                                            ForEach(tpwsCustom) { custom in
                                                Text(custom.name).tag("custom_\(custom.id)")
                                            }
                                        }
                                    }
                                } else {
                                    // ByeDPI picker with custom strategies
                                    Picker("", selection: Binding(
                                        get: {
                                            if zapretManager.useCustomStrategy, let custom = zapretManager.selectedCustomStrategy {
                                                return "custom_\(custom.id)"
                                            }
                                            return "preset_\(zapretManager.currentByeDPIStrategy.rawValue)"
                                        },
                                        set: { newValue in
                                            if newValue.hasPrefix("preset_") {
                                                let presetName = String(newValue.dropFirst(7))
                                                if let strategy = ByeDPIStrategy.allCases.first(where: { $0.rawValue == presetName }) {
                                                    zapretManager.setByeDPIStrategy(strategy)
                                                }
                                            } else if newValue.hasPrefix("custom_") {
                                                let customId = String(newValue.dropFirst(7))
                                                if let custom = zapretManager.customStrategies.first(where: { $0.id == customId && $0.engine == "ciadpi" }) {
                                                    zapretManager.setCustomStrategy(custom)
                                                }
                                            }
                                        }
                                    )) {
                                        // Preset strategies
                                        ForEach(ByeDPIStrategy.allCases) { strategy in
                                            Text(strategy.rawValue).tag("preset_\(strategy.rawValue)")
                                        }
                                        // Custom strategies from bruteforce
                                        let ciadpiCustom = zapretManager.customStrategies.filter { $0.engine == "ciadpi" }
                                        if !ciadpiCustom.isEmpty {
                                            Divider()
                                            ForEach(ciadpiCustom) { custom in
                                                Text(custom.name).tag("custom_\(custom.id)")
                                            }
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
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .frame(width: 28, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .help("Quit")
                .accessibilityLabel("Quit")

                if installerManager.isInstalled {
                    Button {
                        openDiagnosticsWindow()
                    } label: {
                        Image(systemName: "doc.text.magnifyingglass")
                            .frame(width: 28, height: 24)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Diagnostics")
                    .accessibilityLabel("Diagnostics")

                    Button {
                        openStrategiesWindow()
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .frame(width: 28, height: 24)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Strategies")
                    .accessibilityLabel("Strategies")

                    Button {
                        installerManager.uninstall()
                    } label: {
                        Image(systemName: "trash")
                            .frame(width: 28, height: 24)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Uninstall Service")
                    .accessibilityLabel("Uninstall Service")
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

        // Make window work properly with Stage Manager
        window.collectionBehavior = [.managed, .participatesInCycle]

        window.contentView = NSHostingView(rootView: DiagnosticsView(
            diagnosticsManager: diagnosticsManager,
            onStrategiesSaved: {
                self.zapretManager.reloadCustomStrategies()
            }
        ))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openStrategiesWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Strategies"
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.managed, .participatesInCycle]
        window.contentView = NSHostingView(rootView: CustomStrategiesView(zapretManager: zapretManager))
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

// MARK: - Custom Strategies from Bruteforce

struct CustomStrategy: Codable, Identifiable, Equatable {
    let engine: String  // "tpws" or "ciadpi"
    let name: String
    let args: String

    var id: String { "\(engine)_\(name)" }

    var arguments: [String] {
        Self.splitArguments(args)
    }

    static let jsonPath = "/tmp/darkware_strategies.json"
    static let userDefaultsKey = "CustomStrategies"
    static let selectedStrategyKey = "SelectedCustomStrategy"
    static let useCustomStrategyKey = "UseCustomStrategy"

    var tpwsConfigContent: String {
        let trimmedArgs = args.trimmingCharacters(in: .whitespacesAndNewlines)
        let tpwsOptions: String
        if trimmedArgs.contains("--filter-tcp=") || trimmedArgs.contains("\n") {
            tpwsOptions = trimmedArgs
        } else {
            tpwsOptions = """
            --filter-tcp=80 --methodeol <HOSTLIST> --new
            --filter-tcp=443 \(trimmedArgs) <HOSTLIST>
            """
        }

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

        return """
        \(commonVars)
        TPWS_OPT="
        \(tpwsOptions)
        "
        """
    }

    static func splitArguments(_ commandLine: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quote: Character?
        var isEscaping = false

        for char in commandLine {
            if isEscaping {
                current.append(char)
                isEscaping = false
                continue
            }

            if char == "\\" {
                isEscaping = true
                continue
            }

            if let activeQuote = quote {
                if char == activeQuote {
                    quote = nil
                } else {
                    current.append(char)
                }
                continue
            }

            if char == "\"" || char == "'" {
                quote = char
                continue
            }

            if char.isWhitespace {
                if !current.isEmpty {
                    result.append(current)
                    current = ""
                }
            } else {
                current.append(char)
            }
        }

        if isEscaping {
            current.append("\\")
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }

    static func loadFromBruteforce() -> [CustomStrategy] {
        guard let data = FileManager.default.contents(atPath: jsonPath),
              let strategies = try? JSONDecoder().decode([CustomStrategy].self, from: data) else {
            return []
        }
        return strategies
    }

    static func loadSaved() -> [CustomStrategy] {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let strategies = try? JSONDecoder().decode([CustomStrategy].self, from: data) else {
            return []
        }
        return strategies
    }

    static func save(_ strategies: [CustomStrategy]) {
        if let data = try? JSONEncoder().encode(strategies) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    static func loadForEngine(_ engine: String) -> [CustomStrategy] {
        return loadSaved().filter { $0.engine == engine }
    }

    static func loadSelected(from strategies: [CustomStrategy]) -> CustomStrategy? {
        guard UserDefaults.standard.bool(forKey: useCustomStrategyKey),
              let selectedId = UserDefaults.standard.string(forKey: selectedStrategyKey) else {
            return nil
        }
        return strategies.first { $0.id == selectedId }
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

    // Custom strategies from bruteforce
    @Published var customStrategies: [CustomStrategy] = []
    @Published var selectedCustomStrategy: CustomStrategy? = nil
    @Published var useCustomStrategy: Bool = false

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
        // Load custom strategies
        self.customStrategies = CustomStrategy.loadSaved()
        if let custom = CustomStrategy.loadSelected(from: customStrategies) {
            self.selectedCustomStrategy = custom
            self.useCustomStrategy = true
        }
    }

    func reloadCustomStrategies() {
        self.customStrategies = CustomStrategy.loadSaved()
        if let selected = selectedCustomStrategy,
           let refreshed = customStrategies.first(where: { $0.id == selected.id }) {
            selectedCustomStrategy = refreshed
        }
    }

    func saveManualCustomStrategy(engine: Engine, name: String, args: String, replacing oldId: String? = nil) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArgs = args.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !cleanArgs.isEmpty else { return }

        let strategy = CustomStrategy(engine: engine.rawValue, name: cleanName, args: cleanArgs)
        customStrategies.removeAll { existing in
            existing.id == strategy.id || oldId == existing.id
        }
        customStrategies.append(strategy)
        customStrategies.sort { lhs, rhs in
            if lhs.engine == rhs.engine {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.engine < rhs.engine
        }
        CustomStrategy.save(customStrategies)

        if selectedCustomStrategy?.id == oldId || selectedCustomStrategy?.id == strategy.id {
            setCustomStrategy(strategy)
        }
    }

    func deleteCustomStrategy(_ strategy: CustomStrategy) {
        customStrategies.removeAll { $0.id == strategy.id }
        CustomStrategy.save(customStrategies)

        guard selectedCustomStrategy?.id == strategy.id else { return }

        useCustomStrategy = false
        selectedCustomStrategy = nil
        UserDefaults.standard.set(false, forKey: CustomStrategy.useCustomStrategyKey)
        UserDefaults.standard.removeObject(forKey: CustomStrategy.selectedStrategyKey)

        if currentEngine.rawValue == strategy.engine {
            switch currentEngine {
            case .tpws:
                writeTpwsConfig(currentStrategy.configContent, restartIfRunning: isRunning)
            case .byedpi:
                if isRunning {
                    toggleZapret()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        self.toggleZapret()
                    }
                }
            }
        }
    }

    func updateStatus() async {
        let running = checkProcessRunning()
        if self.isRunning != running {
            self.isRunning = running
        }
    }

    func setStrategy(_ strategy: ZapretStrategy) {
        guard strategy != currentStrategy || useCustomStrategy else { return }

        isLoading = true
        currentStrategy = strategy
        useCustomStrategy = false
        selectedCustomStrategy = nil
        UserDefaults.standard.set(strategy.rawValue, forKey: "ZapretStrategy")
        UserDefaults.standard.set(false, forKey: CustomStrategy.useCustomStrategyKey)
        UserDefaults.standard.removeObject(forKey: CustomStrategy.selectedStrategyKey)

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

        if useCustomStrategy, selectedCustomStrategy?.engine != engine.rawValue {
            useCustomStrategy = false
            selectedCustomStrategy = nil
            UserDefaults.standard.set(false, forKey: CustomStrategy.useCustomStrategyKey)
            UserDefaults.standard.removeObject(forKey: CustomStrategy.selectedStrategyKey)
        }

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

    func setCustomStrategy(_ strategy: CustomStrategy) {
        guard currentEngine.rawValue == strategy.engine else { return }

        isLoading = true
        useCustomStrategy = true
        selectedCustomStrategy = strategy
        UserDefaults.standard.set(true, forKey: CustomStrategy.useCustomStrategyKey)
        UserDefaults.standard.set(strategy.id, forKey: CustomStrategy.selectedStrategyKey)

        switch currentEngine {
        case .tpws:
            writeTpwsConfig(strategy.tpwsConfigContent, restartIfRunning: isRunning)
        case .byedpi:
            isLoading = false
            if isRunning {
                toggleZapret()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.toggleZapret()
                }
            }
        }
    }

    private func writeTpwsConfig(_ config: String, restartIfRunning: Bool) {
        let escapedConfig = config.replacingOccurrences(of: "'", with: "'\\''")
        let writeConfig = "printf '%s\\n' '\(escapedConfig)' > \(configPath)"
        let script = restartIfRunning ? "\(writeConfig) && \(restartCommand)" : writeConfig

        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.launchPath = "/bin/sh"
            task.arguments = ["-c", script]
            task.standardOutput = Pipe()
            task.standardError = Pipe()

            do {
                try task.run()
                task.waitUntilExit()

                DispatchQueue.main.async {
                    if task.terminationStatus != 0 {
                        self.errorMessage = "Failed to write TPWS config"
                    }
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

        // Use custom strategy if selected, otherwise use preset
        let strategyArgs: [String]
        if useCustomStrategy, let custom = selectedCustomStrategy, custom.engine == "ciadpi" {
            strategyArgs = custom.arguments
        } else {
            strategyArgs = currentByeDPIStrategy.arguments
        }

        let args = ["-p", port] + strategyArgs

        // Log the arguments for debugging
        let argsLog = Process()
        argsLog.launchPath = "/bin/sh"
        argsLog.arguments = ["-c", "echo 'Arguments: \(args.joined(separator: " "))' >> \(logFile)"]
        try? argsLog.run()
        argsLog.waitUntilExit()

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

                // Give it a moment to start and potentially fail
                Thread.sleep(forTimeInterval: 0.8)

                // CRITICAL: Check if process is still running before enabling proxy!
                if task.isRunning {
                    // Process is alive, safe to enable proxy
                    DispatchQueue.main.sync {
                        self.enableSystemProxy(port: port)
                    }

                    DispatchQueue.main.async {
                        self.isRunning = true
                        self.isLoading = false
                    }
                } else {
                    // Process died immediately - DO NOT enable proxy!
                    DispatchQueue.main.async {
                        self.errorMessage = "ciadpi exited with code \(task.terminationStatus). Check /tmp/ciadpi.log"
                        self.isRunning = false
                        self.isLoading = false
                    }
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
        guard strategy != currentByeDPIStrategy || useCustomStrategy else { return }

        currentByeDPIStrategy = strategy
        useCustomStrategy = false
        selectedCustomStrategy = nil
        UserDefaults.standard.set(strategy.rawValue, forKey: "ByeDPIStrategy")
        UserDefaults.standard.set(false, forKey: CustomStrategy.useCustomStrategyKey)
        UserDefaults.standard.removeObject(forKey: CustomStrategy.selectedStrategyKey)

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

    func uninstall() {
        self.isInstalling = true
        self.errorMessage = nil

        let path = "/opt/darkware-zapret"
        let sudoers = "/etc/sudoers.d/darkware-zapret"

        let scriptSource = "do shell script \"rm -rf '\(path)' && rm -f '\(sudoers)'\" with administrator privileges"

        DispatchQueue.global(qos: .userInitiated).async {
            var error: NSDictionary?
            if let scriptObject = NSAppleScript(source: scriptSource) {
                scriptObject.executeAndReturnError(&error)
            }

            DispatchQueue.main.async {
                if let error = error {
                    self.errorMessage = (error["NSAppleScriptErrorBriefMessage"] as? String) ?? "Uninstall failed"
                } else {
                    self.checkInstallation()
                }
                self.isInstalling = false
            }
        }
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

// MARK: - Custom Strategy Editor

struct CustomStrategiesView: View {
    @ObservedObject var zapretManager: ZapretManager
    @State private var selectedEngine: Engine = .byedpi
    @State private var strategyName = ""
    @State private var strategyArgs = ""
    @State private var editingStrategyId: String?
    @State private var didSave = false

    private var canSave: Bool {
        !strategyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !strategyArgs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List {
                    ForEach(zapretManager.customStrategies) { strategy in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(strategy.name)
                                        .font(.body)
                                        .lineLimit(1)
                                    Text(strategy.engine)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.14))
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                }

                                Text(strategy.args)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }

                            Spacer()

                            if zapretManager.selectedCustomStrategy?.id == strategy.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .help("Selected")
                            }

                            Button {
                                edit(strategy)
                            } label: {
                                Image(systemName: "pencil")
                            }
                            .buttonStyle(.borderless)
                            .help("Edit")

                            Button {
                                zapretManager.deleteCustomStrategy(strategy)
                                if editingStrategyId == strategy.id {
                                    clearForm()
                                }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                            .help("Delete")
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .frame(minWidth: 330)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(editingStrategyId == nil ? "New Strategy" : "Edit Strategy")
                        .font(.headline)

                    Spacer()

                    if didSave {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                Picker("Engine", selection: $selectedEngine) {
                    ForEach(Engine.allCases) { engine in
                        Text(engine.rawValue).tag(engine)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Name", text: $strategyName)
                    .textFieldStyle(.roundedBorder)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Arguments")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $strategyArgs)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 170)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                        )
                }

                HStack {
                    Button("Clear") {
                        clearForm()
                    }

                    Spacer()

                    Button(editingStrategyId == nil ? "Save Strategy" : "Update Strategy") {
                        zapretManager.saveManualCustomStrategy(
                            engine: selectedEngine,
                            name: strategyName,
                            args: strategyArgs,
                            replacing: editingStrategyId
                        )
                        clearForm()
                        didSave = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            didSave = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("TPWS")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("--split-pos=1,midsld --disorder")
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)

                    Text("ciadpi")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text("-d 1 -o 1+s")
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(16)
            .frame(minWidth: 360)
        }
        .frame(width: 720, height: 520)
    }

    private func edit(_ strategy: CustomStrategy) {
        selectedEngine = Engine(rawValue: strategy.engine) ?? .byedpi
        strategyName = strategy.name
        strategyArgs = strategy.args
        editingStrategyId = strategy.id
        didSave = false
    }

    private func clearForm() {
        strategyName = ""
        strategyArgs = ""
        editingStrategyId = nil
    }
}

// MARK: - Diagnostics

enum DiagnosticsMode: String, CaseIterable, Identifiable {
    case quick = "Quick Check"
    case bruteforce = "Bruteforce"

    var id: String { self.rawValue }

    var description: String {
        switch self {
        case .quick:
            return "Fast check of common strategies"
        case .bruteforce:
            return "Test ALL parameter combinations (slow)"
        }
    }

    var scriptName: String {
        switch self {
        case .quick:
            return "macos_blockcheck.sh"
        case .bruteforce:
            return "macos_bruteforce.sh"
        }
    }
}

@MainActor
class DiagnosticsManager: ObservableObject {
    @Published var isRunning = false
    @Published var output = ""
    @Published var testDomain = "discord.com"
    @Published var mode: DiagnosticsMode = .quick

    private var process: Process?

    func runDiagnostics() {
        guard !isRunning else { return }
        isRunning = true
        output = ""

        let zapretPath = "/opt/darkware-zapret"
        let scriptName = mode.scriptName
        let domain = testDomain
        let scriptPath = "\(zapretPath)/\(scriptName)"

        // Check if script exists
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            output += "Error: \(mode.scriptName) not found at \(scriptPath)\n"
            output += "Please reinstall Darkware Zapret.\n"
            isRunning = false
            return
        }

        let timeout = mode == .bruteforce ? "3" : "5"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", """
                cd "\(zapretPath)" && \
                ./\(scriptName) --domain="\(domain)" --timeout=\(timeout) 2>&1
                """]

            process.currentDirectoryURL = URL(fileURLWithPath: zapretPath)

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            DispatchQueue.main.async {
                self.process = process
            }

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

    func saveStrategies() -> Int {
        let strategies = CustomStrategy.loadFromBruteforce()
        if strategies.isEmpty {
            return 0
        }
        // Merge with existing, avoiding duplicates
        var existing = CustomStrategy.loadSaved()
        for strategy in strategies {
            if !existing.contains(where: { $0.id == strategy.id }) {
                existing.append(strategy)
            }
        }
        CustomStrategy.save(existing)
        return strategies.count
    }

    func hasWorkingStrategies() -> Bool {
        let strategies = CustomStrategy.loadFromBruteforce()
        return !strategies.isEmpty
    }
}

struct DiagnosticsView: View {
    @ObservedObject var diagnosticsManager: DiagnosticsManager
    var onStrategiesSaved: (() -> Void)?
    @Environment(\.dismiss) var dismiss
    @State private var copied = false
    @State private var saved = false
    @State private var savedCount = 0

    var body: some View {
        VStack(spacing: 0) {
            // Settings
            VStack(spacing: 8) {
                HStack {
                    Text("Domain:")
                        .font(.subheadline)
                    TextField("Domain to test", text: $diagnosticsManager.testDomain)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                        .disabled(diagnosticsManager.isRunning)

                    Spacer()

                    Text("Mode:")
                        .font(.subheadline)
                    Picker("", selection: $diagnosticsManager.mode) {
                        ForEach(DiagnosticsMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    .disabled(diagnosticsManager.isRunning)
                }

                if diagnosticsManager.mode == .bruteforce {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Bruteforce mode tests all combinations. This may take several minutes.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
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

                // Save Strategies button (always visible in bruteforce mode)
                if diagnosticsManager.mode == .bruteforce {
                    Button {
                        savedCount = diagnosticsManager.saveStrategies()
                        saved = true
                        onStrategiesSaved?()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            saved = false
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: saved ? "checkmark.circle.fill" : "square.and.arrow.down")
                            Text(saved ? "Saved \(savedCount)!" : "Save Strategies")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(diagnosticsManager.isRunning || !diagnosticsManager.hasWorkingStrategies())
                }

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
        .frame(width: 650, height: 500)
    }
}
