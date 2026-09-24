/*
 * libhtsgl.dylib: what LWJGL loads as its OpenGL library (org.lwjgl.opengl.libname).
 *
 * The LWJGL fork of Amethyst asks the GL library for "eglGetProcAddress" first and takes every
 * GL function from it. gl4es doesn't export that symbol, so dlsym found the one of ANGLE's libEGL
 * (a dependency of gl4es) and the game drew with raw ANGLE ES functions next to gl4es's (clear
 * worked, immediate mode didn't). Here all lookups go to gl4es_GetProcAddress of the gl4es named
 * by HTS_GL_LIBRARY.
 */
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

#define EXPORT __attribute__((visibility("default")))

typedef void *(*ProcLookup)(const char *);

static ProcLookup lookup(void) {
    static ProcLookup fn;
    static int tried;
    if (!tried) {
        tried = 1;
        const char *path = getenv("HTS_GL_LIBRARY");
        void *gl4es = dlopen(path && *path ? path : "@rpath/libgl4es_114.dylib", RTLD_NOW | RTLD_GLOBAL);
        fn = gl4es ? (ProcLookup)dlsym(gl4es, "gl4es_GetProcAddress") : NULL;
        if (!fn) fprintf(stderr, "[HTS] libhtsgl: no gl4es_GetProcAddress in %s: %s\n", path, dlerror());
    }
    return fn;
}

EXPORT void *eglGetProcAddress(const char *name) {
    ProcLookup fn = lookup();
    return fn ? fn(name) : NULL;
}

EXPORT void *glXGetProcAddress(const char *name) {
    return eglGetProcAddress(name);
}

EXPORT void *glXGetProcAddressARB(const char *name) {
    return eglGetProcAddress(name);
}
