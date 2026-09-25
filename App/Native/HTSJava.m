// JIT detection and the JIT26 breakpoints follow Amethyst-iOS Natives/utils.m, the JVM options
// follow Natives/JavaLauncher.m (GPL-3.0).

#import "HTSJava.h"

#include <dirent.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <mach/mach.h>
#include <mach/mach_time.h>
#include <os/proc.h>
#include <pthread.h>
#include <sys/mman.h>
#include <unistd.h>

#include "jni.h"

#include <TargetConditionals.h>

#define CS_OPS_STATUS 0
#define CS_DEBUGGED 0x10000000
int csops(pid_t pid, unsigned int ops, void *useraddr, size_t usersize);

static NSString *const HTSJavaErrorDomain = @"HTSJava";

// MARK: - JIT26: breakpoints the StikDebug script handles (x16 = command)

#if defined(__arm64__)

__attribute__((noinline, naked))
static void *JIT26CreateRegionLegacy(size_t len) {
    asm("brk #0x69 \n"
        "ret");
}

__attribute__((noinline, naked))
static void BreakSendJITScript(const char *script, size_t len) {
    asm("mov x16, #2 \n"
        "brk #0xf00d \n"
        "ret");
}

__attribute__((noinline, naked))
static void JIT26SetDetachAfterFirstBr(BOOL value) {
    asm("mov x16, #3 \n"
        "brk #0xf00d \n"
        "ret");
}
#else
// x86_64 simulator slice: never called there (no TXM), only has to link
static void *JIT26CreateRegionLegacy(size_t len) { return NULL; }
static void BreakSendJITScript(const char *script, size_t len) {}
static void JIT26SetDetachAfterFirstBr(BOOL value) {}
#endif

static BOOL DebuggerAttached(void) {
    // getppid() is launchd (1) unless a debugger is attached
    return getppid() != 1;
}

// MARK: - device JIT flags

static BOOL DeviceCanCreateRXMap(void) {
    size_t page = getpagesize();
    uint32_t *map = mmap(NULL, page, PROT_READ | PROT_WRITE, MAP_ANONYMOUS | MAP_SHARED, -1, 0);
    if (map == MAP_FAILED) return NO;
    *map = 0xFFFFFFFF;
    int ret = mprotect(map, page, PROT_READ | PROT_EXEC);
    munmap(map, page);
    return ret == 0;
}

static BOOL DeviceHasTXMReal(void) {
    DIR *d = opendir("/private/preboot");
    if (!d) {
        // Not readable on newer iOS: guess by the chip
        NSUInteger (*MGGetSInt64Answer)(NSString *) = dlsym(RTLD_DEFAULT, "MGGetSInt64Answer");
        NSUInteger chip = MGGetSInt64Answer ? MGGetSInt64Answer(@"ChipID") : 0;
        switch (chip) {
            case 0x8020: // A12
            case 0x8027: // A12X/Z
                return NO;
            case 0x8030: // A13
            case 0x8101: // A14
            case 0x8103: // M1
                if (@available(iOS 27.0, *)) return YES;
                return NO;
            default:
                if (@available(iOS 19.0, *)) return YES;
                return NO;
        }
    }
    char txmPath[PATH_MAX] = {0};
    struct dirent *entry;
    while ((entry = readdir(d)) != NULL) {
        if (strlen(entry->d_name) == 96) {
            snprintf(txmPath, sizeof(txmPath),
                     "/private/preboot/%s/usr/standalone/firmware/FUD/Ap,TrustedExecutionMonitor.img4", entry->d_name);
            break;
        }
    }
    closedir(d);
    return txmPath[0] && access(txmPath, F_OK) == 0;
}

static HTSJITFlags ComputeJITFlags(void) {
    static HTSJITFlags flags;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // JIT_FLAGS overrides the detection, as in Amethyst
        const char *s = getenv("JIT_FLAGS");
        if (s) {
            flags = (HTSJITFlags)strtoul(s, NULL, 0);
            return;
        }
#if TARGET_OS_SIMULATOR
        // A macOS process underneath: no TXM, no debugger dance
        return;
#endif
        if (@available(iOS 26.0, *)) {
            flags |= HTSJITFlagIOS26;
            if (!DeviceCanCreateRXMap()) flags |= HTSJITFlagForceMirrored;
        }
        if (DeviceHasTXMReal()) flags |= HTSJITFlagTXM;
    });
    return flags;
}

/** libjvm looks this up with dlsym (else it reads XNU_HAS_TXM) to pick the JIT26 code path. */
__attribute__((used, visibility("default")))
BOOL DeviceHasTXM(void) {
    return (ComputeJITFlags() & HTSJITFlagTXM) != 0;
}

static BOOL RequiresTXMWorkaround(void) {
    HTSJITFlags f = ComputeJITFlags();
    return (f & (HTSJITFlagForceMirrored | HTSJITFlagTXM)) == (HTSJITFlagForceMirrored | HTSJITFlagTXM);
}

static BOOL JITEnabled(void) {
#if TARGET_OS_SIMULATOR
    // The simulator runs as a macOS process, where JIT isn't restricted (CI runs the probe there
    // with JREs retagged for the simulator platform)
    return YES;
#endif
    int flags = 0;
    csops(getpid(), CS_OPS_STATUS, &flags, sizeof(flags));
    if ((flags & CS_DEBUGGED) == 0) return NO;
    if (!RequiresTXMWorkaround()) return YES;
    // iOS 26 with TXM: the StikDebug script must still be attached
    return DebuggerAttached();
}

// MARK: - address space

/*
 * Without extended-virtual-addressing a 3 GB iPhone gets the small address space: the one big hole
 * is the ~2 GB below the dyld shared cache, and the Java heap has to be a single piece of it. The
 * launcher's own mappings (UIKit, ANGLE, downloads) would split that hole, so it is reserved when
 * the app loads and handed back right before JNI_CreateJavaVM. Mappings go first-fit from the
 * bottom, so the reservation leaves some slack below it: the launcher's allocations land there, and
 * later HotSpot's code cache, which it reserves before the heap.
 */
#define kMB ((size_t)1 << 20)
/** A hole this big means extended VA (or the simulator): nothing to guard. */
#define kPlentyVA (4096 * kMB)
#define kSlack (256 * kMB)
/** -XX:ReservedCodeCacheSize: 240 MB by default with tiered compilation. */
#define kCodeCacheMb 128
/** What the launcher and the JVM map into the hole besides the code cache and the heap. */
#define kOtherMappingsMb 64

static uint8_t *gReserve;
static size_t gReserveSize;
static size_t gHoleAtLoad;
/** The biggest -Xmx that should fit, 0 = no address space limit; set with the reservation. */
static int gMaxHeapMb;

static size_t LargestHole(void) {
    const size_t step = 16 * kMB;
    size_t lo = 0, hi = kPlentyVA / step;
    while (lo < hi) {
        size_t mid = (lo + hi + 1) / 2;
        void *map = mmap(NULL, mid * step, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (map != MAP_FAILED) {
            munmap(map, mid * step);
            lo = mid;
        } else {
            hi = mid - 1;
        }
    }
    return lo * step;
}

static void ReserveHeapSpace(void) {
    size_t hole = LargestHole();
    int mb = (int)(hole / kMB) - kCodeCacheMb - kOtherMappingsMb;
    gMaxHeapMb = hole >= kPlentyVA ? 0 : mb > 64 ? mb - mb % 64 : 64;
    if (hole >= kPlentyVA || hole <= 2 * kSlack) return;
    uint8_t *map = mmap(NULL, hole, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (map == MAP_FAILED) return;
    munmap(map, kSlack);
    gReserve = map + kSlack;
    gReserveSize = hole - kSlack;
}

static void ReleaseHeapSpace(void) {
    if (!gReserve) return;
    munmap(gReserve, gReserveSize);
    gReserve = NULL;
    gReserveSize = 0;
}

__attribute__((constructor))
static void ReserveHeapSpaceAtLoad(void) {
    gHoleAtLoad = LargestHole();
    ReserveHeapSpace();
}

/** Free gaps of 32 MB and more between the mappings, for jvm.log. */
static NSString *AddressSpaceGaps(void) {
    NSMutableArray<NSString *> *gaps = [NSMutableArray array];
    vm_address_t address = 0, end = 0;
    for (;;) {
        vm_size_t size = 0;
        vm_region_basic_info_data_64_t info;
        mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
        mach_port_t object = MACH_PORT_NULL;
        vm_address_t start = address;
        if (vm_region_64(mach_task_self(), &start, &size, VM_REGION_BASIC_INFO_64,
                         (vm_region_info_t)&info, &count, &object) != KERN_SUCCESS) break;
        if (end && start - end >= 32 * kMB) {
            [gaps addObject:[NSString stringWithFormat:@"0x%lx+%luM", (unsigned long)end, (unsigned long)((start - end) / kMB)]];
        }
        end = start + size;
        address = end;
    }
    return [NSString stringWithFormat:@"%@, last mapping ends at 0x%lx", [gaps componentsJoinedByString:@" "], (unsigned long)end];
}

static NSString *Entitlement(NSString *name) {
    void *security = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_NOW);
    void *(*createFromSelf)(CFAllocatorRef) = security ? dlsym(security, "SecTaskCreateFromSelf") : NULL;
    CFTypeRef (*copyValue)(void *, CFStringRef, CFErrorRef *) =
        security ? dlsym(security, "SecTaskCopyValueForEntitlement") : NULL;
    if (!createFromSelf || !copyValue) return @"?";
    void *task = createFromSelf(NULL);
    if (!task) return @"?";
    CFTypeRef value = copyValue(task, (__bridge CFStringRef)name, NULL);
    CFRelease(task);
    if (!value) return @"no";
    NSString *s = CFGetTypeID(value) == CFBooleanGetTypeID() ? (CFBooleanGetValue((CFBooleanRef)value) ? @"yes" : @"false")
                                                             : @"set";
    CFRelease(value);
    return s;
}

static void LogMemory(const char *when) {
    size_t available = os_proc_available_memory();
    printf("[HTS] memory %s: largest hole %zu MB (%zu MB at load), reserved %zu MB, available to the app %zu MB\n"
           "[HTS]   gaps: %s\n",
           when, LargestHole() / kMB, gHoleAtLoad / kMB, gReserveSize / kMB, available / kMB,
           AddressSpaceGaps().UTF8String);
}

// MARK: - JVM

typedef jint (JNICALL *CreateJavaVM_t)(JavaVM **, void **, void *);

static JavaVM *gVM;
static NSString *gLoadedHome;

@interface HTSProbeJob : NSObject
@property (copy) NSString *home;
@property int heapMb;
@property (copy) NSArray<NSString *> *extraArgs;
@property (copy) NSString *logPath;
/** Launch mode: the class whose main(String[]) runs on the JVM's thread; nil = probe. */
@property (copy) NSString *mainClass;
@property (copy) NSArray<NSString *> *mainArgs;
@property (copy) NSDictionary<NSString *, NSString *> *environment;
@property (strong) NSMutableDictionary<NSString *, id> *result;
@property (copy) NSString *failure;
@property (strong) dispatch_semaphore_t done;
@end

@implementation HTSProbeJob
@end

static double Millis(uint64_t start, uint64_t end) {
    static mach_timebase_info_data_t tb;
    if (tb.denom == 0) mach_timebase_info(&tb);
    return (double)(end - start) * tb.numer / tb.denom / 1e6;
}

/** Prints and clears a pending Java exception; YES if there was one. */
static BOOL TakeException(JNIEnv *env) {
    if (!(*env)->ExceptionCheck(env)) return NO;
    (*env)->ExceptionDescribe(env);
    (*env)->ExceptionClear(env);
    return YES;
}

static NSString *JavaString(JNIEnv *env, jstring value) {
    if (!value) return nil;
    const char *chars = (*env)->GetStringUTFChars(env, value, NULL);
    NSString *s = chars ? @(chars) : nil;
    if (chars) (*env)->ReleaseStringUTFChars(env, value, chars);
    return s;
}

static void RedirectStdio(NSString *path) {
    int fd = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd < 0) return;
    setvbuf(stdout, NULL, _IOLBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);
    dup2(fd, STDOUT_FILENO);
    dup2(fd, STDERR_FILENO);
    close(fd);
}

/** The TXM path of Amethyst's launchJVM: hand the extension script to StikDebug. */
static NSString *PrepareTXM(void) {
    size_t page = getpagesize();
    void *region = JIT26CreateRegionLegacy(page);
    if ((uint32_t)(uintptr_t)region != 0x690000E0) {
        munmap(region, page);
        return @"StikDebug запустил McSkill со старым скриптом JIT. Назначьте McSkill скрипт UniversalJIT26.js "
               @"(он лежит в «Файлы» → McSkill → JIT) и запустите заново.";
    }
    NSString *path = [NSBundle.mainBundle pathForResource:@"UniversalJIT26Extension" ofType:@"js"];
    NSString *script = path ? [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] : nil;
    if (!script) return @"В приложении нет UniversalJIT26Extension.js";
    BreakSendJITScript(script.UTF8String, strlen(script.UTF8String));
    JIT26SetDetachAfterFirstBr(YES);
    // Don't get stuck in EXC_BAD_ACCESS once the debugger is gone
    task_set_exception_ports(mach_task_self(), EXC_MASK_BAD_ACCESS, 0, EXCEPTION_DEFAULT, MACHINE_THREAD_STATE);
    return nil;
}

static NSString *StartVM(HTSProbeJob *job, JNIEnv **envOut) {
    NSString *home = job.home;
    NSFileManager *fm = NSFileManager.defaultManager;

    [job.environment enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        setenv(key.UTF8String, value.UTF8String, 1);
        printf("[HTS] env %s=%s\n", key.UTF8String, value.UTF8String);
    }];
    setenv("JAVA_HOME", home.fileSystemRepresentation, 1);
    setenv("HACK_IGNORE_START_ON_FIRST_THREAD", "1", 1);
    setenv("XNU_HAS_TXM", DeviceHasTXM() ? "1" : "0", 1);

    if (RequiresTXMWorkaround()) {
        NSString *error = PrepareTXM();
        if (error) return error;
    }
    printf("[HTS] entitlements: extended-virtual-addressing %s, increased-memory-limit %s\n",
           Entitlement(@"com.apple.developer.kernel.extended-virtual-addressing").UTF8String,
           Entitlement(@"com.apple.developer.kernel.increased-memory-limit").UTF8String);
    LogMemory("before the JVM");

    // libjli first so libjava finds it by install name, then libjvm
    NSString *jli8 = [home stringByAppendingPathComponent:@"lib/jli/libjli.dylib"];
    NSString *jli = [fm fileExistsAtPath:jli8] ? jli8 : [home stringByAppendingPathComponent:@"lib/libjli.dylib"];
    if (!dlopen(jli.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL)) {
        return [NSString stringWithFormat:@"libjli: %s", dlerror()];
    }
    NSString *jvm = [home stringByAppendingPathComponent:@"lib/server/libjvm.dylib"];
    void *libjvm = dlopen(jvm.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL);
    if (!libjvm) return [NSString stringWithFormat:@"libjvm: %s", dlerror()];
    CreateJavaVM_t create = (CreateJavaVM_t)dlsym(libjvm, "JNI_CreateJavaVM");
    if (!create) return @"В libjvm нет JNI_CreateJavaVM";

    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    // SDL on iOS refuses to start unless told that main() is set up (lwjgl3ify never does)
    const char *sdl = getenv("HTS_SDL_LIBRARY");
    if (sdl && *sdl) {
        void *lib = dlopen(sdl, RTLD_NOW | RTLD_GLOBAL);
        void (*setMainReady)(void) = lib ? (void (*)(void))dlsym(lib, "SDL_SetMainReady") : NULL;
        if (setMainReady) setMainReady();
        printf("[HTS] SDL %s: %s\n", sdl, lib ? "loaded" : dlerror());
    }

    NSMutableArray<NSString *> *args = [NSMutableArray arrayWithArray:@[
        @"-Xms64M",
        [NSString stringWithFormat:@"-Xmx%dM", job.heapMb],
        // Random stack guard allocation crashes (Amethyst)
        @"-XX:+UnlockExperimentalVMOptions",
        @"-XX:+DisablePrimordialThreadGuardPages",
        // Without the extended-virtual-addressing entitlement the compressed class space can't be reserved
        @"-XX:-UseCompressedClassPointers",
        // Reserved before the heap and out of the same hole (see ReserveHeapSpace)
        [NSString stringWithFormat:@"-XX:ReservedCodeCacheSize=%dM", kCodeCacheMb],
        [NSString stringWithFormat:@"-Djava.io.tmpdir=%@", NSTemporaryDirectory()],
        [NSString stringWithFormat:@"-Duser.home=%@", docs],
        [NSString stringWithFormat:@"-Duser.dir=%@", docs],
    ]];
    if (@available(iOS 26.0, *)) {
        [args addObject:@"-XX:+MirrorMappedCodeCache"];
    }
    [args addObjectsFromArray:job.extraArgs];
    if (job.mainClass) {
        NSString *command = [[@[job.mainClass] arrayByAddingObjectsFromArray:job.mainArgs ?: @[]]
                             componentsJoinedByString:@" "];
        [args addObject:[@"-Dsun.java.command=" stringByAppendingString:command]];
    }

    JavaVMOption *options = calloc(args.count, sizeof(JavaVMOption));
    for (NSUInteger i = 0; i < args.count; i++) {
        options[i].optionString = strdup(args[i].UTF8String);
        printf("[HTS] JVM option: %s\n", options[i].optionString);
    }
    JavaVMInitArgs init = {
        .version = JNI_VERSION_1_8,
        .nOptions = (jint)args.count,
        .options = options,
        .ignoreUnrecognized = JNI_FALSE,
    };

    // The heap's hole goes back only now, after the dylibs are mapped; HotSpot takes the code cache
    // from its bottom first, then the heap
    ReleaseHeapSpace();
    size_t hole = LargestHole();
    if (hole < kPlentyVA && hole / kMB < (size_t)(job.heapMb + kCodeCacheMb + 32)) {
        ReserveHeapSpace();
        LogMemory("too little");
        return [NSString stringWithFormat:@"Не хватает непрерывной виртуальной памяти на %d МБ: iOS даёт одним куском %zu МБ, "
                                          @"поставьте память не больше %d МБ", job.heapMb, hole / kMB, gMaxHeapMb];
    }

    // The JVM installs its own handlers
    signal(SIGSEGV, SIG_DFL);
    signal(SIGBUS, SIG_DFL);
    signal(SIGILL, SIG_DFL);
    signal(SIGFPE, SIG_DFL);
    signal(SIGPIPE, SIG_DFL);

    printf("[HTS] JNI_CreateJavaVM %s\n", home.UTF8String);
    uint64_t t0 = mach_absolute_time();
    JavaVM *vm = NULL;
    JNIEnv *env = NULL;
    jint rc = create(&vm, (void **)&env, &init);
    uint64_t t1 = mach_absolute_time();
    if (rc != JNI_OK) return [NSString stringWithFormat:@"JNI_CreateJavaVM вернул %d, подробности в jvm.log", rc];
    LogMemory("with the JVM");

    gVM = vm;
    gLoadedHome = [home copy];
    job.result[@"startMs"] = @(Millis(t0, t1));
    job.result[@"options"] = args;
    *envOut = env;
    return nil;
}

static void Measure(HTSProbeJob *job, JNIEnv *env) {
    NSMutableDictionary *result = job.result;

    jclass system = (*env)->FindClass(env, "java/lang/System");
    jmethodID getProperty = (*env)->GetStaticMethodID(env, system, "getProperty", "(Ljava/lang/String;)Ljava/lang/String;");
    NSMutableDictionary *props = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"java.version", @"java.vendor", @"java.vm.name", @"java.vm.version", @"java.vm.info",
                            @"java.home", @"os.name", @"os.version", @"os.arch"]) {
        jstring jkey = (*env)->NewStringUTF(env, key.UTF8String);
        jstring value = (*env)->CallStaticObjectMethod(env, system, getProperty, jkey);
        if (!TakeException(env)) {
            NSString *s = JavaString(env, value);
            if (s) props[key] = s;
        }
        (*env)->DeleteLocalRef(env, jkey);
        if (value) (*env)->DeleteLocalRef(env, value);
    }
    result[@"properties"] = props;

    jclass runtimeClass = (*env)->FindClass(env, "java/lang/Runtime");
    jobject runtime = (*env)->CallStaticObjectMethod(env, runtimeClass,
        (*env)->GetStaticMethodID(env, runtimeClass, "getRuntime", "()Ljava/lang/Runtime;"));
    result[@"processors"] = @((*env)->CallIntMethod(env, runtime,
        (*env)->GetMethodID(env, runtimeClass, "availableProcessors", "()I")));
    result[@"maxMemoryMb"] = @((*env)->CallLongMethod(env, runtime,
        (*env)->GetMethodID(env, runtimeClass, "maxMemory", "()J")) >> 20);
    TakeException(env);

    // Arrays.sort of the same million ints: interpreted rounds take seconds, compiled ones ~0.1 s
    const jsize count = 1000000;
    jint *numbers = malloc(sizeof(jint) * count);
    jclass arrays = (*env)->FindClass(env, "java/util/Arrays");
    jmethodID sort = (*env)->GetStaticMethodID(env, arrays, "sort", "([I)V");
    NSMutableArray<NSNumber *> *rounds = [NSMutableArray array];
    for (int round = 0; round < 6; round++) {
        uint32_t x = 2463534242u;
        for (jsize i = 0; i < count; i++) {
            x ^= x << 13; x ^= x >> 17; x ^= x << 5;
            numbers[i] = (jint)x;
        }
        jintArray array = (*env)->NewIntArray(env, count);
        (*env)->SetIntArrayRegion(env, array, 0, count, numbers);
        uint64_t t0 = mach_absolute_time();
        (*env)->CallStaticVoidMethod(env, arrays, sort, array);
        uint64_t t1 = mach_absolute_time();
        (*env)->DeleteLocalRef(env, array);
        if (TakeException(env)) break;
        [rounds addObject:@(Millis(t0, t1))];
        printf("[HTS] sort round %d: %.1f ms\n", round, Millis(t0, t1));
    }
    free(numbers);
    result[@"sortMs"] = rounds;

    // The JIT compiler as the JVM reports it; null when running interpreted only
    jclass factory = (*env)->FindClass(env, "java/lang/management/ManagementFactory");
    if (!TakeException(env) && factory) {
        jobject bean = (*env)->CallStaticObjectMethod(env, factory,
            (*env)->GetStaticMethodID(env, factory, "getCompilationMXBean", "()Ljava/lang/management/CompilationMXBean;"));
        if (!TakeException(env) && bean) {
            jclass beanClass = (*env)->FindClass(env, "java/lang/management/CompilationMXBean");
            NSString *name = JavaString(env, (*env)->CallObjectMethod(env, bean,
                (*env)->GetMethodID(env, beanClass, "getName", "()Ljava/lang/String;")));
            if (!TakeException(env) && name) result[@"compiler"] = name;
            jlong time = (*env)->CallLongMethod(env, bean,
                (*env)->GetMethodID(env, beanClass, "getTotalCompilationTime", "()J"));
            if (!TakeException(env)) result[@"compileMs"] = @(time);
        }
    }
    fflush(stdout);
}

/** Looks up main(String[]) of the job's class; nil and the reason in job.failure if it's not there. */
static jmethodID FindMain(HTSProbeJob *job, JNIEnv *env, jclass *classOut) {
    NSString *name = [job.mainClass stringByReplacingOccurrencesOfString:@"." withString:@"/"];
    jclass cls = (*env)->FindClass(env, name.UTF8String);
    if (!cls || TakeException(env)) {
        job.failure = [NSString stringWithFormat:@"Класс %@ не найден, подробности в jvm.log", job.mainClass];
        return NULL;
    }
    jmethodID main = (*env)->GetStaticMethodID(env, cls, "main", "([Ljava/lang/String;)V");
    if (!main || TakeException(env)) {
        job.failure = [NSString stringWithFormat:@"У %@ нет main(String[])", job.mainClass];
        return NULL;
    }
    *classOut = cls;
    return main;
}

static void RunMain(HTSProbeJob *job, JNIEnv *env, jclass cls, jmethodID main) {
    NSArray<NSString *> *mainArgs = job.mainArgs ?: @[];
    jclass stringClass = (*env)->FindClass(env, "java/lang/String");
    jobjectArray array = (*env)->NewObjectArray(env, (jsize)mainArgs.count, stringClass, NULL);
    for (NSUInteger i = 0; i < mainArgs.count; i++) {
        jstring s = (*env)->NewStringUTF(env, mainArgs[i].UTF8String);
        (*env)->SetObjectArrayElement(env, array, (jsize)i, s);
        (*env)->DeleteLocalRef(env, s);
    }
    printf("[HTS] %s.main(%lu args)\n", job.mainClass.UTF8String, (unsigned long)mainArgs.count);
    fflush(stdout);
    (*env)->CallStaticVoidMethod(env, cls, main, array);
    BOOL threw = TakeException(env);
    printf("[HTS] %s.main %s\n", job.mainClass.UTF8String, threw ? "threw, see above" : "returned");
    fflush(stdout);
}

static void *ProbeThread(void *arg) {
    HTSProbeJob *job = (__bridge_transfer HTSProbeJob *)arg;
    @autoreleasepool {
        JNIEnv *env = NULL;
        NSString *failure = StartVM(job, &env);
        if (failure) {
            job.failure = failure;
            dispatch_semaphore_signal(job.done);
            return NULL;
        }
        if (job.mainClass) {
            jclass cls = NULL;
            jmethodID main = FindMain(job, env, &cls);
            // The caller gets its answer once the game's main is found; the game runs on here
            dispatch_semaphore_signal(job.done);
            if (main) RunMain(job, env, cls, main);
        } else {
            Measure(job, env);
            dispatch_semaphore_signal(job.done);
        }
    }
    // This thread created the JVM and stays attached to it; it parks instead of exiting
    for (;;) pause();
}

@implementation HTSJava

+ (BOOL)jitEnabled {
    return JITEnabled();
}

+ (BOOL)debuggerAttached {
    return DebuggerAttached();
}

+ (HTSJITFlags)jitFlags {
    return ComputeJITFlags();
}

+ (NSInteger)maxHeapMb {
    return gMaxHeapMb;
}

+ (NSString *)loadedJavaHome {
    @synchronized(self) {
        return gLoadedHome;
    }
}

+ (NSDictionary<NSString *, id> *)probeJavaHome:(NSString *)javaHome
                                        heapMb:(int)heapMb
                                     extraArgs:(NSArray<NSString *> *)extraArgs
                                           log:(NSString *)logPath
                                         error:(NSError **)error {
    return [self runJavaHome:javaHome heapMb:heapMb jvmArgs:extraArgs mainClass:nil mainArgs:nil
                 environment:nil log:logPath error:error];
}

+ (BOOL)launchJavaHome:(NSString *)javaHome
                heapMb:(int)heapMb
               jvmArgs:(NSArray<NSString *> *)jvmArgs
             mainClass:(NSString *)mainClass
                  args:(NSArray<NSString *> *)args
           environment:(NSDictionary<NSString *, NSString *> *)environment
                   log:(NSString *)logPath
                 error:(NSError **)error {
    return [self runJavaHome:javaHome heapMb:heapMb jvmArgs:jvmArgs mainClass:mainClass mainArgs:args
                 environment:environment log:logPath error:error] != nil;
}

+ (NSDictionary<NSString *, id> *)runJavaHome:(NSString *)javaHome
                                      heapMb:(int)heapMb
                                     jvmArgs:(NSArray<NSString *> *)extraArgs
                                   mainClass:(NSString *)mainClass
                                    mainArgs:(NSArray<NSString *> *)mainArgs
                                 environment:(NSDictionary<NSString *, NSString *> *)environment
                                         log:(NSString *)logPath
                                       error:(NSError **)error {
    NSString *failure = nil;
    NSDictionary *result = nil;
    @synchronized(self) {
        if (gVM) {
            failure = [NSString stringWithFormat:@"В этом запуске уже работает %@. Вторую Java iOS в одном процессе не даёт: перезапустите приложение.",
                       gLoadedHome.lastPathComponent];
        } else if (!JITEnabled()) {
            failure = @"JIT не включён";
        } else {
            RedirectStdio(logPath);
            printf("\n[HTS] ===== %s, JIT flags 0x%X, debugger %d =====\n",
                   javaHome.lastPathComponent.UTF8String, ComputeJITFlags(), DebuggerAttached());

            HTSProbeJob *job = [HTSProbeJob new];
            job.home = javaHome;
            job.heapMb = heapMb;
            job.extraArgs = extraArgs;
            job.logPath = logPath;
            job.mainClass = mainClass;
            job.mainArgs = mainArgs;
            job.environment = environment;
            job.result = [NSMutableDictionary dictionary];
            job.done = dispatch_semaphore_create(0);

            // HotSpot wants a big stack on the thread that creates it, and the game runs on it
            pthread_attr_t attr;
            pthread_attr_init(&attr);
            pthread_attr_setstacksize(&attr, 16 << 20);
            pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
            pthread_t thread;
            int rc = pthread_create(&thread, &attr, ProbeThread, (__bridge_retained void *)job);
            pthread_attr_destroy(&attr);
            if (rc != 0) {
                failure = [NSString stringWithFormat:@"pthread_create: %d", rc];
            } else if (dispatch_semaphore_wait(job.done, dispatch_time(DISPATCH_TIME_NOW, 180 * NSEC_PER_SEC)) != 0) {
                failure = @"JVM не ответила за 3 минуты, смотрите jvm.log";
            } else if (job.failure) {
                failure = job.failure;
            } else {
                result = [job.result copy];
            }
        }
    }
    if (failure && error) {
        *error = [NSError errorWithDomain:HTSJavaErrorDomain code:1
                                 userInfo:@{NSLocalizedDescriptionKey: failure}];
    }
    return result;
}

@end
