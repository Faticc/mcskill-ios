import org.lwjgl.opengl.GL;
import org.lwjgl.sdl.SDL_Event;
import org.lwjgl.system.MemoryStack;

import java.io.PrintWriter;
import java.nio.IntBuffer;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

import static org.lwjgl.opengl.GL11.*;
import static org.lwjgl.sdl.SDLError.SDL_GetError;
import static org.lwjgl.sdl.SDLEvents.*;
import static org.lwjgl.sdl.SDLInit.*;
import static org.lwjgl.sdl.SDLMain.SDL_SetMainReady;
import static org.lwjgl.sdl.SDLVideo.*;

/**
 * The game's render path in miniature, run by CI in the simulator (and by "--gltest" on a phone):
 * an SDL window with a GL context from ANGLE's EGL, desktop GL 2.1 of gl4es on top, immediate
 * mode like Minecraft 1.7.10. Writes a report next to the logs: args[0].
 */
public final class HtsGLTest {
    public static void main(String[] args) throws Exception {
        Path report = Path.of(args.length > 0 ? args[0] : "gltest.json");
        StringBuilder log = new StringBuilder();
        try {
            run(log);
            write(report, true, log, null);
        } catch (Throwable t) {
            t.printStackTrace();
            write(report, false, log, t.toString());
        }
    }

    private static void run(StringBuilder log) throws InterruptedException {
        SDL_SetMainReady();
        check(SDL_Init(SDL_INIT_VIDEO | SDL_INIT_EVENTS), "SDL_Init");
        note(log, "SDL video driver: " + SDL_GetCurrentVideoDriver());

        SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_ES);
        SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
        SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 0);
        SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 24);
        long window = SDL_CreateWindow("HTS GL test", 1280, 720, SDL_WINDOW_OPENGL | SDL_WINDOW_FULLSCREEN);
        check(window != 0, "SDL_CreateWindow");
        long context = SDL_GL_CreateContext(window);
        check(context != 0, "SDL_GL_CreateContext");
        SDL_GL_SetSwapInterval(1);

        GL.createCapabilities();
        note(log, "GL_VENDOR: " + glGetString(GL_VENDOR));
        note(log, "GL_RENDERER: " + glGetString(GL_RENDERER));
        note(log, "GL_VERSION: " + glGetString(GL_VERSION));

        int w, h;
        try (MemoryStack stack = MemoryStack.stackPush()) {
            IntBuffer pw = stack.mallocInt(1), ph = stack.mallocInt(1);
            SDL_GetWindowSizeInPixels(window, pw, ph);
            w = pw.get(0);
            h = ph.get(0);
        }
        note(log, "Drawable: " + w + "x" + h);

        SDL_Event event = SDL_Event.malloc();
        long start = System.nanoTime();
        int frames = 0;
        // Long enough for the CI screenshot, then report and keep the picture up
        while (System.nanoTime() - start < 8_000_000_000L) {
            while (SDL_PollEvent(event)) {
                if (event.type() == SDL_EVENT_QUIT) return;
            }
            float t = (System.nanoTime() - start) / 1e9f;
            glViewport(0, 0, w, h);
            glClearColor(0.07f, 0.07f, 0.08f, 1f);
            glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
            glMatrixMode(GL_PROJECTION);
            glLoadIdentity();
            glOrtho(-1.6, 1.6, -0.9, 0.9, -1, 1);
            glMatrixMode(GL_MODELVIEW);
            glLoadIdentity();
            glRotatef(t * 40f, 0, 0, 1);
            glBegin(GL_TRIANGLES);
            glColor3f(0.24f, 0.66f, 0.72f);
            glVertex2f(0f, 0.7f);
            glColor3f(0.01f, 0.52f, 0.61f);
            glVertex2f(-0.6f, -0.45f);
            glColor3f(1f, 0.72f, 0f);
            glVertex2f(0.6f, -0.45f);
            glEnd();
            int error = glGetError();
            if (error != GL_NO_ERROR) note(log, "glGetError: 0x" + Integer.toHexString(error));
            check(SDL_GL_SwapWindow(window), "SDL_GL_SwapWindow");
            frames++;
        }
        double seconds = (System.nanoTime() - start) / 1e9;
        note(log, String.format("Frames: %d in %.1f s (%.0f FPS)", frames, seconds, frames / seconds));
    }

    private static void check(boolean ok, String what) {
        if (!ok) throw new IllegalStateException(what + ": " + SDL_GetError());
    }

    private static void note(StringBuilder log, String line) {
        System.out.println("[gltest] " + line);
        log.append(line).append('\n');
    }

    private static void write(Path report, boolean ok, StringBuilder log, String error) {
        String json = "{\n  \"ok\" : " + ok + ",\n  \"log\" : " + quote(log.toString())
                + (error != null ? ",\n  \"error\" : " + quote(error) : "") + "\n}\n";
        try (PrintWriter out = new PrintWriter(Files.newBufferedWriter(report, StandardCharsets.UTF_8))) {
            out.print(json);
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    private static String quote(String s) {
        return "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n") + "\"";
    }
}
