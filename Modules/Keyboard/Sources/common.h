#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <math.h>
#if defined(THEOS_PACKAGE_SCHEME_ROOTHIDE)
#import <roothide.h>
#define MT_ROOT_PATH_NS(path) jbroot(path)
#else
#import <rootless.h>
#define MT_ROOT_PATH_NS(path) ROOT_PATH_NS(path)
#endif
#import <spawn.h>

@class CPDistributedMessagingCenter;

#import "MTPrefsManager.h"
#import "MTGlobals.h"

#define bundlePath MT_ROOT_PATH_NS(@"/Library/PreferenceBundles/MetisKeyboardPrefs.bundle")
//#define typexBundlePath @"/Library/Application Support/MetisKeyboard.bundle"
#define LOCALIZED(str) [tweakBundle localizedStringForKey:str value:@"" table:nil]

// 细节配置域：Metis 自有域（com.lindo.metis.keyboard），不读取、不迁移旧
// TypeX 插件域（com.lindo.typex）的任何旧值；模块启停权威在
// com.lindo.metis（MTModuleGate），运行端 enabledBOOL 一律被门控值覆盖。
#define kIdentifier @"com.lindo.metis.keyboard"
#define kIPCCenterPrefsManager @"com.lindo.typex.prefsmanager"
#define kIPCCenterKeyboard @"com.lindo.typex"
#define kPrefsChangedIdentifier @"com.lindo.typex/prefschanged"
#define kPrefsPath @"/var/mobile/Library/Preferences/com.lindo.metis.keyboard.plist"

#define kEnabledkey @"enabledBOOL"
#define kEnabledHaptickey @"hapticBOOL"
#define kShortcutskey @"shortcuts"
#define kTopShortcutskey @"topshortcuts"
#define kColorEnabledkey @"colorBOOL"
#define kToggledOnkey @"toggledOnBOOL"
#define kDedicatedGestureButtonkey @"gesturebutton"
#define kGestureTypekey @"gesturetype"
#define kCustomActionskey @"customactions"
#define kTopCustomActionskey @"topcustomactions"
#define kTapCustomActionskey @"tapactions"
#define kSwipeUpCustomActionskey @"swipeupactions"
#define kSwipeDownCustomActionskey @"swipedownactions"
#define kSwipeLeftCustomActionskey @"swipeleftactions"
#define kSwipeRightCustomActionskey @"swiperightactions"
// User-defined actions shown above the built-in actions in every gesture
// picker. Definitions are global so the same ordered list is available to the
// top and bottom toolbar configurations.
#define kLinkActionskey @"linkactions"
#define kLinkActionSelectorPrefix @"__typex_link_action_"
// 自定义动作分组：条目上的可选组名 + 有序分组注册表（管理与选择页展示专用，
// 执行路径不读取）。
#define kLinkActionGroupsKey @"linkactiongroups"
#define kCustomActionGroupKey @"group"
#define kLinkActionCollapsedGroupsKey @"linkactioncollapsedgroups"

// Custom action types, stored on each linkactions entry under "type".  An
// entry without a type is a legacy definition and keeps the old behavior of
// auto-detecting web URL / URL scheme / bundle identifier from its link.
// "url" additionally stores the APP内打开 choice under "inapp" (default YES).
// Entries whose payload supports @@@ (legacy / url / urlscheme) store the
// 剪切替换 choice under "cutreplace": ON clears the input field after its
// text is passed in (cut), OFF keeps the field's content (copy, default).
#define kCustomActionTypeKey @"type"
#define kCustomActionInAppKey @"inapp"
#define kCustomActionUsePullOverKey @"pullover"
#define kCustomActionFloatingKey @"floating"
#define kCustomActionCutReplaceKey @"cutreplace"
#define kCustomActionTypeURLScheme @"urlscheme"
#define kCustomActionTypeText @"text"
// Ordered literal text records; text actions never read the old link payload.
#define kCustomActionTextRecordsKey @"textrecords"
#define kCustomActionTypeURL @"url"
#define kCustomActionTypeOpenApp @"openapp"
#define kCustomActionTypeShortcut @"shortcut"
#define kCustomActionTypeJavaScript @"javascript"
#define kCustomActionTypeSystem @"system"
#define kCustomActionSystemIdentifierKey @"systemaction"
// Quick actions persist the owning bundle in "link" and the stable item type.
#define kCustomActionShortcutTypeKey @"shortcuttype"
#define kCustomActionShortcutTitleKey @"shortcuttitle"
// Legacy tap-mode flag, read only to preserve configurations from older builds.
#define kTapSubActionsEntryKey @"tapsubactions"

#define kSubActionskey @"subactions"
#define kTopSubActionskey @"topsubactions"
#define kShortcutsTintEnabled @"shortcutstintBOOL"
#define kShortcutsBackgroundTintEnabled @"shortcutsbackgroundtintBOOL"
#define kPasteAndGoEnabledkey @"pasteandgo"
#define kHeightOffsetkey @"heightoffset"
#define kEnabledSmartDeleteForwardkey @"smartdeleteforwardBOOL"
#define kShortLabelEnabledKey @"shortLabelBOOL"
#define kCellHeightkey @"shortcutheight"
#define kCellRadiuskey @"shortcutradius"
#define kCellSpacingkey @"shortcutspacing"
#define kBottomSpacingKey @"bottomspacing"
#define kCellBorderEnabledkey @"shortcutborderBOOL"
#define kCellBorderWidthkey @"shortcutborderwidth"
#define kButtonWidthScalekey @"shortcutwidthscale"
#define kSubActionPanelScaleKey @"subactionpanelscale"
// 悬浮打开应用小窗的默认最大占屏比例（百分比存储，如 72 = 72%）。
#define kFloatingCardMaxScaleKey @"floatingcardmaxscale"
// 悬浮打开应用小窗的默认水平停靠位置（0=居左 1=居中 2=居右，缺省居中）。
#define kFloatingCardPositionKey @"floatingcardposition"
// One mode switch: shelf replaces only the keyboard bottom action toolbar.
#define kFloatingShelfEnabledKey @"floatingappshelfBOOL"
// 键盘收起把手：解锁亮屏且键盘隐藏时显示的小入口，点按弹出 App 面板
// （数据源见 kKbdHandleAppsKey；未配置时为最近悬浮列表）。
#define kKbdHandleEnabledKey @"kbdhandleBOOL"
// 把手停靠侧（0=左侧 1=右侧，初始高度在底部；拖动后保存高度与缩边状态）。
#define kKbdHandlePositionKey @"kbdhandleposition"
#define kKbdHandleAnchorKey @"kbdhandleanchor"
#define kKbdHandleNubbedKey @"kbdhandlenubbed"
// 自动隐藏：开启后把手静置超过设定秒数滑入屏幕边缘只露一小截（与手动缩边
// 同状态并持久化，PullOver-X 把手 nub 同款语义），点按或向内拖出恢复；
// 键盘弹出/锁屏/息屏时才整体隐藏。
#define kKbdHandleAutoHideKey @"kbdhandleautohideBOOL"
// 自动隐藏时长（秒，0.5~10 步进 0.5，缺省 3 秒；读取侧夹回范围）。
#define kKbdHandleAutoHideSecondsKey @"kbdhandleautohidesecs"
#define kKbdHandleAutoHideSecondsDefault 3.0
#define kKbdHandleAutoHideSecondsMinimum 0.5
#define kKbdHandleAutoHideSecondsMaximum 10.0
// 把手面板固定应用列表：bundleID 数组（AltList 多选页存储格式，集合序不保证，
// 展示侧按显示名排序）。空数组时面板回退为最近悬浮列表。
#define kKbdHandleAppsKey @"kbdhandleapps"
// Optional single-hand launcher; absence is the legacy rail.
#define kKbdQuickLauncherKey @"kbdquicklauncherBOOL"
#define kKbdLauncherOrderKey @"kbdlauncherorder"
#define kKbdLauncherAliasesKey @"kbdlauncheraliases"
#define kKbdLauncherUsageKey @"kbdlauncherusage"
// 面板固定容量：最近悬浮 App 个数，超出按最近优先保留。
#define kKbdCollapsePanelCapacity 6
// 顶部工具栏固定按"每行个数"换行，第一行紧贴键盘、第二行向上堆叠。
// 行距只作用于两行之间；旧的多行开关不再参与布局或容量计算。
#define kButtonsPerRowKey @"buttonsperrow"
#define kMultiRowSpacingKey @"multirowspacing"
#define buttonsPerRowDefault 6.0f
#define multiRowSpacingDefault 4.0f
#define maxMultiRowRows 2
// A toolbar stores any number of records; its active capacity is one surface.
// The top surface contains one or two rows of the configured column count.
#define maxEnabledTopButtons 16
#define maxMultiRowButtons maxEnabledTopButtons
#define kSpongebobEntropyKey @"spongebobEntropy"
// Clipboard image quick paste: floating thumbnail above the keyboard +
// auto-answering of the iOS 16+ paste-permission alert, one switch for both.
#define kPasteImageChipKey @"pasteimagechipBOOL"
// BundleID -> @YES map of apps where the paste chip may appear. A missing key
// or an entry without the host bundle ID means off: the per-app switches in
// Settings all default to off.
#define kPasteImageChipAppsKey @"pasteimagechipapps"
#define kbuttonsImages12 0
#define kbuttonsImages13 1
#define kselectors 2
#define kshortLabel 4

#define tweakVersion @"1.3.1"
#define maxdefaultshortcuts 6
// The fixed bottom toolbar has one surface with up to eight active buttons.
#define maxEnabledBottomButtons 8


#define heightOffsetDefault 60.0f
// Bottom dock geometry shared by the live toolbar and its Settings preview.
#define MTBottomToolbarLeadingInset 69.0f
#define MTBottomToolbarTrailingInset 60.0f
#define MTBottomToolbarBottomInset 22.0f
#define MTBottomToolbarCellTopInset 22.0f

#define searchedCountEaster 100

#define spacingBetweenCellsDefault 3
#define topBottomSpacingDefault 0.0f
#define cellsHeightDefault 30
#define cellsRadiusDefault 5

#define buttonBorderWidthDefault 1.0f
#define buttonWidthScaleDefault 100.0f
#define subActionPanelScaleDefault 100.0f

// The shared snapshot must live where sandboxed app hosts can read it.  The
// jailbreak root (/var/jb on rootless, resolved by MT_ROOT_PATH_NS) is readable
// from inside app sandboxes -- this tweak already loads its bundle resources
// from /var/jb/Library -- while /var/mobile/Library/** is not.  The package
// stages the directory world-writable (no sticky bit: mobile writers must be
// able to atomically replace the root-owned seed file) so mobile processes
// (Settings, SpringBoard) can refresh the snapshot without a helper daemon.
// Metis 布局：共享目录统一收口 /Library/Metis/Config/ 下（不使用旧插件包
// 目录，避免读到旧插件残留的快照/缓存旧值；gate.plist 门控镜像同目录）。
#define TypeXCachePath MT_ROOT_PATH_NS(@"/Library/Metis/Config/keyboard-cache")
#define TypeXSharedPrefsPath MT_ROOT_PATH_NS(@"/Library/Metis/Config/keyboard-shared.plist")

// Settings and SpringBoard exchange quick-action data through an isolated
// CFPreferences domain. On RootHide iOS 16, SpringBoard can read shared files
// but its sandbox rejects direct writes under /Library/Metis; cfprefsd provides
// the supported cross-process persistence path. Requests carry
// {format: 3, requestID, bundles}; responses replace one complete generation.
// 域名为 Metis 自有（com.lindo.metis.quickactions），与旧插件的
// quickactions 域互不相通。
#define TypeXQuickActionDomain @"com.lindo.metis.quickactions"
#define MTQuickActionRequestKey @"request-v3"
#define TypeXQuickActionStatusKey @"status-v3"
#define TypeXQuickActionSnapshotKey @"snapshot-v3"
#define kShortcutRefreshRequestIdentifier @"com.lindo.typex/shortcutrefresh"
#define kShortcutSnapshotChangedIdentifier @"com.lindo.typex/shortcutschanged"

// MetisKeyboard 自带 AI 面板通道：工具栏进程只写请求（{format:2, requestID, created,
// mode: text|image|empty, origin: sb|app, text?}），SpringBoard 端收到 Darwin
// 通知后整包读取并在 SB 进程内创建 MTAIPanel 悬浮窗。面板不能在键盘进程承载：
// 窗口会被限制在键盘宿主区域内（第三方键盘扩展里完全无法悬浮）。与快捷方式
// 目录共用隔离域，避免再开共享面。
#define MTAIChatRequestKey @"ai-chat-request"
#define kAIChatRequestIdentifier @"com.lindo.typex/aichat"

// Complete SpringBoard-authored snapshot of each app's current static and
// dynamic UIApplicationShortcutItems. The value is replaced as one generation,
// so removed apps and actions cannot survive an incremental merge:
//   {format: 3, generation: requestID, updated: time,
//    apps: {bundleID: {name, items: [{type, title, subtitle, source}]}}}

static inline id MTQuickActionSharedValue(NSString *key) {
    CFStringRef domain = (__bridge CFStringRef)TypeXQuickActionDomain;
    CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    return CFBridgingRelease(CFPreferencesCopyValue((__bridge CFStringRef)key,
                                                    domain,
                                                    kCFPreferencesCurrentUser,
                                                    kCFPreferencesAnyHost));
}

static inline BOOL MTSetQuickActionSharedValue(id value, NSString *key) {
    CFStringRef domain = (__bridge CFStringRef)TypeXQuickActionDomain;
    CFPreferencesSetValue((__bridge CFStringRef)key,
                          (__bridge CFPropertyListRef)value,
                          domain,
                          kCFPreferencesCurrentUser,
                          kCFPreferencesAnyHost);
    return CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}

// Reverse-DNS shape test shared with the SpringBoard-side request handler so
// the channel can never be coerced into acting on a non-identifier payload.
static inline BOOL MTIsValidBundleIdentifier(NSString *value) {
    if (![value isKindOfClass:[NSString class]] || value.length == 0) return NO;
    NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:@"^[A-Za-z0-9_](?:[A-Za-z0-9_-]*[A-Za-z0-9_])?(?:\\.[A-Za-z0-9_](?:[A-Za-z0-9_-]*[A-Za-z0-9_])?)+$"
                                                                                options:0
                                                                                  error:nil];
    return [expression firstMatchInString:value options:0 range:NSMakeRange(0, value.length)] != nil;
}

static inline BOOL MTIsValidAppShortcutType(NSString *value) {
    return [value isKindOfClass:NSString.class] && value.length > 0 && value.length <= 512 &&
        ![value hasPrefix:@"com.apple.springboard."] &&
        [value rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location == NSNotFound;
}

// Shared URL-shape test for the openurl channel action (and the scheme
// classification of custom-action links): a scheme-shaped URL of bounded
// length whose scheme is not an executable/document one (javascript:, data:,
// file:, about:), so the channel can never be coerced beyond "open this URL".
static inline BOOL MTIsOpenableSchemeURLString(NSString *value) {
    if (![value isKindOfClass:[NSString class]] || value.length == 0 || value.length > 2048) return NO;
    NSRange schemeRange = [value rangeOfString:@"^[A-Za-z][A-Za-z0-9+.-]*:" options:NSRegularExpressionSearch];
    if (schemeRange.location != 0) return NO;
    NSURL *url = [NSURL URLWithString:value];
    if (!url || url.scheme.length == 0) return NO;
    NSString *lowercaseScheme = url.scheme.lowercaseString;
    return ![lowercaseScheme isEqualToString:@"javascript"] &&
        ![lowercaseScheme isEqualToString:@"data"] &&
        ![lowercaseScheme isEqualToString:@"file"] &&
        ![lowercaseScheme isEqualToString:@"about"];
}

static inline NSString *MTScopedPreferenceKey(NSString *baseKey, NSString *configuration) {
    if ([configuration isEqualToString:@"top"]) {
        return [@"top" stringByAppendingString:baseKey];
    }
    return baseKey;
}

static inline NSInteger MTMultiRowButtonsPerRowFromPreferences(NSDictionary *preferences) {
    id value = [preferences isKindOfClass:[NSDictionary class]]
        ? preferences[MTScopedPreferenceKey(kButtonsPerRowKey, @"top")] : nil;
    NSInteger perRow = [value respondsToSelector:@selector(integerValue)]
        ? [value integerValue] : (NSInteger)buttonsPerRowDefault;
    return MIN(8, MAX(1, perRow));
}

// Two rows are the hard layout limit. The configured per-row count can lower
// the active capacity, while eight columns keep the absolute ceiling at 16.
static inline NSInteger MTMultiRowCapacityForPreferences(NSDictionary *preferences) {
    return MIN(maxMultiRowButtons,
               MTMultiRowButtonsPerRowFromPreferences(preferences) * maxMultiRowRows);
}

// 悬浮小窗布局把自动适配比例封顶在这个配置值上（0.30–1.00，缺省 0.72）。
// 非法值（含 NaN）一律回退缺省，读配置失败不产生危险布局。
static inline CGFloat MTFloatingCardMaxScaleFromPreferences(NSDictionary *preferences) {
    id value = [preferences isKindOfClass:[NSDictionary class]] ? preferences[kFloatingCardMaxScaleKey] : nil;
    CGFloat scale = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] / 100.0 : 0.72;
    if (!(scale >= 0.30) || scale > 1.0) scale = 0.72;
    return scale;
}

// 悬浮小窗打开时的默认水平位置：0=居左、1=居中、2=居右。非法值一律回退居中。
static inline NSInteger MTFloatingCardPositionFromPreferences(NSDictionary *preferences) {
    id value = [preferences isKindOfClass:[NSDictionary class]] ? preferences[kFloatingCardPositionKey] : nil;
    NSInteger position = [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : 1;
    return (position >= 0 && position <= 2) ? position : 1;
}

// 把手停靠角：0=左下、1=右下。非法值一律回退左下，读配置失败不产生危险布局。
static inline NSInteger MTKbdHandlePositionFromPreferences(NSDictionary *preferences) {
    id value = [preferences isKindOfClass:[NSDictionary class]] ? preferences[kKbdHandlePositionKey] : nil;
    NSInteger position = [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : 0;
    return (position == 0 || position == 1) ? position : 0;
}

// 把手自动隐藏时长（秒）：非法/缺省一律回退 3 秒并夹回 0.5~10，永不外溢。
static inline double MTKbdHandleAutoHideSecondsFromPreferences(NSDictionary *preferences) {
    id value = [preferences isKindOfClass:[NSDictionary class]] ? preferences[kKbdHandleAutoHideSecondsKey] : nil;
    double seconds = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : kKbdHandleAutoHideSecondsDefault;
    if (!isfinite(seconds)) seconds = kKbdHandleAutoHideSecondsDefault;
    return MIN(MAX(seconds, kKbdHandleAutoHideSecondsMinimum), kKbdHandleAutoHideSecondsMaximum);
}

// 把手面板固定应用列表：只接受 bundleID 字符串数组并去重，其余格式回退空表。
static inline NSArray<NSString *> *MTKbdHandleAppsFromPreferences(NSDictionary *preferences) {
    id value = [preferences isKindOfClass:[NSDictionary class]] ? preferences[kKbdHandleAppsKey] : nil;
    if (![value isKindOfClass:[NSArray class]]) return @[];
    NSMutableOrderedSet<NSString *> *identifiers = [NSMutableOrderedSet orderedSet];
    for (id item in value) {
        if ([item isKindOfClass:[NSString class]] && [(NSString *)item length] > 0) [identifiers addObject:item];
    }
    return identifiers.array;
}

// With paging removed, every enabled button must fit the current toolbar surface.
static inline NSInteger MTToolbarCapacityForPreferences(NSDictionary *preferences, NSString *configuration) {
    if (![configuration isEqualToString:@"top"]) return maxEnabledBottomButtons;
    return MTMultiRowCapacityForPreferences(preferences);
}

static inline NSArray *MTToolbarOrderFittingCapacity(NSArray *order, NSDictionary *preferences, NSString *configuration) {
    if (![order isKindOfClass:NSArray.class] || order.count < 2 ||
        ![order[0] isKindOfClass:NSArray.class] || ![order[1] isKindOfClass:NSArray.class]) return order;
    NSInteger remaining = MTToolbarCapacityForPreferences(preferences, configuration);
    NSMutableArray *buttons = [NSMutableArray array];
    for (id item in order[0]) {
        if (![item isKindOfClass:NSDictionary.class] || [item[@"disabled"] boolValue]) {
            [buttons addObject:item];
            continue;
        }
        if (remaining-- > 0) [buttons addObject:item];
        else {
            NSMutableDictionary *disabled = [item mutableCopy];
            disabled[@"disabled"] = @YES;
            [buttons addObject:disabled];
        }
    }
    return @[[buttons copy], order[1]];
}

// Fields whose text was set programmatically start editing with the caret at
// the leading edge; park it past the existing text so a tap continues typing
// where the text ends. Works for UITextField and UITextView alike.
static inline void MTPlaceCaretAtEnd(id<UITextInput> field) {
    if (![field conformsToProtocol:@protocol(UITextInput)]) return;
    UITextPosition *end = field.endOfDocument;
    field.selectedTextRange = [field textRangeFromPosition:end toPosition:end];
}

// Each gesture has an independent ordered action list. Long press retains
// the historical "customactions" key; tap and each swipe use their own keys.
typedef NS_ENUM(NSInteger, MTShortcutGestureType) {
    MTShortcutGestureLongPress = 0,
    MTShortcutGestureSwipeUp = 1,
    MTShortcutGestureSwipeDown = 2,
    MTShortcutGestureSwipeLeft = 3,
    MTShortcutGestureSwipeRight = 4,
    MTShortcutGestureTap = 5,
};

// Temporary identifier used by the "add button" flow: the entry written into
// the tap store before the new button's action (and therefore its real
// identifier) exists. Rewritten to the real selector once the user picks one.
#define kNewButtonPendingIdentifier @"__typex_pending_new_button__"

// Buttons saved without a tap action get a synthetic identifier so gesture
// stores never collide between them. They render on the toolbar but stay
// inert until a tap action is configured for them.
#define kDraftActionPrefix @"__typexdraft_"

static inline BOOL MTIsDraftActionSelector(NSString *selector) {
    return [selector isKindOfClass:[NSString class]] && [selector hasPrefix:kDraftActionPrefix];
}

static inline BOOL MTIsLinkActionSelector(NSString *selector) {
    return [selector isKindOfClass:[NSString class]] && [selector hasPrefix:kLinkActionSelectorPrefix];
}

static inline NSString *MTCustomActionsKeyForGesture(int gestureType, NSString *configuration) {
    NSString *baseKey;
    switch (gestureType) {
        case MTShortcutGestureTap: baseKey = kTapCustomActionskey; break;
        case MTShortcutGestureSwipeUp: baseKey = kSwipeUpCustomActionskey; break;
        case MTShortcutGestureSwipeDown: baseKey = kSwipeDownCustomActionskey; break;
        case MTShortcutGestureSwipeLeft: baseKey = kSwipeLeftCustomActionskey; break;
        case MTShortcutGestureSwipeRight: baseKey = kSwipeRightCustomActionskey; break;
        default: baseKey = kCustomActionskey; break;
    }
    return MTScopedPreferenceKey(baseKey, configuration);
}

// Shared by Settings and toolbar hosts. New gesture entries store an ordered
// selectors array; an explicit empty array disables the gesture and must never
// resurrect a legacy/default action. Legacy preferences are read without writes.
static inline NSArray<NSString *> *MTGestureActionSelectors(NSDictionary *preferences, NSString *identifier,
                                                          int gestureType, NSString *configuration) {
    if (![preferences isKindOfClass:[NSDictionary class]] ||
        ![identifier isKindOfClass:[NSString class]] || identifier.length == 0) return @[];
    id stored = preferences[MTCustomActionsKeyForGesture(gestureType, configuration)];
    NSDictionary *legacyEntry = nil;
    if ([stored isKindOfClass:[NSArray class]]) {
        for (NSDictionary *entry in stored) {
            if (![entry isKindOfClass:[NSDictionary class]] || ![entry[@"identifier"] isEqual:identifier]) continue;
            if (entry[@"selectors"] != nil) {
                NSMutableArray *selectors = [NSMutableArray array];
                id values = entry[@"selectors"];
                if ([values isKindOfClass:[NSArray class]]) {
                    for (id value in values) {
                        if ([value isKindOfClass:[NSString class]] && [value length] > 0) [selectors addObject:value];
                    }
                }
                return selectors;
            }
            if (!legacyEntry) legacyEntry = entry;
        }
    }

    BOOL usesLegacySubActions = gestureType == MTShortcutGestureLongPress;
    if (gestureType == MTShortcutGestureTap) {
        id sections = preferences[MTScopedPreferenceKey(kShortcutskey, configuration)];
        if ([sections isKindOfClass:[NSArray class]]) {
            for (id section in sections) {
                if (![section isKindOfClass:[NSArray class]]) continue;
                for (NSDictionary *entry in section) {
                    if (![entry isKindOfClass:[NSDictionary class]] || ![entry[@"selector"] isEqual:identifier]) continue;
                    id flag = entry[kTapSubActionsEntryKey];
                    usesLegacySubActions = [flag respondsToSelector:@selector(boolValue)] && [flag boolValue];
                }
            }
        }
    }
    if (usesLegacySubActions) {
        NSMutableArray *selectors = [NSMutableArray array];
        id entries = preferences[MTScopedPreferenceKey(kSubActionskey, configuration)];
        if ([entries isKindOfClass:[NSArray class]]) {
            for (NSDictionary *entry in entries) {
                if (![entry isKindOfClass:[NSDictionary class]] || ![entry[@"identifier"] isEqual:identifier]) continue;
                id selector = entry[@"selector"];
                if ([selector isKindOfClass:[NSString class]] && [selector length] > 0) [selectors addObject:selector];
            }
        }
        // The previous runtime ignored the old long-press single-action store.
        return selectors;
    }

    id selector = legacyEntry[@"selector2"] ?: legacyEntry[@"selector"];
    if ([selector isKindOfClass:[NSString class]] && [selector length] > 0) return @[selector];
    if (gestureType == MTShortcutGestureTap && !MTIsDraftActionSelector(identifier) &&
        ![identifier isEqualToString:kNewButtonPendingIdentifier]) return @[identifier];
    return @[];
}

static inline UIColor *MTColorFromHex(NSString *value, NSString *fallback) {
    NSString *hex = [value isKindOfClass:[NSString class]] ? value : fallback;
    hex = [hex stringByReplacingOccurrencesOfString:@"#" withString:@""];
    unsigned int color = 0;
    NSScanner *scanner = [NSScanner scannerWithString:hex];
    if (![scanner scanHexInt:&color]) hex = [fallback stringByReplacingOccurrencesOfString:@"#" withString:@""];
    if (hex.length == 6) {
        scanner = [NSScanner scannerWithString:hex];
        [scanner scanHexInt:&color];
        return [UIColor colorWithRed:((color >> 16) & 0xff) / 255.0
                               green:((color >> 8) & 0xff) / 255.0
                                blue:(color & 0xff) / 255.0
                               alpha:1.0];
    }
    if (hex.length == 8) {
        scanner = [NSScanner scannerWithString:hex];
        [scanner scanHexInt:&color];
        return [UIColor colorWithRed:((color >> 16) & 0xff) / 255.0
                               green:((color >> 8) & 0xff) / 255.0
                                blue:(color & 0xff) / 255.0
                               alpha:((color >> 24) & 0xff) / 255.0];
    }
    return [UIColor redColor];
}

static inline void MTRunShellCommand(NSString *command) {
    if (command.length == 0) return;

    const char *shell = "/bin/bash";
    const char *arguments[] = {shell, "-c", command.UTF8String, NULL};
    pid_t pid = 0;
    extern char **environ;
    posix_spawn(&pid, shell, NULL, NULL, (char *const *)arguments, environ);
}

static inline UIInterfaceOrientation MTCurrentInterfaceOrientation(void) {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                UIInterfaceOrientation orientation = ((UIWindowScene *)scene).interfaceOrientation;
                if (orientation != UIInterfaceOrientationUnknown) return orientation;
            }
        }
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return UIApplication.sharedApplication.statusBarOrientation;
#pragma clang diagnostic pop
}

static inline UIWindow *MTKeyWindow(void) {
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (window.isKeyWindow) return window;
            }
        }
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        if (window.isKeyWindow) return window;
    }
#pragma clang diagnostic pop
    return nil;
}

typedef NS_ENUM(NSInteger, MTPhonemesType){
    MTPhonemesTypeVowel,
    MTPhonemesTypeConsonent
};

typedef NS_ENUM(NSInteger, MTStudlyCapsType){
    MTStudlyCapsTypeRandom,
    MTStudlyCapsTypeAlternate,
    MTStudlyCapsTypeVowel,
    MTStudlyCapsTypeConsonent
};

@interface CPDistributedMessagingCenter : NSObject
+ (id)centerNamed:(id)arg1;
- (void)runServerOnCurrentThread;
- (void)registerForMessageName:(id)arg1 target:(id)arg2 selector:(SEL)arg3;
- (BOOL)sendMessageName:(id)arg1 userInfo:(id)arg2;
- (NSDictionary *)sendMessageAndReceiveReplyName:(id)arg1 userInfo:(id)arg2;
@end

@interface UIKeyboardEmojiCollectionInputView : NSObject {
    unsigned long long  _currentSection;
    double  _frameInset;
    bool  _hasShownAnimojiCell;
    bool  _hasShownAnimojiFirstTimeExperience;
    bool  _inputDelegateCanSupportAnimoji;
    bool  _isDraggingInputView;
    bool  _shouldRetryFetchingAnimojiRecents;
    NSIndexPath * _tappedSkinToneEmoji;
    bool  _useWideAnimojiCell;
}
@end

@interface SBSRelaunchAction : NSObject
@property (nonatomic, readonly) unsigned long long options;
@property (nonatomic, readonly, copy) NSString *reason;
@property (nonatomic, readonly, retain) NSURL *targetURL;
+ (id)actionWithReason:(id)arg1 options:(unsigned long long)arg2 targetURL:(id)arg3;
- (id)initWithReason:(id)arg1 options:(unsigned long long)arg2 targetURL:(id)arg3;
- (unsigned long long)options;
- (id)reason;
- (id)targetURL;

@end

@interface FBSSystemService : NSObject
+ (id)sharedService;
- (void)sendActions:(id)arg1 withResult:(/*^block*/id)arg2;
- (void)openApplication:(NSString *)bundleIdentifier
                options:(NSDictionary *)options
             withResult:(void (^)(NSError *error))result;
@end

// FrontBoard open path that accepts an FBSOpenApplicationRequest; the raw
// bundle-identifier string form on FBSSystemService is rejected on current iOS.
@interface FBSOpenApplicationOptions : NSDictionary
+ (id)optionsWithDictionary:(NSDictionary *)dictionary;
@end

@interface FBSOpenApplicationRequest : NSObject
+ (id)requestWithBundleIdentifier:(NSString *)bundleIdentifier;
@end

@interface FBSOpenApplicationService : NSObject
+ (id)sharedService;
- (void)openApplication:(id)request
                options:(id)options
      withResultHandler:(void (^)(NSError *error))resultHandler;
@end
