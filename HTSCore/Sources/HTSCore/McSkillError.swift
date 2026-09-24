import Foundation
import GRPC

/** An API failure, classified the way the McSkill launcher reports it. */
public struct McSkillError: Error, LocalizedError, Equatable {
    public enum Code: Equatable {
        case networkUnavailable
        case unauthenticated
        case invalidCredentials
        case userNotFound
        case banned
        case rateLimited
        /** The account must confirm its e-mail or accept an updated agreement on the site. */
        case actionRequired
        case mfaRequired
        case unknown
    }

    public let code: Code
    public let message: String?

    public init(code: Code, message: String? = nil) {
        self.code = code
        self.message = message
    }

    public static func from(_ error: Error) -> McSkillError {
        if let e = error as? McSkillError { return e }
        if let t = error as? GRPCStatusTransformable { return from(status: t.makeGRPCStatus()) }
        return McSkillError(code: .unknown, message: String(describing: error))
    }

    public static func from(status: GRPCStatus) -> McSkillError {
        let code: Code
        switch status.code {
        case .unavailable, .deadlineExceeded, .cancelled:
            code = .networkUnavailable
        case .unauthenticated:
            code = .unauthenticated
        case .notFound:
            code = .userNotFound
        case .resourceExhausted:
            code = .rateLimited
        case .permissionDenied:
            // Wrong password and a blocked account both come as PERMISSION_DENIED; the server's
            // text tells them apart
            code = mentions(status.message, ["ban", "блок"]) ? .banned : .invalidCredentials
        case .invalidArgument:
            code = .invalidCredentials
        case .failedPrecondition:
            code = .actionRequired
        default:
            code = .unknown
        }
        return McSkillError(code: code, message: status.message)
    }

    private static func mentions(_ text: String?, _ words: [String]) -> Bool {
        guard let text = text?.lowercased() else { return false }
        return words.contains { text.contains($0) }
    }

    /** Russian text, as the McSkill launcher words it. */
    public var errorDescription: String? {
        let own = message.flatMap { $0.isEmpty ? nil : $0 }
        switch code {
        case .networkUnavailable: return "Сервер недоступен. Проверьте подключение к интернету"
        case .unauthenticated: return "Сессия истекла, войдите заново"
        case .invalidCredentials: return "Неверный пароль"
        case .userNotFound: return "Пользователь не найден"
        case .banned: return "Аккаунт заблокирован"
        case .rateLimited: return "Слишком много попыток. Попробуйте позже"
        case .actionRequired:
            return own ?? "Подтвердите ваш email или примите пользовательское соглашение на сайте"
        case .mfaRequired: return "Требуется подтверждение входа 2FA"
        case .unknown: return own ?? "Неизвестная ошибка"
        }
    }
}
