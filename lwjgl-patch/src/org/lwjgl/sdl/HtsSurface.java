package org.lwjgl.sdl;

import org.lwjgl.hts.HtsGLBaton;

import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.channels.FileChannel;
import java.nio.file.Paths;
import java.nio.file.StandardOpenOption;
import java.util.concurrent.locks.LockSupport;

import static org.lwjgl.system.MemoryUtil.*;

/**
 * What happens around each presented frame on Android.
 * <ul>
 *   <li>Keeps the game running while Android has no usable surface for the window (the game
 *       screen was recreated or its TextureView detached). lwjgl3ify turns a failed
 *       SDL_GL_SwapWindow into an exception, which crashes Minecraft; here such a frame is dropped
 *       instead, and once SDL has an EGL surface for the new Android surface the context is made
 *       current on it again (SDL only does that itself around nativePause/nativeResume, which we
 *       don't use).</li>
 *   <li>VSync. The game draws into a TextureView, whose buffer queue never blocks
 *       eglSwapBuffers, so eglSwapInterval changes nothing (OptiFine's VSync showed 400+ FPS on a
 *       60 Hz screen). The requested interval is kept here and frames are paced to the display's
 *       vsync, which the game screen publishes from Choreographer.</li>
 *   <li>Background: while the game screen is not visible, frames are capped to a few per second.</li>
 * </ul>
 * The game screen (ru.hts.client.game.FrameState, another VM in this process) shares its data
 * through a small memory-mapped file named by HTS_FRAME_STATE.
 */
final class HtsSurface {
    /** Frame pace while there is nothing to present to. */
    private static final long LOST_FRAME_NS = 50_000_000L;
    /** Background waits are cut into slices, so coming back to the game is not delayed. */
    private static final long WAIT_SLICE_NS = 50_000_000L;

    // Layout of the shared file, see ru.hts.client.game.FrameState
    private static final int STATE_VSYNC = 0, STATE_PERIOD = 8, STATE_BACKGROUND = 16, STATE_BACKGROUND_FPS = 20;
    private static final int STATE_SIZE = 64;

    /** Interval the game asked for with SDL_GL_SetSwapInterval (lwjgl3ify starts with 1). */
    private static volatile int swapInterval = 1;

    /** EGL surface the context was last presenting to (only touched on the rendering thread). */
    private static long boundSurface;
    private static boolean lost;

    private static ByteBuffer state;
    private static boolean stateOpened;
    /** Vsync the last paced frame was released at. */
    private static long frameSlot;
    /** End of the last frame, for the background cap. */
    private static long lastFrame;
    private static boolean wasBackground;

    private HtsSurface() {}

    static void setSwapInterval(int interval) {
        // -1 (adaptive vsync) is vsync as well
        int value = interval < 0 ? 1 : interval;
        if (value != swapInterval) System.out.println("[HTS] swap interval " + value + (value > 0 ? " (paced to the display's vsync)" : ""));
        swapInterval = value;
    }

    static int swapInterval() {
        return swapInterval;
    }

    static void swapped(long window) {
        if (lost) {
            lost = false;
            System.out.println("[HTS] presenting to the window again");
        }
        if (boundSurface == NULL) boundSurface = SDLVideo.SDL_EGL_GetWindowSurface(window);
        pace(true);
    }

    /** @return true when the failure was the lost surface and has been swallowed */
    static boolean swapFailed(long window) {
        String error = SDLError.SDL_GetError();
        long surface = SDLVideo.SDL_EGL_GetWindowSurface(window);
        boolean surfaceError = error != null
                && (error.contains("EGL_BAD_SURFACE") || error.contains("EGL_BAD_NATIVE_WINDOW"));
        if (!surfaceError && surface != NULL && surface == boundSurface) return false;

        if (!lost) {
            lost = true;
            System.out.println("[HTS] window surface lost (" + error + "), dropping frames until Android gives a new one");
        }
        if (surface != NULL && surface != boundSurface) {
            long context = SDLVideo.realCurrentContext();
            if (context != NULL && SDLVideo.realMakeCurrent(window, context)) {
                boundSurface = surface;
                System.out.println("[HTS] GL context moved to the new window surface");
            }
        }
        pace(false);
        return true;
    }

    // ---- frame pacing ----

    private static void pace(boolean presented) {
        long now = System.nanoTime();
        // Loading shares the context with the loading screen's thread: never slow it down
        if (HtsGLBaton.loading()) {
            lastFrame = now;
            return;
        }
        ByteBuffer s = state();
        boolean background = s != null && s.getInt(STATE_BACKGROUND) != 0;
        if (background != wasBackground) {
            wasBackground = background;
            System.out.println(background ? "[HTS] game screen hidden, frames capped" : "[HTS] game screen visible again");
        }
        if (background) {
            int fps = s.getInt(STATE_BACKGROUND_FPS);
            long wait = fps > 0 ? 1_000_000_000L / fps : 0;
            if (!presented) wait = Math.max(wait, LOST_FRAME_NS);
            waitUntil(lastFrame + Math.min(wait, 1_000_000_000L), true);
        } else if (!presented) {
            waitUntil(now + LOST_FRAME_NS, false);
        } else if (swapInterval > 0) {
            paceToVsync(s, swapInterval, now);
        }
        lastFrame = System.nanoTime();
    }

    /**
     * Holds the next frame back until {@code interval} vsyncs after the previous one. A frame that
     * took longer is not held at all (no drop to half the refresh rate as with double buffering).
     */
    private static void paceToVsync(ByteBuffer s, int interval, long now) {
        long period = s != null ? s.getLong(STATE_PERIOD) : 0;
        if (period < 2_000_000L || period > 100_000_000L) period = 16_666_667L;
        long vsync = s != null ? s.getLong(STATE_VSYNC) : 0;
        // Vsync times come from Choreographer on System.nanoTime's clock (CLOCK_MONOTONIC)
        boolean grid = vsync != 0 && Math.abs(now - vsync) < 2_000_000_000L;
        long step = period * interval;
        long target = frameSlot + step;
        if (target <= now || target - now > step + period) {
            // First frame, a slow one or stale data: continue from the latest vsync, don't wait
            frameSlot = grid ? vsync + Math.floorDiv(now - vsync, period) * period : now;
            return;
        }
        if (grid) {
            target = vsync + Math.round((double) (target - vsync) / period) * period;
            if (target <= now) {
                frameSlot = vsync + Math.floorDiv(now - vsync, period) * period;
                return;
            }
        }
        waitUntil(target, false);
        frameSlot = target;
    }

    private static void waitUntil(long deadline, boolean whileBackground) {
        long left;
        while ((left = deadline - System.nanoTime()) > 0) {
            LockSupport.parkNanos(whileBackground ? Math.min(left, WAIT_SLICE_NS) : left);
            if (Thread.currentThread().isInterrupted()) return;
            if (whileBackground && state.getInt(STATE_BACKGROUND) == 0) return;
        }
    }

    private static ByteBuffer state() {
        if (!stateOpened) {
            stateOpened = true;
            String path = System.getenv("HTS_FRAME_STATE");
            if (path != null) {
                try (FileChannel channel = FileChannel.open(Paths.get(path), StandardOpenOption.READ)) {
                    state = channel.map(FileChannel.MapMode.READ_ONLY, 0, STATE_SIZE);
                } catch (IOException | RuntimeException e) {
                    System.out.println("[HTS] no frame state from the game screen (" + e + "), vsync falls back to 60 Hz");
                }
            }
        }
        return state;
    }
}
