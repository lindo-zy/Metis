//
//  KayokoHelperConfiguration.m
//  Kayoko
//

#import "KayokoHelperConfiguration.h"
#import "KayokoPreferenceKeys.h"
#import "MTCore.h"

NS_ASSUME_NONNULL_BEGIN

@interface KayokoHelperConfiguration ()

@property(nonatomic, assign, readwrite, getter=isEnabled) BOOL enabled;
@property(nonatomic, assign, readwrite) NSUInteger activationMethod;
@property(nonatomic, assign, readwrite) KayokoGestureRecognizerMode gestureRecognizerMode;
@property(nonatomic, assign, readwrite, getter=isAutomaticallyPasteEnabled) BOOL automaticallyPasteEnabled;
@property(nonatomic, assign, readwrite, getter=isHapticFeedbackEnabled) BOOL hapticFeedbackEnabled;

- (instancetype)initWithPreferences:(NSUserDefaults *)preferences;

@end

NS_ASSUME_NONNULL_END

@implementation KayokoHelperConfiguration

+ (instancetype)currentConfiguration {
    // 模块启停唯一权威是 com.lindo.metis 门控（MTModuleGate）：门控关闭时
    // Helper 在任何宿主（app/键盘扩展/SpringBoard）一律不装 hook。沙盒宿主
    // 读不到偏好文件时由 MTConfigService 的 gate.plist 快照兜底。
    // 细节参数读 Metis 自有细节域（com.lindo.metis.clipboard）；沙盒宿主读
    // 不到时维持默认值——与旧版 KayokoX 行为一致，且绝不读旧插件域。
    [MTModuleGate reload];
    if (![MTModuleGate moduleEnabled:MTModuleClipboard]) {
        KayokoHelperConfiguration *configuration = [[self alloc] init];
        configuration.enabled = NO;
        return configuration;
    }
    NSUserDefaults *preferences = [[NSUserDefaults alloc] initWithSuiteName:kKayokoPreferencesIdentifier];

    [preferences registerDefaults:@{
        kKayokoPreferenceKeyEnabled : @(kKayokoPreferenceKeyEnabledDefaultValue),
        kKayokoPreferenceKeyActivationMethod : @(kKayokoPreferenceKeyActivationMethodDefaultValue),
        kKayokoPreferenceKeyGestureRecognizerMode : @(kKayokoPreferenceKeyGestureRecognizerModeDefaultValue),
        kKayokoPreferenceKeyAutomaticallyPaste : @(kKayokoPreferenceKeyAutomaticallyPasteDefaultValue),
        kKayokoPreferenceKeyPlayHapticFeedback : @(kKayokoPreferenceKeyPlayHapticFeedbackDefaultValue)
    }];

    KayokoHelperConfiguration *configuration = [[self alloc] initWithPreferences:preferences];
    return configuration;
}

- (instancetype)initWithPreferences:(NSUserDefaults *)preferences {
    self = [super init];
    if (self) {
        _enabled = [[preferences objectForKey:kKayokoPreferenceKeyEnabled] boolValue];
        _activationMethod = [[preferences objectForKey:kKayokoPreferenceKeyActivationMethod] unsignedIntegerValue];
        _gestureRecognizerMode =
            [[preferences objectForKey:kKayokoPreferenceKeyGestureRecognizerMode] unsignedIntegerValue];
        if (_gestureRecognizerMode != kKayokoGestureRecognizerModeClassic &&
            _gestureRecognizerMode != kKayokoGestureRecognizerModeSystem) {
            _gestureRecognizerMode = kKayokoPreferenceKeyGestureRecognizerModeDefaultValue;
        }
        _automaticallyPasteEnabled = [[preferences objectForKey:kKayokoPreferenceKeyAutomaticallyPaste] boolValue];
        _hapticFeedbackEnabled = [[preferences objectForKey:kKayokoPreferenceKeyPlayHapticFeedback] boolValue];
    }
    return self;
}

@end
