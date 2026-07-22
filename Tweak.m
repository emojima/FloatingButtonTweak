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
@property (nonatomic, strong) UILongPressGestureRecognizer *globalWakeGesture;
@property (nonatomic, assign) BOOL enableAdFreeRefresh;
@property (nonatomic, assign) BOOL enableExampleRule;
@property (nonatomic, assign) BOOL enableIncreaseRareRate;
@property (nonatomic, assign) BOOL enableIncreaseHP;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *urlReplacementRules;
@property (nonatomic, assign) CGPoint lastPanelTranslation;
+ (instancetype)sharedInstance;
- (void)showFloatingButton;
- (void)ensureButtonOnTop;
- (void)dismissMenuPanel;
- (void)updateMenuSubtitleForTag:(NSInteger)tag text:(NSString *)text;
- (void)enableAllHooks;
- (UIWindow *)topmostWindow;
- (NSString *)applyURLSpecificReplacementsToString:(NSString *)string forURL:(NSString *)urlString;
- (void)registerDefaultURLReplacementRules;
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
    // 显示日志窗口后自动关闭功能面板（仅在面板已打开时）
    UIWindow *kw2 = [self topmostWindow];
    if (kw2 && [kw2 viewWithTag:99997]) {
        [[FloatingButtonManager sharedInstance] dismissMenuPanel];
    }
}

- (void)hideLogWindow {
    self.logContainerView.hidden = YES;
    self.isVisible = NO;
    [[FloatingButtonManager sharedInstance] updateMenuSubtitleForTag:1001 text:@"当前：已隐藏"];
    // 同步更新功能面板中开关按钮的 UI 状态
    UIWindow *keyWindow = [[FloatingButtonManager sharedInstance] topmostWindow];
    if (keyWindow) {
        UIView *panelContainer = [keyWindow viewWithTag:99997];
        if (panelContainer) {
            UIView *contentView = [panelContainer viewWithTag:99998];
            if (contentView) {
                UIView *row = [contentView viewWithTag:1001];
                if (row) {
                    for (UIView *sub in row.subviews) {
                        if ([sub isKindOfClass:[UISwitch class]]) {
                            ((UISwitch *)sub).on = NO;
                            break;
                        }
                    }
                }
            }
        }
    }
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
        _enableAdFreeRefresh = NO;
        _enableExampleRule = NO;
        _enableIncreaseRareRate = NO;
        _enableIncreaseHP = NO;
        _urlReplacementRules = [NSMutableArray array];
        [self registerDefaultURLReplacementRules];
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
    UIView *existingScrollPanel = [keyWindow viewWithTag:99997];
    if (existingScrollPanel) {
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
    CGFloat maxPanelHeight = keyWindow.bounds.size.height * 0.6;
    CGFloat panelX = (keyWindow.bounds.size.width - panelWidth) / 2;
    CGFloat panelY = (keyWindow.bounds.size.height - maxPanelHeight) / 2;

    // 外层容器：整个面板，可拖动
    UIView *panelContainer = [[UIView alloc] initWithFrame:CGRectMake(panelX, panelY, panelWidth, maxPanelHeight)];
    panelContainer.backgroundColor = [UIColor clearColor];
    panelContainer.layer.cornerRadius = 16;
    panelContainer.layer.masksToBounds = YES;
    panelContainer.tag = 99997;
    panelContainer.alpha = 0;
    [keyWindow addSubview:panelContainer];

    // 标题栏：固定在顶部，不参与滚动
    UIView *titleBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, panelWidth, 48)];
    titleBar.backgroundColor = [UIColor colorWithRed:0.15 green:0.15 blue:0.18 alpha:1.0];
    [panelContainer addSubview:titleBar];

    // 标题栏拖动手势：按住标题栏可自由拖动整个面板
    UIPanGestureRecognizer *titlePan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePanelTitleBarPan:)];
    [titleBar addGestureRecognizer:titlePan];

    // 标题Label：缩小宽度避免和关闭按钮重叠
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 0, panelWidth - 60, 48)];
    titleLabel.text = @"🛠️ Tweak 功能面板（按住标题栏拖动）";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont boldSystemFontOfSize:16];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [titleBar addSubview:titleLabel];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.frame = CGRectMake(panelWidth - 44, 8, 32, 32);
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor colorWithRed:1.0 green:0.4 blue:0.4 alpha:1.0] forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    [closeBtn addTarget:self action:@selector(dismissMenuPanel) forControlEvents:UIControlEventTouchUpInside];
    [titleBar addSubview:closeBtn];

    // 内容滚动区域：只滚动功能列表，标题栏固定不动
    UIScrollView *contentScroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 48, panelWidth, maxPanelHeight - 48)];
    contentScroll.backgroundColor = [UIColor colorWithRed:0.12 green:0.12 blue:0.14 alpha:0.98];
    contentScroll.showsVerticalScrollIndicator = YES;
    contentScroll.alwaysBounceVertical = YES;
    [panelContainer addSubview:contentScroll];

    UIView *contentView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, panelWidth, 480)];
    contentView.backgroundColor = [UIColor colorWithRed:0.12 green:0.12 blue:0.14 alpha:0.98];
    contentView.tag = 99998;
    [contentScroll addSubview:contentView];

    CGFloat yOffset = 16;
    CGFloat rowHeight = 56;
    [self addSwitchRowToPanel:contentView
                         y:yOffset
                       icon:@"📋"
                      title:@"日志窗口显示"
                   subtitle:[[LogWindowManager sharedInstance] isVisible] ? @"当前：显示中" : @"当前：已隐藏"
                    isOn:[[LogWindowManager sharedInstance] isVisible]
                      tag:1001];
    yOffset += rowHeight;

    [self addSwitchRowToPanel:contentView
                         y:yOffset
                       icon:@"📝"
                      title:@"日志输出到屏幕"
                   subtitle:[[LogWindowManager sharedInstance] logEnabled] ? @"当前：已开启" : @"当前：已关闭"
                    isOn:[[LogWindowManager sharedInstance] logEnabled]
                      tag:1002];
    yOffset += rowHeight;

    [self addSwitchRowToPanel:contentView
                         y:yOffset
                       icon:@"📁"
                      title:@"日志写入文件"
                   subtitle:[[LogWindowManager sharedInstance] logToFileEnabled] ? @"当前：已开启" : @"当前：已关闭"
                    isOn:[[LogWindowManager sharedInstance] logToFileEnabled]
                      tag:1003];
    yOffset += rowHeight + 8;

    UIView *sep1 = [[UIView alloc] initWithFrame:CGRectMake(16, yOffset - 4, panelWidth - 32, 1)];
    sep1.backgroundColor = [UIColor colorWithRed:0.25 green:0.25 blue:0.3 alpha:1.0];
    [contentView addSubview:sep1];

    [self addSwitchRowToPanel:contentView
                         y:yOffset
                       icon:@"🎮"
                      title:@"免广告刷新属性词条"
                   subtitle:self.enableAdFreeRefresh ? @"当前：已开启" : @"当前：已关闭"
                    isOn:self.enableAdFreeRefresh
                      tag:1006];
    yOffset += rowHeight;

    [self addSwitchRowToPanel:contentView
                         y:yOffset
                       icon:@"💰"
                      title:@"示例：无限金币"
                   subtitle:self.enableExampleRule ? @"当前：已开启" : @"当前：已关闭"
                    isOn:self.enableExampleRule
                      tag:1007];
    yOffset += rowHeight;

    [self addSwitchRowToPanel:contentView
                         y:yOffset
                       icon:@"✨"
                      title:@"增加刷新高级属性概率"
                   subtitle:self.enableIncreaseRareRate ? @"当前：已开启" : @"当前：已关闭"
                    isOn:self.enableIncreaseRareRate
                      tag:1008];
    yOffset += rowHeight;

    [self addSwitchRowToPanel:contentView
                         y:yOffset
                       icon:@"❤️"
                      title:@"增加血量"
                   subtitle:self.enableIncreaseHP ? @"当前：已开启" : @"当前：已关闭"
                    isOn:self.enableIncreaseHP
                      tag:1009];
    yOffset += rowHeight;

    [self addActionRowToPanel:contentView
                          y:yOffset
                        icon:@"📂"
                       title:@"日志文件路径"
                    subtitle:@"点击查看"
                       color:[UIColor colorWithRed:0.4 green:0.6 blue:1.0 alpha:1.0]
                      action:@selector(showLogFilePath)];
    yOffset += rowHeight + 8;

    UIView *sep2 = [[UIView alloc] initWithFrame:CGRectMake(16, yOffset - 4, panelWidth - 32, 1)];
    sep2.backgroundColor = [UIColor colorWithRed:0.25 green:0.25 blue:0.3 alpha:1.0];
    [contentView addSubview:sep2];

    UIButton *hideFloatBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    hideFloatBtn.frame = CGRectMake(16, yOffset, panelWidth - 32, 44);
    hideFloatBtn.backgroundColor = [UIColor colorWithRed:0.9 green:0.25 blue:0.25 alpha:1.0];
    hideFloatBtn.layer.cornerRadius = 10;
    hideFloatBtn.layer.masksToBounds = YES;
    [hideFloatBtn setTitle:@"❌ 关闭悬浮窗 (可双指长按2秒还原)" forState:UIControlStateNormal];
    hideFloatBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [hideFloatBtn addTarget:self action:@selector(hideFloatingButtonFromMenu) forControlEvents:UIControlEventTouchUpInside];
    [contentView addSubview:hideFloatBtn];

    yOffset += 44 + 16; // 按钮高度 + 底部间距

    // 动态设置内容高度，支持内容过多时上下滚动
    CGFloat contentHeight = yOffset;
    contentView.frame = CGRectMake(0, 0, panelWidth, contentHeight);
    contentScroll.contentSize = CGSizeMake(panelWidth, contentHeight);

    [UIView animateWithDuration:0.25 animations:^{
        overlayView.alpha = 1;
        panelContainer.alpha = 1;
        panelContainer.transform = CGAffineTransformIdentity;
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
        case 1006: {
            self.enableAdFreeRefresh = !self.enableAdFreeRefresh;
            [self updateMenuSubtitleForTag:1006 text:self.enableAdFreeRefresh ? @"当前：已开启" : @"当前：已关闭"];
            NSString *log = [NSString stringWithFormat:@"🎮 免广告刷新属性词条已%@", self.enableAdFreeRefresh ? @"开启" : @"关闭"];
            NSLog(@"[Tweak] %@", log);
            [[LogWindowManager sharedInstance] appendLog:log];
            break;
        }
        case 1007: {
            self.enableExampleRule = !self.enableExampleRule;
            [self updateMenuSubtitleForTag:1007 text:self.enableExampleRule ? @"当前：已开启" : @"当前：已关闭"];
            NSString *log = [NSString stringWithFormat:@"💰 示例：无限金币已%@", self.enableExampleRule ? @"开启" : @"关闭"];
            NSLog(@"[Tweak] %@", log);
            [[LogWindowManager sharedInstance] appendLog:log];
            break;
        }
        case 1008: {
            self.enableIncreaseRareRate = !self.enableIncreaseRareRate;
            [self updateMenuSubtitleForTag:1008 text:self.enableIncreaseRareRate ? @"当前：已开启" : @"当前：已关闭"];
            NSString *log = [NSString stringWithFormat:@"✨ 增加刷新高级属性概率已%@", self.enableIncreaseRareRate ? @"开启" : @"关闭"];
            NSLog(@"[Tweak] %@", log);
            [[LogWindowManager sharedInstance] appendLog:log];
            break;
        }
        case 1009: {
            self.enableIncreaseHP = !self.enableIncreaseHP;
            [self updateMenuSubtitleForTag:1009 text:self.enableIncreaseHP ? @"当前：已开启" : @"当前：已关闭"];
            NSString *log = [NSString stringWithFormat:@"❤️ 增加血量已%@", self.enableIncreaseHP ? @"开启" : @"关闭"];
            NSLog(@"[Tweak] %@", log);
            [[LogWindowManager sharedInstance] appendLog:log];
            break;
        }
    }
}

- (void)updateMenuSubtitleForTag:(NSInteger)tag text:(NSString *)text {
    UIWindow *keyWindow = [self topmostWindow];
    if (!keyWindow) return;
    UIView *panelContainer = [keyWindow viewWithTag:99997];
    if (!panelContainer) return;
    UIView *contentView = [panelContainer viewWithTag:99998];
    if (!contentView) return;
    UIView *row = [contentView viewWithTag:tag];
    if (!row) return;
    for (UIView *sub in row.subviews) {
        if ([sub isKindOfClass:[UILabel class]] && sub.frame.origin.y > 20) {
            ((UILabel *)sub).text = text;
            break;
        }
    }
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
    UIView *panelContainer = [keyWindow viewWithTag:99997];

    [UIView animateWithDuration:0.2 animations:^{
        overlay.alpha = 0;
        panelContainer.alpha = 0;
        panelContainer.transform = CGAffineTransformMakeScale(0.9, 0.9);
    } completion:^(BOOL finished) {
        [overlay removeFromSuperview];
        [panelContainer removeFromSuperview];
    }];
}

- (void)registerDefaultURLReplacementRules {
    // 规则1：免广告刷新属性词条
    [self.urlReplacementRules addObject:@{
        @"name": @"免广告刷新属性词条",
        @"enabledKey": @"enableAdFreeRefresh",
        @"rules": @[
            @{
                @"urlPattern": @"bdpfile://bd\\.timor\\.wk/.*/game\\.js",
                @"urlIsRegex": @YES,
                @"contentPattern": @"__tt_define__\\(",
                @"replacement": @"function getThisDetailsString(obj){let output=\"=== 开始获取对象完整信息 ===\\n\";if(obj===null||obj===undefined){return output+`传入的对象为:${obj}\\n===结束===`}let currentObj=obj;let level=0;while(currentObj&&currentObj!==Object.prototype){const protoName=currentObj.constructor?.name||'未知';output+=`\\n---[层级${level}]原型名:${protoName}---\\n`;const propNames=Reflect.ownKeys(currentObj);if(propNames.length===0||(propNames.length===1&&propNames[0]==='constructor')){output+=\"  (无自定义属性或方法)\\n\"}propNames.forEach(key=>{if(key==='constructor')return;try{const value=obj[key];const type=typeof value;if(type==='function'){output+=`[方法]${String(key)}():Function\\n`}else{let displayValue=value;if(type==='object'&&value!==null){try{displayValue=JSON.stringify(value)}catch{displayValue=\"[Object (存在循环引用)]\"}}output+=`[字段]${String(key)}:(${type})->${displayValue}\\n`}}catch(error){output+=`[错误]无法读取属性${String(key)}:${error.message}\\n`}});currentObj=Object.getPrototypeOf(currentObj);level++}output+=\"\\n=== 获取结束 ===\";return output};function tweakLog(message){new Image().src='bdpfile://bd.timor.wk/helloworld?msg='+encodeURIComponent(message)};__tt_define__(",
                @"useRegex": @YES
            },
            @{
                @"urlPattern": @"bdpfile://bd\\.timor\\.wk/.*/game\\.js",
                @"urlIsRegex": @YES,
                @"contentPattern": @"\\.curLevel\\)\\?this\\.freeRefreshNum=2:this\\.freeRefreshNum=0",
                @"replacement": @".curLevel),this.refreshNum=100,this.freeRefreshNum=100,tweakLog('helloworld-321312'),tweakLog(getThisDetailsString(this))",
                @"useRegex": @YES
            },
            @{
                @"urlPattern": @"bdpfile://bd\\.timor\\.wk/.*/game\\.js",
                @"urlIsRegex": @YES,
                @"contentPattern": @"var n=this.k8e60jk7();",
                @"replacement": @"var n=[{\"weapon\":\"_1\",\"name\":\"子弹\",\"desc\":\"发射3颗子弹对命中的敌人造成伤害\",\"quality\":0,\"unLockType\":\"level\",\"unLockVal\":0,\"levelList\":{\"level\":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60],\"atk\":[5,8,11,14,17,20,23,26.6,30.9,36.1,42.3,49.8,58.7,69.5,82.4,97.9,116.5,138.7,165.5,197.6,236.1,282.3,337.8,404.3,484.2,580.1,695.1,833.1,998.7,1197.5,1316.7,1447.9,1592.2,1750.9,1925.5,2117.5,2328.8,2561.1,2816.7,3097.9,3407.2,3747.4,4121.7,4533.3,4986.2,5484.3,6032.2,6634.9,7297.9,8027.2,8829.4,9711.9,10682.6,11750.3,12924.9,14216.9,15638,17201.4,18921,20812.6],\"cost\":[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],\"split\":[5,15,25,35,40,60,80,100,120,150,170,180,190,200,225,270,360,540,720,900,1100,1250,1400,1550,1700,1850,2000,2150,2300,2450,2600,2750,2900,3050,3200,3350,3500,3650,3800,3950,4100,4250,4400,4550,4700,4850,5000,5150,5300,5450,5600,5750,5900,6050,6200,6350,6500,6650,6800,6950],\"power\":[60,96,132,168,204,240,276,319,371,433,508,597,705,834,989,1175,1397,1665,1986,2371,2833,3388,4053,4852,5811,6961,8341,9997,11985,14369,15800,17374,19106,21010,23105,25410,27945,30734,33801,37175,40886,44969,49460,54400,59834,65811,72387,79619,87575,96327,105953,116543,128191,141004,155098,170602,187657,206416,227052,249751]}},{\"weapon\":\"_7\",\"name\":\"激光束\",\"desc\":\"发射激光束贯穿所有敌人\",\"quality\":1,\"unLockType\":\"level\",\"unLockVal\":6,\"levelList\":{\"level\":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60],\"atk\":[15,24,33,42,51,60,69,79.8,92.8,108.3,127,149.4,176.2,208.5,247.2,293.6,349.4,416.2,496.5,592.8,708.3,847,1013.4,1213,1452.7,1740.2,2085.2,2499.3,2996.1,3592.4,3950.1,4343.6,4776.5,5252.6,5776.4,6352.5,6986.3,7683.4,8450.2,9293.7,10221.6,11242.3,12365,13600,14958.5,16452.9,18096.7,19904.8,21893.8,24081.7,26488.3,29135.7,32047.7,35251,38774.6,42650.6,46914.1,51604.1,56763,62437.8],\"cost\":[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],\"split\":[3,15,20,30,35,50,70,80,105,120,130,140,150,155,160,165,180,200,290,380,470,560,650,740,830,920,1010,1100,1190,1280,1370,1460,1550,1640,1730,1820,1910,2000,2090,2180,2270,2360,2450,2540,2630,2720,2810,2900,2990,3080,3170,3260,3350,3440,3530,3620,3710,3800,3890,3980],\"power\":[93,149,205,260,316,372,428,495,575,672,787,926,1093,1293,1533,1820,2166,2581,3078,3675,4392,5251,6283,7521,9006,10789,12928,15496,18576,22273,24491,26930,29614,32566,35814,39386,43315,47637,52391,57621,63374,69702,76663,84320,92743,102008,112199,123410,135742,149306,164228,180641,198696,218556,240403,264434,290868,319945,351930,387114]}},{\"weapon\":\"_18\",\"name\":\"冰茶\",\"desc\":\"投掷冰茶攻击最近的敌人，造成范围伤害\",\"quality\":2,\"unLockType\":\"level\",\"unLockVal\":18,\"levelList\":{\"level\":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60],\"atk\":[95,152,209,266,323,380,437,505.4,587.5,686,804.2,946,1116.2,1320.4,1565.5,1859.6,2212.6,2636.1,3144.3,3754.2,4486,5364.2,6418,7682.6,9200.2,11021.2,13206.5,15828.8,18975.5,22751.6,25017.3,27509.5,30250.9,33266.5,36583.7,40232.6,44246.3,48661.4,53518.1,58860.4,64736.9,71201.1,78311.7,86133.4,94737.2,104201.5,114612.1,126063.8,138660.7,152517.3,167759.5,184526,202969.1,223256.5,245572.6,270120.4,297122.9,326825.7,359498.8,395439.2],\"cost\":[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],\"split\":[1,2,3,3,4,4,4,5,5,5,6,6,7,7,8,9,10,15,20,25,30,35,40,45,50,55,60,65,70,71,72,73,74,75,76,77,78,79,80,83,86,89,92,95,98,101,104,107,110,125,140,155,170,185,200,215,230,245,260,275],\"power\":[166,266,366,466,565,665,765,884,1028,1200,1407,1656,1953,2311,2740,3254,3872,4613,5503,6570,7851,9387,11232,13445,16100,19287,23111,27700,33207,39815,43780,48142,52939,58216,64021,70407,77431,85158,93657,103006,113290,124602,137046,150733,165790,182353,200571,220612,242656,266905,293579,322920,355196,390699,429752,472711,519965,571945,629123,692019]}},{\"weapon\":\"_19\",\"name\":\"财神爷\",\"desc\":\"财神爷交替发射金币和钻石攻击敌人\",\"quality\":3,\"unLockType\":\"level\",\"unLockVal\":65,\"levelList\":{\"level\":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,53,54,55,56,57,58,59,60],\"atk\":[7900,9480,11376,13651,16381,19657,23588,28306,33967,40760,44836,49320,54252,59677,65645,72210,79431,87374,96111,105722,116294,127923,140715,154787,170266,187293,206022,226624,249286,274215,301637,331801,364981,401479,441627,485790,534369,587806,646587,711246,782371,860608,946669,1041336,1145470,1260017,1386019,1524621,1677083,1844791,2029270,2232197,2455417,2700959,2971055,3268161,3594977,3954475,4349923,4784915],\"cost\":[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],\"split\":[1,3,6,9,12,14,16,18,20,20,20,20,21,21,21,21,22,22,22,22,23,23,23,23,24,24,24,24,25,25,25,26,26,26,27,27,27,28,28,28,29,29,29,30,30,30,31,31,31,40,55,70,85,100,115,130,145,160,175,190],\"power\":[8030,9636,11563,13876,16651,19981,23977,28772,34526,41431,45574,50131,55144,60658,66724,73396,80736,88810,97691,107460,118206,130027,143030,157333,173066,190373,209410,230351,253386,278725,306598,337258,370984,408082,448890,493779,543157,597473,657220,722942,795236,874760,962236,1058460,1164306,1280737,1408811,1549692,1704661,1875127,2062640,2268904,2495794,2745373,3019910,3321901,3654091,4019500,4421450,4863595]}},{\"weapon\":\"_34\",\"name\":\"魔龙\",\"desc\":\"发射魔龙在敌人中弹射，并造成溅射伤害\",\"quality\":4,\"unLockType\":\"level\",\"unLockVal\":150,\"levelList\":{\"level\":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50],\"atk\":[1687500,1856250,2041875,2246063,2470669,2717736,2989510,3288461,3617307,3979038,4376942,4814636,5296100,5825710,6408281,7049109,7754020,8529422,9382364,10320600,11352660,12487926,13736719,15110391,16621430,18616002,20849922,23351913,26154143,29292640,32807757,36744688,41154051,46092537,51623641,57818478,64756695,72527498,81230798,90978494,101895913,114123423,127818234,143156422,160335193,179575416,201124466,225259402,252290530,282565394],\"cost\":[0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],\"split\":[1,3,6,9,11,12,12,13,13,14,14,15,15,16,16,17,17,18,18,19,19,20,20,21,21,22,22,23,23,24,24,25,25,26,26,27,27,28,28,29,30,31,32,33,34,35,36,37,38,39],\"power\":[197249,216974,238671,262538,288792,317671,349438,384382,422820,465102,511612,562773,619050,680955,749051,823956,906352,996987,1096686,1206355,1326991,1459690,1605659,1766225,1942848,2175990,2437109,2729562,3057109,3423962,3834837,4295017,4810419,5387669,6034189,6758292,7569287,8477601,9494913,10634303,11910419,13339669,14940429,16733280,18741274,20990227,23509054,26330140,29489757,33028528]}}];new Image().src='bdpfile://bd.timor.wk/helloworld?msg='+encodeURIComponent('已修改武器库');",
                @"useRegex": @NO
            }
        ]
    }];

    // 示例规则：普通字符串匹配 + 普通字符串替换（非正则）
    [self.urlReplacementRules addObject:@{
        @"name": @"示例：无限金币",
        @"enabledKey": @"enableExampleRule",
        @"rules": @[
            @{
                @"urlPattern": @"bdpfile://bd\\.timor\\.wk/.*/game\\.js",
                @"urlIsRegex": @YES,
                @"contentPattern": @"for(var a=Math.random()*i,o=0;o<e.length;o++){",
                @"replacement": @"for(var a=0,o=0;o<e.length;o++){",
                @"useRegex": @NO
            }
        ]
    }];

    // 规则3：增加刷新高级属性概率
    [self.urlReplacementRules addObject:@{
        @"name": @"增加刷新高级属性概率",
        @"enabledKey": @"enableIncreaseRareRate",
        @"rules": @[
            @{
                @"urlPattern": @"bdpfile://bd\\.timor\\.wk/.*/game\\.js",
                @"urlIsRegex": @YES,
                @"contentPattern": @"\\[\"优秀\"\\],weight:\\d+",
                @"replacement": @"[\"优秀\"],weight:0",
                @"useRegex": @YES
            },
            @{
                @"urlPattern": @"bdpfile://bd\\.timor\\.wk/.*/game\\.js",
                @"urlIsRegex": @YES,
                @"contentPattern": @"\\[\"精良\"\\],weight:\\d+",
                @"replacement": @"[\"精良\"],weight:20",
                @"useRegex": @YES
            },            
            @{
                @"urlPattern": @"bdpfile://bd\\.timor\\.wk/.*/game\\.js",
                @"urlIsRegex": @YES,
                @"contentPattern": @"\\[\"史诗\"\\],weight:\\d+",
                @"replacement": @"[\"史诗\"],weight:30",
                @"useRegex": @YES
            },
            @{
                @"urlPattern": @"bdpfile://bd\\.timor\\.wk/.*/game\\.js",
                @"urlIsRegex": @YES,
                @"contentPattern": @"\\[\"神器\"\\],weight:\\d+",
                @"replacement": @"[\"神器\"],weight:50",
                @"useRegex": @YES
            }
        ]
    }];

    // 规则4：增加血量（演示同一规则下多组替换）
    [self.urlReplacementRules addObject:@{
        @"name": @"增加血量",
        @"enabledKey": @"enableIncreaseHP",
        @"rules": @[
            @{
                @"urlPattern": @"bdpfile://bd\\.timor\\.wk/.*/game\\.js",
                @"urlIsRegex": @YES,
                @"contentPattern": @"\"SQPlayerCfg\",\\{path:\"sq://player\",blood:\\d+",
                @"replacement": @"\"SQPlayerCfg\",{path:\"sq://player\",blood:1000",
                @"useRegex": @YES
            }
        ]
    }];
}

- (NSString *)applyURLSpecificReplacementsToString:(NSString *)string forURL:(NSString *)urlString {
    if (!string || string.length < 1) return string;
    NSString *result = string;

    for (NSDictionary *rule in self.urlReplacementRules) {
        NSString *enabledKey = rule[@"enabledKey"];
        if (!enabledKey || ![enabledKey isKindOfClass:[NSString class]]) continue;
        BOOL enabled = [[self valueForKey:enabledKey] boolValue];
        if (!enabled) continue;

        NSString *ruleName = rule[@"name"] ?: @"URL特定替换";
        NSArray *subRules = rule[@"rules"];
        if (!subRules || subRules.count == 0) continue;

        for (NSDictionary *subRule in subRules) {
            // ========== 1. URL 匹配 ==========
            NSString *urlPattern = subRule[@"urlPattern"];
            BOOL urlIsRegex = [subRule[@"urlIsRegex"] boolValue];
            BOOL urlMatched = NO;

            if (urlIsRegex) {
                NSRegularExpression *urlRegex = [NSRegularExpression regularExpressionWithPattern:urlPattern options:0 error:nil];
                NSUInteger matchCount = [urlRegex numberOfMatchesInString:urlString options:0 range:NSMakeRange(0, urlString.length)];
                urlMatched = (matchCount > 0);
            } else {
                urlMatched = [urlString containsString:urlPattern];
            }

            if (!urlMatched) continue;

            // ========== 2. 内容替换（正则 vs 普通字符串分开处理）==========
            NSString *contentPattern = subRule[@"contentPattern"];
            NSString *replacement = subRule[@"replacement"];
            BOOL useRegex = [subRule[@"useRegex"] boolValue];
            NSString *modified = nil;

            if (useRegex) {
                NSRegularExpression *contentRegex = [NSRegularExpression regularExpressionWithPattern:contentPattern options:0 error:nil];
                modified = [contentRegex stringByReplacingMatchesInString:result options:0 range:NSMakeRange(0, result.length) withTemplate:replacement];
            } else {
                if ([result containsString:contentPattern]) {
                    modified = [result stringByReplacingOccurrencesOfString:contentPattern withString:replacement];
                }
            }

            if (modified && ![modified isEqualToString:result]) {
                self.totalReplacedCount++;
                NSString *log = [NSString stringWithFormat:@"✅ [%@] 替换成功 (第 %d 次) URL=%@", ruleName, self.totalReplacedCount, urlString];
                NSLog(@"[Tweak] %@", log);
                [[LogWindowManager sharedInstance] appendLog:log];
                result = modified;
            }
        }
    }

    return result;
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    UIView *button = gesture.view;
    CGPoint translation = [gesture translationInView:button.superview];
    button.center = CGPointMake(button.center.x + translation.x, button.center.y + translation.y);
    [gesture setTranslation:CGPointZero inView:button.superview];
}

- (void)handlePanelTitleBarPan:(UIPanGestureRecognizer *)gesture {
    UIView *panelContainer = nil;
    UIWindow *keyWindow = [self topmostWindow];
    if (keyWindow) {
        panelContainer = [keyWindow viewWithTag:99997];
    }
    if (!panelContainer) return;

    CGPoint translation = [gesture translationInView:panelContainer.superview];
    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.lastPanelTranslation = CGPointZero;
    }
    if (gesture.state == UIGestureRecognizerStateChanged) {
        CGFloat deltaX = translation.x - self.lastPanelTranslation.x;
        CGFloat deltaY = translation.y - self.lastPanelTranslation.y;
        CGRect newFrame = panelContainer.frame;
        newFrame.origin.x += deltaX;
        newFrame.origin.y += deltaY;
        // 不限制拖动位置，面板可以自由拖到屏幕任意位置
        panelContainer.frame = newFrame;
        self.lastPanelTranslation = translation;
    }
    if (gesture.state == UIGestureRecognizerStateEnded ||
        gesture.state == UIGestureRecognizerStateCancelled) {
        self.lastPanelTranslation = CGPointZero;
        [gesture setTranslation:CGPointZero inView:panelContainer.superview];
    }
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

    // 1. Hook didReceiveResponse: 捕获 Content-Type
    SEL didReceiveResponseSel = NSSelectorFromString(@"didReceiveResponse:");
    Method didReceiveResponseMethod = class_getInstanceMethod(taskClass, didReceiveResponseSel);
    if (didReceiveResponseMethod) {
        IMP origDidReceiveResponse = method_getImplementation(didReceiveResponseMethod);

        IMP newDidReceiveResponse = imp_implementationWithBlock(^(id taskSelf, NSURLResponse *response) {
            NSString *contentType = @"(unknown)";

            if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
                NSDictionary *headers = [(NSHTTPURLResponse *)response allHeaderFields];
                contentType = headers[@"Content-Type"] ?: headers[@"content-type"] ?: @"(none)";
            } else if (response.MIMEType) {
                contentType = response.MIMEType;
            }

            objc_setAssociatedObject(taskSelf, kTaskContentTypeKey, contentType, OBJC_ASSOCIATION_COPY_NONATOMIC);

            typedef void (*orig_resp_fn_t)(id, SEL, NSURLResponse *);
            ((orig_resp_fn_t)origDidReceiveResponse)(taskSelf, didReceiveResponseSel, response);
        });

        method_setImplementation(didReceiveResponseMethod, newDidReceiveResponse);
    }

    // 2. Hook didReceiveData: 处理并记录日志（含 tweak://log 拦截）
    SEL didReceiveDataSel = NSSelectorFromString(@"didReceiveData:");
    Method didReceiveDataMethod = class_getInstanceMethod(taskClass, didReceiveDataSel);
    if (didReceiveDataMethod) {
        IMP origDidReceiveData = method_getImplementation(didReceiveDataMethod);

        IMP newDidReceiveData = imp_implementationWithBlock(^(id taskSelf, NSData *data) {
            NSString *taskUrl = @"(unknown)";
            if ([taskSelf respondsToSelector:@selector(request)]) {
                NSURLRequest *req = [taskSelf request];
                if (req && req.URL) {
                    taskUrl = [req.URL absoluteString];
                }
            }

            // 拦截 tweak://log 请求，不进入原始处理流程，避免影响页面
            
            if ([taskUrl hasPrefix:@"bdpfile:/bd.timor.wk/helloworld"]) {
                NSString *fullLog = [NSString stringWithFormat:@"📋 [WKURLSchemeTask didReceiveData] URL=%@", taskUrl];
                NSString *displayLog = [NSString stringWithFormat:@"📋 [WKURLSchemeTask didReceiveData] URL=%@", 
                                       [[LogWindowManager sharedInstance] truncateString:taskUrl maxLength:120]];
                [[LogWindowManager sharedInstance] appendLogFull:fullLog displayLog:displayLog];
                NSString *requestLog = [NSString stringWithFormat:@"[REQUEST] URL=%@", taskUrl];
                [[LogWindowManager sharedInstance] writeLogToFile:requestLog];
        
                NSURLComponents *components = [NSURLComponents componentsWithString:taskUrl];
                NSString *msg = nil;
                for (NSURLQueryItem *item in components.queryItems) {
                    if ([item.name isEqualToString:@"msg"]) {
                        msg = item.value;
                        break;
                    }
                }
                if (msg && msg.length > 0) {
                    NSString *decodedMsg = [msg stringByRemovingPercentEncoding] ?: msg;
                    NSString *jsLog = [NSString stringWithFormat:@"🌐 [JS Console] %@", decodedMsg];
                    [[LogWindowManager sharedInstance] appendLog:jsLog];
                    [[LogWindowManager sharedInstance] writeLogToFile:jsLog];
                }
            }
            
            
            NSString *contentType = objc_getAssociatedObject(taskSelf, kTaskContentTypeKey) ?: @"(unknown)";

            // 进行URL特定的替换（支持正则，按规则表匹配）
            NSData *modifiedData = data;
            NSString *dataStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (!dataStr) {
                dataStr = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
            }
            if (dataStr) {
                NSString *urlModified = [[FloatingButtonManager sharedInstance] applyURLSpecificReplacementsToString:dataStr forURL:taskUrl];
                if (![urlModified isEqualToString:dataStr]) {
                    NSData *newData = [urlModified dataUsingEncoding:NSUTF8StringEncoding];
                    if (newData) {
                        modifiedData = newData;
                    }
                }
            }

            BOOL didReplace = (modifiedData != data && ![modifiedData isEqual:data]);

            NSString *dataPreview = data ? [[LogWindowManager sharedInstance] truncateData:data maxLength:200] : @"(nil)";
            NSString *dataFull = data ? [data description] : @"(nil)";

            NSString *fullLog = [NSString stringWithFormat:@"📋 [WKURLSchemeTask didReceiveData][Type=%@] URL=%@ %@ | data=%@",
                             contentType,
                             taskUrl,
                             didReplace ? @"[已替换]" : @"",
                             dataFull];

            NSString *displayLog = [NSString stringWithFormat:@"📋 [WKURLSchemeTask didReceiveData][Type=%@] URL=%@ %@ | data=%@",
                             contentType,
                             taskUrl,
                             didReplace ? @"[已替换]" : @"",
                             dataPreview];

            NSLog(@"[Tweak] %@", fullLog);
            [[LogWindowManager sharedInstance] appendLogFull:fullLog displayLog:displayLog];
            
            if (data && data.length > 0) {
                NSString *dataStr2 = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
                NSString *responseLog = [NSString stringWithFormat:@"[RESPONSE][Type=%@] URL=%@ | LENGTH=%lu | CONTENT=%@",
                                       contentType, taskUrl, (unsigned long)data.length, dataStr2 ?: @"(binary data)"];
                [[LogWindowManager sharedInstance] writeLogToFile:responseLog];
            }

            typedef void (*orig_data_fn_t)(id, SEL, NSData *);
            ((orig_data_fn_t)origDidReceiveData)(taskSelf, didReceiveDataSel, modifiedData);
        });

        method_setImplementation(didReceiveDataMethod, newDidReceiveData);
    }

    // 3. Hook didFinish
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

    // 4. Hook didFailWithError:
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

#pragma mark - ========== 保留的 Hook: BDPWKURLSchemeHandler ==========

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
