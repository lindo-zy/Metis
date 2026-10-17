#import "MTCaptureLayerExclusion.h"
#import "../Common/MTCaptureLog.h"
#import <string.h>
#import <dispatch/dispatch.h>

// Core Animation 的捕获排除位；只对本会话自有图层生效，保留其他标记。
static const uint64_t MTCaptureExcludedMask = 0x12;
static const char *MTUnqualifiedType(const char *type) {
    while (*type && strchr("rnNoORV", *type)) type++;
    return type;
}
static NSMethodSignature *MTMaskSignature(id layer, BOOL setter) {
    SEL selector = NSSelectorFromString(setter ? @"setDisableUpdateMask:" : @"disableUpdateMask");
    if (![layer respondsToSelector:selector]) return nil;
    NSMethodSignature *sig = [layer methodSignatureForSelector:selector];
    if (!sig || sig.numberOfArguments != (setter ? 3 : 2)) return nil;
    const char *type = MTUnqualifiedType(setter ? [sig getArgumentTypeAtIndex:2] : sig.methodReturnType);
    if (!strchr("ILQ", type[0]) || type[1] != '\0') return nil;
    NSUInteger size = 0;
    NSGetSizeAndAlignment(type, &size, NULL);
    if (size > sizeof(uint64_t) || (setter && strcmp(sig.methodReturnType, @encode(void)))) return nil;
    return sig;
}
static uint64_t MTReadMask(id layer) {
    NSInvocation *call = [NSInvocation invocationWithMethodSignature:MTMaskSignature(layer, NO)];
    call.target = layer; call.selector = NSSelectorFromString(@"disableUpdateMask");
    [call invoke];
    uint64_t mask = 0; [call getReturnValue:&mask]; return mask;
}
static void MTWriteMask(id layer, uint64_t mask) {
    NSInvocation *call = [NSInvocation invocationWithMethodSignature:MTMaskSignature(layer, YES)];
    call.target = layer; call.selector = NSSelectorFromString(@"setDisableUpdateMask:");
    [call setArgument:&mask atIndex:2]; [call invoke];
}
static void MTRestoreCaptureMasks(NSArray<NSDictionary *> *records) {
    for (NSDictionary *record in records) {
        @try {
            id layer = record[@"layer"];
            uint64_t current = MTReadMask(layer), original = [record[@"original"] unsignedLongLongValue];
            MTWriteMask(layer, (current & ~MTCaptureExcludedMask) | (original & MTCaptureExcludedMask));
        } @catch (NSException *exception) {
            MTCaptureLogWarn(@"long shot layer exclusion cleanup failed (%@)", exception.name);
        }
    }
}
@interface MTCaptureLayerExclusion ()
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *records;
@property (nonatomic, readwrite, getter=isActive) BOOL active;
@end
@implementation MTCaptureLayerExclusion
+ (instancetype)beginWithLayers:(NSArray *)layers {
    NSParameterAssert(NSThread.isMainThread);
    if (!layers.count) return nil;
    MTCaptureLayerExclusion *guard = [self new]; guard.records = [NSMutableArray array];
    @try {
        for (id layer in [NSOrderedSet orderedSetWithArray:layers]) {
            if (!MTMaskSignature(layer, NO) || !MTMaskSignature(layer, YES)) {
                [guard invalidate]; return nil;
            }
            uint64_t original = MTReadMask(layer);
            [guard.records addObject:@{@"layer":layer, @"original":@(original)}];
            MTWriteMask(layer, original | MTCaptureExcludedMask);
            if (MTReadMask(layer) != (original | MTCaptureExcludedMask)) {
                [guard invalidate]; return nil;
            }
        }
        guard.active = YES;
        return guard;
    } @catch (NSException *exception) {
        MTCaptureLogWarn(@"long shot layer exclusion setup failed (%@)", exception.name);
        [guard invalidate]; return nil;
    }
}
- (void)invalidate {
    NSParameterAssert(NSThread.isMainThread);
    self.active = NO;
    // 仅恢复自己拥有的捕获位，保留会话期间其他模块改动的非捕获位。
    MTRestoreCaptureMasks(self.records);
    [self.records removeAllObjects];
}
- (void)dealloc {
    if (!_records.count) return;
    // 正常会话显式清理；异常释放兜底也只在主线程恢复图层。
    NSArray *records = [_records copy];
    if (NSThread.isMainThread) MTRestoreCaptureMasks(records);
    else dispatch_async(dispatch_get_main_queue(), ^{ MTRestoreCaptureMasks(records); });
}
@end
