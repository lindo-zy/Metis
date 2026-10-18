#import "MTQuickLauncherView.h"
#import "MTQuickLauncherLayout.h"
#import "MTAppLauncherCatalog.h"
#import "MTHelper.h"
#import "common.h"

static NSString *MTQL(NSString *key) {
    return [[NSBundle bundleWithPath:bundlePath] localizedStringForKey:key value:key table:nil];
}

CGRect MTQuickLauncherFrame(CGRect bounds, UIEdgeInsets safe, NSInteger side, CGFloat scale) {
    return MTQuickLauncherPanelFrame(bounds, safe.top, safe.left, safe.bottom, safe.right, side, scale);
}

@interface MTLauncherPageCell : UICollectionViewCell
@property(nonatomic, copy) NSArray<MTAppSearchMatch *> *matches;
@property(nonatomic, copy) void (^selectHandler)(NSString *);
@property(nonatomic, strong) NSArray<UIButton *> *buttons;
@property(nonatomic, strong) NSArray<UIImageView *> *icons;
@property(nonatomic, strong) NSArray<UILabel *> *names;
@property(nonatomic, strong) NSArray<UILabel *> *badges;
@property(nonatomic) BOOL searchOrder;
@property(nonatomic) NSUInteger slots;
- (void)bind:(NSArray<MTAppSearchMatch *> *)matches slots:(NSUInteger)slots search:(BOOL)search;
@end

@implementation MTLauncherPageCell
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        NSMutableArray *buttons = [NSMutableArray array], *icons = [NSMutableArray array];
        NSMutableArray *names = [NSMutableArray array], *badges = [NSMutableArray array];
        for (NSUInteger i = 0; i < 6; i++) {
            UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom]; button.tag = i;
            [button addTarget:self action:@selector(selected:) forControlEvents:UIControlEventTouchUpInside];
            button.layer.cornerRadius = 10;
            UIImageView *icon = [UIImageView new]; icon.contentMode = UIViewContentModeScaleAspectFit;
            icon.layer.cornerRadius = 8; icon.clipsToBounds = YES; icon.userInteractionEnabled = NO;
            UILabel *name = [UILabel new]; name.font = [UIFont systemFontOfSize:11]; name.textColor = UIColor.whiteColor;
            name.textAlignment = NSTextAlignmentCenter;
            UILabel *badge = [UILabel new]; badge.font = [UIFont systemFontOfSize:9];
            badge.textColor = UIColor.systemTealColor; badge.textAlignment = NSTextAlignmentCenter;
            [button addSubview:icon]; [button addSubview:name]; [button addSubview:badge]; [self.contentView addSubview:button];
            [buttons addObject:button]; [icons addObject:icon]; [names addObject:name]; [badges addObject:badge];
        }
        self.buttons = buttons; self.icons = icons; self.names = names; self.badges = badges;
    } return self;
}
- (void)bind:(NSArray<MTAppSearchMatch *> *)matches slots:(NSUInteger)slots search:(BOOL)search {
    self.matches = matches; self.slots = slots; self.searchOrder = search;
    for (NSUInteger i = 0; i < 6; i++) {
        UIButton *button = self.buttons[i]; button.hidden = i >= matches.count;
        if (button.hidden) continue;
        MTAppSearchMatch *match = matches[i];
        self.icons[i].image = [MTHelper appIconImageForBundleID:match.entry.identifier] ?: [UIImage systemImageNamed:@"app"];
        self.names[i].text = match.entry.name;
        self.badges[i].text = match.quality == 3 ? MTQL(@"QUICK_APPROXIMATE") : @"";
        button.accessibilityLabel = [NSString stringWithFormat:@"%@ %@", match.entry.name, self.badges[i].text];
    }
    [self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width / 3, height = self.contentView.bounds.size.height / (self.slots == 3 ? 1 : 2);
    for (NSUInteger i = 0; i < 6; i++) {
        NSUInteger column = self.searchOrder ? 2 - i % 3 : i % 3;
        UIButton *button = self.buttons[i];
        button.frame = CGRectMake(column * width + 2, (i / 3) * height, width - 4, height - 2);
        CGFloat icon = MIN(36, MAX(24, height - 28));
        self.icons[i].frame = CGRectMake((width - 4 - icon) / 2, 2, icon, icon);
        self.names[i].frame = CGRectMake(1, icon + 3, width - 6, 14);
        self.badges[i].frame = CGRectMake(1, icon + 17, width - 6, 10);
    }
}
- (void)selected:(UIButton *)button {
    if (button.tag < 0 || (NSUInteger)button.tag >= self.matches.count) return;
    NSString *identifier = self.matches[button.tag].entry.identifier;
    if (identifier.length && self.selectHandler) self.selectHandler(identifier);
}
@end

@interface MTQuickLauncherView () <UICollectionViewDataSource, UICollectionViewDelegate>
@property(nonatomic, strong) UIVisualEffectView *material;
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UIButton *closeButton;
@property(nonatomic, strong) UIButton *clearButton;
@property(nonatomic, strong) UILabel *queryLabel;
@property(nonatomic, strong) UIView *queryBackground;
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic, strong) UIPageControl *pages;
@property(nonatomic, strong) UICollectionView *collection;
@property(nonatomic, strong) UICollectionViewFlowLayout *flow;
@property(nonatomic, strong) UIView *keys;
@property(nonatomic, strong) NSMutableArray<UIButton *> *keyButtons;
@property(nonatomic, strong) MTAppLauncherCatalog *catalog;
@property(nonatomic, strong) dispatch_queue_t searchQueue;
@property(nonatomic, copy) NSArray<MTAppSearchEntry *> *entries;
@property(nonatomic, copy) NSArray<MTAppSearchMatch *> *results;
@property(nonatomic, copy) NSArray<NSString *> *favorites;
@property(nonatomic, copy) NSDictionary *fallbackNames;
@property(nonatomic, copy) NSDictionary *aliases;
@property(nonatomic, copy) NSDictionary *usage;
@property(nonatomic, copy) NSString *query;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) NSUInteger session;
@property(nonatomic) NSUInteger slots;
@property(nonatomic) BOOL active;
@property(nonatomic) BOOL available;
@property(nonatomic) BOOL loaded;
@end

@implementation MTQuickLauncherView
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.layer.cornerRadius = 24; self.clipsToBounds = YES;
        self.layer.borderWidth = 0.5; self.layer.borderColor = [UIColor.whiteColor colorWithAlphaComponent:0.2].CGColor;
        self.material = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark]];
        self.material.userInteractionEnabled = NO; [self addSubview:self.material];
        self.titleLabel = [UILabel new]; self.titleLabel.text = MTQL(@"QUICK_TITLE");
        self.titleLabel.font = [UIFont boldSystemFontOfSize:17]; self.titleLabel.textColor = UIColor.whiteColor;
        [self addSubview:self.titleLabel];
        self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [self.closeButton setImage:[UIImage systemImageNamed:@"xmark"] forState:UIControlStateNormal];
        self.closeButton.tintColor = UIColor.whiteColor; self.closeButton.accessibilityLabel = MTQL(@"QUICK_CLOSE");
        [self.closeButton addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside]; [self addSubview:self.closeButton];
        self.queryBackground = [UIView new]; self.queryBackground.backgroundColor = [UIColor.whiteColor colorWithAlphaComponent:0.10];
        self.queryBackground.layer.cornerRadius = 12; [self addSubview:self.queryBackground];
        self.queryLabel = [UILabel new]; self.queryLabel.font = [UIFont systemFontOfSize:16]; self.queryLabel.textColor = UIColor.whiteColor;
        [self.queryBackground addSubview:self.queryLabel];
        self.clearButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [self.clearButton setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
        self.clearButton.tintColor = UIColor.lightGrayColor; self.clearButton.accessibilityLabel = MTQL(@"QUICK_CLEAR");
        [self.clearButton addTarget:self action:@selector(clearQuery) forControlEvents:UIControlEventTouchUpInside];
        [self.queryBackground addSubview:self.clearButton];
        self.statusLabel = [UILabel new]; self.statusLabel.textColor = UIColor.lightGrayColor;
        self.statusLabel.font = [UIFont systemFontOfSize:11]; [self addSubview:self.statusLabel];
        self.flow = [UICollectionViewFlowLayout new]; self.flow.scrollDirection = UICollectionViewScrollDirectionHorizontal;
        self.flow.minimumLineSpacing = 0; self.flow.minimumInteritemSpacing = 0;
        self.collection = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:self.flow];
        self.collection.backgroundColor = UIColor.clearColor; self.collection.pagingEnabled = YES;
        self.collection.showsHorizontalScrollIndicator = NO; self.collection.dataSource = self; self.collection.delegate = self;
        self.collection.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
        [self.collection registerClass:MTLauncherPageCell.class forCellWithReuseIdentifier:@"page"]; [self addSubview:self.collection];
        self.pages = [UIPageControl new]; self.pages.userInteractionEnabled = NO;
        self.pages.hidesForSinglePage = YES; [self addSubview:self.pages];
        self.keys = [UIView new]; [self addSubview:self.keys]; self.keyButtons = [NSMutableArray array];
        self.catalog = [MTAppLauncherCatalog new]; self.searchQueue = dispatch_queue_create("com.lindo.metis.keyboard.launcher.search", DISPATCH_QUEUE_SERIAL);
        __weak typeof(self) weakSelf = self;
        self.catalog.didInvalidate = ^{ if (weakSelf.active) [weakSelf loadCatalog]; };
        self.query = @""; self.results = @[]; self.entries = @[]; self.slots = 6;
        [self buildKeys];
    } return self;
}
- (void)beginWithFavorites:(NSArray<NSString *> *)favorites names:(NSDictionary<NSString *, NSString *> *)names
    aliases:(NSDictionary *)aliases usage:(NSDictionary *)usage {
    self.active = YES; self.session++; self.generation++; self.query = @""; self.launching = NO;
    self.favorites = [favorites copy]; self.fallbackNames = [names copy]; self.aliases = [aliases copy]; self.usage = [usage copy];
    self.loaded = NO; self.available = NO;
    NSMutableArray *seed = [NSMutableArray array];
    for (NSString *identifier in favorites) [seed addObject:[MTAppSearchEntry entryWithIdentifier:identifier name:names[identifier] ?: identifier aliases:@[]]];
    self.entries = seed;
    [self buildKeys]; [self updateResults]; [self loadCatalog];
}
- (void)loadCatalog {
    NSUInteger session = self.session;
    __weak typeof(self) weakSelf = self;
    [self.catalog loadWithAliases:self.aliases fallbackNames:self.fallbackNames completion:^(NSArray *entries, BOOL available) {
        MTQuickLauncherView *view = weakSelf;
        if (!view.active || view.session != session) return;
        view.loaded = YES; view.available = available; view.entries = entries; [view updateResults];
    }];
}
- (void)endSession {
    self.active = NO; self.session++; self.generation++; self.launching = NO;
    self.query = @""; self.results = @[];
    [self.collection setContentOffset:CGPointZero animated:NO]; [self.collection reloadData];
}
- (void)showOpenFailure {
    self.launching = NO; self.statusLabel.text = MTQL(@"QUICK_OPEN_FAILED");
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, self.statusLabel.text);
}
- (void)closeTapped { if (self.closeHandler) self.closeHandler(); }
- (void)clearQuery { if (!self.active || self.launching) return; self.query = @""; [self updateResults]; }
// 清空键的专用 tag：keyTapped 按 tag 分流，不依赖随本地化变化的标题文本。
static NSUInteger const MTQuickLauncherKeyTagClear = 100;

- (void)buildKeys {
    for (UIView *view in self.keyButtons) [view removeFromSuperview]; [self.keyButtons removeAllObjects];
    NSArray *titles = @[@"1\n·", @"2\nABC", @"3\nDEF", @"4\nGHI", @"5\nJKL", @"6\nMNO", @"7\nPQRS", @"8\nTUV", @"9\nWXYZ", @"", @"0", @"⌫"];
    for (NSUInteger i = 0; i < titles.count; i++) {
        BOOL clear = i == 9;
        UIButton *key = [UIButton buttonWithType:UIButtonTypeCustom]; key.tag = clear ? MTQuickLauncherKeyTagClear : i;
        key.layer.cornerRadius = 10;
        key.backgroundColor = [UIColor.whiteColor colorWithAlphaComponent:0.12];
        NSString *text = clear ? MTQL(@"QUICK_CLEAR_KEY") : titles[i];
        NSMutableAttributedString *title = [[NSMutableAttributedString alloc] initWithString:text attributes:@{
            NSForegroundColorAttributeName: UIColor.whiteColor, NSFontAttributeName: [UIFont systemFontOfSize:21]}];
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
        if (self.query.length) self.query = [self.query substringToIndex:self.query.length - 1];
    } else if (self.query.length < 64) {
        NSString *value = [text componentsSeparatedByString:@"\n"].firstObject;
        self.query = [self.query stringByAppendingString:[value isEqual:@"␣"] ? @" " : value];
    }
    [self updateResults];
}
- (void)updateResults {
    NSUInteger generation = ++self.generation, session = self.session;
    NSString *query = self.query; BOOL searching = MTAppSearchNormalize(query).length > 0;
    self.queryLabel.text = query.length ? query : MTQL(@"QUICK_PLACEHOLDER");
    self.queryLabel.textColor = query.length ? UIColor.whiteColor : UIColor.lightGrayColor;
    self.clearButton.hidden = !query.length;
    // Old buttons disappear immediately when the query changes, before background matching returns.
    self.results = @[]; [self.collection setContentOffset:CGPointZero animated:NO]; [self.collection reloadData]; self.pages.numberOfPages = 0;
    NSArray *entries = self.entries, *favorites = self.favorites; NSDictionary *usage = self.usage;
    if (!searching) {
        NSMutableDictionary *byID = [NSMutableDictionary dictionary];
        for (MTAppSearchEntry *entry in entries) byID[entry.identifier] = entry;
        NSMutableArray *results = [NSMutableArray array];
        for (NSString *identifier in favorites) {
            MTAppSearchEntry *entry = byID[identifier]; if (!entry) continue;
            MTAppSearchMatch *match = [MTAppSearchMatch new]; match.entry = entry; [results addObject:match];
        }
        [self applyResults:results]; return;
    }
    self.statusLabel.text = MTQL(@"QUICK_SEARCHING");
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.searchQueue, ^{
        NSArray *matches = MTAppSearch(entries, query, favorites, usage);
        dispatch_async(dispatch_get_main_queue(), ^{
            MTQuickLauncherView *view = weakSelf;
            if (!view.active || view.session != session || view.generation != generation) return;
            [view applyResults:matches];
        });
    });
}
- (void)applyResults:(NSArray *)results {
    self.results = results;
    BOOL searching = MTAppSearchNormalize(self.query).length > 0;
    self.statusLabel.text = searching ? (results.count ? MTQL(@"QUICK_MATCHES") : MTQL(@"QUICK_NO_MATCHES")) : MTQL(@"QUICK_FAVORITES");
    if (!self.loaded) self.statusLabel.text = MTQL(@"QUICK_LOADING");
    else if (!self.available) self.statusLabel.text = MTQL(@"QUICK_CATALOG_UNAVAILABLE");
    self.pages.numberOfPages = (results.count + self.slots - 1) / self.slots; self.pages.currentPage = 0;
    [self.collection reloadData];
}
- (NSInteger)collectionView:(UICollectionView *)collection numberOfItemsInSection:(NSInteger)section {
    return (self.results.count + self.slots - 1) / self.slots;
}
- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collection cellForItemAtIndexPath:(NSIndexPath *)path {
    MTLauncherPageCell *cell = [collection dequeueReusableCellWithReuseIdentifier:@"page" forIndexPath:path];
    NSUInteger start = path.item * self.slots;
    if (start >= self.results.count) return cell;
    [cell bind:[self.results subarrayWithRange:NSMakeRange(start, MIN(self.slots, self.results.count - start))]
        slots:self.slots search:MTAppSearchNormalize(self.query).length > 0];
    NSUInteger session = self.session, generation = self.generation;
    __weak typeof(self) weakSelf = self;
    cell.selectHandler = ^(NSString *identifier) {
        MTQuickLauncherView *view = weakSelf;
        if (!view.active || view.launching || view.session != session || view.generation != generation) return;
        if (view.selectHandler) view.selectHandler(identifier);
    };
    return cell;
}
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (scrollView.bounds.size.width > 0) self.pages.currentPage = lround(scrollView.contentOffset.x / scrollView.bounds.size.width);
}
- (void)layoutSubviews {
    [super layoutSubviews]; self.material.frame = self.bounds;
    CGFloat width = self.bounds.size.width, height = self.bounds.size.height;
    BOOL wide = width > 400; CGFloat contentWidth = wide ? floor(width * 0.47) - 20 : width - 24;
    self.titleLabel.frame = CGRectMake(12, 8, contentWidth - 44, 28);
    self.closeButton.frame = CGRectMake(width - 48, 0, 44, 44);
    self.queryBackground.frame = CGRectMake(12, 44, contentWidth, 36);
    self.queryLabel.frame = CGRectMake(10, 0, contentWidth - 48, 36);
    self.clearButton.frame = CGRectMake(contentWidth - 38, 0, 36, 36);
    self.statusLabel.frame = CGRectMake(12, 84, contentWidth, 18);
    CGFloat gridHeight = wide ? height - 128 : 132;
    self.collection.frame = CGRectMake(12, 104, contentWidth, gridHeight);
    self.pages.frame = CGRectMake(12, 104 + gridHeight, contentWidth, 12);
    NSUInteger slots = gridHeight < 110 ? 3 : 6;
    BOOL changed = self.slots != slots; self.slots = slots;
    CGSize itemSize = CGSizeMake(contentWidth, gridHeight);
    if (!CGSizeEqualToSize(self.flow.itemSize, itemSize)) { self.flow.itemSize = itemSize; [self.flow invalidateLayout]; }
    self.keys.frame = MTQuickLauncherKeysFrame(self.bounds.size);
    for (NSUInteger i = 0; i < self.keyButtons.count; i++) self.keyButtons[i].frame = MTQuickLauncherDigitFrame(self.keys.bounds.size, i);
    if (changed) { self.pages.numberOfPages = (self.results.count + slots - 1) / slots; [self.collection setContentOffset:CGPointZero animated:NO]; [self.collection reloadData]; }
}
@end
