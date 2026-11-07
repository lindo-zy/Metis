#import "MTRecentPhotoShortcut.h"

#import "MTCaptureLog.h"
#import <objc/message.h>

static NSString * const MTPhotosBundleIdentifier = @"com.apple.mobileslideshow";

// 照片 App「最近一张照片」快捷方式的稳定标识：快捷方式目录在 localizedTitle
// 缺失时以裸 type 串 MOST_RECENT_PHOTO 露出，故按 type 与标题双重匹配，
// 兼容系统后续补齐本地化。
static NSString * const MTMostRecentShortcutName = @"MOST_RECENT_PHOTO";

static NSString *MTReadString(id object, NSString *propertyName) {
    SEL selector = NSSelectorFromString(propertyName);
    if (!object || ![object respondsToSelector:selector]) return nil;
    @try {
        id value = ((id (*)(id, SEL))objc_msgSend)(object, selector);
        return [value isKindOfClass:[NSString class]] ? value : nil;
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static NSArray *MTReadItems(id application, NSString *propertyName) {
    SEL selector = NSSelectorFromString(propertyName);
    if (![application respondsToSelector:selector]) return @[];
    @try {
        id items = ((id (*)(id, SEL))objc_msgSend)(application, selector);
        return [items isKindOfClass:[NSArray class]] ? items : @[];
    } @catch (__unused NSException *exception) {
        return @[];
    }
}

BOOL MTLaunchPhotosMostRecentShortcut(void) {
    if (!NSThread.isMainThread) return NO;

    Class controllerClass = NSClassFromString(@"SBApplicationController");
    if (!controllerClass || ![controllerClass respondsToSelector:@selector(sharedInstance)]) return NO;

    @try {
        id controller = ((id (*)(id, SEL))objc_msgSend)(controllerClass, @selector(sharedInstance));
        SEL applicationSelector = @selector(applicationWithBundleIdentifier:);
        id application = controller && [controller respondsToSelector:applicationSelector]
            ? ((id (*)(id, SEL, id))objc_msgSend)(controller, applicationSelector, MTPhotosBundleIdentifier)
            : nil;
        if (!application) {
            MTCaptureLogWarn(@"most recent shortcut: photos application missing");
            return NO;
        }

        // 动态项在前，与系统长按菜单同序。
        id selectedItem = nil;
        NSArray *itemGroups = @[MTReadItems(application, @"dynamicApplicationShortcutItems"),
                                MTReadItems(application, @"staticApplicationShortcutItems")];
        for (NSArray *items in itemGroups) {
            for (id item in items) {
                NSString *type = MTReadString(item, @"type");
                NSString *title = MTReadString(item, @"localizedTitle");
                BOOL matches = (type.length > 0 && [type caseInsensitiveCompare:MTMostRecentShortcutName] == NSOrderedSame) ||
                    (title.length > 0 && [title localizedCaseInsensitiveContainsString:MTMostRecentShortcutName]);
                if (matches) {
                    selectedItem = item;
                    break;
                }
            }
            if (selectedItem) break;
        }
        if (!selectedItem) {
            MTCaptureLogWarn(@"most recent shortcut: item missing in photos catalogue");
            return NO;
        }

        Class iconViewClass = NSClassFromString(@"SBIconView");
        SEL activate = NSSelectorFromString(@"activateShortcut:withBundleIdentifier:forIconView:");
        NSMethodSignature *signature = [iconViewClass methodSignatureForSelector:activate];
        if (![iconViewClass respondsToSelector:activate] || signature.numberOfArguments != 5 ||
            !signature.methodReturnType || strcmp(signature.methodReturnType, @encode(void)) != 0) {
            MTCaptureLogWarn(@"most recent shortcut: SBIconView activate channel unavailable");
            return NO;
        }
        ((void (*)(id, SEL, id, id, id))objc_msgSend)(iconViewClass, activate, selectedItem, MTPhotosBundleIdentifier, nil);
        MTCaptureLogInfo(@"most recent shortcut dispatched");
        return YES;
    } @catch (NSException *exception) {
        MTCaptureLogWarn(@"most recent shortcut dispatch failed: %@", exception.name);
        return NO;
    }
}
