#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach/mach.h>
#import <mach/vm_map.h>
#import <sys/mman.h>
#import <libkern/OSCacheControl.h>
#include <dlfcn.h>
#include <signal.h>
#include <setjmp.h>

static sigjmp_buf jump_buffer;
static volatile sig_atomic_t can_jump = 0;

// Signal handler for SIGBUS/SIGSEGV
static void signal_handler(int sig) {
    if (can_jump) {
        can_jump = 0;
        siglongjmp(jump_buffer, 1);
    }
    // Re-raise if we can't handle it
    signal(sig, SIG_DFL);
    raise(sig);
}

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

// ========== 获取自身 dylib 的内存范围 ==========
- (void)getSelfMemoryRange:(uintptr_t *)start size:(size_t *)size {
    *start = 0;
    *size = 0;

    Dl_info info;
    if (dladdr((__bridge void *)[self class], &info)) {
        *start = (uintptr_t)info.dli_fbase;
        // 估算大小为 64KB，足够覆盖 dylib
        *size = 0x10000;
    }
}

// ========== 安全的内存修改（带信号保护）==========
- (BOOL)safeMemoryReplace:(void *)addr target:(const char *)targetStr targetLen:(size_t)targetLen newStr:(const char *)newStr newLen:(size_t)newLen {
    if (!addr || !targetStr || !newStr) return NO;
    if (targetLen == 0 || newLen == 0) return NO;

    size_t pageSize = getpagesize();

    uintptr_t addrStart = (uintptr_t)addr;
    uintptr_t addrEnd = addrStart + newLen;

    uintptr_t pageStart = (addrStart / pageSize) * pageSize;
    uintptr_t pageEnd = ((addrEnd + pageSize - 1) / pageSize) * pageSize;
    size_t protectSize = pageEnd - pageStart;

    // 设置信号处理
    void (*old_sigbus)(int) = signal(SIGBUS, signal_handler);
    void (*old_sigsegv)(int) = signal(SIGSEGV, signal_handler);

    BOOL success = NO;

    if (sigsetjmp(jump_buffer, 1) == 0) {
        can_jump = 1;

        // 修改权限为可读写
        int result = mprotect((void *)pageStart, protectSize, PROT_READ | PROT_WRITE);
        if (result != 0) {
            kern_return_t kr = vm_protect(mach_task_self(), pageStart, protectSize, false, 
                                          VM_PROT_READ | VM_PROT_COPY | VM_PROT_WRITE);
            if (kr != KERN_SUCCESS) {
                can_jump = 0;
                signal(SIGBUS, old_sigbus);
                signal(SIGSEGV, old_sigsegv);
                return NO;
            }
        }

        // 复制新字符串
        memcpy(addr, newStr, newLen);

        // 恢复只读权限
        mprotect((void *)pageStart, protectSize, PROT_READ);

        // 刷新指令缓存
        sys_icache_invalidate(addr, newLen);

        success = YES;
    } else {
        // 信号被捕获，操作失败
        success = NO;
    }

    can_jump = 0;
    signal(SIGBUS, old_sigbus);
    signal(SIGSEGV, old_sigsegv);

    return success;
}

// ========== 使用 vm_region 安全搜索内存 ==========
- (void)performMemoryPatch {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        const char *targetStr = ".curLevel)?this.freeRefreshNum=2:this.freeRefreshNum=0,this.startChooseCount=0,this.ChooseCount=0,this.isRevive=!1,this.isClickVideo=!1,this.needShowIdList=null";
        const char *newStr = ".curLevel),this.refreshNum=100,this.freeRefreshNum=100,this.startChooseCount=0,this.ChooseCount=0,this.isRevive=!1,this.isClickVideo=!1,this.needShowIdList=null";

        size_t targetLen = strlen(targetStr);
        size_t newLen = strlen(newStr);
        int replaceCount = 0;
        int checkedRegions = 0;

        // 获取自身 dylib 的内存范围
        uintptr_t selfStart = 0;
        size_t selfSize = 0;
        [self getSelfMemoryRange:&selfStart size:&selfSize];

        vm_address_t address = 0;
        vm_size_t size = 0;
        vm_region_basic_info_data_64_t info;
        mach_msg_type_number_t infoCount = VM_REGION_BASIC_INFO_COUNT_64;
        memory_object_name_t objectName = MACH_PORT_NULL;

        // 设置信号处理
        void (*old_sigbus)(int) = signal(SIGBUS, signal_handler);
        void (*old_sigsegv)(int) = signal(SIGSEGV, signal_handler);

        while (1) {
            kern_return_t kr = vm_region_64(mach_task_self(), &address, &size, 
                                            VM_REGION_BASIC_INFO_64, 
                                            (vm_region_info_t)&info, &infoCount, &objectName);

            if (kr != KERN_SUCCESS) break;

            checkedRegions++;

            // 跳过自身 dylib 的内存区域
            if (selfStart > 0 && address >= selfStart && address < selfStart + selfSize) {
                address += size;
                infoCount = VM_REGION_BASIC_INFO_COUNT_64;
                continue;
            }

            // 只搜索可读且可写的内存区域（排除 __TEXT 等只读段）
            // 同时也允许 VM_PROT_COPY（写时复制）
            BOOL isWritable = (info.protection & VM_PROT_WRITE) != 0;
            BOOL isReadable = (info.protection & VM_PROT_READ) != 0;
            BOOL isCopyOnWrite = (info.max_protection & VM_PROT_COPY) != 0;

            if (!isReadable || (!isWritable && !isCopyOnWrite)) {
                address += size;
                infoCount = VM_REGION_BASIC_INFO_COUNT_64;
                continue;
            }

            // 跳过过小的区域
            if (size <= targetLen) {
                address += size;
                infoCount = VM_REGION_BASIC_INFO_COUNT_64;
                continue;
            }

            // 安全搜索该区域
            uintptr_t searchPtr = address;
            uintptr_t endPtr = address + size;

            while (searchPtr < endPtr) {
                if (searchPtr + targetLen > endPtr) break;

                void *found = NULL;

                // 使用信号保护 memmem
                if (sigsetjmp(jump_buffer, 1) == 0) {
                    can_jump = 1;
                    found = memmem((void *)searchPtr, endPtr - searchPtr, targetStr, targetLen);
                    can_jump = 0;
                } else {
                    // 访问该区域导致信号，跳过
                    can_jump = 0;
                    break;
                }

                if (!found) break;

                // 执行替换
                if ([self safeMemoryReplace:found target:targetStr targetLen:targetLen newStr:newStr newLen:newLen]) {
                    replaceCount++;
                }

                searchPtr = (uintptr_t)found + targetLen;
            }

            address += size;
            infoCount = VM_REGION_BASIC_INFO_COUNT_64;
        }

        signal(SIGBUS, old_sigbus);
        signal(SIGSEGV, old_sigsegv);

        dispatch_async(dispatch_get_main_queue(), ^{
            if (replaceCount > 0) {
                [self showMessage:@"修改成功" message:[NSString stringWithFormat:@"成功修改了 %d 处目标字符串（检查了 %d 个内存区域）", replaceCount, checkedRegions]];
            } else {
                [self showMessage:@"修改失败" message:[NSString stringWithFormat:@"未找到目标字符串。\n检查了 %d 个内存区域。\n可能游戏版本已更新或字符串已变更。", checkedRegions]];
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
