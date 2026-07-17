#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import <WebKit/WebKit.h>

@interface FloatingButtonManager : NSObject
@property (nonatomic, strong) UIButton *floatingButton;
@property (nonatomic, strong) NSTimer *keepOnTopTimer;
@property (nonatomic, weak) UIWindow *lastWindow;
@property (nonatomic, assign) BOOL jsHookEnabled;
@property (nonatomic, assign) BOOL wkHookEnabled;
+ (instancetype)sharedInstance;
- (void)showFloatingButton;
- (void)ensureButtonOnTop;
@end

@implementation FloatingButtonManager

+ (instancetype)sharedInstance {
    static FloatingButtonManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _jsHookEnabled = NO;
        _wkHookEnabled = NO;
    }
    return self;
}

- (void)showFloatingButton {
    if (self.floatingButton) {
        [self ensureButtonOnTop];
        return;
    }

    UIWindow *keyWindow = [self topmostWindow];
    if (!keyWindow) return;

    self.lastWindow = keyWindow;

    CGFloat buttonSize = 55.0;
    CGFloat padding = 20.0;
    CGFloat screenWidth = [[UIScreen mainScreen] bounds].size.width;
    CGFloat screenHeight = [[UIScreen mainScreen] bounds].size.height;

    self.floatingButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.floatingButton.frame = CGRectMake(
        screenWidth - buttonSize - padding,
        screenHeight / 2 - buttonSize / 2,
        buttonSize,
        buttonSize
    );

    self.floatingButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:1.0 alpha:0.85];
    self.floatingButton.layer.cornerRadius = buttonSize / 2;
    self.floatingButton.layer.shadowColor = [UIColor blackColor].CGColor;
    self.floatingButton.layer.shadowOffset = CGSizeMake(0, 2);
    self.floatingButton.layer.shadowRadius = 4;
    self.floatingButton.layer.shadowOpacity = 0.3;

    [self.floatingButton setTitle:@"+" forState:UIControlStateNormal];
    [self.floatingButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.floatingButton.titleLabel.font = [UIFont systemFontOfSize:28 weight:UIFontWeightBold];

    [self.floatingButton addTarget:self action:@selector(buttonTapped:) forControlEvents:UIControlEventTouchUpInside];

    UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self.floatingButton addGestureRecognizer:panGesture];

    [keyWindow addSubview:self.floatingButton];
    [keyWindow bringSubviewToFront:self.floatingButton];

    [self startKeepOnTopTimer];
}

- (void)startKeepOnTopTimer {
    [self.keepOnTopTimer invalidate];
    self.keepOnTopTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                            target:self
                                                          selector:@selector(ensureButtonOnTop)
                                                          userInfo:nil
                                                           repeats:YES];
}

- (void)ensureButtonOnTop {
    if (!self.floatingButton) return;

    UIWindow *topWindow = [self topmostWindow];
    if (!topWindow) return;

    if (self.floatingButton.superview != topWindow) {
        CGRect oldFrame = self.floatingButton.frame;
        [self.floatingButton removeFromSuperview];
        [topWindow addSubview:self.floatingButton];
        self.floatingButton.frame = oldFrame;
        self.lastWindow = topWindow;
    }

    [topWindow bringSubviewToFront:self.floatingButton];
}

- (UIWindow *)topmostWindow {
    NSArray *windows = nil;

    if (@available(iOS 13.0, *)) {
        NSMutableArray *allWindows = [NSMutableArray array];
        for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                [allWindows addObjectsFromArray:scene.windows];
            }
        }
        windows = allWindows;
    } else {
        windows = [UIApplication sharedApplication].windows;
    }

    UIWindow *topWindow = nil;
    for (UIWindow *window in windows) {
        if (!window.hidden && window.alpha > 0) {
            if (!topWindow || window.windowLevel > topWindow.windowLevel) {
                topWindow = window;
            }
        }
    }

    return topWindow ?: [UIApplication sharedApplication].keyWindow;
}

- (void)buttonTapped:(UIButton *)sender {
    UIWindow *keyWindow = [self topmostWindow];
    if (!keyWindow) return;

    UIViewController *topVC = [self topViewControllerFromWindow:keyWindow];
    if (!topVC) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🛠️ 功能菜单"
                                                                   message:@"请选择要执行的功能"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    NSString *hookStatus = @"";
    if (self.jsHookEnabled && self.wkHookEnabled) {
        hookStatus = @" (已启用)";
    } else if (self.jsHookEnabled) {
        hookStatus = @" (JS已启用)";
    } else if (self.wkHookEnabled) {
        hookStatus = @" (WK已启用)";
    }

    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"修改属性词条免广告刷新次数%@", hookStatus] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self enableScriptHooks];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"功能二（敬请期待）" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self showMessage:@"敬请期待" message:@"功能二正在开发中..."];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"功能三（敬请期待）" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self showMessage:@"敬请期待" message:@"功能三正在开发中..."];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"关闭悬浮窗" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self hideFloatingButton];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    dispatch_async(dispatch_get_main_queue(), ^{
        [topVC presentViewController:alert animated:YES completion:nil];
    });
}

// ========== 方案一：Hook JSContext 的 evaluateScript 方法 ==========
static id (*orig_JSContext_evaluateScript)(id self, SEL _cmd, NSString *script);
static id hook_JSContext_evaluateScript(id self, SEL _cmd, NSString *script) {
    if (![[FloatingButtonManager sharedInstance] jsHookEnabled]) {
        return orig_JSContext_evaluateScript(self, _cmd, script);
    }

    NSString *modifiedScript = [script stringByReplacingOccurrencesOfString:
        @".curLevel)?this.freeRefreshNum=2:this.freeRefreshNum=0"
        withString:@".curLevel),this.refreshNum=100,this.freeRefreshNum=100"];

    if (![modifiedScript isEqualToString:script]) {
        NSLog(@"[Tweak] JSContext evaluateScript: 已替换目标字符串");
    }

    return orig_JSContext_evaluateScript(self, _cmd, modifiedScript);
}

// ========== 方案二：Hook WKUserScript 的 initWithSource ==========
static id (*orig_WKUserScript_initWithSource)(id self, SEL _cmd, NSString *source, WKUserScriptInjectionTime injectionTime, BOOL forMainFrameOnly);
static id hook_WKUserScript_initWithSource(id self, SEL _cmd, NSString *source, WKUserScriptInjectionTime injectionTime, BOOL forMainFrameOnly) {
    if (![[FloatingButtonManager sharedInstance] wkHookEnabled]) {
        return orig_WKUserScript_initWithSource(self, _cmd, source, injectionTime, forMainFrameOnly);
    }

    NSString *modifiedSource = [source stringByReplacingOccurrencesOfString:
        @".curLevel)?this.freeRefreshNum=2:this.freeRefreshNum=0"
        withString:@".curLevel),this.refreshNum=100,this.freeRefreshNum=100"];

    if (![modifiedSource isEqualToString:source]) {
        NSLog(@"[Tweak] WKUserScript initWithSource: 已替换目标字符串");
    }

    return orig_WKUserScript_initWithSource(self, _cmd, modifiedSource, injectionTime, forMainFrameOnly);
}

// ========== 启用脚本 Hook ==========
- (void)enableScriptHooks {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        BOOL jsSuccess = NO;
        BOOL wkSuccess = NO;
        NSString *errorMsg = @"";

        // 方案一：Hook JSContext
        if (!self.jsHookEnabled) {
            Class jsContextClass = NSClassFromString(@"JSContext");
            if (jsContextClass) {
                SEL evaluateScriptSEL = NSSelectorFromString(@"evaluateScript:");
                Method origMethod = class_getInstanceMethod(jsContextClass, evaluateScriptSEL);
                if (origMethod) {
                    orig_JSContext_evaluateScript = (id (*)(id, SEL, NSString *))method_getImplementation(origMethod);
                    method_setImplementation(origMethod, (IMP)hook_JSContext_evaluateScript);
                    self.jsHookEnabled = YES;
                    jsSuccess = YES;
                    NSLog(@"[Tweak] JSContext evaluateScript: Hook 成功");
                } else {
                    errorMsg = [errorMsg stringByAppendingString:@"JSContext evaluateScript: 方法未找到\n"];
                }
            } else {
                errorMsg = [errorMsg stringByAppendingString:@"JSContext 类未找到\n"];
            }
        } else {
            jsSuccess = YES;
        }

        // 方案二：Hook WKUserScript
        if (!self.wkHookEnabled) {
            Class wkUserScriptClass = NSClassFromString(@"WKUserScript");
            if (wkUserScriptClass) {
                SEL initSEL = NSSelectorFromString(@"initWithSource:injectionTime:forMainFrameOnly:");
                Method origMethod = class_getInstanceMethod(wkUserScriptClass, initSEL);
                if (origMethod) {
                    orig_WKUserScript_initWithSource = (id (*)(id, SEL, NSString *, WKUserScriptInjectionTime, BOOL))method_getImplementation(origMethod);
                    method_setImplementation(origMethod, (IMP)hook_WKUserScript_initWithSource);
                    self.wkHookEnabled = YES;
                    wkSuccess = YES;
                    NSLog(@"[Tweak] WKUserScript initWithSource: Hook 成功");
                } else {
                    errorMsg = [errorMsg stringByAppendingString:@"WKUserScript initWithSource: 方法未找到\n"];
                }
            } else {
                errorMsg = [errorMsg stringByAppendingString:@"WKUserScript 类未找到\n"];
            }
        } else {
            wkSuccess = YES;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (jsSuccess && wkSuccess) {
                [self showMessage:@"Hook 启用成功" message:@"JSContext + WKUserScript 双方案已同时启用，脚本内容将在执行前自动替换。"];
            } else if (jsSuccess) {
                [self showMessage:@"部分 Hook 成功" message:[NSString stringWithFormat:@"JSContext Hook 已启用\nWKUserScript Hook 失败\n%@", errorMsg]];
            } else if (wkSuccess) {
                [self showMessage:@"部分 Hook 成功" message:[NSString stringWithFormat:@"WKUserScript Hook 已启用\nJSContext Hook 失败\n%@", errorMsg]];
            } else {
                [self showMessage:@"Hook 启用失败" message:[NSString stringWithFormat:@"两个方案均失败\n%@\n请确认目标应用使用了 JavaScriptCore 或 WebKit 框架。", errorMsg]];
            }
        });
    });
}

- (void)showMessage:(NSString *)title message:(NSString *)message {
    UIWindow *keyWindow = [self topmostWindow];
    if (!keyWindow) return;

    UIViewController *topVC = [self topViewControllerFromWindow:keyWindow];
    if (!topVC) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];

    dispatch_async(dispatch_get_main_queue(), ^{
        [topVC presentViewController:alert animated:YES completion:nil];
    });
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    UIView *button = gesture.view;
    CGPoint translation = [gesture translationInView:button.superview];
    button.center = CGPointMake(button.center.x + translation.x, button.center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:button.superview];
}

- (void)hideFloatingButton {
    [self.keepOnTopTimer invalidate];
    self.keepOnTopTimer = nil;
    [self.floatingButton removeFromSuperview];
    self.floatingButton = nil;
    self.lastWindow = nil;
}

- (UIViewController *)topViewControllerFromWindow:(UIWindow *)window {
    UIViewController *topVC = window.rootViewController;
    while (topVC.presentedViewController) {
        topVC = topVC.presentedViewController;
    }
    return topVC;
}

@end

__attribute__((constructor))
static void init() {
    @autoreleasepool {
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [[FloatingButtonManager sharedInstance] showFloatingButton];
            });
        }];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [[FloatingButtonManager sharedInstance] showFloatingButton];
        });
    }
}
