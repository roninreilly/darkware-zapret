import Foundation
import SwiftUI
import Darwin

/// HTTPS reachability, not a claim that a whole service or UDP voice works.
enum ProbeVerdict: String, Sendable {
    case reachable, inconclusive, failed

    static func classify(exitStatus: Int32, httpStatus: Int) -> Self {
        guard exitStatus == 0 else { return .failed }
        if (200..<400).contains(httpStatus) { return .reachable }
        if (400..<600).contains(httpStatus) { return .inconclusive }
        return .failed
    }
}

struct ProbeResult: Identifiable, Sendable {
    let id = UUID()
    let strategy: Strategy
    let verdict: ProbeVerdict
    let seconds: Double
    let detail: String
}

@MainActor
final class DiagnosticsModel: ObservableObject {
    @Published var domain = "discord.com"
    @Published var extended = false
    @Published private(set) var isRunning = false
    @Published private(set) var results: [ProbeResult] = []
    @Published private(set) var log = ""
    @Published private(set) var progress = 0.0
    private var work: Task<Void, Never>?
    private var proxy: ProxyProcess?

    var best: ProbeResult? {
        results.filter { $0.verdict == .reachable }.min { $0.seconds < $1.seconds }
    }

    func run(customStrategies: [Strategy]) {
        guard !isRunning else { return }
        let host: String
        do { host = try DomainInput.normalized(domain) }
        catch { log = error.localizedDescription; return }
        results = []
        log = "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)\nHTTPS: \(host)\n"
        progress = 0
        isRunning = true
        let presets = Engine.tpws.builtInStrategies + Engine.byedpi.builtInStrategies
        let candidates = extended ? presets + customStrategies.filter { $0.engine != .packet } : presets
        work = Task {
            defer { self.isRunning = false; self.work = nil }
            do {
                let direct = try await probe(host: host, port: nil)
                append("Direct: \(direct.detail)")
                if direct.verdict == .reachable {
                    append(L("Сайт доступен напрямую. Эти тесты не докажут необходимость обхода.",
                             "Site is reachable directly. These tests cannot establish a need for bypass."))
                }
                append(L("Проверяем SOCKS-стратегии дважды. Настройки системы не меняются.",
                         "Testing SOCKS strategies twice. System settings stay unchanged."))
                for (index, strategy) in candidates.enumerated() {
                    try Task.checkCancellation()
                    let engine = ProxyProcess()
                    proxy = engine
                    let port = try Self.availablePort()
                    do {
                        try await engine.start(engine: strategy.engine, arguments: strategy.arguments, port: port)
                        let first = try await probe(host: host, port: port)
                        try Task.checkCancellation()
                        let second = try await probe(host: host, port: port)
                        let verdict: ProbeVerdict = first.verdict == .reachable && second.verdict == .reachable
                            ? .reachable : (first.verdict == .failed || second.verdict == .failed ? .failed : .inconclusive)
                        let result = ProbeResult(strategy: strategy, verdict: verdict,
                                                 seconds: (first.seconds + second.seconds) / 2,
                                                 detail: "\(first.detail); \(second.detail)")
                        results.append(result)
                        append("\(strategy.engine.displayName) / \(strategy.name): \(result.detail)")
                    } catch is CancellationError {
                        engine.stop()
                        proxy = nil
                        throw CancellationError()
                    } catch {
                        results.append(ProbeResult(strategy: strategy, verdict: .failed, seconds: 0,
                                                   detail: error.localizedDescription))
                        append("\(strategy.name): \(error.localizedDescription)")
                    }
                    engine.stop()
                    proxy = nil
                    progress = Double(index + 1) / Double(max(candidates.count, 1))
                }
                append(L("Готово. Результат относится только к HTTPS выбранного домена, не к UDP/голосу или видеопотоку.",
                         "Finished. Results cover this domain's HTTPS only, not UDP/voice or video streaming."))
            } catch is CancellationError {
                append(L("Проверка остановлена.", "Diagnostics cancelled."))
            } catch {
                append(error.localizedDescription)
            }
            proxy?.stop()
            proxy = nil
        }
    }

    func cancel() {
        work?.cancel()
        proxy?.stop()
    }

    private func append(_ text: String) { log += text + "\n" }

    private func probe(host: String, port: Int?) async throws -> (verdict: ProbeVerdict, seconds: Double, detail: String) {
        var arguments = ["--disable", "--silent", "--show-error", "--output", "/dev/null",
                         "--max-time", "6", "--connect-timeout", "3", "--proto", "=https",
                         "--write-out", "\n%{http_code}\n%{time_total}"]
        if let port {
            arguments += ["--noproxy", "", "--proxy", "socks5h://127.0.0.1:\(port)"]
        } else {
            arguments += ["--noproxy", "*"]
        }
        arguments += ["--url", "https://\(host)/"]
        let result = try await CommandRunner.run(executable: URL(fileURLWithPath: "/usr/bin/curl"),
                                                 arguments: arguments, timeout: 8)
        try Task.checkCancellation()
        let lines = result.output.split(separator: "\n", omittingEmptySubsequences: true)
        let seconds = lines.last.flatMap { Double($0) } ?? 0
        let code = lines.dropLast().last.flatMap { Int($0) } ?? 0
        let verdict = ProbeVerdict.classify(exitStatus: result.status, httpStatus: code)
        let detail = result.status == 0
            ? "HTTPS \(code), \(String(format: "%.2f", seconds)) s (\(verdict.rawValue))"
            : "curl \(result.status): \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))"
        return (verdict, seconds, detail)
    }

    private static func availablePort() throws -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let addressLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, addressLength) }
        }
        guard bound == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let result = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        guard result == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        return Int(UInt16(bigEndian: address.sin_port))
    }
}
