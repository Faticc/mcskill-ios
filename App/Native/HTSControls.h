#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Touch controls over the game: once SDL's window shows up, a transparent window above it with a
 * movement stick, jump/sneak, Esc/inventory/chat/keyboard buttons, the hotbar, and the rest of the
 * screen as the camera (in the world) or the cursor (in menus). Input goes into SDL through the
 * HTS_* functions of our SDL build (sdl/SDL_uikit_hts.m).
 */
@interface HTSControls : NSObject

/** `sdlPath`: the libSDL3.dylib the game loads; `gameDir`: for options.txt (GUI scale). */
+ (void)startWithSDL:(NSString *)sdlPath gameDir:(NSString *)gameDir;

@end

NS_ASSUME_NONNULL_END
