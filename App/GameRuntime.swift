import Foundation
import HTSCore

/**
 * What the game runs on, as CI lays it out in the app (scripts/pack-game-libs.sh):
 * Frameworks/ — SDL3 (ours, ANGLE EGL + main-thread UIKit), ANGLE's libEGL/libGLESv2, gl4es,
 * OpenAL, LWJGL 3.4.1 natives; game/lwjgl-3.4.1/ — the matching LWJGL jars.
 */
enum GameRuntime {
    static let frameworks = Bundle.main.bundleURL.appendingPathComponent("Frameworks", isDirectory: true)
    static let gameDir = Bundle.main.bundleURL.appendingPathComponent("game", isDirectory: true)
    static let lwjglDir = gameDir.appendingPathComponent("lwjgl-3.4.1", isDirectory: true)

    static var sdl: URL { frameworks.appendingPathComponent("libSDL3.dylib") }
    static var gl4es: URL { frameworks.appendingPathComponent("libgl4es_114.dylib") }
    static var egl: URL { frameworks.appendingPathComponent("libEGL.framework/libEGL") }
    static var gles: URL { frameworks.appendingPathComponent("libGLESv2.framework/libGLESv2") }
    static var openal: URL { frameworks.appendingPathComponent("libopenal.dylib") }

    static var installed: Bool {
        FileManager.default.fileExists(atPath: sdl.path) && FileManager.default.fileExists(atPath: gl4es.path)
    }

    static func jars(in dir: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { $0.hasSuffix(".jar") }.sorted().map { dir.appendingPathComponent($0).path }
    }

    /** JVM options every LWJGL/SDL program here needs: where the natives and the renderer are. */
    static var lwjglJvmArgs: [String] {
        [
            "-Djava.library.path=\(frameworks.path)",
            "-Dorg.lwjgl.librarypath=\(frameworks.path)",
            "-Dorg.lwjgl.sdl.libname=\(sdl.path)",
            "-Dorg.lwjgl.opengl.libname=\(gl4es.path)",
            "-Dorg.lwjgl.openal.libname=\(openal.path)",
            "-Dorg.lwjgl.system.allocator=system",
        ]
    }

    /** Environment for SDL (sdl/SDL_uikit_hts.m) and gl4es, as Amethyst sets it up. */
    static var environment: [String: String] {
        [
            "HTS_SDL_LIBRARY": sdl.path,
            "HTS_EGL_LIBRARY": egl.path,
            "HTS_GLES_LIBRARY": gles.path,
            "HTS_GL_LIBRARY": gl4es.path,
            // gl4es: no int overloads hack for 1.17+ (Amethyst), normalize fixes white banners/sheep
            "LIBGL_NOINTOVLHACK": "1",
            "LIBGL_NORMALIZE": "1",
        ]
    }

    static let glTestReport = AppLog.fileURL.deletingLastPathComponent().appendingPathComponent("gltest.json")

    /**
     * The render path without a game: an SDL window, ANGLE, gl4es, a spinning triangle
     * (tests/gltest). CI runs it in the simulator with `--gltest`.
     */
    static func runGLTest(runtime: JavaRuntime) throws {
        try? FileManager.default.removeItem(at: glTestReport)
        try? FileManager.default.removeItem(at: JavaRuntimes.logURL)
        let classpath = (jars(in: lwjglDir) + [gameDir.appendingPathComponent("tests/gltest.jar").path])
            .joined(separator: ":")
        AppLog.info("GL test on \(runtime.title)")
        try HTSJava.launch(javaHome: runtime.home.path, heapMb: 256,
                                   jvmArgs: ["-Djava.class.path=\(classpath)"] + lwjglJvmArgs,
                                   mainClass: "HtsGLTest", args: [glTestReport.path],
                                   environment: environment, log: JavaRuntimes.logURL.path)
        // The touch controls over the test window: the screenshot shows them on SDL's window
        HTSControls.start(withSDL: sdl.path, gameDir: ClientStore.documents.path)
    }
}
