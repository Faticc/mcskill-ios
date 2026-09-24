package org.lwjgl.sdl;

import static org.lwjgl.system.JNI.invokeZ;

/**
 * Maps the GL context lwjgl3ify asks SDL for onto one the selected Android renderer can create.
 *
 * lwjgl3ify requests a desktop "2.1" context without a profile. SDL built for Android defaults to
 * the ES profile, so that turns into "OpenGL ES 2.1", which EGL rejects with EGL_BAD_MATCH on
 * strict drivers. The launcher describes the right context through environment variables:
 * <ul>
 *   <li>HTS_GL_PROFILE: es | compat | core (unset = leave SDL defaults)</li>
 *   <li>HTS_GL_MAJOR / HTS_GL_MINOR: context version to force</li>
 *   <li>HTS_GL_NO_SHARE=1: never ask for a shared context (Android has one window)</li>
 *   <li>HTS_GL_NO_SRGB=1: drop sRGB framebuffer requests</li>
 * </ul>
 */
final class HtsGLAttributes {
    private static final int SDL_GL_CONTEXT_MAJOR_VERSION = 17;
    private static final int SDL_GL_CONTEXT_MINOR_VERSION = 18;
    private static final int SDL_GL_CONTEXT_FLAGS = 19;
    private static final int SDL_GL_CONTEXT_PROFILE_MASK = 20;
    private static final int SDL_GL_SHARE_WITH_CURRENT_CONTEXT = 21;
    private static final int SDL_GL_FRAMEBUFFER_SRGB_CAPABLE = 22;

    private static final int SDL_GL_CONTEXT_DEBUG_FLAG = 0x1;
    private static final int SDL_GL_CONTEXT_FORWARD_COMPATIBLE_FLAG = 0x2;

    private static final int PROFILE = profileMask(System.getenv("HTS_GL_PROFILE"));
    private static final int MAJOR = parse(System.getenv("HTS_GL_MAJOR"));
    private static final int MINOR = parse(System.getenv("HTS_GL_MINOR"));
    private static final boolean NO_SHARE = "1".equals(System.getenv("HTS_GL_NO_SHARE"));
    private static final boolean NO_SRGB = "1".equals(System.getenv("HTS_GL_NO_SRGB"));

    /**
     * HTS_GL_PROC_LIB: library whose glXGetProcAddress answers GL lookups before SDL. SDL asks
     * eglGetProcAddress first when EGL >= 1.5 (Adreno), which hands LWJGL the driver's raw GLES
     * entry points instead of the desktop GL of gl4es, so nothing the game draws is translated.
     */
    private static final String PROC_LIB = System.getenv("HTS_GL_PROC_LIB");
    private static long glXGetProcAddress = -1;

    private HtsGLAttributes() {}

    static long procAddress(long name) {
        if (PROC_LIB == null || PROC_LIB.isEmpty()) return 0L;
        if (glXGetProcAddress == -1) {
            long fn = 0L;
            try {
                fn = org.lwjgl.system.Library.loadNative(HtsGLAttributes.class, "org.lwjgl.opengl", PROC_LIB)
                        .getFunctionAddress("glXGetProcAddress");
            } catch (Throwable t) {
                System.out.println("[HTS] Cannot use " + PROC_LIB + " for GL lookups: " + t);
            }
            glXGetProcAddress = fn;
            System.out.println("[HTS] GL functions from " + PROC_LIB + (fn != 0L ? "" : " unavailable, using SDL"));
        }
        return glXGetProcAddress == 0L ? 0L : org.lwjgl.system.JNI.invokePP(name, glXGetProcAddress);
    }

    static void afterReset(long setAttribute) {
        if (PROFILE >= 0) invokeZ(SDL_GL_CONTEXT_PROFILE_MASK, PROFILE, setAttribute);
        if (MAJOR >= 0) invokeZ(SDL_GL_CONTEXT_MAJOR_VERSION, MAJOR, setAttribute);
        if (MINOR >= 0) invokeZ(SDL_GL_CONTEXT_MINOR_VERSION, MINOR, setAttribute);
    }

    static int filter(int attr, int value) {
        int result = value;
        switch (attr) {
            case SDL_GL_CONTEXT_MAJOR_VERSION:
                if (MAJOR >= 0) result = MAJOR;
                break;
            case SDL_GL_CONTEXT_MINOR_VERSION:
                if (MINOR >= 0) result = MINOR;
                break;
            case SDL_GL_CONTEXT_PROFILE_MASK:
                if (PROFILE >= 0) result = PROFILE;
                break;
            case SDL_GL_CONTEXT_FLAGS:
                // Forward-compatible/debug flags are desktop-only notions for ES contexts
                if (PROFILE == 4) result = value & ~(SDL_GL_CONTEXT_FORWARD_COMPATIBLE_FLAG | SDL_GL_CONTEXT_DEBUG_FLAG);
                break;
            case SDL_GL_SHARE_WITH_CURRENT_CONTEXT:
                if (NO_SHARE) result = 0;
                break;
            case SDL_GL_FRAMEBUFFER_SRGB_CAPABLE:
                if (NO_SRGB) result = 0;
                break;
            default:
                break;
        }
        if (result != value) {
            System.out.println("[HTS] SDL_GL_SetAttribute(" + attr + ", " + value + ") -> " + result);
        }
        return result;
    }

    private static int profileMask(String name) {
        if (name == null) return -1;
        switch (name) {
            case "core": return 1;
            case "compat": return 2;
            case "es": return 4;
            default: return -1;
        }
    }

    private static int parse(String value) {
        if (value == null || value.isEmpty()) return -1;
        try {
            return Integer.parseInt(value.trim());
        } catch (NumberFormatException e) {
            return -1;
        }
    }
}
