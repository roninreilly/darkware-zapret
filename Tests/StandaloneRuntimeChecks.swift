import Foundation
import Darwin

func L(_ russian: String, _ english: String) -> String { english }

@main
struct RuntimeChecks {
    @MainActor static func main() async throws {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ description: String) throws {
            guard condition() else { throw RuntimeError.message("FAILED: \(description)") }
            count += 1
        }
        func rejects(_ description: String, _ operation: () throws -> Void) throws {
            do { try operation() } catch { count += 1; return }
            throw RuntimeError.message("FAILED: expected rejection: \(description)")
        }
        let parsed = try ArgumentParser.parse(#"--flag "two words" '' '$(touch /tmp/nope)' a\ b"#)
        try check(parsed == ["--flag", "two words", "", "$(touch /tmp/nope)", "a b"], "argv remains literal")
        try rejects("unfinished quotation") { _ = try ArgumentParser.parse("--flag 'unfinished") }
        try rejects("trailing escape") { _ = try ArgumentParser.parse("trailing\\") }
        for argument in ["--bind-addr=0.0.0.0", "--port=9999", "--por=9999", "--daemon", "--pidfile=/tmp/pid", "--hostlist-auto=/tmp/list", "-port=9999"] {
            try rejects(argument) { try ArgumentParser.validateProxyArguments([argument], engine: .tpws) }
        }
        for argument in ["-i0.0.0.0", "-p9999", "-D", "-w/tmp/pid", "-Np9999", "--por=9999", "--cache-dump=/tmp/file"] {
            try rejects(argument) { try ArgumentParser.validateProxyArguments([argument], engine: .byedpi) }
        }
        for engine in [Engine.tpws, .byedpi] {
            for strategy in engine.builtInStrategies { try ArgumentParser.validateProxyArguments(strategy.arguments, engine: engine); count += 1 }
        }
        let normalized = try DomainInput.normalized(" YouTube.COM \n")
        try check(normalized == "youtube.com", "domain normalization")
        for domain in ["https://youtube.com", "-example.com", "foo..com", "example.com;echo", "127.0.0.1", "example.com/path", "a@b.com", "example.com:443"] {
            try rejects(domain) { _ = try DomainInput.normalized(domain) }
        }
        let original: [String: Any] = ["SOCKSEnable": 0, "SOCKSProxy": "old", "SOCKSPort": 9050, "SOCKSUser": "alice"]
        let applied: [String: Any] = ["SOCKSEnable": 1, "SOCKSProxy": "127.0.0.1", "SOCKSPort": 1080]
        var current = applied
        current["HTTPProxy"] = "new-http.example"
        current["ExceptionsList"] = ["*.example"]
        let restored = ProxyRestoration.restore(current: current, original: original, applied: applied)
        try check(restored.owned, "restore owned subset")
        try check(restored.settings["SOCKSUser"] as? String == "alice", "restore authentication setting")
        try check(restored.settings["SOCKSPort"] as? Int == 9050, "restore previous port")
        try check(restored.settings["HTTPProxy"] as? String == "new-http.example", "preserve external HTTP edit")
        try check(restored.settings["ExceptionsList"] as? [String] == ["*.example"], "preserve exclusions")
        current["SOCKSPort"] = 9999
        let conflict = ProxyRestoration.restore(current: current, original: original, applied: applied)
        try check(!conflict.owned && ProxyRestoration.equals(conflict.settings, current), "preserve external SOCKS edit")
        try check(ProxyRestoration.restore(current: applied, original: [:], applied: applied).settings.isEmpty, "remove originally absent settings")
        let suite = "DarkwareZapretChecks.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw RuntimeError.message("Cannot create test preferences") }
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("ciadpi", forKey: "Engine")
        defaults.set("Disorder (SNI)", forKey: "ByeDPIStrategy")
        defaults.set(Data(#"[{"engine":"ciadpi","name":"Saved","args":"-d '1+s'"}]"#.utf8), forKey: "CustomStrategies")
        defaults.set(true, forKey: "UseCustomStrategy")
        defaults.set("ciadpi_Saved", forKey: "SelectedCustomStrategy")
        let model = AppModel(defaults: defaults)
        try check(model.engine == .byedpi, "migrate engine")
        try check(model.strategyID == "ciadpi_Saved", "migrate custom selection")
        try check(model.customStrategies.first?.arguments == ["-d", "1+s"], "migrate argv")
        try check(!model.systemProxyEnabled, "system proxy opt-in default")
        model.strategyID = "disorder"
        let reloaded = AppModel(defaults: defaults)
        try check(reloaded.strategyID == "disorder", "legacy choice cannot override a new selection")
        try model.saveStrategy(name: "Edited", arguments: "-d 2", replacing: "ciadpi_Saved")
        try check(model.customStrategies.count == 1 && model.customStrategies[0].arguments == ["-d", "2"], "edit updates the original strategy")
        defaults.removeObject(forKey: "StrategyID.ciadpi")
        defaults.set("Fake Packets", forKey: "ByeDPIStrategy")
        let legacyFake = AppModel(defaults: defaults)
        try check(legacyFake.strategyID == "oob", "migrate renamed Fake Packets preset")
        let command = try await CommandRunner.run(executable: URL(fileURLWithPath: "/usr/bin/printf"), arguments: ["%s", "$(whoami) 'quoted'"])
        try check(command.status == 0 && command.output == "$(whoami) 'quoted'", "subprocess does not evaluate shell text")
        do {
            _ = try await CommandRunner.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"], timeout: 0.05)
            throw RuntimeError.message("FAILED: command timeout")
        } catch RuntimeError.message(let text) { try check(text == "The command timed out.", "command timeout") }
        let task = Task { try await CommandRunner.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["10"]) }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        do { _ = try await task.value; throw RuntimeError.message("FAILED: cancellation") }
        catch is CancellationError { count += 1 }
        for status: Int32 in [5, 6, 7, 28, 35, 60, 97] { try check(ProbeVerdict.classify(exitStatus: status, httpStatus: 200) == .failed, "transport/certificate error \(status)") }
        for status in [200, 204, 301, 302, 307, 308] { try check(ProbeVerdict.classify(exitStatus: 0, httpStatus: status) == .reachable, "HTTP \(status)") }
        for status in [401, 403, 404, 429, 500, 503] { try check(ProbeVerdict.classify(exitStatus: 0, httpStatus: status) == .inconclusive, "HTTP rejection \(status)") }
        try check(ProbeVerdict.classify(exitStatus: 0, httpStatus: 0) == .failed, "missing response")
        guard let identity = ProcessIdentity.read(pid: ProcessInfo.processInfo.processIdentifier) else { throw RuntimeError.message("Cannot identify test process") }
        try check(identity.isCurrent, "process ownership includes executable, uid, and creation time")
        let oob = Engine.tpws.builtInStrategies.first { $0.id == "tlsrec-oob" }
        try check(oob?.arguments.contains("--oob") == true && oob?.arguments.contains("--disorder") == false, "macOS OOB preset avoids unsupported disorder combination")
        struct Lease: Codable { let owner: ProcessIdentity; let child: ProcessIdentity }
        let fixture = Process()
        fixture.executableURL = URL(fileURLWithPath: "/bin/sleep")
        fixture.arguments = ["10"]
        try fixture.run()
        defer { if fixture.isRunning { fixture.terminate() } }
        guard let fixtureIdentity = ProcessIdentity.read(pid: fixture.processIdentifier) else { throw RuntimeError.message("Cannot identify owned test fixture") }
        let leaseDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: leaseDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: leaseDirectory) }
        let leaseURL = leaseDirectory.appendingPathComponent("lease.json")
        try JSONEncoder().encode(Lease(owner: fixtureIdentity, child: identity)).write(to: leaseURL)
        let recovery = ProxyProcess(leaseURL: leaseURL)
        try rejects("living owner preflight") { try recovery.validateRecoveryOwnership() }
        try check(fixture.isRunning && FileManager.default.fileExists(atPath: leaseURL.path), "preflight keeps the other process and its journal")
        try JSONEncoder().encode(Lease(owner: identity, child: fixtureIdentity)).write(to: leaseURL)
        try rejects("process outside the bundled Engines directory") { try recovery.recoverOrphan() }
        try check(fixture.isRunning, "recovery never signals unrelated process")
        if ProcessInfo.processInfo.arguments.contains("--bundled-engines") {
            func bindAvailable(_ port: Int = 0) throws -> Int {
                let descriptor = socket(AF_INET, SOCK_STREAM, 0)
                guard descriptor >= 0 else { throw RuntimeError.message("Cannot open port probe") }
                defer { close(descriptor) }
                var reuse: Int32 = 1
                setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
                var address = sockaddr_in()
                address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                address.sin_family = sa_family_t(AF_INET)
                address.sin_port = UInt16(port).bigEndian
                address.sin_addr.s_addr = inet_addr("127.0.0.1")
                let length = socklen_t(MemoryLayout<sockaddr_in>.size)
                let bound = withUnsafePointer(to: &address) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, length) }
                }
                guard bound == 0 else { throw RuntimeError.message("Port is still occupied") }
                var addressLength = length
                let named = withUnsafeMutablePointer(to: &address) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &addressLength) }
                }
                guard named == 0 else { throw RuntimeError.message("Cannot read free port") }
                return Int(UInt16(bigEndian: address.sin_port))
            }
            let sessionDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: sessionDirectory) }
            for engine in [Engine.tpws, .byedpi] {
                for strategy in engine.builtInStrategies {
                    let port = try bindAvailable()
                    let engineLease = sessionDirectory.appendingPathComponent("engine-lease.json")
                    let process = ProxyProcess(logURL: sessionDirectory.appendingPathComponent("engine.log"), leaseURL: engineLease)
                    defer { process.stop() }
                    try await process.start(engine: engine, arguments: strategy.arguments, port: port)
                    try check(process.isRunning, "actual SOCKS5 readiness: \(engine.rawValue) / \(strategy.name)")
                    try check(FileManager.default.fileExists(atPath: engineLease.path), "owned process lease is durable")
                    let duplicate = ProxyProcess()
                    do {
                        try await duplicate.start(engine: engine, arguments: strategy.arguments, port: port)
                        duplicate.stop()
                        throw RuntimeError.message("FAILED: duplicate listener was accepted")
                    } catch RuntimeError.message(let message) {
                        try check(message.contains("already in use"), "duplicate listener is refused")
                    }
                    try check(process.isRunning, "duplicate listener refusal preserves the first process")
                    process.stop()
                    try check(!FileManager.default.fileExists(atPath: engineLease.path), "stop removes process lease")
                    var reusable = false
                    for _ in 0..<40 {
                        if (try? bindAvailable(port)) != nil { reusable = true; break }
                        try await Task.sleep(for: .milliseconds(25))
                    }
                    try check(reusable, "stop releases owned listener port")
                    print("Runtime SOCKS5 lifecycle passed: \(engine.rawValue) / \(strategy.name)")
                }
            }
        }
        print("Passed \(count) standalone runtime regression checks. Network preferences were not changed.")
    }
}
