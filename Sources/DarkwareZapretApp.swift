import SwiftUI
import AppKit
import ServiceManagement

func L(_ russian: String, _ english: String) -> String {
    Locale.preferredLanguages.first?.hasPrefix("ru") == true ? russian : english
}

@MainActor
private enum AppServices {
    static let model = AppModel()
    static let diagnostics = DiagnosticsModel()
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel? = AppServices.model
    var diagnostics: DiagnosticsModel? = AppServices.diagnostics
    private var quitting = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--render-preview"),
           ProcessInfo.processInfo.arguments.count > index + 1 {
            renderPreview(to: ProcessInfo.processInfo.arguments[index + 1])
            return
        }
        #endif
        Task { await model?.recover() }
    }

    #if DEBUG
    private func renderPreview(to path: String) {
        let preview = AppModel(defaults: UserDefaults(suiteName: "com.darkware.zapret.preview")!)
        let dark = ProcessInfo.processInfo.arguments.contains("--dark")
        let view = NSHostingView(rootView: MenuView(model: preview).environment(\.colorScheme, dark ? .dark : .light))
        view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 640), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        let size = view.fittingSize
        window.setContentSize(NSSize(width: 360, height: size.height))
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
        do { try data.write(to: URL(fileURLWithPath: path)); exit(0) }
        catch { FileHandle.standardError.write(Data("Preview failed: \(error)\n".utf8)); exit(1) }
    }
    #endif

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !quitting, let model else { return .terminateNow }
        guard !model.isBusy else { return .terminateCancel }
        quitting = true
        diagnostics?.cancel()
        Task {
            await model.disconnect()
            // A failed restoration must leave the app open with a recovery action.
            if model.errorMessage != nil {
                quitting = false
                sender.reply(toApplicationShouldTerminate: false)
            } else {
                sender.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }
}

@main
struct DarkwareZapretApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppServices.model
    @StateObject private var diagnostics = AppServices.diagnostics

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            Image(systemName: model.isRunning ? "checkmark.shield.fill" : "shield.lefthalf.filled")
                .accessibilityLabel("Darkware Zapret: \(model.statusText)")
        }
        .menuBarExtraStyle(.window)

        Window(L("Диагностика", "Diagnostics"), id: "diagnostics") {
            DiagnosticsView(model: diagnostics, app: model)
        }
        .defaultSize(width: 760, height: 560)

        Window(L("Стратегии", "Strategies"), id: "strategies") {
            StrategiesView(model: model)
        }
        .defaultSize(width: 680, height: 480)

        Window(L("Журнал", "Activity log"), id: "logs") {
            LogView(model: model)
        }
        .defaultSize(width: 700, height: 440)
    }
}

struct MenuView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var settingsError: String?
    private var locked: Bool { model.isBusy || model.isRunning }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DARKWARE").font(.system(.caption, design: .rounded, weight: .bold)).tracking(2)
                        .foregroundStyle(.secondary)
                    Text("Zapret").font(.system(size: 26, weight: .semibold, design: .rounded))
                }
                Spacer()
                Text(Bundle.main.object(forInfoDictionaryKey: "DarkwareReleaseVersion") as? String ?? "2.0.0-beta.1")
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            .padding(20)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: model.isRunning ? "checkmark.shield.fill" : "shield.lefthalf.filled")
                        .font(.system(size: 28))
                        .foregroundStyle(model.isRunning ? Color.green : Color.secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(statusTitle).font(.headline)
                        Text(model.engine == .packet ? L("Пакетный режим · IPv4", "Packet mode · IPv4") : model.socksAddress)
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if model.isBusy { ProgressView().controlSize(.small) }
                }
                Button {
                    Task {
                        if model.isRunning { await model.disconnect() }
                        else { await model.connect() }
                    }
                } label: {
                    Text(model.isRunning ? L("Отключить", "Disconnect") : L("Подключить", "Connect"))
                        .fontWeight(.semibold).frame(maxWidth: .infinity).padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(model.isRunning ? .secondary : .accentColor)
                .disabled(model.isBusy || model.legacyMigrationNeeded)
                .keyboardShortcut(.return, modifiers: [])
            }
            .padding(16)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 12) {
                Picker(L("Движок", "Engine"), selection: Binding(get: { model.engine }, set: { model.setEngine($0) })) {
                    ForEach(Engine.allCases) { engine in Text(engine.displayName).tag(engine) }
                }
                .disabled(locked)
                Picker(L("Стратегия", "Strategy"), selection: $model.strategyID) {
                    ForEach(model.strategies) { strategy in Text(strategy.name).tag(strategy.id) }
                }
                .disabled(locked)
                Text(model.engine.description).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

                if model.engine == .packet {
                    Label(L("Экспериментально · macOS 14+", "Experimental · macOS 14+"), systemImage: "flask")
                        .font(.caption).foregroundStyle(.orange)
                    Picker("IPSet", selection: $model.ipsetMode) {
                        Text(L("Только домены", "Domains only")).tag("none")
                        Text(L("Из списка IP", "IP list")).tag("loaded")
                        Text(L("Все IPv4", "All IPv4")).tag("any")
                    }
                    .disabled(locked)
                    Button(L("Открыть списки доменов", "Open domain lists")) { openLists() }
                        .disabled(locked)
                    Text(L("Требуется пароль администратора. Отключите VPN с туннелем. Изменения списков применяются при подключении.",
                           "Administrator access required. Disconnect tunnel VPNs. List changes apply on connection."))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Toggle(L("Системный SOCKS-прокси", "System SOCKS proxy"), isOn: $model.systemProxyEnabled)
                        .disabled(locked)
                    Text(model.systemProxyEnabled
                         ? L("Прежние настройки сохраняются и восстанавливаются при отключении.", "Previous settings are saved and restored on disconnect.")
                         : L("Настройте SOCKS5 127.0.0.1:1080 в нужном приложении. UDP/голос не перехватываются автоматически.",
                             "Set SOCKS5 127.0.0.1:1080 in your app. UDP/voice traffic is not captured automatically."))
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if model.legacyMigrationNeeded {
                    Divider()
                    Label(L("Найдена старая системная служба", "Legacy system service found"), systemImage: "arrow.triangle.2.circlepath")
                        .font(.callout)
                    Text(L("Перед запуском удалите службу 1.x и её старые права sudo. Пользовательские стратегии сохранятся.",
                           "Remove the 1.x service and its old sudo permissions before connecting. Saved strategies are kept."))
                        .font(.caption).foregroundStyle(.secondary)
                    Button(L("Обновить службу…", "Migrate service…")) { Task { await model.migrateLegacy() } }
                        .disabled(model.isBusy)
                }
                if let error = model.errorMessage ?? settingsError {
                    Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                    Button(L("Восстановить сеть", "Restore network")) { Task { await model.recover() } }
                        .disabled(model.isBusy)
                }
            }
            .padding(20)

            Divider()
            VStack(spacing: 10) {
                HStack(spacing: 14) {
                    Button { show("diagnostics") } label: { Label(L("Проверить", "Diagnose"), systemImage: "waveform.path.ecg") }
                    Spacer()
                    Button { show("strategies") } label: { Image(systemName: "slider.horizontal.3") }
                        .help(L("Свои стратегии", "Custom strategies")).accessibilityLabel(L("Свои стратегии", "Custom strategies"))
                    Button { show("logs") } label: { Image(systemName: "doc.text") }
                        .help(L("Журнал", "Activity log")).accessibilityLabel(L("Журнал", "Activity log"))
                }
                .buttonStyle(.borderless)
                HStack {
                    Toggle(L("При входе", "Launch at login"), isOn: $launchAtLogin)
                        .toggleStyle(.checkbox)
                        .onChange(of: launchAtLogin) { value in
                            Task {
                                await model.setLaunchAtLogin(value)
                                launchAtLogin = SMAppService.mainApp.status == .enabled
                            }
                        }
                    Spacer()
                    Link(L("Релизы", "Releases"), destination: URL(string: "https://github.com/RoninReilly/darkware-zapret/releases")!)
                    Button(L("Выход", "Quit")) { NSApp.terminate(nil) }.buttonStyle(.borderless)
                }
                .font(.caption)
            }
            .padding(16)
        }
        .frame(width: 360)
        .background(.regularMaterial)
    }

    private var statusTitle: String {
        switch model.state {
        case .idle: L("Готов к запуску", "Ready to connect")
        case .connecting: L("Подключаем…", "Connecting…")
        case .connected: L("Подключено", "Connected")
        case .stopping: L("Восстанавливаем сеть…", "Restoring network…")
        case .failed: L("Требуется внимание", "Needs attention")
        }
    }

    private func show(_ id: String) {
        openWindow(id: id)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openLists() {
        do {
            let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                         appropriateFor: nil, create: true)
                .appendingPathComponent("DarkwareZapret/lists", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let defaults = Bundle.main.resourceURL?.appendingPathComponent("Native/default-lists"),
               let files = try? FileManager.default.contentsOfDirectory(at: defaults, includingPropertiesForKeys: nil) {
                for source in files where source.pathExtension == "txt" {
                    let destination = directory.appendingPathComponent(source.lastPathComponent)
                    if !FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.copyItem(at: source, to: destination)
                    }
                }
            }
            NSWorkspace.shared.open(directory)
        } catch { settingsError = error.localizedDescription }
    }
}

struct DiagnosticsView: View {
    @ObservedObject var model: DiagnosticsModel
    @ObservedObject var app: AppModel
    @State private var exported = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Найдём рабочую стратегию", "Find a working strategy")).font(.title2.weight(.semibold))
                    Text(L("Прямое HTTPS-соединение и две проверки каждого SOCKS-пресета.", "Direct HTTPS baseline and two probes per SOCKS preset."))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.isRunning { ProgressView().controlSize(.small) }
            }
            HStack {
                TextField(L("Домен", "Domain"), text: $model.domain).textFieldStyle(.roundedBorder)
                    .accessibilityLabel(L("Домен для проверки", "Domain to test"))
                Toggle(L("Включая свои", "Include custom"), isOn: $model.extended).toggleStyle(.checkbox)
                Button(model.isRunning ? L("Остановить", "Stop") : L("Проверить", "Run")) {
                    if model.isRunning { model.cancel() }
                    else { model.run(customStrategies: app.customStrategies) }
                }
                .buttonStyle(.borderedProminent)
            }
            .disabled(app.isBusy)
            ProgressView(value: model.progress)
            HSplitView {
                List(model.results) { result in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: result.verdict == .reachable ? "checkmark.circle.fill" : result.verdict == .inconclusive ? "questionmark.circle" : "xmark.circle")
                                .foregroundStyle(result.verdict == .reachable ? .green : .secondary)
                            Text(result.strategy.name).fontWeight(.medium)
                            Spacer()
                            if result.verdict == .reachable { Text(String(format: "%.2f s", result.seconds)).monospacedDigit() }
                        }
                        Text(result.strategy.engine.displayName + " · " + result.verdict.rawValue)
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }
                .frame(minWidth: 240)
                ScrollView {
                    Text(model.log.isEmpty ? L("Проверка не меняет системные настройки и не останавливает другие приложения.",
                                              "Diagnostics do not change system settings or stop other applications.") : model.log)
                        .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                }
                .frame(minWidth: 300)
                .background(Color(nsColor: .textBackgroundColor))
            }
            HStack {
                if let best = model.best {
                    Button(L("Выбрать: ", "Select: ") + best.strategy.name) {
                        app.setEngine(best.strategy.engine)
                        app.strategyID = best.strategy.id
                    }
                    .disabled(app.isRunning || app.isBusy || model.isRunning)
                }
                Spacer()
                Button(exported ? L("Скопировано", "Copied") : L("Скопировать отчёт", "Copy report")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.log, forType: .string)
                    exported = true
                }.disabled(model.log.isEmpty)
            }
            Text(L("Это проверка HTTPS одного домена. Она не подтверждает работу видео, QUIC или голоса Discord. Пакетный режим проверяйте отдельно на своей сети.",
                   "This tests one domain over HTTPS. It does not validate video, QUIC or Discord voice. Test packet mode separately on your network."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20).frame(minWidth: 700, minHeight: 500)
    }
}

struct StrategiesView: View {
    @ObservedObject var model: AppModel
    @State private var name = ""
    @State private var arguments = "--split-pos=1,midsld --disorder"
    @State private var error: String?
    @State private var selectedEngine: Engine = .tpws
    @State private var editingID: String?

    var body: some View {
        HSplitView {
            List(model.customStrategies) { strategy in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(strategy.name).fontWeight(.medium)
                        Spacer()
                        Button(role: .destructive) { model.removeStrategy(id: strategy.id) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless).accessibilityLabel(L("Удалить стратегию", "Delete strategy"))
                            .disabled(model.isRunning || model.isBusy)
                    }
                    Text(strategy.engine.displayName).font(.caption).foregroundStyle(.secondary)
                    Text(strategy.arguments.joined(separator: " ")).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    Button(L("Редактировать", "Edit")) {
                        editingID = strategy.id
                        selectedEngine = strategy.engine
                        name = strategy.name
                        arguments = strategy.arguments.map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }.joined(separator: " ")
                    }.buttonStyle(.borderless)
                }.padding(.vertical, 8)
            }.frame(minWidth: 260)
            VStack(alignment: .leading, spacing: 14) {
                Text(L("Своя стратегия SOCKS", "Custom SOCKS strategy")).font(.title3.weight(.semibold))
                Picker(L("Движок", "Engine"), selection: $selectedEngine) {
                    Text("tpws").tag(Engine.tpws)
                    Text("ByeDPI").tag(Engine.byedpi)
                }.pickerStyle(.segmented)
                TextField(L("Название", "Name"), text: $name).textFieldStyle(.roundedBorder)
                Text(L("Аргументы", "Arguments")).font(.headline)
                TextEditor(text: $arguments).font(.system(.body, design: .monospaced))
                    .border(Color.secondary.opacity(0.25))
                Text(L("Аргументы передаются напрямую движку. Порт, адрес и жизненный цикл задаёт приложение.",
                       "Arguments go directly to the engine. The app controls the port, listen address and process lifecycle."))
                    .font(.caption).foregroundStyle(.secondary)
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
                Button(editingID == nil ? L("Сохранить", "Save") : L("Обновить", "Update")) {
                    do {
                        model.setEngine(selectedEngine)
                        try model.saveStrategy(name: name, arguments: arguments, replacing: editingID)
                        editingID = nil
                        name = ""
                        error = nil
                    } catch { self.error = error.localizedDescription }
                }
                .buttonStyle(.borderedProminent).disabled(model.isRunning || model.isBusy)
            }.padding(20).frame(minWidth: 340)
        }.frame(minWidth: 640, minHeight: 440)
    }
}

struct LogView: View {
    @ObservedObject var model: AppModel
    @State private var engineLog = ""
    private var report: String { model.logText + "\n" + engineLog }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Журнал подключения", "Connection log")).font(.title2.weight(.semibold))
            ScrollView {
                Text(report.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? L("Событий пока нет.", "No events yet.") : report)
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button(L("Обновить", "Refresh")) { loadEngineLog() }
                Button(L("Скопировать", "Copy")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report, forType: .string)
                }
            }
        }.padding(20).frame(minWidth: 600, minHeight: 360)
            .onAppear { loadEngineLog() }
    }

    private func loadEngineLog() {
        let path = model.engine == .packet
            ? URL(fileURLWithPath: "/Library/Application Support/DarkwareZapret/engine.log")
            : model.dataRoot.appendingPathComponent("proxy.log")
        guard let handle = try? FileHandle(forReadingFrom: path) else { engineLog = ""; return }
        defer { try? handle.close() }
        do {
            let end = try handle.seekToEnd()
            try handle.seek(toOffset: end > 32_768 ? end - 32_768 : 0)
            let data = try handle.readToEnd() ?? Data()
            engineLog = String(decoding: data, as: UTF8.self)
        } catch { engineLog = error.localizedDescription }
    }
}
