#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import <WebKit/WebKit.h>
#import <AudioToolbox/AudioToolbox.h>

@interface FloatingButtonManager : NSObject
@property (nonatomic, strong) UIButton *floatingButton;
@property (nonatomic, strong) NSTimer *keepOnTopTimer;
@property (nonatomic, weak) UIWindow *lastWindow;
@property (nonatomic, assign) int totalReplacedCount;
@property (nonatomic, assign) int totalHookedMethods;
@property (nonatomic, strong) UIAlertController *currentMenuAlert;
@property (nonatomic, strong) UILongPressGestureRecognizer *globalWakeGesture; // 全局双指唤醒监听
+ (instancetype)sharedInstance;
- (void)showFloatingButton;
- (void)ensureButtonOnTop;
- (void)dismissMenuPanel;
- (void)updateMenuSubtitleForTag:(NSInteger)tag text:(NSString *)text;
- (id)replaceTargetInObject:(id)obj;
- (NSData *)replaceTargetInData:(NSData *)data;
- (NSString *)replaceTargetInString:(NSString *)string;
- (NSString *)targetKeyword;
- (BOOL)stringContainsTarget:(NSString *)string;
- (BOOL)dataContainsTarget:(NSData *)data;
- (void)enableAllHooks;
@end

@interface LogWindowManager : NSObject
@property (nonatomic, strong) UIView *logContainerView;
@property (nonatomic, strong) UITextView *logTextView;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UIButton *logCopyButton;
@property (nonatomic, strong) UIButton *logClearButton;
@property (nonatomic, strong) UIView *titleBar;
@property (nonatomic, strong) NSMutableString *logBuffer;
@property (nonatomic, assign) BOOL isVisible;
@property (nonatomic, assign) CGPoint lastTranslation;
@property (nonatomic, assign) BOOL logEnabled;
@property (nonatomic, assign) BOOL logToFileEnabled;
@property (nonatomic, copy) NSString *logFilePath;
+ (instancetype)sharedInstance;
- (void)toggleLogWindow;
- (void)showLogWindow;
- (void)hideLogWindow;
- (void)appendLog:(NSString *)log;
- (void)appendLogsBatch:(NSArray *)logs;
- (void)appendLogFull:(NSString *)fullLog displayLog:(NSString *)displayLog;
- (void)setLogEnabled:(BOOL)enabled;
- (void)setLogToFileEnabled:(BOOL)enabled;
- (void)writeLogToFile:(NSString *)log;
- (NSString *)truncateString:(NSString *)string maxLength:(NSInteger)maxLength;
- (NSString *)truncateData:(NSData *)data maxLength:(NSInteger)maxLength;
- (NSString *)objectDescription:(id)obj maxLength:(NSInteger)maxLength;
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
        _logEnabled = NO;
        _logToFileEnabled = NO;
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documentsDir = [paths firstObject];
        _logFilePath = [documentsDir stringByAppendingPathComponent:@"TweakHookLog.txt"];
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
    // 触发联动更新功能面板的 UI 状态显示
    [[FloatingButtonManager sharedInstance] updateMenuSubtitleForTag:1001 text:self.isVisible ? @"当前：显示中" : @"当前：已隐藏"];
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

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 0, windowWidth - 200, 36)];
    titleLabel.text = @"📋 Tweak 日志（拖动标题栏移动）";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [self.titleBar addSubview:titleLabel];

    self.logCopyButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.logCopyButton.frame = CGRectMake(windowWidth - 140, 4, 40, 28);
    [self.logCopyButton setTitle:@"📋" forState:UIControlStateNormal];
    self.logCopyButton.titleLabel.font = [UIFont systemFontOfSize:14];
    [self.logCopyButton addTarget:self action:@selector(copyLogContent) forControlEvents:UIControlEventTouchUpInside];
    [self.titleBar addSubview:self.logCopyButton];

    self.logClearButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.logClearButton.frame = CGRectMake(windowWidth - 95, 4, 40, 28);
    [self.logClearButton setTitle:@"🗑️" forState:UIControlStateNormal];
    self.logClearButton.titleLabel.font = [UIFont systemFontOfSize:14];
    [self.logClearButton addTarget:self action:@selector(clearLogContent) forControlEvents:UIControlEventTouchUpInside];
    [self.titleBar addSubview:self.logClearButton];

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
    [[FloatingButtonManager sharedInstance] updateMenuSubtitleForTag:1001 text:@"当前：已隐藏"];
}
- (void)copyLogContent {
    if (self.logBuffer && self.logBuffer.length > 0) {
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        pasteboard.string = self.logBuffer;
        if (self.logEnabled) {
            NSString *log = @"📋 日志内容已复制到剪贴板";
            NSLog(@"[Tweak] %@", log);
            [self.logBuffer appendString:[NSString stringWithFormat:@"[%@] %@\n", [[NSDate date] description], log]];
            if (self.logTextView) {
                self.logTextView.text = self.logBuffer;
                NSRange bottom = NSMakeRange(self.logTextView.text.length, 0);
                [self.logTextView scrollRangeToVisible:bottom];
            }
        }
    } else {
        if (self.logEnabled) {
            NSString *log = @"⚠️ 日志内容为空，无法复制";
            NSLog(@"[Tweak] %@", log);
            [self appendLog:log];
        }
    }
}

- (void)clearLogContent {
    [self.logBuffer setString:@""];
    if (self.logTextView) {
        self.logTextView.text = @"";
    }
    if (self.logEnabled) {
        NSString *log = @"🗑️ 日志内容已清空";
        NSLog(@"[Tweak] %@", log);
        [self appendLog:log];
    }
}

- (void)setLogEnabled:(BOOL)enabled {
    _logEnabled = enabled;
    if (!enabled) {
        [self.logBuffer setString:@""];
        if (self.logTextView) {
            self.logTextView.text = @"";
        }
    }
}

- (void)setLogToFileEnabled:(BOOL)enabled {
    _logToFileEnabled = enabled;
    if (enabled) {
        NSString *log = [NSString stringWithFormat:@"📁 日志文件路径: %@", self.logFilePath];
        [self writeLogToFile:log];
    }
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

- (void)writeLogToFile:(NSString *)log {
    if (!self.logToFileEnabled) return;
    if (!log || log.length == 0) return;
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    NSString *timestamp = [formatter stringFromDate:[NSDate date]];
    NSString *formattedLog = [NSString stringWithFormat:@"[%@] %@\n", timestamp, log];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:self.logFilePath]) {
        [formattedLog writeToFile:self.logFilePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } else {
        NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:self.logFilePath];
        if (fileHandle) {
            [fileHandle seekToEndOfFile];
            [fileHandle writeData:[formattedLog dataUsingEncoding:NSUTF8StringEncoding]];
            [fileHandle closeFile];
        }
    }
}

- (void)appendLogFull:(NSString *)fullLog displayLog:(NSString *)displayLog {
    if (!self.logEnabled) return;
    if (!fullLog || fullLog.length == 0) return;
    [self writeLogToFile:fullLog];
    NSString *showLog = displayLog ?: fullLog;
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"HH:mm:ss"];
    NSString *timestamp = [formatter stringFromDate:[NSDate date]];
    NSString *formattedLog = [NSString stringWithFormat:@"[%@] %@\n", timestamp, showLog];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.logBuffer appendString:formattedLog];
        if (self.logTextView) {
            self.logTextView.text = self.logBuffer;
            NSRange bottom = NSMakeRange(self.logTextView.text.length, 0);
            [self.logTextView scrollRangeToVisible:bottom];
        }
    });
}

- (void)appendLog:(NSString *)log {
    if (!self.logEnabled) return;
    if (!log || log.length == 0) return;
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"HH:mm:ss"];
    NSString *timestamp = [formatter stringFromDate:[NSDate date]];
    NSString *formattedLog = [NSString stringWithFormat:@"[%@] %@\n", timestamp, log];
    [self writeLogToFile:log];
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
    if (!self.logEnabled) return;
    if (!logs || logs.count == 0) return;
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"HH:mm:ss"];
    NSString *timestamp = [formatter stringFromDate:[NSDate date]];
    NSMutableString *batch = [NSMutableString string];
    for (NSString *log in logs) {
        [batch appendFormat:@"[%@] %@\n", timestamp, log];
        [self writeLogToFile:log];
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
- (NSString *)truncateString:(NSString *)string maxLength:(NSInteger)maxLength {
    if (!string || string.length == 0) return @"(nil)";
    if (string.length <= maxLength) return string;
    return [NSString stringWithFormat:@"%@...(%lu)", [string substringToIndex:maxLength], (unsigned long)(string.length - maxLength)];
}

- (NSData *)truncateData:(NSData *)data maxLength:(NSInteger)maxLength {
    if (!data || data.length == 0) return data;
    // 如果需要对二进制 Data 做长度截断逻辑
    if (data.length <= maxLength) return data;
    return [data subdataWithRange:NSMakeRange(0, maxLength)];
}

- (NSString *)objectDescription:(id)obj maxLength:(NSInteger)maxLength {
    if (!obj) return @"(nil)";
    if ([obj isKindOfClass:[NSString class]]) {
        return [self truncateString:(NSString *)obj maxLength:120];
    }
    if ([obj isKindOfClass:[NSData class]]) {
        NSString *hexStr = [obj description];
        if (hexStr.length <= maxLength) return hexStr;
        return [NSString stringWithFormat:@"%@...(%lu bytes)", [hexStr substringToIndex:maxLength], (unsigned long)((NSData *)obj).length];
    }
    if ([obj isKindOfClass:[NSURL class]]) {
        return [(NSURL *)obj absoluteString] ?: @"(nil URL)";
    }
    if ([obj isKindOfClass:[NSError class]]) {
        NSError *err = (NSError *)obj;
        return [NSString stringWithFormat:@"[NSError domain:%@ code:%ld %@]", err.domain, (long)err.code, err.localizedDescription];
    }
    if ([obj isKindOfClass:[NSNumber class]]) {
        return [(NSNumber *)obj stringValue];
    }
    if ([obj isKindOfClass:[NSArray class]]) {
        return [NSString stringWithFormat:@"[NSArray count:%lu]", (unsigned long)[(NSArray *)obj count]];
    }
    if ([obj isKindOfClass:[NSDictionary class]]) {
        return [NSString stringWithFormat:@"[NSDictionary count:%lu]", (unsigned long)[(NSDictionary *)obj count]];
    }
    NSString *desc = [obj description];
    if (desc.length > maxLength) {
        return [NSString stringWithFormat:@"(%@)%@...(%lu)", NSStringFromClass([obj class]), [desc substringToIndex:maxLength], (unsigned long)(desc.length - maxLength)];
    }
    return [NSString stringWithFormat:@"(%@)%@", NSStringFromClass([obj class]), desc];
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
        _currentMenuAlert = nil;
        [self setupGlobalWakeGesture];
    }
    return self;
}

- (void)setupGlobalWakeGesture {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.globalWakeGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleGlobalWake:)];
        self.globalWakeGesture.numberOfTouchesRequired = 2;
        self.globalWakeGesture.minimumPressDuration = 2.0;
        self.globalWakeGesture.cancelsTouchesInView = NO;
        UIWindow *keyWindow = [self topmostWindow];
        if (keyWindow) {
            [keyWindow addGestureRecognizer:self.globalWakeGesture];
        }
    });
}

- (void)handleGlobalWake:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        if (!self.floatingButton) {
            [self showFloatingButton];
            AudioServicesPlaySystemSound(1519);
            NSLog(@"[Tweak] 检测到双指长按 2 秒，悬浮窗已还原唤醒。");
        }
    }
}

- (void)showFloatingButton {
    if (self.floatingButton) {
        [self ensureButtonOnTop];
        return;
    }
    UIWindow *keyWindow = [self topmostWindow];
    if (!keyWindow) return;
    self.lastWindow = keyWindow;
    if (![keyWindow.gestureRecognizers containsObject:self.globalWakeGesture] && self.globalWakeGesture) {
        [keyWindow addGestureRecognizer:self.globalWakeGesture];
    }
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
    UIView *existingPanel = [keyWindow viewWithTag:99998];
    if (existingPanel) {
        [self dismissMenuPanel];
    } else {
        [self showCustomMenuPanel];
    }
}

- (void)showCustomMenuPanel {
    UIWindow *keyWindow = [self topmostWindow];
    if (!keyWindow) return;
    UIViewController *topVC = [self topViewControllerFromWindow:keyWindow];
    if (!topVC) return;

    UIView *overlayView = [[UIView alloc] initWithFrame:keyWindow.bounds];
    overlayView.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.5];
    overlayView.tag = 99999;
    overlayView.alpha = 0;
    [keyWindow addSubview:overlayView];

    UITapGestureRecognizer *tapOverlay = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissMenuPanel)];
    [overlayView addGestureRecognizer:tapOverlay];

    CGFloat panelWidth = 320;
    CGFloat panelHeight = 420;
    CGFloat panelX = (keyWindow.bounds.size.width - panelWidth) / 2;
    CGFloat panelY = (keyWindow.bounds.size.height - panelHeight) / 2;

    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(panelX, panelY, panelWidth, panelHeight)];
    panel.backgroundColor = [UIColor colorWithRed:0.12 green:0.12 blue:0.14 alpha:0.98];
    panel.layer.cornerRadius = 16;
    panel.layer.masksToBounds = YES;
    panel.layer.borderWidth = 1;
    panel.layer.borderColor = [UIColor colorWithRed:0.3 green:0.3 blue:0.35 alpha:1.0].CGColor;
    panel.tag = 99998;
    panel.alpha = 0;
    panel.transform = CGAffineTransformMakeScale(0.9, 0.9);
    [keyWindow addSubview:panel];

    UIView *titleBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, panelWidth, 48)];
    titleBar.backgroundColor = [UIColor colorWithRed:0.15 green:0.15 blue:0.18 alpha:1.0];
    [panel addSubview:titleBar];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, panelWidth, 48)];
    titleLabel.text = @"🛠️ Tweak 功能面板";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont boldSystemFontOfSize:17];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [titleBar addSubview:titleLabel];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.frame = CGRectMake(panelWidth - 44, 8, 32, 32);
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor colorWithRed:1.0 green:0.4 blue:0.4 alpha:1.0] forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    [closeBtn addTarget:self action:@selector(dismissMenuPanel) forControlEvents:UIControlEventTouchUpInside];
    [titleBar addSubview:closeBtn];

    CGFloat yOffset = 64;
    CGFloat rowHeight = 56;
    [self addSwitchRowToPanel:panel
                         y:yOffset
                       icon:@"📋"
                      title:@"日志窗口显示"
                   subtitle:[[LogWindowManager sharedInstance] isVisible] ? @"当前：显示中" : @"当前：已隐藏"
                    isOn:[[LogWindowManager sharedInstance] isVisible]
                      tag:1001];
    yOffset += rowHeight;

    [self addSwitchRowToPanel:panel
                         y:yOffset
                       icon:@"📝"
                      title:@"日志输出到屏幕"
                   subtitle:[[LogWindowManager sharedInstance] logEnabled] ? @"当前：已开启" : @"当前：已关闭"
                    isOn:[[LogWindowManager sharedInstance] logEnabled]
                      tag:1002];
    yOffset += rowHeight;

    [self addSwitchRowToPanel:panel
                         y:yOffset
                       icon:@"📁"
                      title:@"日志写入文件"
                   subtitle:[[LogWindowManager sharedInstance] logToFileEnabled] ? @"当前：已开启" : @"当前：已关闭"
                    isOn:[[LogWindowManager sharedInstance] logToFileEnabled]
                      tag:1003];
    yOffset += rowHeight + 8;

    UIView *sep1 = [[UIView alloc] initWithFrame:CGRectMake(16, yOffset - 4, panelWidth - 32, 1)];
    sep1.backgroundColor = [UIColor colorWithRed:0.25 green:0.25 blue:0.3 alpha:1.0];
    [panel addSubview:sep1];

    NSString *replaceStatus = self.totalReplacedCount > 0 ? [NSString stringWithFormat:@"已替换 %d 次", self.totalReplacedCount] : @"未触发替换";
    [self addActionRowToPanel:panel
                          y:yOffset
                        icon:@"🔄"
                       title:@"字符串替换"
                    subtitle:replaceStatus
                       color:[UIColor colorWithRed:0.3 green:0.8 blue:0.4 alpha:1.0]
                      action:@selector(showReplaceStatus)];
    yOffset += rowHeight;

    [self addActionRowToPanel:panel
                          y:yOffset
                        icon:@"📂"
                       title:@"日志文件路径"
                    subtitle:@"点击查看"
                       color:[UIColor colorWithRed:0.4 green:0.6 blue:1.0 alpha:1.0]
                      action:@selector(showLogFilePath)];
    yOffset += rowHeight + 8;

    UIView *sep2 = [[UIView alloc] initWithFrame:CGRectMake(16, yOffset - 4, panelWidth - 32, 1)];
    sep2.backgroundColor = [UIColor colorWithRed:0.25 green:0.25 blue:0.3 alpha:1.0];
    [panel addSubview:sep2];

    UIButton *hideFloatBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    hideFloatBtn.frame = CGRectMake(16, yOffset, panelWidth - 32, 44);
    hideFloatBtn.backgroundColor = [UIColor colorWithRed:0.9 green:0.25 blue:0.25 alpha:1.0];
    hideFloatBtn.layer.cornerRadius = 10;
    hideFloatBtn.layer.masksToBounds = YES;
    [hideFloatBtn setTitle:@"❌ 关闭悬浮窗 (可双指长按2秒还原)" forState:UIControlStateNormal];
    hideFloatBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [hideFloatBtn addTarget:self action:@selector(hideFloatingButtonFromMenu) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:hideFloatBtn];

    [UIView animateWithDuration:0.25 animations:^{
        overlayView.alpha = 1;
        panel.alpha = 1;
        panel.transform = CGAffineTransformIdentity;
    }];
}

- (void)addSwitchRowToPanel:(UIView *)panel y:(CGFloat)y icon:(NSString *)icon title:(NSString *)title subtitle:(NSString *)subtitle isOn:(BOOL)isOn tag:(NSInteger)tag {
    CGFloat panelWidth = panel.frame.size.width;
    UIView *row = [[UIView alloc] initWithFrame:CGRectMake(0, y, panelWidth, 56)];
    row.tag = tag;
    [panel addSubview:row];

    UILabel *iconLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 8, 32, 32)];
    iconLabel.text = icon;
    iconLabel.font = [UIFont systemFontOfSize:22];
    [row addSubview:iconLabel];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(56, 6, 180, 22)];
    titleLabel.text = title;
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [row addSubview:titleLabel];

    UILabel *subLabel = [[UILabel alloc] initWithFrame:CGRectMake(56, 28, 180, 18)];
    subLabel.text = subtitle;
    subLabel.textColor = [UIColor colorWithRed:0.6 green:0.6 blue:0.65 alpha:1.0];
    subLabel.font = [UIFont systemFontOfSize:12];
    [row addSubview:subLabel];

    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(panelWidth - 66, 12, 51, 31)];
    sw.on = isOn;
    sw.tag = tag;
    sw.onTintColor = [UIColor colorWithRed:0.2 green:0.7 blue:1.0 alpha:1.0];
    [sw addTarget:self action:@selector(switchValueChanged:) forControlEvents:UIControlEventValueChanged];
    [row addSubview:sw];

    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(56, 55, panelWidth - 72, 1)];
    line.backgroundColor = [UIColor colorWithRed:0.2 green:0.2 blue:0.25 alpha:1.0];
    [row addSubview:line];
}

- (void)addActionRowToPanel:(UIView *)panel y:(CGFloat)y icon:(NSString *)icon title:(NSString *)title subtitle:(NSString *)subtitle color:(UIColor *)color action:(SEL)action {
    CGFloat panelWidth = panel.frame.size.width;
    UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
    row.frame = CGRectMake(0, y, panelWidth, 56);
    [row addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:row];

    UILabel *iconLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 8, 32, 32)];
    iconLabel.text = icon;
    iconLabel.font = [UIFont systemFontOfSize:22];
    [row addSubview:iconLabel];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(56, 6, 180, 22)];
    titleLabel.text = title;
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [row addSubview:titleLabel];

    UILabel *subLabel = [[UILabel alloc] initWithFrame:CGRectMake(56, 28, 180, 18)];
    subLabel.text = subtitle;
    subLabel.textColor = color;
    subLabel.font = [UIFont systemFontOfSize:12];
    [row addSubview:subLabel];

    UILabel *arrowLabel = [[UILabel alloc] initWithFrame:CGRectMake(panelWidth - 36, 14, 24, 24)];
    arrowLabel.text = @"›";
    arrowLabel.textColor = [UIColor colorWithRed:0.5 green:0.5 blue:0.55 alpha:1.0];
    arrowLabel.font = [UIFont systemFontOfSize:22];
    [row addSubview:arrowLabel];

    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(56, 55, panelWidth - 72, 1)];
    line.backgroundColor = [UIColor colorWithRed:0.2 green:0.2 blue:0.25 alpha:1.0];
    [row addSubview:line];
}
- (void)switchValueChanged:(UISwitch *)sender {
    switch (sender.tag) {
        case 1001: {
            [[LogWindowManager sharedInstance] toggleLogWindow];
            break;
        }
        case 1002: {
            BOOL newState = ![[LogWindowManager sharedInstance] logEnabled];
            [[LogWindowManager sharedInstance] setLogEnabled:newState];
            [self updateMenuSubtitleForTag:1002 text:newState ? @"当前：已开启" : @"当前：已关闭"];
            if (!newState) {
                [[LogWindowManager sharedInstance] hideLogWindow];
            }
            break;
        }
        case 1003: {
            BOOL newState = ![[LogWindowManager sharedInstance] logToFileEnabled];
            [[LogWindowManager sharedInstance] setLogToFileEnabled:newState];
            [self updateMenuSubtitleForTag:1003 text:newState ? @"当前：已开启" : @"当前：已关闭"];
            break;
        }
    }
}

- (void)updateMenuSubtitleForTag:(NSInteger)tag text:(NSString *)text {
    UIWindow *keyWindow = [self topmostWindow];
    if (!keyWindow) return;
    UIView *panel = [keyWindow viewWithTag:99998];
    if (!panel) return;
    UIView *row = [panel viewWithTag:tag];
    if (!row) return;
    for (UIView *sub in row.subviews) {
        if ([sub isKindOfClass:[UILabel class]] && sub.frame.origin.y > 20) {
            ((UILabel *)sub).text = text;
            break;
        }
    }
}

- (void)showReplaceStatus {
    NSString *msg = [NSString stringWithFormat:@"字符串替换已激活\n已累计替换 %d 次", self.totalReplacedCount];
    [self showMessage:@"替换状态" message:msg];
    [self dismissMenuPanel];
}

- (void)showLogFilePath {
    NSString *path = [[LogWindowManager sharedInstance] logFilePath];
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    pasteboard.string = path;
    [self showMessage:@"日志文件路径" message:[NSString stringWithFormat:@"%@\n\n已复制到剪贴板", path]];
    [self dismissMenuPanel];
}

- (void)hideFloatingButtonFromMenu {
    [self dismissMenuPanel];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self hideFloatingButton];
    });
}

- (void)dismissMenuPanel {
    UIWindow *keyWindow = [self topmostWindow];
    if (!keyWindow) return;
    UIView *overlay = [keyWindow viewWithTag:99999];
    UIView *panel = [keyWindow viewWithTag:99998];
    
    [UIView animateWithDuration:0.2 animations:^{
        overlay.alpha = 0;
        panel.alpha = 0;
        panel.transform = CGAffineTransformMakeScale(0.9, 0.9);
    } completion:^(BOOL finished) {
        [overlay removeFromSuperview];
        [panel removeFromSuperview];
    }];
}

#pragma mark - ========== 字符串替换工具 ==========

- (NSString *)targetKeyword {
    return @".curLevel)?this.freeRefreshNum=2:this.freeRefreshNum=0";
}

- (NSString *)replacementString {
    return @".curLevel),this.refreshNum=100,this.freeRefreshNum=100";
}

- (BOOL)stringContainsTarget:(NSString *)string {
    if (!string || string.length < 10) return NO;
    return [string containsString:[self targetKeyword]];
}

- (BOOL)dataContainsTarget:(NSData *)data {
    if (!data || data.length < 20) return NO;
    NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!str) {
        str = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
    }
    if (!str) return NO;
    return [self stringContainsTarget:str];
}

- (NSString *)replaceTargetInString:(NSString *)string {
    if (!string || string.length < 20) return string;
    NSString *target = [self targetKeyword];
    NSString *replacement = [self replacementString];
    if ([string containsString:target]) {
        NSString *modified = [string stringByReplacingOccurrencesOfString:target withString:replacement];
        if (![modified isEqualToString:string]) {
            self.totalReplacedCount++;
            NSString *log = [NSString stringWithFormat:@"✅ NSString 替换成功 (第 %d 次)", self.totalReplacedCount];
            NSLog(@"[Tweak] %@", log);
            [[LogWindowManager sharedInstance] appendLog:log];
            return modified;
        }
    }
    return string;
}

- (NSData *)replaceTargetInData:(NSData *)data {
    if (!data || data.length < 20) return data;
    NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!str) {
        str = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
    }
    if (!str || str.length < 20) return data;
    
    NSString *modified = [self replaceTargetInString:str];
    if (![modified isEqualToString:str]) {
        NSData *newData = [modified dataUsingEncoding:NSUTF8StringEncoding];
        if (newData) {
            NSString *log = [NSString stringWithFormat:@"✅ NSData 替换成功 (第 %d 次) | 原长度:%lu -> 新长度:%lu", 
                           self.totalReplacedCount, (unsigned long)data.length, (unsigned long)newData.length];
            NSLog(@"[Tweak] %@", log);
            [[LogWindowManager sharedInstance] appendLog:log];
            return newData;
        }
    }
    return data;
}

- (id)replaceTargetInObject:(id)obj {
    if (!obj) return obj;
    if ([obj isKindOfClass:[NSString class]]) {
        return [self replaceTargetInString:(NSString *)obj];
    }
    if ([obj isKindOfClass:[NSData class]]) {
        return [self replaceTargetInData:(NSData *)obj];
    }
    return obj;
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    UIView *button = gesture.view;
    CGPoint translation = [gesture translationInView:button.superview];
    button.center = CGPointMake(button.center.x + translation.x, button.center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:button.superview];
}

- (void)hideFloatingButton {
    [self dismissMenuPanel];
    [self.keepOnTopTimer invalidate];
    self.keepOnTopTimer = nil;
    [self.floatingButton removeFromSuperview];
    self.floatingButton = nil;
}

- (UIViewController *)topViewControllerFromWindow:(UIWindow *)window {
    UIViewController *topVC = window.rootViewController;
    while (topVC.presentedViewController) {
        topVC = topVC.presentedViewController;
    }
    return topVC;
}

#pragma mark - ========== 递归保护 ==========

static _Thread_local BOOL g_inHook = NO;
#pragma mark - ========== 动态拦截 WKURLSchemeTask 响应数据 ==========


// 定义关联对象的唯一 Key，用于跨方法传递 Content-Type
static const char *kTaskContentTypeKey = "kTaskContentTypeKey";

static void hookURLSchemeTask(id urlSchemeTask) {
    if (!urlSchemeTask) return;
    
    Class taskClass = [urlSchemeTask class];
    
    static NSMutableSet *hookedClasses = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        hookedClasses = [NSMutableSet set];
    });
    
    @synchronized (hookedClasses) {
        NSString *clsName = NSStringFromClass(taskClass);
        if ([hookedClasses containsObject:clsName]) {
            return;
        }
        [hookedClasses addObject:clsName];
    }
    
    // ================== 1. Hook didReceiveResponse: 捕获 Content-Type ==================
    SEL didReceiveResponseSel = NSSelectorFromString(@"didReceiveResponse:");
    Method didReceiveResponseMethod = class_getInstanceMethod(taskClass, didReceiveResponseSel);
    if (didReceiveResponseMethod) {
        IMP origDidReceiveResponse = method_getImplementation(didReceiveResponseMethod);
        
        IMP newDidReceiveResponse = imp_implementationWithBlock(^(id taskSelf, NSURLResponse *response) {
            NSString *contentType = @"(unknown)";
            
            // 优先从 HTTP 响应头提取，其次兜底使用 MIMEType
            if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
                NSDictionary *headers = [(NSHTTPURLResponse *)response allHeaderFields];
                contentType = headers[@"Content-Type"] ?: headers[@"content-type"] ?: @"(none)";
            } else if (response.MIMEType) {
                contentType = response.MIMEType;
            }
            
            // 使用 Associated Object 将 Content-Type 动态绑定到 taskSelf 实例上
            objc_setAssociatedObject(taskSelf, kTaskContentTypeKey, contentType, OBJC_ASSOCIATION_COPY_NONATOMIC);
            
            typedef void (*orig_resp_fn_t)(id, SEL, NSURLResponse *);
            ((orig_resp_fn_t)origDidReceiveResponse)(taskSelf, didReceiveResponseSel, response);
        });
        
        method_setImplementation(didReceiveResponseMethod, newDidReceiveResponse);
    }
    
    // ================== 2. Hook didReceiveData: 处理并记录日志（带 Content-Type） ==================
    SEL didReceiveDataSel = NSSelectorFromString(@"didReceiveData:");
    Method didReceiveDataMethod = class_getInstanceMethod(taskClass, didReceiveDataSel);
    if (didReceiveDataMethod) {
        IMP origDidReceiveData = method_getImplementation(didReceiveDataMethod);
        
        IMP newDidReceiveData = imp_implementationWithBlock(^(id taskSelf, NSData *data) {
            // 安全从 taskSelf 現場获取 request 真实的 URL
            NSString *taskUrl = @"(unknown)";
            if ([taskSelf respondsToSelector:@selector(request)]) {
                NSURLRequest *req = [taskSelf request];
                if (req && req.URL) {
                    taskUrl = [req.URL absoluteString];
                }
            }
            
            // 【核心改动】取出之前在 didReceiveResponse: 中绑定的 Content-Type
            NSString *contentType = objc_getAssociatedObject(taskSelf, kTaskContentTypeKey) ?: @"(unknown)";
            
            // 执行原本的业务逻辑与目标替换
            NSData *modifiedData = [[FloatingButtonManager sharedInstance] replaceTargetInData:data];
            BOOL didReplace = (modifiedData != data && ![modifiedData isEqual:data]);
            BOOL hasTarget = data ? [[FloatingButtonManager sharedInstance] dataContainsTarget:data] : NO;
            
            NSString *dataPreview = data ? [[LogWindowManager sharedInstance] truncateData:data maxLength:200] : @"(nil)";
            NSString *dataFull = data ? [data description] : @"(nil)";
            
            // 日志加入 [Type=xxx] 的格式化输出
            NSString *fullLog = [NSString stringWithFormat:@"%@ [WKURLSchemeTask didReceiveData][Type=%@] URL=%%@ %@ %@ | data=%@",
                             hasTarget ? @"🎯" : @"📋",
                             contentType,
                             taskUrl,
                             hasTarget ? @"发现目标" : @"",
                             didReplace ? @"[已替换]" : @"",
                             dataFull];
                             
            NSString *displayLog = [NSString stringWithFormat:@"%@ [WKURLSchemeTask didReceiveData][Type=%@] URL=%@ %@ %@ | data=%@",
                             hasTarget ? @"🎯" : @"📋",
                             contentType,
                             taskUrl,
                             hasTarget ? @"发现目标" : @"",
                             didReplace ? @"[已替换]" : @"",
                             dataPreview];
                             
            NSLog(@"[Tweak] %@", fullLog);
            [[LogWindowManager sharedInstance] appendLogFull:fullLog displayLog:displayLog];
            
            if (data && data.length > 0) {
                NSString *dataStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
                NSString *responseLog = [NSString stringWithFormat:@"[RESPONSE][Type=%@] URL=%@ | LENGTH=%lu | CONTENT=%@",
                                       contentType, taskUrl, (unsigned long)data.length, dataStr ?: @"(binary data)"];
                [[LogWindowManager sharedInstance] writeLogToFile:responseLog];
            }
            
            typedef void (*orig_data_fn_t)(id, SEL, NSData *);
            ((orig_data_fn_t)origDidReceiveData)(taskSelf, didReceiveDataSel, modifiedData);
        });
        
        method_setImplementation(didReceiveDataMethod, newDidReceiveData);
    }
    
    // ================== 3. 底层其余配套方法保持原样 ==================
    SEL didFinishSel = NSSelectorFromString(@"didFinish");
    Method didFinishMethod = class_getInstanceMethod(taskClass, didFinishSel);
    if (didFinishMethod) {
        IMP origDidFinish = method_getImplementation(didFinishMethod);
        IMP newDidFinish = imp_implementationWithBlock(^(id taskSelf) {
            typedef void (*orig_finish_fn_t)(id, SEL);
            ((orig_finish_fn_t)origDidFinish)(taskSelf, didFinishSel);
        });
        method_setImplementation(didFinishMethod, newDidFinish);
    }
    
    SEL didFailSel = NSSelectorFromString(@"didFailWithError:");
    Method didFailMethod = class_getInstanceMethod(taskClass, didFailSel);
    if (didFailMethod) {
        IMP origDidFail = method_getImplementation(didFailMethod);
        IMP newDidFail = imp_implementationWithBlock(^(id taskSelf, NSError *error) {
            typedef void (*orig_fail_fn_t)(id, SEL, NSError *);
            ((orig_fail_fn_t)origDidFail)(taskSelf, didFailSel, error);
        });
        method_setImplementation(didFailMethod, newDidFail);
    }
}


#pragma mark - ========== 用户指定的 Hook 实现 ==========

// ========== 1. BDPWKURLSchemeHandler ==========

static void (*orig_BDPWKURLSchemeHandler_webView_startURLSchemeTask)(id self, SEL _cmd, WKWebView *webView, id urlSchemeTask);
static void hook_BDPWKURLSchemeHandler_webView_startURLSchemeTask(id self, SEL _cmd, WKWebView *webView, id urlSchemeTask) {
    if (g_inHook) {
        orig_BDPWKURLSchemeHandler_webView_startURLSchemeTask(self, _cmd, webView, urlSchemeTask);
        return;
    }
    g_inHook = YES;

    NSString *urlStr = @"(nil)";
    if (urlSchemeTask && [urlSchemeTask respondsToSelector:@selector(request)]) {
        NSURLRequest *req = [urlSchemeTask request];
        if (req && req.URL) {
            urlStr = [req.URL absoluteString];
        }
    }

    // 触发子任务中内部协议方法的底层拦截绑定
    hookURLSchemeTask(urlSchemeTask);

    NSString *fullLog = [NSString stringWithFormat:@"📋 [BDPWKURLSchemeHandler webView:startURLSchemeTask:] URL=%@", urlStr];
    NSString *displayLog = [NSString stringWithFormat:@"📋 [BDPWKURLSchemeHandler webView:startURLSchemeTask:] URL=%@", 
                           [[LogWindowManager sharedInstance] truncateString:urlStr maxLength:120]];
    NSLog(@"[Tweak] %@", fullLog);
    [[LogWindowManager sharedInstance] appendLogFull:fullLog displayLog:displayLog];
    
    NSString *requestLog = [NSString stringWithFormat:@"[REQUEST] URL=%@", urlStr];
    [[LogWindowManager sharedInstance] writeLogToFile:requestLog];

    orig_BDPWKURLSchemeHandler_webView_startURLSchemeTask(self, _cmd, webView, urlSchemeTask);
    g_inHook = NO;
}

static void (*orig_BDPWKURLSchemeHandler_handleResponseWithTask)(id self, SEL _cmd, id task, id data, id urlInfo, id error);
static void hook_BDPWKURLSchemeHandler_handleResponseWithTask(id self, SEL _cmd, id task, id data, id urlInfo, id error) {
    if (g_inHook) {
        orig_BDPWKURLSchemeHandler_handleResponseWithTask(self, _cmd, task, data, urlInfo, error);
        return;
    }
    g_inHook = YES;
    
    id modifiedData = [[FloatingButtonManager sharedInstance] replaceTargetInObject:data];
    BOOL didReplaceData = (modifiedData != data && ![modifiedData isEqual:data]);
    BOOL hasTargetInData = NO;
    if ([data isKindOfClass:[NSString class]]) {
        hasTargetInData = [[FloatingButtonManager sharedInstance] stringContainsTarget:(NSString *)data];
    } else if ([data isKindOfClass:[NSData class]]) {
        hasTargetInData = [[FloatingButtonManager sharedInstance] dataContainsTarget:(NSData *)data];
    }
    
    NSString *taskDesc = [[LogWindowManager sharedInstance] objectDescription:task maxLength:80];
    NSString *dataDesc = [[LogWindowManager sharedInstance] objectDescription:data maxLength:120];
    NSString *urlInfoDesc = [[LogWindowManager sharedInstance] objectDescription:urlInfo maxLength:120];
    NSString *errorDesc = [[LogWindowManager sharedInstance] objectDescription:error maxLength:80];
    NSString *fullLog = [NSString stringWithFormat:@"%@ [BDPWKURLSchemeHandler handleResponseWithTask] task=%@ | data=%@ | ofURLInfo=%@ | withError=%@",
                     hasTargetInData ? @"🎯" : @"📋",
                     [[LogWindowManager sharedInstance] objectDescription:task maxLength:1000], 
                     [[LogWindowManager sharedInstance] objectDescription:data maxLength:2000], 
                     [[LogWindowManager sharedInstance] objectDescription:urlInfo maxLength:2000], 
                     [[LogWindowManager sharedInstance] objectDescription:error maxLength:1000]];
    NSString *displayLog = [NSString stringWithFormat:@"%@ [BDPWKURLSchemeHandler handleResponseWithTask] %@ %@ | task=%@ | data=%@ | ofURLInfo=%@ | withError=%@",
                     hasTargetInData ? @"🎯" : @"📋",
                     hasTargetInData ? @"发现目标" : @"",
                     didReplaceData ? @"[已替换]" : @"",
                     taskDesc, dataDesc, urlInfoDesc, errorDesc];
    NSLog(@"[Tweak] %@", fullLog);
    [[LogWindowManager sharedInstance] appendLogFull:fullLog displayLog:displayLog];
    
    orig_BDPWKURLSchemeHandler_handleResponseWithTask(self, _cmd, task, modifiedData, urlInfo, error);
    g_inHook = NO;
}
// ========== 2. WKUserContentController ==========

static void (*orig_WKUserContentController_addUserScript)(id self, SEL _cmd, WKUserScript *userScript);
static void hook_WKUserContentController_addUserScript(id self, SEL _cmd, WKUserScript *userScript) {
    if (g_inHook) {
        orig_WKUserContentController_addUserScript(self, _cmd, userScript);
        return;
    }
    g_inHook = YES;
    NSString *source = @"(nil)";
    BOOL hasTarget = NO;
    BOOL didReplace = NO;
    WKUserScript *modifiedScript = userScript;
    if (userScript) {
        NSString *src = [userScript source];
        if (src) {
            source = [[LogWindowManager sharedInstance] truncateString:src maxLength:120];
            hasTarget = [[FloatingButtonManager sharedInstance] stringContainsTarget:src];
            NSString *modified = [[FloatingButtonManager sharedInstance] replaceTargetInString:src];
            didReplace = ![modified isEqualToString:src];
            if (didReplace) {
                modifiedScript = [[WKUserScript alloc] initWithSource:modified injectionTime:[userScript injectionTime] forMainFrameOnly:[userScript isForMainFrameOnly]];
            }
        }
    }
    NSString *srcFull = @"(nil)";
    if (userScript) {
        NSString *src = [userScript source];
        if (src) srcFull = src;
    }
    NSString *fullLog = [NSString stringWithFormat:@"%@ [WKUserContentController addUserScript] %@ %@ | source=%@",
                     hasTarget ? @"🎯" : @"📋",
                     hasTarget ? @"发现目标" : @"",
                     didReplace ? @"[已替换]" : @"",
                     srcFull];
    NSString *displayLog = [NSString stringWithFormat:@"%@ [WKUserContentController addUserScript] %@ %@ | source=%@",
                     hasTarget ? @"🎯" : @"📋",
                     hasTarget ? @"发现目标" : @"",
                     didReplace ? @"[已替换]" : @"",
                     source];
    NSLog(@"[Tweak] %@", fullLog);
    [[LogWindowManager sharedInstance] appendLogFull:fullLog displayLog:displayLog];
    orig_WKUserContentController_addUserScript(self, _cmd, modifiedScript);
    g_inHook = NO;
}

// ========== 3. BDPLocalFileManager ==========

static NSData *(*orig_BDPLocalFileManager_readFileWithLocalURL)(id self, SEL _cmd, NSURL *url, id *error);
static NSData *hook_BDPLocalFileManager_readFileWithLocalURL(id self, SEL _cmd, NSURL *url, id *error) {
    if (g_inHook) {
        return orig_BDPLocalFileManager_readFileWithLocalURL(self, _cmd, url, error);
    }
    g_inHook = YES;
    NSString *urlStr = url ? [url absoluteString] : @"(nil)";
    NSData *result = orig_BDPLocalFileManager_readFileWithLocalURL(self, _cmd, url, error);
    
    NSData *modifiedResult = [[FloatingButtonManager sharedInstance] replaceTargetInData:result];
    BOOL didReplace = (modifiedResult != result && ![modifiedResult isEqual:result]);
    BOOL hasTarget = result ? [[FloatingButtonManager sharedInstance] dataContainsTarget:result] : NO;
    
    NSString *dataPreview = @"(nil)";
    if (result) {
        dataPreview = [[LogWindowManager sharedInstance] truncateData:result maxLength:80];
    }
    NSString *dataFull = @"(nil)";
    if (result) {
        dataFull = [result description];
    }
    NSString *fullLog = [NSString stringWithFormat:@"%@ [BDPLocalFileManager readFileWithLocalURL] %@ %@ | url=%@ -> data=%@", 
                     hasTarget ? @"🎯" : @"📋",
                     hasTarget ? @"发现目标" : @"",
                     didReplace ? @"[已替换]" : @"",
                     urlStr, dataFull];
    NSString *displayLog = [NSString stringWithFormat:@"%@ [BDPLocalFileManager readFileWithLocalURL] %@ %@ | url=%@ -> data=%@", 
                     hasTarget ? @"🎯" : @"📋",
                     hasTarget ? @"发现目标" : @"",
                     didReplace ? @"[已替换]" : @"",
                     urlStr, dataPreview];
    NSLog(@"[Tweak] %@", fullLog);
    [[LogWindowManager sharedInstance] appendLogFull:fullLog displayLog:displayLog];
    g_inHook = NO;
    return modifiedResult;
}
static NSString *(*orig_BDPLocalFileManager_stringWithLocalURL)(id self, SEL _cmd, NSURL *url, unsigned long encoding, id *error);
static NSString *hook_BDPLocalFileManager_stringWithLocalURL(id self, SEL _cmd, NSURL *url, unsigned long encoding, id *error) {
    if (g_inHook) {
        return orig_BDPLocalFileManager_stringWithLocalURL(self, _cmd, url, encoding, error);
    }
    g_inHook = YES;
    NSString *urlStr = url ? [url absoluteString] : @"(nil)";
    NSString *result = orig_BDPLocalFileManager_stringWithLocalURL(self, _cmd, url, encoding, error);
    
    NSString *modifiedResult = [[FloatingButtonManager sharedInstance] replaceTargetInString:result];
    BOOL didReplace = ![modifiedResult isEqualToString:result];
    BOOL hasTarget = result ? [[FloatingButtonManager sharedInstance] stringContainsTarget:result] : NO;
    
    NSString *strPreview = @"(nil)";
    if (result) {
        strPreview = [[LogWindowManager sharedInstance] truncateString:result maxLength:120];
    }
    NSString *strFull = result ?: @"(nil)";
    NSString *fullLog = [NSString stringWithFormat:@"%@ [BDPLocalFileManager stringWithLocalURL] encoding:%lu %@ %@ | url=%@ -> string=%@",
                     hasTarget ? @"🎯" : @"📋",
                     (unsigned long)encoding,
                     hasTarget ? @"发现目标" : @"",
                     didReplace ? @"[已替换]" : @"",
                     urlStr, strFull];
    NSString *displayLog = [NSString stringWithFormat:@"%@ [BDPLocalFileManager stringWithLocalURL] encoding:%lu %@ %@ | url=%@ -> string=%@",
                     hasTarget ? @"🎯" : @"📋",
                     (unsigned long)encoding,
                     hasTarget ? @"发现目标" : @"",
                     didReplace ? @"[已替换]" : @"",
                     urlStr, strPreview];
    NSLog(@"[Tweak] %@", fullLog);
    [[LogWindowManager sharedInstance] appendLogFull:fullLog displayLog:displayLog];
    g_inHook = NO;
    return modifiedResult;
}

// ========== 4. BDPWKGamePage ==========

static void (*orig_BDPWKGamePage_evaluateJavaScript)(id self, SEL _cmd, NSString *javaScriptString, id completionHandler);
static void hook_BDPWKGamePage_evaluateJavaScript(id self, SEL _cmd, NSString *javaScriptString, id completionHandler) {
    if (g_inHook) {
        orig_BDPWKGamePage_evaluateJavaScript(self, _cmd, javaScriptString, completionHandler);
        return;
    }
    g_inHook = YES;
    NSString *modified = [[FloatingButtonManager sharedInstance] replaceTargetInString:javaScriptString];
    BOOL didReplace = ![modified isEqualToString:javaScriptString];
    BOOL hasTarget = javaScriptString && [[FloatingButtonManager sharedInstance] stringContainsTarget:javaScriptString];
    NSString *preview = @"(nil)";
    if (javaScriptString) {
        preview = [[LogWindowManager sharedInstance] truncateString:javaScriptString maxLength:120];
    }
    NSString *scriptFull = javaScriptString ?: @"(nil)";
    NSString *fullLog = [NSString stringWithFormat:@"%@ [BDPWKGamePage evaluateJavaScript] %@ %@ | script=%@",
                     hasTarget ? @"🎯" : @"📋",
                     hasTarget ? @"发现目标" : @"",
                     didReplace ? @"[已替换]" : @"",
                     scriptFull];
    NSString *displayLog = [NSString stringWithFormat:@"%@ [BDPWKGamePage evaluateJavaScript] %@ %@ | script=%@",
                     hasTarget ? @"🎯" : @"📋",
                     hasTarget ? @"发现目标" : @"",
                     didReplace ? @"[已替换]" : @"",
                     preview];
    NSLog(@"[Tweak] %@", fullLog);
    [[LogWindowManager sharedInstance] appendLogFull:fullLog displayLog:displayLog];
    orig_BDPWKGamePage_evaluateJavaScript(self, _cmd, modified, completionHandler);
    g_inHook = NO;
}

// ========== 5. BDPWKGameBusinessEngine ==========

static void (*orig_BDPWKGameBusinessEngine_evaluateScript)(id self, SEL _cmd, id script, NSInteger pageID, NSUInteger dest, id completion);
static void hook_BDPWKGameBusinessEngine_evaluateScript(id self, SEL _cmd, id script, NSInteger pageID, NSUInteger dest, id completion) {
    if (g_inHook) {
        orig_BDPWKGameBusinessEngine_evaluateScript(self, _cmd, script, pageID, dest, completion);
        return;
    }
    g_inHook = YES;
    
    id modifiedScript = [[FloatingButtonManager sharedInstance] replaceTargetInObject:script];
    BOOL didReplace = (modifiedScript != script && ![modifiedScript isEqual:script]);
    BOOL hasTarget = NO;
    NSString *scriptPreview = @"(nil)";
    NSString *scriptFull = @"(nil)";
    
    if (script) {
        if ([script isKindOfClass:[NSString class]]) {
            NSString *str = (NSString *)script;
            scriptPreview = [[LogWindowManager sharedInstance] truncateString:str maxLength:120];
            scriptFull = str;
            hasTarget = [[FloatingButtonManager sharedInstance] stringContainsTarget:str];
        } else if ([script isKindOfClass:[NSData class]]) {
            NSData *data = (NSData *)script;
            scriptPreview = [[LogWindowManager sharedInstance] truncateData:data maxLength:80];
            scriptFull = [data description];
            hasTarget = [[FloatingButtonManager sharedInstance] dataContainsTarget:data];
        } else {
            scriptPreview = [NSString stringWithFormat:@"(%@)%@", NSStringFromClass([script class]), script];
            scriptFull = scriptPreview;
        }
    }
    
    NSString *fullLog = [NSString stringWithFormat:@"%@ [BDPWKGameBusinessEngine evaluateScript] pageID:%ld dest:%lu %@ %@ | script=%@",
                     hasTarget ? @"🎯" : @"📋",
                     (long)pageID,
                     (unsigned long)dest,
                     hasTarget ? @"发现目标" : @"",
                     didReplace ? @"[已替换]" : @"",
                     scriptFull];
    NSString *displayLog = [NSString stringWithFormat:@"%@ [BDPWKGameBusinessEngine evaluateScript] pageID:%ld dest:%lu %@ %@ | script=%@",
                     hasTarget ? @"🎯" : @"📋",
                     (long)pageID,
                     (unsigned long)dest,
                     hasTarget ? @"发现目标" : @"",
                     didReplace ? @"[已替换]" : @"",
                     scriptPreview];
    NSLog(@"[Tweak] %@", fullLog);
    [[LogWindowManager sharedInstance] appendLogFull:fullLog displayLog:displayLog];
    orig_BDPWKGameBusinessEngine_evaluateScript(self, _cmd, modifiedScript, pageID, dest, completion);
    g_inHook = NO;
}
#pragma mark - ========== 启用所有 Hook 入口机制 ==========

- (void)enableAllHooks {
    [[LogWindowManager sharedInstance] appendLog:@"🚀 开始启用用户指定的类方法 Hook..."];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableArray *batchLogs = [NSMutableArray array];
        int successCount = 0;
        int failCount = 0;
        
        {
            Class cls = NSClassFromString(@"BDPWKURLSchemeHandler");
            if (!cls) {
                [batchLogs addObject:@"❌ BDPWKURLSchemeHandler 类未找到"];
                failCount++;
            } else {
                SEL sel = NSSelectorFromString(@"webView:startURLSchemeTask:");
                Method method = class_getInstanceMethod(cls, sel);
                if (!method) {
                    [batchLogs addObject:@"⚠️ BDPWKURLSchemeHandler webView:startURLSchemeTask: 方法未找到"];
                    failCount++;
                } else {
                    orig_BDPWKURLSchemeHandler_webView_startURLSchemeTask = (void (*)(id, SEL, WKWebView *, id))method_getImplementation(method);
                    method_setImplementation(method, (IMP)hook_BDPWKURLSchemeHandler_webView_startURLSchemeTask);
                    [batchLogs addObject:@"✅ BDPWKURLSchemeHandler webView:startURLSchemeTask: Hook 成功 [支持响应数据现场URL提取]"];
                    successCount++;
                }
            }
        }
        
        {
            Class cls = NSClassFromString(@"BDPWKURLSchemeHandler");
            if (!cls) {
                [batchLogs addObject:@"❌ BDPWKURLSchemeHandler 类未找到 (handleResponseWithTask)"];
                failCount++;
            } else {
                SEL sel = NSSelectorFromString(@"handleResponseWithTask:data:ofURLInfo:withError:");
                Method method = class_getInstanceMethod(cls, sel);
                if (!method) {
                    [batchLogs addObject:@"⚠️ BDPWKURLSchemeHandler handleResponseWithTask:data:ofURLInfo:withError: 方法未找到"];
                    failCount++;
                } else {
                    orig_BDPWKURLSchemeHandler_handleResponseWithTask = (void (*)(id, SEL, id, id, id, id))method_getImplementation(method);
                    method_setImplementation(method, (IMP)hook_BDPWKURLSchemeHandler_handleResponseWithTask);
                    [batchLogs addObject:@"✅ BDPWKURLSchemeHandler handleResponseWithTask:data:ofURLInfo:withError: Hook 成功"];
                    successCount++;
                }
            }
        }
        
        {
            Class cls = NSClassFromString(@"WKUserContentController");
            if (!cls) {
                [batchLogs addObject:@"❌ WKUserContentController 类未找到"];
                failCount++;
            } else {
                SEL sel = NSSelectorFromString(@"addUserScript:");
                Method method = class_getInstanceMethod(cls, sel);
                if (!method) {
                    [batchLogs addObject:@"⚠️ WKUserContentController addUserScript: 方法未找到"];
                    failCount++;
                } else {
                    orig_WKUserContentController_addUserScript = (void (*)(id, SEL, WKUserScript *))method_getImplementation(method);
                    method_setImplementation(method, (IMP)hook_WKUserContentController_addUserScript);
                    [batchLogs addObject:@"✅ WKUserContentController addUserScript: Hook 成功"];
                    successCount++;
                }
            }
        }
        
        {
            Class cls = NSClassFromString(@"BDPLocalFileManager");
            if (!cls) {
                [batchLogs addObject:@"❌ BDPLocalFileManager 类未找到"];
                failCount += 2;
            } else {
                SEL sel1 = NSSelectorFromString(@"readFileWithLocalURL:error:");
                Method method1 = class_getInstanceMethod(cls, sel1);
                if (!method1) {
                    [batchLogs addObject:@"⚠️ BDPLocalFileManager readFileWithLocalURL:error: 方法未找到"];
                    failCount++;
                } else {
                    orig_BDPLocalFileManager_readFileWithLocalURL = (NSData *(*)(id, SEL, NSURL *, id *))method_getImplementation(method1);
                    method_setImplementation(method1, (IMP)hook_BDPLocalFileManager_readFileWithLocalURL);
                    [batchLogs addObject:@"✅ BDPLocalFileManager readFileWithLocalURL:error: Hook 成功"];
                    successCount++;
                }
                SEL sel2 = NSSelectorFromString(@"stringWithLocalURL:encoding:error:");
                Method method2 = class_getInstanceMethod(cls, sel2);
                if (!method2) {
                    [batchLogs addObject:@"⚠️ BDPLocalFileManager stringWithLocalURL:encoding:error: 方法未找到"];
                    failCount++;
                } else {
                    orig_BDPLocalFileManager_stringWithLocalURL = (NSString *(*)(id, SEL, NSURL *, unsigned long, id *))method_getImplementation(method2);
                    method_setImplementation(method2, (IMP)hook_BDPLocalFileManager_stringWithLocalURL);
                    [batchLogs addObject:@"✅ BDPLocalFileManager stringWithLocalURL:encoding:error: Hook 成功"];
                    successCount++;
                }
            }
        }
        
        {
            Class cls = NSClassFromString(@"BDPWKGamePage");
            if (!cls) {
                [batchLogs addObject:@"❌ BDPWKGamePage 类未找到"];
                failCount++;
            } else {
                SEL sel = NSSelectorFromString(@"evaluateJavaScript:completionHandler:");
                Method method = class_getInstanceMethod(cls, sel);
                if (!method) {
                    [batchLogs addObject:@"⚠️ BDPWKGamePage evaluateJavaScript:completionHandler: 方法未找到"];
                    failCount++;
                } else {
                    orig_BDPWKGamePage_evaluateJavaScript = (void (*)(id, SEL, NSString *, id))method_getImplementation(method);
                    method_setImplementation(method, (IMP)hook_BDPWKGamePage_evaluateJavaScript);
                    [batchLogs addObject:@"✅ BDPWKGamePage evaluateJavaScript:completionHandler: Hook 成功"];
                    successCount++;
                }
            }
        }
        
        {
            Class cls = NSClassFromString(@"BDPWKGameBusinessEngine");
            if (!cls) {
                [batchLogs addObject:@"❌ BDPWKGameBusinessEngine 类未找到"];
                failCount++;
            } else {
                SEL sel = NSSelectorFromString(@"evaluateScript:pageID:dest:completion:");
                Method method = class_getInstanceMethod(cls, sel);
                if (!method) {
                    [batchLogs addObject:@"⚠️ BDPWKGameBusinessEngine evaluateScript:pageID:dest:completion: 方法未找到"];
                    failCount++;
                } else {
                    orig_BDPWKGameBusinessEngine_evaluateScript = (void (*)(id, SEL, id, NSInteger, NSUInteger, id))method_getImplementation(method);
                    method_setImplementation(method, (IMP)hook_BDPWKGameBusinessEngine_evaluateScript);
                    [batchLogs addObject:@"✅ BDPWKGameBusinessEngine evaluateScript:pageID:dest:completion: Hook 成功"];
                    successCount++;
                }
            }
        }
        
        self.totalHookedMethods = successCount;
        [[LogWindowManager sharedInstance] appendLogsBatch:batchLogs];
        NSString *summary = [NSString stringWithFormat:@"📊 Hook 启用完成 | 成功: %d | 失败: %d", successCount, failCount];
        [[LogWindowManager sharedInstance] appendLog:summary];
        [[LogWindowManager sharedInstance] appendLog:@"🎉 所有 Hook 已启用"];
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

@end

#pragma mark - ========== 应用构造器启动注入入口 ==========

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
