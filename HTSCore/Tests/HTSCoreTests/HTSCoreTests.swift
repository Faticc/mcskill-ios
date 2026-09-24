import GRPC
import XCTest
@testable import HTSCore

final class ErrorMappingTests: XCTestCase {
    private func map(_ code: GRPCStatus.Code, _ message: String? = nil) -> McSkillError.Code {
        McSkillError.from(GRPCStatus(code: code, message: message)).code
    }

    func testNetworkCodes() {
        XCTAssertEqual(map(.unavailable), .networkUnavailable)
        XCTAssertEqual(map(.deadlineExceeded), .networkUnavailable)
        XCTAssertEqual(map(.cancelled), .networkUnavailable)
    }

    func testPermissionDeniedTellsBanFromPassword() {
        XCTAssertEqual(map(.permissionDenied, "Аккаунт заблокирован до 01.01"), .banned)
        XCTAssertEqual(map(.permissionDenied, "User is banned"), .banned)
        XCTAssertEqual(map(.permissionDenied, "Неверный пароль"), .invalidCredentials)
        XCTAssertEqual(map(.permissionDenied), .invalidCredentials)
    }

    func testOtherCodes() {
        XCTAssertEqual(map(.unauthenticated), .unauthenticated)
        XCTAssertEqual(map(.notFound), .userNotFound)
        XCTAssertEqual(map(.resourceExhausted), .rateLimited)
        XCTAssertEqual(map(.invalidArgument), .invalidCredentials)
        XCTAssertEqual(map(.failedPrecondition), .actionRequired)
        XCTAssertEqual(map(.internalError), .unknown)
    }

    func testRussianTexts() {
        XCTAssertEqual(McSkillError(code: .banned).localizedDescription, "Аккаунт заблокирован")
        XCTAssertEqual(McSkillError(code: .actionRequired, message: "Примите соглашение").localizedDescription,
                       "Примите соглашение")
        XCTAssertEqual(McSkillError(code: .unknown, message: "").localizedDescription, "Неизвестная ошибка")
    }
}

final class FormatTests: XCTestCase {
    func testWipeDate() {
        let utc = TimeZone(identifier: "UTC")!
        XCTAssertEqual(Format.wipeDate("1700000000", timeZone: utc), "14.11.2023")
        XCTAssertEqual(Format.wipeDate(" 0 ", timeZone: utc), "—")
        XCTAssertEqual(Format.wipeDate("", timeZone: utc), "—")
        XCTAssertEqual(Format.wipeDate("скоро", timeZone: utc), "скоро")
    }

    func testModsPlural() {
        XCTAssertEqual(Format.mods(1), "1 мод")
        XCTAssertEqual(Format.mods(3), "3 мода")
        XCTAssertEqual(Format.mods(5), "5 модов")
        XCTAssertEqual(Format.mods(11), "11 модов")
        XCTAssertEqual(Format.mods(12), "12 модов")
        XCTAssertEqual(Format.mods(21), "21 мод")
        XCTAssertEqual(Format.mods(141), "141 мод")
        XCTAssertEqual(Format.mods(22), "22 мода")
    }
}

/**
 * The real server over TLS + HTTP/2 + gRPC with a made-up session: checks the whole transport
 * without an account. Skipped (not failed) when the runner cannot reach McSkill at all.
 */
final class LiveAPITests: XCTestCase {
    func testServerAnswersOverGRPC() async throws {
        if ProcessInfo.processInfo.environment["HTS_SKIP_LIVE"] != nil { throw XCTSkip("HTS_SKIP_LIVE") }
        let api = McSkillAPI()
        do {
            let servers = try await api.servers(session: "hts-ios-ci-invalid-session")
            print("LIVE: \(servers.count) servers without a valid session")
        } catch let e as McSkillError {
            print("LIVE: server answered \(e.code) \(e.message ?? "")")
            if e.code == .networkUnavailable {
                throw XCTSkip("McSkill unreachable from the runner: \(e.message ?? "")")
            }
        }
    }
}
