import AppKit

struct AutoDisplaySettingsFormValues: Equatable {
    var claudeEnabled: Bool
    var codexEnabled: Bool
    var approvalEnabled: Bool
    var musicEnabled: Bool

    var weatherEnabled: Bool
    var weatherIntervalMinutes: Int
    var weatherDurationSeconds: Int
    var quoteEnabled: Bool
    var quoteIntervalMinutes: Int
    var quoteDurationSeconds: Int
    var stockEnabled: Bool
    var stockIntervalMinutes: Int
    var stockDurationSeconds: Int
    var netEnabled: Bool
    var netIntervalMinutes: Int
    var netDurationSeconds: Int

    init(claudeEnabled: Bool, codexEnabled: Bool, approvalEnabled: Bool, musicEnabled: Bool,
         weatherEnabled: Bool, weatherIntervalMinutes: Int, weatherDurationSeconds: Int,
         quoteEnabled: Bool, quoteIntervalMinutes: Int, quoteDurationSeconds: Int,
         stockEnabled: Bool, stockIntervalMinutes: Int, stockDurationSeconds: Int,
         netEnabled: Bool, netIntervalMinutes: Int, netDurationSeconds: Int) {
        self.claudeEnabled = claudeEnabled
        self.codexEnabled = codexEnabled
        self.approvalEnabled = approvalEnabled
        self.musicEnabled = musicEnabled
        self.weatherEnabled = weatherEnabled
        self.weatherIntervalMinutes = weatherIntervalMinutes
        self.weatherDurationSeconds = weatherDurationSeconds
        self.quoteEnabled = quoteEnabled
        self.quoteIntervalMinutes = quoteIntervalMinutes
        self.quoteDurationSeconds = quoteDurationSeconds
        self.stockEnabled = stockEnabled
        self.stockIntervalMinutes = stockIntervalMinutes
        self.stockDurationSeconds = stockDurationSeconds
        self.netEnabled = netEnabled
        self.netIntervalMinutes = netIntervalMinutes
        self.netDurationSeconds = netDurationSeconds
    }

    init(configuration: AutoDisplayConfiguration) {
        let weather = configuration.scheduled[.weather]
        let quote = configuration.scheduled[.quote]
        let stock = configuration.scheduled[.stock]
        let net = configuration.scheduled[.net]
        self.init(
            claudeEnabled: configuration.events[.claude] ?? false,
            codexEnabled: configuration.events[.codex] ?? false,
            approvalEnabled: configuration.events[.approval] ?? false,
            musicEnabled: configuration.events[.music] ?? false,
            weatherEnabled: weather?.enabled ?? false,
            weatherIntervalMinutes: (weather?.intervalSeconds ?? 60) / 60,
            weatherDurationSeconds: weather?.durationSeconds ?? 5,
            quoteEnabled: quote?.enabled ?? false,
            quoteIntervalMinutes: (quote?.intervalSeconds ?? 60) / 60,
            quoteDurationSeconds: quote?.durationSeconds ?? 5,
            stockEnabled: stock?.enabled ?? false,
            stockIntervalMinutes: (stock?.intervalSeconds ?? 60) / 60,
            stockDurationSeconds: stock?.durationSeconds ?? 5,
            netEnabled: net?.enabled ?? false,
            netIntervalMinutes: (net?.intervalSeconds ?? 60) / 60,
            netDurationSeconds: net?.durationSeconds ?? 5
        )
    }

    func configuration() -> AutoDisplayConfiguration {
        func intervalSeconds(_ minutes: Int) -> Int {
            min(240, max(0, minutes)) * 60
        }
        var configuration = AutoDisplayConfiguration(
            events: [
                .claude: claudeEnabled,
                .codex: codexEnabled,
                .approval: approvalEnabled,
                .music: musicEnabled,
            ],
            scheduled: [
                .weather: .init(enabled: weatherEnabled,
                                intervalSeconds: intervalSeconds(weatherIntervalMinutes),
                                durationSeconds: weatherDurationSeconds),
                .quote: .init(enabled: quoteEnabled,
                              intervalSeconds: intervalSeconds(quoteIntervalMinutes),
                              durationSeconds: quoteDurationSeconds),
                .stock: .init(enabled: stockEnabled,
                              intervalSeconds: intervalSeconds(stockIntervalMinutes),
                              durationSeconds: stockDurationSeconds),
                .net: .init(enabled: netEnabled,
                            intervalSeconds: intervalSeconds(netIntervalMinutes),
                            durationSeconds: netDurationSeconds),
            ]
        )
        configuration.normalize()
        return configuration
    }
}

final class AutoDisplaySettingsWindowController: NSWindowController {
    private let store: AutoDisplaySettingsStore

    private let claudeCheckbox = NSButton(checkboxWithTitle: "Claude 工作状态", target: nil, action: nil)
    private let codexCheckbox = NSButton(checkboxWithTitle: "Codex 工作状态", target: nil, action: nil)
    private let approvalCheckbox = NSButton(checkboxWithTitle: "等待确认", target: nil, action: nil)
    private let musicCheckbox = NSButton(checkboxWithTitle: "音乐播放", target: nil, action: nil)

    private let weatherCheckbox = NSButton(checkboxWithTitle: "天气", target: nil, action: nil)
    private let weatherInterval = NSTextField()
    private let weatherDuration = NSTextField()
    private let quoteCheckbox = NSButton(checkboxWithTitle: "名人名言", target: nil, action: nil)
    private let quoteInterval = NSTextField()
    private let quoteDuration = NSTextField()
    private let stockCheckbox = NSButton(checkboxWithTitle: "股票", target: nil, action: nil)
    private let stockInterval = NSTextField()
    private let stockDuration = NSTextField()
    private let netCheckbox = NSButton(checkboxWithTitle: "网速", target: nil, action: nil)
    private let netInterval = NSTextField()
    private let netDuration = NSTextField()

    init(store: AutoDisplaySettingsStore) {
        self.store = store
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 510, height: 410),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "自动显示设置"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.contentView = makeContentView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        load(configuration: store.configuration)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeContentView() -> NSView {
        let content = NSView()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        stack.addArrangedSubview(sectionLabel("事件触发"))
        let events = NSStackView(views: [claudeCheckbox, codexCheckbox, approvalCheckbox, musicCheckbox])
        events.orientation = .horizontal
        events.spacing = 18
        stack.addArrangedSubview(events)

        stack.addArrangedSubview(sectionLabel("定时显示"))
        let header = [NSTextField(labelWithString: "内容"), NSTextField(labelWithString: "间隔（分钟）"),
                      NSTextField(labelWithString: "显示（秒）")]
        let grid = NSGridView(views: [
            header,
            [weatherCheckbox, weatherInterval, weatherDuration],
            [quoteCheckbox, quoteInterval, quoteDuration],
            [stockCheckbox, stockInterval, stockDuration],
            [netCheckbox, netInterval, netDuration],
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 18
        grid.column(at: 0).width = 180
        grid.column(at: 1).width = 120
        grid.column(at: 2).width = 100
        for field in [weatherInterval, weatherDuration, quoteInterval, quoteDuration,
                      stockInterval, stockDuration, netInterval, netDuration] {
            field.alignment = .right
            field.placeholderString = "0"
        }
        for label in header {
            label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            label.textColor = .secondaryLabelColor
        }
        stack.addArrangedSubview(grid)

        let help = NSTextField(wrappingLabelWithString: "间隔范围 1–240 分钟；显示时长范围 5–60 秒。保存时会自动调整超出范围的数值。")
        help.textColor = .secondaryLabelColor
        help.font = NSFont.systemFont(ofSize: 11)
        stack.addArrangedSubview(help)

        let cancel = NSButton(title: "取消", target: self, action: #selector(cancelAction))
        cancel.keyEquivalent = "\u{1b}"
        let save = NSButton(title: "保存", target: self, action: #selector(saveAction))
        save.keyEquivalent = "\r"
        save.bezelStyle = .rounded
        let buttons = NSStackView(views: [cancel, save])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(buttons)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
        ])
        return content
    }

    private func sectionLabel(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    private func load(configuration: AutoDisplayConfiguration) {
        let values = AutoDisplaySettingsFormValues(configuration: configuration)
        claudeCheckbox.state = values.claudeEnabled ? .on : .off
        codexCheckbox.state = values.codexEnabled ? .on : .off
        approvalCheckbox.state = values.approvalEnabled ? .on : .off
        musicCheckbox.state = values.musicEnabled ? .on : .off
        weatherCheckbox.state = values.weatherEnabled ? .on : .off
        weatherInterval.integerValue = values.weatherIntervalMinutes
        weatherDuration.integerValue = values.weatherDurationSeconds
        quoteCheckbox.state = values.quoteEnabled ? .on : .off
        quoteInterval.integerValue = values.quoteIntervalMinutes
        quoteDuration.integerValue = values.quoteDurationSeconds
        stockCheckbox.state = values.stockEnabled ? .on : .off
        stockInterval.integerValue = values.stockIntervalMinutes
        stockDuration.integerValue = values.stockDurationSeconds
        netCheckbox.state = values.netEnabled ? .on : .off
        netInterval.integerValue = values.netIntervalMinutes
        netDuration.integerValue = values.netDurationSeconds
    }

    @objc private func saveAction() {
        let values = AutoDisplaySettingsFormValues(
            claudeEnabled: claudeCheckbox.state == .on,
            codexEnabled: codexCheckbox.state == .on,
            approvalEnabled: approvalCheckbox.state == .on,
            musicEnabled: musicCheckbox.state == .on,
            weatherEnabled: weatherCheckbox.state == .on,
            weatherIntervalMinutes: weatherInterval.integerValue,
            weatherDurationSeconds: weatherDuration.integerValue,
            quoteEnabled: quoteCheckbox.state == .on,
            quoteIntervalMinutes: quoteInterval.integerValue,
            quoteDurationSeconds: quoteDuration.integerValue,
            stockEnabled: stockCheckbox.state == .on,
            stockIntervalMinutes: stockInterval.integerValue,
            stockDurationSeconds: stockDuration.integerValue,
            netEnabled: netCheckbox.state == .on,
            netIntervalMinutes: netInterval.integerValue,
            netDurationSeconds: netDuration.integerValue
        )
        let configuration = values.configuration()
        guard store.save(configuration) else {
            let alert = NSAlert()
            alert.messageText = "无法保存设置"
            alert.informativeText = "自动显示设置未能写入，请重试。"
            alert.runModal()
            return
        }
        window?.close()
        DeviceClient.fetchInfo { result in
            guard case let .success(info) = result,
                  DeviceClient.supportsAutoDisplayConfiguration(
                    firmwareVersion: info.firmwareVersion
                  ) == false else { return }
            let alert = NSAlert()
            alert.messageText = "设备固件需要更新"
            alert.informativeText = "设置已保存在这台 Mac 上，但当前设备固件 \(info.firmwareVersion) 不支持自动显示配置和名人名言。请升级到 v0.4.13 或更高版本。"
            alert.addButton(withTitle: "知道了")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    @objc private func cancelAction() {
        window?.close()
    }
}
