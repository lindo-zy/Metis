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
#import "MTBottomBarLayout.h"
#import <notify.h>
#import <objc/message.h>

// Both segments render the same validated mixed-entry model used by Settings.


@interface MTFloatingAppShelfView ()
@property(nonatomic, assign) BOOL preview;
@property(nonatomic, copy) NSDictionary *previewPreferences;
@property(nonatomic, copy) NSDictionary *renderedPreferences;
@property(nonatomic, strong) UIScrollView *itemsScroll;
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
@property(nonatomic, strong) NSArray<NSArray<UIButton *> *> *segments;
@property(nonatomic, strong) NSMutableDictionary<NSString *, UIImage *> *appIcons;
@property(nonatomic, copy) NSDictionary<NSString *, UIButton *> *stableButtons;
@end

@implementation MTFloatingAppShelfView

- (instancetype)initForPreview { return [self initWithFrame:CGRectZero preview:YES]; }
- (instancetype)initWithFrame:(CGRect)frame { return [self initWithFrame:frame preview:NO]; }
- (instancetype)initWithFrame:(CGRect)frame preview:(BOOL)preview {
    if ((self = [super initWithFrame:frame])) {
        self.preview = preview;
        self.appIcons = [NSMutableDictionary dictionary];
        self.itemsScroll = [UIScrollView new];
        self.itemsScroll.showsHorizontalScrollIndicator = NO;
        [self addSubview:self.itemsScroll];
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

        if (preview) { self.userInteractionEnabled = NO; return self; }
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

- (void)configurePreviewWithPreferences:(NSDictionary *)preferences decision:(MTContextDecision *)decision {
    if (!self.preview) return;
    self.previewPreferences = preferences;
    self.decision = decision;
    self.snapshot = @{};
    self.stableButtons = @{};
    [self rebuildEntries];
    [self setNeedsLayout];
}
- (NSDictionary *)preferences { return self.preview ? self.previewPreferences : MTPrefsManager.sharedInstance.prefs; }
#pragma mark - 数据

- (NSArray<NSDictionary *> *)recordsFromSnapshot:(NSDictionary *)snapshot {
    NSArray *items = snapshot[@"items"];
    if (![items isKindOfClass:NSArray.class]) return @[];
    NSMutableArray *records = [NSMutableArray array];
    for (id item in items) {
        if (![item isKindOfClass:NSDictionary.class]) continue;
        id identifier = item[@"bundleID"];
        if ([identifier isKindOfClass:NSString.class] && [identifier length] && [identifier length] <= 512) [records addObject:item];
    }
    return records;
}

// 常用应用补位：悬浮记录为空时底栏不再是一片空白，同时保证固定区的内容在
// 用户配置不变的前提下不会自己跳位。
- (NSArray<NSDictionary *> *)fallbackRecordsAfter:(NSArray<NSDictionary *> *)records limit:(NSUInteger)limit {
    if (records.count >= limit) return @[];
    id configured = [self preferences][kKbdHandleAppsKey];
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
// - reloadSnapshot:NO 是动作组变化：复用固定动作/速启按钮和应用图标，只替换动态格。
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
    if (self.preview) return;
    NSDictionary *currentPreferences = [self preferences];
    BOOL appsDirty = ![self.renderedPreferences isEqual:currentPreferences];
    self.renderedPreferences = currentPreferences;
    if (reloadSnapshot) {
        NSDictionary *snapshot = MTReadFloatingShelf();
        if (snapshot != self.snapshot && ![snapshot isEqual:self.snapshot]) {
            self.snapshot = snapshot;
            appsDirty = YES;
        }
    }
    MTContextDecision *decision = [MTContextSignalCenter sharedCenter].currentDecision;
    if (decision.group == MTContextGroupDefault || decision.group == MTContextGroupNone) decision = nil;

    BOOL decisionSame = decision == self.decision ||
        (decision && self.decision && [decision isEquivalentToDecision:self.decision]);
    if (decisionSame && !appsDirty) return;

    self.decision = decision;
    if (appsDirty) self.stableButtons = @{};
    if (reloadSnapshot && appsDirty) [self.appIcons removeAllObjects];
    [self rebuildEntries];
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

- (UIImage *)iconForApp:(NSString *)identifier {
    UIImage *icon = self.appIcons[identifier];
    if (!icon) {
        icon = [MTHelper appIconImageForBundleID:identifier];
        if (icon) self.appIcons[identifier] = icon;
    }
    return icon;
}

- (NSDictionary *)shortcutDefinition:(NSString *)selector {
    id sections = [self preferences][kShortcutskey];
    for (id section in [sections isKindOfClass:NSArray.class] ? sections : @[])
        for (id item in [section isKindOfClass:NSArray.class] ? section : @[])
            if ([item isKindOfClass:NSDictionary.class] && [item[@"selector"] isEqual:selector]) return item;
    return nil;
}

- (void)rebuildEntries {
    NSArray *oldViews = [self.itemsScroll.subviews copy];
    NSMutableArray *newViews = [NSMutableArray array];
    NSMutableDictionary *stable = [NSMutableDictionary dictionary];
    NSDictionary *preferences = [self preferences];
    NSDictionary *layout = MTBottomBarLayout(preferences);
    NSMutableArray *segments = [NSMutableArray array], *apps = [NSMutableArray array], *contexts = [NSMutableArray array];
    NSArray *records = [self recordsFromSnapshot:self.snapshot];
    NSMutableArray *fallbacks = [records mutableCopy];
    [fallbacks addObjectsFromArray:[self fallbackRecordsAfter:records limit:MTFloatingShelfCapacity]];
    for (NSArray *entries in @[layout[@"left"], [layout[@"single"] boolValue] ? @[] : layout[@"right"]]) {
        NSMutableArray *buttons = [NSMutableArray array];
        for (NSDictionary *entry in entries) {
            NSString *kind = entry[@"kind"], *value = entry[@"value"];
            NSString *stableKey = [NSString stringWithFormat:@"%lu:%lu:%@:%@", (unsigned long)segments.count, (unsigned long)buttons.count, kind, value];
            UIButton *existing = self.stableButtons[stableKey];
            if (existing && ([kind isEqual:@"action"] || [kind isEqual:@"app"])) {
                [buttons addObject:existing]; [newViews addObject:existing]; stable[stableKey] = existing;
                if ([kind isEqual:@"app"]) [apps addObject:existing];
                continue;
            }
            NSString *title = nil;
            UIImage *icon = nil;
            MTContextAction *contextAction = nil;
            NSDictionary *app = nil;
            BOOL fixed = [kind isEqual:@"action"];
            if (fixed) {
                NSDictionary *definition = [self shortcutDefinition:value];
                title = [MTHelper customNameForShortcutItem:definition] ?: [self.actionTarget subActionPanelTitleForSelector:value];
                NSString *customIcon = [MTHelper customIconForShortcutItem:definition];
                icon = customIcon.length ? [MTHelper imageForName:customIcon withSystemColor:YES completion:nil] : [self.actionTarget subActionPanelImageForSelector:value];
            } else if ([kind isEqual:@"app"]) {
                app = @{@"bundleID":value, @"fallback":@YES, @"title":[entry[@"title"] length] ? entry[@"title"] : value};
                for (NSDictionary *record in records) if ([record[@"bundleID"] isEqual:value]) { app = record; break; }
            } else {
                NSUInteger index = [entry[@"index"] unsignedIntegerValue];
                contextAction = MTBottomBarContextAction(entry, self.decision);
                if (contextAction) {
                    BOOL configured = [contextAction.identifier hasPrefix:@"configured:"];
                    title = configured ? [self.actionTarget subActionPanelTitleForSelector:contextAction.payload] : contextAction.title;
                    icon = configured ? [self.actionTarget subActionPanelImageForSelector:contextAction.payload] : [UIImage systemImageNamed:contextAction.symbol];
                } else if ([entry[@"fallback"] boolValue] && !self.decision && [preferences[kFloatingShelfEnabledKey] boolValue] && index < fallbacks.count) {
                    app = fallbacks[index];
                } else {
                    NSString *key = [@"BAR_CONTEXT_" stringByAppendingString:value.uppercaseString];
                    title = LOCALIZED(key); icon = [UIImage systemImageNamed:@"square.dashed"];
                }
            }
            if (app) {
                NSString *identifier = app[@"bundleID"];
                title = [app[@"title"] isKindOfClass:NSString.class] ? app[@"title"] : identifier;
                icon = [self iconForApp:identifier];
            }
            SEL action = app ? @selector(activate:) : @selector(activateContext:);
            UIButton *button = [self buttonWithIcon:icon accessibilityText:title ?: value action:action];
            if (fixed) {
                [button removeTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
                [self.actionTarget configureBottomActionButton:button selector:value];
            } else if (app) {
                button.accessibilityIdentifier = app[@"bundleID"];
                button.tag = [app[@"fallback"] boolValue] ? 1 : 0;
                BOOL active = !button.tag && [self.snapshot[@"active"] isEqual:app[@"bundleID"]];
                BOOL foreground = !button.tag && [self.snapshot[@"foreground"] isEqual:app[@"bundleID"]];
                button.accessibilityValue = active ? LOCALIZED(@"FLOATING_SHELF_ACTIVE") : (foreground ? LOCALIZED(@"FLOATING_SHELF_FOREGROUND") : nil);
                if (active) button.backgroundColor = [UIColor.systemBlueColor colorWithAlphaComponent:0.12];
                button.enabled = self.preview || (self.unlocked && !self.pendingIdentifier);
                [apps addObject:button];
            } else if (contextAction) {
                objc_setAssociatedObject(button, @selector(activateContext:), contextAction, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                [contexts addObject:button];
            } else {
                button.enabled = NO; button.alpha = 0.28;
            }
            button.layer.cornerRadius = self.actionTarget.buttonRadius;
            button.layer.borderWidth = self.actionTarget.borderEnabled ? self.actionTarget.borderWidth : 0;
            button.layer.borderColor = UIColor.labelColor.CGColor;
            UIColor *tint = [preferences[kShortcutsTintEnabled] boolValue] ? MTColorFromHex(preferences[@"shortcutstint"], @"#ff0000") : UIColor.labelColor;
            button.tintColor = tint;
            if ([preferences[kColorEnabledkey] boolValue] && (!preferences[kShortcutsBackgroundTintEnabled] || [preferences[kShortcutsBackgroundTintEnabled] boolValue])) button.backgroundColor = MTColorFromHex(preferences[@"shortcutsbackgroundtint"], @"#5B5B5B");
            button.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
            button.titleLabel.adjustsFontSizeToFitWidth = YES;
            button.titleLabel.minimumScaleFactor = 0.65;
            [button setTitleColor:tint forState:UIControlStateNormal];
            if (self.actionTarget.useShortLabel) {
                NSString *shortTitle = fixed ? ([MTHelper customNameForShortcutItem:[self shortcutDefinition:value]] ?: [MTHelper localizedStringForActionNamed:value shortName:YES bundle:[NSBundle bundleWithPath:bundlePath]]) : title;
                [button setImage:nil forState:UIControlStateNormal];
                [button setTitle:shortTitle forState:UIControlStateNormal];
            }
            [self.itemsScroll addSubview:button]; [buttons addObject:button]; [newViews addObject:button];
            if (fixed || [kind isEqual:@"app"]) stable[stableKey] = button;
        }
        [segments addObject:buttons];
    }
    for (UIView *view in oldViews) if (![newViews containsObject:view]) [view removeFromSuperview];
    self.stableButtons = stable;
    self.segments = segments; self.buttons = apps; self.contextButtons = contexts;
    [self setNeedsLayout];
}

#pragma mark - 布局

- (void)layoutSubviews {
    [super layoutSubviews];
    NSDictionary *layout = MTBottomBarLayout([self preferences]);
    CGFloat width = CGRectGetWidth(self.bounds), height = CGRectGetHeight(self.bounds);
    CGFloat left = width * MTBottomBarLeftFraction(layout);
    self.itemsScroll.frame = self.bounds; self.itemsScroll.contentSize = self.bounds.size;
    CGFloat cellHeight = MAX(0, MIN(self.actionTarget.buttonHeight, height - MTBottomToolbarCellTopInset));
    CGFloat gap = MAX(0, MIN(20, self.actionTarget.buttonSpacing));
    CGFloat scale = MAX(0.3, MIN(1, self.actionTarget.widthScale / 100.0));
    for (NSUInteger segment = 0; segment < self.segments.count; segment++) {
        NSArray<UIButton *> *buttons = self.segments[segment];
        CGFloat segmentWidth = segment ? width - left : left;
        CGFloat cellWidth = buttons.count ? segmentWidth / buttons.count : 0;
        CGFloat buttonWidth = MAX(0, cellWidth - MIN(gap, cellWidth)) * scale;
        for (NSUInteger i = 0; i < buttons.count; i++) buttons[i].frame = CGRectMake((segment ? left : 0) + i * cellWidth + (cellWidth - buttonWidth) / 2, MTBottomToolbarCellTopInset, buttonWidth, cellHeight);
    }
    self.divider.hidden = [layout[@"single"] boolValue] || ![layout[@"left"] count] || ![layout[@"right"] count];
    self.divider.frame = CGRectMake(left, MTBottomToolbarCellTopInset + 3, 0.5, MAX(0, cellHeight - 6));
    self.message.frame = CGRectMake(0, MTBottomToolbarCellTopInset, width, MAX(0, height - MTBottomToolbarCellTopInset));
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer { return YES; }

#pragma mark - 执行

- (void)activate:(UIButton *)button {
    NSDictionary *preferences = MTPrefsManager.sharedInstance.prefs;
    if (self.preview || !self.unlocked || !MTBottomToolbarEnabled(preferences) || !self.window || self.hidden || ![self.actionTarget keyboardPanelGestureSourceVisible] || self.pendingIdentifier ||
        ![self.buttons containsObject:button]) return;
    [[MTContextSignalCenter sharedCenter] noteActionPerformed];
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
        for (UIButton *current in view.buttons) current.enabled = view.unlocked;
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
    if (self.preview || !self.window || self.hidden || ![self.actionTarget keyboardPanelGestureSourceVisible] || !MTBottomToolbarEnabled([self preferences])) return;
    if (![self.contextButtons containsObject:button]) return;
    MTContextAction *shown = objc_getAssociatedObject(button, @selector(activateContext:));
    if (!shown) return;
    MTContextDecision *fresh = [[MTContextSignalCenter sharedCenter] decisionForExecution];
    if (fresh.group != self.decision.group) return;
    MTContextAction *action = nil;
    for (MTContextAction *candidate in fresh.actions) if ([candidate.identifier isEqual:shown.identifier]) { action = candidate; break; }
    if (!action) return;
    NSLog(@"[MetisKeyboard][ContextGroup] perform id=%@ kind=%ld", action.identifier, (long)action.payloadKind);
    switch (action.payloadKind) {
        case MTContextPayloadSelector: {
            MTCollectionView *toolbar = self.actionTarget;
            if (!toolbar || !action.payload.length) return;
            NSString *selector = action.payload;
            if ([toolbar canExecuteKeyboardPanelSelector:selector]) {
                [toolbar dispatchKeyboardPanelSelector:selector sender:button];
            } else { return; }
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
    [[MTContextSignalCenter sharedCenter] noteActionPerformed];
}

@end
