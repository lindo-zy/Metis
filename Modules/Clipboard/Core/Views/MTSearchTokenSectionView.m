//
//  MTSearchTokenSectionView.m
//  Mt
//

#import "MTSearchTokenSectionView.h"

#import "MTSearchTokenCollectionView.h"

static CGFloat const kMTSearchTokenSectionHorizontalInset = 24;static CGFloat const kMTSearchTokenSectionTitleHeight = 0;
static CGFloat const kMTSearchTokenSectionTitleBottomSpacing = 0;
static CGFloat const kMTSearchTokenSectionItemWidth = 108;
static CGFloat const kMTSearchTokenSectionItemHeight = 38;
static CGFloat const kMTSearchTokenSectionItemSpacing = 8;
static NSUInteger const kMTSearchTokenSectionDefaultRowCount = 1;

@interface MTSearchTokenSectionView ()
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong, readwrite) MTSearchTokenCollectionView *collectionView;
@end

@implementation MTSearchTokenSectionView

- (instancetype)initWithTitle:(NSString *)title {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _numberOfRows = kMTSearchTokenSectionDefaultRowCount;
        _horizontalScrollingLayout = YES;
        [self setBackgroundColor:[UIColor clearColor]];

        _titleLabel = [[UILabel alloc] init];
        [_titleLabel setText:title];
        [_titleLabel setTextColor:[UIColor secondaryLabelColor]];
        [_titleLabel setFont:[UIFont systemFontOfSize:13 weight:UIFontWeightSemibold]];
        [_titleLabel setHidden:YES];
        [self addSubview:_titleLabel];

        _collectionView = [[MTSearchTokenCollectionView alloc]
                  initWithItemSize:CGSizeMake(kMTSearchTokenSectionItemWidth, kMTSearchTokenSectionItemHeight)
                       itemSpacing:kMTSearchTokenSectionItemSpacing
            horizontalContentInset:kMTSearchTokenSectionHorizontalInset];
        [self addSubview:_collectionView];
    }
    return self;
}

+ (NSUInteger)normalizedNumberOfRows:(NSUInteger)numberOfRows {
    return MAX(numberOfRows, 1);
}

+ (CGFloat)collectionHeightForNumberOfRows:(NSUInteger)numberOfRows {
    NSUInteger normalizedNumberOfRows = [self normalizedNumberOfRows:numberOfRows];
    return normalizedNumberOfRows * kMTSearchTokenSectionItemHeight +
           (normalizedNumberOfRows - 1) * kMTSearchTokenSectionItemSpacing;
}

+ (CGFloat)preferredHeight {
    return [self preferredHeightForNumberOfRows:kMTSearchTokenSectionDefaultRowCount];
}

+ (CGFloat)preferredHeightForNumberOfRows:(NSUInteger)numberOfRows {
    return kMTSearchTokenSectionTitleHeight + kMTSearchTokenSectionTitleBottomSpacing +
           [self collectionHeightForNumberOfRows:numberOfRows];
}

+ (NSUInteger)numberOfColumnsForWidth:(CGFloat)width {
    if (width <= 0) {
        return 2;
    }

    CGFloat availableWidth = MAX(width - kMTSearchTokenSectionHorizontalInset * 2, 0);
    CGFloat columnWidth = kMTSearchTokenSectionItemWidth + kMTSearchTokenSectionItemSpacing;
    return MAX((NSUInteger)floor((availableWidth + kMTSearchTokenSectionItemSpacing) / columnWidth), 1);
}

+ (NSUInteger)numberOfRowsForItemCount:(NSUInteger)itemCount
                                 width:(CGFloat)width
             horizontalScrollingLayout:(BOOL)horizontalScrollingLayout {
    if (itemCount == 0) {
        return 0;
    }
    if (horizontalScrollingLayout) {
        return kMTSearchTokenSectionDefaultRowCount;
    }

    NSUInteger columns = [self numberOfColumnsForWidth:width];
    return (itemCount + columns - 1) / columns;
}

+ (CGFloat)preferredHeightForItemCount:(NSUInteger)itemCount
                                 width:(CGFloat)width
             horizontalScrollingLayout:(BOOL)horizontalScrollingLayout {
    NSUInteger numberOfRows = [self numberOfRowsForItemCount:itemCount
                                                       width:width
                                   horizontalScrollingLayout:horizontalScrollingLayout];
    if (numberOfRows == 0) {
        return 0;
    }

    return [self preferredHeightForNumberOfRows:numberOfRows];
}

- (CGFloat)preferredHeight {
    return [[self class] preferredHeightForNumberOfRows:[self numberOfRows]];
}

- (void)setNumberOfRows:(NSUInteger)numberOfRows {
    numberOfRows = [[self class] normalizedNumberOfRows:numberOfRows];
    if (_numberOfRows == numberOfRows) {
        return;
    }

    _numberOfRows = numberOfRows;
    [[self collectionView] setNeedsLayout];
    [[[self collectionView] collectionViewLayout] invalidateLayout];
    [self setNeedsLayout];
}

- (void)setHorizontalScrollingLayout:(BOOL)horizontalScrollingLayout {
    if (_horizontalScrollingLayout == horizontalScrollingLayout) {
        return;
    }

    _horizontalScrollingLayout = horizontalScrollingLayout;
    [[self collectionView] setHorizontalScrollingLayout:horizontalScrollingLayout];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGFloat width = CGRectGetWidth([self bounds]);
    CGFloat contentWidth = MAX(width - kMTSearchTokenSectionHorizontalInset * 2, 0);
    CGFloat collectionHeight = [[self class] collectionHeightForNumberOfRows:[self numberOfRows]];
    [[self titleLabel] setFrame:CGRectMake(kMTSearchTokenSectionHorizontalInset, 0, contentWidth,
                                           kMTSearchTokenSectionTitleHeight)];
    [[self collectionView]
        setFrame:CGRectMake(0, kMTSearchTokenSectionTitleHeight + kMTSearchTokenSectionTitleBottomSpacing,
                            width, collectionHeight)];
}

@end
