// MTPhotosHooks —— 照片 App 相册增强 hook 实现。
// Hook 点参考 DenyPhotoAlbums 1.2.1 的 PhotosUI 私有类接入方式，运行结构按
// MTChargingRuntime 同款「类存在 + 方法签名」守卫：iOS 大版本改版导致类缺失
// 或签名漂移时降级为无操作并记 syslog，不崩溃。
#import "MTPhotosHooks.h"
#import "MTPhotosPreferences.h"
#import "MTModuleGate.h"
#import "MTLog.h"
#import <substrate.h>
#import <objc/message.h>

// 解除缩放上限后的最大倍率：系统照片查看器原生约 5–8 倍，16 倍留足余量，
// 真机反馈过大再调。
static const double MTPhotosMaxZoomScale = 16.0;

static IMP MTPhotosOriginalMaxZoom;
static IMP MTPhotosOriginalSkipConfirm;

static BOOL MTPhotosMaxZoomActive(void) {
    return [MTModuleGate globalEnabled] && MTPhotosMaxZoomEnabled();
}

static BOOL MTPhotosSkipConfirmActive(void) {
    return [MTModuleGate globalEnabled] && MTPhotosSkipDeleteConfirmEnabled();
}

// 首次生效记一次 syslog，供真机核对 hook 命中；不逐次打，避免刷屏。
static void MTPhotosLogFirstHit(BOOL *flag, NSString *name) {
    if (*flag) return;
    *flag = YES;
    MTLogInfo(@"photos", @"state=hook-applied feature=%@", name);
}

static void MTPhotosMaxZoom(id self, SEL _cmd, double scale) {
    if (MTPhotosMaxZoomActive()) {
        static BOOL logged;
        MTPhotosLogFirstHit(&logged, @"max-zoom");
        scale = MTPhotosMaxZoomScale;
    }
    ((void (*)(id, SEL, double))MTPhotosOriginalMaxZoom)(self, _cmd, scale);
}

static BOOL MTPhotosSkipConfirm(id self, SEL _cmd) {
    if (MTPhotosSkipConfirmActive()) {
        static BOOL logged;
        MTPhotosLogFirstHit(&logged, @"skip-delete-confirm");
        return YES;
    }
    return ((BOOL (*)(id, SEL))MTPhotosOriginalSkipConfirm)(self, _cmd);
}

// 与 MTChargingMethodSupported 同款守卫：返回类型 + 参数个数 + 形参类型逐项
// 核对，防同名方法签名漂移。
static BOOL MTPhotosMethodSupported(Class cls, SEL selector, BOOL expectsDoubleArgument) {
    NSMethodSignature *signature = [cls instanceMethodSignatureForSelector:selector];
    if (!signature) return NO;
    const char *type = signature.methodReturnType;
    if (expectsDoubleArgument) {
        return !strcmp(type, "v") && signature.numberOfArguments == 3u &&
               !strcmp([signature getArgumentTypeAtIndex:2], "d");
    }
    return signature.numberOfArguments == 2u &&
           (!strcmp(type, "B") || !strcmp(type, "c"));
}

void MTPhotosInstall(void) {
    Class transform = NSClassFromString(@"PUUserTransformView");
    SEL maxZoom = NSSelectorFromString(@"_setPreferredMaximumZoomScale:");
    if (MTPhotosMethodSupported(transform, maxZoom, YES)) {
        MSHookMessageEx(transform, maxZoom, (IMP)MTPhotosMaxZoom, (IMP *)&MTPhotosOriginalMaxZoom);
    } else {
        MTLogWarn(@"photos", @"state=hooks-unavailable class=PUUserTransformView");
    }
    Class deleteAction = NSClassFromString(@"PUDeletePhotosActionController");
    SEL skipConfirm = @selector(shouldSkipDeleteConfirmation);
    if (MTPhotosMethodSupported(deleteAction, skipConfirm, NO)) {
        MSHookMessageEx(deleteAction, skipConfirm, (IMP)MTPhotosSkipConfirm, (IMP *)&MTPhotosOriginalSkipConfirm);
    } else {
        MTLogWarn(@"photos", @"state=hooks-unavailable class=PUDeletePhotosActionController");
    }
    // MTModuleGate 的 Darwin 分发链惰性注册（首个 addObserver 才挂）：照片进程
    // 没有其他观察者，这里必须注册一个，config-changed 后 globalEnabled 快照才会刷新。
    [MTModuleGate addObserver:dispatch_get_main_queue() block:^{
        MTLogInfo(@"photos", @"state=gate-applied enabled=%d", [MTModuleGate globalEnabled]);
    }];
    MTLogInfo(@"photos", @"state=installed max-zoom=%d skip-confirm=%d",
              MTPhotosMaxZoomEnabled(), MTPhotosSkipDeleteConfirmEnabled());
}
