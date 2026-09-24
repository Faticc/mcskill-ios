#import "HTSControls.h"

#import <UIKit/UIKit.h>
#include <dlfcn.h>

// SDL scancodes (SDL_scancode.h)
enum {
    SC_A = 4, SC_D = 7, SC_E = 8, SC_Q = 20, SC_S = 22, SC_T = 23, SC_W = 26,
    SC_1 = 30, SC_RETURN = 40, SC_ESCAPE = 41, SC_BACKSPACE = 42, SC_SPACE = 44,
    SC_F5 = 62, SC_LSHIFT = 225,
};
enum { BUTTON_LEFT = 1, BUTTON_RIGHT = 3 };

static struct {
    bool (*hasWindow)(void);
    bool (*relativeMouse)(void);
    void (*sendKey)(int, bool);
    void (*sendText)(const char *);
    void (*sendMotion)(bool, float, float);
    void (*sendButton)(int, bool);
    void (*sendWheel)(float, float);
    void **(*getWindows)(int *);
    bool (*sizeInPixels)(void *, int *, int *);
    void (*free)(void *);
} sdl;

static NSString *gameDir;

static void Key(int scancode, bool down) {
    if (sdl.sendKey) sdl.sendKey(scancode, down);
}

static void Tap(int scancode) {
    Key(scancode, true);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        Key(scancode, false);
    });
}

// MARK: - button

@interface HTSButton : UILabel
@property int scancode;
@property BOOL toggle;
@property BOOL on;
@end

@implementation HTSButton
- (instancetype)initWithTitle:(NSString *)title scancode:(int)scancode {
    if ((self = [super initWithFrame:CGRectZero])) {
        self.text = title;
        self.scancode = scancode;
        self.textAlignment = NSTextAlignmentCenter;
        self.textColor = UIColor.whiteColor;
        self.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
        self.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.35];
        self.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.35].CGColor;
        self.layer.borderWidth = 1.5;
        self.layer.masksToBounds = YES;
        self.userInteractionEnabled = NO;
    }
    return self;
}

- (void)setPressed:(BOOL)pressed {
    self.backgroundColor = [UIColor colorWithWhite:pressed ? 0.6 : 0.1 alpha:pressed ? 0.5 : 0.35];
}
@end

// MARK: - text input

@interface HTSTextSink : UITextField <UITextFieldDelegate>
@end

@implementation HTSTextSink
- (instancetype)init {
    if ((self = [super initWithFrame:CGRectMake(0, 0, 1, 1)])) {
        self.delegate = self;
        self.alpha = 0.01;
        self.autocorrectionType = UITextAutocorrectionTypeNo;
        self.autocapitalizationType = UITextAutocapitalizationTypeNone;
        self.spellCheckingType = UITextSpellCheckingTypeNo;
        self.returnKeyType = UIReturnKeySend;
        // One space so backspace has something to delete (and reaches us)
        self.text = @" ";
    }
    return self;
}

- (BOOL)textField:(UITextField *)field shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)text {
    if (text.length == 0) {
        Tap(SC_BACKSPACE);
    } else if (sdl.sendText) {
        sdl.sendText(text.UTF8String);
    }
    return NO;
}

- (BOOL)textFieldShouldReturn:(UITextField *)field {
    Tap(SC_RETURN);
    return NO;
}
@end

// MARK: - controls view

typedef NS_ENUM(NSInteger, HTSTouchRole) {
    HTSTouchButton,
    HTSTouchStick,
    HTSTouchLook,
    HTSTouchPointer,
    HTSTouchIgnored,
};

@interface HTSTouch : NSObject
@property HTSTouchRole role;
@property (weak) HTSButton *button;
@property CGPoint start;
@property CGPoint last;
@property NSTimeInterval began;
@property BOOL moved;
@property BOOL breaking;
@end

@implementation HTSTouch
@end

@interface HTSControlsView : UIView
@end

@implementation HTSControlsView {
    NSMapTable<UITouch *, HTSTouch *> *touches;
    NSArray<HTSButton *> *buttons;
    HTSButton *sneak;
    HTSButton *keyboard;
    UIView *stickBase;
    UIView *stickKnob;
    HTSTextSink *textSink;
    NSTimer *breakTimer;
    BOOL keyW, keyA, keyS, keyD;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.multipleTouchEnabled = YES;
        self.backgroundColor = UIColor.clearColor;
        touches = [NSMapTable strongToStrongObjectsMapTable];

        stickBase = [[UIView alloc] init];
        stickBase.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.25];
        stickBase.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.3].CGColor;
        stickBase.layer.borderWidth = 1.5;
        stickBase.userInteractionEnabled = NO;
        [self addSubview:stickBase];
        stickKnob = [[UIView alloc] init];
        stickKnob.backgroundColor = [UIColor colorWithWhite:1 alpha:0.35];
        stickKnob.userInteractionEnabled = NO;
        [self addSubview:stickKnob];

        HTSButton *jump = [[HTSButton alloc] initWithTitle:@"⤒" scancode:SC_SPACE];
        sneak = [[HTSButton alloc] initWithTitle:@"⇩" scancode:SC_LSHIFT];
        sneak.toggle = YES;
        HTSButton *pause = [[HTSButton alloc] initWithTitle:@"II" scancode:SC_ESCAPE];
        HTSButton *inventory = [[HTSButton alloc] initWithTitle:@"E" scancode:SC_E];
        HTSButton *chat = [[HTSButton alloc] initWithTitle:@"T" scancode:SC_T];
        HTSButton *drop = [[HTSButton alloc] initWithTitle:@"Q" scancode:SC_Q];
        HTSButton *view = [[HTSButton alloc] initWithTitle:@"F5" scancode:SC_F5];
        keyboard = [[HTSButton alloc] initWithTitle:@"⌨" scancode:0];
        buttons = @[jump, sneak, pause, inventory, chat, drop, view, keyboard];
        for (HTSButton *b in buttons) [self addSubview:b];

        textSink = [HTSTextSink new];
        [self addSubview:textSink];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    UIEdgeInsets safe = self.safeAreaInsets;
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    CGFloat left = MAX(safe.left, 16) + 8, right = w - MAX(safe.right, 16) - 8;

    CGFloat stick = 150;
    stickBase.frame = CGRectMake(left, h - stick - 18, stick, stick);
    stickBase.layer.cornerRadius = stick / 2;
    [self centerKnob];

    CGFloat big = 64, small = 44, gap = 10;
    HTSButton *jump = buttons[0];
    jump.frame = CGRectMake(right - big, h - big - 30, big, big);
    sneak.frame = CGRectMake(right - big - gap - big, h - big - 18, big, big);
    NSArray<HTSButton *> *top = [buttons subarrayWithRange:NSMakeRange(2, 6)];
    CGFloat x = right - small;
    for (HTSButton *b in top) {
        b.frame = CGRectMake(x, 10, small, small);
        x -= small + gap;
    }
    for (HTSButton *b in buttons) b.layer.cornerRadius = b.bounds.size.width / 2;
    stickKnob.layer.cornerRadius = 28;
}

- (void)centerKnob {
    CGPoint c = CGPointMake(CGRectGetMidX(stickBase.frame), CGRectGetMidY(stickBase.frame));
    stickKnob.frame = CGRectMake(c.x - 28, c.y - 28, 56, 56);
}

// MARK: hotbar

/** Minecraft's GUI scale: options.txt guiScale, 0 = the largest that keeps 320x240. */
- (CGRect)hotbarRect {
    int pw = 0, ph = 0;
    if (sdl.getWindows && sdl.sizeInPixels) {
        int count = 0;
        void **windows = sdl.getWindows(&count);
        if (count > 0) sdl.sizeInPixels(windows[0], &pw, &ph);
        if (windows && sdl.free) sdl.free(windows);
    }
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    if (pw <= 0 || ph <= 0) {
        pw = (int)w;
        ph = (int)h;
    }
    int setting = 0;
    NSString *options = [NSString stringWithContentsOfFile:[gameDir stringByAppendingPathComponent:@"options.txt"]
                                                  encoding:NSUTF8StringEncoding error:nil];
    for (NSString *line in [options componentsSeparatedByString:@"\n"]) {
        if ([line hasPrefix:@"guiScale:"]) setting = [line substringFromIndex:9].intValue;
    }
    int scale = 1;
    while ((setting == 0 || scale < setting) && pw / (scale + 1) >= 320 && ph / (scale + 1) >= 240) scale++;
    CGFloat pointsPerPixel = w / pw;
    CGFloat hw = 182 * scale * pointsPerPixel, hh = 22 * scale * pointsPerPixel;
    return CGRectMake((w - hw) / 2, h - hh, hw, hh);
}

// MARK: touches

- (HTSButton *)buttonAt:(CGPoint)p {
    for (HTSButton *b in buttons) {
        if (CGRectContainsPoint(CGRectInset(b.frame, -8, -8), p)) return b;
    }
    return nil;
}

- (void)touchesBegan:(NSSet<UITouch *> *)set withEvent:(UIEvent *)event {
    BOOL relative = sdl.relativeMouse && sdl.relativeMouse();
    for (UITouch *touch in set) {
        CGPoint p = [touch locationInView:self];
        HTSTouch *t = [HTSTouch new];
        t.start = t.last = p;
        t.began = touch.timestamp;
        HTSButton *button = [self buttonAt:p];
        if (button) {
            t.role = HTSTouchButton;
            t.button = button;
            [self press:button down:YES];
        } else if (relative && CGRectContainsPoint(CGRectInset(stickBase.frame, -30, -30), p)) {
            t.role = HTSTouchStick;
            [self moveStick:p];
        } else if (relative && CGRectContainsPoint([self hotbarRect], p)) {
            CGRect bar = [self hotbarRect];
            int slot = (int)((p.x - bar.origin.x) / (bar.size.width / 9));
            Tap(SC_1 + MAX(0, MIN(8, slot)));
            t.role = HTSTouchIgnored;
        } else if (relative) {
            t.role = HTSTouchLook;
            [self scheduleBreak];
        } else {
            t.role = HTSTouchPointer;
            if (sdl.sendMotion) sdl.sendMotion(false, p.x, p.y);
            if (sdl.sendButton) sdl.sendButton(BUTTON_LEFT, true);
        }
        [touches setObject:t forKey:touch];
    }
}

- (void)touchesMoved:(NSSet<UITouch *> *)set withEvent:(UIEvent *)event {
    for (UITouch *touch in set) {
        HTSTouch *t = [touches objectForKey:touch];
        if (!t) continue;
        CGPoint p = [touch locationInView:self];
        switch (t.role) {
            case HTSTouchStick:
                [self moveStick:p];
                break;
            case HTSTouchLook: {
                CGFloat dx = p.x - t.last.x, dy = p.y - t.last.y;
                if (hypot(p.x - t.start.x, p.y - t.start.y) > 10) {
                    t.moved = YES;
                    if (!t.breaking) [breakTimer invalidate];
                }
                if (sdl.sendMotion) sdl.sendMotion(true, dx * 2.2f, dy * 2.2f);
                break;
            }
            case HTSTouchPointer:
                if (sdl.sendMotion) sdl.sendMotion(false, p.x, p.y);
                break;
            default:
                break;
        }
        t.last = p;
    }
}

- (void)touchesEnded:(NSSet<UITouch *> *)set withEvent:(UIEvent *)event {
    for (UITouch *touch in set) {
        HTSTouch *t = [touches objectForKey:touch];
        if (!t) continue;
        switch (t.role) {
            case HTSTouchButton:
                [self press:t.button down:NO];
                break;
            case HTSTouchStick:
                [self releaseStick];
                break;
            case HTSTouchLook:
                [breakTimer invalidate];
                if (t.breaking) {
                    if (sdl.sendButton) sdl.sendButton(BUTTON_LEFT, false);
                } else if (!t.moved && touch.timestamp - t.began < 0.3) {
                    // A short tap uses the held item or places a block, as on Bedrock
                    if (sdl.sendButton) {
                        sdl.sendButton(BUTTON_RIGHT, true);
                        sdl.sendButton(BUTTON_RIGHT, false);
                    }
                }
                break;
            case HTSTouchPointer:
                if (sdl.sendButton) sdl.sendButton(BUTTON_LEFT, false);
                break;
            default:
                break;
        }
        [touches removeObjectForKey:touch];
    }
}

- (void)touchesCancelled:(NSSet<UITouch *> *)set withEvent:(UIEvent *)event {
    [self touchesEnded:set withEvent:event];
}

/** Holding still in the world breaks the block under the crosshair. */
- (void)scheduleBreak {
    [breakTimer invalidate];
    __weak HTSControlsView *weakSelf = self;
    breakTimer = [NSTimer scheduledTimerWithTimeInterval:0.3 repeats:NO block:^(NSTimer *timer) {
        HTSControlsView *view = weakSelf;
        if (!view) return;
        for (UITouch *touch in view->touches) {
            HTSTouch *t = [view->touches objectForKey:touch];
            if (t.role == HTSTouchLook && !t.moved && !t.breaking) {
                t.breaking = YES;
                if (sdl.sendButton) sdl.sendButton(BUTTON_LEFT, true);
                break;
            }
        }
    }];
}

- (void)press:(HTSButton *)button down:(BOOL)down {
    if (button == keyboard) {
        if (down) {
            if (textSink.isFirstResponder) [textSink resignFirstResponder];
            else [textSink becomeFirstResponder];
        }
        [button setPressed:down];
        return;
    }
    if (button.toggle) {
        if (!down) return;
        button.on = !button.on;
        [button setPressed:button.on];
        Key(button.scancode, button.on);
        return;
    }
    [button setPressed:down];
    Key(button.scancode, down);
}

- (void)moveStick:(CGPoint)p {
    CGPoint c = CGPointMake(CGRectGetMidX(stickBase.frame), CGRectGetMidY(stickBase.frame));
    CGFloat dx = p.x - c.x, dy = p.y - c.y;
    CGFloat radius = stickBase.bounds.size.width / 2;
    CGFloat len = hypot(dx, dy);
    if (len > radius) {
        dx = dx / len * radius;
        dy = dy / len * radius;
    }
    stickKnob.center = CGPointMake(c.x + dx, c.y + dy);
    CGFloat dead = radius * 0.3;
    [self setW:dy < -dead a:dx < -dead s:dy > dead d:dx > dead];
}

- (void)releaseStick {
    [self centerKnob];
    [self setW:NO a:NO s:NO d:NO];
}

- (void)setW:(BOOL)w a:(BOOL)a s:(BOOL)s d:(BOOL)d {
    if (w != keyW) Key(SC_W, keyW = w);
    if (a != keyA) Key(SC_A, keyA = a);
    if (s != keyS) Key(SC_S, keyS = s);
    if (d != keyD) Key(SC_D, keyD = d);
}
@end

// MARK: - window

@interface HTSControlsViewController : UIViewController
@end

@implementation HTSControlsViewController
- (void)loadView {
    self.view = [[HTSControlsView alloc] initWithFrame:UIScreen.mainScreen.bounds];
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (BOOL)prefersHomeIndicatorAutoHidden {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskLandscape;
}
@end

@implementation HTSControls

static UIWindow *overlay;
static NSTimer *watch;

+ (void)startWithSDL:(NSString *)sdlPath gameDir:(NSString *)dir {
    gameDir = [dir copy];
    void *lib = dlopen(sdlPath.fileSystemRepresentation, RTLD_NOW | RTLD_GLOBAL);
    if (!lib) {
        NSLog(@"[HTS] controls: no SDL: %s", dlerror());
        return;
    }
    *(void **)&sdl.hasWindow = dlsym(lib, "HTS_HasGameWindow");
    *(void **)&sdl.relativeMouse = dlsym(lib, "HTS_RelativeMouse");
    *(void **)&sdl.sendKey = dlsym(lib, "HTS_SendKey");
    *(void **)&sdl.sendText = dlsym(lib, "HTS_SendText");
    *(void **)&sdl.sendMotion = dlsym(lib, "HTS_SendMouseMotion");
    *(void **)&sdl.sendButton = dlsym(lib, "HTS_SendMouseButton");
    *(void **)&sdl.sendWheel = dlsym(lib, "HTS_SendMouseWheel");
    *(void **)&sdl.getWindows = dlsym(lib, "SDL_GetWindows");
    *(void **)&sdl.sizeInPixels = dlsym(lib, "SDL_GetWindowSizeInPixels");
    *(void **)&sdl.free = dlsym(lib, "SDL_free");

    dispatch_async(dispatch_get_main_queue(), ^{
        [watch invalidate];
        // The game creates its window some seconds into loading; the controls go above it
        watch = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) {
            UIWindow *game = [self gameWindow];
            if (!game || overlay) return;
            overlay = [[UIWindow alloc] initWithWindowScene:game.windowScene];
            overlay.windowLevel = game.windowLevel + 1;
            overlay.backgroundColor = UIColor.clearColor;
            overlay.rootViewController = [HTSControlsViewController new];
            // Visible but not key: a hardware keyboard keeps talking to SDL's window
            overlay.hidden = NO;
            [timer invalidate];
        }];
    });
}

+ (UIWindow *)gameWindow {
    // SDL3 makes a plain UIWindow; its root view controller is SDL's
    Class sdlController = NSClassFromString(@"SDL_uikitviewcontroller");
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (sdlController && [window.rootViewController isKindOfClass:sdlController] && !window.hidden) return window;
        }
    }
    return nil;
}

@end
