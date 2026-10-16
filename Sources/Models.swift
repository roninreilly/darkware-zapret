import Foundation

enum Engine: String, CaseIterable, Identifiable, Codable, Sendable {
    case packet = "utunws"
    case tpws
    case byedpi = "ciadpi"
    var id: String { rawValue }
    var displayName: String {
        switch self { case .packet: "Native Packet · experimental"; case .tpws: "zapret · tpws"; case .byedpi: "ByeDPI" }
    }
    var description: String {
        switch self {
        case .packet: "System-wide IPv4 TCP/UDP bypass · macOS 14+ · administrator access"
        case .tpws: "Local SOCKS5 · TCP · macOS 13+"
        case .byedpi: "Local SOCKS5 · TCP · macOS 13+"
        }
    }
    var defaultStrategyID: String { self == .packet ? "general-simple-fake" : builtInStrategies[0].id }
    var builtInStrategies: [Strategy] {
        switch self {
        case .packet:
            let url = Bundle.main.resourceURL?.appendingPathComponent("Native/strategies.tsv")
            if let url, let text = try? String(contentsOf: url, encoding: .utf8) {
                let parsed = text.split(separator: "\n").compactMap { line -> Strategy? in
                    guard !line.hasPrefix("#") else { return nil }
                    let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
                    guard fields.count >= 2, !fields[0].isEmpty else { return nil }
                    return Strategy(id: String(fields[0]), name: String(fields[1]), engine: self, arguments: [])
                }
                if !parsed.isEmpty { return parsed }
            }
            return [Strategy(id: "general-simple-fake", name: "General · simple fake", engine: self, arguments: [])]
        case .tpws:
            return [
                Strategy(id: "split-disorder", name: "Split+Disorder", engine: self, arguments: ["--split-pos=1,midsld", "--disorder"]),
                Strategy(id: "tlsrec-split", name: "TLSRec+Split", engine: self, arguments: ["--tlsrec=sniext", "--split-pos=1,midsld", "--disorder"]),
                Strategy(id: "tlsrec-midsld", name: "TLSRec MidSLD", engine: self, arguments: ["--tlsrec=midsld", "--split-pos=midsld", "--disorder"]),
                Strategy(id: "tlsrec-oob", name: "TLSRec+OOB", engine: self, arguments: ["--tlsrec=sniext", "--split-pos=1,midsld", "--oob"])
            ]
        case .byedpi:
            return [
                Strategy(id: "disorder", name: "Disorder (Simple)", engine: self, arguments: ["-d", "1"]),
                Strategy(id: "disorder-sni", name: "Disorder (SNI)", engine: self, arguments: ["-d", "1+s"]),
                Strategy(id: "oob", name: "Out-of-band", engine: self, arguments: ["-d", "1", "--oob", "1"]),
                Strategy(id: "auto", name: "Auto (Torst)", engine: self, arguments: ["-A", "torst", "-d", "1"])
            ]
        }
    }
}

struct Strategy: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let engine: Engine
    let arguments: [String]
}

enum ConnectionState: Equatable {
    case idle, connecting, connected, stopping, failed(String)
}

enum RuntimeError: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let text): text } }
}

enum ArgumentParser {
    /// Parses quoting for an argv array. This never evaluates shell expressions.
    static func parse(_ input: String) throws -> [String] {
        var result: [String] = [], token = ""
        var quote: Character?, escaped = false, started = false
        for character in input {
            guard character != "\0", character != "\r" else { throw RuntimeError.message("Arguments contain invalid control characters.") }
            if escaped { token.append(character); escaped = false; started = true; continue }
            if character == "\\", quote != "'" { escaped = true; started = true; continue }
            if let active = quote {
                if character == active { quote = nil } else { token.append(character) }
                continue
            }
            if character == "\"" || character == "'" { quote = character; started = true; continue }
            if character.isWhitespace {
                if started { result.append(token); token = ""; started = false }
            } else { token.append(character); started = true }
        }
        guard quote == nil, !escaped else { throw RuntimeError.message("Close the quotation mark or escape in the arguments.") }
        if started { result.append(token) }
        return result
    }

    static func validateProxyArguments(_ arguments: [String], engine: Engine) throws {
        guard arguments.count <= 256, arguments.allSatisfy({ $0.utf8.count <= 4096 && !$0.contains("\0") }) else {
            throw RuntimeError.message("The strategy is too large or contains invalid arguments.")
        }
        // Exact option names prevent getopt's long-option abbreviations and short-option clusters
        // from bypassing ownership of listener, process lifecycle, and writable files.
        let tpwsRequired: Set<String> = ["hostspell", "hostpad", "split-http-req", "split-tls", "split-pos", "oob-data", "tlsrec", "tlsrec-pos", "tamper-start", "tamper-cutoff", "filter-l3", "filter-tcp", "filter-l7", "hostlist-domains", "hostlist-exclude-domains", "ipset-ip", "ipset-exclude-ip"]
        let tpwsOptional: Set<String> = ["split-any-protocol", "disorder", "oob", "comment"]
        let tpwsFlags: Set<String> = ["hostcase", "hostdot", "hostnospace", "domcase", "methodspace", "methodeol", "hosttab", "unixeol", "new", "skip", "no-resolve", "skip-nodelay"]
        let byeRequired: Set<String> = ["auto", "auto-mode", "cache-ttl", "timeout", "copy", "proto", "pf", "round", "split", "disorder", "oob", "disoob", "fake", "fake-sni", "ttl", "fake-offset", "fake-tls-mod", "oob-data", "mod-http", "tlsrec", "tlsminor", "udp-fake", "def-ttl", "await-int"]
        let byeFlags: Set<String> = ["no-domain", "no-ipv6", "no-udp", "wait-send"]
        let byeShortRequired = Set("ALuTBKVRsdoqfntOQeMrmagW")
        let byeShortFlags = Set("NXUZ")
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            var needsValue = false
            if argument.hasPrefix("--") {
                let pieces = argument.dropFirst(2).split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let name = String(pieces.first ?? "")
                let required = engine == .tpws ? tpwsRequired : byeRequired
                let optional = engine == .tpws ? tpwsOptional : []
                let flags = engine == .tpws ? tpwsFlags : byeFlags
                guard required.contains(name) || optional.contains(name) || flags.contains(name) else {
                    throw RuntimeError.message("Unsupported or application-managed option: \(argument)")
                }
                guard !flags.contains(name) || pieces.count == 1 else { throw RuntimeError.message("This option does not accept a value: \(argument)") }
                needsValue = required.contains(name) && pieces.count == 1
            } else if engine == .byedpi, argument.hasPrefix("-"), let option = argument.dropFirst().first {
                guard byeShortRequired.contains(option) || (byeShortFlags.contains(option) && argument.count == 2) else {
                    throw RuntimeError.message("Unsupported or application-managed option: \(argument)")
                }
                needsValue = byeShortRequired.contains(option) && argument.count == 2
            } else { throw RuntimeError.message("Expected a complete DPI option: \(argument)") }
            if needsValue {
                index += 1
                guard index < arguments.count, !arguments[index].isEmpty else { throw RuntimeError.message("Missing value for \(argument)") }
            }
            index += 1
        }
    }
}

enum DomainInput {
    static func normalized(_ input: String) throws -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard value.utf8.count <= 253, !value.isEmpty, !value.contains(":"), !value.contains("/"), !value.contains("@") else {
            throw RuntimeError.message("Enter a domain name, such as youtube.com, without a URL or port.")
        }
        let labels = value.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2, labels.allSatisfy({ label in
            !label.isEmpty && label.utf8.count <= 63 && label.first != "-" && label.last != "-" && label.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
        }), labels.last!.contains(where: { $0.isLetter }) else {
            throw RuntimeError.message("Enter a valid ASCII domain name (use punycode for international domains).")
        }
        return value
    }
}
