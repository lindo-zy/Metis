#import "MTPhotoShortcut.h"
#import "MTCaptureLog.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>

static NSString * const MTPhotosBundleIdentifier = @"com.apple.mobileslideshow";
// 照片 App「最近照片」应用快捷方式 type：真机照片 App 静态 App Shortcut 实测
// 取值（同机 MetisKeyboard 快捷动作选择器枚举出的同一条目）。
static NSString * const MTPhotosRecentShortcutType = @"MOST_RECENT_PHOTO";

@implementation MTPhotoShortcut

+ (id)mtSharedInstanceOfClass:(NSString *)className {
    Class cls = NSClassFromString(className);
    SEL shared = NSSelectorFromString(@"sharedInstance");
    if (!cls || ![(id)cls respondsToSelector:shared]) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(cls, shared);
}

+ (NSString *)mtReadStringProperty:(NSString *)name of:(id)object {
    SEL selector = NSSelectorFromString(name);
    if (!object || ![object respondsToSelector:selector]) return nil;
    id value = ((id (*)(id, SEL))objc_msgSend)(object, selector);
    return [value isKindOfClass:NSString.class] ? value : nil;
}

+ (NSArray *)mtReadArrayProperty:(NSString *)name of:(id)object {
    SEL selector = NSSelectorFromString(name);
    if (!object || ![object respondsToSelector:selector]) return @[];
    id value = ((id (*)(id, SEL))objc_msgSend)(object, selector);
    return [value isKindOfClass:NSArray.class] ? value : @[];
}

+ (BOOL)openMostRecentPhoto {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self openMostRecentPhoto]; });
        return NO;
    }
    if (![NSProcessInfo.processInfo.processName isEqualToString:@"SpringBoard"]) {
        MTCaptureLogWarn(@"photos shortcut skipped: not SpringBoard");
        return NO;
    }

    // 照片 App 的应用快捷方式（动态 + 静态），在 SpringBoard 内枚举。
    id controller = [self mtSharedInstanceOfClass:@"SBApplicationController"];
    SEL applicationSelector = NSSelectorFromString(@"applicationWithBundleIdentifier:");
    id application = nil;
    if (controller && [controller respondsToSelector:applicationSelector]) {
        application = ((id (*)(id, SEL, id))objc_msgSend)(controller, applicationSelector, MTPhotosBundleIdentifier);
    }

    NSMutableArray *items = [NSMutableArray array];
    [items addObjectsFromArray:[self mtReadArrayProperty:@"dynamicApplicationShortcutItems" of:application]];
    [items addObjectsFromArray:[self mtReadArrayProperty:@"staticApplicationShortcutItems" of:application]];

    // 按 type 精确（大小写不敏感）命中「最近照片」；快捷方式未带本地化标题时
    // 用标题兜底（中文「最近」/英文 recent），都没命中再回退拉起 App。
    id recent = nil;
    NSString *recentDescription = nil;
    for (id item in items) {
        NSString *type = [self mtReadStringProperty:@"type" of:item];
        BOOL typeHit = type.length > 0 && [type caseInsensitiveCompare:MTPhotosRecentShortcutType] == NSOrderedSame;
        NSString *title = [self mtReadStringProperty:@"localizedTitle" of:item];
        BOOL titleHit = title.length > 0 &&
            ([title containsString:@"最近"] || [title localizedCaseInsensitiveContainsString:@"recent"]);
        if (typeHit || titleHit) {
            recent = item;
            recentDescription = type ?: title;
            break;
        }
    }

    if (recent) {
        Class iconViewClass = NSClassFromString(@"SBIconView");
        SEL activate = NSSelectorFromString(@"activateShortcut:withBundleIdentifier:forIconView:");
        NSMethodSignature *signature = [iconViewClass methodSignatureForSelector:activate];
        // 与 MetisKeyboard 一致：历史头文件对返回类型说法不一，运行时核对 void 返回 ABI。
        if (iconViewClass && [iconViewClass respondsToSelector:activate] && signature &&
            signature.numberOfArguments == 5 && signature.methodReturnType &&
            strcmp(signature.methodReturnType, @encode(void)) == 0) {
            ((void (*)(id, SEL, id, id, id))objc_msgSend)(iconViewClass, activate, recent,
                                                          MTPhotosBundleIdentifier, nil);
            MTCaptureLogInfo(@"photos shortcut activated (%@, items %lu)", recentDescription,
                      (unsigned long)items.count);
            return YES;
        }
        MTCaptureLogWarn(@"photos shortcut activate unavailable, falling back to app launch");
    } else {
        MTCaptureLogWarn(@"photos recent shortcut not found (items %lu), falling back to app launch",
                  (unsigned long)items.count);
    }

    // 回退：直接拉起照片 App（停在图库页）。返回类型同样按运行时签名核对。
    UIApplication *app = UIApplication.sharedApplication;
    SEL launch = NSSelectorFromString(@"launchApplicationWithIdentifier:suspended:");
    NSMethodSignature *launchSignature = [app methodSignatureForSelector:launch];
    if (![app respondsToSelector:launch] || !launchSignature || launchSignature.numberOfArguments != 4) {
        MTCaptureLogError(@"photos app launch unavailable");
        return NO;
    }
    BOOL opened = ((BOOL (*)(id, SEL, id, BOOL))objc_msgSend)(app, launch, MTPhotosBundleIdentifier, NO);
    MTCaptureLogInfo(@"photos app launched=%d (fallback)", opened);
    return opened;
}

@end
