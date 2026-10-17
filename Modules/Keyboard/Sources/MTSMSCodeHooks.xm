#import "common.h"
#import "MTSMSCodePolicy.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#include <atomic>

// One atomic word carries both admission and epoch, so reloads cannot undo
// a newer disable notification. Bit 0 is enabled; higher bits are the epoch.
static std::atomic<NSUInteger> MTSMSCodeEpoch(0);
static MTSMSCodeSession *MTSMSSession;
static void MTSMSTryInstallHooks(void);

// Read only object-returning selectors whose ABI has been checked. A missing
// or changed private getter disables that field instead of crashing SpringBoard.
static id MTSMSObject(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    if (![object respondsToSelector:selector]) return nil;
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (!signature || signature.numberOfArguments != 2 || signature.methodReturnType[0] != '@') return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}
static NSString *MTSMSString(id object, NSString *name) {
    id value = MTSMSObject(object, name);
    return [value isKindOfClass:NSString.class] ? [value copy] : nil;
}

static void MTSMSCaptureBulletin(id bulletin, NSString *explicitSection) {
    // The off path does not even read the notification payload.
    NSUInteger epoch = MTSMSCodeEpoch.load();
    if (!(epoch & 1)) return;
    NSString *section = explicitSection ?: MTSMSString(bulletin, @"sectionID");
    if (![section isEqualToString:@"com.apple.MobileSMS"]) return;
    NSString *text = MTSMSString(bulletin, @"message");
    if (!text.length || text.length > 4096) return;
    NSString *messageID = MTSMSString(bulletin, @"recordID");
    if (!messageID.length) messageID = MTSMSString(bulletin, @"publisherBulletinID");
    if (!messageID.length) messageID = MTSMSString(bulletin, @"bulletinID");
    id date = MTSMSObject(bulletin, @"date");
    if (![date isKindOfClass:NSDate.class]) date = MTSMSObject(bulletin, @"publicationDate");
    if (!messageID.length || ![date isKindOfClass:NSDate.class]) return;
    NSDate *messageDate = [date copy];
    NSDate *receivedAt = [NSDate date];
    dispatch_async(dispatch_get_main_queue(), ^{
        if (epoch != MTSMSCodeEpoch.load() ||
            [[NSDate date] timeIntervalSinceDate:receivedAt] > 2) return;
        @try {
            NSString *code = MTSMSExtractCode(text);
            if (!code || ![MTSMSSession acceptMessageID:messageID date:messageDate now:[NSDate date]]) return;
            if (epoch != MTSMSCodeEpoch.load()) return;
            // Parsing and writing form one main-thread operation; there is no
            // delayed parse result that can later replace a newer manual copy.
            [[UIPasteboard generalPasteboard] setItems:@[@{@"public.utf8-plain-text": code}]
                options:@{UIPasteboardOptionLocalOnly: @YES,
                          UIPasteboardOptionExpirationDate: [NSDate dateWithTimeIntervalSinceNow:180]}];
            NSLog(@"[MetisKeyboard][SMSCode] receive copied length=%lu", (unsigned long)code.length);
        } @catch (NSException *exception) {
            NSLog(@"[MetisKeyboard][SMSCode] receive copy failed");
        }
    });
}
static void MTSMSReceiveBulletin(id bulletin, NSString *explicitSection) {
    @try { MTSMSCaptureBulletin(bulletin, explicitSection); }
    @catch (NSException *exception) { NSLog(@"[MetisKeyboard][SMSCode] receive unsupported payload"); }
}

%group MTSMSPublish
%hook BBServer
- (void)publishBulletin:(id)bulletin destinations:(unsigned long long)destinations {
    MTSMSReceiveBulletin(bulletin, nil);
    %orig;
}
%end
%end
%group MTSMSPublishLock
%hook BBServer
- (void)publishBulletin:(id)bulletin destinations:(unsigned long long)destinations alwaysToLockScreen:(BOOL)always {
    MTSMSReceiveBulletin(bulletin, nil);
    %orig;
}
%end
%end
%group MTSMSRequest
%hook BBServer
- (void)publishBulletinRequest:(id)bulletin destinations:(unsigned long long)destinations {
    MTSMSReceiveBulletin(bulletin, nil);
    %orig;
}
%end
%end
%group MTSMSPrivateRequest
%hook BBServer
- (void)_publishBulletinRequest:(id)bulletin forSectionID:(id)section forDestinations:(unsigned long long)destinations {
    MTSMSReceiveBulletin(bulletin, [section isKindOfClass:NSString.class] ? section : nil);
    %orig;
}
%end
%end
%group MTSMSPrivateRequestLock
%hook BBServer
- (void)_publishBulletinRequest:(id)bulletin forSectionID:(id)section forDestinations:(unsigned long long)destinations alwaysToLockScreen:(BOOL)always {
    MTSMSReceiveBulletin(bulletin, [section isKindOfClass:NSString.class] ? section : nil);
    %orig;
}
%end
%end

static BOOL MTSMSMethodMatches(Class cls, NSString *name, const char *arguments) {
    Method method = class_getInstanceMethod(cls, NSSelectorFromString(name));
    if (!method || method_getNumberOfArguments(method) != strlen(arguments) + 2) return NO;
    char type[16] = {};
    method_getReturnType(method, type, sizeof(type));
    if (type[0] != 'v') return NO;
    for (NSUInteger i = 0; arguments[i]; i++) {
        method_getArgumentType(method, (unsigned int)i + 2, type, sizeof(type));
        if (arguments[i] == 'B') {
            if (type[0] != 'B' && type[0] != 'c') return NO;
        } else if (type[0] != arguments[i]) return NO;
    }
    return YES;
}
static void MTSMSTryInstallHooks(void) {
    Class cls = NSClassFromString(@"BBServer");
    if (!cls) return;
    static BOOL publish, publishLock, request, privateRequest, privateRequestLock;
    if (!publish && MTSMSMethodMatches(cls, @"publishBulletin:destinations:", "@Q")) {
        %init(MTSMSPublish, BBServer = cls); publish = YES;
    }
    if (!publishLock && MTSMSMethodMatches(cls, @"publishBulletin:destinations:alwaysToLockScreen:", "@QB")) {
        %init(MTSMSPublishLock, BBServer = cls); publishLock = YES;
    }
    if (!request && MTSMSMethodMatches(cls, @"publishBulletinRequest:destinations:", "@Q")) {
        %init(MTSMSRequest, BBServer = cls); request = YES;
    }
    if (!privateRequest && MTSMSMethodMatches(cls, @"_publishBulletinRequest:forSectionID:forDestinations:", "@@Q")) {
        %init(MTSMSPrivateRequest, BBServer = cls); privateRequest = YES;
    }
    if (!privateRequestLock && MTSMSMethodMatches(cls, @"_publishBulletinRequest:forSectionID:forDestinations:alwaysToLockScreen:", "@@QB")) {
        %init(MTSMSPrivateRequestLock, BBServer = cls); privateRequestLock = YES;
    }
    static BOOL reported;
    if (!reported) {
        reported = YES;
        NSLog(@"[MetisKeyboard][SMSCode] hooks publish=%d lock=%d request=%d private=%d privateLock=%d",
              publish, publishLock, request, privateRequest, privateRequestLock);
    }
}
static void MTSMSReload(void) {
    NSUInteger epoch = MTSMSCodeEpoch.load();
    NSDictionary *preferences = [[MTPrefsManager sharedInstance] readPrefs];
    [MTSMSSession updatePreferences:preferences now:[NSDate date]];
    MTSMSCodeEpoch.compare_exchange_strong(epoch, (epoch & ~NSUInteger(1)) | (MTSMSSession.enabled ? 1 : 0));
}
static void MTSMSPreferencesChanged(CFNotificationCenterRef center, void *observer,
                                   CFStringRef name, const void *object, CFDictionaryRef info) {
    // Stop admission immediately; a disable/re-enable invalidates queued work
    // even if both preference notifications arrive before the main queue runs.
    NSUInteger epoch = MTSMSCodeEpoch.load();
    while (!MTSMSCodeEpoch.compare_exchange_weak(epoch, (epoch + 2) & ~NSUInteger(1))) {}
    dispatch_async(dispatch_get_main_queue(), ^{ MTSMSReload(); });
}
%ctor {
    @autoreleasepool {
        if (![NSProcessInfo.processInfo.processName isEqualToString:@"SpringBoard"]) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            MTSMSSession = [MTSMSCodeSession new];
            MTSMSReload();
            // Keep the image loaded for the installed IMPs' process lifetime.
            dlopen("/System/Library/PrivateFrameworks/BulletinBoard.framework/BulletinBoard", RTLD_LAZY);
            MTSMSTryInstallHooks();
            CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
                MTSMSPreferencesChanged, (CFStringRef)kPrefsChangedIdentifier, NULL,
                CFNotificationSuspensionBehaviorDeliverImmediately);
            // Process-lifetime observers, installed exactly once in SpringBoard.
            [NSNotificationCenter.defaultCenter addObserverForName:NSBundleDidLoadNotification object:nil
                queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { MTSMSTryInstallHooks(); }];
            [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidFinishLaunchingNotification object:nil
                queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { MTSMSTryInstallHooks(); }];
        });
    }
}
