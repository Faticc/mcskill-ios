/*
 * HTS additions to SDL's UIKit video driver (copied into src/video/uikit by scripts/build-sdl.sh,
 * installed from UIKit_CreateDevice):
 *
 * 1. The game runs on its own thread (the JVM's), not on the iOS main thread as SDL expects.
 *    Everything that touches UIKit is run on the main thread, and PumpEvents off the main thread
 *    leaves the run loop alone: UIKit keeps delivering touches on the main thread, and SDL's
 *    event queue hands them to the game thread.
 * 2. OpenGL goes through EGL of ANGLE (Metal) on the window's CAMetalLayer, the way Amethyst's
 *    gl_bridge.m does it, instead of EAGL: gl4es is built against ANGLE's EGL/GLESv2.
 *    Environment: HTS_EGL_LIBRARY (default @rpath/libEGL.framework/libEGL),
 *    HTS_GLES_LIBRARY (default @rpath/libGLESv2.framework/libGLESv2),
 *    HTS_GL_LIBRARY (GL entry points asked from SDL come from here first, i.e. gl4es).
 */
#include "SDL_internal.h"

#ifdef SDL_VIDEO_DRIVER_UIKIT

#include "../SDL_sysvideo.h"

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#include <dlfcn.h>
#include <pthread.h>

// MARK: - main thread

static void HTS_OnMain(void (^block)(void))
{
    if ([NSThread isMainThread]) {
        block();
    } else {
        dispatch_sync(dispatch_get_main_queue(), block);
    }
}

static struct {
    bool (*VideoInit)(SDL_VideoDevice *);
    bool (*GetDisplayUsableBounds)(SDL_VideoDevice *, SDL_VideoDisplay *, SDL_Rect *);
    bool (*GetDisplayModes)(SDL_VideoDevice *, SDL_VideoDisplay *);
    bool (*SetDisplayMode)(SDL_VideoDevice *, SDL_VideoDisplay *, SDL_DisplayMode *);
    bool (*CreateSDLWindow)(SDL_VideoDevice *, SDL_Window *, SDL_PropertiesID);
    void (*SetWindowTitle)(SDL_VideoDevice *, SDL_Window *);
    void (*SetWindowSize)(SDL_VideoDevice *, SDL_Window *);
    void (*GetWindowSizeInPixels)(SDL_VideoDevice *, SDL_Window *, int *, int *);
    void (*ShowWindow)(SDL_VideoDevice *, SDL_Window *);
    void (*HideWindow)(SDL_VideoDevice *, SDL_Window *);
    void (*SetWindowBordered)(SDL_VideoDevice *, SDL_Window *, bool);
    SDL_FullscreenResult (*SetWindowFullscreen)(SDL_VideoDevice *, SDL_Window *, SDL_VideoDisplay *, SDL_FullscreenOp);
    void (*DestroyWindow)(SDL_VideoDevice *, SDL_Window *);
    void (*PumpEvents)(SDL_VideoDevice *);
    bool (*SuspendScreenSaver)(SDL_VideoDevice *);
    bool (*StartTextInput)(SDL_VideoDevice *, SDL_Window *, SDL_PropertiesID);
    bool (*StopTextInput)(SDL_VideoDevice *, SDL_Window *);
    bool (*UpdateTextInputArea)(SDL_VideoDevice *, SDL_Window *);
    void (*SetTextInputProperties)(SDL_VideoDevice *, SDL_Window *, SDL_PropertiesID);
    SDL_MetalView (*Metal_CreateView)(SDL_VideoDevice *, SDL_Window *);
    void (*Metal_DestroyView)(SDL_VideoDevice *, SDL_MetalView);
    void *(*Metal_GetLayer)(SDL_VideoDevice *, SDL_MetalView);
} orig;

static bool HTS_VideoInit(SDL_VideoDevice *_this)
{
    __block bool r = false;
    HTS_OnMain(^{ r = orig.VideoInit(_this); });
    return r;
}

static bool HTS_GetDisplayUsableBounds(SDL_VideoDevice *_this, SDL_VideoDisplay *display, SDL_Rect *rect)
{
    __block bool r = false;
    HTS_OnMain(^{ r = orig.GetDisplayUsableBounds(_this, display, rect); });
    return r;
}

static bool HTS_GetDisplayModes(SDL_VideoDevice *_this, SDL_VideoDisplay *display)
{
    __block bool r = false;
    HTS_OnMain(^{ r = orig.GetDisplayModes(_this, display); });
    return r;
}

static bool HTS_SetDisplayMode(SDL_VideoDevice *_this, SDL_VideoDisplay *display, SDL_DisplayMode *mode)
{
    __block bool r = false;
    HTS_OnMain(^{ r = orig.SetDisplayMode(_this, display, mode); });
    return r;
}

static bool HTS_CreateSDLWindow(SDL_VideoDevice *_this, SDL_Window *window, SDL_PropertiesID props)
{
    __block bool r = false;
    HTS_OnMain(^{ r = orig.CreateSDLWindow(_this, window, props); });
    return r;
}

static void HTS_SetWindowTitle(SDL_VideoDevice *_this, SDL_Window *window)
{
    HTS_OnMain(^{ orig.SetWindowTitle(_this, window); });
}

static void HTS_SetWindowSize(SDL_VideoDevice *_this, SDL_Window *window)
{
    HTS_OnMain(^{ orig.SetWindowSize(_this, window); });
}

static void HTS_GetWindowSizeInPixels(SDL_VideoDevice *_this, SDL_Window *window, int *w, int *h)
{
    HTS_OnMain(^{ orig.GetWindowSizeInPixels(_this, window, w, h); });
}

static void HTS_ShowWindow(SDL_VideoDevice *_this, SDL_Window *window)
{
    HTS_OnMain(^{ orig.ShowWindow(_this, window); });
}

static void HTS_HideWindow(SDL_VideoDevice *_this, SDL_Window *window)
{
    HTS_OnMain(^{ orig.HideWindow(_this, window); });
}

static void HTS_SetWindowBordered(SDL_VideoDevice *_this, SDL_Window *window, bool bordered)
{
    HTS_OnMain(^{ orig.SetWindowBordered(_this, window, bordered); });
}

static SDL_FullscreenResult HTS_SetWindowFullscreen(SDL_VideoDevice *_this, SDL_Window *window,
                                                    SDL_VideoDisplay *display, SDL_FullscreenOp op)
{
    __block SDL_FullscreenResult r = SDL_FULLSCREEN_FAILED;
    HTS_OnMain(^{ r = orig.SetWindowFullscreen(_this, window, display, op); });
    return r;
}

static void HTS_DestroyWindow(SDL_VideoDevice *_this, SDL_Window *window)
{
    HTS_OnMain(^{ orig.DestroyWindow(_this, window); });
}

static void HTS_PumpEvents(SDL_VideoDevice *_this)
{
    // Off the main thread there is no run loop of ours to spin: UIKit's main loop keeps running
    if ([NSThread isMainThread]) {
        orig.PumpEvents(_this);
    }
}

static bool HTS_SuspendScreenSaver(SDL_VideoDevice *_this)
{
    __block bool r = false;
    HTS_OnMain(^{ r = orig.SuspendScreenSaver(_this); });
    return r;
}

static bool HTS_StartTextInput(SDL_VideoDevice *_this, SDL_Window *window, SDL_PropertiesID props)
{
    __block bool r = false;
    HTS_OnMain(^{ r = orig.StartTextInput(_this, window, props); });
    return r;
}

static bool HTS_StopTextInput(SDL_VideoDevice *_this, SDL_Window *window)
{
    __block bool r = false;
    HTS_OnMain(^{ r = orig.StopTextInput(_this, window); });
    return r;
}

static bool HTS_UpdateTextInputArea(SDL_VideoDevice *_this, SDL_Window *window)
{
    __block bool r = false;
    HTS_OnMain(^{ r = orig.UpdateTextInputArea(_this, window); });
    return r;
}

static void HTS_SetTextInputProperties(SDL_VideoDevice *_this, SDL_Window *window, SDL_PropertiesID props)
{
    HTS_OnMain(^{ orig.SetTextInputProperties(_this, window, props); });
}

static SDL_MetalView HTS_Metal_CreateView(SDL_VideoDevice *_this, SDL_Window *window)
{
    __block SDL_MetalView r = NULL;
    HTS_OnMain(^{ r = orig.Metal_CreateView(_this, window); });
    return r;
}

static void HTS_Metal_DestroyView(SDL_VideoDevice *_this, SDL_MetalView view)
{
    HTS_OnMain(^{ orig.Metal_DestroyView(_this, view); });
}

static void *HTS_Metal_GetLayer(SDL_VideoDevice *_this, SDL_MetalView view)
{
    __block void *r = NULL;
    HTS_OnMain(^{ r = orig.Metal_GetLayer(_this, view); });
    return r;
}

// MARK: - EGL (ANGLE)

typedef void *EGLDisplay;
typedef void *EGLConfig;
typedef void *EGLSurface;
typedef void *EGLContext;
typedef int32_t EGLint;
typedef unsigned int EGLBoolean;
typedef unsigned int EGLenum;

#define EGL_DEFAULT_DISPLAY ((void *)0)
#define EGL_NO_CONTEXT ((EGLContext)0)
#define EGL_NO_SURFACE ((EGLSurface)0)
#define EGL_ALPHA_SIZE 0x3021
#define EGL_BLUE_SIZE 0x3022
#define EGL_GREEN_SIZE 0x3023
#define EGL_RED_SIZE 0x3024
#define EGL_DEPTH_SIZE 0x3025
#define EGL_STENCIL_SIZE 0x3026
#define EGL_SURFACE_TYPE 0x3033
#define EGL_NONE 0x3038
#define EGL_RENDERABLE_TYPE 0x3040
#define EGL_WINDOW_BIT 0x0004
#define EGL_PBUFFER_BIT 0x0001
#define EGL_OPENGL_ES2_BIT 0x0004
#define EGL_OPENGL_ES3_BIT 0x0040
#define EGL_CONTEXT_CLIENT_VERSION 0x3098
#define EGL_OPENGL_ES_API 0x30A0

static struct {
    void *lib;
    void *gles;
    void *gl;
    EGLDisplay display;
    EGLDisplay (*GetDisplay)(void *);
    EGLBoolean (*Initialize)(EGLDisplay, EGLint *, EGLint *);
    EGLBoolean (*BindAPI)(EGLenum);
    EGLBoolean (*ChooseConfig)(EGLDisplay, const EGLint *, EGLConfig *, EGLint, EGLint *);
    EGLSurface (*CreateWindowSurface)(EGLDisplay, EGLConfig, void *, const EGLint *);
    EGLContext (*CreateContext)(EGLDisplay, EGLConfig, EGLContext, const EGLint *);
    EGLBoolean (*MakeCurrent)(EGLDisplay, EGLSurface, EGLSurface, EGLContext);
    EGLBoolean (*SwapBuffers)(EGLDisplay, EGLSurface);
    EGLBoolean (*SwapInterval)(EGLDisplay, EGLint);
    EGLBoolean (*DestroyContext)(EGLDisplay, EGLContext);
    EGLBoolean (*DestroySurface)(EGLDisplay, EGLSurface);
    EGLint (*GetError)(void);
    void *(*GetProcAddress)(const char *);
} egl;

/** One EGL surface per SDL window, on the window's Metal view. */
typedef struct HTS_GLWindow {
    SDL_Window *window;
    SDL_MetalView view;
    EGLSurface surface;
    EGLConfig config;
    struct HTS_GLWindow *next;
} HTS_GLWindow;

static HTS_GLWindow *gl_windows;
static int swap_interval = 1;

static const char *HTS_Env(const char *name, const char *fallback)
{
    const char *v = SDL_getenv(name);
    return v && *v ? v : fallback;
}

static bool HTS_GL_LoadLibrary(SDL_VideoDevice *_this, const char *path)
{
    if (egl.lib) {
        return true;
    }
    const char *eglPath = path ? path : HTS_Env("HTS_EGL_LIBRARY", "@rpath/libEGL.framework/libEGL");
    egl.lib = dlopen(eglPath, RTLD_NOW | RTLD_GLOBAL);
    if (!egl.lib) {
        return SDL_SetError("HTS: can't load EGL %s: %s", eglPath, dlerror());
    }
    egl.gles = dlopen(HTS_Env("HTS_GLES_LIBRARY", "@rpath/libGLESv2.framework/libGLESv2"), RTLD_NOW | RTLD_GLOBAL);
    const char *glPath = SDL_getenv("HTS_GL_LIBRARY");
    if (glPath && *glPath) {
        egl.gl = dlopen(glPath, RTLD_NOW | RTLD_GLOBAL);
    }

#define HTS_EGL_FN(field, name)                                  \
    *(void **)&egl.field = dlsym(egl.lib, name);                 \
    if (!egl.field) {                                            \
        return SDL_SetError("HTS: EGL has no %s", name);         \
    }
    HTS_EGL_FN(GetDisplay, "eglGetDisplay")
    HTS_EGL_FN(Initialize, "eglInitialize")
    HTS_EGL_FN(BindAPI, "eglBindAPI")
    HTS_EGL_FN(ChooseConfig, "eglChooseConfig")
    HTS_EGL_FN(CreateWindowSurface, "eglCreateWindowSurface")
    HTS_EGL_FN(CreateContext, "eglCreateContext")
    HTS_EGL_FN(MakeCurrent, "eglMakeCurrent")
    HTS_EGL_FN(SwapBuffers, "eglSwapBuffers")
    HTS_EGL_FN(SwapInterval, "eglSwapInterval")
    HTS_EGL_FN(DestroyContext, "eglDestroyContext")
    HTS_EGL_FN(DestroySurface, "eglDestroySurface")
    HTS_EGL_FN(GetError, "eglGetError")
    HTS_EGL_FN(GetProcAddress, "eglGetProcAddress")
#undef HTS_EGL_FN

    egl.display = egl.GetDisplay(EGL_DEFAULT_DISPLAY);
    if (!egl.display || !egl.Initialize(egl.display, NULL, NULL)) {
        return SDL_SetError("HTS: eglInitialize failed: 0x%x", egl.GetError());
    }
    egl.BindAPI(EGL_OPENGL_ES_API);
    SDL_strlcpy(_this->gl_config.driver_path, eglPath, SDL_arraysize(_this->gl_config.driver_path));
    return true;
}

static void HTS_GL_UnloadLibrary(SDL_VideoDevice *_this)
{
    // ANGLE stays loaded: gl4es keeps pointers into it
}

static SDL_FunctionPointer HTS_GL_GetProcAddress(SDL_VideoDevice *_this, const char *proc)
{
    void *fn = NULL;
    if (egl.gl) {
        fn = dlsym(egl.gl, proc);
    }
    if (!fn && egl.gles) {
        fn = dlsym(egl.gles, proc);
    }
    if (!fn && egl.GetProcAddress) {
        fn = egl.GetProcAddress(proc);
    }
    return (SDL_FunctionPointer)fn;
}

static HTS_GLWindow *HTS_FindGLWindow(SDL_Window *window)
{
    for (HTS_GLWindow *w = gl_windows; w; w = w->next) {
        if (w->window == window) {
            return w;
        }
    }
    return NULL;
}

static HTS_GLWindow *HTS_GetGLWindow(SDL_VideoDevice *_this, SDL_Window *window)
{
    HTS_GLWindow *w = HTS_FindGLWindow(window);
    if (w) {
        return w;
    }
    const int es3 = _this->gl_config.major_version >= 3;
    const EGLint attribs[] = {
        EGL_RED_SIZE, SDL_max(_this->gl_config.red_size, 8),
        EGL_GREEN_SIZE, SDL_max(_this->gl_config.green_size, 8),
        EGL_BLUE_SIZE, SDL_max(_this->gl_config.blue_size, 8),
        EGL_ALPHA_SIZE, SDL_max(_this->gl_config.alpha_size, 8),
        EGL_DEPTH_SIZE, SDL_max(_this->gl_config.depth_size, 24),
        EGL_STENCIL_SIZE, SDL_max(_this->gl_config.stencil_size, 8),
        EGL_SURFACE_TYPE, EGL_WINDOW_BIT | EGL_PBUFFER_BIT,
        EGL_RENDERABLE_TYPE, es3 ? EGL_OPENGL_ES3_BIT : EGL_OPENGL_ES2_BIT,
        EGL_NONE
    };
    EGLConfig config = NULL;
    EGLint count = 0;
    if (!egl.ChooseConfig(egl.display, attribs, &config, 1, &count) || count < 1) {
        SDL_SetError("HTS: eglChooseConfig found nothing: 0x%x", egl.GetError());
        return NULL;
    }
    SDL_MetalView view = _this->Metal_CreateView(_this, window);
    if (!view) {
        return NULL;
    }
    void *layer = _this->Metal_GetLayer(_this, view);
    EGLSurface surface = egl.CreateWindowSurface(egl.display, config, layer, NULL);
    if (!surface) {
        SDL_SetError("HTS: eglCreateWindowSurface failed: 0x%x", egl.GetError());
        _this->Metal_DestroyView(_this, view);
        return NULL;
    }
    w = (HTS_GLWindow *)SDL_calloc(1, sizeof(*w));
    w->window = window;
    w->view = view;
    w->surface = surface;
    w->config = config;
    w->next = gl_windows;
    gl_windows = w;
    return w;
}

static SDL_GLContext HTS_GL_CreateContext(SDL_VideoDevice *_this, SDL_Window *window)
{
    if (!HTS_GL_LoadLibrary(_this, NULL)) {
        return NULL;
    }
    HTS_GLWindow *w = HTS_GetGLWindow(_this, window);
    if (!w) {
        return NULL;
    }
    const EGLint ctxAttribs[] = {
        EGL_CONTEXT_CLIENT_VERSION, _this->gl_config.major_version >= 3 ? 3 : 2,
        EGL_NONE
    };
    EGLContext share = _this->gl_config.share_with_current_context ? (EGLContext)SDL_GL_GetCurrentContext() : EGL_NO_CONTEXT;
    EGLContext ctx = egl.CreateContext(egl.display, w->config, share, ctxAttribs);
    if (!ctx) {
        SDL_SetError("HTS: eglCreateContext failed: 0x%x", egl.GetError());
        return NULL;
    }
    if (!egl.MakeCurrent(egl.display, w->surface, w->surface, ctx)) {
        SDL_SetError("HTS: eglMakeCurrent failed: 0x%x", egl.GetError());
        egl.DestroyContext(egl.display, ctx);
        return NULL;
    }
    egl.SwapInterval(egl.display, swap_interval);
    return (SDL_GLContext)ctx;
}

static bool HTS_GL_MakeCurrent(SDL_VideoDevice *_this, SDL_Window *window, SDL_GLContext context)
{
    if (!context) {
        egl.MakeCurrent(egl.display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        return true;
    }
    HTS_GLWindow *w = window ? HTS_GetGLWindow(_this, window) : NULL;
    EGLSurface surface = w ? w->surface : EGL_NO_SURFACE;
    if (!egl.MakeCurrent(egl.display, surface, surface, (EGLContext)context)) {
        return SDL_SetError("HTS: eglMakeCurrent failed: 0x%x", egl.GetError());
    }
    return true;
}

static bool HTS_GL_SetSwapInterval(SDL_VideoDevice *_this, int interval)
{
    swap_interval = interval < 0 ? 1 : interval;
    if (egl.display && !egl.SwapInterval(egl.display, swap_interval)) {
        return SDL_SetError("HTS: eglSwapInterval failed: 0x%x", egl.GetError());
    }
    return true;
}

static bool HTS_GL_GetSwapInterval(SDL_VideoDevice *_this, int *interval)
{
    *interval = swap_interval;
    return true;
}

static bool HTS_GL_SwapWindow(SDL_VideoDevice *_this, SDL_Window *window)
{
    HTS_GLWindow *w = HTS_FindGLWindow(window);
    if (!w) {
        return SDL_SetError("HTS: window has no EGL surface");
    }
    if (!egl.SwapBuffers(egl.display, w->surface)) {
        return SDL_SetError("HTS: eglSwapBuffers failed: 0x%x", egl.GetError());
    }
    return true;
}

static bool HTS_GL_DestroyContext(SDL_VideoDevice *_this, SDL_GLContext context)
{
    egl.DestroyContext(egl.display, (EGLContext)context);
    return true;
}

static void HTS_DestroyGLWindow(SDL_VideoDevice *_this, SDL_Window *window)
{
    for (HTS_GLWindow **p = &gl_windows; *p; p = &(*p)->next) {
        HTS_GLWindow *w = *p;
        if (w->window == window) {
            egl.DestroySurface(egl.display, w->surface);
            _this->Metal_DestroyView(_this, w->view);
            *p = w->next;
            SDL_free(w);
            return;
        }
    }
}

static void HTS_DestroyWindowWithGL(SDL_VideoDevice *_this, SDL_Window *window)
{
    HTS_DestroyGLWindow(_this, window);
    HTS_DestroyWindow(_this, window);
}

// MARK: - install

void HTS_UIKit_Install(SDL_VideoDevice *device)
{
#define HTS_WRAP(name)                    \
    if (device->name) {                   \
        orig.name = device->name;         \
        device->name = HTS_##name;        \
    }
    HTS_WRAP(VideoInit)
    HTS_WRAP(GetDisplayUsableBounds)
    HTS_WRAP(GetDisplayModes)
    HTS_WRAP(SetDisplayMode)
    HTS_WRAP(CreateSDLWindow)
    HTS_WRAP(SetWindowTitle)
    HTS_WRAP(SetWindowSize)
    HTS_WRAP(GetWindowSizeInPixels)
    HTS_WRAP(ShowWindow)
    HTS_WRAP(HideWindow)
    HTS_WRAP(SetWindowBordered)
    HTS_WRAP(SetWindowFullscreen)
    HTS_WRAP(DestroyWindow)
    HTS_WRAP(PumpEvents)
    HTS_WRAP(SuspendScreenSaver)
    HTS_WRAP(StartTextInput)
    HTS_WRAP(StopTextInput)
    HTS_WRAP(UpdateTextInputArea)
    HTS_WRAP(SetTextInputProperties)
    HTS_WRAP(Metal_CreateView)
    HTS_WRAP(Metal_DestroyView)
    HTS_WRAP(Metal_GetLayer)
#undef HTS_WRAP

    if (orig.DestroyWindow) {
        device->DestroyWindow = HTS_DestroyWindowWithGL;
    }
    device->GL_LoadLibrary = HTS_GL_LoadLibrary;
    device->GL_UnloadLibrary = HTS_GL_UnloadLibrary;
    device->GL_GetProcAddress = HTS_GL_GetProcAddress;
    device->GL_CreateContext = HTS_GL_CreateContext;
    device->GL_MakeCurrent = HTS_GL_MakeCurrent;
    device->GL_SetSwapInterval = HTS_GL_SetSwapInterval;
    device->GL_GetSwapInterval = HTS_GL_GetSwapInterval;
    device->GL_SwapWindow = HTS_GL_SwapWindow;
    device->GL_DestroyContext = HTS_GL_DestroyContext;
}

#endif // SDL_VIDEO_DRIVER_UIKIT
