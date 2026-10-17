#import "MTCapturePreferences.h"
#import "MTConstants.h"
#import "MTCaptureLog.h"
#import "MTModuleGate.h"

// .m 内部可写版本：加载时一次性填充，之后只读。
@interface MTConfig ()
@property (nonatomic, readwrite) BOOL enabled;
@property (nonatomic, readwrite) MTOutputAction defaultResultAction;
@property (nonatomic, readwrite) BOOL saveAlsoCopy;
@property (nonatomic, readwrite) BOOL showResultBubble;
@property (nonatomic, readwrite) BOOL floatingSnapShadow;
@property (nonatomic, readwrite) CGFloat selectionSnapEdgeDistance;
@property (nonatomic, readwrite) BOOL screenshotHaptic;
@property (nonatomic, readwrite) BOOL areaRememberLastRect;
@property (nonatomic, readwrite) CGFloat editorDefaultLineWidth;
@property (nonatomic, strong, readwrite) MTLongShotOptions *longShotOptions;
@end

@implementation MTConfig

- (instancetype)initDefault {
    if (self = [super init]) {
        _enabled = YES;
        _defaultResultAction = (MTOutputAction)MTDefaultResultAction;
        _saveAlsoCopy = YES;
        _showResultBubble = YES;
        _floatingSnapShadow = YES;
        _selectionSnapEdgeDistance = 12.0;
        _screenshotHaptic = YES;
        _areaRememberLastRect = NO;
        _editorDefaultLineWidth = MTDefaultEditorLineWidth;
        _longShotOptions = [[MTLongShotOptions alloc] initWithValues:@{}];
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<MTConfig enabled=%d action=%ld saveAlsoCopy=%d bubble=%d snapShadow=%d haptic=%d rememberRect=%d lineWidth=%.1f>",
            self.enabled, (long)self.defaultResultAction, self.saveAlsoCopy,
            self.showResultBubble, self.floatingSnapShadow, self.screenshotHaptic, self.areaRememberLastRect,
            self.editorDefaultLineWidth];
}

@end

static BOOL MTPrefBool(NSString *key, BOOL defaultValue) {
    Boolean valid = false;
    Boolean value = CFPreferencesGetAppBooleanValue((__bridge CFStringRef)key,
                                                    (__bridge CFStringRef)MTCapturePreferencesDomain,
                                                    &valid);
    return valid ? (BOOL)value : defaultValue;
}

static NSInteger MTPrefInteger(NSString *key, NSInteger defaultValue) {
    Boolean valid = false;
    CFIndex value = CFPreferencesGetAppIntegerValue((__bridge CFStringRef)key,
                                                    (__bridge CFStringRef)MTCapturePreferencesDomain,
                                                    &valid);
    return valid ? (NSInteger)value : defaultValue;
}

static CGFloat MTPrefDouble(NSString *key, CGFloat defaultValue) {
    id obj = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                         (__bridge CFStringRef)MTCapturePreferencesDomain));
    if ([obj isKindOfClass:[NSNumber class]]) {
        return [(NSNumber *)obj doubleValue];
    }
    return defaultValue;
}

@implementation MTCapturePreferences

static MTConfig *_currentConfig = nil;

+ (MTConfig *)config {
    @synchronized(self) {
        if (!_currentConfig) {
            [self reload];
        }
        return _currentConfig;
    }
}

+ (void)reload {
    MTConfig *config = [[MTConfig alloc] initDefault];

    // Metis 门控桥接：模块启停的唯一权威是 com.lindo.metis 域（MTModuleGate）。
    // 旧 Enabled key 仅在迁移 importer 中读取，运行端不再消费。
    [MTModuleGate reload];
    config.enabled = [MTModuleGate moduleEnabled:MTModuleCapture];
    config.showResultBubble = MTPrefBool(MTKeyShowResultBubble, YES);
    config.floatingSnapShadow = MTPrefBool(MTKeyFloatingSnapShadow, YES);
    config.selectionSnapEdgeDistance = MAX(0.0, MIN(60.0, MTPrefDouble(MTKeySelectionSnapEdgeDistance, 12.0)));
    config.screenshotHaptic = MTPrefBool(MTKeyScreenshotHaptic, YES);
    config.areaRememberLastRect = MTPrefBool(MTKeyAreaRememberLastRect, NO);

    NSInteger action = MTPrefInteger(MTKeyDefaultResultAction, MTDefaultResultAction);
    config.defaultResultAction = (MTOutputAction)MAX(0, MIN(4, action));
    config.saveAlsoCopy = MTPrefBool(MTKeySaveAlsoCopy, YES);

    CGFloat lineWidth = MTPrefDouble(MTKeyEditorDefaultLineWidth, MTDefaultEditorLineWidth);
    config.editorDefaultLineWidth = MAX(0.5, MIN(16.0, lineWidth));
    NSMutableDictionary *longValues = [NSMutableDictionary dictionary];
    for (NSString *key in MTLongShotOptions.preferenceKeys) {
        id value = CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                              (__bridge CFStringRef)MTCapturePreferencesDomain));
        if (value) longValues[key] = value;
    }
    config.longShotOptions = [[MTLongShotOptions alloc] initWithValues:longValues];

    @synchronized(self) {
        _currentConfig = config;
    }
    MTCaptureLogInfo(@"config reloaded: %@", config);
}

@end
