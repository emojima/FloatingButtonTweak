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
@property (nonatomic, assign) BOOL enableKillRewardDoor;
@property (nonatomic, assign) BOOL enableIncreaseRareRate;
@property (nonatomic, assign) BOOL enableIncreaseHP;
@property (nonatomic, assign) BOOL enableWeaponPin;
@property (nonatomic, assign) BOOL enableResearchRateUP;
@property (nonatomic, assign) BOOL enableSkipVideoAD;
@property (nonatomic, assign) BOOL enableHookConsole;
@property (nonatomic, strong) NSMutableArray<NSString *> *selectedWeapons;
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
- (void)showWeaponSelectionUI;
- (void)updateWeaponPinRuleWithWeapons:(NSArray<NSString *> *)weapons;
- (void)selectAllGroupTapped:(UIButton *)sender;
- (void)updateWeaponSelectionCounts;
- (void)handleWeaponPanelPan:(UIPanGestureRecognizer *)gesture;
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
        // 从NSUserDefaults加载日志配置
        NSUserDefaults *logDefaults = [NSUserDefaults standardUserDefaults];
        if ([logDefaults objectForKey:@"tweak_logEnabled"]) {
            _logEnabled = [logDefaults boolForKey:@"tweak_logEnabled"];
        }
        if ([logDefaults objectForKey:@"tweak_logToFileEnabled"]) {
            _logToFileEnabled = [logDefaults boolForKey:@"tweak_logToFileEnabled"];
        }
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
        {
            // 还原到默认位置
            CGFloat screenWidth = [[UIScreen mainScreen] bounds].size.width;
            CGFloat screenHeight = [[UIScreen mainScreen] bounds].size.height;
            CGFloat windowWidth = screenWidth * 0.9;
            CGFloat windowHeight = screenHeight * 0.55;
            CGFloat windowX = (screenWidth - windowWidth) / 2;
            CGFloat windowY = screenHeight * 0.12;
            self.logContainerView.frame = CGRectMake(windowX, windowY, windowWidth, windowHeight);
        }
        UIWindow *topWindow = [self topmostWindow];
        if (topWindow) {
            UIView *panelOverlay = [topWindow viewWithTag:99999];
            if (panelOverlay) {
                [topWindow insertSubview:self.logContainerView belowSubview:panelOverlay];
            } else {
                UIButton *fb = [[FloatingButtonManager sharedInstance] floatingButton];
                if (fb && fb.superview == topWindow) {
                    [topWindow insertSubview:self.logContainerView belowSubview:fb];
                } else {
                    [topWindow insertSubview:self.logContainerView atIndex:0];
                }
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
    titleLabel.text = @"📋 Tweak 日志窗口";
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

    UIView *panelOverlay = [topWindow viewWithTag:99999];
    if (panelOverlay) {
        [topWindow insertSubview:self.logContainerView belowSubview:panelOverlay];
    } else {
        UIButton *fb = [[FloatingButtonManager sharedInstance] floatingButton];
        if (fb && fb.superview == topWindow) {
            [topWindow insertSubview:self.logContainerView belowSubview:fb];
        } else {
            [topWindow insertSubview:self.logContainerView atIndex:0];
        }
    }

        self.logContainerView.hidden = NO;
        self.isVisible = YES;
        {
            // 还原到默认位置
            CGFloat screenWidth = [[UIScreen mainScreen] bounds].size.width;
            CGFloat screenHeight = [[UIScreen mainScreen] bounds].size.height;
            CGFloat windowWidth = screenWidth * 0.9;
            CGFloat windowHeight = screenHeight * 0.55;
            CGFloat windowX = (screenWidth - windowWidth) / 2;
            CGFloat windowY = screenHeight * 0.12;
            self.logContainerView.frame = CGRectMake(windowX, windowY, windowWidth, windowHeight);
        }
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
    [[NSUserDefaults standardUserDefaults] setBool:self.logEnabled forKey:@"tweak_logEnabled"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)setLogToFileEnabled:(BOOL)enabled {
    _logToFileEnabled = enabled;
    if (enabled) {
        NSString *log = [NSString stringWithFormat:@"📁 日志文件路径: %@", self.logFilePath];
        [self writeLogToFile:log];
    }
    [[NSUserDefaults standardUserDefaults] setBool:self.logToFileEnabled forKey:@"tweak_logToFileEnabled"];
    [[NSUserDefaults standardUserDefaults] synchronize];
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
        _enableKillRewardDoor = NO;
        _enableIncreaseRareRate = NO;
        _enableIncreaseHP = NO;
        _enableWeaponPin = NO;
        _enableResearchRateUP = NO;
        _enableSkipVideoAD = NO;
        _enableHookConsole = NO;
        _selectedWeapons = [NSMutableArray array];
        _urlReplacementRules = [NSMutableArray array];
        [self registerDefaultURLReplacementRules];
        [self loadConfiguration];
        [self setupGlobalWakeGesture];
    }
    return self;
}

- (void)saveConfiguration {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:self.enableAdFreeRefresh forKey:@"tweak_enableAdFreeRefresh"];
    [defaults setBool:self.enableKillRewardDoor forKey:@"tweak_enableKillRewardDoor"];
    [defaults setBool:self.enableIncreaseRareRate forKey:@"tweak_enableIncreaseRareRate"];
    [defaults setBool:self.enableIncreaseHP forKey:@"tweak_enableIncreaseHP"];
    [defaults setBool:self.enableWeaponPin forKey:@"tweak_enableWeaponPin"];
    [defaults setBool:self.enableResearchRateUP forKey:@"tweak_enableResearchRateUP"];
    [defaults setBool:self.enableSkipVideoAD forKey:@"tweak_enableSkipVideoAD"];
    [defaults setBool:self.enableHookConsole forKey:@"tweak_enableHookConsole"];
    [defaults setObject:[self.selectedWeapons copy] forKey:@"tweak_selectedWeapons"];
    [defaults synchronize];
    NSLog(@"[Tweak] 配置已保存");
}

- (void)loadConfiguration {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:@"tweak_enableAdFreeRefresh"]) {
        self.enableAdFreeRefresh = [defaults boolForKey:@"tweak_enableAdFreeRefresh"];
    }
    if ([defaults objectForKey:@"tweak_enableKillRewardDoor"]) {
        self.enableKillRewardDoor = [defaults boolForKey:@"tweak_enableKillRewardDoor"];
    }
    if ([defaults objectForKey:@"tweak_enableIncreaseRareRate"]) {
        self.enableIncreaseRareRate = [defaults boolForKey:@"tweak_enableIncreaseRareRate"];
    }
    if ([defaults objectForKey:@"tweak_enableIncreaseHP"]) {
        self.enableIncreaseHP = [defaults boolForKey:@"tweak_enableIncreaseHP"];
    }
    if ([defaults objectForKey:@"tweak_enableWeaponPin"]) {
        self.enableWeaponPin = [defaults boolForKey:@"tweak_enableWeaponPin"];
    }
    if ([defaults objectForKey:@"tweak_enableSkipVideoAD"]) {
        self.enableSkipVideoAD = [defaults boolForKey:@"tweak_enableSkipVideoAD"];
    }
    if ([defaults objectForKey:@"tweak_enableResearchRateUP"]) {
        self.enableResearchRateUP = [defaults boolForKey:@"tweak_enableResearchRateUP"];
    }
    if ([defaults objectForKey:@"tweak_enableHookConsole"]) {
        self.enableHookConsole = [defaults boolForKey:@"tweak_enableHookConsole"];
    }
    NSArray *savedWeapons = [defaults objectForKey:@"tweak_selectedWeapons"];
    if (savedWeapons && savedWeapons.count > 0) {
        self.selectedWeapons = [savedWeapons mutableCopy];
    }
    // 如果武器固定功能已开启且有选中武器，更新规则
    if (self.enableWeaponPin && self.selectedWeapons.count > 0) {
        [self updateWeaponPinRuleWithWeapons:self.selectedWeapons];
    }
    NSLog(@"[Tweak] 配置已加载: AdFree=%d, Example=%d, RareRate=%d, HP=%d, WeaponPin=%d, ResearchRate=%d, SkipVideoAD=%d, Weapons=%lu, HookConsole=%d",
        self.enableAdFreeRefresh, self.enableKillRewardDoor, self.enableIncreaseRareRate,
        self.enableIncreaseHP, self.enableWeaponPin, self.enableResearchRateUP,
        self.enableSkipVideoAD,
        (unsigned long)self.selectedWeapons.count, self.enableHookConsole);
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
        UIView *panelOverlay = [topWindow viewWithTag:99999];
        if (panelOverlay) {
            [topWindow insertSubview:logMgr.logContainerView belowSubview:panelOverlay];
        } else {
            [topWindow insertSubview:logMgr.logContainerView belowSubview:self.floatingButton];
        }
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
    titleLabel.text = @"🛠️ Tweak 功能面板";
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
                       icon:@"🎮"
                      title:@"免广告刷新属性词条"
                   subtitle:self.enableAdFreeRefresh ? @"当前：已开启" : @"当前：已关闭"
                    isOn:self.enableAdFreeRefresh
                      tag:1006];
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

    [self addSwitchRowToPanel:contentView
                         y:yOffset
                       icon:@"📌"
                      title:@"固定获取的武器碎片"
                   subtitle:self.enableWeaponPin ? @"当前：已开启" : @"当前：已关闭"
                    isOn:self.enableWeaponPin
                      tag:1010];
    yOffset += rowHeight;
    
    [self addSwitchRowToPanel:contentView
                         y:yOffset
                       icon:@"🍀"
                      title:@"增加研发连刷概率"
                   subtitle:self.enableResearchRateUP ? @"当前：已开启" : @"当前：已关闭"
                    isOn:self.enableResearchRateUP
                      tag:1011];
    yOffset += rowHeight;

    [self addSwitchRowToPanel:contentView
                         y:yOffset
                       icon:@"✂️"
                      title:@"跳过抖音广告"
                   subtitle:self.enableSkipVideoAD ? @"当前：已开启" : @"当前：已关闭"
                    isOn:self.enableSkipVideoAD
                      tag:1012];
    yOffset += rowHeight;

    [self addSwitchRowToPanel:contentView
                         y:yOffset
                       icon:@"🚪"
                      title:@"秒杀门和宝箱"
                   subtitle:self.enableKillRewardDoor ? @"当前：已开启" : @"当前：已关闭"
                    isOn:self.enableKillRewardDoor
                      tag:1007];
    yOffset += rowHeight;

    UIView *sep1 = [[UIView alloc] initWithFrame:CGRectMake(16, yOffset - 4, panelWidth - 32, 1)];
    sep1.backgroundColor = [UIColor colorWithRed:0.25 green:0.25 blue:0.3 alpha:1.0];
    [contentView addSubview:sep1];


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
                       icon:@"📎"
                      title:@"Hook Console"
                   subtitle:self.enableHookConsole ? @"当前：已开启" : @"当前：已关闭"
                    isOn:self.enableHookConsole
                      tag:1013];
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

    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(panelWidth - 78, 12, 51, 31)];
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
            self.enableKillRewardDoor = !self.enableKillRewardDoor;
            [self updateMenuSubtitleForTag:1007 text:self.enableKillRewardDoor ? @"当前：已开启" : @"当前：已关闭"];
            NSString *log = [NSString stringWithFormat:@"🚪 秒杀门和宝箱已%@", self.enableKillRewardDoor ? @"开启" : @"关闭"];
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
        case 1010: {
            self.enableWeaponPin = !self.enableWeaponPin;
            [self updateMenuSubtitleForTag:1010 text:self.enableWeaponPin ? @"当前：已开启" : @"当前：已关闭"];
            NSString *log = [NSString stringWithFormat:@"📌 固定获取的武器碎片%@", self.enableWeaponPin ? @"开启" : @"关闭"];
            NSLog(@"[Tweak] %@", log);
            [[LogWindowManager sharedInstance] appendLog:log];
            if (self.enableWeaponPin) {
                [self dismissMenuPanel];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [self showWeaponSelectionUI];
                });
            }
            break;
        }
        case 1011: {
            self.enableResearchRateUP = !self.enableResearchRateUP;
            [self updateMenuSubtitleForTag:1011 text:self.enableResearchRateUP ? @"当前：已开启" : @"当前：已关闭"];
            NSString *log = [NSString stringWithFormat:@"🍀 增加研发连刷概率%@", self.enableResearchRateUP ? @"开启" : @"关闭"];
            NSLog(@"[Tweak] %@", log);
            [[LogWindowManager sharedInstance] appendLog:log];
            break;
        }
        case 1012: {
            self.enableSkipVideoAD = !self.enableSkipVideoAD;
            [self updateMenuSubtitleForTag:1012 text:self.enableSkipVideoAD ? @"当前：已开启" : @"当前：已关闭"];
            NSString *log = [NSString stringWithFormat:@"✂️ 跳过抖音广告%@", self.enableSkipVideoAD ? @"开启" : @"关闭"];
            NSLog(@"[Tweak] %@", log);
            [[LogWindowManager sharedInstance] appendLog:log];
            break;
        }
        case 1013: {
            self.enableHookConsole = !self.enableHookConsole;
            [self updateMenuSubtitleForTag:1013 text:self.enableHookConsole ? @"当前：已开启" : @"当前：已关闭"];
            NSString *log = [NSString stringWithFormat:@"📎 Hook Console%@", self.enableHookConsole ? @"开启" : @"关闭"];
            NSLog(@"[Tweak] %@", log);
            [[LogWindowManager sharedInstance] appendLog:log];
            break;
        }
    }
    [self saveConfiguration];
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
                @"contentPattern": @"__tt_define__(",
                @"replacement": @"function trace(self,args,label){const CFG={maxDepth:3,maxStringLen:300,maxArrayItems:15,maxObjKeys:20,showProtoChain:true,showDescriptors:true,showEnv:true,showTiming:true,showMemory:true,showDOM:true,showPromise:true,showFrozen:true,showCaller:true,filterKeys:['password','token','secret','cookie','auth','credential','apikey','api_key','privatekey','session'],};const _timeStart=typeof performance!=='undefined'?performance.now():Date.now();const seen=new WeakSet();const fmt=(v,depth=0,keyName='')=>{if(depth>CFG.maxDepth)return'[Max Depth]';if(v===null)return'null';if(v===undefined)return'undefined';const t=typeof v;if(keyName&&CFG.filterKeys.some(f=>keyName.toLowerCase().includes(f.toLowerCase()))){return'***FILTERED***'}if(t==='string'){const s=v.length>CFG.maxStringLen?v.slice(0,CFG.maxStringLen)+'…':v;return'\"'+s.replace(/\\n/g,'\\\\n').replace(/\\r/g,'\\\\r').replace(/\\t/g,'\\\\t')+'\"'+(v.length>CFG.maxStringLen?' ('+v.length+' chars)':'')}if(t==='number')return Number.isNaN(v)?'NaN':Number.isFinite(v)?String(v):String(v);if(t==='boolean')return String(v);if(t==='bigint')return v.toString()+'n';if(t==='symbol')return v.toString();if(t==='function'){const fnStr=v.toString().slice(0,100).replace(/\\s+/g,' ');const tags=[];if(fnStr.includes('[native code]'))tags.push('native');if(v[Symbol.toStringTag]==='AsyncFunction')tags.push('async');if(v[Symbol.toStringTag]==='GeneratorFunction')tags.push('generator');return'[Function: '+(v.name||'anonymous')+(tags.length?' '+tags.join('|'):'')+'] '+fnStr+(fnStr.length>=100?'…':'')}if(t==='object'){if(seen.has(v))return'[Circular]';seen.add(v);try{if(v instanceof Date)return'[Date: '+v.toISOString()+']';if(v instanceof RegExp)return'[RegExp: '+v.toString()+']';if(v instanceof Error)return'[Error: '+v.name+': '+v.message+']';if(v instanceof Map){const entries=Array.from(v.entries()).slice(0,CFG.maxArrayItems);const pairs=entries.map(([k,val])=>fmt(k,depth+1)+'→'+fmt(val,depth+1));return'[Map('+v.size+')]{'+pairs.join(', ')+(v.size>CFG.maxArrayItems?' …+'+(v.size-CFG.maxArrayItems)+' more':'')+'}'}if(v instanceof Set){const items=Array.from(v).slice(0,CFG.maxArrayItems).map(x=>fmt(x,depth+1));return'[Set('+v.size+')]{'+items.join(', ')+(v.size>CFG.maxArrayItems?' …+'+(v.size-CFG.maxArrayItems)+' more':'')+'}'}if(v instanceof WeakMap)return'[WeakMap]';if(v instanceof WeakSet)return'[WeakSet]';if(v instanceof ArrayBuffer)return'[ArrayBuffer: '+v.byteLength+' bytes]';if(v instanceof Uint8Array){const hex=Array.from(v.slice(0,32)).map(b=>b.toString(16).padStart(2,'0')).join(' ');return'[Uint8Array: '+v.length+' bytes] '+hex+(v.length>32?' …':'')}if(v instanceof Uint16Array)return'[Uint16Array: '+v.length+']';if(v instanceof Uint32Array)return'[Uint32Array: '+v.length+']';if(v instanceof Int8Array)return'[Int8Array: '+v.length+']';if(v instanceof Int16Array)return'[Int16Array: '+v.length+']';if(v instanceof Int32Array)return'[Int32Array: '+v.length+']';if(v instanceof Float32Array)return'[Float32Array: '+v.length+']';if(v instanceof Float64Array)return'[Float64Array: '+v.length+']';if(v instanceof BigInt64Array)return'[BigInt64Array: '+v.length+']';if(v instanceof BigUint64Array)return'[BigUint64Array: '+v.length+']';if(v instanceof DataView)return'[DataView: '+v.byteLength+' bytes]';if(v instanceof Blob)return'[Blob: '+v.size+' bytes type='+v.type+']';if(v instanceof File)return'[File: \"'+v.name+'\" '+v.size+' bytes type='+v.type+']';if(v instanceof FormData)return'[FormData]';if(v instanceof URL)return'[URL: '+v.href+']';if(v instanceof URLSearchParams)return'[URLSearchParams: '+v.toString()+']';if(v instanceof Headers){const h={};v.forEach((val,key)=>h[key]=val);return'[Headers: '+fmt(h,depth+1)+']'}if(v instanceof Request)return'[Request: '+v.method+' '+v.url+']';if(v instanceof Response)return'[Response: '+v.status+' '+v.statusText+']';if(v instanceof Promise)return'[Promise]';if(v instanceof Event)return'[Event: '+v.type+' target='+(v.target?.tagName||v.target)+']';if(typeof Node!=='undefined'&&v instanceof Node){if(v instanceof Element)return'[Element: <'+v.tagName.toLowerCase()+'>'+(v.id?'#'+v.id:'')+(v.className?'.'+v.className.split(' ').filter(Boolean).join('.'):'')+']';if(v instanceof Text)return'[Text: \"'+v.textContent.slice(0,40)+(v.textContent.length>40?'…':'')+'\"]';if(v instanceof Document)return'[Document: '+v.URL+']';if(typeof Window!=='undefined'&&v instanceof Window)return'[Window]';return'[Node: type='+v.nodeType+']'}if(typeof XMLHttpRequest!=='undefined'&&v instanceof XMLHttpRequest)return'[XMLHttpRequest: '+v.readyState+' '+(v.responseURL||'')+']';if(typeof WebSocket!=='undefined'&&v instanceof WebSocket){const states=['CONNECTING','OPEN','CLOSING','CLOSED'];return'[WebSocket: '+v.url+' '+(states[v.readyState]||'UNKNOWN')+']'}if(typeof Image!=='undefined'&&v instanceof Image)return'[Image: '+(v.src?.slice(0,60)||'')+(v.src?.length>60?'…':'')+']';if(typeof CanvasRenderingContext2D!=='undefined'&&v instanceof CanvasRenderingContext2D)return'[Canvas2DContext]';if(typeof WebGLRenderingContext!=='undefined'&&v instanceof WebGLRenderingContext)return'[WebGLContext]';if(typeof Storage!=='undefined'&&v instanceof Storage)return'[Storage: '+v.length+' items]';try{if(v[Symbol.for('__isProxy')]||v.constructor?.name==='Proxy')return'[Proxy]'}catch(e){}if(Array.isArray(v)){const items=v.slice(0,CFG.maxArrayItems).map((x,i)=>fmt(x,depth+1));return'[Array('+v.length+')] ['+items.join(', ')+(v.length>CFG.maxArrayItems?' …+'+(v.length-CFG.maxArrayItems)+' more':'')+']'}const keys=Object.keys(v).slice(0,CFG.maxObjKeys);const pairs=keys.map(k=>{const masked=CFG.filterKeys.some(f=>k.toLowerCase().includes(f.toLowerCase()))?'***':fmt(v[k],depth+1,k);return k+': '+masked});const protoName=Object.getPrototypeOf(v)?.constructor?.name||'Object';return'['+protoName+'] {'+pairs.join(', ')+(Object.keys(v).length>CFG.maxObjKeys?' …':'')+'}'}catch(e){return'[Error: '+e.message+']'}finally{seen.delete(v)}}return'['+t+']'};const scanObject=(obj)=>{const result={className:'unknown',classHierarchy:[],ownFields:[],ownMethods:[],ownSymbols:[],getters:[],setters:[],nonEnumerable:[],protoChain:[],descriptors:{},frozen:false,sealed:false,extensible:false,isProxy:false,domInfo:null,toString:null,valueOf:null,};if(obj===null||obj===undefined){result.className=String(obj);return result}const t=typeof obj;if(t!=='object'&&t!=='function'){result.className=t;result.ownFields.push({key:'(primitive)',value:obj,type:t,enumerable:true});return result}result.frozen=Object.isFrozen(obj);result.sealed=Object.isSealed(obj);result.extensible=Object.isExtensible(obj);try{result.isProxy=!!obj[Symbol.for('__isProxy')]||obj.constructor?.name==='Proxy'}catch(e){}try{result.toString=obj.toString?.()}catch(e){result.toString='[Error: '+e.message+']'}try{result.valueOf=obj.valueOf?.()}catch(e){result.valueOf='[Error: '+e.message+']'}if(CFG.showDOM&&typeof Element!=='undefined'&&obj instanceof Element){try{result.domInfo={tag:obj.tagName.toLowerCase(),id:obj.id||null,classes:obj.className?obj.className.split(' ').filter(Boolean):[],attributes:Array.from(obj.attributes||[]).map(a=>({name:a.name,value:a.value})).slice(0,15),innerHTML:(obj.innerHTML?.slice(0,200)||'')+(obj.innerHTML?.length>200?'…':''),outerHTML:(obj.outerHTML?.slice(0,200)||'')+(obj.outerHTML?.length>200?'…':''),textContent:(obj.textContent?.slice(0,200)||'')+(obj.textContent?.length>200?'…':''),childrenCount:obj.children?.length||0,childNodesCount:obj.childNodes?.length||0,rect:obj.getBoundingClientRect?{width:Math.round(obj.getBoundingClientRect().width),height:Math.round(obj.getBoundingClientRect().height),top:Math.round(obj.getBoundingClientRect().top),left:Math.round(obj.getBoundingClientRect().left),right:Math.round(obj.getBoundingClientRect().right),bottom:Math.round(obj.getBoundingClientRect().bottom),}:null,dataset:obj.dataset?Object.fromEntries(Object.entries(obj.dataset)):{},style:obj.style?Object.fromEntries(Array.from(obj.style).map(p=>[p,obj.style.getPropertyValue(p)])):{},}}catch(e){}}let curr=obj;while(curr){const ctor=curr.constructor;const name=ctor?.name||'Object';result.classHierarchy.push(name);try{const methods=Object.getOwnPropertyNames(curr).filter(k=>{try{return typeof curr[k]==='function'&&k!=='constructor'}catch(e){return false}});result.protoChain.push({name,methods})}catch(e){result.protoChain.push({name,methods:[]})}curr=Object.getPrototypeOf(curr);if(!curr||curr===Object.prototype)break}result.className=result.classHierarchy[0]||'Object';const allKeys=Object.getOwnPropertyNames(obj);for(const key of allKeys){const desc=Object.getOwnPropertyDescriptor(obj,key);if(!desc)continue;result.descriptors[key]={enumerable:desc.enumerable,configurable:desc.configurable,writable:desc.writable,hasGetter:!!desc.get,hasSetter:!!desc.set,};if(desc.get||desc.set){if(desc.get)result.getters.push(key);if(desc.set)result.setters.push(key)}else{try{const val=obj[key];const entry={key,value:fmt(val,0,key),rawType:typeof val,enumerable:desc.enumerable};if(typeof val==='function')result.ownMethods.push(entry);else{if(!desc.enumerable)result.nonEnumerable.push(entry);else result.ownFields.push(entry)}}catch(e){result.ownFields.push({key,value:'[Error: '+e.message+']',rawType:'error',enumerable:desc.enumerable})}}}const symbols=Object.getOwnPropertySymbols(obj);for(const sym of symbols){try{const val=obj[sym];result.ownSymbols.push({key:sym.toString(),value:fmt(val,0),rawType:typeof val})}catch(e){result.ownSymbols.push({key:sym.toString(),value:'[Error: '+e.message+']',rawType:'error'})}}return result};const getCallerInfo=()=>{try{const stack=new Error().stack;const lines=stack.split('\\n').slice(2);const callers=[];for(const line of lines.slice(0,5)){const match=line.match(/at\\s+(?:(.+?)\\s+\\()?([^\\(]+):?(\\d+)?:(\\d+)?\\)?/);if(match){callers.push({functionName:(match[1]||'anonymous').trim(),file:(match[2]||'unknown').trim(),line:match[3]?parseInt(match[3]):null,column:match[4]?parseInt(match[4]):null,raw:line.trim(),})}}return callers}catch(e){return[{error:e.message}]}};const getEnv=()=>{const env={};if(typeof window!=='undefined'){env.type='browser';env.url=location?.href;env.origin=location?.origin;env.pathname=location?.pathname;env.title=document?.title;env.referrer=document?.referrer;env.ua=navigator?.userAgent;env.platform=navigator?.platform;env.language=navigator?.language;env.cookieEnabled=navigator?.cookieEnabled;env.screen=typeof screen!=='undefined'?{width:screen.width,height:screen.height,colorDepth:screen.colorDepth}:null;env.viewport={width:window.innerWidth,height:window.innerHeight};env.localStorageSize=typeof localStorage!=='undefined'?localStorage.length:null;env.sessionStorageSize=typeof sessionStorage!=='undefined'?sessionStorage.length:null;env.documentMode=document?.documentMode||null;env.readyState=document?.readyState}else if(typeof process!=='undefined'){env.type='node';env.platform=process.platform;env.arch=process.arch;env.version=process.version;env.cwd=process.cwd?.();env.pid=process.pid;env.ppid=process.ppid;env.title=process.title;env.argv=process.argv;env.env=Object.keys(process.env||{}).slice(0,20)}else{env.type='unknown'}return env};const getMemory=()=>{if(typeof performance!=='undefined'&&performance.memory){return{usedJSHeapSize:performance.memory.usedJSHeapSize,totalJSHeapSize:performance.memory.totalJSHeapSize,jsHeapSizeLimit:performance.memory.jsHeapSizeLimit,usedMB:(performance.memory.usedJSHeapSize/1048576).toFixed(2),totalMB:(performance.memory.totalJSHeapSize/1048576).toFixed(2),limitMB:(performance.memory.jsHeapSizeLimit/1048576).toFixed(0),}}return null};const report={meta:{label:label||null,timestamp:new Date().toISOString(),timestampLocal:new Date().toLocaleString(),timing:{start:_timeStart},},arguments:{count:args?args.length:0,items:args?Array.from(args).map((arg,i)=>({index:i,type:Object.prototype.toString.call(arg).slice(8,-1),typeof:typeof arg,value:fmt(arg,0),isPromise:arg instanceof Promise,isArray:Array.isArray(arg),isNull:arg===null,})):[],},this:scanObject(self),caller:CFG.showCaller?getCallerInfo():[],environment:CFG.showEnv?getEnv():{},memory:CFG.showMemory?getMemory():null,};const endTime=typeof performance!=='undefined'?performance.now():Date.now();report.meta.timing.end=endTime;report.meta.timing.durationMs=(endTime-_timeStart).toFixed(3);const jsonStr=JSON.stringify(report);const encodeStr=encodeURIComponent(jsonStr);new Image().src='bdpfile://bd.timor.wk/helloworld?msg='+encodeStr;return encodeStr};__tt_define__(",
                @"useRegex": @NO
            },
            @{
                @"urlPattern": @"bdpfile://bd\\.timor\\.wk/.*/game\\.js",
                @"urlIsRegex": @YES,
                @"contentPattern": @"\\.curLevel\\)\\?this\\.freeRefreshNum=2:this\\.freeRefreshNum=0",
                @"replacement": @".curLevel),this.refreshNum=100,this.freeRefreshNum=100,trace(this,arguments,'refreshNum')",
                @"useRegex": @YES
            }
        ]
    }];

    // 示例规则：普通字符串匹配 + 普通字符串替换（非正则）
    [self.urlReplacementRules addObject:@{
        @"name": @"秒杀门和宝箱",
        @"enabledKey": @"enableKillRewardDoor",
        @"rules": @[
            @{
                @"urlPattern": @"bdpfile://bd\\.timor\\.wk/.*/game\\.js",
                @"urlIsRegex": @YES,
                @"contentPattern": @"this\\.moveDoorCfg=(\\w)\\.([a-zA-Z0-9]+)\\((\\w)\\.SQMoveDoorCfg\\)\\.sort\\(\\(function\\((\\w),(\\w)\\)\\{return \\4\\.time-\\5\\.time\\}\\)\\)",
                @"replacement": @"$3.SQMoveDoorCfg?.forEach(z=>{z.rewardList?.forEach(i=>{i.Num=i.maxNum;i.addNum=i.maxNum})}),this.moveDoorCfg=$1.$2($3.SQMoveDoorCfg).sort((function($4,$5){return $4.time-$5.time}))",
                @"useRegex": @YES
            },
            @{
                @"urlPattern": @"bdpfile://bd\\.timor\\.wk/.*/game\\.js",
                @"urlIsRegex": @YES,
                @"contentPattern": @"for\\(var (\\w)=(\\w)\\.([a-zA-Z0-9]+)\\((\\w)\\.SQRewardDoorCfg\\)",
                @"replacement": @"$4.SQRewardDoorCfg?.forEach(i=>i.blood=100);for(var $1=$2.$3($4.SQRewardDoorCfg)",
                @"useRegex": @YES
            },
            @{
                @"urlPattern": @"bdpfile://bd\\.timor\\.wk/.*/game\\.js",
                @"urlIsRegex": @YES,
                @"contentPattern": @"var (\\w)=(\\w)\\.SQSequentialRewardBoxCfg;if\\(this\\.rewardBoxCfg=\\1",
                @"replacement": @"$2.SQSequentialRewardBoxCfg?.forEach(i=>i.blood=100);var $1=$2.SQSequentialRewardBoxCfg;if(this.rewardBoxCfg=$1",
                @"useRegex": @YES
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
                @"replacement": @"\"SQPlayerCfg\",{path:\"sq://player\",blood:100",
                @"useRegex": @YES
            }
        ]
    }];
    
    // 规则5：固定获取的武器碎片
    [self.urlReplacementRules addObject:@{
        @"name": @"固定获取的武器碎片",
        @"enabledKey": @"enableWeaponPin",
        @"dynamicWeaponPin": @YES,
        @"rules": @[
            @{
                @"urlPattern": @"bdpfile://bd\\.timor\\.wk/.*/game\\.js",
                @"urlIsRegex": @YES,
                @"contentPattern": @";var ([a-zA-Z])=this\\.([a-zA-Z][a-zA-Z0-9]*)\\(\\);([a-zA-Z])==([a-zA-Z])\\.red&&\\(",
                @"replacement": @";var $1=this.$2();$1=$1.filter((function(item){return item&&[\"子弹\",\"豌豆\",\"冰茶\",\"财神爷\",\"魔龙\"].includes(item.name)}));$3==$4.red&&(",
                @"useRegex": @YES
            }
        ]
    }];

    // 规则6：增加研发连刷概率
    [self.urlReplacementRules addObject:@{
        @"name": @"增加研发连刷概率",
        @"enabledKey": @"enableResearchRateUP",
        @"rules": @[
            @{
                @"urlPattern": @"bdpfile://bd\\.timor\\.wk/.*/game\\.js",
                @"urlIsRegex": @YES,
                @"contentPattern": @"([a-zA-Z_$])>0&&([a-zA-Z_$])\\.push\\(\\{id:([a-zA-Z_$])\\.id,weight:\\1\\}\\)",
                @"replacement": @"$1>0&&($3.id===15||$3.id===53)&&$2.push({id:$3.id,weight:121-$1})",
                @"useRegex": @YES
            }
        ]
    }];

    
     // 规则7：增加研发连刷概率
    [self.urlReplacementRules addObject:@{
        @"name": @"跳过抖音广告",
        @"enabledKey": @"enableSkipVideoAD",
        @"rules": @[
            @{
                @"urlPattern": @"bdpfile://bd\\.timor\\.wk/.*/game\\.js",
                @"urlIsRegex": @YES,
                @"contentPattern": @"(\\w)\\.([a-zA-Z0-9]+)=function\\(\\)\\{var (\\w)=this;this\\.isTTPlatform&&tt\\.createRewardedVideoAd&&\\(this\\.adRewardVideo=tt\\.createRewardedVideoAd\\(\\{adUnitId:this\\.VideoAdPos\\}\\),.*?\\(\"暂无广告请咨询官方客服\"\\)\\}\\)\\)\\)\\},",
                @"replacement": @"$1.$2=function(){var $3=this;this.adRewardVideo={onClose:function(t){$3._fCls=t},onError:function(){},load:function(){return Promise.resolve()},show:function(){return setTimeout((function(){$3._fCls&&$3._fCls({isEnded:true}),$3.onVideoRewardHandler&&($3.onVideoRewardHandler(),$3.onVideoRewardHandler=null)}),50),Promise.resolve()}}},",
                @"useRegex": @YES
            }
        ]
    }];
    
     // 规则8：Hook Console
    [self.urlReplacementRules addObject:@{
        @"name": @"Hook Console",
        @"enabledKey": @"enableHookConsole",
        @"rules": @[
            @{
                @"urlPattern": @"bdpfile://bd\\.timor\\.wk/.*/game\\.js",
                @"urlIsRegex": @YES,
                @"contentPattern": @"__tt_define__(",
                @"replacement": @"(function(){const REPORT_URL='bdpfile://bd.timor.wk/helloworld';const methods=['log','info','warn','error'];let logQueue=[];let isSending=false;function flushLogs(){if(logQueue.length===0||isSending)return;isSending=true;try{const batch=logQueue.splice(0,10);const logString=batch.map(item=>`[${item.type}]${item.msg}`).join('\n');const safeContent=logString.substring(0,1500);const img=new Image();img.onload=img.onerror=function(){isSending=false};img.src=`${REPORT_URL}?logs=${encodeURIComponent(safeContent)}&_t=${Date.now()}`}catch(e){isSending=false}}setInterval(flushLogs,500);methods.forEach(method=>{const originalMethod=console[method];if(!originalMethod)return;console[method]=function(...args){originalMethod.apply(this,arguments);try{const content=args.map(arg=>{if(arg===null)return'null';if(arg===undefined)return'undefined';if(typeof arg==='object'){return arg.message?`Error:${arg.message}`:Object.prototype.toString.call(arg)}return String(arg)}).join(' ');logQueue.push({type:method,msg:content.substring(0,300)});if(logQueue.length>200){logQueue=[]}}catch(e){}}})})();console.log('bdpfile://bd.timor.wk/helloworld');__tt_define__(",
                @"useRegex": @NO
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

            // 只输出URL匹配的日志
            BOOL didReplace = (modified && ![modified isEqualToString:result]);
            NSString *dataPreview = result ? [[LogWindowManager sharedInstance] truncateString:result maxLength:200] : @"(nil)";
            NSString *fullLog = [NSString stringWithFormat:@"📋 [applyURLSpecificReplacementsToString] URL=%@ %@ | string=%@",
                             urlString,
                             didReplace ? @"[已替换]" : @"",
                             result];
            NSString *displayLog = [NSString stringWithFormat:@"📋 [applyURLSpecificReplacementsToString] URL=%@ %@ | string=%@",
                             urlString,
                             didReplace ? @"[已替换]" : @"",
                             dataPreview];
            // [[LogWindowManager sharedInstance] appendLogFull:fullLog displayLog:displayLog];
            if (result && result.length > 0) {
                NSString *responseLog = [NSString stringWithFormat:@"[RESPONSE] URL=%@ | LENGTH=%lu | CONTENT=%@",
                                       urlString, (unsigned long)result.length, result];
                [[LogWindowManager sharedInstance] writeLogToFile:responseLog];
            }

            if (modified && ![modified isEqualToString:result]) {
                self.totalReplacedCount++;
                NSString *log = [NSString stringWithFormat:@"✅ [%@] 替换成功 (第 %d 次) URL=%@", ruleName, self.totalReplacedCount, urlString];
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


- (void)showWeaponSelectionUI {
    UIWindow *keyWindow = [self topmostWindow];
    if (!keyWindow) return;

    NSArray *allWeapons = @[
        @{@"name":@"子弹",@"rarity":@"绿色武器"},@{@"name":@"金箍棒",@"rarity":@"绿色武器"},@{@"name":@"针",@"rarity":@"绿色武器"},@{@"name":@"手电筒",@"rarity":@"绿色武器"},@{@"name":@"便便",@"rarity":@"绿色武器"},
        @{@"name":@"小火人",@"rarity":@"蓝色武器"},@{@"name":@"豌豆",@"rarity":@"蓝色武器"},@{@"name":@"香肠",@"rarity":@"蓝色武器"},@{@"name":@"激光束",@"rarity":@"蓝色武器"},
        @{@"name":@"电风扇",@"rarity":@"紫色武器"},@{@"name":@"冰锥",@"rarity":@"紫色武器"},@{@"name":@"龙卷风",@"rarity":@"紫色武器"},@{@"name":@"冰茶",@"rarity":@"紫色武器"},@{@"name":@"纸飞机",@"rarity":@"紫色武器"},@{@"name":@"电池",@"rarity":@"紫色武器"},@{@"name":@"香蕉",@"rarity":@"紫色武器"},@{@"name":@"大威天龙",@"rarity":@"紫色武器"},@{@"name":@"篮球",@"rarity":@"紫色武器"},@{@"name":@"怪兽之眼",@"rarity":@"紫色武器"},@{@"name":@"三眼射线",@"rarity":@"紫色武器"},
        @{@"name":@"财神爷",@"rarity":@"金色武器"},@{@"name":@"大宝剑",@"rarity":@"金色武器"},@{@"name":@"冰棍",@"rarity":@"金色武器"},@{@"name":@"盾牌",@"rarity":@"金色武器"},@{@"name":@"回旋镖",@"rarity":@"金色武器"},@{@"name":@"菜刀",@"rarity":@"金色武器"},@{@"name":@"水滴",@"rarity":@"金色武器"},@{@"name":@"拳头",@"rarity":@"金色武器"},@{@"name":@"胶囊",@"rarity":@"金色武器"},@{@"name":@"插头",@"rarity":@"金色武器"},
        @{@"name":@"魔龙",@"rarity":@"红色武器"},@{@"name":@"万兵决",@"rarity":@"红色武器"}
    ];

    NSMutableArray *groups = [NSMutableArray array];
    NSArray *rarityOrder = @[@"绿色武器",@"蓝色武器",@"紫色武器",@"金色武器",@"红色武器"];
    NSDictionary *rarityColors = @{
        @"绿色武器": [UIColor colorWithRed:0.2 green:0.8 blue:0.2 alpha:1.0],
        @"蓝色武器": [UIColor colorWithRed:0.3 green:0.5 blue:1.0 alpha:1.0],
        @"紫色武器": [UIColor colorWithRed:0.7 green:0.3 blue:0.9 alpha:1.0],
        @"金色武器": [UIColor colorWithRed:1.0 green:0.8 blue:0.2 alpha:1.0],
        @"红色武器": [UIColor colorWithRed:1.0 green:0.3 blue:0.3 alpha:1.0]
    };
    NSDictionary *rarityEmojis = @{
        @"绿色武器": @"🟢", @"蓝色武器": @"🔵", @"紫色武器": @"🟣", @"金色武器": @"🟡", @"红色武器": @"🔴"
    };

    for (NSString *rarity in rarityOrder) {
        NSMutableArray *weaponsInGroup = [NSMutableArray array];
        for (NSDictionary *weapon in allWeapons) {
            if ([weapon[@"rarity"] isEqualToString:rarity]) {
                [weaponsInGroup addObject:weapon];
            }
        }
        if (weaponsInGroup.count > 0) {
            [groups addObject:@{@"rarity": rarity, @"weapons": weaponsInGroup}];
        }
    }

    // 遮罩层
    UIView *overlay = [[UIView alloc] initWithFrame:keyWindow.bounds];
    overlay.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.55];
    overlay.tag = 88888;
    overlay.alpha = 0;
    [keyWindow addSubview:overlay];

    CGFloat panelWidth = keyWindow.bounds.size.width * 0.92;
    CGFloat panelHeight = keyWindow.bounds.size.height * 0.82;
    CGFloat panelX = (keyWindow.bounds.size.width - panelWidth) / 2;
    CGFloat panelY = (keyWindow.bounds.size.height - panelHeight) / 2;

    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(panelX, panelY, panelWidth, panelHeight)];
    panel.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.13 alpha:0.98];
    panel.layer.cornerRadius = 18;
    panel.layer.masksToBounds = YES;
    panel.tag = 88889;
    panel.alpha = 0;
    panel.transform = CGAffineTransformMakeScale(0.85, 0.85);
    [keyWindow addSubview:panel];

    // 标题栏 - 可拖动
    UIView *titleBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, panelWidth, 52)];
    titleBar.backgroundColor = [UIColor colorWithRed:0.14 green:0.14 blue:0.18 alpha:1.0];
    [panel addSubview:titleBar];

    UIPanGestureRecognizer *titlePan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleWeaponPanelPan:)];
    [titleBar addGestureRecognizer:titlePan];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 0, panelWidth - 100, 52)];
    titleLabel.text = @"📌 选择武器碎片（每组至少选1个）";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont boldSystemFontOfSize:15];
    titleLabel.numberOfLines = 1;
    titleLabel.adjustsFontSizeToFitWidth = YES;
    [titleBar addSubview:titleLabel];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    closeBtn.frame = CGRectMake(panelWidth - 48, 10, 32, 32);
    closeBtn.layer.cornerRadius = 16;
    closeBtn.backgroundColor = [UIColor colorWithRed:1.0 green:0.3 blue:0.3 alpha:0.15];
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [closeBtn setTitleColor:[UIColor colorWithRed:1.0 green:0.4 blue:0.4 alpha:1.0] forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    closeBtn.tag = 88890;
    [titleBar addSubview:closeBtn];

    // 滚动区域
    CGFloat bottomBarHeight = 84;
    UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 52, panelWidth, panelHeight - 52 - bottomBarHeight)];
    scrollView.showsVerticalScrollIndicator = YES;
    scrollView.alwaysBounceVertical = YES;
    scrollView.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    [panel addSubview:scrollView];

    UIView *scrollContent = [[UIView alloc] initWithFrame:CGRectZero];
    scrollContent.tag = 88891;
    [scrollView addSubview:scrollContent];

    CGFloat yOff = 8;
    CGFloat btnSize = 34;
    CGFloat btnPadding = 7;
    NSInteger groupIndex = 0;

    for (NSDictionary *group in groups) {
        NSString *rarity = group[@"rarity"];
        NSArray *weapons = group[@"weapons"];
        UIColor *rarityColor = rarityColors[rarity] ?: [UIColor whiteColor];
        NSString *emoji = rarityEmojis[rarity] ?: @"";

        // 分组背景
        UIView *groupBg = [[UIView alloc] initWithFrame:CGRectZero];
        groupBg.backgroundColor = [rarityColor colorWithAlphaComponent:0.06];
        groupBg.layer.cornerRadius = 10;
        groupBg.tag = 89000 + groupIndex;
        [scrollContent addSubview:groupBg];
        CGFloat groupBgStartY = yOff;

        // 分组标题栏
        UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(10, yOff, panelWidth - 20, 36)];
        headerView.backgroundColor = [rarityColor colorWithAlphaComponent:0.15];
        headerView.layer.cornerRadius = 8;
        [scrollContent addSubview:headerView];

        UILabel *groupLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 0, 160, 36)];
        groupLabel.text = [NSString stringWithFormat:@"%@ %@", emoji, rarity];
        groupLabel.textColor = rarityColor;
        groupLabel.font = [UIFont boldSystemFontOfSize:14];
        [headerView addSubview:groupLabel];

        // 分组计数
        NSUInteger preSelected = 0;
        for (NSDictionary *w in weapons) {
            if ([self.selectedWeapons containsObject:w[@"name"]]) preSelected++;
        }
        UILabel *groupCountLabel = [[UILabel alloc] initWithFrame:CGRectMake(170, 0, 60, 36)];
        groupCountLabel.text = [NSString stringWithFormat:@"%lu/%lu", (unsigned long)preSelected, (unsigned long)weapons.count];
        groupCountLabel.textColor = [rarityColor colorWithAlphaComponent:0.8];
        groupCountLabel.font = [UIFont systemFontOfSize:12];
        groupCountLabel.textAlignment = NSTextAlignmentCenter;
        groupCountLabel.tag = 89100 + groupIndex;
        [headerView addSubview:groupCountLabel];

        // 全选按钮
        UIButton *selectAllBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        selectAllBtn.frame = CGRectMake(panelWidth - 20 - 68, 4, 68, 28);
        selectAllBtn.layer.cornerRadius = 6;
        selectAllBtn.layer.borderWidth = 1;
        selectAllBtn.layer.borderColor = [rarityColor colorWithAlphaComponent:0.4].CGColor;
        selectAllBtn.backgroundColor = [rarityColor colorWithAlphaComponent:0.1];
        selectAllBtn.titleLabel.font = [UIFont systemFontOfSize:12];
        selectAllBtn.tag = 89200 + groupIndex;
        BOOL allSelected = (preSelected == weapons.count);
        if (allSelected) {
            [selectAllBtn setTitle:@"取消全选" forState:UIControlStateNormal];
            [selectAllBtn setTitleColor:rarityColor forState:UIControlStateNormal];
        } else {
            [selectAllBtn setTitle:@"全选" forState:UIControlStateNormal];
            [selectAllBtn setTitleColor:rarityColor forState:UIControlStateNormal];
        }
        objc_setAssociatedObject(selectAllBtn, "rarityName", rarity, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(selectAllBtn, "groupIndex", @(groupIndex), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [selectAllBtn addTarget:self action:@selector(selectAllGroupTapped:) forControlEvents:UIControlEventTouchUpInside];
        [headerView addSubview:selectAllBtn];

        yOff += 40;

        // 武器按钮（流式布局）
        CGFloat xOff = 14;
        for (NSDictionary *weapon in weapons) {
            NSString *name = weapon[@"name"];
            CGFloat textWidth = [name sizeWithAttributes:@{NSFontAttributeName: [UIFont systemFontOfSize:13]}].width;
            CGFloat btnWidth = textWidth + 24;
            if (btnWidth < 56) btnWidth = 56;

            if (xOff + btnWidth > panelWidth - 14) {
                xOff = 14;
                yOff += btnSize + btnPadding;
            }

            UIButton *weaponBtn = [UIButton buttonWithType:UIButtonTypeCustom];
            weaponBtn.frame = CGRectMake(xOff, yOff, btnWidth, btnSize);
            weaponBtn.layer.cornerRadius = 8;
            weaponBtn.layer.masksToBounds = YES;
            weaponBtn.titleLabel.font = [UIFont systemFontOfSize:13];
            weaponBtn.tag = 88900;

            BOOL isSelected = [self.selectedWeapons containsObject:name];
            if (isSelected) {
                weaponBtn.backgroundColor = [rarityColor colorWithAlphaComponent:0.85];
                [weaponBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
                weaponBtn.layer.borderWidth = 2;
                weaponBtn.layer.borderColor = rarityColor.CGColor;
                weaponBtn.selected = YES;
            } else {
                weaponBtn.backgroundColor = [UIColor colorWithRed:0.18 green:0.18 blue:0.22 alpha:1.0];
                [weaponBtn setTitleColor:[UIColor colorWithRed:0.65 green:0.65 blue:0.7 alpha:1.0] forState:UIControlStateNormal];
                weaponBtn.layer.borderWidth = 1;
                weaponBtn.layer.borderColor = [UIColor colorWithRed:0.3 green:0.3 blue:0.35 alpha:1.0].CGColor;
                weaponBtn.selected = NO;
            }
            [weaponBtn setTitle:name forState:UIControlStateNormal];

            objc_setAssociatedObject(weaponBtn, "rarityColor", rarityColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(weaponBtn, "weaponName", name, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(weaponBtn, "rarityName", rarity, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(weaponBtn, "groupIndex", @(groupIndex), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

            [weaponBtn addTarget:self action:@selector(weaponButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
            [scrollContent addSubview:weaponBtn];

            xOff += btnWidth + btnPadding;
        }
        yOff += btnSize + btnPadding + 6;

        // 更新分组背景尺寸
        CGFloat groupBgHeight = yOff - groupBgStartY;
        groupBg.frame = CGRectMake(6, groupBgStartY, panelWidth - 12, groupBgHeight);

        yOff += 6; // 组间距
        groupIndex++;
    }

    scrollContent.frame = CGRectMake(0, 0, panelWidth, yOff);
    scrollView.contentSize = CGSizeMake(panelWidth, yOff);

    // 底部操作栏
    UIView *bottomBar = [[UIView alloc] initWithFrame:CGRectMake(0, panelHeight - bottomBarHeight, panelWidth, bottomBarHeight)];
    bottomBar.backgroundColor = [UIColor colorWithRed:0.13 green:0.13 blue:0.16 alpha:1.0];
    [panel addSubview:bottomBar];

    // 分隔线
    UIView *topLine = [[UIView alloc] initWithFrame:CGRectMake(0, 0, panelWidth, 1)];
    topLine.backgroundColor = [UIColor colorWithRed:0.25 green:0.25 blue:0.3 alpha:0.5];
    [bottomBar addSubview:topLine];

    UILabel *selectedCountLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 4, panelWidth - 32, 18)];
    selectedCountLabel.text = [NSString stringWithFormat:@"✦ 已选择 %lu 个武器", (unsigned long)self.selectedWeapons.count];
    selectedCountLabel.textColor = [UIColor colorWithRed:0.7 green:0.75 blue:0.85 alpha:1.0];
    selectedCountLabel.font = [UIFont systemFontOfSize:12];
    selectedCountLabel.textAlignment = NSTextAlignmentCenter;
    selectedCountLabel.tag = 88892;
    [bottomBar addSubview:selectedCountLabel];

    // 确认按钮 - 渐变色效果
    UIButton *confirmBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    confirmBtn.frame = CGRectMake(16, 26, panelWidth - 32, 44);
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.frame = confirmBtn.bounds;
    gradient.colors = @[(id)[UIColor colorWithRed:0.2 green:0.5 blue:1.0 alpha:1.0].CGColor, (id)[UIColor colorWithRed:0.4 green:0.3 blue:0.9 alpha:1.0].CGColor];
    gradient.startPoint = CGPointMake(0, 0.5);
    gradient.endPoint = CGPointMake(1, 0.5);
    gradient.cornerRadius = 10;
    [confirmBtn.layer insertSublayer:gradient atIndex:0];
    confirmBtn.layer.cornerRadius = 10;
    confirmBtn.layer.masksToBounds = YES;
    [confirmBtn setTitle:@"✅ 确认选择" forState:UIControlStateNormal];
    confirmBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    confirmBtn.tag = 88893;
    [bottomBar addSubview:confirmBtn];

    [closeBtn addTarget:self action:@selector(weaponSelectionCancel) forControlEvents:UIControlEventTouchUpInside];
    [confirmBtn addTarget:self action:@selector(weaponSelectionConfirm) forControlEvents:UIControlEventTouchUpInside];

    // 入场动画
    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:UIViewAnimationOptionCurveEaseOut animations:^{
        overlay.alpha = 1;
        panel.alpha = 1;
        panel.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)weaponButtonTapped:(UIButton *)sender {
    NSString *weaponName = objc_getAssociatedObject(sender, "weaponName");
    UIColor *rarityColor = objc_getAssociatedObject(sender, "rarityColor");
    NSString *rarityName = objc_getAssociatedObject(sender, "rarityName");
    NSNumber *groupIdx = objc_getAssociatedObject(sender, "groupIndex");

    if (sender.selected) {
        NSUInteger groupSelectedCount = 0;
        UIView *scrollContent = sender.superview;
        for (UIView *sub in scrollContent.subviews) {
            if ([sub isKindOfClass:[UIButton class]] && sub.tag == 88900) {
                UIButton *btn = (UIButton *)sub;
                NSString *btnRarity = objc_getAssociatedObject(btn, "rarityName");
                if (btn.selected && [btnRarity isEqualToString:rarityName]) {
                    groupSelectedCount++;
                }
            }
        }
        if (groupSelectedCount <= 1) {
            // 抖动动画 - 提示不能取消
            CABasicAnimation *shake = [CABasicAnimation animationWithKeyPath:@"position.x"];
            shake.fromValue = @(sender.center.x - 4);
            shake.toValue = @(sender.center.x + 4);
            shake.duration = 0.08;
            shake.autoreverses = YES;
            shake.repeatCount = 2;
            [sender.layer addAnimation:shake forKey:@"shake"];
            return;
        }
        sender.selected = NO;
        sender.backgroundColor = [UIColor colorWithRed:0.18 green:0.18 blue:0.22 alpha:1.0];
        [sender setTitleColor:[UIColor colorWithRed:0.65 green:0.65 blue:0.7 alpha:1.0] forState:UIControlStateNormal];
        sender.layer.borderWidth = 1;
        sender.layer.borderColor = [UIColor colorWithRed:0.3 green:0.3 blue:0.35 alpha:1.0].CGColor;
        [self.selectedWeapons removeObject:weaponName];
    } else {
        sender.selected = YES;
        sender.backgroundColor = [rarityColor colorWithAlphaComponent:0.85];
        [sender setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        sender.layer.borderWidth = 2;
        sender.layer.borderColor = rarityColor.CGColor;
        [self.selectedWeapons addObject:weaponName];
        // 选中缩放动画
        [UIView animateWithDuration:0.1 animations:^{
            sender.transform = CGAffineTransformMakeScale(1.1, 1.1);
        } completion:^(BOOL finished) {
            [UIView animateWithDuration:0.1 animations:^{
                sender.transform = CGAffineTransformIdentity;
            } completion:nil];
        }];
    }

    [self updateWeaponSelectionCounts];
}

- (void)weaponSelectionCancel {
    UIWindow *keyWindow = [self topmostWindow];
    if (!keyWindow) return;
    UIView *overlay = [keyWindow viewWithTag:88888];
    UIView *panel = [keyWindow viewWithTag:88889];
    [UIView animateWithDuration:0.25 animations:^{
        overlay.alpha = 0;
        panel.alpha = 0;
        panel.transform = CGAffineTransformMakeScale(0.9, 0.9);
    } completion:^(BOOL finished) {
        [overlay removeFromSuperview];
        [panel removeFromSuperview];
    }];
    self.enableWeaponPin = NO;
    [self updateMenuSubtitleForTag:1010 text:@"当前：已关闭"];
}

- (void)weaponSelectionConfirm {
    if (self.selectedWeapons.count == 0) {
        [self showMessage:@"提示" message:@"请至少选择一个武器"];
        return;
    }

    [self updateWeaponPinRuleWithWeapons:self.selectedWeapons];
    [self saveConfiguration];

    UIWindow *keyWindow = [self topmostWindow];
    if (!keyWindow) return;
    UIView *overlay = [keyWindow viewWithTag:88888];
    UIView *panel = [keyWindow viewWithTag:88889];
    [UIView animateWithDuration:0.25 animations:^{
        overlay.alpha = 0;
        panel.alpha = 0;
        panel.transform = CGAffineTransformMakeScale(0.9, 0.9);
    } completion:^(BOOL finished) {
        [overlay removeFromSuperview];
        [panel removeFromSuperview];
    }];

    NSString *weaponsStr = [self.selectedWeapons componentsJoinedByString:@", "];
    NSString *log = [NSString stringWithFormat:@"📌 已选择 %lu 个武器: %@", (unsigned long)self.selectedWeapons.count, weaponsStr];
    NSLog(@"[Tweak] %@", log);
    [[LogWindowManager sharedInstance] appendLog:log];
}

- (void)updateWeaponPinRuleWithWeapons:(NSArray<NSString *> *)weapons {
    NSMutableArray *quotedNames = [NSMutableArray array];
    for (NSString *name in weapons) {
        [quotedNames addObject:[NSString stringWithFormat:@"\"%@\"", name]];
    }
    NSString *newWeaponArray = [NSString stringWithFormat:@"[%@]", [quotedNames componentsJoinedByString:@","]];

    for (NSUInteger idx = 0; idx < self.urlReplacementRules.count; idx++) {
        NSDictionary *rule = self.urlReplacementRules[idx];
        if ([rule[@"enabledKey"] isEqualToString:@"enableWeaponPin"]) {
            NSArray *subRules = rule[@"rules"];
            if (subRules.count > 0) {
                NSDictionary *subRule = subRules[0];
                NSString *currentReplacement = subRule[@"replacement"];
                NSError *error = nil;
                NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"\\[.*?\\]" options:0 error:&error];
                if (!error && regex) {
                    NSString *updatedReplacement = [regex stringByReplacingMatchesInString:currentReplacement options:0 range:NSMakeRange(0, currentReplacement.length) withTemplate:newWeaponArray];
                    NSDictionary *newSubRule = @{
                        @"urlPattern": subRule[@"urlPattern"],
                        @"urlIsRegex": subRule[@"urlIsRegex"],
                        @"contentPattern": subRule[@"contentPattern"],
                        @"replacement": updatedReplacement,
                        @"useRegex": subRule[@"useRegex"]
                    };
                    NSDictionary *newRule = @{
                        @"name": rule[@"name"],
                        @"enabledKey": rule[@"enabledKey"],
                        @"dynamicWeaponPin": rule[@"dynamicWeaponPin"],
                        @"rules": @[newSubRule]
                    };
                    [self.urlReplacementRules replaceObjectAtIndex:idx withObject:newRule];
                }
            }
            break;
        }
    }
}

- (void)selectAllGroupTapped:(UIButton *)sender {
    NSString *rarity = objc_getAssociatedObject(sender, "rarityName");
    NSNumber *groupIdx = objc_getAssociatedObject(sender, "groupIndex");
    UIWindow *keyWindow = [self topmostWindow];
    if (!keyWindow) return;
    UIView *panel = [keyWindow viewWithTag:88889];
    if (!panel) return;
    UIScrollView *scrollView = nil;
    for (UIView *sub in panel.subviews) {
        if ([sub isKindOfClass:[UIScrollView class]]) { scrollView = (UIScrollView *)sub; break; }
    }
    if (!scrollView) return;
    UIView *scrollContent = scrollView.subviews.firstObject;
    if (!scrollContent) return;

    // 判断当前是否全选
    NSUInteger totalCount = 0;
    NSUInteger selectedCount = 0;
    NSMutableArray *groupButtons = [NSMutableArray array];
    for (UIView *sub in scrollContent.subviews) {
        if ([sub isKindOfClass:[UIButton class]] && sub.tag == 88900) {
            UIButton *btn = (UIButton *)sub;
            NSString *btnRarity = objc_getAssociatedObject(btn, "rarityName");
            if ([btnRarity isEqualToString:rarity]) {
                [groupButtons addObject:btn];
                totalCount++;
                if (btn.selected) selectedCount++;
            }
        }
    }

    BOOL shouldSelectAll = (selectedCount < totalCount);
    UIColor *rarityColor = nil;

    for (UIButton *btn in groupButtons) {
        NSString *name = objc_getAssociatedObject(btn, "weaponName");
        rarityColor = objc_getAssociatedObject(btn, "rarityColor");
        if (shouldSelectAll && !btn.selected) {
            btn.selected = YES;
            btn.backgroundColor = [rarityColor colorWithAlphaComponent:0.85];
            [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
            btn.layer.borderWidth = 2;
            btn.layer.borderColor = rarityColor.CGColor;
            if (![self.selectedWeapons containsObject:name]) {
                [self.selectedWeapons addObject:name];
            }
        } else if (!shouldSelectAll && btn.selected) {
            // 取消全选时保留至少一个
            if ([groupButtons indexOfObject:btn] == 0) continue; // 保留第一个
            btn.selected = NO;
            btn.backgroundColor = [UIColor colorWithRed:0.18 green:0.18 blue:0.22 alpha:1.0];
            [btn setTitleColor:[UIColor colorWithRed:0.65 green:0.65 blue:0.7 alpha:1.0] forState:UIControlStateNormal];
            btn.layer.borderWidth = 1;
            btn.layer.borderColor = [UIColor colorWithRed:0.3 green:0.3 blue:0.35 alpha:1.0].CGColor;
            [self.selectedWeapons removeObject:name];
        }
    }

    [self updateWeaponSelectionCounts];
}

- (void)updateWeaponSelectionCounts {
    UIWindow *keyWindow = [self topmostWindow];
    if (!keyWindow) return;
    UIView *panel = [keyWindow viewWithTag:88889];
    if (!panel) return;
    UIScrollView *scrollView = nil;
    for (UIView *sub in panel.subviews) {
        if ([sub isKindOfClass:[UIScrollView class]]) { scrollView = (UIScrollView *)sub; break; }
    }
    if (!scrollView) return;
    UIView *scrollContent = scrollView.subviews.firstObject;
    if (!scrollContent) return;

    // 按分组统计
    NSMutableDictionary *groupCounts = [NSMutableDictionary dictionary];
    NSMutableDictionary *groupTotals = [NSMutableDictionary dictionary];
    for (UIView *sub in scrollContent.subviews) {
        if ([sub isKindOfClass:[UIButton class]] && sub.tag == 88900) {
            UIButton *btn = (UIButton *)sub;
            NSString *rarity = objc_getAssociatedObject(btn, "rarityName") ?: @"unknown";
            NSNumber *gIdx = objc_getAssociatedObject(btn, "groupIndex") ?: @0;
            if (!groupTotals[gIdx]) groupTotals[gIdx] = @0;
            if (!groupCounts[gIdx]) groupCounts[gIdx] = @0;
            groupTotals[gIdx] = @([groupTotals[gIdx] intValue] + 1);
            if (btn.selected) {
                groupCounts[gIdx] = @([groupCounts[gIdx] intValue] + 1);
            }
        }
    }

    // 更新每组计数Label和全选按钮
    for (NSNumber *gIdx in groupTotals) {
        NSInteger idx = [gIdx integerValue];
        NSInteger cnt = [groupCounts[gIdx] integerValue];
        NSInteger total = [groupTotals[gIdx] integerValue];
        UILabel *countLabel = [scrollContent viewWithTag:89100 + idx];
        if (countLabel) {
            countLabel.text = [NSString stringWithFormat:@"%ld/%ld", (long)cnt, (long)total];
        }
        UIButton *selAllBtn = [scrollContent viewWithTag:89200 + idx];
        if (!selAllBtn) {
            // 查找headerView中的全选按钮
            for (UIView *sub2 in scrollContent.subviews) {
                if (sub2.tag == 89200 + idx) { selAllBtn = (UIButton *)sub2; break; }
            }
        }
    }

    // 更新全选按钮文本 - 遍历headerView
    for (UIView *sub in scrollContent.subviews) {
        for (UIView *headerSub in sub.subviews) {
            if ([headerSub isKindOfClass:[UIButton class]] && headerSub.tag >= 89200 && headerSub.tag < 89300) {
                UIButton *selBtn = (UIButton *)headerSub;
                NSInteger idx = selBtn.tag - 89200;
                NSInteger cnt = [groupCounts[@(idx)] integerValue];
                NSInteger total = [groupTotals[@(idx)] integerValue];
                if (cnt == total) {
                    [selBtn setTitle:@"取消全选" forState:UIControlStateNormal];
                } else {
                    [selBtn setTitle:@"全选" forState:UIControlStateNormal];
                }
            }
        }
    }

    // 更新底部总计数
    for (UIView *sub in panel.subviews) {
        UILabel *countLabel = [sub viewWithTag:88892];
        if (countLabel && [countLabel isKindOfClass:[UILabel class]]) {
            countLabel.text = [NSString stringWithFormat:@"✦ 已选择 %lu 个武器", (unsigned long)self.selectedWeapons.count];
            break;
        }
    }
}

- (void)handleWeaponPanelPan:(UIPanGestureRecognizer *)gesture {
    UIView *panel = nil;
    UIWindow *keyWindow = [self topmostWindow];
    if (keyWindow) { panel = [keyWindow viewWithTag:88889]; }
    if (!panel) return;
    CGPoint translation = [gesture translationInView:panel.superview];
    if (gesture.state == UIGestureRecognizerStateChanged) {
        CGRect newFrame = panel.frame;
        newFrame.origin.x += translation.x;
        newFrame.origin.y += translation.y;
        panel.frame = newFrame;
        [gesture setTranslation:CGPointZero inView:panel.superview];
    }
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
            if ([taskUrl hasPrefix:@"bdpfile:/bd.timor.wk/helloworld"] || [taskUrl hasPrefix:@"bdpfile://bd.timor.wk/helloworld"]) {
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
            
            /*
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
            //[[LogWindowManager sharedInstance] appendLogFull:fullLog displayLog:displayLog];
            
            if (data && data.length > 0) {
                NSString *dataStr2 = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
                NSString *responseLog = [NSString stringWithFormat:@"[RESPONSE][Type=%@] URL=%@ | LENGTH=%lu | CONTENT=%@",
                                       contentType, taskUrl, (unsigned long)data.length, dataStr2 ?: @"(binary data)"];
                [[LogWindowManager sharedInstance] writeLogToFile:responseLog];
            }
            */
            
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
    
    hookURLSchemeTask(urlSchemeTask);
    
    /*
    NSString *urlStr = @"(nil)";
    if (urlSchemeTask && [urlSchemeTask respondsToSelector:@selector(request)]) {
        NSURLRequest *req = [urlSchemeTask request];
        if (req && req.URL) {
            urlStr = [req.URL absoluteString];
        }
    }

    NSString *fullLog = [NSString stringWithFormat:@"📋 [BDPWKURLSchemeHandler webView:startURLSchemeTask:] URL=%@", urlStr];
    NSString *displayLog = [NSString stringWithFormat:@"📋 [BDPWKURLSchemeHandler webView:startURLSchemeTask:] URL=%@", 
                           [[LogWindowManager sharedInstance] truncateString:urlStr maxLength:120]];
    NSLog(@"[Tweak] %@", fullLog);
    [[LogWindowManager sharedInstance] appendLogFull:fullLog displayLog:displayLog];

    NSString *requestLog = [NSString stringWithFormat:@"[REQUEST] URL=%@", urlStr];
    [[LogWindowManager sharedInstance] writeLogToFile:requestLog];
    */
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
