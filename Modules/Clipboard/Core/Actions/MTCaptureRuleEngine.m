//
//  MTCaptureRuleEngine.m
//  Mt
//

#import "MTCaptureRuleEngine.h"

#import <CommonCrypto/CommonDigest.h>
#import <JavaScriptCore/JavaScriptCore.h>
#import <dlfcn.h>

static NSUInteger const MTCaptureRuleMaxCount = 32;
static NSUInteger const MTCaptureRuleMaxActions = 8;
static NSUInteger const MTCaptureRuleNameLimit = 128;
static NSUInteger const MTCaptureRuleSourceLimit = 8192;
static NSUInteger const MTCaptureRuleTextLimit = 2000;
// 连续失败达到上限的规则在进程内停用，避免一条坏脚本反复拖慢每次采集；
// 规则集变化（指纹变化）后重新开始计数。
static NSUInteger const MTCaptureRuleFailureLimit = 3;
static NSTimeInterval const MTCaptureRuleTimeLimitSeconds = 0.05;

typedef void (*MTCaptureLimit)(JSContextGroupRef, double, bool (*)(JSContextRef, void *), void *);
typedef void (*MTCaptureClear)(JSContextGroupRef);
static bool MTCaptureTerminate(JSContextRef context, void *data) {
    *((BOOL *)data) = YES;
    return true;
}

static NSString *MTCaptureRuleName(NSDictionary *entry) {
    NSString *name = [entry[@"name"] isKindOfClass:NSString.class] ? entry[@"name"] : @"";
    return [name substringToIndex:MIN((NSUInteger)MTCaptureRuleNameLimit, name.length)];
}

@implementation MTCaptureRule

+ (NSArray<MTCaptureRule *> *)rulesFromDictionaries:(NSArray *)dictionaries {
    if (![dictionaries isKindOfClass:NSArray.class]) return @[];
    NSMutableArray<MTCaptureRule *> *result = [NSMutableArray array];
    for (NSDictionary *entry in dictionaries) {
        if (![entry isKindOfClass:NSDictionary.class]) continue;
        NSString *identifier = [entry[@"id"] isKindOfClass:NSString.class] ? entry[@"id"] : nil;
        NSString *source = [entry[@"source"] isKindOfClass:NSString.class] ? entry[@"source"] : nil;
        NSMutableCharacterSet *allowedIdentifier = [NSCharacterSet alphanumericCharacterSet].mutableCopy;
        [allowedIdentifier addCharactersInString:@"-"];
        if (identifier.length == 0 || identifier.length > 64 ||
            [identifier rangeOfCharacterFromSet:[allowedIdentifier invertedSet]].location != NSNotFound) continue;
        if (source.length == 0 || [source lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > MTCaptureRuleSourceLimit) continue;
        NSMutableArray<NSString *> *actions = [NSMutableArray array];
        for (id action in [entry[@"actions"] isKindOfClass:NSArray.class] ? entry[@"actions"] : @[]) {
            if (![action isKindOfClass:NSString.class] || [(NSString *)action length] == 0) continue;
            [actions addObject:action];
            if (actions.count >= MTCaptureRuleMaxActions) break;
        }
        MTCaptureRule *rule = [MTCaptureRule new];
        rule->_identifier = identifier;
        rule->_name = MTCaptureRuleName(entry);
        // enabled 缺省为开；auto 缺省为关（复制后自动执行默认关闭）。
        rule->_enabled = entry[@"enabled"] == nil || [entry[@"enabled"] boolValue];
        rule->_autoRun = [entry[@"auto"] boolValue];
        rule->_source = source;
        rule->_actions = actions;
        [result addObject:rule];
        if (result.count >= MTCaptureRuleMaxCount) break;
    }
    return result;
}

- (NSDictionary *)dictionaryRepresentation {
    return @{ @"id": self.identifier,
              @"name": self.name ?: @"",
              @"enabled": @(self.enabled),
              @"auto": @(self.autoRun),
              @"source": self.source ?: @"",
              @"actions": self.actions ?: @[] };
}

@end

static NSString *MTCaptureFingerprint(NSArray<MTCaptureRule *> *rules) {
    NSMutableString *fingerprint = [NSMutableString string];
    for (MTCaptureRule *rule in rules) {
        [fingerprint appendFormat:@"%@|%d|%@;", rule.identifier, rule.enabled, rule.source];
    }
    return fingerprint;
}

@interface MTCaptureRuleEngine ()
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, strong) JSVirtualMachine *vm;
// key = 规则 id，value = 连续失败次数；规则集指纹变化时清零。
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *failures;
@property (nonatomic, copy) NSString *failureFingerprint;
@end

@implementation MTCaptureRuleEngine

+ (instancetype)sharedEngine {
    static MTCaptureRuleEngine *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [self new];
    });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        _queue = dispatch_queue_create("com.lindo.metis.capture-rules", DISPATCH_QUEUE_SERIAL);
        _failures = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)evaluateRules:(NSArray<MTCaptureRule *> *)rules
                 text:(NSString *)text
                 kind:(NSString *)kind
             autoOnly:(BOOL)autoOnly
           completion:(void (^)(MTCaptureRule *hit))completion {
    NSString *copy = [text isKindOfClass:NSString.class]
        ? [text substringToIndex:MIN((NSUInteger)MTCaptureRuleTextLimit, text.length)]
        : @"";
    NSString *safeKind = [kind isKindOfClass:NSString.class] && kind.length ? kind : @"text";
    NSString *fingerprint = MTCaptureFingerprint(rules);
    dispatch_async(self.queue, ^{
        if (![fingerprint isEqual:self.failureFingerprint]) {
            [self.failures removeAllObjects];
            self.failureFingerprint = fingerprint;
        }
        MTCaptureRule *hit = nil;
        for (MTCaptureRule *rule in rules) {
            if (!rule.enabled || !rule.actions.count) continue;
            if (autoOnly && !rule.autoRun) continue;
            if ([self.failures[rule.identifier] unsignedIntegerValue] >= MTCaptureRuleFailureLimit) continue;
            NSDictionary *result = [self evaluateSource:rule.source text:copy kind:safeKind];
            if ([result[@"error"] length] > 0) {
                NSUInteger failures = [self.failures[rule.identifier] unsignedIntegerValue] + 1;
                self.failures[rule.identifier] = @(failures);
                NSLog(@"[Metis][CaptureRules] rule=%@ error=%@ failures=%lu",
                      rule.identifier, result[@"error"], (unsigned long)failures);
                continue;
            }
            if ([result[@"matched"] boolValue]) {
                hit = rule;
                break;
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(hit);
        });
    });
}

- (NSDictionary *)evaluateSource:(NSString *)source
                            text:(NSString *)text
                            kind:(NSString *)kind {
    CFAbsoluteTime start = CFAbsoluteTimeGetCurrent();
    MTCaptureLimit limit = (MTCaptureLimit)dlsym(RTLD_DEFAULT, "JSContextGroupSetExecutionTimeLimit");
    MTCaptureClear clear = (MTCaptureClear)dlsym(RTLD_DEFAULT, "JSContextGroupClearExecutionTimeLimit");
    if (!limit || !clear) return @{ @"matched": @NO, @"error": @"CAPTURE_JS_UNAVAILABLE", @"ms": @0 };

    if (!self.vm) self.vm = [JSVirtualMachine new];
    // 每次求值独立 realm：规则对全局对象/原型的改动不会泄漏到其他规则，
    // 结果也不依赖上一次的输入。
    JSContext *context = [[JSContext alloc] initWithVirtualMachine:self.vm];
    [context evaluateScript:
        @"Object.defineProperty(this,'Date',{value:null,writable:false,configurable:false});"
        @"Object.defineProperty(Math,'random',{value:null,writable:false,configurable:false});"];
    __block NSUInteger logBytes = 0;
    context[@"console"] = @{};
    context[@"console"][@"log"] = ^(NSString *message) {
        if (logBytes >= 4096) return;
        NSString *line = [message isKindOfClass:NSString.class] ? message : @"[value]";
        line = [line substringToIndex:MIN((NSUInteger)512, line.length)];
        logBytes += [line lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        NSLog(@"[Metis][CaptureRules] %@", line);
    };
    __block BOOL timedOut = NO;
    JSContextGroupRef group = JSContextGetGroup(context.JSGlobalContextRef);
    limit(group, MTCaptureRuleTimeLimitSeconds, MTCaptureTerminate, &timedOut);

    JSValue *function = [context evaluateScript:
        [NSString stringWithFormat:
            @"(function(){'use strict';\n%@\n;return typeof match === 'function' ? function(text, meta){return !!match(text, meta);} : null;})()",
            source]];
    BOOL matched = NO;
    NSString *error = nil;
    if (!context.exception && function && !function.isNull && !function.isUndefined) {
        JSValue *value = [function callWithArguments:@[ text ?: @"", @{ @"kind": kind ?: @"text" } ]];
        if (!context.exception && !timedOut) matched = value.toBool;
    } else if (!context.exception) {
        error = @"CAPTURE_JS_NO_MATCH";
    }
    if (timedOut) error = @"CAPTURE_JS_TIMEOUT";
    else if (context.exception) error = @"CAPTURE_JS_ERROR";
    clear(group);
    return @{ @"matched": @(matched && !error), @"error": error ?: @"",
              @"ms": @((CFAbsoluteTimeGetCurrent() - start) * 1000) };
}

@end
