#import "MTContextSignalCenter.h"
#import "MTContextGroupEngine.h"
#import "MTPrefsManager.h"
#import "common.h"

NSNotificationName const MTContextGroupDidChangeNotification = @"MTContextGroupDidChangeNotification";

// 选区变化去抖：拖选过程中光标每移动一次都会改选区，不压住会让底栏抖成一片。
static const NSTimeInterval MTContextDebounceInterval = 0.2;
// 进入判定的选区/剪贴板文本上限：只用于分类与种子文本，超出部分对判定无意义。
static const NSUInteger MTContextSelectionTextLimit = 2000;
// 剪贴板内容在内存里的保留上限，超时即丢，避免复制过的密码长期驻留。
static const NSTimeInterval MTContextClipboardTextRetention = 120;

@interface MTContextSignalCenter ()
@property(nonatomic, strong, readwrite) MTContextDecision *currentDecision;
@property(nonatomic, weak) UIResponder *activeResponder;
@property(nonatomic, assign) NSUInteger selectionLength;
// 选区最后一次变化的时间：与 clipboardAt 比较，决定「刚复制」和「刚选中」谁更新。
@property(nonatomic, assign) NSTimeInterval selectionAt;
@property(nonatomic, copy) NSString *clipboardText;
@property(nonatomic, assign) BOOL clipboardAvailable;
@property(nonatomic, assign) NSTimeInterval clipboardAt;
@property(nonatomic, assign) NSUInteger pastedLength;
@property(nonatomic, assign) NSTimeInterval pasteAt;
@property(nonatomic, assign) NSUInteger evaluationGeneration;
@property(nonatomic, assign) BOOL observersInstalled;
@end

static NSTimeInterval MTContextNow(void) {
    return NSDate.date.timeIntervalSince1970;
}

FOUNDATION_EXPORT NSUInteger MTContextTextLengthForResponder(UIResponder *responder) {
    if ([responder isKindOfClass:UITextField.class]) return ((UITextField *)responder).text.length;
    if ([responder isKindOfClass:UITextView.class]) return ((UITextView *)responder).text.length;
    return 0;
}

static NSString *MTContextTextForResponder(UIResponder *responder) {
    if ([responder isKindOfClass:UITextField.class]) {
        UITextField *field = (UITextField *)responder;
        return field.secureTextEntry ? nil : field.text;
    }
    if ([responder isKindOfClass:UITextView.class]) return ((UITextView *)responder).text;
    return nil;
}

// 选区文本只在去抖后的判定里读一次：hook 只记录长度，避免拖选时反复取子串。
static NSString *MTContextSelectedText(UIResponder *responder) {
    if (![responder conformsToProtocol:@protocol(UITextInput)]) return nil;
    id<UITextInput> input = (id<UITextInput>)responder;
    @try {
        UITextRange *range = [input selectedTextRange];
        if (!range || [range isEmpty]) return nil;
        // 先量长度再取文本：textInRange: 会为整段选区立刻建串，全选 100KB 文本时
        // 每 200ms 一次能把主线程拖出可见卡顿。超长选区对分类没有意义，直接放弃。
        NSInteger length = [input offsetFromPosition:range.start toPosition:range.end];
        if (length <= 0 || (NSUInteger)length > MTContextSelectionTextLimit) return nil;
        NSString *text = [input textInRange:range];
        if (![text isKindOfClass:NSString.class] || !text.length) return nil;
        return text.length > MTContextSelectionTextLimit ? [text substringToIndex:MTContextSelectionTextLimit] : text;
    } @catch (__unused NSException *exception) {
        // 自定义 inputView 可能对 textInRange: 抛异常：当作「取不到文本」，不中断判定。
        return nil;
    }
}

@implementation MTContextSignalCenter

+ (instancetype)sharedCenter {
    static MTContextSignalCenter *center;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ center = [MTContextSignalCenter new]; });
    return center;
}

- (instancetype)init {
    if ((self = [super init])) {
        _currentDecision = [MTContextDecision decisionWithGroup:MTContextGroupDefault reason:@"init" actions:@[] ttl:0];
        if (NSThread.isMainThread) {
            [self mtInstallObservers];
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{ [self mtInstallObservers]; });
        }
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)mtInstallObservers {
    if (self.observersInstalled) return;
    self.observersInstalled = YES;
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    // 只监听「变了」，不读剪贴板内容：键盘进程读跨 App 剪贴板会弹系统粘贴提示。
    [center addObserver:self selector:@selector(mtPasteboardChanged:) name:UIPasteboardChangedNotification object:nil];
    [center addObserver:self selector:@selector(mtApplicationDidBecomeActive:)
                   name:UIApplicationDidBecomeActiveNotification object:nil];
}

#pragma mark - 开关

- (BOOL)active {
    MTPrefsManager *manager = [MTPrefsManager sharedInstance];
    if (!manager.preferencesAvailable) return NO;
    NSDictionary *preferences = manager.prefs;
    if (![preferences isKindOfClass:NSDictionary.class]) return NO;
    id shelf = preferences[kFloatingShelfEnabledKey];
    // 动作组占用的是悬浮底栏的预留区：底栏没开，采集与判定全部停摆。
    if (![shelf isKindOfClass:NSNumber.class] || ![shelf boolValue]) return NO;
    id groups = preferences[kContextGroupsEnabledKey];
    if ([groups isKindOfClass:NSNumber.class] && ![groups boolValue]) return NO;
    return YES;
}

- (MTContextGroupSettings *)settings {
    return [MTContextGroupSettings settingsFromPreferences:MTPrefsManager.sharedInstance.prefs ?: @{}];
}

#pragma mark - 线程

- (void)onMain:(dispatch_block_t)block {
    if (!block) return;
    if (NSThread.isMainThread) block();
    else dispatch_async(dispatch_get_main_queue(), block);
}

#pragma mark - hook 入口

- (void)noteResponderActivated:(UIResponder *)responder {
    [self onMain:^{
        if (!self.active || ![responder isKindOfClass:UIResponder.class]) return;
        if (self.activeResponder == responder) return;
        self.activeResponder = responder;
        self.selectionLength = 0;
        self.selectionAt = 0;
        // 换输入框视为新会话：上一次的粘贴后状态不再代表当前框。
        self.pastedLength = 0;
        self.pasteAt = 0;
        [self scheduleEvaluation:MTContextDebounceInterval];
    }];
}

- (void)noteResponderResigned:(UIResponder *)responder {
    [self onMain:^{
        if (self.activeResponder != responder) return;
        self.activeResponder = nil;
        self.selectionLength = 0;
        self.selectionAt = 0;
        self.pastedLength = 0;
        self.pasteAt = 0;
        [self scheduleEvaluation:0];
    }];
}

- (void)noteSelectionLengthChanged:(NSUInteger)length responder:(UIResponder *)responder {
    [self onMain:^{
        if (!self.active || ![responder isKindOfClass:UIResponder.class]) return;
        self.activeResponder = responder;
        NSTimeInterval now = MTContextNow();
        // 有选区时每次调用都刷新时间戳：重新选中同样长度的另一段文字也必须算「比复制更新」。
        if (length > 0) self.selectionAt = now;
        // 纯光标移动（无选区且长度没变）不改判定，直接返回，避免打字时每帧重算。
        if (length == self.selectionLength && length == 0) return;
        self.selectionLength = length;
        [self scheduleEvaluation:MTContextDebounceInterval];
    }];
}

- (void)noteCopyFromResponder:(UIResponder *)responder {
    [self onMain:^{
        if (!self.active) return;
        if ([responder isKindOfClass:UIResponder.class]) self.activeResponder = responder;
        NSString *text = MTContextSelectedText(self.activeResponder) ?: MTContextTextForResponder(self.activeResponder);
        if (!text.length) return;
        self.clipboardText = text.length > MTContextSelectionTextLimit
            ? [text substringToIndex:MTContextSelectionTextLimit] : text;
        self.clipboardAvailable = YES;
        self.clipboardAt = MTContextNow();
        [self scheduleEvaluation:0.05];
    }];
}

- (void)notePasteToResponder:(UIResponder *)responder insertedLength:(NSUInteger)insertedLength {
    [self onMain:^{
        if (!self.active) return;
        if ([responder isKindOfClass:UIResponder.class]) self.activeResponder = responder;
        NSUInteger length = insertedLength;
        // 系统菜单里的异步粘贴取不到增量时，用已知剪贴板长度兜底；都取不到就不触发。
        if (!length) length = self.clipboardText.length;
        if (!length) return;
        self.pastedLength = length;
        self.pasteAt = MTContextNow();
        self.selectionLength = 0;
        [self scheduleEvaluation:0.05];
    }];
}

- (void)noteExternalClipboardChange {
    [self onMain:^{
        if (!self.active) return;
        // 自己刚写入的那次会和 copy: hook 撞车：1 秒内忽略，避免把已知文本冲成「未知」。
        if (MTContextNow() - self.clipboardAt < 1.0) return;
        self.clipboardText = nil;
        self.clipboardAvailable = YES;
        self.clipboardAt = MTContextNow();
        [self scheduleEvaluation:MTContextDebounceInterval];
    }];
}

- (void)mtPasteboardChanged:(NSNotification *)notification {
    [self noteExternalClipboardChange];
}

- (void)mtApplicationDidBecomeActive:(NSNotification *)notification {
    [self onMain:^{ [self evaluateNow]; }];
}

#pragma mark - 执行侧

- (void)scheduleEvaluation:(NSTimeInterval)delay {
    NSUInteger generation = ++self.evaluationGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MAX(0, delay) * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        MTContextSignalCenter *center = weakSelf;
        if (!center || center.evaluationGeneration != generation) return;
        [center evaluateNow];
    });
}

- (MTContextSnapshot *)snapshotNow {
    NSTimeInterval now = MTContextNow();
    MTContextSnapshot *snapshot = [MTContextSnapshot new];
    UIResponder *responder = self.activeResponder;
    if ([responder isFirstResponder]) {
        if ([responder isKindOfClass:UITextField.class]) {
            UITextField *field = (UITextField *)responder;
            snapshot.inputAvailable = YES;
            snapshot.secureInput = field.secureTextEntry;
            snapshot.contentType = field.textContentType;
            snapshot.keyboardType = field.keyboardType;
            snapshot.inputLength = field.text.length;
        } else if ([responder isKindOfClass:UITextView.class]) {
            UITextView *view = (UITextView *)responder;
            snapshot.inputAvailable = YES;
            snapshot.contentType = view.textContentType;
            snapshot.keyboardType = view.keyboardType;
            snapshot.inputLength = view.text.length;
        }
    }
    // 安全输入框不读任何内容，只保留「有输入框」这一事实。
    snapshot.selectionLength = snapshot.secureInput ? 0 : self.selectionLength;
    snapshot.selectionText = snapshot.secureInput ? nil : MTContextSelectedText(responder);
    // 从未选中过时给一个足够大的值：剪贴板组不会被「很久以前的选区」压住。
    snapshot.selectionAge = self.selectionAt > 0 ? MAX(0, now - self.selectionAt) : 86400;

    NSTimeInterval clipboardAge = self.clipboardAt > 0 ? now - self.clipboardAt : 0;
    if (self.clipboardAvailable && clipboardAge <= MTContextClipboardTextRetention) {
        snapshot.clipboardAvailable = YES;
        snapshot.clipboardAge = MAX(0, clipboardAge);
        snapshot.clipboardText = self.clipboardText;
    } else {
        // 过期剪贴板信号不再参与判定，并顺手释放文本。
        self.clipboardText = nil;
        self.clipboardAvailable = NO;
        self.clipboardAt = 0;
    }

    if (self.pasteAt > 0) {
        snapshot.pastedLength = self.pastedLength;
        snapshot.pasteAge = MAX(0, now - self.pasteAt);
    } else {
        snapshot.pasteAge = -1;
    }
    return snapshot;
}

- (void)evaluateNow {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self evaluateNow]; });
        return;
    }
    NSUInteger generation = ++self.evaluationGeneration;
    if (!self.active) {
        if (self.activeResponder) self.activeResponder = nil;
        self.selectionLength = 0;
        [self applyDecision:[MTContextDecision decisionWithGroup:MTContextGroupDefault reason:@"inactive" actions:@[] ttl:0]
                 generation:generation];
        return;
    }
    MTContextSnapshot *snapshot = [self snapshotNow];
    MTContextDecision *decision = [MTContextGroupEngine decisionForSnapshot:snapshot settings:[self settings]];
    [self applyDecision:decision generation:generation];

    if (decision.ttl > 0.05) {
        NSUInteger ttlGeneration = generation;
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(decision.ttl * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            MTContextSignalCenter *center = weakSelf;
            if (!center || center.evaluationGeneration != ttlGeneration) return;
            [center evaluateNow];
        });
    }
}

- (void)applyDecision:(MTContextDecision *)decision generation:(NSUInteger)generation {
    if ([self.currentDecision isEquivalentToDecision:decision]) return;
    NSLog(@"[MetisKeyboard][ContextGroup] %@ -> %@ reason=%@ actions=%lu",
          MTContextGroupName(self.currentDecision.group), MTContextGroupName(decision.group),
          decision.reason, (unsigned long)decision.actions.count);
    self.currentDecision = decision;
    [[NSNotificationCenter defaultCenter] postNotificationName:MTContextGroupDidChangeNotification object:self];
}

- (NSString *)diagnosticSummary {
    NSTimeInterval now = MTContextNow();
    return [NSString stringWithFormat:@"group=%@ reason=%@ actions=%lu selection=%lu(%.1fs) clipboard=%d(%.1fs) paste=%lu(%.1fs) active=%d",
            MTContextGroupName(self.currentDecision.group), self.currentDecision.reason,
            (unsigned long)self.currentDecision.actions.count,
            (unsigned long)self.selectionLength, self.selectionAt > 0 ? MAX(0, now - self.selectionAt) : -1,
            self.clipboardAvailable, self.clipboardAt > 0 ? MAX(0, now - self.clipboardAt) : 0,
            (unsigned long)self.pastedLength, self.pasteAt > 0 ? MAX(0, now - self.pasteAt) : 0,
            self.active];
}

@end
