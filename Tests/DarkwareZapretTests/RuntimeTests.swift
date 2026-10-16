import Foundation
import Darwin
import Testing
@testable import DarkwareZapret

@Test func quotedArgumentsArePassedLiterally() throws {
    #expect(try ArgumentParser.parse(#"--flag "two words" '' '$(touch /tmp/nope)' a\ b"#) == ["--flag", "two words", "", "$(touch /tmp/nope)", "a b"])
    #expect(throws: (any Error).self) { try ArgumentParser.parse("--flag 'unfinished") }
    #expect(throws: (any Error).self) { try ArgumentParser.parse("trailing\\") }
}

@Test(arguments: ["--bind-addr=0.0.0.0", "--port=9999", "--daemon", "--pidfile=/tmp/process", "--hostlist-auto=/tmp/list"])
func customStrategiesCannotReplaceManagedOptions(_ argument: String) {
    #expect(throws: (any Error).self) { try ArgumentParser.validateProxyArguments([argument], engine: .tpws) }
}

@Test(arguments: ["-i0.0.0.0", "-p9999", "-D", "-l/tmp/log", "-Uroot"])
func shortListenerAndProcessOptionsAreRejected(_ argument: String) {
    #expect(throws: (any Error).self) { try ArgumentParser.validateProxyArguments([argument], engine: .byedpi) }
}

@Test func builtInProxyStrategiesPassValidation() throws {
    for engine in [Engine.tpws, .byedpi] {
        for strategy in engine.builtInStrategies { try ArgumentParser.validateProxyArguments(strategy.arguments, engine: engine) }
    }
}

@Test func domainValidationRejectsURLAndCommandInputs() throws {
    #expect(try DomainInput.normalized("  YouTube.COM \n") == "youtube.com")
    for value in ["https://youtube.com", "-example.com", "foo..com", "example.com;echo", "127.0.0.1", "example.com/path", "a@b.com", "example.com:443"] {
        #expect(throws: (any Error).self) { try DomainInput.normalized(value) }
    }
}

@Test func proxyRestorationPreservesUnrelatedNewSettings() {
    let original: [String: Any] = ["SOCKSEnable": 0, "SOCKSProxy": "old", "SOCKSPort": 9050, "SOCKSUser": "alice", "HTTPEnable": 1]
    let applied: [String: Any] = ["SOCKSEnable": 1, "SOCKSProxy": "127.0.0.1", "SOCKSPort": 1080]
    var current = applied
    current["HTTPProxy"] = "new-http.example"
    current["ExceptionsList"] = ["*.example"]
    let restored = ProxyRestoration.restore(current: current, original: original, applied: applied)
    #expect(restored.owned)
    #expect(restored.settings["SOCKSUser"] as? String == "alice")
    #expect(restored.settings["SOCKSPort"] as? Int == 9050)
    #expect(restored.settings["HTTPProxy"] as? String == "new-http.example")
    #expect(restored.settings["ExceptionsList"] as? [String] == ["*.example"])
}

@Test func proxyRestorationDoesNotOverwriteExternalSOCKSEdit() {
    let original: [String: Any] = ["SOCKSEnable": 0]
    let applied: [String: Any] = ["SOCKSEnable": 1, "SOCKSProxy": "127.0.0.1", "SOCKSPort": 1080]
    var current = applied
    current["SOCKSPort"] = 9999
    let restored = ProxyRestoration.restore(current: current, original: original, applied: applied)
    #expect(!restored.owned)
    #expect(ProxyRestoration.equals(restored.settings, current))
}

@Test func proxyRestorationRemovesOriginallyAbsentKeys() {
    let applied: [String: Any] = ["SOCKSEnable": 1, "SOCKSProxy": "127.0.0.1", "SOCKSPort": 1080]
    let restored = ProxyRestoration.restore(current: applied, original: [:], applied: applied)
    #expect(restored.owned)
    #expect(restored.settings.isEmpty)
}

@Test @MainActor func commandRunnerCapturesOutputAndExitCodeWithoutShell() async throws {
    let result = try await CommandRunner.run(executable: URL(fileURLWithPath: "/usr/bin/printf"), arguments: ["%s", "$(whoami) 'quoted'"])
    #expect(result.status == 0)
    #expect(result.output == "$(whoami) 'quoted'")
}

@Test @MainActor func legacyPreferencesAndCustomStrategiesMigrate() throws {
    let suite = "DarkwareZapretTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set("ciadpi", forKey: "Engine")
    defaults.set("Disorder (SNI)", forKey: "ByeDPIStrategy")
    defaults.set(Data(#"[{"engine":"ciadpi","name":"Saved","args":"-d '1+s'"}]"#.utf8), forKey: "CustomStrategies")
    let model = AppModel(defaults: defaults)
    #expect(model.engine == .byedpi)
    #expect(model.strategyID == "disorder-sni")
    #expect(model.customStrategies.first?.arguments == ["-d", "1+s"])
    #expect(!model.systemProxyEnabled)
}

@Test func macOSTpwsOOBPresetAvoidsUnsupportedDisorderCombination() throws {
    let strategy = try #require(Engine.tpws.builtInStrategies.first { $0.id == "tlsrec-oob" })
    #expect(strategy.arguments.contains("--oob"))
    #expect(!strategy.arguments.contains("--disorder"))
}

@Test @MainActor func liveOwnerBlocksCrashRecoveryWithoutSignallingAnotherProcess() throws {
    struct Lease: Codable { let owner: ProcessIdentity; let child: ProcessIdentity }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sleep")
    process.arguments = ["10"]
    try process.run()
    defer { if process.isRunning { process.terminate() } }
    let identity = try #require(ProcessIdentity.read(pid: process.processIdentifier))
    let current = try #require(ProcessIdentity.read(pid: getpid()))
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("lease.json")
    try JSONEncoder().encode(Lease(owner: identity, child: current)).write(to: url)
    let proxy = ProxyProcess(leaseURL: url)
    #expect(throws: (any Error).self) { try proxy.validateRecoveryOwnership() }
    #expect(process.isRunning)
    #expect(FileManager.default.fileExists(atPath: url.path))
    try JSONEncoder().encode(Lease(owner: current, child: identity)).write(to: url)
    #expect(throws: (any Error).self) { try proxy.recoverOrphan() }
    #expect(process.isRunning)
}
