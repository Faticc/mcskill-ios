import HTSCore
import SwiftUI

/** "АВТОРИЗАЦИЯ": McSkill login with Telegram (MFA) and authenticator (TOTP) confirmation. */
struct LoginView: View {
    @EnvironmentObject private var model: AppModel

    @State private var username = ""
    @State private var password = ""
    @State private var busy = false
    @State private var errorText: String?

    @State private var showMfa = false
    @State private var mfaNotConfirmed = false
    @State private var showTotp = false
    @State private var totpCode = ""
    @State private var totpError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("АВТОРИЗАЦИЯ")
                    .font(.system(size: 20, weight: .bold))
                    .kerning(1)
                    .foregroundStyle(Theme.text)
                    .padding(.bottom, 4)
                Field(icon: "person", placeholder: "Никнейм", text: $username)
                    .textContentType(.username)
                Field(icon: "lock", placeholder: "Пароль", text: $password, secure: true)
                    .textContentType(.password)
                if let errorText {
                    Text(errorText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.red)
                }
                Button(busy ? "Подключение…" : "Войти") { submit() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(busy)
                    .opacity(busy ? 0.6 : 1)
                    .padding(.top, 4)
            }
            .padding(22)
            .card()
            .frame(maxWidth: 420)
            .padding(.horizontal, 16)
            .padding(.top, 80)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: $showMfa) {
            ConfirmSheet(title: "Подтверждение 2FA",
                         text: "Мы отправили вам запрос на подтверждение входа. Подтвердите его, чтобы продолжить") {
                if mfaNotConfirmed {
                    Text("Подтверждение не выполнено")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.red)
                }
                Button(busy ? "Проверяем…" : "Продолжить") {
                    mfaNotConfirmed = false
                    submit()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy)
            }
            .presentationDetents([.height(250)])
        }
        .sheet(isPresented: $showTotp) {
            ConfirmSheet(title: "Подтверждение 2FA",
                         text: "Введите код из приложения-аутентификатора, чтобы продолжить вход") {
                Field(icon: "key", placeholder: "000000", text: $totpCode)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                if let totpError {
                    Text(totpError)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.red)
                }
                Button(busy ? "Проверяем…" : "Подтвердить") {
                    let code = totpCode.trimmingCharacters(in: .whitespaces)
                    guard !code.isEmpty else { return }
                    totpError = nil
                    submit(totp: code)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(busy)
            }
            .presentationDetents([.height(300)])
        }
    }

    /** One login call; a confirmation window that is open gets the outcome. */
    private func submit(totp: String? = nil) {
        guard !busy else { return }
        let name = username.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !password.isEmpty else {
            errorText = "Введите никнейм и пароль"
            return
        }
        errorText = nil
        busy = true
        Task {
            defer { busy = false }
            do {
                switch try await McSkillAPI.shared.login(username: name, password: password, totp: totp) {
                case .session(let session):
                    showMfa = false
                    showTotp = false
                    password = ""
                    model.signedIn(session)
                case .mfaRequired:
                    if showMfa { mfaNotConfirmed = true } else { showMfa = true }
                case .totpRequired:
                    if showTotp {
                        totpError = "Неверный код. Попробуйте ещё раз"
                    } else {
                        totpCode = ""
                        showTotp = true
                    }
                }
            } catch {
                let e = McSkillError.from(error)
                AppLog.error("Login failed: \(e.code) \(e.message ?? "")")
                if showTotp {
                    totpError = e.localizedDescription
                } else {
                    showMfa = false
                    errorText = e.localizedDescription
                }
            }
        }
    }
}

/** Bottom sheet of the 2FA steps. */
struct ConfirmSheet<Content: View>: View {
    let title: String
    let text: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title.uppercased())
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Theme.text)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text2)
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.panel.ignoresSafeArea())
    }
}
