import XCTest
@testable import HTSCore

/** The McSkill launcher's path rules, as the Android app checked them against the PC launcher. */
final class PathRulesTests: XCTestCase {
    func testPrefix() {
        XCTAssertTrue(PathRules.under("mods", "mods"))
        XCTAssertTrue(PathRules.under("mods/x.jar", "mods/"))
        XCTAssertFalse(PathRules.under("modsx/x.jar", "mods"))
    }

    func testManaged() {
        let include = ["mods", "config", "libraries"]
        let exclude = ["config/optifine", "mods/user"]
        XCTAssertTrue(PathRules.managed("mods/a.jar", include: include, exclude: exclude))
        XCTAssertFalse(PathRules.managed("mods/user/b.jar", include: include, exclude: exclude))
        XCTAssertFalse(PathRules.managed("options.txt", include: include, exclude: exclude))
        XCTAssertFalse(PathRules.managed("config/optifine/x.cfg", include: include, exclude: exclude))
    }

    func testDesktopOnly() {
        XCTAssertTrue(PathRules.desktopOnly("natives/lwjgl.dll"))
        XCTAssertTrue(PathRules.desktopOnly("libraries/lwjgl-glfw-natives-windows.jar"))
        XCTAssertTrue(PathRules.desktopOnly("libraries/ffmpeg-8.0.1-1.5.13-windows-x86_64.jar"))
        XCTAssertTrue(PathRules.desktopOnly("libraries/x/libfoo.dylib"))
        XCTAssertFalse(PathRules.desktopOnly("libraries/lwjgl-glfw.jar"))
        XCTAssertFalse(PathRules.desktopOnly("mods/natives-mod.jar"))
    }

    func testNormalize() {
        XCTAssertEqual(PathRules.normalize(#"\mods\a.jar"#), "mods/a.jar")
        XCTAssertNil(PathRules.normalize("mods/../../etc/passwd"))
        XCTAssertNil(PathRules.normalize(""))
        XCTAssertNil(PathRules.normalize("a//b"))
    }

    func testFolderName() {
        XCTAssertEqual(try ClientStore.folderName("Industrial_1.7.10"), "Industrial_1.7.10")
        XCTAssertThrowsError(try ClientStore.folderName("../x"))
        XCTAssertThrowsError(try ClientStore.folderName(".hidden"))
    }
}
