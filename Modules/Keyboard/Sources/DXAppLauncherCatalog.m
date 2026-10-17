#import "DXAppLauncherCatalog.h"
#import <objc/message.h>
#import <dlfcn.h>

static id DXLauncherRead(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    if (![object respondsToSelector:selector]) return nil;
    NSMethodSignature *sig = [object methodSignatureForSelector:selector];
    if (sig.numberOfArguments != 2 || strcmp(sig.methodReturnType, "@")) return nil;
    @try { return ((id (*)(id, SEL))objc_msgSend)(object, selector); }
    @catch (__unused NSException *exception) { return nil; }
}

static BOOL DXLauncherFlag(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    if (![object respondsToSelector:selector]) return NO;
    NSMethodSignature *sig = [object methodSignatureForSelector:selector];
    if (!sig) return NO;
    const char *type = sig.methodReturnType;
    if (sig.numberOfArguments != 2 || !type || (strcmp(type, "B") && strcmp(type, "c"))) return NO;
    @try { return ((BOOL (*)(id, SEL))objc_msgSend)(object, selector); }
    @catch (__unused NSException *exception) { return NO; }
}

static BOOL DXLauncherHiddenTags(id tags) {
    if (![tags isKindOfClass:NSArray.class] && ![tags isKindOfClass:NSSet.class]) return NO;
    for (id tag in tags) if ([tag isKindOfClass:NSString.class] && [tag containsString:@"hidden"]) return YES;
    return NO;
}

@interface DXAppLauncherCatalog ()
@property(nonatomic, strong) dispatch_queue_t worker;
@property(nonatomic, strong) id workspace;
@property(nonatomic, copy) NSArray<NSDictionary *> *records; // worker queue only
@property(nonatomic, strong) NSDate *loadedAt; // worker queue only
@property(nonatomic) BOOL observing;
@end

@implementation DXAppLauncherCatalog
- (instancetype)init {
    if ((self = [super init])) self.worker = dispatch_queue_create("com.lindo.typex.launcher.catalog", DISPATCH_QUEUE_SERIAL);
    return self;
}
- (void)dealloc {
    if (self.observing && [self.workspace respondsToSelector:NSSelectorFromString(@"removeObserver:")]) {
        @try { ((void (*)(id, SEL, id))objc_msgSend)(self.workspace, NSSelectorFromString(@"removeObserver:"), self); }
        @catch (__unused NSException *exception) {}
    }
}
- (void)applicationsDidInstall:(__unused NSArray *)applications { [self invalidate]; }
- (void)applicationsDidUninstall:(__unused NSArray *)applications { [self invalidate]; }
- (void)applicationDatabaseDidChange { [self invalidate]; }
- (void)invalidate {
    dispatch_async(self.worker, ^{ self.loadedAt = nil; });
    dispatch_async(dispatch_get_main_queue(), ^{ if (self.didInvalidate) self.didInvalidate(); });
}
- (void)prepareWorkspace {
    if (self.workspace) return;
    // Called only after the handle's startup gate, never from a constructor.
    for (NSString *path in @[@"/System/Library/Frameworks/CoreServices.framework/CoreServices",
        @"/System/Library/Frameworks/MobileCoreServices.framework/MobileCoreServices"]) {
        if (dlopen(path.UTF8String, RTLD_LAZY | RTLD_LOCAL)) break;
    }
    self.workspace = DXLauncherRead(NSClassFromString(@"LSApplicationWorkspace"), @"defaultWorkspace");
    if ([self.workspace respondsToSelector:NSSelectorFromString(@"addObserver:")]) {
        @try {
            ((void (*)(id, SEL, id))objc_msgSend)(self.workspace, NSSelectorFromString(@"addObserver:"), self);
            self.observing = YES;
        } @catch (__unused NSException *exception) {}
    }
}
- (void)loadWithAliases:(NSDictionary *)aliases fallbackNames:(NSDictionary<NSString *, NSString *> *)names
    completion:(void (^)(NSArray<DXAppSearchEntry *> *, BOOL))completion {
    NSAssert(NSThread.isMainThread, @"Launcher catalogue must be requested on the main thread");
    [self prepareWorkspace];
    id workspace = self.workspace;
    NSDictionary *aliasSnapshot = [aliases copy], *fallback = [names copy];
    dispatch_async(self.worker, ^{
        @autoreleasepool {
            BOOL available = self.loadedAt != nil;
            if (!self.loadedAt || -self.loadedAt.timeIntervalSinceNow > 60) {
                id installed = DXLauncherRead(workspace, @"allApplications");
                available = [installed isKindOfClass:NSArray.class] && [installed count] > 0;
                if (available) {
                    NSMutableArray *records = [NSMutableArray array];
                    NSMutableSet *seen = [NSMutableSet set];
                    for (id proxy in installed) {
                        id identifier = DXLauncherRead(proxy, @"applicationIdentifier");
                        id type = DXLauncherRead(proxy, @"applicationType");
                        id tags = DXLauncherRead(proxy, @"appTags");
                        id record = DXLauncherRead(proxy, @"correspondingApplicationRecord");
                        id url = DXLauncherRead(proxy, @"bundleURL");
                        NSBundle *bundle = [url isKindOfClass:NSURL.class] ? [NSBundle bundleWithURL:url] : nil;
                        if (![identifier isKindOfClass:NSString.class] || [identifier length] == 0 ||
                            [seen containsObject:identifier] ||
                            (![@"User" isEqual:type] && ![@"System" isEqual:type]) ||
                            DXLauncherHiddenTags(tags) || DXLauncherHiddenTags(DXLauncherRead(record, @"appTags")) ||
                            DXLauncherHiddenTags([bundle objectForInfoDictionaryKey:@"SBAppTags"]) ||
                            DXLauncherFlag(record, @"launchProhibited") || DXLauncherFlag(proxy, @"isLaunchProhibited") ||
                            [identifier rangeOfString:@"com.apple.webapp" options:NSCaseInsensitiveSearch].location != NSNotFound) continue;
                        id name = DXLauncherRead(proxy, @"localizedName");
                        id english = [bundle objectForInfoDictionaryKey:@"CFBundleName"] ?: DXLauncherRead(proxy, @"itemName");
                        [records addObject:@{@"id": identifier,
                            @"name": [name isKindOfClass:NSString.class] && [name length] ? name : identifier,
                            @"english": [english isKindOfClass:NSString.class] ? english : @""}];
                        [seen addObject:identifier];
                    }
                    self.records = records; self.loadedAt = NSDate.date;
                } else { self.loadedAt = nil; }
                NSLog(@"[MetisKeyboard][Launcher] catalogue available=%d count=%lu", available, (unsigned long)self.records.count);
            }
            NSArray *records = self.records;
            if (!available) {
                NSMutableArray *seed = [NSMutableArray array];
                for (NSString *identifier in fallback) [seed addObject:@{@"id": identifier, @"name": fallback[identifier]}];
                records = seed;
            }
            NSMutableArray *entries = [NSMutableArray array];
            for (NSDictionary *record in records) {
                id raw = aliasSnapshot[record[@"id"]];
                NSMutableArray *terms = [NSMutableArray array];
                if ([raw isKindOfClass:NSArray.class]) [terms addObjectsFromArray:raw];
                if ([record[@"english"] length]) [terms addObject:record[@"english"]];
                [entries addObject:[DXAppSearchEntry entryWithIdentifier:record[@"id"] name:record[@"name"] aliases:terms]];
            }
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(entries, available); });
        }
    });
}
@end
