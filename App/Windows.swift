import HTSCore
import SwiftUI

/** "Настройки": the basic tab as on the PC (memory, glow), the advanced one for the runtime. */
struct SettingsModal: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismissModal) private var dismiss

    @State private var settings = LaunchSettings.load()
    @State private var memoryAuto = Prefs.memoryAuto
    @State private var ramText = String(LaunchSettings.load().ramMb)
    @State private var ramError: String?
    @State private var glow = Prefs.glow
    @State private var debug = Prefs.debug
    @State private var advanced: Bool

    init(advanced: Bool = false) {
        _advanced = State(initialValue: advanced)
    }

    var body: some View {
        ModalCard("Настройки") {
            HStack(spacing: 0) {
                tab("Основные", on: !advanced) { advanced = false }
                tab("Продвинутые", on: advanced) { advanced = true }
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 9).fill(Theme.tile))
            if advanced { advancedTab } else { basicTab }
        } footer: {
            ModalPrimary(label: "Сохранить", closes: false, action: save)
        }
    }

    private func tab(_ label: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(Theme.semibold(13))
                .foregroundStyle(on ? Theme.text : Theme.text2)
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 7).fill(on ? Theme.panel : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }

    // MARK: - basic

    private var basicTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            group("ic_cpu", "Выделение памяти:") {
                Choices(labels: ["Авто", "Вручную"], selected: memoryAuto ? 0 : 1) { index in
                    memoryAuto = index == 0
                    ramError = nil
                }
                if memoryAuto {
                    Text("Рекомендуем автоматический режим — он подбирает оптимальный объём памяти для каждого клиента.")
                        .font(Theme.regular(12))
                        .foregroundStyle(Theme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                } else {
                    HStack(spacing: 0) {
                        FieldBox(icon: nil, placeholder: "4096", text: $ramText, keyboard: .numberPad) {
                            Text("MB")
                                .font(Theme.semibold(12))
                                .foregroundStyle(Theme.text3)
                        }
                        .frame(width: 140, height: 38)
                        Text("из \(LaunchSettings.deviceRamMb) MB")
                            .font(Theme.medium(12))
                            .foregroundStyle(Theme.text3)
                            .padding(.leading, 10)
                    }
                    .padding(.top, 10)
                    if let ramError {
                        Text(ramError)
                            .font(Theme.medium(11))
                            .foregroundStyle(Theme.red)
                            .padding(.top, 6)
                    }
                }
            }
            group("ic_monitor", "Разрешение рендера") {
                Choices(labels: LaunchSettings.scales.map { "\(Int(($0 * 100).rounded()))%" },
                        selected: LaunchSettings.scales.firstIndex(where: { abs($0 - settings.scale) < 0.01 }) ?? 0) {
                    settings.scale = LaunchSettings.scales[$0]
                }
            }
            group("ic_zap", "FPS свёрнутой игры") {
                let choices = LaunchSettings.backgroundFpsChoices
                Choices(labels: choices.map { $0 > 0 ? String($0) : "Без ограничения" },
                        selected: choices.firstIndex(of: settings.backgroundFps) ?? choices.count - 1) {
                    settings.backgroundFps = choices[$0]
                }
            }
            toggleRow("Экран загрузки как на ПК",
                      "Родной экран загрузки сборки (MetaStart и др.) вместо экрана лаунчера", $settings.forgeSplash)
            toggleRow("Фоновое свечение", nil, $glow)
            toggleRow("Режим отладки", "Код выхода и лог после закрытия игры", $debug)
        }
    }

    // MARK: - advanced

    private var advancedTab: some View {
        let renderer = Renderer(rawValue: settings.renderer) ?? .gl4es
        return VStack(alignment: .leading, spacing: 0) {
            javaGroup
            group("ic_monitor", "Рендер") {
                Choices(labels: Renderer.allCases.map(\.title),
                        selected: Renderer.allCases.firstIndex(of: renderer) ?? 0) {
                    settings.renderer = Renderer.allCases[$0].rawValue
                }
            }
            group("ic_cpu", "Драйвер Vulkan (для ANGLE/Zink)") {
                Choices(labels: ["Системный"], selected: 0) { _ in }
                    .opacity(renderer.usesVulkan ? 1 : 0.5)
                HStack(spacing: 8) {
                    SecondaryButton(label: "Импорт") { model.overlay.toast("На iOS драйвер видеочипа заменить нельзя") }
                    SecondaryButton(label: "Проверить") { model.overlay.toast("Vulkan на iOS — MoltenVK поверх Metal") }
                    SecondaryButton(label: "Удалить") {}
                }
                .frame(height: 34)
                .padding(.top, 10)
            }
            toggleRow("Turbo GPU", "Держать частоты видеочипа (только Adreno)", $settings.turbo)
                .opacity(0.5)
                .disabled(true)
            group("ic_sliders", "Доп. аргументы JVM") {
                FieldBox(icon: nil, placeholder: "-Dkey=value ...", text: $settings.extraJvmArgs,
                         font: .system(size: 14, design: .monospaced))
                    .frame(height: 40)
            }
            group("ic_hard_drive", "Файлы") {
                HStack(spacing: 8) {
                    SecondaryButton(label: "Папка клиентов") { model.openClientsFolder() }
                    SecondaryButton(label: "Скрипт JIT") {
                        if !Platform.openInFiles(JavaRuntimes.jitScriptFolder) {
                            model.overlay.toast("Не удалось открыть «Файлы»")
                        }
                    }
                }
                .frame(height: 34)
            }
        }
    }

    /** JIT state and the bundled runtimes, each can be started once per app launch to test it. */
    private var javaGroup: some View {
        let jit = model.jit
        return group("ic_zap", "Java") {
            HStack(spacing: 8) {
                Circle()
                    .fill(jit.enabled ? Theme.green : Theme.red)
                    .frame(width: 8, height: 8)
                Text(jit.title)
                    .font(Theme.semibold(13))
                    .foregroundStyle(Theme.text)
                if !jit.details.isEmpty {
                    Text(jit.details)
                        .font(Theme.medium(12))
                        .foregroundStyle(Theme.text3)
                }
            }
            Text(jit.hint)
                .font(Theme.regular(12))
                .foregroundStyle(Theme.text3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            let runtimes = model.javaRuntimes
            if runtimes.isEmpty {
                Text("В этой сборке нет встроенной Java")
                    .font(Theme.medium(12))
                    .foregroundStyle(Theme.red)
                    .padding(.top, 10)
            }
            ForEach(runtimes) { runtime in
                HStack(spacing: 10) {
                    Text(runtime.title)
                        .font(Theme.semibold(13))
                        .foregroundStyle(Theme.text)
                    Text(runtime.version)
                        .font(Theme.medium(12))
                        .foregroundStyle(Theme.text3)
                    Spacer(minLength: 0)
                    SecondaryButton(label: "Проверить") {
                        dismiss()
                        model.probeJava(runtime)
                    }
                    .frame(width: 130, height: 32)
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
                .box(Theme.field, radius: 9, border: Theme.fieldBorder)
                .padding(.top, 8)
            }
        }
    }

    // MARK: - building blocks

    private func group<Content: View>(_ icon: String, _ title: String,
                                      @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Icon(icon, Theme.accent, 15)
                Text(title)
                    .font(Theme.semibold(13))
                    .foregroundStyle(Theme.text)
            }
            .padding(.bottom, 10)
            content()
        }
        .padding(.top, 18)
    }

    private func toggleRow(_ title: String, _ hint: String?, _ value: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.semibold(13))
                    .foregroundStyle(Theme.text)
                if let hint {
                    Text(hint)
                        .font(Theme.regular(11))
                        .foregroundStyle(Theme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Switch(isOn: value)
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { value.wrappedValue.toggle() } }
        .padding(.top, 18)
    }

    private func save() {
        if !memoryAuto {
            let text = ramText.trimmingCharacters(in: .whitespaces)
            let max = LaunchSettings.deviceRamMb - 1024
            var error: String?
            var ram = 0
            if text.isEmpty {
                error = "Введите MB"
            } else if let value = Int(text) {
                ram = value
                if ram < 1024 { error = "Минимум 1024 MB" } else if ram > max { error = "Максимум \(max) MB" }
            } else {
                error = "Только число"
            }
            if let error {
                ramError = error
                return
            }
            settings.ramMb = ram
        }
        Prefs.memoryAuto = memoryAuto
        settings.save()
        Prefs.glow = glow
        model.glow = glow
        Prefs.debug = debug
        dismiss()
        model.overlay.toast("Настройки сохранены")
    }
}

/** "Помощь с клиентом": the log, sharing it, a full file check on the next start. */
struct HelpModal: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismissModal) private var dismiss
    let server: ServerInfo

    var body: some View {
        ModalCard("Помощь с клиентом") {
            ModalText("Возникла проблема с клиентом? Посмотрите лог последнего запуска или отправьте его в поддержку. "
                + "Полная проверка перечитает все файлы клиента и докачает повреждённые.")
            HStack(spacing: 8) {
                SecondaryButton(label: "Лог") { model.showLog() }
                SecondaryButton(label: "Поделиться логом") { model.shareLog() }
            }
            .frame(height: 36)
            Text("Проверить все файлы при следующем запуске")
                .font(Theme.semibold(13))
                .foregroundStyle(Theme.accent)
                .padding(.top, 14)
                .onTapGesture {
                    Prefs.setFullCheck(server.id, true)
                    dismiss()
                    model.overlay.toast("Файлы \(server.title) будут проверены полностью")
                }
            if Prefs.debug {
                Text("ID \(server.id) · \(DeviceInfo.machine)")
                    .font(Theme.regular(11))
                    .foregroundStyle(Theme.text3)
                    .padding(.top, 12)
            }
        }
    }
}

/** "Список модов": all of them, with the main and custom tags. */
struct ModsModal: View {
    let server: ServerInfo

    var body: some View {
        let mods = server.mods.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        ModalCard("Список модов") {
            ModalText("\(Format.mods(mods.count)) на сервере \(server.title)")
            ForEach(Array(mods.enumerated()), id: \.offset) { _, mod in
                HStack(spacing: 0) {
                    Text(mod.name)
                        .font(Theme.medium(13))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    ForEach(mod.tags.filter { $0 == "main" || $0 == "custom" }, id: \.self) { tag in
                        let main = tag == "main"
                        let color = main ? Theme.accent : Theme.gold
                        Text(main ? "основной" : "авторский")
                            .font(Theme.semibold(10))
                            .foregroundStyle(color)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 5).fill(color.opacity(0x22 / 255.0)))
                            .padding(.leading, 6)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.tile))
                .padding(.bottom, 6)
            }
        }
    }
}
