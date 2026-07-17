#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import <WebKit/WebKit.h>
#import <mach/mach.h>
#import <mach/vm_map.h>
#import <sys/mman.h>
#import <libkern/OSCacheControl.h>
#include <dlfcn.h>

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

    [alert addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"修改属性词条免广告刷新次数%@", hookStatus] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self enableAllHooks];
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:@"Unity WASM 内存修改" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self performWASMMemoryPatch];
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

static id (*orig_WKWebView_loadRequest)(id self, SEL _cmd, NSURLRequest *request);
static id hook_WKWebView_loadRequest(id self, SEL _cmd, NSURLRequest *request) {
    if (![[FloatingButtonManager sharedInstance] hookEnabled]) {
        return orig_WKWebView_loadRequest(self, _cmd, request);
    }

    NSLog(@"[Tweak] ℹ️ WKWebView loadRequest: URL=%@", request.URL.absoluteString);
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
                NSLog(@"[Tweak] ✅ NSString stringWithContentsOfFile: 已替换文件内容 | path=%@", path);
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
                    NSLog(@"[Tweak] ✅ NSData dataWithContentsOfFile: 已替换文件内容 | path=%@", path);
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

static id (*orig_NSString_initWithData_encoding)(id self, SEL _cmd, NSData *data, NSStringEncoding encoding);
static id hook_NSString_initWithData_encoding(id self, SEL _cmd, NSData *data, NSStringEncoding encoding) {
    id result = orig_NSString_initWithData_encoding(self, _cmd, data, encoding);

    if ([[FloatingButtonManager sharedInstance] hookEnabled] && [result isKindOfClass:[NSString class]]) {
        NSString *content = (NSString *)result;
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
                            NSLog(@"[Tweak] ✅ AutoHook: %@ %@", className, selName);
                        }
                    }
                }
            }
        }

        free(methods);
    }

    free(classes);

    NSLog(@"[Tweak] AutoHook 完成: 扫描 %d 个类, Hook %d 个方法", classCount, hookCount);
}

#pragma mark - ========== 方案八：Unity WASM 内存修改 ==========

// Unity IL2CPP 编译后，C# 字段在内存中的布局是固定的
// freeRefreshNum 是 int 类型，在内存中占 4 字节
// 我们需要在进程的内存中搜索并修改这个值

- (void)getSelfMemoryRange:(uintptr_t *)start size:(size_t *)size {
    *start = 0;
    *size = 0;

    Dl_info info;
    if (dladdr((__bridge void *)[self class], &info)) {
        *start = (uintptr_t)info.dli_fbase;
        *size = 0x10000;
    }
}

- (BOOL)safeMemoryReplace:(void *)addr target:(const char *)targetStr targetLen:(size_t)targetLen newStr:(const char *)newStr newLen:(size_t)newLen {
    if (!addr || !targetStr || !newStr) return NO;
    if (targetLen == 0 || newLen == 0) return NO;

    if (memcmp(addr, targetStr, targetLen) != 0) return NO;

    kern_return_t kr = vm_write(mach_task_self(), 
                                (vm_address_t)addr, 
                                (vm_offset_t)newStr, 
                                (mach_msg_type_number_t)newLen);

    if (kr == KERN_SUCCESS) {
        sys_icache_invalidate(addr, newLen);
        return YES;
    }

    return NO;
}

- (void)performWASMMemoryPatch {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Unity WASM 中，freeRefreshNum 相关的字符串特征（可能被 IL2CPP 元数据引用）
        const char *targetStr = "freeRefreshNum";
        const char *newStr = "freeRefreshNum"; // 占位，实际修改内存中的数值

        size_t targetLen = strlen(targetStr);
        int foundCount = 0;
        int modifiedCount = 0;
        int checkedRegions = 0;

        uintptr_t selfStart = 0;
        size_t selfSize = 0;
        [self getSelfMemoryRange:&selfStart size:&selfSize];

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

            checkedRegions++;

            if (selfStart > 0 && address >= selfStart && address < selfStart + selfSize) {
                address += size;
                infoCount = VM_REGION_BASIC_INFO_COUNT_64;
                continue;
            }

            BOOL isWritable = (info.protection & VM_PROT_WRITE) != 0;
            BOOL isReadable = (info.protection & VM_PROT_READ) != 0;

            if (!isReadable || !isWritable) {
                address += size;
                infoCount = VM_REGION_BASIC_INFO_COUNT_64;
                continue;
            }

            if (size <= targetLen) {
                address += size;
                infoCount = VM_REGION_BASIC_INFO_COUNT_64;
                continue;
            }

            if (info.shared) {
                address += size;
                infoCount = VM_REGION_BASIC_INFO_COUNT_64;
                continue;
            }

            // 搜索 freeRefreshNum 字符串
            uintptr_t searchPtr = address;
            uintptr_t endPtr = address + size;

            while (searchPtr < endPtr) {
                if (searchPtr + targetLen > endPtr) break;

                void *found = memmem((void *)searchPtr, endPtr - searchPtr, targetStr, targetLen);
                if (!found) break;

                foundCount++;

                // 在找到字符串的附近搜索数值 2 或 0（int32）
                // IL2CPP 中，字段名后面通常跟着字段偏移或默认值
                // 这里我们尝试在前后 64 字节内搜索 0x02 0x00 0x00 0x00 或 0x00 0x00 0x00 0x00
                uint8_t *base = (uint8_t *)found;
                for (int offset = -64; offset <= 64; offset += 4) {
                    uint8_t *checkAddr = base + offset;
                    if (checkAddr < (uint8_t *)address || checkAddr >= (uint8_t *)endPtr) continue;

                    // 检查是否是 int32 的 2
                    if (checkAddr[0] == 0x02 && checkAddr[1] == 0x00 && checkAddr[2] == 0x00 && checkAddr[3] == 0x00) {
                        // 修改为 100 (0x64)
                        uint8_t newValue[4] = {0x64, 0x00, 0x00, 0x00};
                        kern_return_t writeKr = vm_write(mach_task_self(), 
                                                        (vm_address_t)checkAddr, 
                                                        (vm_offset_t)newValue, 
                                                        4);
                        if (writeKr == KERN_SUCCESS) {
                            modifiedCount++;
                            NSLog(@"[Tweak] ✅ WASM Memory: 修改 freeRefreshNum 附近数值 at offset %d", offset);
                        }
                    }
                }

                searchPtr = (uintptr_t)found + targetLen;
            }

            address += size;
            infoCount = VM_REGION_BASIC_INFO_COUNT_64;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (modifiedCount > 0) {
                [self showMessage:@"WASM 内存修改成功" message:[NSString stringWithFormat:@"找到 %d 处 freeRefreshNum，修改 %d 处数值\n（检查 %d 个内存区域）", foundCount, modifiedCount, checkedRegions]];
            } else if (foundCount > 0) {
                [self showMessage:@"WASM 内存部分成功" message:[NSString stringWithFormat:@"找到 %d 处 freeRefreshNum，但未修改数值\n可能数值不在附近，需要进一步分析", foundCount]];
            } else {
                [self showMessage:@"WASM 内存修改失败" message:[NSString stringWithFormat:@"未找到 freeRefreshNum 字符串\n检查 %d 个内存区域\n可能字符串被混淆或存储在只读段", checkedRegions]];
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
