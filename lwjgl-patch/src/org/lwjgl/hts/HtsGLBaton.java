package org.lwjgl.hts;

import org.lwjgl.opengl.GL11;
import org.lwjgl.system.MemoryStack;

import java.util.HashMap;
import java.util.Map;

import static org.lwjgl.system.JNI.*;
import static org.lwjgl.system.MemoryUtil.*;

/**
 * Lets Forge's loading splash run on Android with a single GL context (HTS_GL_SPLASH=1).
 *
 * On the PC the splash thread draws with the window's context while loading goes on in a second,
 * shared context that lwjgl3ify creates on a hidden window. Android has one window, and gl4es
 * keeps one global GL state, so two live contexts are impossible here. Instead:
 * <ul>
 *   <li>the hidden window and the shared context are virtual handles standing for the main
 *       window and the main context;</li>
 *   <li>one thread at a time owns the context: loading lends it to the splash at progress steps
 *       ({@link #mainYield}), the splash returns it after each frame ({@link #afterSwap});</li>
 *   <li>what the splash touches is saved and restored around its frame, so loading finds its
 *       texture bindings, matrices and buffers exactly as it left them;</li>
 *   <li>the splash keeps its own state too: Forge's splash sets clear colour, blending and depth
 *       test once when its thread starts, as it would in a context of its own
 *       ({@link SplashState}).</li>
 * </ul>
 * The hooks in Forge classes are added by MioLibPatcher's SplashProgressTransformer. Loading
 * screens copied from Forge's (ModernSplash...) have no hooks of their own: they are recognised
 * by how they use the context ({@link #recognizeSplash}).
 *
 * The same source is built into both LWJGL patches: lwjgl3ify 3 on SDL (org.lwjgl.sdl.SDLVideo)
 * and lwjgl3ify 2 on Pojav's GLFW (org.lwjgl.glfw.GLFW, where a window handle is its context).
 * Each registers the real make-current and function lookup as the {@link Backend}.
 */
public final class HtsGLBaton {
    /** What the windowing library really does, without virtual handles or the baton. */
    public interface Backend {
        boolean makeCurrent(long window, long context);

        long getProcAddress(String name);
    }

    private static final boolean ENABLED = "1".equals(System.getenv("HTS_GL_SPLASH"));
    private static volatile Backend backend;

    public static void setBackend(Backend b) {
        backend = b;
    }
    /** Mode of a loading screen recognised without hooks. */
    private static final String AUTO = "auto";
    /** Minimum time between two splash frames taken from loading. */
    private static final long FRAME_INTERVAL_NS = 40_000_000L;
    /** Never let loading hang on the splash for longer than this. */
    private static final long LOADING_WAIT_LIMIT_NS = 10_000_000_000L;

    private static final int GL_ALL_ATTRIB_BITS = 0x000fffff;
    private static final int GL_CLIENT_ALL_ATTRIB_BITS = 0xffffffff;
    private static final int GL_MATRIX_MODE = 0x0BA0;
    private static final int GL_MODELVIEW = 0x1700, GL_PROJECTION = 0x1701, GL_TEXTURE = 0x1702;
    private static final int GL_ACTIVE_TEXTURE = 0x84E0, GL_TEXTURE0 = 0x84C0;
    private static final int GL_TEXTURE_2D = 0x0DE1, GL_TEXTURE_BINDING_2D = 0x8069;
    private static final int GL_CURRENT_PROGRAM = 0x8B8D;
    private static final int GL_FRAMEBUFFER = 0x8D40, GL_FRAMEBUFFER_BINDING = 0x8CA6;
    private static final int GL_ARRAY_BUFFER = 0x8892, GL_ARRAY_BUFFER_BINDING = 0x8894;
    private static final int GL_ELEMENT_ARRAY_BUFFER = 0x8893, GL_ELEMENT_ARRAY_BUFFER_BINDING = 0x8895;
    /** Capabilities a loading screen may switch once and rely on (GL11 fixed function). */
    private static final int[] SPLASH_CAPS = {
            0x0B50 /* LIGHTING */, 0x0B71 /* DEPTH_TEST */, 0x0BE2 /* BLEND */, 0x0BC0 /* ALPHA_TEST */,
            0x0B44 /* CULL_FACE */, GL_TEXTURE_2D, 0x0B60 /* FOG */, 0x0B57 /* COLOR_MATERIAL */,
            0x0C11 /* SCISSOR_TEST */, 0x0B90 /* STENCIL_TEST */, 0x0BA1 /* NORMALIZE */,
            0x803A /* RESCALE_NORMAL */, 0x8037 /* POLYGON_OFFSET_FILL */,
    };

    private static final Object LOCK = new Object();
    private static final long VIRTUAL_BASE = 0x7e57_0000_0000L;

    private static long mainWindow;
    private static long mainContext;
    /**
     * lwjgl3ify's "cloneable" context: only made current (on SDL's main thread, while loading owns
     * the real context) to create shared contexts from. Nothing is ever drawn with it, so making
     * it current is purely logical here.
     */
    private static long cloneableContext;
    private static long nextVirtual = VIRTUAL_BASE;

    /** Between the loading screen's start and finish. */
    private static boolean active;
    /**
     * Which loading screen drives the hooks: "fml" (Forge splash), "metastart" (MetaStart) or
     * "auto" (a copy of Forge's splash, recognised without hooks).
     */
    private static String mode;
    /** Thread that last gave the real main context up. */
    private static Thread lastReleaser;
    /** A loading screen was already recognised without hooks (there is one per game start). */
    private static boolean recognized;
    private static Thread loadingThread;
    private static Thread splashThread;
    /** Thread that has the real main context current, null if none. */
    private static Thread owner;
    /** Loading lent the context for one splash frame. */
    private static boolean splashTurn;
    /** Loading gave the context up until it makes it current again (pause/finish). */
    private static boolean released;
    private static boolean splashWaiting;
    private static long lastFrame;

    private static final ThreadLocal<long[]> logical = ThreadLocal.withInitial(() -> new long[2]);
    private static final int[] saved = new int[7];
    /** The splash's own state after its last frame, null before the first one. */
    private static SplashState splashState;
    private static final Map<String, Long> functions = new HashMap<>();

    private HtsGLBaton() {}

    // ---- virtual hidden window and shared context ----

    /**
     * A hidden window for a context shared with the main one (lwjgl3ify's SharedDrawable): a
     * virtual handle standing for the main window. NULL while there is no main window yet or the
     * baton is off.
     */
    public static long virtualWindow() {
        if (!ENABLED || mainWindow == NULL) return NULL;
        synchronized (LOCK) {
            System.out.println("[HTS] virtual hidden window instead of a second Android window");
            return nextVirtual += 0x10;
        }
    }

    public static long virtualContext() {
        synchronized (LOCK) {
            nextVirtual += 0x10;
            if (cloneableContext == NULL) cloneableContext = nextVirtual;
            return nextVirtual;
        }
    }

    public static boolean isVirtual(long handle) {
        return ENABLED && handle > VIRTUAL_BASE && handle <= nextVirtual;
    }

    public static void onWindowCreated(long window) {
        if (ENABLED && window != NULL && mainWindow == NULL) mainWindow = window;
    }

    /** @param current the context was made current on creation (SDL_GL_CreateContext does that) */
    public static void onContextCreated(long window, long context, boolean current) {
        if (!ENABLED || context == NULL || mainContext != NULL || window != mainWindow) return;
        mainContext = context;
        if (!current) return;
        synchronized (LOCK) {
            owner = Thread.currentThread();
        }
    }

    public static long realWindow(long window) {
        return isVirtual(window) ? mainWindow : window;
    }

    private static long realContext(long context) {
        return isVirtual(context) ? mainContext : context;
    }

    /** SDL_GL_GetCurrentWindow as the caller made it current (virtual handles included). */
    public static long currentWindow(long real) {
        long[] l = logical.get();
        return ENABLED && l[1] != NULL && realWindow(l[0]) == real ? l[0] : real;
    }

    public static long currentContext(long real) {
        long[] l = logical.get();
        return ENABLED && l[1] != NULL && realContext(l[1]) == real ? l[1] : real;
    }

    /** The loading screen shares the context with loading right now. */
    public static boolean loading() {
        if (!ENABLED) return false;
        synchronized (LOCK) {
            return active;
        }
    }

    // ---- make current with the baton ----

    public static boolean makeCurrent(long window, long context) {
        if (!ENABLED) return backend.makeCurrent(window, context);
        long[] l = logical.get();
        Thread me = Thread.currentThread();
        if (context == NULL) {
            boolean result;
            synchronized (LOCK) {
                if (active && owner == me && me == splashThread) restoreState();
                result = backend.makeCurrent(realWindow(window), NULL);
                if (owner == me) {
                    owner = null;
                    lastReleaser = me;
                    LOCK.notifyAll();
                }
            }
            l[0] = NULL;
            l[1] = NULL;
            return result;
        }
        if (context == cloneableContext) {
            l[0] = window;
            l[1] = context;
            return true;
        }
        long realCtx = realContext(context);
        if (realCtx != mainContext) return backend.makeCurrent(window, context);
        long realWin = realWindow(window);
        boolean result;
        synchronized (LOCK) {
            recognizeSplash(me, context);
            boolean acquired = false;
            if (active && owner != me) {
                acquire(me);
                acquired = true;
            }
            owner = me;
            if (me == loadingThread) released = false;
            result = backend.makeCurrent(realWin, realCtx);
            if (acquired && me == splashThread) {
                saveState();
                if (splashState != null) splashState.apply();
            }
        }
        l[0] = window;
        l[1] = context;
        return result;
    }

    /**
     * (LOCK held) Loading screens copied from Forge's SplashProgress have no hooks here, but use
     * the context the same way: in start() the loading thread gives the window's context up and
     * makes a shared one current, then the screen's own thread makes the window's context current
     * and keeps it until finish(). The first such thread becomes the splash thread; once it has
     * ended, the loading thread's next make-current closes the screen.
     */
    private static void recognizeSplash(Thread me, long context) {
        if (active) {
            if (!AUTO.equals(mode)) return;
            if (splashThread == null && me != loadingThread && !isVirtual(context)) {
                splashThread = me;
                System.out.println("[HTS] loading screen thread " + me.getName() + " shares the GL context with loading");
            } else if (me == loadingThread && splashThread != null && !splashThread.isAlive()) {
                splashFinished(AUTO);
            }
            return;
        }
        if (recognized || context == cloneableContext || !isVirtual(context) || lastReleaser != me) return;
        recognized = true;
        splashStarting(AUTO);
    }

    /** Waits (LOCK held) until the context is free and it's this thread's turn, then owns it. */
    private static void acquire(Thread me) {
        boolean splash = me == splashThread;
        long start = System.nanoTime();
        if (splash) splashWaiting = true;
        try {
            while (true) {
                boolean free = owner == null || owner == me || !owner.isAlive();
                boolean turn = !splash || !active || splashTurn || released;
                if (free && turn) break;
                if (!splash && System.nanoTime() - start > LOADING_WAIT_LIMIT_NS) {
                    System.out.println("[HTS] splash did not return the GL context, taking it back");
                    break;
                }
                LOCK.wait(20);
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        } finally {
            if (splash) splashWaiting = false;
        }
        owner = me;
    }

    /** Right after a frame was presented. On the splash thread: return the context to loading. */
    public static void afterSwap() {
        if (!ENABLED) return;
        Thread me = Thread.currentThread();
        synchronized (LOCK) {
            if (!active || me != splashThread || owner != me || released) return;
            long[] l = logical.get();
            if (splashState == null) splashState = new SplashState();
            splashState.capture();
            restoreState();
            backend.makeCurrent(NULL, NULL);
            owner = null;
            splashTurn = false;
            LOCK.notifyAll();
            // Wait for the next frame loading lends us (or for loading to let go for good)
            acquire(me);
            backend.makeCurrent(realWindow(l[0]), realContext(l[1]));
            saveState();
            splashState.apply();
        }
    }

    // ---- hooks inserted into Forge ----

    /**
     * The loading screen starts (Forge splash or MetaStart): the caller is the loading thread and
     * has the context current. MetaStart replaces Forge's splash and starts first, so a later
     * call for another screen is ignored.
     */
    public static void splashStarting(String screen) {
        if (!ENABLED) return;
        synchronized (LOCK) {
            if (active && mode != null && !mode.equals(screen)) return;
            mode = screen;
            loadingThread = Thread.currentThread();
            owner = loadingThread;
            active = true;
            released = false;
            splashTurn = false;
            splashState = null;
            System.out.println("[HTS] " + screen + " loading screen shares one GL context with loading");
        }
    }

    /** First statement of the loading screen's render thread. */
    public static void splashThread(String screen) {
        if (!ENABLED) return;
        synchronized (LOCK) {
            if (!screen.equals(mode)) return;
            splashThread = Thread.currentThread();
        }
    }

    /** A progress step on the loading thread: lend the context for one splash frame. */
    public static void mainYield() {
        if (!ENABLED) return;
        Thread me = Thread.currentThread();
        synchronized (LOCK) {
            if (!active || me != loadingThread || owner != me || !splashWaiting) return;
            long now = System.nanoTime();
            if (now - lastFrame < FRAME_INTERVAL_NS) return;
            lastFrame = now;
            long[] l = logical.get();
            long window = l[0], context = l[1];
            backend.makeCurrent(NULL, NULL);
            owner = null;
            splashTurn = true;
            LOCK.notifyAll();
            try {
                long deadline = now + 300_000_000L;
                while (splashTurn) {
                    if (owner == null && System.nanoTime() > deadline) break; // splash didn't come
                    if (splashThread == null || !splashThread.isAlive()) break;
                    LOCK.wait(20);
                }
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
            }
            splashTurn = false;
            acquire(me);
            backend.makeCurrent(realWindow(window), realContext(context));
        }
    }

    /**
     * SplashProgress.pause()/finish(): loading is about to wait for the splash thread (lock or
     * join), so it gives the context up until it makes it current again.
     */
    public static void mainRelease(String screen) {
        if (!ENABLED) return;
        Thread me = Thread.currentThread();
        synchronized (LOCK) {
            if (!screen.equals(mode)) return;
            // Nobody may own it either: finish() on the init error screen comes after loading let
            // the context go, and without "released" the splash waited for its turn while
            // loading waited for the splash to end (GregTech, LiteLoader failing in init)
            if (!active || me != loadingThread || (owner != me && owner != null)) return;
            // Forge calls finish() even when its splash is off: without a running splash thread
            // nobody would take the context. MetaStart re-makes its context current afterwards.
            if ("fml".equals(screen) && (splashThread == null || !splashThread.isAlive())) return;
            if (owner == me) backend.makeCurrent(NULL, NULL);
            owner = null;
            released = true;
            splashTurn = false;
            LOCK.notifyAll();
        }
    }

    /**
     * Before the loading screen's finish(), once its render thread was told to stop: give the
     * context up and wait (outside any lock of the caller) until that thread has ended.
     * lwjgl3ify 2 makes contexts current and releases them under one global lock, so loading must
     * not wait for the render thread's release from inside its own make-current (that stalled the
     * end of loading until the 10 s limit).
     */
    public static void mainFinish(String screen, Thread renderThread) {
        if (!ENABLED) return;
        Thread me = Thread.currentThread();
        synchronized (LOCK) {
            if (!active || !screen.equals(mode) || me != loadingThread) return;
            if (owner == me) {
                backend.makeCurrent(NULL, NULL);
                owner = null;
            }
            // The render thread may be waiting for its turn: it has to finish its frame to stop
            released = true;
            splashTurn = false;
            LOCK.notifyAll();
        }
        if (renderThread == null || renderThread == me) return;
        try {
            renderThread.join(5000);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
        if (renderThread.isAlive()) System.out.println("[HTS] loading screen thread still running after 5 s");
    }

    /**
     * After waiting for the render thread (MetaStart's first frame): take the context back. The
     * render thread kept it while released and hands it over after its next frame.
     */
    public static void mainReacquire() {
        if (!ENABLED) return;
        Thread me = Thread.currentThread();
        synchronized (LOCK) {
            if (!active || me != loadingThread || !released) return;
            released = false;
            LOCK.notifyAll();
            long[] l = logical.get();
            acquire(me);
            if (l[1] != NULL) backend.makeCurrent(realWindow(l[0]), realContext(l[1]));
        }
    }

    /**
     * Loader.loadingComplete() returned: FMLClientHandler calls the loading screen's finish() next,
     * which waits for the screen's thread. A screen recognised without hooks gets the context for
     * its last frames now.
     */
    public static void loadingComplete() {
        if (!ENABLED) return;
        synchronized (LOCK) {
            if (!AUTO.equals(mode)) return;
            if (splashThread == null || !splashThread.isAlive()) {
                splashFinished(AUTO);
                return;
            }
        }
        mainRelease(AUTO);
    }

    /** After the loading screen finished. */
    public static void splashFinished(String screen) {
        if (!ENABLED) return;
        synchronized (LOCK) {
            if (!screen.equals(mode)) return;
            mode = null;
            active = false;
            released = false;
            splashThread = null;
            LOCK.notifyAll();
        }
    }

    // ---- GL state around splash frames (one context: nothing may leak into loading) ----

    private static void saveState() {
        try (MemoryStack stack = MemoryStack.stackPush()) {
            long value = stack.nmalloc(4, 64);
            saved[0] = getInteger(GL_MATRIX_MODE, value);
            saved[1] = getInteger(GL_ACTIVE_TEXTURE, value);
            saved[2] = getInteger(GL_CURRENT_PROGRAM, value);
            saved[3] = getInteger(GL_FRAMEBUFFER_BINDING, value);
            saved[4] = getInteger(GL_ARRAY_BUFFER_BINDING, value);
            saved[5] = getInteger(GL_ELEMENT_ARRAY_BUFFER_BINDING, value);
            call1("glActiveTexture", GL_TEXTURE0);
            saved[6] = getInteger(GL_TEXTURE_BINDING_2D, value);
        }
        call1("glPushAttrib", GL_ALL_ATTRIB_BITS);
        call1("glPushClientAttrib", GL_CLIENT_ALL_ATTRIB_BITS);
        for (int mode : new int[]{GL_TEXTURE, GL_PROJECTION, GL_MODELVIEW}) {
            call1("glMatrixMode", mode);
            call0("glPushMatrix");
        }
        // The splash draws with fixed function into the window
        call1("glUseProgram", 0);
        call2("glBindFramebuffer", GL_FRAMEBUFFER, 0);
        call2("glBindBuffer", GL_ARRAY_BUFFER, 0);
        call2("glBindBuffer", GL_ELEMENT_ARRAY_BUFFER, 0);
    }

    private static void restoreState() {
        for (int mode : new int[]{GL_TEXTURE, GL_PROJECTION, GL_MODELVIEW}) {
            call1("glMatrixMode", mode);
            call0("glPopMatrix");
        }
        call0("glPopClientAttrib");
        call0("glPopAttrib");
        call1("glActiveTexture", GL_TEXTURE0);
        call2("glBindTexture", GL_TEXTURE_2D, saved[6]);
        call1("glActiveTexture", saved[1]);
        call2("glBindBuffer", GL_ARRAY_BUFFER, saved[4]);
        call2("glBindBuffer", GL_ELEMENT_ARRAY_BUFFER, saved[5]);
        call2("glBindFramebuffer", GL_FRAMEBUFFER, saved[3]);
        call1("glUseProgram", saved[2]);
        call1("glMatrixMode", saved[0]);
    }

    private static int getInteger(int pname, long buffer) {
        long fn = gl("glGetIntegerv");
        if (fn == NULL) return 0;
        memPutInt(buffer, 0);
        invokePV(pname, buffer, fn);
        return memGetInt(buffer);
    }

    private static void call0(String name) {
        long fn = gl(name);
        if (fn != NULL) invokeV(fn);
    }

    private static void call1(String name, int a) {
        long fn = gl(name);
        if (fn != NULL) invokeV(a, fn);
    }

    private static void call2(String name, int a, int b) {
        long fn = gl(name);
        if (fn != NULL) invokeV(a, b, fn);
    }

    /**
     * State a loading screen sets once and keeps using: on the PC its thread has a context of its
     * own. Taken after each splash frame, before loading's state comes back, and put back when the
     * splash gets the context again (matrices, viewport and bindings it sets per frame itself).
     */
    private static final class SplashState {
        private final boolean[] caps = new boolean[SPLASH_CAPS.length];
        private final float[] clearColor = new float[4];
        private final float[] color = new float[4];
        private int blendSrc, blendDst, alphaFunc, depthFunc, shadeModel;
        private float alphaRef;
        private boolean depthMask;
        private boolean broken;

        void capture() {
            if (broken) return;
            try {
                for (int i = 0; i < caps.length; i++) caps[i] = GL11.glIsEnabled(SPLASH_CAPS[i]);
                GL11.glGetFloatv(GL11.GL_COLOR_CLEAR_VALUE, clearColor);
                GL11.glGetFloatv(GL11.GL_CURRENT_COLOR, color);
                blendSrc = GL11.glGetInteger(GL11.GL_BLEND_SRC);
                blendDst = GL11.glGetInteger(GL11.GL_BLEND_DST);
                alphaFunc = GL11.glGetInteger(GL11.GL_ALPHA_TEST_FUNC);
                alphaRef = GL11.glGetFloat(GL11.GL_ALPHA_TEST_REF);
                depthFunc = GL11.glGetInteger(GL11.GL_DEPTH_FUNC);
                depthMask = GL11.glGetBoolean(GL11.GL_DEPTH_WRITEMASK);
                shadeModel = GL11.glGetInteger(GL11.GL_SHADE_MODEL);
            } catch (Throwable e) {
                broken = true;
                System.out.println("[HTS] cannot keep the loading screen's GL state: " + e);
            }
        }

        void apply() {
            if (broken) return;
            try {
                for (int i = 0; i < caps.length; i++) {
                    if (caps[i]) GL11.glEnable(SPLASH_CAPS[i]);
                    else GL11.glDisable(SPLASH_CAPS[i]);
                }
                GL11.glClearColor(clearColor[0], clearColor[1], clearColor[2], clearColor[3]);
                GL11.glColor4f(color[0], color[1], color[2], color[3]);
                GL11.glBlendFunc(blendSrc, blendDst);
                GL11.glAlphaFunc(alphaFunc, alphaRef);
                GL11.glDepthFunc(depthFunc);
                GL11.glDepthMask(depthMask);
                GL11.glShadeModel(shadeModel);
            } catch (Throwable e) {
                broken = true;
                System.out.println("[HTS] cannot restore the loading screen's GL state: " + e);
            }
        }
    }

    private static long gl(String name) {
        Long cached = functions.get(name);
        if (cached == null) {
            cached = backend.getProcAddress(name);
            functions.put(name, cached);
        }
        return cached;
    }
}
