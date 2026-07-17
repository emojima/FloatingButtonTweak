#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import <WebKit/WebKit.h>
#import <mach/mach.h>
#import <mach/vm_map.h>

@interface LogWindowManager : NSObject
@property (nonatomic, strong) UIWindow *logWindow;
@property (nonatomic, strong) UITextView *logTextView;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) NSMutableString *logBuffer;
@property (nonatomic, assign) BOOL isVisible;
+ (instancetype)sharedInstance;
- (void)toggleLogWindow;
- (void)showLogWindow;
- (void)hideLogWindow;
- (void)appendLog:(NSString *)log;
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
    }
    return self;
}

- (void)toggleLogWindow {
    if (self.isVisible) {
        [self hideLogWindow];
    } else {
        [self showLogWindow];
    }
}

- (void)showLogWindow {
    if (self.logWindow) {
        self.logWindow.hidden = NO;
        self.isVisible = YES;
        [self.logWindow makeKeyAndVisible];
        return;
    }

    CGFloat screenWidth = [[UIScreen mainScreen] bounds].size.width;
    CGFloat screenHeight = [[UIScreen mainScreen] bounds].size.height;
    CGFloat windowWidth = screenWidth * 0.9;
    CGFloat windowHeight = screenHeight * 0.6;
    CGFloat windowX = (screenWidth - windowWidth) / 2;
    CGFloat windowY = screenHeight * 0.15;

    self.logWindow = [[UIWindow alloc] initWithFrame:CGRectMake(windowX, windowY, windowWidth, windowHeight)];
    self.logWindow.windowLevel = UIWindowLevelAlert + 100;
    self.logWindow.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.1 alpha:0.92];
    self.logWindow.layer.cornerRadius = 12;
    self.logWindow.layer.masksToBounds = YES;

    // 标题栏
    UIView *titleBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, windowWidth, 36)];
    titleBar.backgroundColor = [UIColor colorWithRed:0.15 green:0.15 blue:0.15 alpha:1.0];
    [self.logWindow addSubview:titleBar];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 0, windowWidth - 80, 36)];
    titleLabel.text = @"📋 Tweak 日志";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [titleBar addSubview:titleLabel];

    // 关闭按钮
    self.closeButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.closeButton.frame = CGRectMake(windowWidth - 50, 4, 40, 28);
    [self.closeButton setTitle:@"✕" forState:UIControlStateNormal];
    [self.closeButton setTitleColor:[UIColor colorWithRed:1.0 green:0.3 blue:0.3 alpha:1.0] forState:UIControlStateNormal];
    self.closeButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [self.closeButton addTarget:self action:@selector(hideLogWindow) forControlEvents:UIControlEventTouchUpInside];
    [titleBar addSubview:self.closeButton];

    // 日志文本视图
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
    [self.logWindow addSubview:self.logTextView];

    self.logWindow.hidden = NO;
    self.isVisible = YES;
    [self.logWindow makeKeyAndVisible];
}

- (void)hideLogWindow {
    self.logWindow.hidden = YES;
    self.isVisible = NO;
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
            // 不自动滚动，保持用户当前滚动位置
        }
    });
}

@end

@interface FloatingButtonManager : NSObject
@property (nonatomic, strong) UIButton *floatingButton;
@property (nonatomic, strong) NSTimer *keepOnTopTimer;
@property (nonatomic, weak) UIWindow *lastWindow;
@property (nonatomic, assign) BOOL hookEnabled;
@property (nonatomic, strong) NSMutableArray *hookedClasses;
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
        _hookEnabled = NO;
        _hookedClasses = [NSMutableArray array];
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

    NSString *hookStatus = self.hookEnabled ? @" (已启用)" : @"";
    NSString *logStatus = [[LogWindowManager sharedInstance] isVisible] ? @" (显示中)" : @"";

    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"修改属性词条免广告刷新次数%@", hookStatus] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self enableAllHooks];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Unity WASM 内存搜索" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self searchWASMMemory];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"日志窗口%@", logStatus] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [[LogWindowManager sharedInstance] toggleLogWindow];
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

#pragma mark - ========== 字符串替换工具 ==========

- (NSString *)replaceTargetInString:(NSString *)string {
    if (!string || string.length == 0) return string;

    NSString *modified = string;

    modified = [modified stringByReplacingOccurrencesOfString:
        @".curLevel)?this.freeRefreshNum=2:this.freeRefreshNum=0"
        withString:@".curLevel),this.refreshNum=100,this.freeRefreshNum=100"];

    modified = [modified stringByReplacingOccurrencesOfString:
        @".curLevel) ? this.freeRefreshNum = 2 : this.freeRefreshNum = 0"
        withString:@".curLevel), this.refreshNum = 100, this.freeRefreshNum = 100"];

    modified = [modified stringByReplacingOccurrencesOfString:
        @"curLevel)?this.freeRefreshNum=2:this.freeRefreshNum=0"
        withString:@"curLevel),this.refreshNum=100,this.freeRefreshNum=100"];

    modified = [modified stringByReplacingOccurrencesOfString:
        @".curLevel'?this.freeRefreshNum=2:this.freeRefreshNum=0"
        withString:@".curLevel'),this.refreshNum=100,this.freeRefreshNum=100"];

    modified = [modified stringByReplacingOccurrencesOfString:
        @"this.freeRefreshNum=2:this.freeRefreshNum=0"
        withString:@"this.refreshNum=100,this.freeRefreshNum=100"];

    modified = [modified stringByReplacingOccurrencesOfString:
        @"?this.freeRefreshNum=2:this.freeRefreshNum=0"
        withString:@",this.refreshNum=100,this.freeRefreshNum=100"];

    modified = [modified stringByReplacingOccurrencesOfString:
        @"freeRefreshNum=2"
        withString:@"freeRefreshNum=100"];

    modified = [modified stringByReplacingOccurrencesOfString:
        @"freeRefreshNum=0"
        withString:@"freeRefreshNum=100"];

    return modified;
}

#pragma mark - ========== 方案一：Hook JSContext ==========

static id (*orig_JSContext_evaluateScript)(id self, SEL _cmd, NSString *script);
static id hook_JSContext_evaluateScript(id self, SEL _cmd, NSString *script) {
    if (![[FloatingButtonManager sharedInstance] hookEnabled]) {
        return orig_JSContext_evaluateScript(self, _cmd, script);
    }

    NSString *modifiedScript = [[FloatingButtonManager sharedInstance] replaceTargetInString:script];

    if (![modifiedScript isEqualToString:script]) {
        NSLog(@"[Tweak] ✅ JSContext evaluateScript: 已替换目标字符串");
        [[LogWindowManager sharedInstance] appendLog:@"✅ JSContext evaluateScript: 已替换目标字符串"];
    }

    return orig_JSContext_evaluateScript(self, _cmd, modifiedScript);
}

#pragma mark - ========== 方案二：Hook WKUserScript ==========

static id (*orig_WKUserScript_initWithSource)(id self, SEL _cmd, NSString *source, WKUserScriptInjectionTime injectionTime, BOOL forMainFrameOnly);
static id hook_WKUserScript_initWithSource(id self, SEL _cmd, NSString *source, WKUserScriptInjectionTime injectionTime, BOOL forMainFrameOnly) {
    if (![[FloatingButtonManager sharedInstance] hookEnabled]) {
        return orig_WKUserScript_initWithSource(self, _cmd, source, injectionTime, forMainFrameOnly);
    }

    NSString *modifiedSource = [[FloatingButtonManager sharedInstance] replaceTargetInString:source];

    if (![modifiedSource isEqualToString:source]) {
        NSLog(@"[Tweak] ✅ WKUserScript initWithSource: 已替换目标字符串");
        [[LogWindowManager sharedInstance] appendLog:@"✅ WKUserScript initWithSource: 已替换目标字符串"];
    }

    return orig_WKUserScript_initWithSource(self, _cmd, modifiedSource, injectionTime, forMainFrameOnly);
}

#pragma mark - ========== 方案三：Hook WKWebView 加载方法 ==========

static id (*orig_WKWebView_loadHTMLString)(id self, SEL _cmd, NSString *string, NSURL *baseURL);
static id hook_WKWebView_loadHTMLString(id self, SEL _cmd, NSString *string, NSURL *baseURL) {
    if (![[FloatingButtonManager sharedInstance] hookEnabled]) {
        return orig_WKWebView_loadHTMLString(self, _cmd, string, baseURL);
    }

    NSString *modifiedString = [[FloatingButtonManager sharedInstance] replaceTargetInString:string];

    if (![modifiedString isEqualToString:string]) {
        NSLog(@"[Tweak] ✅ WKWebView loadHTMLString: 已替换目标字符串");
        [[LogWindowManager sharedInstance] appendLog:@"✅ WKWebView loadHTMLString: 已替换目标字符串"];
    }

    return orig_WKWebView_loadHTMLString(self, _cmd, modifiedString, baseURL);
}

static id (*orig_WKWebView_loadData)(id self, SEL _cmd, NSData *data, NSString *MIMEType, NSString *characterEncodingName, NSURL *baseURL);
static id hook_WKWebView_loadData(id self, SEL _cmd, NSData *data, NSString *MIMEType, NSString *characterEncodingName, NSURL *baseURL) {
    if (![[FloatingButtonManager sharedInstance] hookEnabled]) {
        return orig_WKWebView_loadData(self, _cmd, data, MIMEType, characterEncodingName, baseURL);
    }

    if ([MIMEType isEqualToString:@"text/html"] || [MIMEType isEqualToString:@"application/javascript"] || [MIMEType isEqualToString:@"text/javascript"]) {
        NSString *content = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (content) {
            NSString *modifiedContent = [[FloatingButtonManager sharedInstance] replaceTargetInString:content];
            if (![modifiedContent isEqualToString:content]) {
                NSLog(@"[Tweak] ✅ WKWebView loadData: 已替换目标字符串");
                [[LogWindowManager sharedInstance] appendLog:@"✅ WKWebView loadData: 已替换目标字符串"];
                data = [modifiedContent dataUsingEncoding:NSUTF8StringEncoding];
            }
        }
    }

    return orig_WKWebView_loadData(self, _cmd, data, MIMEType, characterEncodingName, baseURL);
}

static id (*orig_WKWebView_loadRequest)(id self, SEL _cmd, NSURLRequest *request);
static id hook_WKWebView_loadRequest(id self, SEL _cmd, NSURLRequest *request) {
    if (![[FloatingButtonManager sharedInstance] hookEnabled]) {
        return orig_WKWebView_loadRequest(self, _cmd, request);
    }

    NSString *log = [NSString stringWithFormat:@"ℹ️ WKWebView loadRequest: URL=%@", request.URL.absoluteString];
    NSLog(@"[Tweak] %@", log);
    [[LogWindowManager sharedInstance] appendLog:log];
    return orig_WKWebView_loadRequest(self, _cmd, request);
}

#pragma mark - ========== 方案四：Hook 文件读取 ==========

static id (*orig_NSString_stringWithContentsOfFile_encoding_error)(id self, SEL _cmd, NSString *path, NSStringEncoding enc, NSError **error);
static id hook_NSString_stringWithContentsOfFile_encoding_error(id self, SEL _cmd, NSString *path, NSStringEncoding enc, NSError **error) {
    id result = orig_NSString_stringWithContentsOfFile_encoding_error(self, _cmd, path, enc, error);

    if ([[FloatingButtonManager sharedInstance] hookEnabled] && [result isKindOfClass:[NSString class]]) {
        NSString *content = (NSString *)result;
        if ([path hasSuffix:@".js"] || [path hasSuffix:@".html"] || [path hasSuffix:@".htm"] || [path containsString:@"javascript"] || [path containsString:@"script"]) {
            NSString *modifiedContent = [[FloatingButtonManager sharedInstance] replaceTargetInString:content];
            if (![modifiedContent isEqualToString:content]) {
                NSString *log = [NSString stringWithFormat:@"✅ NSString stringWithContentsOfFile: 已替换 | path=%@", path];
                NSLog(@"[Tweak] %@", log);
                [[LogWindowManager sharedInstance] appendLog:log];
                return modifiedContent;
            }
        }
    }

    return result;
}

static id (*orig_NSData_dataWithContentsOfFile)(id self, SEL _cmd, NSString *path);
static id hook_NSData_dataWithContentsOfFile(id self, SEL _cmd, NSString *path) {
    id result = orig_NSData_dataWithContentsOfFile(self, _cmd, path);

    if ([[FloatingButtonManager sharedInstance] hookEnabled] && [result isKindOfClass:[NSData class]]) {
        if ([path hasSuffix:@".js"] || [path containsString:@"javascript"] || [path containsString:@"script"]) {
            NSString *content = [[NSString alloc] initWithData:(NSData *)result encoding:NSUTF8StringEncoding];
            if (content) {
                NSString *modifiedContent = [[FloatingButtonManager sharedInstance] replaceTargetInString:content];
                if (![modifiedContent isEqualToString:content]) {
                    NSString *log = [NSString stringWithFormat:@"✅ NSData dataWithContentsOfFile: 已替换 | path=%@", path];
                    NSLog(@"[Tweak] %@", log);
                    [[LogWindowManager sharedInstance] appendLog:log];
                    return [modifiedContent dataUsingEncoding:NSUTF8StringEncoding];
                }
            }
        }
    }

    return result;
}

#pragma mark - ========== 方案五：Hook 网络请求 ==========

static id (*orig_NSURLSession_dataTaskWithRequest_completion)(id self, SEL _cmd, NSURLRequest *request, id completionHandler);
static id hook_NSURLSession_dataTaskWithRequest_completion(id self, SEL _cmd, NSURLRequest *request, id completionHandler) {
    if (![[FloatingButtonManager sharedInstance] hookEnabled]) {
        return orig_NSURLSession_dataTaskWithRequest_completion(self, _cmd, request, completionHandler);
    }

    id modifiedCompletion = completionHandler;
    if (completionHandler) {
        modifiedCompletion = ^(NSData *data, NSURLResponse *response, NSError *error) {
            NSData *modifiedData = data;
            if (data && [response isKindOfClass:[NSHTTPURLResponse class]]) {
                NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
                NSString *contentType = httpResponse.allHeaderFields[@"Content-Type"];
                NSString *urlString = request.URL.absoluteString;

                BOOL isJSContent = [contentType containsString:@"javascript"] || 
                                   [contentType containsString:@"json"] ||
                                   [urlString hasSuffix:@".js"] ||
                                   [urlString containsString:@"script"] ||
                                   [urlString containsString:@"js"];

                if (isJSContent) {
                    NSString *content = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                    if (content) {
                        NSString *modifiedContent = [[FloatingButtonManager sharedInstance] replaceTargetInString:content];
                        if (![modifiedContent isEqualToString:content]) {
                            NSString *log = [NSString stringWithFormat:@"✅ NSURLSession: 已替换网络响应 | URL=%@", urlString];
                            NSLog(@"[Tweak] %@", log);
                            [[LogWindowManager sharedInstance] appendLog:log];
                            modifiedData = [modifiedContent dataUsingEncoding:NSUTF8StringEncoding];
                        }
                    }
                }
            }

            void (^origBlock)(NSData *, NSURLResponse *, NSError *) = completionHandler;
            origBlock(modifiedData, response, error);
        };
    }

    return orig_NSURLSession_dataTaskWithRequest_completion(self, _cmd, request, modifiedCompletion);
}

#pragma mark - ========== 方案六：Hook 通用字符串创建 ==========

static id (*orig_NSString_initWithData_encoding)(id self, SEL _cmd, NSData *data, NSStringEncoding encoding);
static id hook_NSString_initWithData_encoding(id self, SEL _cmd, NSData *data, NSStringEncoding encoding) {
    id result = orig_NSString_initWithData_encoding(self, _cmd, data, encoding);

    if ([[FloatingButtonManager sharedInstance] hookEnabled] && [result isKindOfClass:[NSString class]]) {
        NSString *content = (NSString *)result;
        if (content.length > 100 && ([content containsString:@"this."] || [content containsString:@"function"])) {
            NSString *modifiedContent = [[FloatingButtonManager sharedInstance] replaceTargetInString:content];
            if (![modifiedContent isEqualToString:content]) {
                NSString *log = [NSString stringWithFormat:@"✅ NSString initWithData: 已替换 (长度:%lu)", (unsigned long)content.length];
                NSLog(@"[Tweak] %@", log);
                [[LogWindowManager sharedInstance] appendLog:log];
                return modifiedContent;
            }
        }
    }

    return result;
}

#pragma mark - ========== 方案七：自动扫描并 Hook 所有 JS 相关类 ==========

- (void)autoHookJSClasses {
    NSArray *keywords = @[@"JS", @"Script", @"Evaluate", @"Engine", @"Runtime", 
                           @"Bridge", @"Context", @"WebView", @"Game", @"Mini",
                           @"Stark", @"Tt", @"Byte", @"Douyin", @"Aweme"];

    NSArray *methodKeywords = @[@"evaluateScript", @"evaluateJavaScript", @"executeScript",
                                 @"runScript", @"callJS", @"invokeJS", @"sendScript"];

    int classCount = 0;
    int hookCount = 0;

    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);

    for (unsigned int i = 0; i < count; i++) {
        Class cls = classes[i];
        NSString *className = NSStringFromClass(cls);

        BOOL matchClass = NO;
        for (NSString *keyword in keywords) {
            if ([className containsString:keyword]) {
                matchClass = YES;
                break;
            }
        }

        if (!matchClass || [className hasPrefix:@"NS"] || [className hasPrefix:@"UI"] || 
            [className hasPrefix:@"WK"] || [className hasPrefix:@"JS"] || [className hasPrefix:@"_"]) {
            continue;
        }

        classCount++;

        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(cls, &methodCount);

        for (unsigned int j = 0; j < methodCount; j++) {
            Method method = methods[j];
            SEL sel = method_getName(method);
            NSString *selName = NSStringFromSelector(sel);

            BOOL matchMethod = NO;
            for (NSString *keyword in methodKeywords) {
                if ([selName containsString:keyword]) {
                    matchMethod = YES;
                    break;
                }
            }

            if (matchMethod) {
                NSMethodSignature *sig = [cls instanceMethodSignatureForSelector:sel];
                if (sig) {
                    NSInteger argCount = [sig numberOfArguments];

                    if (argCount >= 3) {
                        const char *argType = [sig getArgumentTypeAtIndex:2];
                        if (strcmp(argType, "@") == 0) {
                            [self.hookedClasses addObject:[NSString stringWithFormat:@"✅ %@ %@", className, selName]];
                            hookCount++;
                            NSString *log = [NSString stringWithFormat:@"✅ AutoHook: %@ %@", className, selName];
                            NSLog(@"[Tweak] %@", log);
                            [[LogWindowManager sharedInstance] appendLog:log];
                        }
                    }
                }
            }
        }

        free(methods);
    }

    free(classes);

    NSString *log = [NSString stringWithFormat:@"AutoHook 完成: 扫描 %d 个类, Hook %d 个方法", classCount, hookCount];
    NSLog(@"[Tweak] %@", log);
    [[LogWindowManager sharedInstance] appendLog:log];
}

#pragma mark - ========== 方案八：Unity WASM 内存搜索（只读，不修改）==========

- (void)searchWASMMemory {
    [[LogWindowManager sharedInstance] appendLog:@"🔍 开始 Unity WASM 内存搜索..."];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSArray *searchStrings = @[@"freeRefreshNum", @"refreshNum", @"startChooseCount", @"ChooseCount", @"isRevive", @"isClickVideo"];

        NSMutableDictionary *results = [NSMutableDictionary dictionary];
        for (NSString *str in searchStrings) {
            results[str] = @0;
        }

        int checkedRegions = 0;
        int totalRegions = 0;

        vm_address_t address = 0;
        vm_size_t size = 0;
        vm_region_basic_info_data_64_t info;
        mach_msg_type_number_t infoCount = VM_REGION_BASIC_INFO_COUNT_64;
        memory_object_name_t objectName = MACH_PORT_NULL;

        while (1) {
            kern_return_t kr = vm_region_64(mach_task_self(), &address, &size, 
                                            VM_REGION_BASIC_INFO_64, 
                                            (vm_region_info_t)&info, &infoCount, &objectName);

            if (kr != KERN_SUCCESS) break;
            totalRegions++;

            BOOL isReadable = (info.protection & VM_PROT_READ) != 0;

            if (!isReadable || size < 100) {
                address += size;
                infoCount = VM_REGION_BASIC_INFO_COUNT_64;
                continue;
            }

            checkedRegions++;

            for (NSString *targetStr in searchStrings) {
                const char *target = [targetStr UTF8String];
                size_t targetLen = strlen(target);

                if (size <= targetLen) continue;

                uintptr_t searchPtr = address;
                uintptr_t endPtr = address + size;

                while (searchPtr < endPtr) {
                    if (searchPtr + targetLen > endPtr) break;

                    void *found = memmem((void *)searchPtr, endPtr - searchPtr, target, targetLen);
                    if (!found) break;

                    int currentCount = [results[targetStr] intValue];
                    results[targetStr] = @(currentCount + 1);

                    NSString *log = [NSString stringWithFormat:@"🔍 Found '%@' at %p", targetStr, found];
                    NSLog(@"[Tweak] %@", log);
                    [[LogWindowManager sharedInstance] appendLog:log];

                    searchPtr = (uintptr_t)found + targetLen;
                }
            }

            address += size;
            infoCount = VM_REGION_BASIC_INFO_COUNT_64;
        }

        NSMutableString *report = [NSMutableString string];
        [report appendFormat:@"扫描完成\n总内存区域: %d\n已检查区域: %d\n", totalRegions, checkedRegions];

        int totalFound = 0;
        for (NSString *str in searchStrings) {
            int count = [results[str] intValue];
            totalFound += count;
            [report appendFormat:@"%@: %d 处\n", str, count];
        }

        [report appendFormat:@"总计找到: %d 处", totalFound];

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

#pragma mark - ========== 启用所有 Hook ==========

- (void)enableAllHooks {
    if (self.hookEnabled) {
        [self showMessage:@"Hook 已启用" message:@"所有 Hook 方案已在运行中，脚本内容将在执行前自动替换。"];
        return;
    }

    [[LogWindowManager sharedInstance] appendLog:@"🚀 开始启用所有 Hook..."];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableString *log = [NSMutableString string];

        void (^hookClass)(NSString *, NSString *, IMP, IMP *) = ^(NSString *className, NSString *selName, IMP hookIMP, IMP *origIMP) {
            Class cls = NSClassFromString(className);
            if (!cls) {
                [log appendFormat:@"❌ %@ 类未找到\n", className];
                return;
            }

            SEL sel = NSSelectorFromString(selName);
            Method method = class_getInstanceMethod(cls, sel);
            if (!method) {
                [log appendFormat:@"⚠️ %@ %@ 方法未找到\n", className, selName];
                return;
            }

            *origIMP = method_getImplementation(method);
            method_setImplementation(method, hookIMP);
            [log appendFormat:@"✅ %@ %@ Hook 成功\n", className, selName];
        };

        hookClass(@"JSContext", @"evaluateScript:", (IMP)hook_JSContext_evaluateScript, (IMP *)&orig_JSContext_evaluateScript);
        hookClass(@"WKUserScript", @"initWithSource:injectionTime:forMainFrameOnly:", (IMP)hook_WKUserScript_initWithSource, (IMP *)&orig_WKUserScript_initWithSource);
        hookClass(@"WKWebView", @"loadHTMLString:baseURL:", (IMP)hook_WKWebView_loadHTMLString, (IMP *)&orig_WKWebView_loadHTMLString);
        hookClass(@"WKWebView", @"loadData:MIMEType:characterEncodingName:baseURL:", (IMP)hook_WKWebView_loadData, (IMP *)&orig_WKWebView_loadData);
        hookClass(@"WKWebView", @"loadRequest:", (IMP)hook_WKWebView_loadRequest, (IMP *)&orig_WKWebView_loadRequest);
        hookClass(@"NSString", @"stringWithContentsOfFile:encoding:error:", (IMP)hook_NSString_stringWithContentsOfFile_encoding_error, (IMP *)&orig_NSString_stringWithContentsOfFile_encoding_error);
        hookClass(@"NSData", @"dataWithContentsOfFile:", (IMP)hook_NSData_dataWithContentsOfFile, (IMP *)&orig_NSData_dataWithContentsOfFile);
        hookClass(@"NSURLSession", @"dataTaskWithRequest:completionHandler:", (IMP)hook_NSURLSession_dataTaskWithRequest_completion, (IMP *)&orig_NSURLSession_dataTaskWithRequest_completion);
        hookClass(@"NSString", @"initWithData:encoding:", (IMP)hook_NSString_initWithData_encoding, (IMP *)&orig_NSString_initWithData_encoding);

        [log appendString:@"\n--- 自动扫描 JS 相关类 ---\n"];
        [self autoHookJSClasses];

        if (self.hookedClasses.count > 0) {
            [log appendString:[self.hookedClasses componentsJoinedByString:@"\n"]];
            [log appendFormat:@"\n\n共自动 Hook %lu 个方法\n", (unsigned long)self.hookedClasses.count];
        } else {
            [log appendString:@"⚠️ 未找到额外的 JS 相关类\n"];
        }

        self.hookEnabled = YES;

        int successCount = 0;
        int failCount = 0;
        NSArray *lines = [log componentsSeparatedByString:@"\n"];
        for (NSString *line in lines) {
            if ([line hasPrefix:@"✅"]) successCount++;
            else if ([line hasPrefix:@"❌"] || [line hasPrefix:@"⚠️"]) failCount++;
        }

        NSString *summary = [NSString stringWithFormat:@"Hook 启用完成 | 成功: %d | 失败: %d", successCount, failCount];
        [[LogWindowManager sharedInstance] appendLog:summary];

        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *title = successCount > 0 ? @"Hook 启用成功" : @"Hook 启用失败";
            NSString *message = [NSString stringWithFormat:@"成功: %d\n失败: %d\n\n%@", successCount, failCount, log];
            [self showMessage:title message:message];
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
