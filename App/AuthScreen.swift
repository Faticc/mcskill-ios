import HTSCore
import SwiftUI

/** "АВТОРИЗАЦИЯ": McSkill login with Telegram (MFA) and authenticator (TOTP) confirmation. */
struct AuthScreen: View {
    private static let site = "https://mcskill.net/"

    @ObservedObject var flow: LoginFlow
    @State private var username = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var remember = !Prefs.forgetAccount

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                ScrollView {
                    card
                        .frame(width: min(380, geo.size.width - 32))
                        .frame(maxWidth: .infinity, minHeight: max(0, geo.size.height - 60))
                        .padding(.top, 44)
                        .padding(.bottom, 16)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
                Text("McSkill")
                    .font(Theme.bold(18))
                    .foregroundStyle(Theme.text)
                    .padding(.leading, 20)
                    .padding(.top, 14)
            }
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            Caps(text: "Авторизация", size: 20, color: Theme.text)
                .frame(maxWidth: .infinity)
            RoundedRectangle(cornerRadius: 1)
                .fill(Theme.accent)
                .frame(width: 44, height: 2)
                .padding(.top, 10)
                .padding(.bottom, 16)
            FieldBox(icon: "ic_user", placeholder: "Никнейм", text: $username)
                .textContentType(.username)
                .submitLabel(.next)
                .frame(height: 46)
            FieldBox(icon: "ic_lock", placeholder: "Пароль", text: $password, secure: !showPassword) {
                Button { showPassword.toggle() } label: {
                    Icon(showPassword ? "ic_eye_off" : "ic_eye", Theme.text3, 18)
                }
                .buttonStyle(.plain)
            }
            .textContentType(.password)
            .submitLabel(.done)
            .onSubmit(submit)
            .frame(height: 46)
            .padding(.top, 10)
            HStack(spacing: 0) {
                Switch(isOn: $remember)
                Text("Запомнить меня")
                    .font(Theme.medium(13))
                    .foregroundStyle(Theme.text2)
                    .padding(.leading, 10)
                    .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { remember.toggle() } }
                Spacer(minLength: 8)
                Text("Забыли пароль? ")
                    .font(Theme.regular(12))
                    .foregroundStyle(Theme.text3)
                Text("Восстановить")
                    .font(Theme.semibold(12))
                    .foregroundStyle(Theme.accent)
                    .onTapGesture { Platform.open(Self.site) }
            }
            .padding(.top, 14)
            PrimaryButton(label: flow.busy ? "Подключение…" : "Войти", fill: true, action: submit)
                .frame(height: 48)
                .opacity(flow.busy ? 0.7 : 1)
                .padding(.top, 18)
            if let error = flow.error {
                Text(error)
                    .font(Theme.medium(12))
                    .foregroundStyle(Theme.red)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
            }
            HStack(spacing: 0) {
                Text("Нет аккаунта? ")
                    .font(Theme.regular(12))
                    .foregroundStyle(Theme.text3)
                Text("Создать")
                    .font(Theme.semibold(12))
                    .foregroundStyle(Theme.accent)
                    .onTapGesture { Platform.open(Self.site) }
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .box(Color(argb: 0xF21F2024), radius: 16, border: Theme.panelBorder)
    }

    private func submit() {
        flow.submit(username: username, password: password, remember: remember)
    }
}

/** Telegram confirmation: the player approves the login there, then presses "Продолжить". */
struct MfaModal: View {
    @ObservedObject var flow: LoginFlow
    let retry: () -> Void

    var body: some View {
        ModalCard("Подтверждение 2FA") {
            ModalText("Мы отправили вам запрос на подтверждение входа. Подтвердите его, чтобы продолжить")
            if flow.mfaNotConfirmed {
                Text("Подтверждение не выполнено")
                    .font(Theme.medium(12))
                    .foregroundStyle(Theme.red)
            }
        } footer: {
            ModalPrimary(label: "Продолжить", closes: false) {
                flow.mfaNotConfirmed = false
                retry()
            }
            .opacity(flow.busy ? 0.6 : 1)
        }
    }
}

/** Code of an authenticator app. */
struct TotpModal: View {
    @ObservedObject var flow: LoginFlow
    let submit: (String) -> Void
    @State private var code = ""

    var body: some View {
        ModalCard("Подтверждение 2FA") {
            ModalText("Введите код из приложения-аутентификатора, чтобы продолжить вход")
            FieldBox(icon: "ic_key", placeholder: "000000", text: $code, font: Theme.medium(20),
                     alignment: .center, keyboard: .numberPad)
                .textContentType(.oneTimeCode)
                .frame(height: 50)
                .onChange(of: code) { value in
                    if value.count > 8 { code = String(value.prefix(8)) }
                }
            if let error = flow.totpError {
                Text(error)
                    .font(Theme.medium(12))
                    .foregroundStyle(Theme.red)
                    .padding(.top, 8)
            }
        } footer: {
            ModalPrimary(label: flow.busy ? "Проверяем…" : "Подтвердить", closes: false) {
                let value = code.trimmingCharacters(in: .whitespaces)
                guard !value.isEmpty else { return }
                flow.totpError = nil
                submit(value)
            }
        }
    }
}
