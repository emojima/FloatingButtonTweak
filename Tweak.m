#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import <WebKit/WebKit.h>
#import <mach/mach.h>
#import <mach/vm_map.h>
#import <setjmp.h>
#import <signal.h>

@interface FloatingButtonManager : NSObject
@property (nonatomic, strong) UIButton *floatingButton;
@property (nonatomic, strong) NSTimer *keepOnTopTimer;
@property (nonatomic, weak) UIWindow *lastWindow;
@property (nonatomic, assign) int totalReplacedCount;
@property (nonatomic, assign) int totalHookedMethods;
+ (instancetype)sharedInstance;
- (void)showFloatingButton;
- (void)ensureButtonOnTop;
@end

@interface LogWindowManager : NSObject
@property (nonatomic, strong) UIView *logContainerView;
@property (nonatomic, strong) UITextView *logTextView;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UIView *titleBar;
@property (nonatomic, strong) NSMutableString *logBuffer;
@property (nonatomic, assign) BOOL isVisible;
@property (nonatomic, assign) CGPoint lastTranslation;
+ (instancetype)sharedInstance;
- (void)toggleLogWindow;
- (void)showLogWindow;
- (void)hideLogWindow;
- (void)appendLog:(NSString *)log;
- (void)appendLogsBatch:(NSArray *)logs;
@end

@implementation LogWindowManager

+ (instancetype)sharedInstance {
    static LogWindowManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _logBuffer = [NSMutableString string];
        _isVisible = NO;
        _lastTranslation = CGPointZero;
    }
    return self;
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

- (void)toggleLogWindow {
    if (self.isVisible) {
        [self hideLogWindow];
    } else {
        [self showLogWindow];
    }
}

- (void)showLogWindow {
    if (self.logContainerView) {
        self.logContainerView.hidden = NO;
        self.isVisible = YES;
        UIWindow *topWindow = [self topmostWindow];
        if (topWindow) {
            UIButton *fb = [[FloatingButtonManager sharedInstance] floatingButton];
            if (fb && fb.superview == topWindow) {
                [topWindow insertSubview:self.logContainerView belowSubview:fb];
            } else {
                [topWindow bringSubviewToFront:self.logContainerView];
            }
        }
        return;
    }

    UIWindow *topWindow = [self topmostWindow];
    if (!topWindow) return;

    CGFloat screenWidth = [[UIScreen mainScreen] bounds].size.width;
    CGFloat screenHeight = [[UIScreen mainScreen] bounds].size.height;
    CGFloat windowWidth = screenWidth * 0.9;
    CGFloat windowHeight = screenHeight * 0.55;
    CGFloat windowX = (screenWidth - windowWidth) / 2;
    CGFloat windowY = screenHeight * 0.12;

    self.logContainerView = [[UIView alloc] initWithFrame:CGRectMake(windowX, windowY, windowWidth, windowHeight)];
    self.logContainerView.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:0.92];
    self.logContainerView.layer.cornerRadius = 12;
    self.logContainerView.layer.masksToBounds = YES;

    self.titleBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, windowWidth, 36)];
    self.titleBar.backgroundColor = [UIColor colorWithRed:0.15 green:0.15 blue:0.15 alpha:1.0];
    [self.logContainerView addSubview:self.titleBar];

    UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleTitleBarPan:)];
    [self.titleBar addGestureRecognizer:panGesture];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 0, windowWidth - 80, 36)];
    titleLabel.text = @"📋 Tweak 日志（拖动标题栏移动）";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [self.titleBar addSubview:titleLabel];

    self.closeButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.closeButton.frame = CGRectMake(windowWidth - 50, 4, 40, 28);
    [self.closeButton setTitle:@"✕" forState:UIControlStateNormal];
    [self.closeButton setTitleColor:[UIColor colorWithRed:1.0 green:0.3 blue:0.3 alpha:1.0] forState:UIControlStateNormal];
    self.closeButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [self.closeButton addTarget:self action:@selector(hideLogWindow) forControlEvents:UIControlEventTouchUpInside];
    [self.titleBar addSubview:self.closeButton];

    self.logTextView = [[UITextView alloc] initWithFrame:CGRectMake(8, 44, windowWidth - 16, windowHeight - 52)];
    self.logTextView.backgroundColor = [UIColor clearColor];
    self.logTextView.textColor = [UIColor colorWithRed:0.8 green:0.9 blue:1.0 alpha:1.0];
    self.logTextView.font = [UIFont fontWithName:@"Menlo" size:11];
    self.logTextView.editable = NO;
    self.logTextView.selectable = YES;
    self.logTextView.scrollEnabled = YES;
    self.logTextView.showsVerticalScrollIndicator = YES;
    self.logTextView.textContainerInset = UIEdgeInsetsMake(4, 4, 4, 4);
    self.logTextView.text = self.logBuffer;
    [self.logContainerView addSubview:self.logTextView];

    UIButton *fb = [[FloatingButtonManager sharedInstance] floatingButton];
    if (fb && fb.superview == topWindow) {
        [topWindow insertSubview:self.logContainerView belowSubview:fb];
    } else {
        [topWindow addSubview:self.logContainerView];
    }

    self.logContainerView.hidden = NO;
    self.isVisible = YES;
}

- (void)hideLogWindow {
    self.logContainerView.hidden = YES;
    self.isVisible = NO;
}

- (void)handleTitleBarPan:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:self.logContainerView.superview];

    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.lastTranslation = CGPointZero;
    }

    if (gesture.state == UIGestureRecognizerStateChanged) {
        CGFloat deltaX = translation.x - self.lastTranslation.x;
        CGFloat deltaY = translation.y - self.lastTranslation.y;

        CGRect newFrame = self.logContainerView.frame;
        newFrame.origin.x += deltaX;
        newFrame.origin.y += deltaY;

        CGFloat screenWidth = [[UIScreen mainScreen] bounds].size.width;
        CGFloat screenHeight = [[UIScreen mainScreen] bounds].size.height;
        newFrame.origin.x = MAX(0, MIN(newFrame.origin.x, screenWidth - newFrame.size.width));
        newFrame.origin.y = MAX(0, MIN(newFrame.origin.y, screenHeight - newFrame.size.height));

        self.logContainerView.frame = newFrame;
        self.lastTranslation = translation;
    }

    if (gesture.state == UIGestureRecognizerStateEnded || 
        gesture.state == UIGestureRecognizerStateCancelled) {
        self.lastTranslation = CGPointZero;
        [gesture setTranslation:CGPointZero inView:self.logContainerView.superview];
    }
}

- (void)appendLog:(NSString *)log {
    if (!log || log.length == 0) return;

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"HH:mm:ss"];
    NSString *timestamp = [formatter stringFromDate:[NSDate date]];

    NSString *formattedLog = [NSString stringWithFormat:@"[%@] %@\n", timestamp, log];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.logBuffer appendString:formattedLog];

        if (self.logTextView) {
            self.logTextView.text = self.logBuffer;
            NSRange bottom = NSMakeRange(self.logTextView.text.length, 0);
            [self.logTextView scrollRangeToVisible:bottom];
        }
    });
}

- (void)appendLogsBatch:(NSArray *)logs {
    if (!logs || logs.count == 0) return;

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"HH:mm:ss"];
    NSString *timestamp = [formatter stringFromDate:[NSDate date]];

    NSMutableString *batch = [NSMutableString string];
    for (NSString *log in logs) {
        [batch appendFormat:@"[%@] %@\n", timestamp, log];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.logBuffer appendString:batch];

        if (self.logTextView) {
            self.logTextView.text = self.logBuffer;
            NSRange bottom = NSMakeRange(self.logTextView.text.length, 0);
            [self.logTextView scrollRangeToVisible:bottom];
        }
    });
}

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
        _totalReplacedCount = 0;
        _totalHookedMethods = 0;
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

    LogWindowManager *logMgr = [LogWindowManager sharedInstance];
    if (logMgr.logContainerView && logMgr.logContainerView.superview == topWindow) {
        [topWindow insertSubview:logMgr.logContainerView belowSubview:self.floatingButton];
    }
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

    NSString *logStatus = [[LogWindowManager sharedInstance] isVisible] ? @" (显示中)" : @"";

    [alert addAction:[UIAlertAction actionWithTitle:@"Unity WASM 内存搜索" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self searchWASMMemory];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"日志窗口%@", logStatus] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [[LogWindowManager sharedInstance] toggleLogWindow];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"关闭悬浮窗" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [self hideFloatingButton];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    dispatch_async(dispatch_get_main_queue(), ^{
        [topVC presentViewController:alert animated:YES completion:nil];
    });
}

#pragma mark - ========== 目标字符串检测工具 ==========

- (NSArray *)targetKeywords {
    return @[
        @"freeRefreshNum",
        @"refreshNum",
        @"startChooseCount",
        @"ChooseCount",
        @"isRevive",
        @"isClickVideo"
    ];
}

- (BOOL)stringContainsTarget:(NSString *)string {
    if (!string || string.length < 5) return NO;
    for (NSString *kw in [self targetKeywords]) {
        if ([string containsString:kw]) return YES;
    }
    return NO;
}

#pragma mark - ========== 日志输出工具 ==========

- (NSString *)truncateString:(NSString *)string maxLength:(NSInteger)maxLength {
    if (!string || string.length == 0) return @"(nil)";
    if (string.length <= maxLength) return string;
    return [NSString stringWithFormat:@"%@...(+%lu)", [string substringToIndex:maxLength], (unsigned long)(string.length - maxLength)];
}

#pragma mark - ========== 递归保护 ==========

static _Thread_local BOOL g_inHook = NO;

#pragma mark - ========== 图片中所有类的具体 Hook 实现 ==========
// 所有 Hook 方法被调用时，无条件输出参数的部分内容

// 1. GameDock - evaluateJavaScript:completionHandler:
static void (*orig_GameDock_evaluateJS)(id self, SEL _cmd, NSString *script, id completionHandler);
static void hook_GameDock_evaluateJS(id self, SEL _cmd, NSString *script, id completionHandler) {
    if (g_inHook) {
        orig_GameDock_evaluateJS(self, _cmd, script, completionHandler);
        return;
    }
    g_inHook = YES;

    NSString *preview = [[FloatingButtonManager sharedInstance] truncateString:script maxLength:120];
    BOOL hasTarget = script && [[FloatingButtonManager sharedInstance] stringContainsTarget:script];
    NSString *log = [NSString stringWithFormat:@"%@ [GameDock evaluateJS] %@ | 内容: %@", 
                     hasTarget ? @"🎯" : @"📋", 
                     hasTarget ? @"发现目标" : @"",
                     preview];
    NSLog(@"[Tweak] %@", log);
    [[LogWindowManager sharedInstance] appendLog:log];

    orig_GameDock_evaluateJS(self, _cmd, script, completionHandler);
    g_inHook = NO;
}

// 2. BDPGameContainer - evaluateJavaScript:completionHandler:
static void (*orig_BDPGameContainer_evaluateJS)(id self, SEL _cmd, NSString *script, id completionHandler);
static void hook_BDPGameContainer_evaluateJS(id self, SEL _cmd, NSString *script, id completionHandler) {
    if (g_inHook) {
        orig_BDPGameContainer_evaluateJS(self, _cmd, script, completionHandler);
        return;
    }
    g_inHook = YES;

    NSString *preview = [[FloatingButtonManager sharedInstance] truncateString:script maxLength:120];
    BOOL hasTarget = script && [[FloatingButtonManager sharedInstance] stringContainsTarget:script];
    NSString *log = [NSString stringWithFormat:@"%@ [BDPGameContainer evaluateJS] %@ | 内容: %@", 
                     hasTarget ? @"🎯" : @"📋", 
                     hasTarget ? @"发现目标" : @"",
                     preview];
    NSLog(@"[Tweak] %@", log);
    [[LogWindowManager sharedInstance] appendLog:log];

    orig_BDPGameContainer_evaluateJS(self, _cmd, script, completionHandler);
    g_inHook = NO;
}

// 3. MQPWebView - evaluateJavaScript:completionHandler:
static void (*orig_MQPWebView_evaluateJS)(id self, SEL _cmd, NSString *script, id completionHandler);
static void hook_MQPWebView_evaluateJS(id self, SEL _cmd, NSString *script, id completionHandler) {
    if (g_inHook) {
        orig_MQPWebView_evaluateJS(self, _cmd, script, completionHandler);
        return;
    }
    g_inHook = YES;

    NSString *preview = [[FloatingButtonManager sharedInstance] truncateString:script maxLength:120];
    BOOL hasTarget = script && [[FloatingButtonManager sharedInstance] stringContainsTarget:script];
    NSString *log = [NSString stringWithFormat:@"%@ [MQPWebView evaluateJS] %@ | 内容: %@", 
                     hasTarget ? @"🎯" : @"📋", 
                     hasTarget ? @"发现目标" : @"",
                     preview];
    NSLog(@"[Tweak] %@", log);
    [[LogWindowManager sharedInstance] appendLog:log];

    orig_MQPWebView_evaluateJS(self, _cmd, script, completionHandler);
    g_inHook = NO;
}

// 4. BDECRabbiFlyJSWorker - evaluateJavaScript:filename:
static void (*orig_BDECRabbiFlyJSWorker_evaluateJS_filename)(id self, SEL _cmd, NSString *script, NSString *filename);
static void hook_BDECRabbiFlyJSWorker_evaluateJS_filename(id self, SEL _cmd, NSString *script, NSString *filename) {
    if (g_inHook) {
        orig_BDECRabbiFlyJSWorker_evaluateJS_filename(self, _cmd, script, filename);
        return;
    }
    g_inHook = YES;

    NSString *preview = [[FloatingButtonManager sharedInstance] truncateString:script maxLength:120];
    BOOL hasTarget = script && [[FloatingButtonManager sharedInstance] stringContainsTarget:script];
    NSString *log = [NSString stringWithFormat:@"%@ [BDECRabbiFlyJSWorker evaluateJS:filename:%@] %@ | 内容: %@", 
                     hasTarget ? @"🎯" : @"📋", 
                     filename ?: @"(nil)",
                     hasTarget ? @"发现目标" : @"",
                     preview];
    NSLog(@"[Tweak] %@", log);
    [[LogWindowManager sharedInstance] appendLog:log];

    orig_BDECRabbiFlyJSWorker_evaluateJS_filename(self, _cmd, script, filename);
    g_inHook = NO;
}

// 5. BDPAIActionJSBridge - evaluateJavaScript:inWebView:completionHandler:
static void (*orig_BDPAIActionJSBridge_evaluateJS_inWebView)(id self, SEL _cmd, NSString *script, id webView, id completionHandler);
static void hook_BDPAIActionJSBridge_evaluateJS_inWebView(id self, SEL _cmd, NSString *script, id webView, id completionHandler) {
    if (g_inHook) {
        orig_BDPAIActionJSBridge_evaluateJS_inWebView(self, _cmd, script, webView, completionHandler);
        return;
    }
    g_inHook = YES;

    NSString *preview = [[FloatingButtonManager sharedInstance] truncateString:script maxLength:120];
    BOOL hasTarget = script && [[FloatingButtonManager sharedInstance] stringContainsTarget:script];
    NSString *log = [NSString stringWithFormat:@"%@ [BDPAIActionJSBridge evaluateJS:inWebView] %@ | 内容: %@", 
                     hasTarget ? @"🎯" : @"📋", 
                     hasTarget ? @"发现目标" : @"",
                     preview];
    NSLog(@"[Tweak] %@", log);
    [[LogWindowManager sharedInstance] appendLog:log];

    orig_BDPAIActionJSBridge_evaluateJS_inWebView(self, _cmd, script, webView, completionHandler);
    g_inHook = NO;
}

// 6. JsWorkerIOS - evaluateJavaScript:param:
static void (*orig_JsWorkerIOS_evaluateJS_param)(id self, SEL _cmd, NSString *script, id param);
static void hook_JsWorkerIOS_evaluateJS_param(id self, SEL _cmd, NSString *script, id param) {
    if (g_inHook) {
        orig_JsWorkerIOS_evaluateJS_param(self, _cmd, script, param);
        return;
    }
    g_inHook = YES;

    NSString *preview = [[FloatingButtonManager sharedInstance] truncateString:script maxLength:120];
    BOOL hasTarget = script && [[FloatingButtonManager sharedInstance] stringContainsTarget:script];
    NSString *log = [NSString stringWithFormat:@"%@ [JsWorkerIOS evaluateJS:param] %@ | 内容: %@", 
                     hasTarget ? @"🎯" : @"📋", 
                     hasTarget ? @"发现目标" : @"",
                     preview];
    NSLog(@"[Tweak] %@", log);
    [[LogWindowManager sharedInstance] appendLog:log];

    orig_JsWorkerIOS_evaluateJS_param(self, _cmd, script, param);
    g_inHook = NO;
}

// 7. LynxBackgroundRuntime - evaluateJavaScript:withSources:
static void (*orig_LynxBackgroundRuntime_evaluateJS_withSources)(id self, SEL _cmd, NSString *script, id sources);
static void hook_LynxBackgroundRuntime_evaluateJS_withSources(id self, SEL _cmd, NSString *script, id sources) {
    if (g_inHook) {
        orig_LynxBackgroundRuntime_evaluateJS_withSources(self, _cmd, script, sources);
        return;
    }
    g_inHook = YES;

    NSString *preview = [[FloatingButtonManager sharedInstance] truncateString:script maxLength:120];
    BOOL hasTarget = script && [[FloatingButtonManager sharedInstance] stringContainsTarget:script];
    NSString *log = [NSString stringWithFormat:@"%@ [LynxBackgroundRuntime evaluateJS:withSources] %@ | 内容: %@", 
                     hasTarget ? @"🎯" : @"📋", 
                     hasTarget ? @"发现目标" : @"",
                     preview];
    NSLog(@"[Tweak] %@", log);
    [[LogWindowManager sharedInstance] appendLog:log];

    orig_LynxBackgroundRuntime_evaluateJS_withSources(self, _cmd, script, sources);
    g_inHook = NO;
}

// 8. BDPInteractCreationRuntime - evaluateJavaScriptSafely:completion:
static void (*orig_BDPInteractCreationRuntime_evaluateJSSafely)(id self, SEL _cmd, NSString *script, id completion);
static void hook_BDPInteractCreationRuntime_evaluateJSSafely(id self, SEL _cmd, NSString *script, id completion) {
    if (g_inHook) {
        orig_BDPInteractCreationRuntime_evaluateJSSafely(self, _cmd, script, completion);
        return;
    }
    g_inHook = YES;

    NSString *preview = [[FloatingButtonManager sharedInstance] truncateString:script maxLength:120];
    BOOL hasTarget = script && [[FloatingButtonManager sharedInstance] stringContainsTarget:script];
    NSString *log = [NSString stringWithFormat:@"%@ [BDPInteractCreationRuntime evaluateJSSafely] %@ | 内容: %@", 
                     hasTarget ? @"🎯" : @"📋", 
                     hasTarget ? @"发现目标" : @"",
                     preview];
    NSLog(@"[Tweak] %@", log);
    [[LogWindowManager sharedInstance] appendLog:log];

    orig_BDPInteractCreationRuntime_evaluateJSSafely(self, _cmd, script, completion);
    g_inHook = NO;
}

// 9. UPWebViewJavascriptBridgeBase - _evaluateJavascript:
static void (*orig_UPWebViewJavascriptBridgeBase_evaluateJS)(id self, SEL _cmd, NSString *script);
static void hook_UPWebViewJavascriptBridgeBase_evaluateJS(id self, SEL _cmd, NSString *script) {
    if (g_inHook) {
        orig_UPWebViewJavascriptBridgeBase_evaluateJS(self, _cmd, script);
        return;
    }
    g_inHook = YES;

    NSString *preview = [[FloatingButtonManager sharedInstance] truncateString:script maxLength:120];
    BOOL hasTarget = script && [[FloatingButtonManager sharedInstance] stringContainsTarget:script];
    NSString *log = [NSString stringWithFormat:@"%@ [UPWebViewJavascriptBridgeBase _evaluateJS] %@ | 内容: %@", 
                     hasTarget ? @"🎯" : @"📋", 
                     hasTarget ? @"发现目标" : @"",
                     preview];
    NSLog(@"[Tweak] %@", log);
    [[LogWindowManager sharedInstance] appendLog:log];

    orig_UPWebViewJavascriptBridgeBase_evaluateJS(self, _cmd, script);
    g_inHook = NO;
}

// 10. UPWKWebViewJavascriptBridge - _evaluateJavascript:
static void (*orig_UPWKWebViewJavascriptBridge_evaluateJS)(id self, SEL _cmd, NSString *script);
static void hook_UPWKWebViewJavascriptBridge_evaluateJS(id self, SEL _cmd, NSString *script) {
    if (g_inHook) {
        orig_UPWKWebViewJavascriptBridge_evaluateJS(self, _cmd, script);
        return;
    }
    g_inHook = YES;

    NSString *preview = [[FloatingButtonManager sharedInstance] truncateString:script maxLength:120];
    BOOL hasTarget = script && [[FloatingButtonManager sharedInstance] stringContainsTarget:script];
    NSString *log = [NSString stringWithFormat:@"%@ [UPWKWebViewJavascriptBridge _evaluateJS] %@ | 内容: %@", 
                     hasTarget ? @"🎯" : @"📋", 
                     hasTarget ? @"发现目标" : @"",
                     preview];
    NSLog(@"[Tweak] %@", log);
    [[LogWindowManager sharedInstance] appendLog:log];

    orig_UPWKWebViewJavascriptBridge_evaluateJS(self, _cmd, script);
    g_inHook = NO;
}

// 11. BDXMixABTestHelper - enableFixWebEvaluateJavaScript_100400 (返回 BOOL)
static BOOL (*orig_BDXMixABTestHelper_enableFix)(id self, SEL _cmd);
static BOOL hook_BDXMixABTestHelper_enableFix(id self, SEL _cmd) {
    if (g_inHook) {
        return orig_BDXMixABTestHelper_enableFix(self, _cmd);
    }
    g_inHook = YES;

    BOOL result = orig_BDXMixABTestHelper_enableFix(self, _cmd);

    NSString *log = [NSString stringWithFormat:@"📋 [BDXMixABTestHelper enableFix] 返回值: %@", result ? @"YES" : @"NO"];
    NSLog(@"[Tweak] %@", log);
    [[LogWindowManager sharedInstance] appendLog:log];

    g_inHook = NO;
    return result;
}

// 12. CJPayAnnieJSWorker - evaluateJavaScript:
static void (*orig_CJPayAnnieJSWorker_evaluateJS)(id self, SEL _cmd, NSString *script);
static void hook_CJPayAnnieJSWorker_evaluateJS(id self, SEL _cmd, NSString *script) {
    if (g_inHook) {
        orig_CJPayAnnieJSWorker_evaluateJS(self, _cmd, script);
        return;
    }
    g_inHook = YES;

    NSString *preview = [[FloatingButtonManager sharedInstance] truncateString:script maxLength:120];
    BOOL hasTarget = script && [[FloatingButtonManager sharedInstance] stringContainsTarget:script];
    NSString *log = [NSString stringWithFormat:@"%@ [CJPayAnnieJSWorker evaluateJS] %@ | 内容: %@", 
                     hasTarget ? @"🎯" : @"📋", 
                     hasTarget ? @"发现目标" : @"",
                     preview];
    NSLog(@"[Tweak] %@", log);
    [[LogWindowManager sharedInstance] appendLog:log];

    orig_CJPayAnnieJSWorker_evaluateJS(self, _cmd, script);
    g_inHook = NO;
}

// 13. BDECRabbiFlyJSWorker - evaluateJavaScript: (第二个签名)
static void (*orig_BDECRabbiFlyJSWorker_evaluateJS)(id self, SEL _cmd, NSString *script);
static void hook_BDECRabbiFlyJSWorker_evaluateJS(id self, SEL _cmd, NSString *script) {
    if (g_inHook) {
        orig_BDECRabbiFlyJSWorker_evaluateJS(self, _cmd, script);
        return;
    }
    g_inHook = YES;

    NSString *preview = [[FloatingButtonManager sharedInstance] truncateString:script maxLength:120];
    BOOL hasTarget = script && [[FloatingButtonManager sharedInstance] stringContainsTarget:script];
    NSString *log = [NSString stringWithFormat:@"%@ [BDECRabbiFlyJSWorker evaluateJS] %@ | 内容: %@", 
                     hasTarget ? @"🎯" : @"📋", 
                     hasTarget ? @"发现目标" : @"",
                     preview];
    NSLog(@"[Tweak] %@", log);
    [[LogWindowManager sharedInstance] appendLog:log];

    orig_BDECRabbiFlyJSWorker_evaluateJS(self, _cmd, script);
    g_inHook = NO;
}

// 14. AMGMiniGameRuntime - evaluateJavaScript:completion:
static void (*orig_AMGMiniGameRuntime_evaluateJS_completion)(id self, SEL _cmd, NSString *script, id completion);
static void hook_AMGMiniGameRuntime_evaluateJS_completion(id self, SEL _cmd, NSString *script, id completion) {
    if (g_inHook) {
        orig_AMGMiniGameRuntime_evaluateJS_completion(self, _cmd, script, completion);
        return;
    }
    g_inHook = YES;

    NSString *preview = [[FloatingButtonManager sharedInstance] truncateString:script maxLength:120];
    BOOL hasTarget = script && [[FloatingButtonManager sharedInstance] stringContainsTarget:script];
    NSString *log = [NSString stringWithFormat:@"%@ [AMGMiniGameRuntime evaluateJS:completion] %@ | 内容: %@", 
                     hasTarget ? @"🎯" : @"📋", 
                     hasTarget ? @"发现目标" : @"",
                     preview];
    NSLog(@"[Tweak] %@", log);
    [[LogWindowManager sharedInstance] appendLog:log];

    orig_AMGMiniGameRuntime_evaluateJS_completion(self, _cmd, script, completion);
    g_inHook = NO;
}

// 15. ADFGWebViewBridgeEngine - evaluateJavaScript:completionHandler:
static void (*orig_ADFGWebViewBridgeEngine_evaluateJS)(id self, SEL _cmd, NSString *script, id completionHandler);
static void hook_ADFGWebViewBridgeEngine_evaluateJS(id self, SEL _cmd, NSString *script, id completionHandler) {
    if (g_inHook) {
        orig_ADFGWebViewBridgeEngine_evaluateJS(self, _cmd, script, completionHandler);
        return;
    }
    g_inHook = YES;

    NSString *preview = [[FloatingButtonManager sharedInstance] truncateString:script maxLength:120];
    BOOL hasTarget = script && [[FloatingButtonManager sharedInstance] stringContainsTarget:script];
    NSString *log = [NSString stringWithFormat:@"%@ [ADFGWebViewBridgeEngine evaluateJS] %@ | 内容: %@", 
                     hasTarget ? @"🎯" : @"📋", 
                     hasTarget ? @"发现目标" : @"",
                     preview];
    NSLog(@"[Tweak] %@", log);
    [[LogWindowManager sharedInstance] appendLog:log];

    orig_ADFGWebViewBridgeEngine_evaluateJS(self, _cmd, script, completionHandler);
    g_inHook = NO;
}

// 16. AWEGameContainer - evaluateJavaScript:completionHandler:
static void (*orig_AWEGameContainer_evaluateJS)(id self, SEL _cmd, NSString *script, id completionHandler);
static void hook_AWEGameContainer_evaluateJS(id self, SEL _cmd, NSString *script, id completionHandler) {
    if (g_inHook) {
        orig_AWEGameContainer_evaluateJS(self, _cmd, script, completionHandler);
        return;
    }
    g_inHook = YES;

    NSString *preview = [[FloatingButtonManager sharedInstance] truncateString:script maxLength:120];
    BOOL hasTarget = script && [[FloatingButtonManager sharedInstance] stringContainsTarget:script];
    NSString *log = [NSString stringWithFormat:@"%@ [AWEGameContainer evaluateJS] %@ | 内容: %@", 
                     hasTarget ? @"🎯" : @"📋", 
                     hasTarget ? @"发现目标" : @"",
                     preview];
    NSLog(@"[Tweak] %@", log);
    [[LogWindowManager sharedInstance] appendLog:log];

    orig_AWEGameContainer_evaluateJS(self, _cmd, script, completionHandler);
    g_inHook = NO;
}

// 17. TTWebViewBridgeEngine - evaluateJavaScript:completionHandler:
static void (*orig_TTWebViewBridgeEngine_evaluateJS)(id self, SEL _cmd, NSString *script, id completionHandler);
static void hook_TTWebViewBridgeEngine_evaluateJS(id self, SEL _cmd, NSString *script, id completionHandler) {
    if (g_inHook) {
        orig_TTWebViewBridgeEngine_evaluateJS(self, _cmd, script, completionHandler);
        return;
    }
    g_inHook = YES;

    NSString *preview = [[FloatingButtonManager sharedInstance] truncateString:script maxLength:120];
    BOOL hasTarget = script && [[FloatingButtonManager sharedInstance] stringContainsTarget:script];
    NSString *log = [NSString stringWithFormat:@"%@ [TTWebViewBridgeEngine evaluateJS] %@ | 内容: %@", 
                     hasTarget ? @"🎯" : @"📋", 
                     hasTarget ? @"发现目标" : @"",
                     preview];
    NSLog(@"[Tweak] %@", log);
    [[LogWindowManager sharedInstance] appendLog:log];

    orig_TTWebViewBridgeEngine_evaluateJS(self, _cmd, script, completionHandler);
    g_inHook = NO;
}

// 18. BDXWebView - evaluateJavaScript:completionHandler:
static void (*orig_BDXWebView_evaluateJS)(id self, SEL _cmd, NSString *script, id completionHandler);
static void hook_BDXWebView_evaluateJS(id self, SEL _cmd, NSString *script, id completionHandler) {
    if (g_inHook) {
        orig_BDXWebView_evaluateJS(self, _cmd, script, completionHandler);
        return;
    }
    g_inHook = YES;

    NSString *preview = [[FloatingButtonManager sharedInstance] truncateString:script maxLength:120];
    BOOL hasTarget = script && [[FloatingButtonManager sharedInstance] stringContainsTarget:script];
    NSString *log = [NSString stringWithFormat:@"%@ [BDXWebView evaluateJS] %@ | 内容: %@", 
                     hasTarget ? @"🎯" : @"📋", 
                     hasTarget ? @"发现目标" : @"",
                     preview];
    NSLog(@"[Tweak] %@", log);
    [[LogWindowManager sharedInstance] appendLog:log];

    orig_BDXWebView_evaluateJS(self, _cmd, script, completionHandler);
    g_inHook = NO;
}

// 19. AnnieXWebViewLoader - evaluateJavaScript:completionHandler:
static void (*orig_AnnieXWebViewLoader_evaluateJS)(id self, SEL _cmd, NSString *script, id completionHandler);
static void hook_AnnieXWebViewLoader_evaluateJS(id self, SEL _cmd, NSString *script, id completionHandler) {
    if (g_inHook) {
        orig_AnnieXWebViewLoader_evaluateJS(self, _cmd, script, completionHandler);
        return;
    }
    g_inHook = YES;

    NSString *preview = [[FloatingButtonManager sharedInstance] truncateString:script maxLength:120];
    BOOL hasTarget = script && [[FloatingButtonManager sharedInstance] stringContainsTarget:script];
    NSString *log = [NSString stringWithFormat:@"%@ [AnnieXWebViewLoader evaluateJS] %@ | 内容: %@", 
                     hasTarget ? @"🎯" : @"📋", 
                     hasTarget ? @"发现目标" : @"",
                     preview];
    NSLog(@"[Tweak] %@", log);
    [[LogWindowManager sharedInstance] appendLog:log];

    orig_AnnieXWebViewLoader_evaluateJS(self, _cmd, script, completionHandler);
    g_inHook = NO;
}

// 20. LynxWebViewDefaultLoader - evaluateJavaScript:completionHandler:
static void (*orig_LynxWebViewDefaultLoader_evaluateJS)(id self, SEL _cmd, NSString *script, id completionHandler);
static void hook_LynxWebViewDefaultLoader_evaluateJS(id self, SEL _cmd, NSString *script, id completionHandler) {
    if (g_inHook) {
        orig_LynxWebViewDefaultLoader_evaluateJS(self, _cmd, script, completionHandler);
        return;
    }
    g_inHook = YES;

    NSString *preview = [[FloatingButtonManager sharedInstance] truncateString:script maxLength:120];
    BOOL hasTarget = script && [[FloatingButtonManager sharedInstance] stringContainsTarget:script];
    NSString *log = [NSString stringWithFormat:@"%@ [LynxWebViewDefaultLoader evaluateJS] %@ | 内容: %@", 
                     hasTarget ? @"🎯" : @"📋", 
                     hasTarget ? @"发现目标" : @"",
                     preview];
    NSLog(@"[Tweak] %@", log);
    [[LogWindowManager sharedInstance] appendLog:log];

    orig_LynxWebViewDefaultLoader_evaluateJS(self, _cmd, script, completionHandler);
    g_inHook = NO;
}

#pragma mark - ========== 启用所有 Hook（App 启动时调用）==========

- (void)enableAllHooks {
    [[LogWindowManager sharedInstance] appendLog:@"🚀 开始启用图片中所有类的 JS 执行 Hook..."];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableArray *batchLogs = [NSMutableArray array];
        int successCount = 0;
        int failCount = 0;

        struct HookDef {
            const char *className;
            const char *selName;
            IMP hookIMP;
            IMP *origIMPPtr;
        } hookDefs[] = {
            {"GameDock", "evaluateJavaScript:completionHandler:", (IMP)hook_GameDock_evaluateJS, (IMP *)&orig_GameDock_evaluateJS},
            {"BDPGameContainer", "evaluateJavaScript:completionHandler:", (IMP)hook_BDPGameContainer_evaluateJS, (IMP *)&orig_BDPGameContainer_evaluateJS},
            {"MQPWebView", "evaluateJavaScript:completionHandler:", (IMP)hook_MQPWebView_evaluateJS, (IMP *)&orig_MQPWebView_evaluateJS},
            {"BDECRabbiFlyJSWorker", "evaluateJavaScript:filename:", (IMP)hook_BDECRabbiFlyJSWorker_evaluateJS_filename, (IMP *)&orig_BDECRabbiFlyJSWorker_evaluateJS_filename},
            {"BDPAIActionJSBridge", "evaluateJavaScript:inWebView:completionHandler:", (IMP)hook_BDPAIActionJSBridge_evaluateJS_inWebView, (IMP *)&orig_BDPAIActionJSBridge_evaluateJS_inWebView},
            {"JsWorkerIOS", "evaluateJavaScript:param:", (IMP)hook_JsWorkerIOS_evaluateJS_param, (IMP *)&orig_JsWorkerIOS_evaluateJS_param},
            {"LynxBackgroundRuntime", "evaluateJavaScript:withSources:", (IMP)hook_LynxBackgroundRuntime_evaluateJS_withSources, (IMP *)&orig_LynxBackgroundRuntime_evaluateJS_withSources},
            {"BDPInteractCreationRuntime", "evaluateJavaScriptSafely:completion:", (IMP)hook_BDPInteractCreationRuntime_evaluateJSSafely, (IMP *)&orig_BDPInteractCreationRuntime_evaluateJSSafely},
            {"UPWebViewJavascriptBridgeBase", "_evaluateJavascript:", (IMP)hook_UPWebViewJavascriptBridgeBase_evaluateJS, (IMP *)&orig_UPWebViewJavascriptBridgeBase_evaluateJS},
            {"UPWKWebViewJavascriptBridge", "_evaluateJavascript:", (IMP)hook_UPWKWebViewJavascriptBridge_evaluateJS, (IMP *)&orig_UPWKWebViewJavascriptBridge_evaluateJS},
            {"BDXMixABTestHelper", "enableFixWebEvaluateJavaScript_100400", (IMP)hook_BDXMixABTestHelper_enableFix, (IMP *)&orig_BDXMixABTestHelper_enableFix},
            {"CJPayAnnieJSWorker", "evaluateJavaScript:", (IMP)hook_CJPayAnnieJSWorker_evaluateJS, (IMP *)&orig_CJPayAnnieJSWorker_evaluateJS},
            {"BDECRabbiFlyJSWorker", "evaluateJavaScript:", (IMP)hook_BDECRabbiFlyJSWorker_evaluateJS, (IMP *)&orig_BDECRabbiFlyJSWorker_evaluateJS},
            {"AMGMiniGameRuntime", "evaluateJavaScript:completion:", (IMP)hook_AMGMiniGameRuntime_evaluateJS_completion, (IMP *)&orig_AMGMiniGameRuntime_evaluateJS_completion},
            {"ADFGWebViewBridgeEngine", "evaluateJavaScript:completionHandler:", (IMP)hook_ADFGWebViewBridgeEngine_evaluateJS, (IMP *)&orig_ADFGWebViewBridgeEngine_evaluateJS},
            {"AWEGameContainer", "evaluateJavaScript:completionHandler:", (IMP)hook_AWEGameContainer_evaluateJS, (IMP *)&orig_AWEGameContainer_evaluateJS},
            {"TTWebViewBridgeEngine", "evaluateJavaScript:completionHandler:", (IMP)hook_TTWebViewBridgeEngine_evaluateJS, (IMP *)&orig_TTWebViewBridgeEngine_evaluateJS},
            {"BDXWebView", "evaluateJavaScript:completionHandler:", (IMP)hook_BDXWebView_evaluateJS, (IMP *)&orig_BDXWebView_evaluateJS},
            {"AnnieXWebViewLoader", "evaluateJavaScript:completionHandler:", (IMP)hook_AnnieXWebViewLoader_evaluateJS, (IMP *)&orig_AnnieXWebViewLoader_evaluateJS},
            {"LynxWebViewDefaultLoader", "evaluateJavaScript:completionHandler:", (IMP)hook_LynxWebViewDefaultLoader_evaluateJS, (IMP *)&orig_LynxWebViewDefaultLoader_evaluateJS},
        };

        int totalHooks = sizeof(hookDefs) / sizeof(hookDefs[0]);

        for (int i = 0; i < totalHooks; i++) {
            struct HookDef def = hookDefs[i];
            Class cls = NSClassFromString([NSString stringWithUTF8String:def.className]);
            if (!cls) {
                [batchLogs addObject:[NSString stringWithFormat:@"❌ %s 类未找到", def.className]];
                failCount++;
                continue;
            }

            SEL sel = NSSelectorFromString([NSString stringWithUTF8String:def.selName]);
            Method method = class_getInstanceMethod(cls, sel);
            if (!method) {
                method = class_getClassMethod(cls, sel);
            }

            if (!method) {
                [batchLogs addObject:[NSString stringWithFormat:@"⚠️ %s %s 方法未找到", def.className, def.selName]];
                failCount++;
                continue;
            }

            *def.origIMPPtr = method_getImplementation(method);
            method_setImplementation(method, def.hookIMP);

            [batchLogs addObject:[NSString stringWithFormat:@"✅ %s %s Hook 成功", def.className, def.selName]];
            successCount++;
        }

        self.totalHookedMethods = successCount;

        [[LogWindowManager sharedInstance] appendLogsBatch:batchLogs];

        NSString *summary = [NSString stringWithFormat:@"📊 Hook 启用完成 | 成功: %d | 失败: %d | 总计: %d", successCount, failCount, totalHooks];
        [[LogWindowManager sharedInstance] appendLog:summary];
        [[LogWindowManager sharedInstance] appendLog:@"🎉 所有 JS 执行 Hook 已静默启用，参数日志输出已激活"];
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

#pragma mark - ========== 内存搜索 ==========

static kern_return_t safe_vm_read(vm_address_t address, vm_size_t size, vm_offset_t *outData, mach_msg_type_number_t *outSize) {
    vm_offset_t data = 0;
    mach_msg_type_number_t dataSize = 0;
    kern_return_t kr = vm_read(mach_task_self(), address, size, &data, &dataSize);
    if (kr == KERN_SUCCESS) {
        *outData = data;
        *outSize = dataSize;
    }
    return kr;
}

static void safe_vm_free(vm_offset_t data, mach_msg_type_number_t size) {
    if (data != 0 && size > 0) {
        vm_deallocate(mach_task_self(), data, size);
    }
}

static int searchInCopiedMemory(const void *data, size_t dataSize, const char *target, size_t targetLen,
                                  NSMutableArray *foundAddresses, vm_address_t baseAddr, int maxMatches) {
    int count = 0;
    const uint8_t *ptr = (const uint8_t *)data;
    const uint8_t *end = ptr + dataSize;

    while (ptr < end - targetLen && count < maxMatches) {
        void *found = memmem(ptr, end - ptr, target, targetLen);
        if (!found) break;

        vm_address_t offset = (vm_address_t)((const uint8_t *)found - (const uint8_t *)data);
        vm_address_t absoluteAddr = baseAddr + offset;
        [foundAddresses addObject:[NSNumber numberWithUnsignedLongLong:absoluteAddr]];
        count++;

        ptr = (const uint8_t *)found + targetLen;
    }

    return count;
}

- (void)searchWASMMemory {
    [[LogWindowManager sharedInstance] appendLog:@"🔍 开始 Unity WASM 内存搜索..."];
    [[LogWindowManager sharedInstance] showLogWindow];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
        NSArray *searchStrings = @[@"freeRefreshNum", @"refreshNum", @"startChooseCount", @"ChooseCount", @"isRevive", @"isClickVideo"];

        NSMutableDictionary *results = [NSMutableDictionary dictionary];
        NSMutableDictionary *addresses = [NSMutableDictionary dictionary];
        for (NSString *str in searchStrings) {
            results[str] = @0;
            addresses[str] = [NSMutableArray array];
        }

        int checkedRegions = 0;
        int totalRegions = 0;
        int skippedRegions = 0;
        int readFailedRegions = 0;

        NSTimeInterval startTime = [[NSDate date] timeIntervalSince1970];
        NSTimeInterval maxDuration = 10.0;

        const vm_size_t MAX_REGION_SIZE = 10 * 1024 * 1024;
        const int MAX_MATCHES_PER_STRING = 50;

        vm_address_t address = 0;
        vm_size_t size = 0;
        vm_region_basic_info_data_64_t info;
        mach_msg_type_number_t infoCount = VM_REGION_BASIC_INFO_COUNT_64;
        memory_object_name_t objectName = MACH_PORT_NULL;

        while (1) {
            NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
            if (currentTime - startTime > maxDuration) {
                [[LogWindowManager sharedInstance] appendLog:@"⏱️ 搜索超时（10秒），提前结束"];
                break;
            }

            kern_return_t kr = vm_region_64(mach_task_self(), &address, &size,
                                            VM_REGION_BASIC_INFO_64,
                                            (vm_region_info_t)&info, &infoCount, &objectName);

            if (kr != KERN_SUCCESS) break;
            totalRegions++;

            BOOL isReadable = (info.protection & VM_PROT_READ) != 0;

            if (!isReadable || size < 10) {
                skippedRegions++;
                address += size;
                infoCount = VM_REGION_BASIC_INFO_COUNT_64;
                continue;
            }

            if (size > MAX_REGION_SIZE) {
                skippedRegions++;
                address += size;
                infoCount = VM_REGION_BASIC_INFO_COUNT_64;
                continue;
            }

            checkedRegions++;

            if (checkedRegions % 100 == 0) {
                NSString *log = [NSString stringWithFormat:@"📊 已检查 %d 个区域...", checkedRegions];
                NSLog(@"[Tweak] %@", log);
                [[LogWindowManager sharedInstance] appendLog:log];
                [NSThread sleepForTimeInterval:0.005];
            }

            vm_offset_t copiedData = 0;
            mach_msg_type_number_t copiedSize = 0;
            kern_return_t readKr = safe_vm_read(address, size, &copiedData, &copiedSize);

            if (readKr != KERN_SUCCESS) {
                readFailedRegions++;
                address += size;
                infoCount = VM_REGION_BASIC_INFO_COUNT_64;
                continue;
            }

            for (NSString *targetStr in searchStrings) {
                const char *target = [targetStr UTF8String];
                size_t targetLen = strlen(target);

                if (copiedSize <= targetLen) continue;

                NSMutableArray *foundAddrs = addresses[targetStr];
                int currentCount = [results[targetStr] intValue];

                if (currentCount >= MAX_MATCHES_PER_STRING) continue;

                int remaining = MAX_MATCHES_PER_STRING - currentCount;
                int found = searchInCopiedMemory((const void *)copiedData, (size_t)copiedSize, target, targetLen,
                                                   foundAddrs, address, remaining);

                if (found > 0) {
                    results[targetStr] = @(currentCount + found);
                }
            }

            safe_vm_free(copiedData, copiedSize);

            address += size;
            infoCount = VM_REGION_BASIC_INFO_COUNT_64;
        }

        NSMutableArray *batchLogs = [NSMutableArray array];
        for (NSString *targetStr in searchStrings) {
            int count = [results[targetStr] intValue];
            NSArray *addrs = addresses[targetStr];

            [batchLogs addObject:[NSString stringWithFormat:@"📌 '%@' 找到 %d 处", targetStr, count]];

            int logCount = MIN((int)addrs.count, 10);
            for (int i = 0; i < logCount; i++) {
                NSNumber *addr = addrs[i];
                [batchLogs addObject:[NSString stringWithFormat:@"   🔍 at %p", (void *)[addr unsignedLongLongValue]]];
            }
            if (addrs.count > 10) {
                [batchLogs addObject:[NSString stringWithFormat:@"   ... 还有 %lu 处", (unsigned long)(addrs.count - 10)]];
            }
        }

        if (batchLogs.count > 0) {
            [[LogWindowManager sharedInstance] appendLogsBatch:batchLogs];
        }

        NSMutableString *report = [NSMutableString string];
        [report appendFormat:@"扫描完成\n总内存区域: %d\n已检查区域: %d\n跳过区域: %d\n读取失败: %d\n",
         totalRegions, checkedRegions, skippedRegions, readFailedRegions];

        int totalFound = 0;
        for (NSString *str in searchStrings) {
            int count = [results[str] intValue];
            totalFound += count;
            [report appendFormat:@"%@: %d 处\n", str, count];
        }

        [report appendFormat:@"\n总计找到: %d 处", totalFound];

        [[LogWindowManager sharedInstance] appendLog:report];

        dispatch_async(dispatch_get_main_queue(), ^{
            if (totalFound > 0) {
                [self showMessage:@"内存搜索成功" message:report];
            } else {
                [self showMessage:@"内存搜索完成" message:[NSString stringWithFormat:@"%@\n\n未找到任何目标字符串，可能：\n1. 字符串被混淆\n2. 使用 IL2CPP 全局元数据存储\n3. 字段名在编译期被优化掉", report]];
            }
        });
    });
}

@end

__attribute__((constructor))
static void init() {
    @autoreleasepool {
        static BOOL hooksExecuted = NO;

        void (^executeOnce)(void) = ^{
            if (hooksExecuted) return;
            hooksExecuted = YES;
            [[FloatingButtonManager sharedInstance] showFloatingButton];
            [[FloatingButtonManager sharedInstance] enableAllHooks];
        };

        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), executeOnce);
        }];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            executeOnce();
        });
    }
}
