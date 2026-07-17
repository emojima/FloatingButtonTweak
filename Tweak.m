#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import <WebKit/WebKit.h>

@interface FloatingButtonManager : NSObject
@property (nonatomic, strong) UIButton *floatingButton;
@property (nonatomic, strong) NSTimer *keepOnTopTimer;
@property (nonatomic, weak) UIWindow *lastWindow;
@property (nonatomic, assign) BOOL hookEnabled;
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

    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"修改属性词条免广告刷新次数%@", hookStatus] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self enableAllHooks];
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

#pragma mark - ========== 字符串替换工具 ==========

- (NSString *)replaceTargetInString:(NSString *)string {
    if (!string || string.length == 0) return string;

    NSString *modified = string;

    // 原始目标字符串
    modified = [modified stringByReplacingOccurrencesOfString:
        @".curLevel)?this.freeRefreshNum=2:this.freeRefreshNum=0"
        withString:@".curLevel),this.refreshNum=100,this.freeRefreshNum=100"];

    // 可能的变体 1：空格差异
    modified = [modified stringByReplacingOccurrencesOfString:
        @".curLevel) ? this.freeRefreshNum = 2 : this.freeRefreshNum = 0"
        withString:@".curLevel), this.refreshNum = 100, this.freeRefreshNum = 100"];

    // 可能的变体 2：压缩后无空格
    modified = [modified stringByReplacingOccurrencesOfString:
        @"curLevel)?this.freeRefreshNum=2:this.freeRefreshNum=0"
        withString:@"curLevel),this.refreshNum=100,this.freeRefreshNum=100"];

    // 可能的变体 3：使用单引号
    modified = [modified stringByReplacingOccurrencesOfString:
        @".curLevel'?this.freeRefreshNum=2:this.freeRefreshNum=0"
        withString:@".curLevel'),this.refreshNum=100,this.freeRefreshNum=100"];

    // 可能的变体 4：部分匹配（只匹配关键逻辑）
    modified = [modified stringByReplacingOccurrencesOfString:
        @"this.freeRefreshNum=2:this.freeRefreshNum=0"
        withString:@"this.refreshNum=100,this.freeRefreshNum=100"];

    // 可能的变体 5：使用 var/let/const 声明
    modified = [modified stringByReplacingOccurrencesOfString:
        @"this.freeRefreshNum=2:this.freeRefreshNum=0"
        withString:@"this.refreshNum=100,this.freeRefreshNum=100"];

    // 可能的变体 6：三元运算符不同写法
    modified = [modified stringByReplacingOccurrencesOfString:
        @"?this.freeRefreshNum=2:this.freeRefreshNum=0"
        withString:@",this.refreshNum=100,this.freeRefreshNum=100"];

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
    }

    return orig_WKUserScript_initWithSource(self, _cmd, modifiedSource, injectionTime, forMainFrameOnly);
}

#pragma mark - ========== 方案三：Hook WKWebView 加载方法 ==========

// Hook loadHTMLString
static id (*orig_WKWebView_loadHTMLString)(id self, SEL _cmd, NSString *string, NSURL *baseURL);
static id hook_WKWebView_loadHTMLString(id self, SEL _cmd, NSString *string, NSURL *baseURL) {
    if (![[FloatingButtonManager sharedInstance] hookEnabled]) {
        return orig_WKWebView_loadHTMLString(self, _cmd, string, baseURL);
    }

    NSString *modifiedString = [[FloatingButtonManager sharedInstance] replaceTargetInString:string];

    if (![modifiedString isEqualToString:string]) {
        NSLog(@"[Tweak] ✅ WKWebView loadHTMLString: 已替换目标字符串");
    }

    return orig_WKWebView_loadHTMLString(self, _cmd, modifiedString, baseURL);
}

// Hook loadData
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
                data = [modifiedContent dataUsingEncoding:NSUTF8StringEncoding];
            }
        }
    }

    return orig_WKWebView_loadData(self, _cmd, data, MIMEType, characterEncodingName, baseURL);
}

// Hook loadRequest
static id (*orig_WKWebView_loadRequest)(id self, SEL _cmd, NSURLRequest *request);
static id hook_WKWebView_loadRequest(id self, SEL _cmd, NSURLRequest *request) {
    if (![[FloatingButtonManager sharedInstance] hookEnabled]) {
        return orig_WKWebView_loadRequest(self, _cmd, request);
    }

    NSLog(@"[Tweak] ℹ️ WKWebView loadRequest: URL=%@", request.URL.absoluteString);
    return orig_WKWebView_loadRequest(self, _cmd, request);
}

#pragma mark - ========== 方案四：Hook 文件读取 ==========

// Hook NSString stringWithContentsOfFile
static id (*orig_NSString_stringWithContentsOfFile_encoding_error)(id self, SEL _cmd, NSString *path, NSStringEncoding enc, NSError **error);
static id hook_NSString_stringWithContentsOfFile_encoding_error(id self, SEL _cmd, NSString *path, NSStringEncoding enc, NSError **error) {
    id result = orig_NSString_stringWithContentsOfFile_encoding_error(self, _cmd, path, enc, error);

    if ([[FloatingButtonManager sharedInstance] hookEnabled] && [result isKindOfClass:[NSString class]]) {
        NSString *content = (NSString *)result;
        // 只处理 JS/HTML 相关文件
        if ([path hasSuffix:@".js"] || [path hasSuffix:@".html"] || [path hasSuffix:@".htm"] || [path containsString:@"javascript"] || [path containsString:@"script"]) {
            NSString *modifiedContent = [[FloatingButtonManager sharedInstance] replaceTargetInString:content];
            if (![modifiedContent isEqualToString:content]) {
                NSLog(@"[Tweak] ✅ NSString stringWithContentsOfFile: 已替换文件内容 | path=%@", path);
                return modifiedContent;
            }
        }
    }

    return result;
}

// Hook NSData dataWithContentsOfFile
static id (*orig_NSData_dataWithContentsOfFile)(id self, SEL _cmd, NSString *path);
static id hook_NSData_dataWithContentsOfFile(id self, SEL _cmd, NSString *path) {
    id result = orig_NSData_dataWithContentsOfFile(self, _cmd, path);

    if ([[FloatingButtonManager sharedInstance] hookEnabled] && [result isKindOfClass:[NSData class]]) {
        // 只处理 JS 相关文件
        if ([path hasSuffix:@".js"] || [path containsString:@"javascript"] || [path containsString:@"script"]) {
            NSString *content = [[NSString alloc] initWithData:(NSData *)result encoding:NSUTF8StringEncoding];
            if (content) {
                NSString *modifiedContent = [[FloatingButtonManager sharedInstance] replaceTargetInString:content];
                if (![modifiedContent isEqualToString:content]) {
                    NSLog(@"[Tweak] ✅ NSData dataWithContentsOfFile: 已替换文件内容 | path=%@", path);
                    return [modifiedContent dataUsingEncoding:NSUTF8StringEncoding];
                }
            }
        }
    }

    return result;
}

#pragma mark - ========== 方案五：Hook 网络请求 ==========

// Hook NSURLSession dataTaskWithRequest
static id (*orig_NSURLSession_dataTaskWithRequest_completion)(id self, SEL _cmd, NSURLRequest *request, id completionHandler);
static id hook_NSURLSession_dataTaskWithRequest_completion(id self, SEL _cmd, NSURLRequest *request, id completionHandler) {
    if (![[FloatingButtonManager sharedInstance] hookEnabled]) {
        return orig_NSURLSession_dataTaskWithRequest_completion(self, _cmd, request, completionHandler);
    }

    // 包装 completionHandler 来修改响应数据
    id modifiedCompletion = completionHandler;
    if (completionHandler) {
        modifiedCompletion = ^(NSData *data, NSURLResponse *response, NSError *error) {
            NSData *modifiedData = data;
            if (data && [response isKindOfClass:[NSHTTPURLResponse class]]) {
                NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
                NSString *contentType = httpResponse.allHeaderFields[@"Content-Type"];
                NSString *urlString = request.URL.absoluteString;

                // 检查是否是 JS 相关内容
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
                            NSLog(@"[Tweak] ✅ NSURLSession: 已替换网络响应数据 | URL=%@", urlString);
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

// Hook NSString initWithData
static id (*orig_NSString_initWithData_encoding)(id self, SEL _cmd, NSData *data, NSStringEncoding encoding);
static id hook_NSString_initWithData_encoding(id self, SEL _cmd, NSData *data, NSStringEncoding encoding) {
    id result = orig_NSString_initWithData_encoding(self, _cmd, data, encoding);

    if ([[FloatingButtonManager sharedInstance] hookEnabled] && [result isKindOfClass:[NSString class]]) {
        NSString *content = (NSString *)result;
        // 如果内容较长且包含 JS 特征，尝试替换
        if (content.length > 100 && ([content containsString:@"this."] || [content containsString:@"function"])) {
            NSString *modifiedContent = [[FloatingButtonManager sharedInstance] replaceTargetInString:content];
            if (![modifiedContent isEqualToString:content]) {
                NSLog(@"[Tweak] ✅ NSString initWithData: 已替换目标字符串 (长度:%lu)", (unsigned long)content.length);
                return modifiedContent;
            }
        }
    }

    return result;
}

#pragma mark - ========== 方案七：抖音小程序小游戏专用 Hook ==========

// 抖音小程序使用自研 JS 引擎（基于 V8/JSC 封装），常见类名如下：
// - BDJSContext / TTJSContext / AwemeJSContext
// - BDWebView / TTWebView / AwemeWebView
// - BDJSBridge / TTJSBridge / AwemeJSBridge
// - TTGameEngine / TTGameRuntime

// Hook 抖音 JS 引擎执行方法
static id (*orig_BDJSContext_evaluateScript)(id self, SEL _cmd, NSString *script);
static id hook_BDJSContext_evaluateScript(id self, SEL _cmd, NSString *script) {
    if (![[FloatingButtonManager sharedInstance] hookEnabled]) {
        return orig_BDJSContext_evaluateScript(self, _cmd, script);
    }

    NSString *modifiedScript = [[FloatingButtonManager sharedInstance] replaceTargetInString:script];

    if (![modifiedScript isEqualToString:script]) {
        NSLog(@"[Tweak] ✅ BDJSContext evaluateScript: 已替换目标字符串");
    }

    return orig_BDJSContext_evaluateScript(self, _cmd, modifiedScript);
}

static id (*orig_TTJSContext_evaluateScript)(id self, SEL _cmd, NSString *script);
static id hook_TTJSContext_evaluateScript(id self, SEL _cmd, NSString *script) {
    if (![[FloatingButtonManager sharedInstance] hookEnabled]) {
        return orig_TTJSContext_evaluateScript(self, _cmd, script);
    }

    NSString *modifiedScript = [[FloatingButtonManager sharedInstance] replaceTargetInString:script];

    if (![modifiedScript isEqualToString:script]) {
        NSLog(@"[Tweak] ✅ TTJSContext evaluateScript: 已替换目标字符串");
    }

    return orig_TTJSContext_evaluateScript(self, _cmd, modifiedScript);
}

static id (*orig_AwemeJSContext_evaluateScript)(id self, SEL _cmd, NSString *script);
static id hook_AwemeJSContext_evaluateScript(id self, SEL _cmd, NSString *script) {
    if (![[FloatingButtonManager sharedInstance] hookEnabled]) {
        return orig_AwemeJSContext_evaluateScript(self, _cmd, script);
    }

    NSString *modifiedScript = [[FloatingButtonManager sharedInstance] replaceTargetInString:script];

    if (![modifiedScript isEqualToString:script]) {
        NSLog(@"[Tweak] ✅ AwemeJSContext evaluateScript: 已替换目标字符串");
    }

    return orig_AwemeJSContext_evaluateScript(self, _cmd, modifiedScript);
}

// Hook 抖音 JSBridge 通信
static id (*orig_TTJSBridge_callJS)(id self, SEL _cmd, NSString *method, id params);
static id hook_TTJSBridge_callJS(id self, SEL _cmd, NSString *method, id params) {
    if (![[FloatingButtonManager sharedInstance] hookEnabled]) {
        return orig_TTJSBridge_callJS(self, _cmd, method, params);
    }

    // 如果参数是字符串（JS 代码），尝试替换
    if ([params isKindOfClass:[NSString class]]) {
        NSString *modifiedParams = [[FloatingButtonManager sharedInstance] replaceTargetInString:(NSString *)params];
        if (![modifiedParams isEqualToString:(NSString *)params]) {
            NSLog(@"[Tweak] ✅ TTJSBridge callJS: 已替换目标字符串 | method=%@", method);
            return orig_TTJSBridge_callJS(self, _cmd, method, modifiedParams);
        }
    }

    return orig_TTJSBridge_callJS(self, _cmd, method, params);
}

static id (*orig_BDJSBridge_callJS)(id self, SEL _cmd, NSString *method, id params);
static id hook_BDJSBridge_callJS(id self, SEL _cmd, NSString *method, id params) {
    if (![[FloatingButtonManager sharedInstance] hookEnabled]) {
        return orig_BDJSBridge_callJS(self, _cmd, method, params);
    }

    if ([params isKindOfClass:[NSString class]]) {
        NSString *modifiedParams = [[FloatingButtonManager sharedInstance] replaceTargetInString:(NSString *)params];
        if (![modifiedParams isEqualToString:(NSString *)params]) {
            NSLog(@"[Tweak] ✅ BDJSBridge callJS: 已替换目标字符串 | method=%@", method);
            return orig_BDJSBridge_callJS(self, _cmd, method, modifiedParams);
        }
    }

    return orig_BDJSBridge_callJS(self, _cmd, method, params);
}

// Hook 抖音小游戏引擎
static id (*orig_TTGameEngine_evaluateScript)(id self, SEL _cmd, NSString *script);
static id hook_TTGameEngine_evaluateScript(id self, SEL _cmd, NSString *script) {
    if (![[FloatingButtonManager sharedInstance] hookEnabled]) {
        return orig_TTGameEngine_evaluateScript(self, _cmd, script);
    }

    NSString *modifiedScript = [[FloatingButtonManager sharedInstance] replaceTargetInString:script];

    if (![modifiedScript isEqualToString:script]) {
        NSLog(@"[Tweak] ✅ TTGameEngine evaluateScript: 已替换目标字符串");
    }

    return orig_TTGameEngine_evaluateScript(self, _cmd, modifiedScript);
}

static id (*orig_TTGameRuntime_evaluateScript)(id self, SEL _cmd, NSString *script);
static id hook_TTGameRuntime_evaluateScript(id self, SEL _cmd, NSString *script) {
    if (![[FloatingButtonManager sharedInstance] hookEnabled]) {
        return orig_TTGameRuntime_evaluateScript(self, _cmd, script);
    }

    NSString *modifiedScript = [[FloatingButtonManager sharedInstance] replaceTargetInString:script];

    if (![modifiedScript isEqualToString:script]) {
        NSLog(@"[Tweak] ✅ TTGameRuntime evaluateScript: 已替换目标字符串");
    }

    return orig_TTGameRuntime_evaluateScript(self, _cmd, modifiedScript);
}

// Hook 抖音 WebView 加载
static id (*orig_TTWebView_loadRequest)(id self, SEL _cmd, NSURLRequest *request);
static id hook_TTWebView_loadRequest(id self, SEL _cmd, NSURLRequest *request) {
    if (![[FloatingButtonManager sharedInstance] hookEnabled]) {
        return orig_TTWebView_loadRequest(self, _cmd, request);
    }

    NSLog(@"[Tweak] ℹ️ TTWebView loadRequest: URL=%@", request.URL.absoluteString);
    return orig_TTWebView_loadRequest(self, _cmd, request);
}

static id (*orig_BDWebView_loadRequest)(id self, SEL _cmd, NSURLRequest *request);
static id hook_BDWebView_loadRequest(id self, SEL _cmd, NSURLRequest *request) {
    if (![[FloatingButtonManager sharedInstance] hookEnabled]) {
        return orig_BDWebView_loadRequest(self, _cmd, request);
    }

    NSLog(@"[Tweak] ℹ️ BDWebView loadRequest: URL=%@", request.URL.absoluteString);
    return orig_BDWebView_loadRequest(self, _cmd, request);
}

static id (*orig_AwemeWebView_loadRequest)(id self, SEL _cmd, NSURLRequest *request);
static id hook_AwemeWebView_loadRequest(id self, SEL _cmd, NSURLRequest *request) {
    if (![[FloatingButtonManager sharedInstance] hookEnabled]) {
        return orig_AwemeWebView_loadRequest(self, _cmd, request);
    }

    NSLog(@"[Tweak] ℹ️ AwemeWebView loadRequest: URL=%@", request.URL.absoluteString);
    return orig_AwemeWebView_loadRequest(self, _cmd, request);
}

#pragma mark - ========== 启用所有 Hook ==========

- (void)enableAllHooks {
    if (self.hookEnabled) {
        [self showMessage:@"Hook 已启用" message:@"所有 Hook 方案已在运行中，脚本内容将在执行前自动替换。"];
        return;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableString *log = [NSMutableString string];
        int successCount = 0;
        int failCount = 0;

        // 辅助 Hook 函数 - 使用 __block 修饰局部变量
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

        // 方案一：JSContext
        hookClass(@"JSContext", @"evaluateScript:", (IMP)hook_JSContext_evaluateScript, (IMP *)&orig_JSContext_evaluateScript);

        // 方案二：WKUserScript
        hookClass(@"WKUserScript", @"initWithSource:injectionTime:forMainFrameOnly:", (IMP)hook_WKUserScript_initWithSource, (IMP *)&orig_WKUserScript_initWithSource);

        // 方案三：WKWebView
        hookClass(@"WKWebView", @"loadHTMLString:baseURL:", (IMP)hook_WKWebView_loadHTMLString, (IMP *)&orig_WKWebView_loadHTMLString);
        hookClass(@"WKWebView", @"loadData:MIMEType:characterEncodingName:baseURL:", (IMP)hook_WKWebView_loadData, (IMP *)&orig_WKWebView_loadData);
        hookClass(@"WKWebView", @"loadRequest:", (IMP)hook_WKWebView_loadRequest, (IMP *)&orig_WKWebView_loadRequest);

        // 方案四：NSString / NSData 文件读取
        hookClass(@"NSString", @"stringWithContentsOfFile:encoding:error:", (IMP)hook_NSString_stringWithContentsOfFile_encoding_error, (IMP *)&orig_NSString_stringWithContentsOfFile_encoding_error);
        hookClass(@"NSData", @"dataWithContentsOfFile:", (IMP)hook_NSData_dataWithContentsOfFile, (IMP *)&orig_NSData_dataWithContentsOfFile);

        // 方案五：NSURLSession
        hookClass(@"NSURLSession", @"dataTaskWithRequest:completionHandler:", (IMP)hook_NSURLSession_dataTaskWithRequest_completion, (IMP *)&orig_NSURLSession_dataTaskWithRequest_completion);

        // 方案六：NSString initWithData
        hookClass(@"NSString", @"initWithData:encoding:", (IMP)hook_NSString_initWithData_encoding, (IMP *)&orig_NSString_initWithData_encoding);

        // 方案七：抖音小程序专用
        // 抖音 JS 引擎
        hookClass(@"BDJSContext", @"evaluateScript:", (IMP)hook_BDJSContext_evaluateScript, (IMP *)&orig_BDJSContext_evaluateScript);
        hookClass(@"TTJSContext", @"evaluateScript:", (IMP)hook_TTJSContext_evaluateScript, (IMP *)&orig_TTJSContext_evaluateScript);
        hookClass(@"AwemeJSContext", @"evaluateScript:", (IMP)hook_AwemeJSContext_evaluateScript, (IMP *)&orig_AwemeJSContext_evaluateScript);

        // 抖音 JSBridge
        hookClass(@"TTJSBridge", @"callJS:params:", (IMP)hook_TTJSBridge_callJS, (IMP *)&orig_TTJSBridge_callJS);
        hookClass(@"BDJSBridge", @"callJS:params:", (IMP)hook_BDJSBridge_callJS, (IMP *)&orig_BDJSBridge_callJS);

        // 抖音小游戏引擎
        hookClass(@"TTGameEngine", @"evaluateScript:", (IMP)hook_TTGameEngine_evaluateScript, (IMP *)&orig_TTGameEngine_evaluateScript);
        hookClass(@"TTGameRuntime", @"evaluateScript:", (IMP)hook_TTGameRuntime_evaluateScript, (IMP *)&orig_TTGameRuntime_evaluateScript);

        // 抖音 WebView
        hookClass(@"TTWebView", @"loadRequest:", (IMP)hook_TTWebView_loadRequest, (IMP *)&orig_TTWebView_loadRequest);
        hookClass(@"BDWebView", @"loadRequest:", (IMP)hook_BDWebView_loadRequest, (IMP *)&orig_BDWebView_loadRequest);
        hookClass(@"AwemeWebView", @"loadRequest:", (IMP)hook_AwemeWebView_loadRequest, (IMP *)&orig_AwemeWebView_loadRequest);

        // 统计成功/失败数量
        NSArray *lines = [log componentsSeparatedByString:@"\n"];
        for (NSString *line in lines) {
            if ([line hasPrefix:@"✅"]) successCount++;
            else if ([line hasPrefix:@"❌"] || [line hasPrefix:@"⚠️"]) failCount++;
        }

        self.hookEnabled = YES;

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
