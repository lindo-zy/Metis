#import "MTContextClassifier.h"
#import "MTContextGroupEngine.h"
#import <JavaScriptCore/JavaScriptCore.h>
#import <CommonCrypto/CommonDigest.h>
#import <dlfcn.h>

static BOOL MTCTXRegex(NSString *text, NSString *pattern) {
    return [text rangeOfString:pattern options:NSRegularExpressionSearch].location != NSNotFound;
}
NSArray<NSString *> *MTContextBuiltinMatches(NSString *text, BOOL hasImage) {
    if (hasImage) return @[@"image", @"fallback"];
    NSString *t = [[text ?: @"" precomposedStringWithCompatibilityMapping] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSMutableArray *matches = [NSMutableArray array];
    if (MTContextURLForText(t)) [matches addObject:@"url"];
    if (MTCTXRegex(t, @"^\\d{4}[-/]\\d{1,2}[-/]\\d{1,2}(?:[ T].*)?$")) [matches addObject:@"date"];
    if (MTCTXRegex(t, @"^[+]?[- ()0-9]{7,24}$") && MTContextTextLooksLikePhone(t) && ![matches containsObject:@"date"]) [matches addObject:@"phone"];
    if (MTCTXRegex(t, @"^[+-]?(?:[0-9]+(?:\\.[0-9]+)?|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?$")) [matches addObject:@"number"];
    if (MTCTXRegex(t, @"(?:省|市|区|县|路|街|巷|号|栋|室)") && MTCTXRegex(t, @"[0-9一二三四五六七八九十]")) [matches addObject:@"address"];
    BOOL chinese = MTCTXRegex(t, @"[\\x{3400}-\\x{9fff}]");
    BOOL english = MTCTXRegex(t, @"[A-Za-z]");
    if (chinese && english) [matches addObject:@"mixed"];
    else if (chinese) [matches addObject:@"chinese"];
    // General text is a fallback, not a catch-all that shadows every JS rule.
    if (t.length && ![matches containsObject:@"url"] && ![matches containsObject:@"phone"] && ![matches containsObject:@"date"] && ![matches containsObject:@"number"] && ![matches containsObject:@"address"]) [matches addObject:@"text"];
    [matches addObject:@"fallback"]; return matches;
}
NSString *MTContextInsertedText(NSString *before, NSString *after) {
    if (![before isKindOfClass:NSString.class] || ![after isKindOfClass:NSString.class]) return nil;
    NSUInteger prefix = 0, suffix = 0;
    while (prefix < before.length && prefix < after.length && [before characterAtIndex:prefix] == [after characterAtIndex:prefix]) prefix++;
    while (suffix < before.length - prefix && suffix < after.length - prefix && [before characterAtIndex:before.length - suffix - 1] == [after characterAtIndex:after.length - suffix - 1]) suffix++;
    return [after substringWithRange:NSMakeRange(prefix, after.length - prefix - suffix)];
}
typedef void (*MTCTXLimit)(JSContextGroupRef, double, bool (*)(JSContextRef, void *), void *);
typedef void (*MTCTXClear)(JSContextGroupRef);
static bool MTCTXTerminate(JSContextRef context, void *data) { *((BOOL *)data) = YES; return true; }

@interface MTContextClassifier ()
@property(nonatomic, strong) dispatch_queue_t queue;
@property(nonatomic, strong) JSVirtualMachine *vm;
@property(nonatomic, strong) NSMutableDictionary *cache;
@property(nonatomic, strong) NSMutableArray *lru;
@property(nonatomic, strong) NSMutableDictionary *failures;
@property(nonatomic, assign) NSUInteger generation;
@end
@implementation MTContextClassifier
+ (instancetype)sharedClassifier { static id instance; static dispatch_once_t once; dispatch_once(&once, ^{ instance = [self new]; }); return instance; }
- (instancetype)init {
    if ((self = [super init])) { _queue = dispatch_queue_create("com.lindo.metis.context-classifier", DISPATCH_QUEUE_SERIAL); _cache = [NSMutableDictionary dictionary]; _lru = [NSMutableArray array]; _failures = [NSMutableDictionary dictionary]; } return self;
}
- (void)invalidate {
    dispatch_async(self.queue, ^{ self.vm = nil; [self.cache removeAllObjects]; [self.lru removeAllObjects]; [self.failures removeAllObjects]; self.generation++; });
}
- (NSDictionary *)runSource:(NSString *)source text:(NSString *)text identifier:(NSString *)identifier {
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    MTCTXLimit limit = (MTCTXLimit)dlsym(RTLD_DEFAULT, "JSContextGroupSetExecutionTimeLimit");
    MTCTXClear clear = (MTCTXClear)dlsym(RTLD_DEFAULT, "JSContextGroupClearExecutionTimeLimit");
    NSString *error = nil;
    if (!limit || !clear) error = @"CTX_JS_UNAVAILABLE";
    else if ([self.failures[identifier] unsignedIntegerValue] >= 3) error = @"CTX_JS_DISABLED";
    else if (![source isKindOfClass:NSString.class] || !source.length || [source lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 8192) error = @"CTX_JS_SIZE";
    if (error) return @{@"matched":@NO, @"error":error, @"ms":@0};
    if (!self.vm) self.vm = [JSVirtualMachine new];
    // A fresh realm for every uncached call prevents rule globals/prototype edits
    // from leaking into another rule or making results depend on previous text.
    JSContext *context = [[JSContext alloc] initWithVirtualMachine:self.vm];
    [context evaluateScript:@"Object.defineProperty(this,'Date',{value:null,writable:false,configurable:false}); Object.defineProperty(Math,'random',{value:null,writable:false,configurable:false});"];
    __block NSUInteger logBytes = 0;
    context[@"console"] = @{};
    context[@"console"][@"log"] = ^(NSString *message) {
        if (logBytes >= 16384) return;
        NSString *line = [message isKindOfClass:NSString.class] ? message : @"[value]";
        line = [line substringToIndex:MIN(line.length, (NSUInteger)1024)];
        NSUInteger bytes = [line lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        if (logBytes + bytes <= 16384) NSLog(@"[Metis][ContextJS] %@", line); logBytes += bytes;
    };
    __block BOOL timedOut = NO;
    JSContextGroupRef group = JSContextGetGroup(context.JSGlobalContextRef);
    limit(group, 0.05, MTCTXTerminate, &timedOut);
    JSValue *function = [context evaluateScript:[NSString stringWithFormat:@"(function(){'use strict';\n%@\n;return typeof match === 'function' ? function(text){return !!match(text);} : null;})()", source]];
    BOOL matched = NO;
    if (!context.exception && function && !function.isNull && !function.isUndefined) {
        JSValue *value = [function callWithArguments:@[text ?: @""]];
        if (!context.exception && !timedOut) matched = value.toBool;
    } else if (!context.exception) error = @"CTX_JS_NO_MATCH";
    if (timedOut) error = @"CTX_JS_TIMEOUT";
    else if (context.exception) error = @"CTX_JS_ERROR";
    clear(group);
    if (error) {
        NSUInteger failures = [self.failures[identifier] unsignedIntegerValue] + 1; self.failures[identifier] = @(failures);
        NSLog(@"[Metis][ContextJS] rule=%@ error=%@ failures=%lu", identifier, error, (unsigned long)failures);
    } else self.failures[identifier] = @0;
    return @{@"matched":@(matched && !error), @"error":error ?: @"", @"ms":@((CFAbsoluteTimeGetCurrent() - start) * 1000)};
}
- (void)classifyText:(NSString *)text surface:(NSString *)surface flags:(NSDictionary *)flags group:(NSString *)group config:(MTContextGroupConfig *)config completion:(void (^)(NSDictionary *))completion {
    NSString *copy = [text isKindOfClass:NSString.class] ? [text substringToIndex:MIN(text.length, (NSUInteger)2000)] : @"";
    dispatch_async(self.queue, ^{
        NSData *bytes = [copy dataUsingEncoding:NSUTF8StringEncoding]; unsigned char digest[CC_SHA1_DIGEST_LENGTH]; CC_SHA1(bytes.bytes, (CC_LONG)bytes.length, digest);
        NSMutableString *hash = [NSMutableString string]; for (NSUInteger i = 0; i < sizeof(digest); i++) [hash appendFormat:@"%02x", digest[i]];
        // Include config + image flag; an editor test never poisons runtime cache.
        NSData *rules = [[[config dictionaryRepresentation][group] description] dataUsingEncoding:NSUTF8StringEncoding];
        CC_SHA1(rules.bytes, (CC_LONG)rules.length, digest);
        NSMutableString *revision = [NSMutableString string]; for (NSUInteger i = 0; i < sizeof(digest); i++) [revision appendFormat:@"%02x", digest[i]];
        NSString *key = [NSString stringWithFormat:@"%@|%@|%@|%lu|%@|%@", group, surface, hash, (unsigned long)copy.length, flags ?: @{}, revision];
        NSDictionary *result = self.cache[key];
        if (result) { [self.lru removeObject:key]; [self.lru addObject:key]; }
        else {
            NSMutableArray *matches = [NSMutableArray array];
            if (![flags[@"secure"] boolValue] && copy.length && ![flags[@"image"] boolValue]) {
                for (MTContextType *type in [config typesForGroup:group]) if (type.enabled && [type.kind isEqual:@"js"]) {
                    NSString *identifier = [NSString stringWithFormat:@"%@/%@/%lu", group, type.identifier, (unsigned long)type.source.hash];
                    NSDictionary *test = [self runSource:type.source text:copy identifier:identifier];
                    if ([test[@"matched"] boolValue]) [matches addObject:type.identifier];
                }
            }
            result = @{@"builtin":MTContextBuiltinMatches(copy, [flags[@"image"] boolValue]), @"js":matches, @"pending":@NO};
            self.cache[key] = result; [self.lru addObject:key];
            if (self.lru.count > 32) { [self.cache removeObjectForKey:self.lru.firstObject]; [self.lru removeObjectAtIndex:0]; }
        }
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(result); });
    });
}
- (void)testRule:(NSString *)identifier source:(NSString *)source text:(NSString *)text completion:(void (^)(NSDictionary *))completion {
    NSString *copy = [text isKindOfClass:NSString.class] ? [text substringToIndex:MIN(text.length, (NSUInteger)2000)] : @"";
    dispatch_async(self.queue, ^{ NSDictionary *result = [self runSource:source text:copy identifier:[@"test/" stringByAppendingString:identifier ?: @"rule"]]; dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(result); }); });
}
@end
