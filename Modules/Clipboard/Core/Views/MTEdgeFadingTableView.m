//
//  MTEdgeFadingTableView.m
//  Mt
//

#import "MTEdgeFadingTableView.h"

#import "MTEdgeFadeMaskController.h"

@interface MTEdgeFadingTableView ()
@property(nonatomic, strong) MTEdgeFadeMaskController *edgeFadeMaskController;
@end

@implementation MTEdgeFadingTableView

- (instancetype)init {
    self = [super init];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame style:(UITableViewStyle)style {
    self = [super initWithFrame:frame style:style];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    if ([self edgeFadeMaskController]) {
        return;
    }
    [self setEdgeFadeMaskController:[[MTEdgeFadeMaskController alloc] initWithScrollView:self]];
}

- (CGFloat)edgeFadeWidth {
    return [[self edgeFadeMaskController] fadeWidth];
}

- (void)setEdgeFadeWidth:(CGFloat)edgeFadeWidth {
    [[self edgeFadeMaskController] setFadeWidth:edgeFadeWidth];
}

- (CGFloat)edgeFadeLeadingScrollOffset {
    return [[self edgeFadeMaskController] leadingFadeScrollOffset];
}

- (void)setEdgeFadeLeadingScrollOffset:(CGFloat)edgeFadeLeadingScrollOffset {
    [[self edgeFadeMaskController] setLeadingFadeScrollOffset:edgeFadeLeadingScrollOffset];
}

- (MTEdgeFadeAxis)edgeFadeAxis {
    return [[self edgeFadeMaskController] axis];
}

- (void)setEdgeFadeAxis:(MTEdgeFadeAxis)edgeFadeAxis {
    [[self edgeFadeMaskController] setAxis:edgeFadeAxis];
}

- (BOOL)isEdgeFadeEnabled {
    return [[self edgeFadeMaskController] isEnabled];
}

- (void)setEdgeFadeEnabled:(BOOL)edgeFadeEnabled {
    [[self edgeFadeMaskController] setEnabled:edgeFadeEnabled];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self updateEdgeFadeMask];
}

- (void)setContentOffset:(CGPoint)contentOffset {
    [super setContentOffset:contentOffset];
    [self updateEdgeFadeMask];
}

- (void)setContentSize:(CGSize)contentSize {
    [super setContentSize:contentSize];
    [self updateEdgeFadeMask];
}

- (void)setContentInset:(UIEdgeInsets)contentInset {
    [super setContentInset:contentInset];
    [self updateEdgeFadeMask];
}

- (void)updateEdgeFadeMask {
    [[self edgeFadeMaskController] updateMask];
}

@end
