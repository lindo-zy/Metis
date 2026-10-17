#import "MTConstants.h"

// MTBundleID 保留 PixPin 身份（外部 URL scheme / 错误域标识）；偏好域是
// Metis 自有域，不读取、不迁移旧 PixPin 插件域（com.lindo.metis.capture）
// 的任何旧值；模块启停权威在 com.lindo.metis（MTModuleGate）。
NSString * const MTBundleID = @"com.lindo.metis.capture";
NSString * const MTCapturePreferencesDomain = @"com.lindo.metis.capture";

CFStringRef const MTDarwinActivate = CFSTR("com.lindo.metis.capture/activate");
CFStringRef const MTDarwinCaptureFull = CFSTR("com.lindo.metis.capture/full");
CFStringRef const MTDarwinCaptureArea = CFSTR("com.lindo.metis.capture/area");
CFStringRef const MTDarwinCaptureFreeze = CFSTR("com.lindo.metis.capture/freeze");
CFStringRef const MTDarwinCaptureInstant = CFSTR("com.lindo.metis.capture/instant");
CFStringRef const MTDarwinCaptureMarkup = CFSTR("com.lindo.metis.capture/markup");
CFStringRef const MTDarwinCaptureLong = CFSTR("com.lindo.metis.capture/long");
CFStringRef const MTDarwinCaptureCancel = CFSTR("com.lindo.metis.capture/cancel");
CFStringRef const MTDarwinPreferencesReload = CFSTR("com.lindo.metis.capture/preferences/reload");

CFStringRef const MTDarwinSnapperForceOpen = CFSTR("com.jontelang.snapper3.force.open");
CFStringRef const MTDarwinSnapperForceInstantOpen = CFSTR("com.jontelang.snapper3.forceinstant.open");
CFStringRef const MTDarwinSnapperForceFreezeOpen = CFSTR("com.jontelang.snapper3.forcefreeze.open");
CFStringRef const MTDarwinSnapperCloseAll = CFSTR("com.jontelang.snapper3.close.all");
CFStringRef const MTDarwinSnapperCloseCrop = CFSTR("com.jontelang.snapper3.closecrop");

CFStringRef const MTDarwinShellXOpen = CFSTR("com.iosdump.screenshotshell.open");
CFStringRef const MTDarwinShellXOpenInstant = CFSTR("com.iosdump.screenshotshell.open.instant");
CFStringRef const MTDarwinShellXOpenFreeze = CFSTR("com.iosdump.screenshotshell.open.freeze");
CFStringRef const MTDarwinShellXClose = CFSTR("com.iosdump.screenshotshell.close");

CFStringRef const MTShellXTriggerArea = CFSTR("com.iosdump.screenshotshell.open");
CFStringRef const MTShellXTriggerInstant = CFSTR("com.iosdump.screenshotshell.open.instant");
CFStringRef const MTShellXTriggerFreeze = CFSTR("com.iosdump.screenshotshell.open.freeze");
CFStringRef const MTShellXTriggerHistory = CFSTR("com.iosdump.screenshotshell.history");
CFStringRef const MTShellXTriggerOpenLast = CFSTR("com.iosdump.screenshotshell.openlast");
CFStringRef const MTShellXTriggerClose = CFSTR("com.iosdump.screenshotshell.close");
CFStringRef const MTShellXTriggerAssistive = CFSTR("com.iosdump.screenshotshell/AssistiveScreenshot");

CFStringRef const MTShellXRouteLong = CFSTR("prefs://root=shellx_long");
CFStringRef const MTShellXRouteFull = CFSTR("prefs://root=shellx_full");
CFStringRef const MTShellXRouteMark = CFSTR("prefs://root=shellx_mark");
CFStringRef const MTShellXRouteEdit = CFSTR("prefs://root=shellx_edit");
CFStringRef const MTShellXRouteAI2 = CFSTR("prefs://root=shellx_ai2");
CFStringRef const MTShellXRouteTranslate = CFSTR("prefs://root=shellx_translate");
CFStringRef const MTShellXRouteScan = CFSTR("prefs://root=shellx_scan");

NSString * const MTNotificationResultUpdated = @"com.lindo.metis.capture/result/updated";

NSString * const MTKeyEnabled = @"Enabled";
NSString * const MTKeyDefaultResultAction = @"DefaultResultAction";
// 保存同时复制：任何保存动作同时写入剪贴板（默认开）。
NSString * const MTKeySaveAlsoCopy = @"SaveAlsoCopy";
NSString * const MTKeyAutoSaveToPhotos = @"AutoSaveToPhotos";
NSString * const MTKeyCopyToClipboard = @"CopyToClipboard";
NSString * const MTKeyShowResultBubble = @"ShowResultBubble";
NSString * const MTKeyFloatingSnapShadow = @"FloatingSnapShadow";
// 选区边缘吸附距离：0=关闭，拖动选框时边距屏幕边缘不超过该值即对齐边缘。
NSString * const MTKeySelectionSnapEdgeDistance = @"SelectionSnapEdgeDistance";
NSString * const MTKeyShowCompletionNotification = @"ShowCompletionNotification";
NSString * const MTKeyMuteScreenshotSound = @"MuteScreenshotSound";
NSString * const MTKeyScreenshotHaptic = @"ScreenshotHaptic";
NSString * const MTKeyEditorDefaultColor = @"EditorDefaultColor";
NSString * const MTKeyEditorDefaultLineWidth = @"EditorDefaultLineWidth";
NSString * const MTKeyEditorActionOrder = @"EditorActionOrder";
NSString * const MTKeyEditorToolOrder = @"EditorToolOrder";
NSString * const MTKeyEditorActionHidden = @"EditorActionHidden";
NSString * const MTKeyEditorToolHidden = @"EditorToolHidden";
NSString * const MTKeyEditorActionNames = @"EditorActionNames";
NSString * const MTKeyEditorToolNames = @"EditorToolNames";
NSString * const MTKeyEditorActionIcons = @"EditorActionIcons";
NSString * const MTKeyEditorToolIcons = @"EditorToolIcons";
NSString * const MTKeyEditorButtonIconSize = @"EditorButtonIconSize";
NSString * const MTKeySelectionButtonOrder = @"SelectionButtonOrder";
NSString * const MTKeySelectionButtonHidden = @"SelectionButtonHidden";
NSString * const MTKeySelectionButtonNames = @"SelectionButtonNames";
NSString * const MTKeySelectionButtonIcons = @"SelectionButtonIcons";
NSString * const MTKeySelectionButtonIconStyle = @"SelectionButtonIconStyle";
// 自定义 URL 按钮：行记录 CSV，行间 \n、字段间逗号（id,name,icon,url）；由 MTEditorOrder 解析。
NSString * const MTKeySelectionCustomButtons = @"SelectionCustomButtons";
NSString * const MTKeyAreaRememberLastRect = @"AreaRememberLastRect";
// 选区矩形以 NSStringFromCGRect 存储；与开关独立，关开关时清除。
NSString * const MTKeyAreaLastSelectionRect = @"AreaLastSelectionRect";
// 全屏标记收起把手位置以 NSStringFromCGPoint 存储；无开关，始终记忆。
NSString * const MTKeyMarkupHandleOrigin = @"MarkupHandleOrigin";
NSString * const MTKeyLongShotMode = @"LongShotMode";
NSString * const MTKeyLongShotAutoScroll = @"LongShotAutoScroll";
NSString * const MTKeyLongShotSampleInterval = @"LongShotSampleInterval";
NSString * const MTKeyLongShotIdleInterval = @"LongShotIdleInterval";
NSString * const MTKeyLongShotScrollDuration = @"LongShotScrollDuration";
NSString * const MTKeyLongShotSettleDuration = @"LongShotSettleDuration";
NSString * const MTKeyLongShotMaxSlices = @"LongShotMaxSlices";
NSString * const MTKeyLongShotMaxCanvasHeight = @"LongShotMaxCanvasHeight";
NSString * const MTKeyLongShotSliceQuality = @"LongShotSliceQuality";
NSString * const MTKeyLongShotOutputQuality = @"LongShotOutputQuality";

const NSInteger MTDefaultResultAction = 0;
const CGFloat MTDefaultEditorLineWidth = 4.0;

static NSString *MTCreateDirectoryIfNeeded(NSString *path, NSError **error) {
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        if (![[NSFileManager defaultManager] createDirectoryAtPath:path
                                       withIntermediateDirectories:YES
                                                        attributes:nil
                                                             error:error]) {
            return nil;
        }
    }
    return path;
}

NSString *MTTemporaryTasksRoot(void) {
    static NSString *path = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:@"PixPinTasks"];
        path = MTCreateDirectoryIfNeeded(root, nil) ?: [NSTemporaryDirectory() stringByAppendingPathComponent:@"PixPinTasks"];
    });
    return path;
}
