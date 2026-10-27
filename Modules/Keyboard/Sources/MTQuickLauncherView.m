#import "MTQuickLauncherView.h"
#import "MTQuickLauncherLayout.h"
#import "MTAppLauncherCatalog.h"
#import "MTHelper.h"
#import "common.h"

static NSString *MTQL(NSString *key) {
    static NSBundle *bundle;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ bundle = [NSBundle bundleWithPath:bundlePath]; });
    return [bundle localizedStringForKey:key value:key table:nil];
}

CGRect MTQuickLauncherFrame(CGRect bounds, UIEdgeInsets safe, NSInteger side, CGFloat scale) {
    return MTQuickLauncherPanelFrame(bounds, safe.top, safe.left, safe.bottom, safe.right, side, scale);
}

// A vertical app list must yield horizontal movement to the stage-switch gesture.
@interface MTLauncherCollection : UICollectionView
@end
@implementation MTLauncherCollection
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    if (gesture == self.panGestureRecognizer) {
        CGPoint v = [self.panGestureRecognizer velocityInView:self];
        if (fabs(v.x) > fabs(v.y)) return NO;
    }
    return [super gestureRecognizerShouldBegin:gesture];
}
@end

@interface MTLauncherAppCell : UICollectionViewCell
@property(nonatomic, strong) UIImageView *icon;
@property(nonatomic, strong) UILabel *name;
@property(nonatomic, strong) UILabel *badge;
@property(nonatomic, copy) BOOL (^activationHandler)(void);
@property(nonatomic, copy) NSString *representedIdentifier;
@end
@implementation MTLauncherAppCell
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.icon = [UIImageView new]; self.icon.contentMode = UIViewContentModeScaleAspectFit;
        self.icon.layer.cornerRadius = 9; self.icon.clipsToBounds = YES;
        self.name = [UILabel new]; self.name.font = [UIFont systemFontOfSize:10];
        self.name.textColor = UIColor.labelColor; self.name.textAlignment = NSTextAlignmentCenter;
        self.badge = [UILabel new]; self.badge.font = [UIFont systemFontOfSize:8];
        self.badge.textColor = UIColor.systemTealColor; self.badge.textAlignment = NSTextAlignmentCenter;
        [self.contentView addSubview:self.icon]; [self.contentView addSubview:self.name]; [self.contentView addSubview:self.badge];
        self.isAccessibilityElement = YES; self.accessibilityTraits = UIAccessibilityTraitButton;
    } return self;
}
- (BOOL)accessibilityActivate { return self.activationHandler ? self.activationHandler() : NO; }
- (void)prepareForReuse {
    [super prepareForReuse];
    self.representedIdentifier = nil; self.activationHandler = nil; self.icon.image = nil;
}
- (void)layoutSubviews {
    [super layoutSubviews]; CGFloat w = self.bounds.size.width;
    CGFloat icon = MIN(38, MAX(16, self.bounds.size.height - 28));
    self.icon.frame = CGRectMake((w - icon) / 2, 2, icon, icon);
    self.name.frame = CGRectMake(1, icon + 4, w - 2, 13);
    self.badge.frame = CGRectMake(1, icon + 17, w - 2, 10);
}
@end

@interface MTQuickPanelActionButton : UIButton
@end
@implementation MTQuickPanelActionButton
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    self.imageView.contentMode = UIViewContentModeScaleAspectFit;
    self.imageView.frame = CGRectMake((width - 20) / 2, 3, 20, 20);
    self.titleLabel.frame = CGRectMake(1, 25, width - 2, 13);
}
@end

static CGFloat const MTQuickLauncherGrabberZoneHeight = 24.0;

@interface MTQuickLauncherView () <UICollectionViewDataSource, UICollectionViewDelegate, UIGestureRecognizerDelegate>
@property(nonatomic, strong) UIVisualEffectView *material;
@property(nonatomic, strong) UIView *panelContent;
@property(nonatomic, strong) UIView *grabber;
@property(nonatomic, strong) UIPanGestureRecognizer *dragPan;
@property(nonatomic, strong) UIPanGestureRecognizer *modePan;
@property(nonatomic, readwrite) MTQuickLauncherMode presentationMode;
@property(nonatomic, strong) NSArray<UIButton *> *actionButtons;
@property(nonatomic, copy) NSArray<NSDictionary *> *quickActions;
@property(nonatomic, strong) UIButton *modeButton;
@property(nonatomic) BOOL dragging;
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UIButton *closeButton;
@property(nonatomic, strong) UIButton *clearButton;
@property(nonatomic, strong) UILabel *queryLabel;
@property(nonatomic, strong) UIView *queryBackground;
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic, strong) UICollectionView *collection;
@property(nonatomic, strong) UICollectionViewFlowLayout *flow;
@property(nonatomic, strong) UIView *keys;
@property(nonatomic, strong) NSMutableArray<UIButton *> *keyButtons;
@property(nonatomic, strong) MTAppLauncherCatalog *catalog;
@property(nonatomic, strong) NSOperationQueue *searchQueue;
@property(nonatomic, strong) NSOperationQueue *iconQueue;
@property(nonatomic, strong) NSCache<NSString *, UIImage *> *iconCache;
@property(nonatomic, strong) NSCache<NSString *, NSArray<MTAppSearchMatch *> *> *queryCache;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSOperation *> *iconRequests;
@property(nonatomic, copy) NSArray<MTAppSearchEntry *> *entries;
@property(nonatomic, copy) NSArray<MTAppSearchMatch *> *results;
@property(nonatomic, copy) NSArray<NSString *> *favorites;
@property(nonatomic, copy) NSString *modeHint;
@property(nonatomic, copy) NSDictionary *fallbackNames;
@property(nonatomic, copy) NSDictionary *aliases;
@property(nonatomic, copy) NSDictionary *usage;
@property(nonatomic, copy) NSString *query;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) NSUInteger session;
@property(nonatomic) NSUInteger selectionGeneration;
@property(nonatomic) NSUInteger selectionSession;
@property(nonatomic, copy) NSString *selectionIdentifier;
@property(nonatomic) BOOL active;
@property(nonatomic) BOOL available;
@property(nonatomic) BOOL loaded;
@end

@implementation MTQuickLauncherView
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.layer.cornerRadius = 24; self.clipsToBounds = YES;
        self.layer.borderWidth = 0.5; self.layer.borderColor = [UIColor.labelColor colorWithAlphaComponent:0.2].CGColor;
        self.material = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]];
        self.material.userInteractionEnabled = NO; [self addSubview:self.material];
        self.panelContent = [UIView new]; [self addSubview:self.panelContent];
        self.grabber = [UIView new];
        self.grabber.backgroundColor = [[UIColor secondaryLabelColor] colorWithAlphaComponent:0.38];
        self.grabber.layer.cornerRadius = 2; self.grabber.userInteractionEnabled = YES;
        self.grabber.isAccessibilityElement = YES;
        self.grabber.accessibilityLabel = MTQL(@"QUICK_MOVE");
        self.grabber.accessibilityTraits = UIAccessibilityTraitButton;
        [self.panelContent addSubview:self.grabber];
        self.dragPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragPanned:)];
        self.dragPan.maximumNumberOfTouches = 1; self.dragPan.delegate = self;
        self.dragPan.delaysTouchesBegan = NO; self.dragPan.delaysTouchesEnded = NO;
        [self addGestureRecognizer:self.dragPan];
        self.modePan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(modePanned:)];
        self.modePan.maximumNumberOfTouches = 1; self.modePan.delegate = self;
        self.modePan.delaysTouchesBegan = NO; self.modePan.delaysTouchesEnded = NO;
        [self addGestureRecognizer:self.modePan];
        self.modeButton = [UIButton buttonWithType:UIButtonTypeSystem];
        self.modeButton.titleLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
        self.modeButton.tintColor = UIColor.secondaryLabelColor;
        [self.modeButton addTarget:self action:@selector(advanceMode) forControlEvents:UIControlEventTouchUpInside];
        [self.panelContent addSubview:self.modeButton];
        self.accessibilityCustomActions = @[[[UIAccessibilityCustomAction alloc] initWithName:MTQL(@"QUICK_CLOSE")
            target:self selector:@selector(accessibilityClose:)]];
        NSMutableArray *actions = [NSMutableArray array];
        for (NSUInteger i = 0; i < 4; i++) {
            UIButton *button = [MTQuickPanelActionButton buttonWithType:UIButtonTypeSystem]; button.tag = i;
            button.tintColor = UIColor.labelColor; button.titleLabel.font = [UIFont systemFontOfSize:9];
            button.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
            [button addTarget:self action:@selector(actionTapped:) forControlEvents:UIControlEventTouchUpInside];
            [self.panelContent addSubview:button]; [actions addObject:button];
        }
        self.actionButtons = actions;
        UITapGestureRecognizer *resetTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(resetTapped:)];
        resetTap.numberOfTapsRequired = 2;
        resetTap.delaysTouchesBegan = NO; resetTap.delaysTouchesEnded = NO;
        resetTap.delegate = self; [self addGestureRecognizer:resetTap];
        self.titleLabel = [UILabel new]; self.titleLabel.text = MTQL(@"QUICK_TITLE");
        self.titleLabel.font = [UIFont boldSystemFontOfSize:17]; self.titleLabel.textColor = UIColor.labelColor;
        [self.panelContent addSubview:self.titleLabel];
        self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [self.closeButton setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
        self.closeButton.tintColor = UIColor.labelColor; self.closeButton.accessibilityLabel = MTQL(@"QUICK_CLOSE");
        [self.closeButton addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside]; [self.panelContent addSubview:self.closeButton];
        self.queryBackground = [UIView new]; self.queryBackground.backgroundColor = [UIColor.labelColor colorWithAlphaComponent:0.10];
        self.queryBackground.layer.cornerRadius = 12; [self.panelContent addSubview:self.queryBackground];
        self.queryLabel = [UILabel new]; self.queryLabel.font = [UIFont systemFontOfSize:16]; self.queryLabel.textColor = UIColor.labelColor;
        [self.queryBackground addSubview:self.queryLabel];
        self.clearButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [self.clearButton setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
        self.clearButton.tintColor = UIColor.lightGrayColor; self.clearButton.accessibilityLabel = MTQL(@"QUICK_CLEAR");
        [self.clearButton addTarget:self action:@selector(clearQuery) forControlEvents:UIControlEventTouchUpInside];
        [self.queryBackground addSubview:self.clearButton];
        self.statusLabel = [UILabel new]; self.statusLabel.textColor = UIColor.lightGrayColor;
        self.statusLabel.font = [UIFont systemFontOfSize:11]; [self.panelContent addSubview:self.statusLabel];
        self.flow = [UICollectionViewFlowLayout new]; self.flow.scrollDirection = UICollectionViewScrollDirectionVertical;
        self.flow.minimumLineSpacing = 0; self.flow.minimumInteritemSpacing = 0;
        self.collection = [[MTLauncherCollection alloc] initWithFrame:CGRectZero collectionViewLayout:self.flow];
        self.collection.backgroundColor = UIColor.clearColor; self.collection.pagingEnabled = NO; self.collection.alwaysBounceVertical = YES; self.collection.showsVerticalScrollIndicator = NO;
        self.collection.showsHorizontalScrollIndicator = NO; self.collection.dataSource = self; self.collection.delegate = self;
        self.collection.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
        [self.collection registerClass:MTLauncherAppCell.class forCellWithReuseIdentifier:@"app"]; [self.panelContent addSubview:self.collection];
        self.keys = [UIView new]; [self.panelContent addSubview:self.keys]; self.keyButtons = [NSMutableArray array];
        self.catalog = [MTAppLauncherCatalog new];
        self.searchQueue = [NSOperationQueue new];
        self.searchQueue.name = @"com.lindo.metis.keyboard.launcher.search";
        self.searchQueue.maxConcurrentOperationCount = 1;
        self.searchQueue.qualityOfService = NSQualityOfServiceUserInitiated;
        self.iconQueue = [NSOperationQueue new];
        self.iconQueue.name = @"com.lindo.metis.keyboard.launcher.icons";
        self.iconQueue.maxConcurrentOperationCount = 2;
        self.iconQueue.qualityOfService = NSQualityOfServiceUserInitiated;
        self.iconCache = [NSCache new]; self.iconCache.countLimit = 256;
        self.queryCache = [NSCache new]; self.queryCache.countLimit = 64;
        self.iconRequests = [NSMutableDictionary dictionary];
        __weak typeof(self) weakSelf = self;
        self.catalog.didInvalidate = ^{ if (weakSelf.active) [weakSelf loadCatalog]; };
        self.query = @""; self.results = @[]; self.entries = @[]; self.modeHint = @"QUICK_STAGE_EXPAND";
        [self buildKeys];
    } return self;
}
- (void)beginWithFavorites:(NSArray<NSString *> *)favorites names:(NSDictionary<NSString *, NSString *> *)names
    aliases:(NSDictionary *)aliases usage:(NSDictionary *)usage {
    self.presentationMode = MTQuickLauncherModeStrip;
    self.modeHint = @"QUICK_STAGE_EXPAND";
    self.active = YES; self.session++; self.generation++; self.query = @""; self.launching = NO;
    aliases = aliases ?: @{}; names = names ?: @{};
    BOOL reusable = [self.aliases isEqual:aliases] && [self.fallbackNames isEqual:names];
    self.favorites = [favorites copy]; self.fallbackNames = [names copy]; self.aliases = [aliases copy]; self.usage = [usage copy];
    self.loaded = NO; self.available = NO;
    if (!reusable) {
        self.entries = @[];
        [self.queryCache removeAllObjects];
    }
    [self updateResults]; [self loadCatalog];
    // 预取常用图标：首屏配置格子时大概率已进缓存，消除占位符渐现。
    [self prefetchFavoriteIcons];
}
- (void)loadCatalog {
    NSUInteger session = self.session;
    __weak typeof(self) weakSelf = self;
    [self.catalog loadWithAliases:self.aliases fallbackNames:self.fallbackNames completion:^(NSArray *entries, BOOL available) {
        MTQuickLauncherView *view = weakSelf;
        if (!view.active || view.session != session) return;
        view.loaded = YES; view.available = available;
        // Catalog cache hits hand back the identical instance: keep query
        // results valid across panel sessions until the index really changes.
        if (view.entries != entries) { view.entries = entries; [view.queryCache removeAllObjects]; }
        [view updateResults];
    }];
}
- (void)endSession {
    self.active = NO; self.session++; self.generation++; self.launching = NO;
    [self.searchQueue cancelAllOperations]; [self cancelIconRequests];
    // 会话结束视为拖动被打断：宿主可能已先取消，这里只兜底清掉本地追踪态。
    if (self.dragging) { self.dragging = NO; self.dragPan.enabled = NO; self.dragPan.enabled = YES; }
    self.modePan.enabled = NO; self.modePan.enabled = YES;
    self.query = @""; self.results = @[];
    [self.collection reloadData]; [self.collection setContentOffset:CGPointZero animated:NO];
}
- (void)showOpenFailure {
    self.launching = NO; self.statusLabel.text = MTQL(@"QUICK_OPEN_FAILED");
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, self.statusLabel.text);
}
- (void)closeTapped { if (self.closeHandler) self.closeHandler(); }
- (void)resetTapped:(UITapGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded || !self.active || self.launching) return;
    if (self.resetHandler) self.resetHandler();
}
- (BOOL)accessibilityClose:(__unused UIAccessibilityCustomAction *)action { [self closeTapped]; return YES; }
- (void)configureQuickActions:(NSArray<NSDictionary *> *)actions {
    self.quickActions = [actions copy];
    self.modeButton.accessibilityCustomActions = self.accessibilityCustomActions;
    for (NSUInteger i = 0; i < self.actionButtons.count; i++) {
        NSDictionary *entry = i < actions.count ? actions[i] : @{};
        UIButton *button = self.actionButtons[i];
        NSString *name = [entry[@"name"] isKindOfClass:NSString.class] ? entry[@"name"] : @"";
        BOOL configured = [entry[@"selector"] length] > 0;
        // SF Symbols resolve cheaply on the main thread; app-icon lookups hit
        // disk and private APIs and must stay off the opening path.
        NSString *icon = [entry[@"icon"] isKindOfClass:NSString.class] ? entry[@"icon"] : @"";
        NSString *fallback = [MTHelper defaultIconForActionType:[entry[@"type"] isKindOfClass:NSString.class] ? entry[@"type"] : @""];
        UIImage *resolved = configured ? ([MTHelper symbolImageForIconConfig:icon] ?: [self.iconCache objectForKey:icon]) : nil;
        if (configured && !resolved && icon.length) {
            resolved = [UIImage systemImageNamed:fallback];
            [self loadActionIconAsyncForIcon:icon buttonIndex:i];
        }
        [button setImage:configured ? (resolved ?: [UIImage systemImageNamed:fallback]) : [UIImage systemImageNamed:@"plus.circle"] forState:UIControlStateNormal];
        [button setTitle:configured ? name : MTQL(@"QUICK_ACTION_EMPTY") forState:UIControlStateNormal];
        button.accessibilityLabel = configured ? name : MTQL(@"QUICK_ACTION_EMPTY_HINT");
        button.enabled = configured;
    }
    [self setNeedsLayout];
}
- (void)actionTapped:(UIButton *)button {
    if (!self.active || self.launching || button.tag < 0 || (NSUInteger)button.tag >= self.quickActions.count) return;
    NSString *selector = self.quickActions[button.tag][@"selector"];
    if (selector.length && self.actionHandler) self.actionHandler(selector);
}
- (void)setMode:(MTQuickLauncherMode)mode {
    if (!self.active || self.launching || self.dragging || mode == self.presentationMode) return;
    self.presentationMode = mode;
    // A previous search must never leak its results into the favorites stages.
    if (mode != MTQuickLauncherModeSearch) self.query = @"";
    self.modeHint = mode == MTQuickLauncherModeStrip ? @"QUICK_STAGE_EXPAND"
        : (mode == MTQuickLauncherModeSearch ? @"QUICK_STAGE_COLLAPSE" : @"QUICK_STAGE_SEARCH");
    [self updateResults];
    [self setNeedsLayout];
    if (self.modeChangeHandler) self.modeChangeHandler();
    [self layoutIfNeeded];
    UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, self.modeButton);
}
- (void)advanceMode { [self setMode:(MTQuickLauncherMode)((self.presentationMode + 1) % 3)]; }
- (void)modePanned:(UIPanGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateEnded) return;
    CGPoint d = [gesture translationInView:self], v = [gesture velocityInView:self];
    [self setMode:MTQuickLauncherNextMode(self.presentationMode, d.x, d.y, v.x)];
}
- (BOOL)isGrabberPoint:(CGPoint)point {
    CGFloat trailing = self.presentationMode == MTQuickLauncherModeSearch ? 48 : 0;
    return point.x >= 0 && point.x < self.panelContent.bounds.size.width - trailing &&
        point.y >= 0 && point.y <= MTQuickLauncherGrabberZoneHeight;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    if (!self.active || self.launching) return NO;
    // Reject at touch-down: shouldBegin runs only when a double tap is ready
    // to recognize, after UIKit has already held a key's touch-up for a timeout.
    CGPoint point = [touch locationInView:self.panelContent];
    if (gesture == self.dragPan || [gesture isKindOfClass:UITapGestureRecognizer.class])
        return [self isGrabberPoint:point];
    if (gesture == self.modePan) return !self.dragging && point.y > MTQuickLauncherGrabberZoneHeight;
    return YES;
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    if (!self.active || self.launching) return NO;
    CGPoint point = [gesture locationInView:self.panelContent];
    if (gesture == self.modePan) {
        CGPoint v = [self.modePan velocityInView:self];
        return !self.dragging && point.y > MTQuickLauncherGrabberZoneHeight && fabs(v.x) > fabs(v.y) * 1.2;
    }
    if (gesture == self.dragPan || [gesture isKindOfClass:UITapGestureRecognizer.class]) return [self isGrabberPoint:point];
    return YES;
}
- (void)emitDrag:(MTQuickLauncherDragPhase)phase translation:(CGPoint)translation {
    if (self.dragHandler) self.dragHandler(phase, translation);
}
- (void)dragPanned:(UIPanGestureRecognizer *)gesture {
    if (!self.dragHandler) return;
    UIView *reference = self.superview ?: self;
    CGPoint translation = [gesture translationInView:reference];
    [gesture setTranslation:CGPointZero inView:reference];
    if (gesture.state == UIGestureRecognizerStateBegan) { self.dragging = YES; [self emitDrag:MTQuickLauncherDragBegan translation:CGPointZero]; return; }
    if (!self.dragging) return;
    if (gesture.state == UIGestureRecognizerStateChanged) { [self emitDrag:MTQuickLauncherDragChanged translation:translation]; return; }
    self.dragging = NO;
    if (gesture.state == UIGestureRecognizerStateEnded) [self emitDrag:MTQuickLauncherDragEnded translation:translation];
    else [self emitDrag:MTQuickLauncherDragCancelled translation:CGPointZero];
}
- (void)cancelDrag {
    if (!self.dragging) return;
    self.dragging = NO;
    // 断开并重建手势状态，避免被系统打断的拖动继续追踪后续触摸。
    self.dragPan.enabled = NO; self.dragPan.enabled = YES;
    if (self.dragHandler) self.dragHandler(MTQuickLauncherDragCancelled, CGPointZero);
}
- (void)clearQuery { if (!self.active || self.launching || !self.query.length) return; self.query = @""; [self updateResults]; }
// 清空键的专用 tag：keyTapped 按 tag 分流，不依赖随本地化变化的标题文本。
static NSUInteger const MTQuickLauncherKeyTagClear = 100;

- (void)buildKeys {
    for (UIView *view in self.keyButtons) [view removeFromSuperview]; [self.keyButtons removeAllObjects];
    NSArray *titles = @[@"1\n·", @"2\nABC", @"3\nDEF", @"4\nGHI", @"5\nJKL", @"6\nMNO", @"7\nPQRS", @"8\nTUV", @"9\nWXYZ", @"", @"0", @"⌫"];
    for (NSUInteger i = 0; i < titles.count; i++) {
        BOOL clear = i == 9;
        UIButton *key = [UIButton buttonWithType:UIButtonTypeCustom]; key.tag = clear ? MTQuickLauncherKeyTagClear : i;
        key.layer.cornerRadius = 10;
        key.backgroundColor = [UIColor.labelColor colorWithAlphaComponent:0.12];
        NSString *text = clear ? MTQL(@"QUICK_CLEAR_KEY") : titles[i];
        NSMutableAttributedString *title = [[NSMutableAttributedString alloc] initWithString:text attributes:@{
            NSForegroundColorAttributeName: UIColor.labelColor, NSFontAttributeName: [UIFont systemFontOfSize:21]}];
        NSRange newline = [text rangeOfString:@"\n"];
        if (newline.location != NSNotFound) [title addAttribute:NSFontAttributeName value:[UIFont systemFontOfSize:9]
            range:NSMakeRange(newline.location + 1, text.length - newline.location - 1)];
        [key setAttributedTitle:title forState:UIControlStateNormal]; key.titleLabel.numberOfLines = 2; key.titleLabel.textAlignment = NSTextAlignmentCenter;
        key.accessibilityLabel = clear ? MTQL(@"QUICK_CLEAR") : [text isEqual:@"⌫"] ? MTQL(@"QUICK_DELETE")
            : [text stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
        [key addTarget:self action:@selector(keyTapped:) forControlEvents:UIControlEventTouchUpInside];
        if ([text isEqual:@"⌫"]) {
            UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(deleteHeld:)];
            [key addGestureRecognizer:hold];
        }
        [self.keys addSubview:key]; [self.keyButtons addObject:key];
    }
    [self setNeedsLayout];
}
- (void)deleteHeld:(UILongPressGestureRecognizer *)gesture { if (gesture.state == UIGestureRecognizerStateBegan) [self clearQuery]; }
- (void)keyTapped:(UIButton *)key {
    if (!self.active || self.launching) return;
    if (key.tag == MTQuickLauncherKeyTagClear) { [self clearQuery]; return; }
    NSString *text = [key attributedTitleForState:UIControlStateNormal].string;
    if ([text isEqual:@"⌫"]) {
        if (!self.query.length) return;
        self.query = [self.query substringToIndex:self.query.length - 1];
    } else if (self.query.length < 64) {
        NSString *value = [text componentsSeparatedByString:@"\n"].firstObject;
        self.query = [self.query stringByAppendingString:[value isEqual:@"␣"] ? @" " : value];
    } else return;
    [self updateResults];
}
- (void)updateResults {
    NSUInteger generation = ++self.generation, session = self.session;
    [self.searchQueue cancelAllOperations];
    NSString *query = self.query; BOOL searching = MTAppSearchNormalize(query).length > 0;
    self.queryLabel.text = query.length ? query : MTQL(@"QUICK_PLACEHOLDER");
    self.queryLabel.textColor = query.length ? UIColor.labelColor : UIColor.lightGrayColor;
    self.clearButton.hidden = !query.length;
    // Keep the last frame while matching, but never allow an old result to launch.
    // Swap the collection once per completed query instead of clearing/rebuilding twice.
    self.selectionIdentifier = nil;
    self.collection.userInteractionEnabled = NO;
    self.collection.accessibilityElementsHidden = YES;
    NSArray *entries = self.entries, *favorites = self.favorites; NSDictionary *usage = self.usage;
    if (!searching) {
        NSMutableDictionary *byID = [NSMutableDictionary dictionary];
        if (favorites.count) for (MTAppSearchEntry *entry in entries) byID[entry.identifier] = entry;
        NSMutableArray *results = [NSMutableArray array];
        for (NSString *identifier in favorites) {
            MTAppSearchEntry *entry = byID[identifier]; if (!entry) continue;
            MTAppSearchMatch *match = [MTAppSearchMatch new]; match.entry = entry; [results addObject:match];
        }
        if (self.presentationMode != MTQuickLauncherModeSearch && !favorites.count) {
            NSMutableSet *included = [NSMutableSet setWithArray:favorites];
            for (MTAppSearchEntry *entry in entries) {
                if ([included containsObject:entry.identifier]) continue;
                MTAppSearchMatch *match = [MTAppSearchMatch new]; match.entry = entry; [results addObject:match];
                [included addObject:entry.identifier];
            }
        }
        [self applyResults:results]; return;
    }
    NSArray *cached = [self.queryCache objectForKey:query];
    if (cached) { [self applyResults:cached]; return; }
    self.statusLabel.text = MTQL(@"QUICK_SEARCHING");
    __weak typeof(self) weakSelf = self;
    NSBlockOperation *operation = [NSBlockOperation new];
    __weak NSBlockOperation *weakOperation = operation;
    [operation addExecutionBlock:^{
        NSBlockOperation *work = weakOperation;
        if (!work || work.cancelled) return;
        NSArray *matches = MTAppSearchWithCancellation(entries, query, favorites, usage, ^{ return work.cancelled; });
        if (!matches || work.cancelled) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            MTQuickLauncherView *view = weakSelf;
            if (work.cancelled || !view.active || view.session != session || view.generation != generation) return;
            [view.queryCache setObject:matches forKey:query];
            [view applyResults:matches];
        });
    }];
    [self.searchQueue addOperation:operation];
}
- (void)applyResults:(NSArray *)results {
    // The shape of the collection only changes when its count changes. Rebind
    // existing cells for other queries instead of discarding the entire grid.
    BOOL sameCount = self.results.count == results.count;
    self.results = results;
    self.collection.userInteractionEnabled = YES;
    self.collection.accessibilityElementsHidden = NO;
    BOOL searching = MTAppSearchNormalize(self.query).length > 0;
    self.statusLabel.text = searching ? (results.count ? MTQL(@"QUICK_MATCHES") : MTQL(@"QUICK_NO_MATCHES")) : MTQL(results.count ? (self.presentationMode != MTQuickLauncherModeSearch && !self.favorites.count ? @"QUICK_ALL_APPS" : @"QUICK_FAVORITES") : @"QUICK_EMPTY_FAVORITES");
    if (!self.loaded) self.statusLabel.text = MTQL(@"QUICK_LOADING");
    else if (!self.available) self.statusLabel.text = MTQL(@"QUICK_CATALOG_UNAVAILABLE");
    if (sameCount) {
        for (NSIndexPath *path in self.collection.indexPathsForVisibleItems) {
            MTLauncherAppCell *cell = (MTLauncherAppCell *)[self.collection cellForItemAtIndexPath:path];
            if (path.item < results.count) [self configureCell:cell atIndexPath:path];
        }
    } else [self.collection reloadData];
    [self.collection setContentOffset:CGPointZero animated:NO];
}
- (void)cancelIconRequests {
    [self.iconQueue cancelAllOperations];
    [self.iconRequests removeAllObjects];
}
- (void)loadIconForCell:(MTLauncherAppCell *)cell identifier:(NSString *)identifier {
    BOOL sameIdentifier = [cell.representedIdentifier isEqual:identifier];
    cell.representedIdentifier = identifier;
    UIImage *cached = [self.iconCache objectForKey:identifier];
    if (cached || !sameIdentifier || !cell.icon.image)
        cell.icon.image = cached ?: [UIImage systemImageNamed:@"app"];
    if (cached || self.iconRequests[identifier] || !self.active || !self.collection.userInteractionEnabled) return;
    [self enqueueIconLoadForIdentifier:identifier];
}

// 格子与快捷按钮共用的后台图标任务：磁盘读取、私有图标查询与光栅化全部离开主线程，
// 回填前在主线程校验请求仍然有效（取消/会话/同一请求）。
- (void)enqueueIconLoadForIdentifier:(NSString *)identifier {
    if (!self.active || self.iconRequests[identifier]) return;
    __weak typeof(self) weakSelf = self;
    NSBlockOperation *operation = [NSBlockOperation new];
    __weak NSBlockOperation *weakOperation = operation;
    [operation addExecutionBlock:^{
        @autoreleasepool {
            NSBlockOperation *work = weakOperation;
            if (!work || work.cancelled) return;
            UIImage *icon = [MTHelper appIconImageForBundleID:identifier];
            icon = [icon imageByPreparingForDisplay] ?: icon;
            if (work.cancelled) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                MTQuickLauncherView *view = weakSelf;
                if (work.cancelled || view.iconRequests[identifier] != work) return;
                [view.iconRequests removeObjectForKey:identifier];
                if (!icon) return;
                [view.iconCache setObject:icon forKey:identifier];
                for (MTLauncherAppCell *visible in view.collection.visibleCells) {
                    if ([visible.representedIdentifier isEqual:identifier]) visible.icon.image = icon;
                }
            });
        }
    }];
    self.iconRequests[identifier] = operation;
    [self.iconQueue addOperation:operation];
}

- (void)prefetchFavoriteIcons {
    NSUInteger count = MIN(self.favorites.count, (NSUInteger)12);
    for (NSUInteger index = 0; index < count; index++) {
        NSString *identifier = self.favorites[index];
        if (![identifier isKindOfClass:NSString.class] || [self.iconCache objectForKey:identifier]) continue;
        [self enqueueIconLoadForIdentifier:identifier];
    }
}

// 快捷动作的 App 图标：先以回退符号占位，加载完成仅当按钮仍指向同一配置时回填。
- (void)loadActionIconAsyncForIcon:(NSString *)icon buttonIndex:(NSUInteger)index {
    UIImage *cached = [self.iconCache objectForKey:icon];
    if (cached) {
        [self.actionButtons[index] setImage:cached forState:UIControlStateNormal];
        return;
    }
    NSString *key = [@"action:" stringByAppendingString:icon];
    if (self.iconRequests[key]) return;
    __weak typeof(self) weakSelf = self;
    NSUInteger generation = self.generation, session = self.session;
    NSBlockOperation *operation = [NSBlockOperation new];
    __weak NSOperation *weakOperation = operation;
    [operation addExecutionBlock:^{
        @autoreleasepool {
            NSOperation *work = weakOperation;
            if (!work || work.cancelled) return;
            UIImage *appIcon = [MTHelper appIconImageForBundleID:icon];
            appIcon = [appIcon imageByPreparingForDisplay] ?: appIcon;
            if (work.cancelled) return;
            dispatch_async(dispatch_get_main_queue(), ^{
                MTQuickLauncherView *view = weakSelf;
                if (!view || work.cancelled || view.iconRequests[key] != work) return;
                [view.iconRequests removeObjectForKey:key];
                if (!appIcon || !view.active || view.generation != generation || view.session != session) return;
                NSDictionary *entry = index < view.quickActions.count ? view.quickActions[index] : nil;
                if (![entry isKindOfClass:NSDictionary.class] || ![entry[@"icon"] isKindOfClass:NSString.class] ||
                    ![entry[@"icon"] isEqual:icon]) return;
                [view.iconCache setObject:appIcon forKey:icon];
                [view.actionButtons[index] setImage:appIcon forState:UIControlStateNormal];
            });
        }
    }];
    self.iconRequests[key] = operation;
    [self.iconQueue addOperation:operation];
}
- (NSInteger)collectionView:(UICollectionView *)collection numberOfItemsInSection:(NSInteger)section {
    return self.results.count;
}
- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collection cellForItemAtIndexPath:(NSIndexPath *)path {
    MTLauncherAppCell *cell = [collection dequeueReusableCellWithReuseIdentifier:@"app" forIndexPath:path];
    [self configureCell:cell atIndexPath:path];
    return cell;
}
- (void)configureCell:(MTLauncherAppCell *)cell atIndexPath:(NSIndexPath *)path {
    MTAppSearchMatch *match = self.results[path.item];
    [self loadIconForCell:cell identifier:match.entry.identifier];
    cell.name.text = match.entry.name;
    cell.badge.text = match.quality == 3 ? MTQL(@"QUICK_APPROXIMATE") : @"";
    cell.accessibilityLabel = [NSString stringWithFormat:@"%@ %@", match.entry.name, cell.badge.text];
    NSUInteger generation = self.generation, session = self.session;
    NSString *identifier = match.entry.identifier;
    __weak typeof(self) weakSelf = self;
    cell.activationHandler = ^BOOL {
        MTQuickLauncherView *view = weakSelf;
        if (!view.active || view.launching || view.generation != generation || view.session != session || !view.selectHandler) return NO;
        view.selectHandler(identifier); return YES;
    };
}
- (BOOL)collectionView:(UICollectionView *)collection shouldHighlightItemAtIndexPath:(NSIndexPath *)path {
    if (!self.active || self.launching || path.item >= self.results.count) return NO;
    self.selectionGeneration = self.generation; self.selectionSession = self.session;
    self.selectionIdentifier = self.results[path.item].entry.identifier;
    return YES;
}
- (void)collectionView:(UICollectionView *)collection didSelectItemAtIndexPath:(NSIndexPath *)path {
    if (!self.active || self.launching || path.item >= self.results.count ||
        self.selectionGeneration != self.generation || self.selectionSession != self.session ||
        ![self.selectionIdentifier isEqual:self.results[path.item].entry.identifier]) return;
    NSString *identifier = self.selectionIdentifier; self.selectionIdentifier = nil;
    if (self.selectHandler) self.selectHandler(identifier);
}
- (void)layoutSubviews {
    [super layoutSubviews]; self.material.frame = self.bounds;
    BOOL search = self.presentationMode == MTQuickLauncherModeSearch;
    BOOL strip = self.presentationMode == MTQuickLauncherModeStrip;
    CGSize base = MTQuickLauncherModeBaseSize(self.presentationMode, self.landscape);
    CGFloat scale = MIN(self.bounds.size.width / base.width, self.bounds.size.height / base.height);
    self.panelContent.bounds = (CGRect){CGPointZero, base};
    self.panelContent.transform = CGAffineTransformMakeScale(scale, scale);
    self.panelContent.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    self.layer.cornerRadius = (strip ? 28 : 24) * scale;
    CGFloat width = base.width;
    self.grabber.frame = CGRectMake((width - 32) / 2, 8, 32, 4);
    self.titleLabel.hidden = YES; self.closeButton.hidden = !search;
    self.closeButton.frame = CGRectMake(width - 46, 0, 44, 44);
    MTQuickLauncherContentFrames frames = MTQuickLauncherContentLayout(self.presentationMode, self.landscape);
    CGFloat actionWidth = frames.actions.size.width / frames.actionColumns;
    for (NSUInteger i = 0; i < 4; i++) {
        self.actionButtons[i].frame = CGRectMake(frames.actions.origin.x + (i % frames.actionColumns) * actionWidth,
            frames.actions.origin.y + (i / frames.actionColumns) * frames.actionHeight, actionWidth, frames.actionHeight);
    }
    self.queryBackground.hidden = self.keys.hidden = !search; self.statusLabel.hidden = strip;
    self.queryBackground.frame = frames.query;
    self.queryLabel.frame = CGRectMake(10, 0, MAX(0, frames.query.size.width - 48), 36);
    self.clearButton.frame = CGRectMake(MAX(0, frames.query.size.width - 38), 0, 36, 36);
    self.statusLabel.frame = frames.status;
    self.keys.frame = frames.keys;
    self.collection.frame = frames.apps;
    NSUInteger columns = frames.appColumns;
    CGFloat contentWidth = frames.apps.size.width;
    CGFloat itemWidth = floor(contentWidth / columns);
    CGFloat itemHeight = search ? floor(self.collection.bounds.size.height / 3) : 66;
    CGSize itemSize = CGSizeMake(itemWidth, MAX(44, itemHeight));
    if (!CGSizeEqualToSize(self.flow.itemSize, itemSize)) { self.flow.itemSize = itemSize; [self.flow invalidateLayout]; }
    if (search) for (NSUInteger i = 0; i < self.keyButtons.count; i++) self.keyButtons[i].frame = MTQuickLauncherDigitFrame(self.keys.bounds.size, i);
    self.modeButton.frame = frames.footer;
    NSString *hint = self.modeHint ?: @"QUICK_STAGE_EXPAND";
    [self.modeButton setTitle:MTQL(hint) forState:UIControlStateNormal];
    self.modeButton.accessibilityLabel = MTQL(hint);
}
@end
