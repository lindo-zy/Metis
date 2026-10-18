//
//  MTHistoryListViewController.m
//  Mt
//

#import "MTHistoryListViewController.h"
#import "MTFavoritesTableView.h"
#import "MTHistoryItemActionHandler.h"
#import "MTHistoryListView.h"
#import "MTHistoryTableView.h"
#import "MTPasteboardItem.h"
#import "MTPasteboardManager.h"
#import "MTSearchCriteria.h"
#import "MTSnapperIntegration.h"
#import "MTTableDataStore.h"
#import "MTTableViewCell.h"
#import "MTTableViewCellContent.h"
#import "MTTableViewCellContentProvider.h"

// 系统动作（Keyboard 共享层，经 MetisCore 链接）：目录 + 执行器 + 截图集成检查。
#import "common.h"
#import "MTCaptureIntegration.h"
#import "MTSystemActionCatalog.h"
#import "MTSystemActionExecutor.h"

#import <math.h>
#import <objc/runtime.h>

static CGFloat const kMTGalleryMinimumRowHeight = 112;
static NSUInteger const kMTGalleryColumnCount = 2;
static const void *kMTGalleryItemDictionaryKey = &kMTGalleryItemDictionaryKey;
static CGFloat const kMTGalleryActionMinimumWidth = 40;
static CGFloat const kMTGalleryActionMaximumWidth = 52;
static NSInteger const kMTGalleryTrailingActionTagOffset = 1000;

typedef void (^MTGalleryActionHandler)(UIView *sourceView, void (^completion)(BOOL success));

@interface MTGalleryAction : NSObject
@property(nonatomic, assign) UIContextualActionStyle style;
@property(nonatomic, strong) UIImage *image;
@property(nonatomic, strong) UIColor *backgroundColor;
@property(nonatomic, copy) NSString *accessibilityLabel;
@property(nonatomic, copy) MTGalleryActionHandler handler;
@end

@implementation MTGalleryAction
@end

@interface MTGallerySwipeView : UIView <UIGestureRecognizerDelegate>
@property(nonatomic, strong, readonly) MTTableViewCell *itemCell;
@property(nonatomic, copy) void (^willOpenHandler)(MTGallerySwipeView *swipeView);
- (instancetype)initWithItemCell:(MTTableViewCell *)itemCell
                  leadingActions:(NSArray<MTGalleryAction *> *)leadingActions
                 trailingActions:(NSArray<MTGalleryAction *> *)trailingActions;
- (void)setOpen:(BOOL)open animated:(BOOL)animated;
- (BOOL)isOpen;
@end

@interface MTGallerySwipeView ()
@property(nonatomic, strong, readwrite) MTTableViewCell *itemCell;
@property(nonatomic, copy) NSArray<MTGalleryAction *> *leadingActions;
@property(nonatomic, copy) NSArray<MTGalleryAction *> *trailingActions;
@property(nonatomic, strong) UIStackView *leadingActionStackView;
@property(nonatomic, strong) UIStackView *trailingActionStackView;
@property(nonatomic, strong) UIPanGestureRecognizer *panGestureRecognizer;
@property(nonatomic, assign) CGFloat leadingRevealWidth;
@property(nonatomic, assign) CGFloat trailingRevealWidth;
@property(nonatomic, assign) CGFloat panStartOffset;
@property(nonatomic, assign) CGFloat contentOffset;
@end

@implementation MTGallerySwipeView

- (instancetype)initWithItemCell:(MTTableViewCell *)itemCell
                  leadingActions:(NSArray<MTGalleryAction *> *)leadingActions
                 trailingActions:(NSArray<MTGalleryAction *> *)trailingActions {
    self = [super initWithFrame:CGRectZero];
    if (!self) {
        return nil;
    }

    _itemCell = itemCell;
    _leadingActions = [leadingActions copy] ?: @[];
    _trailingActions = [trailingActions copy] ?: @[];
    [self setClipsToBounds:YES];
    [[self layer] setCornerRadius:12];

    _leadingActionStackView = [[UIStackView alloc] init];
    [_leadingActionStackView setAxis:UILayoutConstraintAxisHorizontal];
    [_leadingActionStackView setDistribution:UIStackViewDistributionFillEqually];
    [self addSubview:_leadingActionStackView];
    _trailingActionStackView = [[UIStackView alloc] init];
    [_trailingActionStackView setAxis:UILayoutConstraintAxisHorizontal];
    [_trailingActionStackView setDistribution:UIStackViewDistributionFillEqually];
    [self addSubview:_trailingActionStackView];

    [_leadingActions enumerateObjectsUsingBlock:^(MTGalleryAction *action, NSUInteger index, BOOL *stop) {
      (void)stop;
      UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
      [button setTag:(NSInteger)index];
      [button setImage:[action image] forState:UIControlStateNormal];
      [button setTintColor:[UIColor whiteColor]];
      [button setBackgroundColor:[action backgroundColor]];
      [button setAccessibilityLabel:[action accessibilityLabel]];
      [[button imageView] setContentMode:UIViewContentModeScaleAspectFit];
      [button addTarget:self action:@selector(handleActionButton:) forControlEvents:UIControlEventTouchUpInside];
      [[self leadingActionStackView] addArrangedSubview:button];
    }];
    [_trailingActions enumerateObjectsUsingBlock:^(MTGalleryAction *action, NSUInteger index, BOOL *stop) {
      (void)stop;
      UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
      [button setTag:kMTGalleryTrailingActionTagOffset + (NSInteger)index];
      [button setImage:[action image] forState:UIControlStateNormal];
      [button setTintColor:[UIColor whiteColor]];
      [button setBackgroundColor:[action backgroundColor]];
      [button setAccessibilityLabel:[action accessibilityLabel]];
      [[button imageView] setContentMode:UIViewContentModeScaleAspectFit];
      [button addTarget:self action:@selector(handleActionButton:) forControlEvents:UIControlEventTouchUpInside];
      [[self trailingActionStackView] addArrangedSubview:button];
    }];

    [self addSubview:_itemCell];
    _panGestureRecognizer = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePanGesture:)];
    [_panGestureRecognizer setDelegate:self];
    [_panGestureRecognizer setMaximumNumberOfTouches:1];
    [self addGestureRecognizer:_panGestureRecognizer];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = CGRectGetWidth([self bounds]);
    CGFloat actionWidth = MIN(kMTGalleryActionMaximumWidth,
                              MAX(kMTGalleryActionMinimumWidth, floor(width / 4.0)));
    [self setLeadingRevealWidth:MIN(width, actionWidth * [[self leadingActions] count])];
    [self setTrailingRevealWidth:MIN(width, actionWidth * [[self trailingActions] count])];
    CGFloat height = CGRectGetHeight([self bounds]);
    [[self leadingActionStackView] setFrame:CGRectMake(0, 0, [self leadingRevealWidth], height)];
    [[self trailingActionStackView]
        setFrame:CGRectMake(width - [self trailingRevealWidth], 0, [self trailingRevealWidth], height)];
    [[self itemCell] setTransform:CGAffineTransformIdentity];
    [[self itemCell] setFrame:[self bounds]];
    [[self itemCell] setTransform:CGAffineTransformMakeTranslation([self contentOffset], 0)];

    CGFloat symbolPointSize = MIN(18, MAX(14, floor(width / 11.0)));
    UIImageSymbolConfiguration *configuration =
        [UIImageSymbolConfiguration configurationWithPointSize:symbolPointSize weight:UIImageSymbolWeightSemibold];
    for (UIStackView *stackView in @[ [self leadingActionStackView], [self trailingActionStackView] ]) {
        for (UIButton *button in [stackView arrangedSubviews]) {
            UIImage *image = [button imageForState:UIControlStateNormal];
            [button setImage:[image imageByApplyingSymbolConfiguration:configuration] forState:UIControlStateNormal];
        }
    }
}

- (BOOL)isOpen {
    return fabs([self contentOffset]) > 0.5;
}

- (void)setOpen:(BOOL)open animated:(BOOL)animated {
    CGFloat targetOffset = 0;
    if (open) {
        targetOffset = [self contentOffset] < 0 ? -[self trailingRevealWidth] : [self leadingRevealWidth];
    }
    [self setContentOffset:targetOffset];
    void (^changes)(void) = ^{
      [[self itemCell] setTransform:CGAffineTransformMakeTranslation(targetOffset, 0)];
    };
    if (animated) {
        [UIView animateWithDuration:0.22
                              delay:0
             usingSpringWithDamping:0.9
              initialSpringVelocity:0
                            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                         animations:changes
                         completion:nil];
    } else {
        changes();
    }
}

- (BOOL)gestureRecognizerShouldBegin:(UIPanGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer != [self panGestureRecognizer] ||
        ([[self leadingActions] count] == 0 && [[self trailingActions] count] == 0)) {
        return NO;
    }
    CGPoint velocity = [gestureRecognizer velocityInView:self];
    if (fabs(velocity.x) <= fabs(velocity.y)) {
        return NO;
    }
    return [self isOpen] || (velocity.x > 0 && [[self leadingActions] count] > 0) ||
           (velocity.x < 0 && [[self trailingActions] count] > 0);
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
    shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    (void)gestureRecognizer;
    (void)otherGestureRecognizer;
    return YES;
}

- (void)handlePanGesture:(UIPanGestureRecognizer *)recognizer {
    switch ([recognizer state]) {
        case UIGestureRecognizerStateBegan:
            [self setPanStartOffset:[self contentOffset]];
            if (![self isOpen] && [self willOpenHandler]) {
                [self willOpenHandler](self);
            }
            break;
        case UIGestureRecognizerStateChanged: {
            CGFloat translation = [recognizer translationInView:self].x;
            CGFloat offset = MIN([self leadingRevealWidth],
                                 MAX(-[self trailingRevealWidth], [self panStartOffset] + translation));
            [self setContentOffset:offset];
            [[self itemCell] setTransform:CGAffineTransformMakeTranslation(offset, 0)];
            break;
        }
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            CGFloat velocity = [recognizer velocityInView:self].x;
            BOOL opensLeading = [[self leadingActions] count] > 0 &&
                                  (velocity > 300 || ([self contentOffset] > 0 && velocity >= -300 &&
                                                      [self contentOffset] >= [self leadingRevealWidth] * 0.5));
            BOOL opensTrailing = [[self trailingActions] count] > 0 &&
                                   (velocity < -300 || ([self contentOffset] < 0 && velocity <= 300 &&
                                                       -[self contentOffset] >= [self trailingRevealWidth] * 0.5));
            if (opensLeading) {
                [self setContentOffset:MAX([self contentOffset], 0.5)];
            } else if (opensTrailing) {
                [self setContentOffset:MIN([self contentOffset], -0.5)];
            }
            BOOL opens = opensLeading || opensTrailing;
            [self setOpen:opens animated:YES];
            break;
        }
        default:
            break;
    }
}

- (void)handleActionButton:(UIButton *)button {
    BOOL trailing = [button tag] >= kMTGalleryTrailingActionTagOffset;
    NSUInteger index = (NSUInteger)([button tag] - (trailing ? kMTGalleryTrailingActionTagOffset : 0));
    NSArray<MTGalleryAction *> *actions = trailing ? [self trailingActions] : [self leadingActions];
    if (index >= [actions count]) {
        return;
    }
    MTGalleryAction *action = actions[index];
    [button setEnabled:NO];
    __weak typeof(self) weakSelf = self;
    [action handler]([self itemCell], ^(BOOL success) {
      dispatch_async(dispatch_get_main_queue(), ^{
        [button setEnabled:YES];
        if (success) {
            [weakSelf setOpen:NO animated:YES];
        }
      });
    });
}

@end

@interface MTGalleryRowCell : UITableViewCell
@property(nonatomic, copy) NSArray<MTTableViewCell *> *itemCells;
@property(nonatomic, copy) NSArray<MTGallerySwipeView *> *itemSwipeViews;
- (void)setGalleryItemSwipeViews:(NSArray<MTGallerySwipeView *> *)itemSwipeViews;
- (nullable MTTableViewCell *)itemCellAtColumn:(NSUInteger)column;
@end

@implementation MTGalleryRowCell

- (instancetype)initWithReuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
    if (self) {
        [self setBackgroundColor:[UIColor clearColor]];
        [self setSelectionStyle:UITableViewCellSelectionStyleNone];
    }
    return self;
}

- (void)setGalleryItemSwipeViews:(NSArray<MTGallerySwipeView *> *)itemSwipeViews {
    for (UIView *view in [self itemSwipeViews]) {
        [view removeFromSuperview];
    }
    _itemSwipeViews = [itemSwipeViews copy] ?: @[];
    NSMutableArray<MTTableViewCell *> *itemCells = [[NSMutableArray alloc] initWithCapacity:[_itemSwipeViews count]];
    for (MTGallerySwipeView *swipeView in _itemSwipeViews) {
        [itemCells addObject:[swipeView itemCell]];
    }
    _itemCells = [itemCells copy];

    UIView *previousView = nil;
    for (MTGallerySwipeView *swipeView in _itemSwipeViews) {
        [[self contentView] addSubview:swipeView];
        [swipeView setTranslatesAutoresizingMaskIntoConstraints:NO];
        NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray arrayWithArray:@[
            [[swipeView topAnchor] constraintEqualToAnchor:[[self contentView] topAnchor] constant:5],
            [[swipeView bottomAnchor] constraintEqualToAnchor:[[self contentView] bottomAnchor] constant:-5]
        ]];
        if (previousView) {
            [constraints addObject:[[swipeView leadingAnchor] constraintEqualToAnchor:[previousView trailingAnchor]
                                                                             constant:8]];
            [constraints addObject:[[swipeView widthAnchor] constraintEqualToAnchor:[previousView widthAnchor]]];
        } else {
            [constraints addObject:[[swipeView leadingAnchor] constraintEqualToAnchor:[[self contentView] leadingAnchor]
                                                                             constant:8]];
            [constraints addObject:[[swipeView widthAnchor] constraintEqualToAnchor:[[self contentView] widthAnchor]
                                                                       multiplier:0.5
                                                                         constant:-12]];
        }
        [NSLayoutConstraint activateConstraints:constraints];
        previousView = swipeView;
    }
    if ([[self itemSwipeViews] count] == kMTGalleryColumnCount) {
        [[previousView trailingAnchor] constraintEqualToAnchor:[[self contentView] trailingAnchor] constant:-8].active = YES;
    }
}

- (nullable MTTableViewCell *)itemCellAtColumn:(NSUInteger)column {
    return column < [[self itemCells] count] ? [self itemCells][column] : nil;
}

@end

NS_ASSUME_NONNULL_BEGIN

@interface MTHistoryListViewController () <UITableViewDelegate, UITableViewDataSource>

#pragma mark - Views

@property(nonatomic, strong, readwrite) MTHistoryListView *tableView;

#pragma mark - State

@property(nonatomic, copy, readwrite) NSString *historyKey;
@property(nonatomic, copy, readwrite) NSString *name;

#pragma mark - Data

@property(nonatomic, strong) MTTableDataStore *dataStore;
@property(nonatomic, strong) MTTableViewCellContentProvider *cellContentProvider;
@property(nonatomic, strong) MTHistoryItemActionHandler *actionHandler;
@property(nonatomic, copy, nullable) NSString *presentationHiddenItemContent;
@property(nonatomic, weak, nullable) MTGallerySwipeView *openGallerySwipeView;

- (MTTableViewCell *)newCellForItem:(MTPasteboardItem *)item addsPreviewGesture:(BOOL)addsPreviewGesture;
- (MTTableViewCell *)newGalleryCellForItem:(MTPasteboardItem *)item
                                     dictionary:(NSDictionary<NSString *, id> *)dictionary;
- (void)loadThumbnailForItem:(MTPasteboardItem *)item
                    intoCell:(MTTableViewCell *)cell
                  targetSize:(CGSize)targetSize;
- (void)refreshVisibleItemDetails;
- (NSArray<MTGalleryAction *> *)leadingActionsForItem:(MTPasteboardItem *)item
                                               dictionary:(NSDictionary<NSString *, id> *)dictionary
                                                indexPath:(NSIndexPath *)indexPath;
- (MTGalleryAction *)deleteActionForItem:(MTPasteboardItem *)item indexPath:(NSIndexPath *)indexPath;
- (UIContextualAction *)contextualActionForGalleryAction:(MTGalleryAction *)galleryAction;
- (nullable UIContextualAction *)snapperActionForItem:(MTPasteboardItem *)item;
@end

NS_ASSUME_NONNULL_END

@implementation MTHistoryListViewController

#pragma mark - Lifecycle

- (instancetype)initWithName:(NSString *)name historyKey:(NSString *)historyKey {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _name = [name copy] ?: @"";
        _historyKey = [historyKey copy] ?: kMTHistoryKeyHistory;
        if ([_historyKey isEqualToString:kMTHistoryKeyFavorites]) {
            _tableView = [[MTFavoritesTableView alloc] initWithName:_name];
        } else {
            _tableView = [[MTHistoryTableView alloc] initWithName:_name];
        }
        _dataStore = [[MTTableDataStore alloc] init];
        _cellContentProvider = [[MTTableViewCellContentProvider alloc] init];
        _actionHandler = [[MTHistoryItemActionHandler alloc] init];
        [_tableView setName:_name];
        [_tableView setDelegate:self];
        [_tableView setDataSource:self];
    }
    return self;
}

- (void)loadView {
    [self setView:[self tableView]];
}

#pragma mark - State

- (NSArray<NSDictionary<NSString *, id> *> *)items {
    return [[self dataStore] items];
}

- (NSArray<NSDictionary<NSString *, id> *> *)displayedItems {
    return [[self dataStore] displayedItems];
}

- (NSString *)searchText {
    return [[self dataStore] searchText];
}

- (MTSearchCriteria *)searchCriteria {
    return [[self dataStore] searchCriteria];
}

- (BOOL)isBrowsingSearchTokens {
    return [[self dataStore] isBrowsingSearchTokens];
}

- (BOOL)hasActiveSearch {
    return [[self dataStore] hasActiveSearch];
}

- (void)setPreviewLineCount:(NSUInteger)previewLineCount {
    [[self tableView] setPreviewLineCount:previewLineCount];
}

- (NSUInteger)previewLineCount {
    return [[self tableView] previewLineCount];
}

- (void)setPrivacyMode:(BOOL)privacyMode {
    [[self cellContentProvider] setPrivacyMode:privacyMode];
    [self reloadTableView];
}

- (BOOL)privacyMode {
    return [[self cellContentProvider] privacyMode];
}

- (void)setItemDetailsMode:(MTItemDetailsMode)itemDetailsMode {
    [[self tableView] setItemDetailsMode:itemDetailsMode];
}

- (MTItemDetailsMode)itemDetailsMode {
    return [[self tableView] itemDetailsMode];
}

- (void)setGalleryModeEnabled:(BOOL)galleryModeEnabled {
    if (_galleryModeEnabled == galleryModeEnabled) {
        return;
    }
    _galleryModeEnabled = galleryModeEnabled;
    MTHistoryListView *tableView = [self tableView];
    [tableView setSeparatorStyle:galleryModeEnabled ? UITableViewCellSeparatorStyleNone
                                               : UITableViewCellSeparatorStyleSingleLine];
    if (galleryModeEnabled) {
        [tableView setRowHeight:MAX(kMTGalleryMinimumRowHeight, floor(CGRectGetHeight([tableView bounds]) / 3.0))];
    } else {
        [tableView setPreviewLineCount:[tableView previewLineCount]];
    }
    [self reloadTableView];
}

- (void)refreshSearchPlaceholder {
    BOOL showsNoSearchResults = [self hasActiveSearch] && ![self isBrowsingSearchTokens] && [[self items] count] > 0 &&
                                [[self displayedItems] count] == 0;
    [[self tableView] setShowsNoSearchResultsPlaceholder:showsNoSearchResults];
}

- (void)reloadTableView {
    [[self tableView] reloadData];
    [self refreshSearchPlaceholder];
}

- (void)refreshVisibleItemDetails {
    if ([self isGalleryModeEnabled]) {
        NSArray<NSIndexPath *> *visibleRows = [[self tableView] indexPathsForVisibleRows];
        if ([visibleRows count] > 0) {
            [[self tableView] reloadRowsAtIndexPaths:visibleRows withRowAnimation:UITableViewRowAnimationNone];
        }
        return;
    }
    for (NSIndexPath *indexPath in [[self tableView] indexPathsForVisibleRows]) {
        MTPasteboardItem *item =
            [MTPasteboardItem itemFromDictionary:[self itemDictionaryAtIndexPath:indexPath]];
        if (!item) {
            continue;
        }
        MTTableViewCellContent *content = [[self cellContentProvider] cellContentForItem:item
                                                                            previewLineCount:[self previewLineCount]
                                                                             itemDetailsMode:[self itemDetailsMode]
                                                                                  searchText:[self searchText]];
        MTTableViewCell *cell = (MTTableViewCell *)[[self tableView] cellForRowAtIndexPath:indexPath];
        [cell applyDetailContent:content];
    }
}

- (void)scrollToTopAnimated:(BOOL)animated {
    [[self tableView] scrollToTopAnimated:animated];
}

#pragma mark - Diffing

- (NSArray<NSIndexPath *> *)indexPathsFromRow:(NSUInteger)startRow count:(NSUInteger)count {
    NSMutableArray<NSIndexPath *> *indexPaths = [[NSMutableArray alloc] initWithCapacity:count];
    for (NSUInteger row = startRow; row < startRow + count; row++) {
        [indexPaths addObject:[NSIndexPath indexPathForRow:row inSection:0]];
    }
    return indexPaths;
}

- (BOOL)canUpdateFromItems:(NSArray<NSDictionary<NSString *, id> *> *)oldItems
                   toItems:(NSArray<NSDictionary<NSString *, id> *> *)newItems
      withTopInsertedCount:(NSUInteger *)insertedCount
        bottomRemovedCount:(NSUInteger *)removedCount {
    NSUInteger oldCount = [oldItems count];
    NSUInteger newCount = [newItems count];

    if (newCount == 0 || [oldItems isEqualToArray:newItems]) {
        return NO;
    }

    if (oldCount == 0) {
        if (insertedCount) {
            *insertedCount = newCount;
        }
        if (removedCount) {
            *removedCount = 0;
        }
        return YES;
    }

    NSUInteger candidateInsertedCount = [newItems indexOfObject:oldItems[0]];
    if (candidateInsertedCount == NSNotFound || candidateInsertedCount == 0) {
        return NO;
    }

    NSUInteger retainedCount = MIN(oldCount, newCount - candidateInsertedCount);
    if (retainedCount == 0 || candidateInsertedCount + retainedCount != newCount) {
        return NO;
    }

    for (NSUInteger index = 0; index < retainedCount; index++) {
        if (![newItems[candidateInsertedCount + index] isEqual:oldItems[index]]) {
            return NO;
        }
    }

    if (insertedCount) {
        *insertedCount = candidateInsertedCount;
    }
    if (removedCount) {
        *removedCount = oldCount - retainedCount;
    }
    return YES;
}

- (NSUInteger)normalizedLimit:(NSUInteger)limit {
    return limit == 0 ? NSUIntegerMax : limit;
}

- (BOOL)shouldRestoreContentOffsetAfterTopInsertionFromOffset:(CGPoint)contentOffset {
    return ![self hasActiveSearch] && [[self tableView] isContentOffsetAtHiddenSearchHeaderBoundary:contentOffset];
}

- (BOOL)shouldRestoreContentOffsetAfterTopRowRemovalAtIndexPath:(NSIndexPath *)indexPath
                                                     fromOffset:(CGPoint)contentOffset {
    if ([indexPath row] != 0) {
        return NO;
    }

    return [[self tableView] isSearchHeaderExposedAtContentOffset:contentOffset] ||
           [[self tableView] isContentOffsetAtHiddenSearchHeaderBoundary:contentOffset];
}

- (BOOL)shouldRestoreContentOffsetAfterMovingRowToTopFromOffset:(CGPoint)contentOffset {
    return ![self hasActiveSearch] && ([[self tableView] isSearchHeaderExposedAtContentOffset:contentOffset] ||
                                       [[self tableView] isContentOffsetAtHiddenSearchHeaderBoundary:contentOffset]);
}

- (UITableViewRowAnimation)rowAnimationForTopInsertionFromContentOffset:(CGPoint)contentOffset {
    if ([[self tableView] isSearchHeaderExposedAtContentOffset:contentOffset]) {
        return UITableViewRowAnimationFade;
    }

    return UITableViewRowAnimationTop;
}

- (nullable NSDictionary<NSString *, id> *)itemDictionaryAtIndexPath:(NSIndexPath *)indexPath {
    NSArray<NSDictionary<NSString *, id> *> *displayedItems = [self displayedItems];
    if ([indexPath row] >= [displayedItems count]) {
        return nil;
    }
    return displayedItems[[indexPath row]];
}

#pragma mark - Data Updates

- (void)setItems:(NSArray<NSDictionary<NSString *, id> *> *)items {
    [[self dataStore] setItems:items];
}

- (void)reloadDataWithItems:(NSArray<NSDictionary<NSString *, id> *> *)items {
    [self updateDataWithItems:items animatingTopInsertions:NO];
}

- (void)updateDataWithItems:(NSArray<NSDictionary<NSString *, id> *> *)items
     animatingTopInsertions:(BOOL)animatingTopInsertions {
    NSArray<NSDictionary<NSString *, id> *> *oldItems = [self items] ?: @[];
    NSArray<NSDictionary<NSString *, id> *> *newItems = items ?: @[];
    NSUInteger expectedOldRowCount = [self isGalleryModeEnabled] ? ([oldItems count] + 1) / 2 : [oldItems count];
    if ([oldItems isEqualToArray:newItems] && [[self tableView] numberOfRowsInSection:0] == expectedOldRowCount) {
        [self refreshVisibleItemDetails];
        return;
    }

    NSUInteger insertedCount = 0;
    NSUInteger removedCount = 0;
    BOOL canAnimateTopInsertion = ![self isGalleryModeEnabled] && ![self hasActiveSearch] && animatingTopInsertions &&
                                  [[self tableView] numberOfRowsInSection:0] == [oldItems count] &&
                                  [self canUpdateFromItems:oldItems
                                                   toItems:newItems
                                      withTopInsertedCount:&insertedCount
                                        bottomRemovedCount:&removedCount];

    if (!canAnimateTopInsertion) {
        [self setItems:newItems];
        [self reloadTableView];
        return;
    }

    NSArray<NSIndexPath *> *insertedIndexPaths = [self indexPathsFromRow:0 count:insertedCount];
    NSArray<NSIndexPath *> *removedIndexPaths = [self indexPathsFromRow:[oldItems count] - removedCount
                                                                  count:removedCount];
    UITableViewRowAnimation insertionAnimation =
        [self rowAnimationForTopInsertionFromContentOffset:[[self tableView] contentOffset]];

    [[self tableView]
        performBatchUpdates:^{
          [self setItems:newItems];
          if ([insertedIndexPaths count] > 0) {
              [[self tableView] insertRowsAtIndexPaths:insertedIndexPaths withRowAnimation:insertionAnimation];
          }
          if ([removedIndexPaths count] > 0) {
              [[self tableView] deleteRowsAtIndexPaths:removedIndexPaths withRowAnimation:UITableViewRowAnimationFade];
          }
        }
        completion:^(__unused BOOL finished) {
          [self refreshVisibleItemDetails];
          [self refreshSearchPlaceholder];
        }];
}

#pragma mark - Search

- (void)applySearchText:(NSString *)searchText {
    [[self dataStore] applySearchText:searchText];
    [self reloadTableView];
}

- (void)beginApplyingSearchCriteria:(MTSearchCriteria *)searchCriteria {
    [[self dataStore] beginApplyingSearchCriteria:searchCriteria];
    [self refreshSearchPlaceholder];
}

- (void)applySearchCriteria:(MTSearchCriteria *)searchCriteria
              filteredItems:(NSArray<NSDictionary<NSString *, id> *> *)filteredItems {
    [[self dataStore] applySearchCriteria:searchCriteria filteredItems:filteredItems];
    [self reloadTableView];
}

- (void)showSearchTokensWithFullListForCriteria:(MTSearchCriteria *)searchCriteria {
    MTSearchCriteria *criteria = searchCriteria ?: [MTSearchCriteria emptyCriteria];
    BOOL alreadyBrowsingFullList =
        [self isBrowsingSearchTokens] && [[self searchCriteria] isEqualToCriteria:criteria] &&
        [[self displayedItems] count] == [[self items] count] &&
        [[self tableView] numberOfRowsInSection:0] == [[self displayedItems] count];
    BOOL canFlipStateWithoutReload =
        !alreadyBrowsingFullList && ![self hasActiveSearch] &&
        [[self displayedItems] isEqualToArray:[self items] ?: @[]] &&
        [[self tableView] numberOfRowsInSection:0] == [[self displayedItems] count];

    [[self dataStore] showSearchTokensWithFullListForCriteria:criteria];
    if (alreadyBrowsingFullList || canFlipStateWithoutReload) {
        [self refreshSearchPlaceholder];
        return;
    }
    [self reloadTableView];
}

- (void)clearSearch {
    if (![self hasActiveSearch] && ![self isBrowsingSearchTokens] &&
        [[self displayedItems] isEqualToArray:[self items] ?: @[]] &&
        [[self tableView] numberOfRowsInSection:0] == [[self displayedItems] count]) {
        [[self dataStore] clearSearch];
        [self refreshSearchPlaceholder];
        return;
    }
    [[self dataStore] clearSearch];
    [self reloadTableView];
}

#pragma mark - Item Mutations

- (void)clearItems {
    NSArray<NSDictionary<NSString *, id> *> *oldItems = [self items] ?: @[];
    if ([oldItems count] == 0) {
        return;
    }

    [self setItems:@[]];
    [self reloadTableView];
}

- (void)upsertItemDictionaryAtTop:(NSDictionary<NSString *, id> *)dictionary limit:(NSUInteger)limit {
    [self upsertItemDictionaryAtTop:dictionary limit:limit animating:YES];
}

- (void)upsertItemDictionaryAtTop:(NSDictionary<NSString *, id> *)dictionary
                            limit:(NSUInteger)limit
                        animating:(BOOL)animating {
    if (!dictionary || [dictionary[kMTItemKeyContent] length] == 0) {
        return;
    }

    NSArray<NSDictionary<NSString *, id> *> *oldItems = [self items] ?: @[];
    NSMutableArray<NSDictionary<NSString *, id> *> *newItems = [oldItems mutableCopy];
    NSUInteger existingIndex = [[self dataStore] indexOfItemMatchingDictionary:dictionary inItems:newItems];
    NSUInteger normalizedLimit = [self normalizedLimit:limit];

    if (existingIndex != NSNotFound) {
        [newItems removeObjectAtIndex:existingIndex];
    }
    [newItems insertObject:dictionary atIndex:0];
    while ([newItems count] > normalizedLimit) {
        [newItems removeLastObject];
    }

    if ([self isGalleryModeEnabled]) {
        [self setItems:newItems];
        [self reloadTableView];
        return;
    }

    if ([oldItems isEqualToArray:newItems] &&
        [[self tableView] numberOfRowsInSection:0] == [[self displayedItems] count]) {
        [self refreshVisibleItemDetails];
        return;
    }

    if (!animating) {
        [self updateDataWithItems:newItems animatingTopInsertions:NO];
        return;
    }

    if ([self hasActiveSearch] || [[self tableView] numberOfRowsInSection:0] != [oldItems count]) {
        [self updateDataWithItems:newItems animatingTopInsertions:YES];
        return;
    }

    if (existingIndex == 0) {
        [self setItems:newItems];
        [[self tableView] reloadRowsAtIndexPaths:@[ [NSIndexPath indexPathForRow:0 inSection:0] ]
                                withRowAnimation:UITableViewRowAnimationNone];
        [self refreshVisibleItemDetails];
        [self refreshSearchPlaceholder];
        return;
    }

    if (existingIndex != NSNotFound && existingIndex < [oldItems count] && [newItems count] == [oldItems count]) {
        CGPoint contentOffsetBeforeMove = [[self tableView] contentOffset];
        BOOL restoresContentOffsetAfterMove =
            [self shouldRestoreContentOffsetAfterMovingRowToTopFromOffset:contentOffsetBeforeMove];

        [[self tableView]
            performBatchUpdates:^{
              [self setItems:newItems];
              [[self tableView] moveRowAtIndexPath:[NSIndexPath indexPathForRow:existingIndex inSection:0]
                                       toIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
            }
            completion:^(__unused BOOL finished) {
              if (restoresContentOffsetAfterMove) {
                  [[self tableView] setContentOffset:contentOffsetBeforeMove animated:NO];
              }
              [self refreshVisibleItemDetails];
              [self refreshSearchPlaceholder];
            }];
        return;
    }

    NSUInteger removedCount = [oldItems count] + 1 > [newItems count] ? [oldItems count] + 1 - [newItems count] : 0;
    NSMutableArray<NSIndexPath *> *removedIndexPaths = [[NSMutableArray alloc] initWithCapacity:removedCount];
    for (NSUInteger row = [oldItems count] - removedCount; row < [oldItems count]; row++) {
        [removedIndexPaths addObject:[NSIndexPath indexPathForRow:row inSection:0]];
    }

    CGPoint contentOffsetBeforeInsertion = [[self tableView] contentOffset];
    BOOL restoresContentOffsetAfterInsertion =
        [self shouldRestoreContentOffsetAfterTopInsertionFromOffset:contentOffsetBeforeInsertion];
    UITableViewRowAnimation insertionAnimation =
        [self rowAnimationForTopInsertionFromContentOffset:contentOffsetBeforeInsertion];

    [[self tableView]
        performBatchUpdates:^{
          [self setItems:newItems];
          [[self tableView] insertRowsAtIndexPaths:@[ [NSIndexPath indexPathForRow:0 inSection:0] ]
                                  withRowAnimation:insertionAnimation];
          if ([removedIndexPaths count] > 0) {
              [[self tableView] deleteRowsAtIndexPaths:removedIndexPaths withRowAnimation:UITableViewRowAnimationFade];
          }
        }
        completion:^(__unused BOOL finished) {
          if (restoresContentOffsetAfterInsertion) {
              [[self tableView] setContentOffset:contentOffsetBeforeInsertion animated:NO];
          }
          [self refreshVisibleItemDetails];
          [self refreshSearchPlaceholder];
        }];
}

- (void)removeItemDictionary:(NSDictionary<NSString *, id> *)dictionary {
    NSArray<NSDictionary<NSString *, id> *> *displayedItems = [self displayedItems] ?: @[];
    NSUInteger displayedIndex = [[self dataStore] indexOfItemMatchingDictionary:dictionary inItems:displayedItems];
    if (displayedIndex == NSNotFound) {
        return;
    }

    [self removeItemAtIndexPath:[NSIndexPath indexPathForRow:displayedIndex inSection:0] completion:nil];
}

- (void)removeItemAtIndexPath:(NSIndexPath *)indexPath completion:(void (^)(BOOL success))completion {
    NSDictionary<NSString *, id> *dictionary = [self itemDictionaryAtIndexPath:indexPath];
    if (!dictionary || [indexPath row] >= [[self displayedItems] count]) {
        if (completion) {
            completion(NO);
        }
        return;
    }

    if ([self isGalleryModeEnabled]) {
        [[self dataStore] removeDisplayedItemAtIndex:[indexPath row]];
        [self reloadTableView];
        if (completion) {
            completion(YES);
        }
        return;
    }

    CGPoint contentOffsetBeforeRemoval = [[self tableView] contentOffset];
    BOOL restoresContentOffsetAfterRemoval =
        [self shouldRestoreContentOffsetAfterTopRowRemovalAtIndexPath:indexPath fromOffset:contentOffsetBeforeRemoval];

    [[self tableView] prepareHiddenHeaderInsetsForRemovingRowAtIndexPath:indexPath];

    [[self tableView]
        performBatchUpdates:^{
          [[self dataStore] removeDisplayedItemAtIndex:[indexPath row]];
          [[self tableView] deleteRowsAtIndexPaths:@[ indexPath ] withRowAnimation:UITableViewRowAnimationAutomatic];
        }
        completion:^(__unused BOOL finished) {
          if (restoresContentOffsetAfterRemoval) {
              [[self tableView] setContentOffset:contentOffsetBeforeRemoval animated:NO];
          }
          [self refreshVisibleItemDetails];
          [self refreshSearchPlaceholder];
          if (completion) {
              completion(YES);
          }
        }];
}

- (void)updateNote:(NSString *)note
            forItem:(MTPasteboardItem *)item
         completion:(void (^)(void))completion {
    if (!item) {
        if (completion) {
            completion();
        }
        return;
    }

    NSDictionary<NSString *, id> *dictionary = [item dictionaryRepresentation];
    if ([self isGalleryModeEnabled]) {
        NSUInteger displayedIndex = NSNotFound;
        [[self dataStore] updateNote:note
              forItemMatchingDictionary:dictionary
                     displayedItemIndex:&displayedIndex];
        [self reloadTableView];
        if (completion) {
            completion();
        }
        return;
    }
    __block MTTableDataStoreDisplayedItemUpdate update = MTTableDataStoreDisplayedItemUpdateNotFound;
    __block NSUInteger displayedIndex = NSNotFound;

    [[self tableView]
        performBatchUpdates:^{
          update = [[self dataStore] updateNote:note
                         forItemMatchingDictionary:dictionary
                                displayedItemIndex:&displayedIndex];
          if (displayedIndex == NSNotFound) {
              return;
          }

          NSIndexPath *indexPath = [NSIndexPath indexPathForRow:displayedIndex inSection:0];
          if (update == MTTableDataStoreDisplayedItemUpdateRemove) {
              [[self tableView] deleteRowsAtIndexPaths:@[ indexPath ]
                                      withRowAnimation:UITableViewRowAnimationAutomatic];
          } else if (update == MTTableDataStoreDisplayedItemUpdateReload) {
              [[self tableView] reloadRowsAtIndexPaths:@[ indexPath ] withRowAnimation:UITableViewRowAnimationNone];
          }
        }
        completion:^(__unused BOOL finished) {
          [self refreshVisibleItemDetails];
          [self refreshSearchPlaceholder];
          if (completion) {
              completion();
          }
        }];
}

- (void)replaceContent:(NSString *)content
               forItem:(MTPasteboardItem *)item
            completion:(void (^)(void))completion {
    [self replaceContent:content
forItemMatchingDictionary:[item dictionaryRepresentation]
              completion:completion];
}

- (void)replaceContent:(NSString *)content
forItemMatchingDictionary:(NSDictionary<NSString *, id> *)dictionary
            completion:(void (^)(void))completion {
    if (!dictionary || [content length] == 0) {
        if (completion) {
            completion();
        }
        return;
    }
    if ([self isGalleryModeEnabled]) {
        NSUInteger displayedIndex = NSNotFound;
        [[self dataStore] replaceContent:content
              forItemMatchingDictionary:dictionary
                     displayedItemIndex:&displayedIndex];
        [self reloadTableView];
        if (completion) {
            completion();
        }
        return;
    }
    __block MTTableDataStoreDisplayedItemUpdate update = MTTableDataStoreDisplayedItemUpdateNotFound;
    __block NSUInteger displayedIndex = NSNotFound;

    [[self tableView]
        performBatchUpdates:^{
          update = [[self dataStore] replaceContent:content
                           forItemMatchingDictionary:dictionary
                                  displayedItemIndex:&displayedIndex];
          if (displayedIndex == NSNotFound) {
              return;
          }

          NSIndexPath *indexPath = [NSIndexPath indexPathForRow:displayedIndex inSection:0];
          if (update == MTTableDataStoreDisplayedItemUpdateRemove) {
              [[self tableView] deleteRowsAtIndexPaths:@[ indexPath ]
                                      withRowAnimation:UITableViewRowAnimationAutomatic];
          } else if (update == MTTableDataStoreDisplayedItemUpdateReload) {
              [[self tableView] reloadRowsAtIndexPaths:@[ indexPath ] withRowAnimation:UITableViewRowAnimationNone];
          }
        }
        completion:^(__unused BOOL finished) {
          [self refreshVisibleItemDetails];
          [self refreshSearchPlaceholder];
          if (completion) {
              completion();
          }
        }];
}

- (nullable MTTableViewCell *)visibleCellForItem:(MTPasteboardItem *)item {
    if (!item) {
        return nil;
    }

    NSUInteger displayedIndex = [[self dataStore] indexOfItemMatchingDictionary:[item dictionaryRepresentation]
                                                                        inItems:[self displayedItems]];
    if (displayedIndex == NSNotFound) {
        return nil;
    }
    if ([self isGalleryModeEnabled]) {
        NSIndexPath *rowIndexPath = [NSIndexPath indexPathForRow:displayedIndex / kMTGalleryColumnCount inSection:0];
        MTGalleryRowCell *rowCell = (MTGalleryRowCell *)[[self tableView] cellForRowAtIndexPath:rowIndexPath];
        return [rowCell itemCellAtColumn:displayedIndex % kMTGalleryColumnCount];
    }
    return (MTTableViewCell *)[[self tableView]
        cellForRowAtIndexPath:[NSIndexPath indexPathForRow:displayedIndex inSection:0]];
}

- (MTTableViewCell *)presentationCellForItem:(MTPasteboardItem *)item {
    return [self newCellForItem:item addsPreviewGesture:NO];
}

- (void)setCellPresentationHidden:(BOOL)hidden forItem:(MTPasteboardItem *)item {
    NSString *content = [item content];
    if ([content length] == 0) {
        return;
    }

    if (hidden) {
        [self setPresentationHiddenItemContent:content];
    } else if ([[self presentationHiddenItemContent] isEqualToString:content]) {
        [self setPresentationHiddenItemContent:nil];
    } else {
        return;
    }

    MTHistoryListView *tableView = [self tableView];
    NSString *hiddenContent = [self presentationHiddenItemContent];
    if ([self isGalleryModeEnabled]) {
        for (NSIndexPath *rowIndexPath in [tableView indexPathsForVisibleRows]) {
            MTGalleryRowCell *rowCell = (MTGalleryRowCell *)[tableView cellForRowAtIndexPath:rowIndexPath];
            for (MTTableViewCell *itemCell in [rowCell itemCells]) {
                NSDictionary *dictionary = objc_getAssociatedObject(itemCell, kMTGalleryItemDictionaryKey);
                BOOL hidesCell = [hiddenContent length] > 0 &&
                                 [dictionary[kMTItemKeyContent] isEqualToString:hiddenContent];
                [itemCell setHidden:hidesCell];
            }
        }
        return;
    }
    for (NSIndexPath *indexPath in [tableView indexPathsForVisibleRows]) {
        NSDictionary<NSString *, id> *dictionary = [self itemDictionaryAtIndexPath:indexPath];
        BOOL hidesCell =
            [hiddenContent length] > 0 && [dictionary[kMTItemKeyContent] isEqualToString:hiddenContent];
        [[tableView cellForRowAtIndexPath:indexPath] setHidden:hidesCell];
    }
}

- (nullable MTTableViewCell *)scrollItemToVisible:(MTPasteboardItem *)item {
    if (!item) {
        return nil;
    }

    NSUInteger displayedIndex = [[self dataStore] indexOfItemMatchingDictionary:[item dictionaryRepresentation]
                                                                        inItems:[self displayedItems]];
    if (displayedIndex == NSNotFound) {
        return nil;
    }

    NSUInteger tableRow = [self isGalleryModeEnabled] ? displayedIndex / kMTGalleryColumnCount : displayedIndex;
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:tableRow inSection:0];
    MTHistoryListView *tableView = [self tableView];
    [tableView layoutIfNeeded];
    MTTableViewCell *visibleCell = [self visibleCellForItem:item];
    if (visibleCell) {
        return visibleCell;
    }

    [tableView scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
    [tableView layoutIfNeeded];
    return [self visibleCellForItem:item];
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (tableView != [self tableView]) {
        return 0;
    }
    NSUInteger itemCount = [[self displayedItems] count];
    return [self isGalleryModeEnabled] ? (itemCount + kMTGalleryColumnCount - 1) / kMTGalleryColumnCount
                                       : itemCount;
}

- (MTTableViewCell *)newCellForItem:(MTPasteboardItem *)item addsPreviewGesture:(BOOL)addsPreviewGesture {
    MTTableViewCellContent *content = [[self cellContentProvider] cellContentForItem:item
                                                                        previewLineCount:[self previewLineCount]
                                                                         itemDetailsMode:[self itemDetailsMode]
                                                                              searchText:[self searchText]];

    MTTableViewCell *cell =
        [[MTTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                           content:content
                                   reuseIdentifier:[MTTableViewCell reuseIdentifierForContent:content]];
    [self loadThumbnailForItem:item intoCell:cell targetSize:[MTTableViewCell contentImageThumbnailSize]];

    if (addsPreviewGesture) {
        UILongPressGestureRecognizer *gesture =
            [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                          action:@selector(handleLongPressGestureRecognizer:)];
        [cell addGestureRecognizer:gesture];
    }
    return cell;
}

- (MTTableViewCell *)newGalleryCellForItem:(MTPasteboardItem *)item
                                     dictionary:(NSDictionary<NSString *, id> *)dictionary {
    MTTableViewCellContent *content = [[self cellContentProvider] cellContentForItem:item
                                                                        previewLineCount:3
                                                                         itemDetailsMode:[self itemDetailsMode]
                                                                              searchText:[self searchText]];
    MTTableViewCell *cell = [[MTTableViewCell alloc]
        initWithGalleryContent:content
               reuseIdentifier:[MTTableViewCell galleryReuseIdentifierForContent:content]];
    objc_setAssociatedObject(cell, kMTGalleryItemDictionaryKey, dictionary, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UITapGestureRecognizer *tapGesture =
        [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleGalleryTapGestureRecognizer:)];
    [cell addGestureRecognizer:tapGesture];
    UILongPressGestureRecognizer *longPressGesture =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPressGestureRecognizer:)];
    [tapGesture requireGestureRecognizerToFail:longPressGesture];
    [cell addGestureRecognizer:longPressGesture];
    [self loadThumbnailForItem:item
                      intoCell:cell
                    targetSize:[MTTableViewCell galleryContentImageThumbnailSize]];
    return cell;
}

- (void)loadThumbnailForItem:(MTPasteboardItem *)item
                    intoCell:(MTTableViewCell *)cell
                  targetSize:(CGSize)targetSize {
    NSString *imageName = [[item imageName] copy];
    if ([imageName length] == 0) {
        return;
    }

    __weak MTTableViewCell *weakCell = cell;
    [[self cellContentProvider] loadThumbnailForItem:item
                                          targetSize:targetSize
                                          completion:^(UIImage *_Nullable image) {
                                            [weakCell setContentImage:image forImageName:imageName];
                                          }];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self isGalleryModeEnabled]) {
        static NSString *const reuseIdentifier = @"MTGalleryRowCell";
        MTGalleryRowCell *rowCell = [tableView dequeueReusableCellWithIdentifier:reuseIdentifier];
        if (!rowCell) {
            rowCell = [[MTGalleryRowCell alloc] initWithReuseIdentifier:reuseIdentifier];
        }
        NSMutableArray<MTGallerySwipeView *> *itemSwipeViews = [[NSMutableArray alloc] initWithCapacity:2];
        NSUInteger firstItemIndex = [indexPath row] * kMTGalleryColumnCount;
        for (NSUInteger column = 0; column < kMTGalleryColumnCount; column++) {
            NSUInteger itemIndex = firstItemIndex + column;
            if (itemIndex >= [[self displayedItems] count]) {
                break;
            }
            NSDictionary<NSString *, id> *dictionary = [self displayedItems][itemIndex];
            MTPasteboardItem *item = [MTPasteboardItem itemFromDictionary:dictionary];
            MTTableViewCell *itemCell = [self newGalleryCellForItem:item dictionary:dictionary];
            [itemCell setHidden:[[self presentationHiddenItemContent] isEqualToString:[item content]]];
            NSIndexPath *itemIndexPath = [NSIndexPath indexPathForRow:itemIndex inSection:0];
            NSArray<MTGalleryAction *> *actions = [self leadingActionsForItem:item
                                                                        dictionary:dictionary
                                                                         indexPath:itemIndexPath];
            NSArray<MTGalleryAction *> *trailingActions =
                @[ [self deleteActionForItem:item indexPath:itemIndexPath] ];
            MTGallerySwipeView *swipeView = [[MTGallerySwipeView alloc] initWithItemCell:itemCell
                                                                                   leadingActions:actions
                                                                                  trailingActions:trailingActions];
            __weak typeof(self) weakSelf = self;
            [swipeView setWillOpenHandler:^(MTGallerySwipeView *openingSwipeView) {
              MTGallerySwipeView *openSwipeView = [weakSelf openGallerySwipeView];
              if (openSwipeView && openSwipeView != openingSwipeView) {
                  [openSwipeView setOpen:NO animated:YES];
              }
              [weakSelf setOpenGallerySwipeView:openingSwipeView];
            }];
            [itemSwipeViews addObject:swipeView];
        }
        [rowCell setGalleryItemSwipeViews:itemSwipeViews];
        return rowCell;
    }
    NSDictionary<NSString *, id> *dictionary = [self itemDictionaryAtIndexPath:indexPath];
    MTPasteboardItem *item = [MTPasteboardItem itemFromDictionary:dictionary];
    MTTableViewCellContent *content = [[self cellContentProvider] cellContentForItem:item
                                                                        previewLineCount:[self previewLineCount]
                                                                         itemDetailsMode:[self itemDetailsMode]
                                                                              searchText:[self searchText]];
    NSString *reuseIdentifier = [MTTableViewCell reuseIdentifierForContent:content];
    MTTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseIdentifier];
    if (cell) {
        [cell applyContent:content];
    } else {
        cell = [[MTTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                                  content:content
                                          reuseIdentifier:reuseIdentifier];
        UILongPressGestureRecognizer *gesture =
            [[UILongPressGestureRecognizer alloc] initWithTarget:self
                                                          action:@selector(handleLongPressGestureRecognizer:)];
        [cell addGestureRecognizer:gesture];
    }
    [self loadThumbnailForItem:item intoCell:cell targetSize:[MTTableViewCell contentImageThumbnailSize]];
    [cell setHidden:[[self presentationHiddenItemContent] isEqualToString:[item content]]];
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView
      willDisplayCell:(UITableViewCell *)cell
    forRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if ([self isGalleryModeEnabled]) {
        return;
    }
    NSDictionary<NSString *, id> *dictionary = [self itemDictionaryAtIndexPath:indexPath];
    NSString *hiddenContent = [self presentationHiddenItemContent];
    BOOL hidesCell = [hiddenContent length] > 0 && [dictionary[kMTItemKeyContent] isEqualToString:hiddenContent];
    [cell setHidden:hidesCell];
}

- (void)tableView:(UITableView *)tableView
    didEndDisplayingCell:(UITableViewCell *)cell
       forRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    [cell setHidden:NO];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self isGalleryModeEnabled]) {
        return;
    }
    [[tableView cellForRowAtIndexPath:indexPath] setSelected:NO animated:YES];

    MTPasteboardItem *item = [MTPasteboardItem itemFromDictionary:[self itemDictionaryAtIndexPath:indexPath]];
    [self activateItem:item];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)indexPath;
    if (![self isGalleryModeEnabled]) {
        return [tableView rowHeight];
    }
    return MAX(kMTGalleryMinimumRowHeight, floor(CGRectGetHeight([tableView bounds]) / 3.0));
}

- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView
                     withVelocity:(CGPoint)velocity
              targetContentOffset:(inout CGPoint *)targetContentOffset {
    (void)velocity;
    if (scrollView != [self tableView] || [self hasActiveSearch]) {
        return;
    }

    [[self tableView] adjustTargetContentOffsetForSearchBarSnap:targetContentOffset];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self isGalleryModeEnabled]) {
        return nil;
    }
    NSMutableArray<UIContextualAction *> *actions = [[NSMutableArray alloc] init];
    NSDictionary<NSString *, id> *dictionary = [self itemDictionaryAtIndexPath:indexPath];
    MTPasteboardItem *item = [MTPasteboardItem itemFromDictionary:dictionary];
    for (MTGalleryAction *galleryAction in [self leadingActionsForItem:item
                                                                   dictionary:dictionary
                                                                    indexPath:indexPath]) {
        [actions addObject:[self contextualActionForGalleryAction:galleryAction]];
    }

    return [UISwipeActionsConfiguration configurationWithActions:actions];
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView
    trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self isGalleryModeEnabled]) {
        return nil;
    }
    MTPasteboardItem *item = [MTPasteboardItem itemFromDictionary:[self itemDictionaryAtIndexPath:indexPath]];

    NSMutableArray<UIContextualAction *> *actions = [[NSMutableArray alloc] init];
    [actions addObject:[self contextualActionForGalleryAction:[self deleteActionForItem:item indexPath:indexPath]]];

    UIContextualAction *snapperAction = [self snapperActionForItem:item];
    if (snapperAction) {
        [actions addObject:snapperAction];
    }
    return [UISwipeActionsConfiguration configurationWithActions:actions];
}

#pragma mark - Swipe Actions

- (nullable UIContextualAction *)snapperActionForItem:(MTPasteboardItem *)item {
    NSString *text = [[item content] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!item || ([[item imageName] length] == 0 && [text length] == 0) || ![MTSnapperIntegration isAvailable]) {
        return nil;
    }

    UIContextualAction *snapperAction = [UIContextualAction
        contextualActionWithStyle:UIContextualActionStyleNormal
                            title:@""
                          handler:^(__unused UIContextualAction *action, __unused __kindof UIView *sourceView,
                                    void (^completionHandler)(BOOL)) {
                            completionHandler([MTSnapperIntegration floatPasteboardItem:item]);
                          }];
    [snapperAction setImage:[UIImage systemImageNamed:@"pin.fill"]];
    [snapperAction setBackgroundColor:[UIColor systemGreenColor]];
    return snapperAction;
}

- (NSArray<MTGalleryAction *> *)leadingActionsForItem:(MTPasteboardItem *)item
                                               dictionary:(NSDictionary<NSString *, id> *)dictionary
                                                indexPath:(NSIndexPath *)indexPath {
    if (!item || !dictionary || !indexPath) {
        return @[];
    }

    NSMutableArray<MTGalleryAction *> *actions = [[NSMutableArray alloc] init];
    NSBundle *bundle = [MTPasteboardManager localizationBundle];
    __weak typeof(self) weakSelf = self;

    NSString *sourceHistoryKey = [self historyKey];
    BOOL sourceIsFavorites = [sourceHistoryKey isEqualToString:kMTHistoryKeyFavorites];
    NSString *destinationHistoryKey = sourceIsFavorites ? kMTHistoryKeyHistory : kMTHistoryKeyFavorites;
    NSString *imageName = sourceIsFavorites ? @"heart.slash.fill" : @"heart.fill";
    MTGalleryAction *moveAction = [[MTGalleryAction alloc] init];
    [moveAction setStyle:UIContextualActionStyleDestructive];
    [moveAction setImage:[UIImage systemImageNamed:imageName]];
    [moveAction setBackgroundColor:[UIColor systemPinkColor]];
    [moveAction setAccessibilityLabel:[bundle localizedStringForKey:(sourceIsFavorites ? @"History" : @"Favorites")
                                                               value:nil
                                                               table:@"Tweak"]];
    [moveAction setHandler:^(__unused UIView *sourceView, void (^completionHandler)(BOOL)) {
      __strong typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf) {
          completionHandler(NO);
          return;
      }
      [[strongSelf actionHandler]
                       moveItem:item
               sourceHistoryKey:sourceHistoryKey
          destinationHistoryKey:destinationHistoryKey
                     completion:^(BOOL success) {
                       if (!success) {
                           completionHandler(NO);
                           return;
                       }
                       [[strongSelf delegate] historyListViewController:strongSelf
                                                didMoveItemDictionary:dictionary
                                                   fromHistoryWithKey:sourceHistoryKey
                                                     toHistoryWithKey:destinationHistoryKey];
                       [strongSelf removeItemAtIndexPath:indexPath
                                            completion:^(BOOL removed) {
                                              if (removed) {
                                                  [[strongSelf delegate]
                                                      historyListViewControllerDidChangeContentState:strongSelf];
                                              }
                                              completionHandler(removed);
                                            }];
                     }];
    }];
    [actions addObject:moveAction];

    MTGalleryAction *noteAction = [[MTGalleryAction alloc] init];
    [noteAction setStyle:UIContextualActionStyleNormal];
    [noteAction setImage:[UIImage systemImageNamed:@"note.text"]];
    [noteAction setBackgroundColor:[UIColor systemOrangeColor]];
    [noteAction setAccessibilityLabel:[bundle localizedStringForKey:@"Note" value:nil table:@"Tweak"]];
    [noteAction setHandler:^(UIView *sourceView, void (^completionHandler)(BOOL)) {
      __strong typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf) {
          completionHandler(NO);
          return;
      }
      MTTableViewCell *sourceCell = [sourceView isKindOfClass:[MTTableViewCell class]]
                                                ? (MTTableViewCell *)sourceView
                                                : [strongSelf visibleCellForItem:item];
      MTTableViewCell *presentationCell = [strongSelf newCellForItem:item addsPreviewGesture:NO];
      completionHandler(YES);
      dispatch_async(dispatch_get_main_queue(), ^{
        [[strongSelf delegate] historyListViewController:strongSelf
                             didRequestEditNoteForItem:item
                                      presentationCell:presentationCell
                                            sourceCell:sourceCell];
      });
    }];
    [actions addObject:noteAction];

    if ([self automaticallyPaste] || [[item imageName] length] > 0) {
        BOOL savesImage = [[item imageName] length] > 0;
        MTGalleryAction *saveAction = [[MTGalleryAction alloc] init];
        [saveAction setStyle:UIContextualActionStyleNormal];
        [saveAction setImage:[UIImage systemImageNamed:(savesImage ? @"square.and.arrow.down.fill" : @"doc.on.doc.fill")]];
        [saveAction setBackgroundColor:[UIColor systemBlueColor]];
        [saveAction setAccessibilityLabel:
                        [bundle localizedStringForKey:(savesImage ? @"Save to Photos" : @"Copy")
                                               value:nil
                                               table:@"Tweak"]];
        [saveAction setHandler:^(__unused UIView *sourceView, void (^completionHandler)(BOOL)) {
          __strong typeof(weakSelf) strongSelf = weakSelf;
          if (!strongSelf) {
              completionHandler(NO);
          } else if (savesImage) {
              [[strongSelf actionHandler] saveImageForItem:item completion:completionHandler];
          } else {
              [[strongSelf actionHandler] copyItem:item completion:completionHandler];
          }
        }];
        [actions addObject:saveAction];
    }

    if ([item hasLink]) {
        MTGalleryAction *linkAction = [[MTGalleryAction alloc] init];
        [linkAction setStyle:UIContextualActionStyleNormal];
        [linkAction setImage:[UIImage systemImageNamed:@"safari"]];
        [linkAction setBackgroundColor:[UIColor systemGreenColor]];
        [linkAction setAccessibilityLabel:[bundle localizedStringForKey:@"Open" value:nil table:@"Tweak"]];
        [linkAction setHandler:^(__unused UIView *sourceView, void (^completionHandler)(BOOL)) {
          __strong typeof(weakSelf) strongSelf = weakSelf;
          if (!strongSelf) {
              completionHandler(NO);
              return;
          }
          [[strongSelf actionHandler] openLinkForItem:item completion:completionHandler];
        }];
        [actions addObject:linkAction];
    }

    MTGalleryAction *systemAction = [[MTGalleryAction alloc] init];
    [systemAction setStyle:UIContextualActionStyleNormal];
    [systemAction setImage:[UIImage systemImageNamed:@"switch.2"]];
    [systemAction setBackgroundColor:[UIColor systemIndigoColor]];
    [systemAction setAccessibilityLabel:[bundle localizedStringForKey:@"System Actions"
                                                               value:@"System Actions"
                                                               table:@"Tweak"]];
    [systemAction setHandler:^(UIView *sourceView, void (^completionHandler)(BOOL)) {
      __strong typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf) {
          completionHandler(NO);
          return;
      }
      completionHandler(YES);
      [strongSelf presentSystemActionSheetFromView:sourceView];
    }];
    [actions addObject:systemAction];
    return actions;
}

#pragma mark - System Actions

// 左滑「系统动作」：弹出系统动作选择面板（与键盘系统动作同一目录），
// 选中后经 MetisCore 的执行器在 SpringBoard 主线程执行。
- (void)presentSystemActionSheetFromView:(UIView *)sourceView {
    if (!NSThread.isMainThread) {
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
          [weakSelf presentSystemActionSheetFromView:sourceView];
        });
        return;
    }

    BOOL pixPinInstalled = MTCaptureInstalledAtPath(MT_ROOT_PATH_NS(MTCaptureDylibPath));
    NSArray<NSDictionary *> *catalog = MTVisibleSystemActionCatalog(pixPinInstalled);
    if ([catalog count] == 0) {
        return;
    }

    NSBundle *keyboardBundle = [NSBundle bundleWithPath:bundlePath];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil
                                                                 message:nil
                                                          preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSDictionary *definition in catalog) {
        NSString *action = definition[@"id"];
        NSString *title = [keyboardBundle localizedStringForKey:definition[@"title"] value:action table:nil];
        __weak typeof(self) weakSelf = self;
        UIAlertAction *alertAction = [UIAlertAction actionWithTitle:title
                                                             style:UIAlertActionStyleDefault
                                                           handler:^(__unused UIAlertAction *selectedAction) {
                                                             [weakSelf performClipboardSystemAction:action];
                                                           }];
        [sheet addAction:alertAction];
    }

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:[keyboardBundle localizedStringForKey:@"CANCEL"
                                                                                                value:@"Cancel"
                                                                                                table:nil]
                                                              style:UIAlertActionStyleCancel
                                                            handler:nil];
    [sheet addAction:cancelAction];

    UIPopoverPresentationController *popoverController = [sheet popoverPresentationController];
    if (popoverController) {
        [popoverController setSourceView:sourceView ?: [self view]];
        [popoverController setSourceRect:sourceView ? [sourceView bounds] : CGRectZero];
    }
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)performClipboardSystemAction:(NSString *)action {
    if (!NSThread.isMainThread || ![action isKindOfClass:[NSString class]]) {
        return;
    }
    NSDictionary *definition = MTSystemActionDefinition(action);
    if (!definition) {
        return;
    }
    if (MTSystemActionIsRecording(action)) {
        MTPerformSystemRecordingAction(action, ^(MTSystemOpenResult result) {
          NSLog(@"[MetisClipboard][SystemAction] recording id=%@ result=%llu", action, (unsigned long long)result);
        });
        return;
    }
    if ([definition[@"destructive"] boolValue]) {
        // 破坏性动作（注销/安全模式/关机/重启）走执行器内置的确认弹窗。
        NSProgress *operation = [NSProgress discreteProgressWithTotalUnitCount:1];
        MTConfirmSystemExitAction(action, operation);
        return;
    }
    MTSystemOpenResult result = MTPerformSystemAction(action);
    NSLog(@"[MetisClipboard][SystemAction] id=%@ result=%llu", action, (unsigned long long)result);
}

- (MTGalleryAction *)deleteActionForItem:(MTPasteboardItem *)item indexPath:(NSIndexPath *)indexPath {
    MTGalleryAction *deleteAction = [[MTGalleryAction alloc] init];
    [deleteAction setStyle:UIContextualActionStyleDestructive];
    [deleteAction setImage:[UIImage systemImageNamed:@"trash.fill"]];
    [deleteAction setBackgroundColor:[UIColor systemRedColor]];
    NSBundle *bundle = [MTPasteboardManager localizationBundle];
    [deleteAction setAccessibilityLabel:[bundle localizedStringForKey:@"Delete" value:nil table:@"Tweak"]];

    __weak typeof(self) weakSelf = self;
    [deleteAction setHandler:^(__unused UIView *sourceView, void (^completionHandler)(BOOL)) {
      __strong typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf) {
          completionHandler(NO);
          return;
      }
      [[strongSelf actionHandler]
          deleteItem:item
          historyKey:[strongSelf historyKey]
          completion:^(BOOL success) {
            if (!success) {
                completionHandler(NO);
                return;
            }
            [strongSelf removeItemAtIndexPath:indexPath
                                  completion:^(BOOL removed) {
                                    if (removed) {
                                        [[strongSelf delegate]
                                            historyListViewControllerDidChangeContentState:strongSelf];
                                    }
                                    completionHandler(removed);
                                  }];
          }];
    }];
    return deleteAction;
}

- (UIContextualAction *)contextualActionForGalleryAction:(MTGalleryAction *)galleryAction {
    UIContextualAction *contextualAction = [UIContextualAction
        contextualActionWithStyle:[galleryAction style]
                            title:@""
                          handler:^(__unused UIContextualAction *action, __kindof UIView *sourceView,
                                    void (^completionHandler)(BOOL)) {
                            [galleryAction handler](sourceView, completionHandler);
                          }];
    [contextualAction setImage:[galleryAction image]];
    [contextualAction setBackgroundColor:[galleryAction backgroundColor]];
    return contextualAction;
}

#pragma mark - Gestures

- (void)activateItem:(MTPasteboardItem *)item {
    if (!item) {
        return;
    }
    [[self actionHandler] activateItem:item
                            historyKey:[self historyKey]
                            completion:^(BOOL success) {
                              if (success) {
                                  if ([self automaticallyPaste]) {
                                      [[self delegate] historyListViewControllerDidRequestHideAfterDirectPaste:self];
                                  } else {
                                      [[self delegate] historyListViewControllerDidRequestHide:self];
                                  }
                              }
                            }];
}

- (void)handleGalleryTapGestureRecognizer:(UITapGestureRecognizer *)recognizer {
    if ([recognizer state] != UIGestureRecognizerStateEnded) {
        return;
    }
    MTGallerySwipeView *openSwipeView = [self openGallerySwipeView];
    if ([openSwipeView isOpen]) {
        [openSwipeView setOpen:NO animated:YES];
        [self setOpenGallerySwipeView:nil];
        return;
    }
    NSDictionary *dictionary = objc_getAssociatedObject([recognizer view], kMTGalleryItemDictionaryKey);
    [self activateItem:[MTPasteboardItem itemFromDictionary:dictionary]];
}

- (void)handleLongPressGestureRecognizer:(UILongPressGestureRecognizer *)recognizer {
    if ([recognizer state] != UIGestureRecognizerStateBegan) {
        return;
    }

    MTGallerySwipeView *openSwipeView = [self openGallerySwipeView];
    if ([openSwipeView isOpen]) {
        [openSwipeView setOpen:NO animated:YES];
        [self setOpenGallerySwipeView:nil];
        return;
    }

    NSDictionary *dictionary = objc_getAssociatedObject([recognizer view], kMTGalleryItemDictionaryKey);
    if (!dictionary) {
        NSIndexPath *indexPath = [[self tableView] indexPathForCell:(UITableViewCell *)[recognizer view]];
        dictionary = [self itemDictionaryAtIndexPath:indexPath];
    }
    MTPasteboardItem *item = [MTPasteboardItem itemFromDictionary:dictionary];
    if (item) {
        [[self delegate] historyListViewController:self didRequestPreviewForItem:item];
    }
}

@end
