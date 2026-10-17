//
//  MTClipboardHelperConfiguration.m
//  Mt
//

#import "MTClipboardHelperConfiguration.h"
#import "MTPreferenceKeys.h"
#import "MTCore.h"

NS_ASSUME_NONNULL_BEGIN

@interface MTClipboardHelperConfiguration ()

@property(nonatomic, assign, readwrite, getter=isEnabled) BOOL enabled;
@property(nonatomic, assign, readwrite) NSUInteger activationMethod;
@property(nonatomic, assign, readwrite) MTGestureRecognizerMode gestureRecognizerMode;
@property(nonatomic, assign, readwrite, getter=isAutomaticallyPasteEnabled) BOOL automaticallyPasteEnabled;
@property(nonatomic, assign, readwrite, getter=isHapticFeedbackEnabled) BOOL hapticFeedbackEnabled;

- (instancetype)initWithPreferences:(NSUserDefaults *)preferences;

@end

NS_ASSUME_NONNULL_END

@implementation MTClipboardHelperConfiguration

+ (instancetype)currentConfiguration {
    // 模块启停唯一权威是 com.lindo.metis 门控（MTModuleGate）：门控关闭时
    // Helper 在任何宿主（app/键盘扩展/SpringBoard）一律不装 hook。沙盒宿主
    // 读不到偏好文件时由 MTConfigService 的 gate.plist 快照兜底。
    // 细节参数读 Metis 自有细节域（com.lindo.metis.clipboard）；沙盒宿主读
    // 不到时维持默认值——与旧版 MTX 行为一致，且绝不读旧插件域。
    [MTModuleGate reload];
    if (![MTModuleGate moduleEnabled:MTModuleClipboard]) {
        MTClipboardHelperConfiguration *configuration = [[self alloc] init];
        configuration.enabled = NO;
        return configuration;
    }
    NSUserDefaults *preferences = [[NSUserDefaults alloc] initWithSuiteName:kMTClipboardPreferencesIdentifier];

    [preferences registerDefaults:@{
        kMTPreferenceKeyEnabled : @(kMTPreferenceKeyEnabledDefaultValue),
        kMTPreferenceKeyActivationMethod : @(kMTPreferenceKeyActivationMethodDefaultValue),
        kMTPreferenceKeyGestureRecognizerMode : @(kMTPreferenceKeyGestureRecognizerModeDefaultValue),
        kMTPreferenceKeyAutomaticallyPaste : @(kMTPreferenceKeyAutomaticallyPasteDefaultValue),
        kMTPreferenceKeyPlayHapticFeedback : @(kMTPreferenceKeyPlayHapticFeedbackDefaultValue)
    }];

    MTClipboardHelperConfiguration *configuration = [[self alloc] initWithPreferences:preferences];
    return configuration;
}

- (instancetype)initWithPreferences:(NSUserDefaults *)preferences {
    self = [super init];
    if (self) {
        _enabled = [[preferences objectForKey:kMTPreferenceKeyEnabled] boolValue];
        _activationMethod = [[preferences objectForKey:kMTPreferenceKeyActivationMethod] unsignedIntegerValue];
        _gestureRecognizerMode =
            [[preferences objectForKey:kMTPreferenceKeyGestureRecognizerMode] unsignedIntegerValue];
        if (_gestureRecognizerMode != kMTGestureRecognizerModeClassic &&
            _gestureRecognizerMode != kMTGestureRecognizerModeSystem) {
            _gestureRecognizerMode = kMTPreferenceKeyGestureRecognizerModeDefaultValue;
        }
        _automaticallyPasteEnabled = [[preferences objectForKey:kMTPreferenceKeyAutomaticallyPaste] boolValue];
        _hapticFeedbackEnabled = [[preferences objectForKey:kMTPreferenceKeyPlayHapticFeedback] boolValue];
    }
    return self;
}

@end
