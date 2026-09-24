#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/** How JIT has to be obtained on this device (Amethyst's JITFlags). */
typedef NS_OPTIONS(uint32_t, HTSJITFlags) {
    HTSJITFlagIOS26 NS_SWIFT_NAME(iOS26) = 1 << 0,
    /** RX pages can't be made directly: HotSpot needs its mirrored code cache. */
    HTSJITFlagForceMirrored NS_SWIFT_NAME(forceMirrored) = 1 << 1,
    /** Trusted Execution Monitor: JIT only through a debugger kept attached (StikDebug script). */
    HTSJITFlagTXM NS_SWIFT_NAME(txm) = 1 << 2,
};

/**
 * The JVM side of the app, from Amethyst-iOS (GPL-3.0): the JIT checks, the JIT26 breakpoints the
 * StikDebug script answers, and a JVM started inside this process. iOS allows one JVM per
 * process, and it can't be unloaded: another Java version needs the app restarted.
 */
@interface HTSJava : NSObject

/** CS_DEBUGGED is set (and, where TXM needs it, the debugger is still attached). */
@property (class, readonly) BOOL jitEnabled;
/** A debugger (StikDebug) is attached right now. */
@property (class, readonly) BOOL debuggerAttached;
@property (class, readonly) HTSJITFlags jitFlags;
/** Java home of the JVM running in this process, nil before the first start. */
@property (class, readonly, nullable) NSString *loadedJavaHome;

/**
 * Starts the JVM of `javaHome` in this process and measures it: system properties, the JIT
 * compiler, `Arrays.sort` rounds (fast later rounds mean the JIT works). Blocks for seconds.
 * stdout and stderr go to `logPath` from then on. Without JIT the process dies here, so the
 * caller checks `jitEnabled` first.
 */
+ (nullable NSDictionary<NSString *, id> *)probeJavaHome:(NSString *)javaHome
                                                 heapMb:(int)heapMb
                                              extraArgs:(NSArray<NSString *> *)extraArgs
                                                    log:(NSString *)logPath
                                                  error:(NSError **)error;

/**
 * Starts the JVM of `javaHome` in this process and runs `mainClass.main(args)` on the JVM's own
 * thread (16 MB stack). Returns once the class and its main are found; the program keeps running.
 * `environment` is set before the JVM starts; HTS_SDL_LIBRARY there gets SDL_SetMainReady called.
 * When the program calls System.exit, the app exits with it.
 */
+ (BOOL)launchJavaHome:(NSString *)javaHome
                heapMb:(int)heapMb
               jvmArgs:(NSArray<NSString *> *)jvmArgs
             mainClass:(NSString *)mainClass
                  args:(NSArray<NSString *> *)args
           environment:(NSDictionary<NSString *, NSString *> *)environment
                   log:(NSString *)logPath
                 error:(NSError **)error NS_SWIFT_NAME(launch(javaHome:heapMb:jvmArgs:mainClass:args:environment:log:));

@end

NS_ASSUME_NONNULL_END
