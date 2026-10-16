import AppKit
import Combine
import Darwin
import Foundation
import ServiceManagement

struct CommandResult: Sendable {
    let status: Int32
    let output: String
}

@MainActor
enum CommandRunner {
    static func run(executable: URL, arguments: [String], timeout: TimeInterval = 30) async throws -> CommandResult {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("output")
        FileManager.default.createFile(atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let handle = try FileHandle(forWritingTo: output)
        defer { try? handle.close() }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        do {
            while process.isRunning {
                try Task.checkCancellation()
                guard Date() < deadline else { throw RuntimeError.message("The command timed out.") }
                try await Task.sleep(for: .milliseconds(80))
            }
        } catch {
            if process.isRunning { process.terminate() }
            for _ in 0..<20 where process.isRunning { try? await Task.sleep(for: .milliseconds(50)) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            throw error
        }
        let data = (try? Data(contentsOf: output)) ?? Data()
        return CommandResult(status: process.terminationStatus, output: String(decoding: data.suffix(262_144), as: UTF8.self))
    }

    static func administrator(script: URL, arguments: [String] = []) async throws {
        let command = (["/bin/sh", script.path] + arguments).map(shellQuote).joined(separator: " ")
        let appleScript = "do shell script \"\(command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"
        let result = try await run(executable: URL(fileURLWithPath: "/usr/bin/osascript"), arguments: ["-e", appleScript], timeout: 180)
        guard result.status == 0 else { throw RuntimeError.message(result.output.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    static func shellQuote(_ string: String) -> String { "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'" }
}

struct ProcessIdentity: Codable, Equatable {
    let pid: Int32
    let executable: String
    let userID: UInt32
    let startedSeconds: UInt64
    let startedMicroseconds: UInt64

    static func read(pid: Int32) -> ProcessIdentity? {
        guard pid > 1 else { return nil }
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.size
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size)) == size else { return nil }
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return nil }
        let executable = String(decoding: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return ProcessIdentity(pid: pid, executable: executable, userID: info.pbi_uid, startedSeconds: info.pbi_start_tvsec, startedMicroseconds: info.pbi_start_tvusec)
    }
    var isCurrent: Bool { Self.read(pid: pid) == self }
}

private struct ProxyLease: Codable {
    let owner: ProcessIdentity
    let child: ProcessIdentity
}

@MainActor
final class ProxyProcess {
    private var process: Process?
    private var handle: FileHandle?
    private let logURL: URL?
    private let leaseURL: URL?
    var isRunning: Bool { process?.isRunning == true }
    init(logURL: URL? = nil, leaseURL: URL? = nil) { self.logURL = logURL; self.leaseURL = leaseURL }

    func validateRecoveryOwnership() throws {
        guard let leaseURL, FileManager.default.fileExists(atPath: leaseURL.path) else { return }
        let lease = try JSONDecoder().decode(ProxyLease.self, from: Data(contentsOf: leaseURL))
        if lease.owner.pid != getpid(), lease.owner.isCurrent {
            throw RuntimeError.message("Another Darkware Zapret instance owns the local engine. Quit that instance first.")
        }
    }
    @discardableResult
    func recoverOrphan() throws -> Bool {
        guard !isRunning, let leaseURL, FileManager.default.fileExists(atPath: leaseURL.path) else { return false }
        let lease = try JSONDecoder().decode(ProxyLease.self, from: Data(contentsOf: leaseURL))
        if lease.child.isCurrent {
            guard lease.child.userID == getuid(), lease.child.executable.hasSuffix("/Engines/tpws") || lease.child.executable.hasSuffix("/Engines/ciadpi") else {
                throw RuntimeError.message("The previous engine ownership record is invalid; no process was stopped.")
            }
            guard !lease.owner.isCurrent || lease.owner.pid == getpid() else { throw RuntimeError.message("Another Darkware Zapret instance owns the local engine. Quit that instance first.") }
            guard kill(lease.child.pid, SIGKILL) == 0 || errno == ESRCH else { throw RuntimeError.message("Cannot stop the previous owned local engine.") }
            try FileManager.default.removeItem(at: leaseURL)
            return true
        }
        try FileManager.default.removeItem(at: leaseURL)
        return false
    }
    static func binaryURL(for engine: Engine) throws -> URL {
        guard let root = Bundle.main.resourceURL else { throw RuntimeError.message("Application resources are missing. Install the built .app bundle.") }
        let url = root.appendingPathComponent("Engines/\(engine.rawValue)")
        guard FileManager.default.isExecutableFile(atPath: url.path) else { throw RuntimeError.message("The bundled \(engine.rawValue) engine is missing. Install the release .app bundle.") }
        return url
    }
    func start(engine: Engine, arguments: [String], port: Int) async throws {
        guard engine != .packet, !isRunning, (1024...65535).contains(port) else { throw RuntimeError.message("Invalid local proxy launch.") }
        try ArgumentParser.validateProxyArguments(arguments, engine: engine)
        try recoverOrphan()
        guard !Self.portAcceptingConnections(port) else { throw RuntimeError.message("Port \(port) is already in use. Stop the other listener first.") }
        let process = Process()
        process.executableURL = try Self.binaryURL(for: engine)
        let listener = engine == .tpws ? ["--bind-addr=127.0.0.1", "--port=\(port)", "--socks"] : ["--ip", "127.0.0.1", "--port", String(port)]
        process.arguments = listener + arguments
        process.standardInput = FileHandle.nullDevice
        if let logURL {
            FileManager.default.createFile(atPath: logURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
            let handle = try FileHandle(forWritingTo: logURL)
            self.handle = handle
            process.standardError = handle
            process.standardOutput = handle
        } else {
            process.standardError = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
        }
        try process.run()
        self.process = process
        do {
            if let leaseURL {
                guard let owner = ProcessIdentity.read(pid: getpid()), let child = ProcessIdentity.read(pid: process.processIdentifier) else { throw RuntimeError.message("Cannot record local engine ownership.") }
                try JSONEncoder().encode(ProxyLease(owner: owner, child: child)).write(to: leaseURL, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: leaseURL.path)
            }
            for _ in 0..<60 {
                try Task.checkCancellation()
                guard process.isRunning else { throw RuntimeError.message("\(engine.rawValue) exited during startup. Check the engine log and strategy arguments.") }
                if Self.portAcceptingConnections(port, socksHandshake: true) {
                    try await Task.sleep(for: .milliseconds(150))
                    guard process.isRunning else { throw RuntimeError.message("The engine exited before becoming ready.") }
                    return
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            throw RuntimeError.message("The local proxy did not become ready.")
        } catch { stop(); throw error }
    }
    func stop() {
        guard let process else { return }
        if process.isRunning { process.terminate() }
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        if let leaseURL { try? FileManager.default.removeItem(at: leaseURL) }
        self.process = nil
        try? handle?.close(); handle = nil
    }
    private static func portAcceptingConnections(_ port: Int, socksHandshake: Bool = false) -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(port).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0 }
        }
        guard connected, socksHandshake else { return connected }
        var timeout = timeval(tv_sec: 0, tv_usec: 100_000)
        var noSignal: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        let greeting: [UInt8] = [5, 1, 0]
        guard greeting.withUnsafeBytes({ send(descriptor, $0.baseAddress, $0.count, 0) }) == greeting.count else { return false }
        var response = [UInt8](repeating: 0, count: 2)
        let received = response.withUnsafeMutableBytes { recv(descriptor, $0.baseAddress, $0.count, MSG_WAITALL) }
        return received == 2 && response == [5, 0]
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var engine: Engine { didSet { defaults.set(engine.rawValue, forKey: "Engine") } }
    @Published var strategyID: String { didSet { defaults.set(strategyID, forKey: "StrategyID.\(engine.rawValue)") } }
    @Published var systemProxyEnabled: Bool { didSet { defaults.set(systemProxyEnabled, forKey: "SystemProxyEnabled") } }
    @Published var ipsetMode: String { didSet { defaults.set(ipsetMode, forKey: "IPSetMode") } }
    @Published private(set) var state: ConnectionState = .idle
    @Published private(set) var customStrategies: [Strategy] = []
    @Published var errorMessage: String?
    @Published private(set) var logText = ""
    @Published private(set) var launchAtLogin = false
    @Published private(set) var hasPendingRecovery = false
    private let defaults: UserDefaults
    let dataRoot: URL
    private let proxy: ProxyProcess
    private let settings: ProxySettings
    private var monitor: Task<Void, Never>?
    private var packetOwned = false
    private let packetPIDPath = "/var/run/com.darkware.zapret.packet/engine.pid"
    var strategies: [Strategy] { engine.builtInStrategies + customStrategies.filter { $0.engine == engine } }
    var isRunning: Bool { state == .connected || proxy.isRunning || packetOwned }
    var isBusy: Bool { state == .connecting || state == .stopping }
    var statusText: String {
        switch state { case .idle: "Ready"; case .connecting: "Connecting…"; case .connected: "Connected"; case .stopping: "Stopping…"; case .failed(let message): message }
    }
    var socksAddress: String { "127.0.0.1:1080" }
    var legacyMigrationNeeded: Bool {
        ["/etc/sudoers.d/darkware-zapret", "/Library/LaunchDaemons/com.darkware.zapret.plist", "/opt/darkware-zapret/config_custom"].contains { FileManager.default.fileExists(atPath: $0) }
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DarkwareZapret", isDirectory: true)
        dataRoot = root
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        proxy = ProxyProcess(logURL: root.appendingPathComponent("proxy.log"), leaseURL: root.appendingPathComponent("proxy-session.json"))
        settings = ProxySettings(journalURL: root.appendingPathComponent("proxy-recovery.json"))
        let initialEngine = Engine(rawValue: defaults.string(forKey: "Engine") ?? "") ?? .tpws
        engine = initialEngine
        systemProxyEnabled = defaults.bool(forKey: "SystemProxyEnabled")
        ipsetMode = defaults.string(forKey: "IPSetMode") ?? "none"
        let saved = defaults.string(forKey: "StrategyID.\(initialEngine.rawValue)")
        let legacy = defaults.string(forKey: initialEngine == .tpws ? "ZapretStrategy" : "ByeDPIStrategy")
        let legacyID = initialEngine == .byedpi && legacy == "Fake Packets" ? "oob" : initialEngine.builtInStrategies.first(where: { $0.name == legacy })?.id
        strategyID = saved ?? legacyID ?? initialEngine.defaultStrategyID
        let isLegacyMigration = defaults.data(forKey: "StrategiesV2") == nil
        if let data = defaults.data(forKey: "StrategiesV2"), let values = try? JSONDecoder().decode([Strategy].self, from: data) { customStrategies = values }
        else { migrateStrategies() }
        if isLegacyMigration, defaults.bool(forKey: "UseCustomStrategy"), let oldID = defaults.string(forKey: "SelectedCustomStrategy"), let selected = customStrategies.first(where: { $0.id == oldID && $0.engine == engine }) { strategyID = selected.id }
        if isLegacyMigration {
            defaults.set(false, forKey: "UseCustomStrategy")
            defaults.set(strategyID, forKey: "StrategyID.\(engine.rawValue)")
        }
        hasPendingRecovery = settings.hasPendingRecovery
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setEngine(_ engine: Engine) {
        guard !isBusy, !isRunning else { return }
        self.engine = engine
        strategyID = defaults.string(forKey: "StrategyID.\(engine.rawValue)") ?? engine.defaultStrategyID
        if !strategies.contains(where: { $0.id == strategyID }) { strategyID = engine.defaultStrategyID }
    }
    func saveStrategy(name: String, arguments: String, replacing id: String? = nil) throws {
        guard !isBusy, !isRunning, engine != .packet else { throw RuntimeError.message("Disconnect and select a SOCKS engine to add a strategy.") }
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, cleanName.count <= 80 else { throw RuntimeError.message("Give the strategy a name of 1–80 characters.") }
        let values = try ArgumentParser.parse(arguments)
        try ArgumentParser.validateProxyArguments(values, engine: engine)
        let strategy = Strategy(id: id ?? UUID().uuidString, name: cleanName, engine: engine, arguments: values)
        if let id {
            guard let index = customStrategies.firstIndex(where: { $0.id == id && $0.engine == engine }) else { throw RuntimeError.message("The strategy to update no longer exists.") }
            customStrategies[index] = strategy
        } else { customStrategies.append(strategy) }
        defaults.set(try JSONEncoder().encode(customStrategies), forKey: "StrategiesV2")
        strategyID = strategy.id
    }
    func removeStrategy(id: String) {
        guard !isBusy, !isRunning else { return }
        customStrategies.removeAll { $0.id == id }
        if let data = try? JSONEncoder().encode(customStrategies) { defaults.set(data, forKey: "StrategiesV2") }
        if strategyID == id { strategyID = engine.defaultStrategyID }
    }
    func setLaunchAtLogin(_ enabled: Bool) async {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try await SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } catch { errorMessage = error.localizedDescription }
    }
    func migrateLegacy() async {
        guard !isBusy, !isRunning else { return }
        state = .connecting
        do { try await CommandRunner.administrator(script: try nativeScript("migrate-legacy.sh")); errorMessage = nil; state = .idle; log("Legacy privileged installation removed.") }
        catch { fail(error) }
    }
    func recover() async {
        guard !isBusy else { return }
        if proxy.isRunning || packetOwned { await disconnect(); return }
        errorMessage = nil
        do { try proxy.validateRecoveryOwnership() } catch { fail(error); return }
        if settings.hasPendingRecovery {
            state = .stopping
            do {
                let conflicts = try settings.restore()
                hasPendingRecovery = false
                log(conflicts == 0 ? "Restored network settings from the previous session." : "Kept \(conflicts) network services that were edited outside Darkware Zapret.")
                state = .idle
            } catch { hasPendingRecovery = true; fail(error); return }
        }
        do { if try proxy.recoverOrphan() { log("Stopped the local engine left by the previous app session.") } }
        catch { fail(error); return }
        if packetAlive() || FileManager.default.fileExists(atPath: "/var/run/com.darkware.zapret.packet/ready") {
            packetOwned = true
            engine = .packet
            let installed = (try? String(contentsOfFile: "/Library/Application Support/DarkwareZapret/selected-strategy", encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
            strategyID = engine.builtInStrategies.first(where: { $0.id == installed })?.id ?? engine.defaultStrategyID
            if packetAlive() {
                state = .connected
                log("Reconnected to the installed native engine. Use Stop to remove its routes.")
                startMonitoring()
            } else { fail(RuntimeError.message("The previous native session needs cleanup. Use Disconnect to remove its routes.")) }
        } else { state = .idle }
    }
    func connect() async {
        guard !isBusy, !isRunning else { return }
        errorMessage = nil
        guard !legacyMigrationNeeded else { fail(RuntimeError.message("Migrate the legacy privileged installation before connecting.")); return }
        guard !settings.hasPendingRecovery else { hasPendingRecovery = true; fail(RuntimeError.message("Restore saved network settings before connecting.")); return }
        guard let strategy = strategies.first(where: { $0.id == strategyID }) else { fail(RuntimeError.message("Select a valid strategy.")); return }
        state = .connecting
        do {
            if engine == .packet {
                guard #available(macOS 14, *) else { throw RuntimeError.message("Native Packet requires macOS 14 or newer. Select a SOCKS engine on macOS 13.") }
                guard ["none", "loaded", "any"].contains(ipsetMode) else { throw RuntimeError.message("Select a valid IP set mode.") }
                try await CommandRunner.administrator(script: try nativeScript("install.sh"), arguments: [dataRoot.path, strategy.id, ipsetMode])
                packetOwned = true
                guard packetAlive() else { throw RuntimeError.message("The native engine did not stay running. Check its engine log.") }
            } else {
                try await proxy.start(engine: engine, arguments: strategy.arguments, port: 1080)
                if systemProxyEnabled { try settings.apply(port: 1080) }
                guard proxy.isRunning else { throw RuntimeError.message("The local engine exited while configuring network settings.") }
            }
            hasPendingRecovery = settings.hasPendingRecovery
            state = .connected
            log("Started \(engine.displayName): \(strategy.name).")
            startMonitoring()
        } catch {
            let startupError = error
            var cleanupError: Error?
            if settings.hasPendingRecovery {
                do { try settings.restore() } catch { cleanupError = error; log("Recovery required: \(error.localizedDescription)") }
            }
            // Keep the owned listener alive if restoration authorization was cancelled.
            if !settings.hasPendingRecovery { proxy.stop() }
            if engine == .packet, packetAlive() { packetOwned = true }
            if packetOwned { do { try await stopPacket() } catch { cleanupError = error; log("Native cleanup required: \(error.localizedDescription)") } }
            hasPendingRecovery = settings.hasPendingRecovery
            if let cleanupError { fail(RuntimeError.message("\(startupError.localizedDescription) Cleanup needs attention: \(cleanupError.localizedDescription)")) }
            else { fail(startupError) }
        }
    }
    func disconnect() async {
        guard !isBusy else { return }
        state = .stopping
        monitor?.cancel(); monitor = nil
        do {
            try proxy.validateRecoveryOwnership()
            // Restore while our listener is still alive, so cancelled authorization cannot strand clients.
            if settings.hasPendingRecovery { let conflicts = try settings.restore(); if conflicts > 0 { log("Preserved external SOCKS edits on \(conflicts) services.") } }
            hasPendingRecovery = settings.hasPendingRecovery
            proxy.stop()
            try proxy.recoverOrphan()
            if packetOwned { try await stopPacket() }
            state = .idle
            errorMessage = nil
            log("Stopped; saved network settings restored.")
        } catch { hasPendingRecovery = settings.hasPendingRecovery; fail(error) }
    }
    private func stopPacket() async throws {
        try await CommandRunner.administrator(script: URL(fileURLWithPath: "/Library/Application Support/DarkwareZapret/stop.sh"))
        packetOwned = false
    }
    private func nativeScript(_ name: String) throws -> URL {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("Native/\(name)"), FileManager.default.fileExists(atPath: url.path) else { throw RuntimeError.message("The bundled native installer is missing. Install the release .app bundle.") }
        return url
    }
    private func packetAlive() -> Bool {
        guard let text = try? String(contentsOfFile: packetPIDPath, encoding: .utf8), let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 1 else { return false }
        var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &path, UInt32(path.count))
        guard length > 0 else { return false }
        let executablePath = String(decoding: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return executablePath == "/Library/Application Support/DarkwareZapret/bin/utunws" && (kill(pid, 0) == 0 || errno == EPERM)
    }
    private func startMonitoring() {
        monitor?.cancel()
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self, self.state == .connected else { return }
                let alive = self.engine == .packet ? self.packetAlive() : self.proxy.isRunning
                if !alive {
                    self.monitor = nil
                    await self.disconnect()
                    self.fail(RuntimeError.message("The engine exited unexpectedly. Network settings were restored where possible; inspect the engine log before reconnecting."))
                    return
                }
            }
        }
    }
    private func fail(_ error: Error) { errorMessage = error.localizedDescription; state = .failed(error.localizedDescription); log(error.localizedDescription) }
    private func log(_ message: String) {
        logText += "[\(Date().formatted(date: .omitted, time: .standard))] \(message)\n"
        if logText.count > 32_000 { logText = String(logText.suffix(32_000)) }
    }
    private func migrateStrategies() {
        struct Legacy: Decodable { let engine: String; let name: String; let args: String }
        guard let data = defaults.data(forKey: "CustomStrategies"), let values = try? JSONDecoder().decode([Legacy].self, from: data) else { return }
        customStrategies = values.compactMap { value in
            guard let engine = Engine(rawValue: value.engine), engine != .packet, let arguments = try? ArgumentParser.parse(value.args), (try? ArgumentParser.validateProxyArguments(arguments, engine: engine)) != nil else { return nil }
            return Strategy(id: "\(value.engine)_\(value.name)", name: value.name, engine: engine, arguments: arguments)
        }
        if let data = try? JSONEncoder().encode(customStrategies) { defaults.set(data, forKey: "StrategiesV2") }
    }
}
