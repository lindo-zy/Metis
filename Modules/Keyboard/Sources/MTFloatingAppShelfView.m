#import "MTFloatingAppShelfView.h"
#import "MTFloatingAppShelfChannel.h"
#import "MTFloatingAppShelfState.h"
#import "MTCollectionView.h"
#import "MTContextSignalCenter.h"
#import "MTAIPanel.h"
#import "MTHelper.h"
#import "MTPrefsManager.h"
#import "MTSystemOpenBroker.h"
#import "common.h"
#import "MTShared.h"
#import <notify.h>
#import <objc/message.h>

// 有动作组时固定区收到 3 格：3 个应用 + 最多 3 个上下文动作，是 390pt 机型上
// 每格仍剩约 44pt 宽的设计目标布局；实际宽度始终按可用宽度等分，不写死像素。
static const NSUInteger MTContextShelfFixedSlots = 3;

@interface MTFloatingAppShelfView ()
@property(nonatomic, strong) UILabel *message;
@property(nonatomic, strong) UIView *divider;
@property(nonatomic, strong) NSArray<UIButton *> *buttons;
@property(nonatomic, strong) NSArray<UIButton *> *contextButtons;
@property(nonatomic, copy) NSDictionary *snapshot;
@property(nonatomic, strong) MTContextDecision *decision;
@property(nonatomic, copy) NSString *pendingIdentifier;
@property(nonatomic) NSUInteger requestGeneration;
@property(nonatomic) NSUInteger messageGeneration;
@property(nonatomic) int token;
@end

@implementation MTFloatingAppShelfView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.token = NOTIFY_TOKEN_INVALID;
        self.clipsToBounds = YES;
        self.message = [UILabel new];
        self.message.hidden = YES;
        self.message.numberOfLines = 2;
        self.message.textAlignment = NSTextAlignmentCenter;
        self.message.font = [UIFont systemFontOfSize:11];
        self.message.textColor = UIColor.labelColor;
        self.message.backgroundColor = UIColor.secondarySystemBackgroundColor;
        self.message.userInteractionEnabled = NO;
        [self addSubview:self.message];

        self.divider = [UIView new];
        self.divider.hidden = YES;
        self.divider.userInteractionEnabled = NO;
        self.divider.backgroundColor = [UIColor.separatorColor colorWithAlphaComponent:0.35];
        [self addSubview:self.divider];

        __weak typeof(self) weakSelf = self;
        int token = NOTIFY_TOKEN_INVALID;
        if (notify_register_dispatch(MTFloatingShelfChangedName, &token, dispatch_get_main_queue(), ^(__unused int changed) {
            [weakSelf refresh];
        }) == NOTIFY_STATUS_OK) self.token = token;
        NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
        [center addObserver:self selector:@selector(refresh) name:UIKeyboardDidShowNotification object:nil];
        [center addObserver:self selector:@selector(refresh) name:UIApplicationDidBecomeActiveNotification object:nil];
        // 动作组变化只换上下文区，不重读悬浮快照。
        [center addObserver:self selector:@selector(contextGroupDidChange:) name:MTContextGroupDidChangeNotification object:nil];
        [self refresh];
    }
    return self;
}

- (void)dealloc {
    if (self.token != NOTIFY_TOKEN_INVALID) notify_cancel(self.token);
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)unlocked { return [self.snapshot[@"unlocked"] boolValue]; }

- (void)didMoveToWindow { [super didMoveToWindow]; if (self.window) [self refresh]; }

#pragma mark - 数据

- (NSArray<NSDictionary *> *)recordsFromSnapshot:(NSDictionary *)snapshot {
    NSArray *items = snapshot[@"items"];
    if (![items isKindOfClass:NSArray.class]) return @[];
    NSMutableArray *records = [NSMutableArray array];
    for (id item in items) if ([item isKindOfClass:NSDictionary.class]) [records addObject:item];
    return records;
}

// 常用应用补位：悬浮记录为空时底栏不再是一片空白，同时保证固定区的内容在
// 用户配置不变的前提下不会自己跳位。
- (NSArray<NSDictionary *> *)fallbackRecordsAfter:(NSArray<NSDictionary *> *)records limit:(NSUInteger)limit {
    if (records.count >= limit) return @[];
    id configured = MTPrefsManager.sharedInstance.prefs[kKbdHandleAppsKey];
    if (![configured isKindOfClass:NSArray.class]) return @[];
    NSMutableArray *result = [NSMutableArray array];
    for (id identifier in configured) {
        if (result.count + records.count >= limit) break;
        if (![identifier isKindOfClass:NSString.class] || [identifier length] < 3) continue;
        BOOL duplicate = NO;
        for (NSDictionary *record in records) if ([record[@"bundleID"] isEqual:identifier]) { duplicate = YES; break; }
        for (NSDictionary *record in result) if ([record[@"bundleID"] isEqual:identifier]) { duplicate = YES; break; }
        if (duplicate) continue;
        [result addObject:@{@"bundleID": identifier, @"title": identifier, @"fallback": @YES}];
    }
    return result;
}

#pragma mark - 刷新

// 两条刷新路径必须分开：
// - reloadSnapshot:YES 只在「悬浮记录/键盘生命周期」变化时走，要读完 8KB 快照
//   （最坏上千次 notify_get_state），不能跟着选区变化每 200ms 跑一次；
// - reloadSnapshot:NO 是动作组变化，只换上下文区，应用图标原样复用。
- (void)refresh {
    [self refreshReloadingSnapshot:YES];
}

- (void)contextGroupDidChange:(NSNotification *)notification {
    [self refreshReloadingSnapshot:NO];
}

- (void)refreshReloadingSnapshot:(BOOL)reloadSnapshot {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self refreshReloadingSnapshot:reloadSnapshot]; });
        return;
    }
    BOOL appsDirty = NO;
    if (reloadSnapshot) {
        NSDictionary *snapshot = MTReadFloatingShelf();
        if (snapshot != self.snapshot && ![snapshot isEqual:self.snapshot]) {
            self.snapshot = snapshot;
            appsDirty = YES;
        }
    }
    MTContextDecision *decision = [MTContextSignalCenter sharedCenter].currentDecision;
    if (!decision.actions.count) decision = nil;
    BOOL hadContext = self.contextButtons.count > 0;
    BOOL decisionSame = decision == self.decision ||
        (decision && self.decision && [decision isEquivalentToDecision:self.decision]);
    if (decisionSame && !appsDirty) return;

    self.decision = decision;
    // 上下文区有无会改变固定区容量（3 格 / 6 格），此时应用区必须重建。
    BOOL contextToggled = hadContext != (decision != nil);
    if (appsDirty || contextToggled) [self rebuildAppButtons];
    if (!decisionSame) [self rebuildContextButtons];
    [self bringSubviewToFront:self.message];
    [self bringSubviewToFront:self.divider];
    [self setNeedsLayout];
    if (self.contentChanged) self.contentChanged();
}

- (UIButton *)buttonWithIcon:(UIImage *)icon
             accessibilityText:(NSString *)text
                        action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.backgroundColor = UIColor.clearColor;
    button.layer.cornerRadius = 8;
    button.imageView.contentMode = UIViewContentModeScaleAspectFit;
    [button setImage:icon ?: [UIImage systemImageNamed:@"app"] forState:UIControlStateNormal];
    button.accessibilityLabel = text;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)rebuildAppButtons {
    for (UIButton *button in self.buttons) [button removeFromSuperview];
    NSArray<NSDictionary *> *records = [self recordsFromSnapshot:self.snapshot];
    NSUInteger capacity = self.decision ? MTContextShelfFixedSlots : MTFloatingShelfCapacity;
    NSMutableArray<NSDictionary *> *shown = [records mutableCopy];
    [shown addObjectsFromArray:[self fallbackRecordsAfter:records limit:capacity]];

    NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
    for (NSDictionary *item in shown) {
        if (buttons.count >= capacity) break;
        NSString *identifier = item[@"bundleID"];
        if (![identifier isKindOfClass:NSString.class] || !identifier.length) continue;
        BOOL fallback = [item[@"fallback"] boolValue];
        BOOL active = !fallback && [self.snapshot[@"active"] isEqual:identifier];
        BOOL foreground = !fallback && [self.snapshot[@"foreground"] isEqual:identifier];
        UIImage *icon = [MTHelper appIconImageForBundleID:identifier];
        UIButton *button = [self buttonWithIcon:icon
                               accessibilityText:[item[@"title"] isKindOfClass:NSString.class] ? item[@"title"] : identifier
                                          action:@selector(activate:)];
        button.accessibilityIdentifier = identifier;
        button.accessibilityValue = active ? LOCALIZED(@"FLOATING_SHELF_ACTIVE") :
            (foreground ? LOCALIZED(@"FLOATING_SHELF_FOREGROUND") : nil);
        button.backgroundColor = active ? [UIColor.systemBlueColor colorWithAlphaComponent:0.12] : UIColor.clearColor;
        button.tintColor = UIColor.secondaryLabelColor;
        button.tag = fallback ? 1 : 0;
        // 快照仅用于展示：前台/悬浮状态可能已过期，不能据此永久禁用恢复入口。
        button.enabled = ![self.pendingIdentifier isEqual:identifier];
        [self addSubview:button];
        [buttons addObject:button];
    }
    self.buttons = buttons;
}

- (void)rebuildContextButtons {
    for (UIButton *button in self.contextButtons) [button removeFromSuperview];
    NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
    NSArray<MTContextAction *> *actions = self.decision.actions;
    for (MTContextAction *action in actions) {
        UIImage *icon = [UIImage systemImageNamed:action.symbol] ?: [UIImage systemImageNamed:@"ellipsis"];
        UIButton *button = [self buttonWithIcon:icon accessibilityText:action.title action:@selector(activateContext:)];
        button.accessibilityIdentifier = action.identifier;
        button.tintColor = UIColor.labelColor;
        [self addSubview:button];
        [buttons addObject:button];
    }
    self.contextButtons = buttons;
    self.divider.hidden = buttons.count == 0;
}

#pragma mark - 布局

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = CGRectGetWidth(self.bounds), height = CGRectGetHeight(self.bounds);
    CGFloat cellHeight = MAX(0, MIN(33, height - MTBottomToolbarCellTopInset));
    BOOL hasContext = self.contextButtons.count > 0;
    // 只有「固定区有应用」时才分区；没有应用可显示时让上下文动作独占整条，
    // 否则左半条空白、右半条挤在一起。
    BOOL split = hasContext && self.buttons.count > 0;
    CGFloat appWidth = split ? floor(width * 0.5) : width;
    CGFloat slotWidth = appWidth / (split ? MTContextShelfFixedSlots : MTFloatingShelfCapacity);
    for (NSUInteger index = 0; index < self.buttons.count; index++) {
        self.buttons[index].frame = CGRectMake(index * slotWidth + 3, MTBottomToolbarCellTopInset,
            MAX(0, slotWidth - 6), cellHeight);
    }
    self.divider.hidden = !split;
    if (hasContext) {
        CGFloat contextLeft = split ? appWidth : 0;
        CGFloat contextWidth = width - contextLeft;
        NSUInteger count = self.contextButtons.count;
        CGFloat contextSlot = contextWidth / MAX((CGFloat)count, 1.0);
        for (NSUInteger index = 0; index < count; index++) {
            self.contextButtons[index].frame = CGRectMake(contextLeft + index * contextSlot + 3,
                MTBottomToolbarCellTopInset, MAX(0, contextSlot - 6), cellHeight);
        }
        if (split) {
            self.divider.frame = CGRectMake(contextLeft - 0.5, MTBottomToolbarCellTopInset + 3, 1,
                MAX(0, cellHeight - 6));
        }
    }
    self.message.frame = CGRectMake(0, MTBottomToolbarCellTopInset, width, MAX(0, height - MTBottomToolbarCellTopInset));
}

#pragma mark - 执行

- (void)activate:(UIButton *)button {
    NSDictionary *preferences = MTPrefsManager.sharedInstance.prefs;
    if (!self.window || self.hidden || self.pendingIdentifier ||
        ![preferences[kFloatingShelfEnabledKey] isKindOfClass:NSNumber.class] ||
        ![preferences[kFloatingShelfEnabledKey] boolValue] || ![self.buttons containsObject:button]) return;
    NSString *identifier = [button.accessibilityIdentifier copy];
    if (!identifier.length) return;

    // 常用应用补位项不在悬浮记录里：它没有会话可恢复，直接按悬浮方式打开。
    if (button.tag == 1) {
        NSLog(@"[MetisKeyboard][FloatingShelf] open fallback app bundleID=%@", identifier);
        MTOpenFloatingApplication(identifier, ^(MTSystemOpenResult result) {
            if (result != MTSystemOpenSucceeded)
                NSLog(@"[MetisKeyboard][FloatingShelf] fallback open failed bundleID=%@ result=%llu",
                      identifier, (unsigned long long)result);
        });
        return;
    }

    uint64_t revision = [self.snapshot[@"revision"] unsignedLongLongValue];
    if ([self.snapshot[@"active"] isEqual:identifier] || [self.snapshot[@"foreground"] isEqual:identifier])
        NSLog(@"[MetisKeyboard][FloatingShelf] restore revalidate bundleID=%@ revision=%llu", identifier, (unsigned long long)revision);
    self.pendingIdentifier = identifier;
    NSUInteger generation = ++self.requestGeneration;
    button.enabled = NO;
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    spinner.center = CGPointMake(CGRectGetMidX(button.bounds), CGRectGetMidY(button.bounds));
    [button addSubview:spinner]; [spinner startAnimating];
    __weak typeof(self) weakSelf = self;
    MTRestoreFloatingApplication(identifier, revision, ^(MTSystemOpenResult result) {
        MTFloatingAppShelfView *view = weakSelf;
        if (!view || view.requestGeneration != generation || ![view.pendingIdentifier isEqual:identifier]) return;
        view.pendingIdentifier = nil;
        [spinner removeFromSuperview];
        for (UIButton *current in view.buttons) current.enabled = YES;
        [view refresh];
        if (result != MTSystemOpenSucceeded && view.window && !view.hidden) {
            NSUInteger messageGeneration = ++view.messageGeneration;
            view.message.text = LOCALIZED(@"FLOATING_SHELF_RESTORE_FAILED"); view.message.hidden = NO;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                if (weakSelf.messageGeneration == messageGeneration) weakSelf.message.hidden = YES;
            });
        }
    });
}

- (void)activateContext:(UIButton *)button {
    NSUInteger index = [self.contextButtons indexOfObject:button];
    if (index == NSNotFound || index >= self.decision.actions.count) return;
    MTContextAction *action = self.decision.actions[index];
    NSLog(@"[MetisKeyboard][ContextGroup] perform id=%@ kind=%ld", action.identifier, (long)action.payloadKind);
    switch (action.payloadKind) {
        case MTContextPayloadSelector: {
            MTCollectionView *toolbar = self.actionTarget;
            if (!toolbar || !action.payload.length) return;
            NSString *selector = action.payload;
            if ([toolbar canExecuteKeyboardPanelSelector:selector]) {
                [toolbar dispatchKeyboardPanelSelector:selector sender:button];
            } else if ([toolbar respondsToSelector:NSSelectorFromString(selector)]) {
                // 未进选择器表但类上确有该方法（例如被隐藏的历史动作）时直接派发。
                ((void (*)(id, SEL, id))objc_msgSend)(toolbar, NSSelectorFromString(selector), button);
            }
            break;
        }
        case MTContextPayloadURL: {
            NSURL *url = [NSURL URLWithString:action.payload ?: @""];
            if (!url) return;
            MTOpenFloatingURL(url, ^(MTSystemOpenResult result) {
                if (result != MTSystemOpenSucceeded)
                    NSLog(@"[MetisKeyboard][ContextGroup] url open failed result=%llu",
                          (unsigned long long)result);
            });
            break;
        }
        case MTContextPayloadAISeed:
            if (action.payload.length) [MTAIPanel openFromKeyboardWithSeedText:action.payload];
            break;
    }
}

@end
