# hts-lwjgl-patch (iOS)

Copied from the Android project (`lwjgl-patch/`, `glbaton/`): LWJGL 3.4.1's `SDLVideo` with the HTS
hooks, goes first on the game classpath of SDL packs (lwjgl3ify 3).

- `HtsGLAttributes`: the GL context lwjgl3ify asks for (desktop 2.1) becomes the one ANGLE makes
  (ES 3.0, env `HTS_GL_PROFILE/MAJOR/MINOR`); GL lookups go to gl4es first (`HTS_GL_PROC_LIB`).
- `HtsSurface`: frame pacing; its Android frame-state file (`HTS_FRAME_STATE`) is not set on iOS.
- `HtsGLBaton`: one GL context shared with the loading screen (`HTS_GL_SPLASH=1`), off for now.

Android's `ThreadLocalUtil` is left out: there it lays the GL function table out for natives built
from other sources than the jars; the iOS natives and jars come from one build (release deps-1).
Built by CI: `javac --release 8` against the LWJGL 3.4.1 jars and jspecify.
