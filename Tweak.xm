#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/loader.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>
#import <mach/vm_map.h>
#import <sys/mman.h>
#import <libkern/OSCacheControl.h>

// ========== 悬浮按钮管理器 ==========
@interface FloatingButtonManager : NSObject
@property (nonatomic, strong) UIButton *floatingButton;
@property (nonatomic, strong) NSTimer *keepOnTopTimer;
@property (nonatomic, weak) UIWindow *lastWindow;
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
    
    // 启动定时器，确保按钮始终在最上层
    [self startKeepOnTopTimer];
}

// 定时检测并确保按钮在最上层
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
    
    // 如果窗口变了，把按钮移到新窗口
    if (self.floatingButton.superview != topWindow) {
        CGRect oldFrame = self.floatingButton.frame;
        [self.floatingButton removeFromSuperview];
        [topWindow addSubview:self.floatingButton];
        self.floatingButton.frame = oldFrame;
        self.lastWindow = topWindow;
    }
    
    // 确保在当前窗口的最上层
    [topWindow bringSubviewToFront:self.floatingButton];
}

// 获取最上层的 UIWindow（包括小程序/webview 创建的窗口）
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
    
    // 找到 windowLevel 最高的可见窗口
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
    
    [alert addAction:[UIAlertAction actionWithTitle:@"修改属性词条免广告刷新次数" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self performMemoryPatch];
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

// ========== 内存修改功能一 ==========
- (void)performMemoryPatch {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        const char *targetStr = ".curLevel)?this.freeRefreshNum=2:this.freeRefreshNum=0,this.startChooseCount=0,this.ChooseCount=0,this.isRevive=!1,this.isClickVideo=!1,this.needShowIdList=null";
        const char *newStr = ".curLevel),this.refreshNum=100,this.freeRefreshNum=100,this.startChooseCount=0,this.ChooseCount=0,this.isRevive=!1,this.isClickVideo=!1,this.needShowIdList=null";
        
        size_t targetLen = strlen(targetStr);
        size_t newLen = strlen(newStr);
        int replaceCount = 0;
        
        const struct mach_header_64 *header = (const struct mach_header_64 *)_dyld_get_image_header(0);
        if (!header) {
            [self showMessage:@"修改失败" message:@"无法获取主二进制信息"];
            return;
        }
        
        uintptr_t slide = _dyld_get_image_vmaddr_slide(0);
        uintptr_t cmdPtr = (uintptr_t)header + sizeof(struct mach_header_64);
        
        for (uint32_t i = 0; i < header->ncmds; i++) {
            struct load_command *cmd = (struct load_command *)cmdPtr;
            
            if (cmd->cmd == LC_SEGMENT_64) {
                struct segment_command_64 *seg = (struct segment_command_64 *)cmd;
                
                if ((seg->initprot & VM_PROT_READ) != 0) {
                    uintptr_t segStart = seg->vmaddr + slide;
                    uintptr_t segEnd = segStart + seg->vmsize;
                    uintptr_t searchPtr = segStart;
                    
                    while (searchPtr < segEnd) {
                        void *found = memmem((void *)searchPtr, segEnd - searchPtr, targetStr, targetLen);
                        if (!found) break;
                        
                        void *addr = found;
                        size_t pageSize = getpagesize();
                        uintptr_t pageStart = ((uintptr_t)addr / pageSize) * pageSize;
                        size_t pageOffset = (uintptr_t)addr - pageStart;
                        
                        int result = mprotect((void *)pageStart, pageOffset + newLen, PROT_READ | PROT_WRITE);
                        if (result != 0) {
                            kern_return_t kr = vm_protect(mach_task_self(), pageStart, pageOffset + newLen, false, VM_PROT_READ | VM_PROT_COPY | VM_PROT_WRITE);
                            if (kr != KERN_SUCCESS) {
                                searchPtr = (uintptr_t)found + 1;
                                continue;
                            }
                        }
                        
                        memcpy(addr, newStr, newLen);
                        mprotect((void *)pageStart, pageOffset + newLen, PROT_READ);
                        sys_icache_invalidate(addr, newLen);
                        
                        replaceCount++;
                        searchPtr = (uintptr_t)found + targetLen;
                    }
                }
            }
            cmdPtr += cmd->cmdsize;
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (replaceCount > 0) {
                [self showMessage:@"修改成功" message:[NSString stringWithFormat:@"成功修改了 %d 处目标字符串", replaceCount]];
            } else {
                [self showMessage:@"修改失败" message:@"未找到目标字符串，可能游戏版本已更新或字符串已变更"];
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
    CGPoint translation = [gestue translationInView:button.superview];
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

// ========== 构造函数 ==========
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
