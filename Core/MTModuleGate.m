#import "MTModuleGate.h"
#import "MTLog.h"
#import "MTPathResolver.h"
#import <CoreFoundation/CoreFoundation.h>
#import <pthread/pthread.h>

#ifdef METIS_CONFIG_DOMAIN_OVERRIDE
NSString *const MTConfigDomain = @METIS_CONFIG_DOMAIN_OVERRIDE;
#else
NSString *const MTConfigDomain = @"com.lindo.metis";
#endif
NSString *const MTConfigChangedNotification = @"com.lindo.metis/config-changed";

NSString *const MTModuleCapture = @"capture";
NSString *const MTModuleKeyboard = @"keyboard";
NSString *const MTModuleClipboard = @"clipboard";

// 不可变快照 + 锁内替换；读取方只拿稳定引用，不会读到半份数据。
static pthread_mutex_t gSnapshotLock = PTHREAD_MUTEX_INITIALIZER;
static NSDictionary<NSString *, NSNumber *> *gSnapshot;

static id MTReadPreferenceValue(NSString *key) {
    CFPropertyListRef value = CFPreferencesCopyAppValue(
        (__bridge CFStringRef)key, (__bridge CFStringRef)MTConfigDomain);
    if (value != NULL) {
        id result = (__bridge_transfer id)value;
        return result;
    }
    // 兜底链（都读不到就维持缺省 YES：核心能力首装默认可用，v3 P05）：
    //   1. 偏好文件直读：cfprefsd 未就绪 / 首解锁前保护期的冷启动路径；
    //   2. 门控快照 /Library/Metis/Config/gate.plist：沙盒宿主（app/键盘
    //      扩展）既走不了 CFPreferences 权威域、也读不到 /var/mobile 文件，
    //      由设置端 flush 写入的世界可读快照是它们唯一的门控来源。
    static NSString *plistPath = nil;
    static NSString *gateSnapshotPath = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        plistPath = [MTResolvePath(@"/var/mobile/Library/Preferences/com.lindo.metis.plist") copy];
        gateSnapshotPath = [MTGateSnapshotPath() copy];
    });
    NSDictionary *root = [NSDictionary dictionaryWithContentsOfFile:plistPath];
    if (root[key]) return root[key];
    NSDictionary *gate = [NSDictionary dictionaryWithContentsOfFile:gateSnapshotPath];
    return gate[key];
}

// 快照只承载唯一整体开关；旧模块键（*Enabled）已退役，不再进入快照，
// 也不再把缺省值固化成 NO（05-data-migration §1 默认值契约）。
static NSDictionary<NSString *, NSNumber *> *MTBuildSnapshot(void) {
    NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];
    id global = MTReadPreferenceValue(@"enabled");
    snapshot[@"enabled"] = [global isKindOfClass:NSNumber.class] ? @([global boolValue]) : @YES;
    return snapshot;
}

static void MTStoreSnapshot(void) {
    NSDictionary *next = MTBuildSnapshot();
    pthread_mutex_lock(&gSnapshotLock);
    gSnapshot = next;
    pthread_mutex_unlock(&gSnapshotLock);
}

static NSDictionary *MTCurrentSnapshot(void) {
    pthread_mutex_lock(&gSnapshotLock);
    NSDictionary *snapshot = gSnapshot;
    pthread_mutex_unlock(&gSnapshotLock);
    if (!snapshot) {
        MTStoreSnapshot();
        pthread_mutex_lock(&gSnapshotLock);
        snapshot = gSnapshot;
        pthread_mutex_unlock(&gSnapshotLock);
    }
    return snapshot;
}

#pragma mark - Darwin config-changed 分发

@interface MTModuleGateObserverToken : NSObject
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, copy) void (^block)(void);
@end

@implementation MTModuleGateObserverToken
@end

static pthread_mutex_t gObserverLock = PTHREAD_MUTEX_INITIALIZER;
static NSMutableArray<MTModuleGateObserverToken *> *gObservers;
static dispatch_once_t gDarwinObserverOnce;

static void MTConfigChangedDarwinCallback(CFNotificationCenterRef center,
                                          void *observer,
                                          CFStringRef name,
                                          const void *object,
                                          CFDictionaryRef userInfo) {
    (void)center; (void)observer; (void)name; (void)object; (void)userInfo;
    MTStoreSnapshot();
    pthread_mutex_lock(&gObserverLock);
    NSArray<MTModuleGateObserverToken *> *observers = gObservers ? [gObservers copy] : nil;
    pthread_mutex_unlock(&gObserverLock);
    for (MTModuleGateObserverToken *token in observers) {
        dispatch_block_t fire = ^{
            [MTModuleGate reload];
            token.block();
        };
        if (token.queue) {
            dispatch_async(token.queue, fire);
        } else {
            dispatch_async(dispatch_get_main_queue(), fire);
        }
    }
}

@implementation MTModuleGate

+ (BOOL)globalEnabled {
    NSNumber *value = MTCurrentSnapshot()[@"enabled"];
    return value ? value.boolValue : YES;
}

+ (void)reload {
    MTStoreSnapshot();
}

+ (id)addObserver:(dispatch_queue_t)queue block:(void (^)(void))block {
    if (!block) return nil;
    dispatch_once(&gDarwinObserverOnce, ^{
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            NULL,
            &MTConfigChangedDarwinCallback,
            (__bridge CFStringRef)MTConfigChangedNotification,
            NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
    });
    MTModuleGateObserverToken *token = [[MTModuleGateObserverToken alloc] init];
    token.queue = queue;
    token.block = block;
    pthread_mutex_lock(&gObserverLock);
    if (!gObservers) gObservers = [NSMutableArray array];
    [gObservers addObject:token];
    pthread_mutex_unlock(&gObserverLock);
    return token;
}

+ (void)removeObserver:(id)token {
    if (![token isKindOfClass:[MTModuleGateObserverToken class]]) return;
    pthread_mutex_lock(&gObserverLock);
    [gObservers removeObject:token];
    pthread_mutex_unlock(&gObserverLock);
}

+ (NSDictionary<NSString *, NSNumber *> *)switchSnapshotForDiagnostics {
    return [MTCurrentSnapshot() copy];
}

@end
