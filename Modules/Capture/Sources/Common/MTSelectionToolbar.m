#import "MTSelectionToolbar.h"
#import "MTCaptureLog.h"
#import <math.h>

@interface MTSelectionToolbar ()
@property (nonatomic, copy, readwrite) NSArray<UIButton *> *buttons;
@property (nonatomic, assign, readwrite) MTSelectionToolbarArrangement arrangement;
@property (nonatomic, copy) NSArray<UIView *> *separators;
@property (nonatomic, assign) CGFloat buttonScale;
@property (nonatomic, assign) CGFloat rowHeight;
@property (nonatomic, assign) NSUInteger layoutColumns;
// 滑动排布才存在：承载全部按钮的横向滚动容器，宽度随可用空间夹断。
@property (nonatomic, strong) UIScrollView *scroller;
@end

@implementation MTSelectionToolbar

- (instancetype)initWithIdentifiers:(NSArray<NSString *> *)identifiers
                              style:(MTSelectionButtonStyle)style
                      iconPointSize:(CGFloat)iconPointSize {
    return [self initWithIdentifiers:identifiers style:style iconPointSize:iconPointSize
                         arrangement:MTSelectionToolbarArrangementRows];
}

- (instancetype)initWithIdentifiers:(NSArray<NSString *> *)identifiers
                              style:(MTSelectionButtonStyle)style
                      iconPointSize:(CGFloat)iconPointSize
                        arrangement:(MTSelectionToolbarArrangement)arrangement {
    if ((self = [super initWithFrame:CGRectZero])) {
        // 排布方式在创建时固定（与图标尺寸同属快照），运行期不再跟随偏好抖动。
        _arrangement = arrangement;
        iconPointSize = MAX(10.0, MIN(20.0, iconPointSize));
        _buttonScale = iconPointSize / 17.0;
        BOOL stacked = style == MTSelectionButtonStyleIconAndText;
        _rowHeight = (stacked ? 62.0 : 46.0) * _buttonScale;
        self.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.78];
        self.layer.cornerRadius = 14.0 * _buttonScale;
        self.clipsToBounds = YES;
        // 滑动排布：按钮装进横向滚动容器，工具栏自身仍是原来那张圆角条。
        UIView *container = self;
        if (_arrangement == MTSelectionToolbarArrangementSwipe) {
            UIScrollView *scroller = [[UIScrollView alloc] initWithFrame:CGRectZero];
            scroller.showsHorizontalScrollIndicator = NO;
            scroller.showsVerticalScrollIndicator = NO;
            scroller.scrollsToTop = NO;
            scroller.bounces = YES;
            scroller.alwaysBounceHorizontal = NO;
            [self addSubview:scroller];
            self.scroller = scroller;
            container = scroller;
        }

        NSMutableArray<UIButton *> *buttons = [NSMutableArray array];
        NSMutableArray<UIView *> *separators = [NSMutableArray array];
        for (NSString *identifier in identifiers) {
            UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
            // 取消键统一红色（同编辑器关闭键、长截图 HUD 取消），其余键保持白色。
            BOOL isCancelButton = [identifier isEqualToString:@"cancel"];
            button.tintColor = isCancelButton ? UIColor.systemRedColor : UIColor.whiteColor;
            NSString *name = [MTEditorOrder displayNameForSelectionIdentifier:identifier];
            button.accessibilityLabel = name;
            button.accessibilityIdentifier = identifier;
            UIImage *icon = nil;
            if (style != MTSelectionButtonStyleText) {
                NSString *symbol = [MTEditorOrder iconNameForSelectionIdentifier:identifier];
                icon = symbol.length ? [UIImage systemImageNamed:symbol] : nil;
                if (icon) {
                    icon = [icon imageWithConfiguration:[UIImageSymbolConfiguration
                        configurationWithPointSize:iconPointSize weight:UIImageSymbolWeightMedium]];
                }
            }
            if (stacked && icon) {
                UIButtonConfiguration *configuration = [UIButtonConfiguration plainButtonConfiguration];
                configuration.baseForegroundColor =
                    isCancelButton ? UIColor.systemRedColor : UIColor.whiteColor;
                configuration.image = icon;
                configuration.imagePlacement = NSDirectionalRectEdgeTop;
                configuration.imagePadding = 4.0 * _buttonScale;
                configuration.attributedTitle = [[NSAttributedString alloc] initWithString:name attributes:@{
                    NSFontAttributeName: [UIFont systemFontOfSize:11.0 * _buttonScale weight:UIFontWeightSemibold],
                }];
                configuration.titleAlignment = UIButtonConfigurationTitleAlignmentCenter;
                configuration.titleLineBreakMode = NSLineBreakByTruncatingTail;
                configuration.contentInsets = NSDirectionalEdgeInsetsMake(4.0 * _buttonScale,
                    2.0 * _buttonScale, 4.0 * _buttonScale, 2.0 * _buttonScale);
                button.configuration = configuration;
            } else if (icon) {
                [button setImage:icon forState:UIControlStateNormal];
            } else {
                // 当前系统不支持自定义符号时，保留名称和可点击的完整按钮。
                [button setTitle:name forState:UIControlStateNormal];
                button.titleLabel.font = [UIFont systemFontOfSize:15.0 * _buttonScale weight:UIFontWeightSemibold];
            }
            button.titleLabel.numberOfLines = 1;
            button.titleLabel.adjustsFontSizeToFitWidth = YES;
            button.titleLabel.minimumScaleFactor = 0.5;
            [buttons addObject:button];
            [container addSubview:button];
            if (buttons.count > 1) {
                UIView *separator = [[UIView alloc] init];
                separator.backgroundColor = UIColor.whiteColor;
                separator.userInteractionEnabled = NO;
                [container addSubview:separator];
                [separators addObject:separator];
            }
        }
        _buttons = [buttons copy];
        _separators = [separators copy];
    }
    return self;
}

- (CGFloat)preferredWidthForAvailableWidth:(CGFloat)availableWidth {
    availableWidth = MAX(0.0, availableWidth);
    NSUInteger columns = [self mtColumnsForAvailableWidth:availableWidth];
    return columns ? MIN(availableWidth, (columns * 60.0 + 12.0) * self.buttonScale) : 0.0;
}

- (NSUInteger)mtColumnsForAvailableWidth:(CGFloat)availableWidth {
    if (self.buttons.count == 0) return 0;
    // 滑动排布恒为一排：屏幕上放不下的按钮横向滑动查看，不换行。
    if (self.arrangement == MTSelectionToolbarArrangementSwipe) return self.buttons.count;
    CGFloat contentWidth = MAX(0.0, availableWidth - 12.0 * self.buttonScale);
    // 保留至少 40pt 的基准按钮宽度；空间不足时换行，不继续挤压所有按钮。
    NSUInteger fitting = (NSUInteger)MAX(1.0, floor((contentWidth + self.buttonScale) /
                                                   (41.0 * self.buttonScale)));
    return MIN(MIN(8, self.buttons.count), fitting);
}

- (CGFloat)preferredHeightForAvailableWidth:(CGFloat)availableWidth {
    NSUInteger columns = [self mtColumnsForAvailableWidth:availableWidth];
    if (columns == 0) return 0.0;
    NSUInteger rows = (self.buttons.count + columns - 1) / columns;
    return rows * self.rowHeight + (rows - 1) * 4.0 * self.buttonScale;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = CGRectGetWidth(self.bounds);
    NSUInteger columns = [self mtColumnsForAvailableWidth:width];
    if (columns == 0 || width <= 0.0) return;
    CGFloat scale = self.buttonScale;
    BOOL scrolling = self.arrangement == MTSelectionToolbarArrangementSwipe;
    // 多排按可用宽度均分；滑动模式下按钮保持最小宽度，让内容依靠滑动而非压缩。
    CGFloat even = MAX(0.0, (width - 12.0 * scale - (columns - 1) * scale) / columns);
    CGFloat buttonWidth = scrolling ? MAX(41.0 * scale, even) : even;
    CGFloat stride = buttonWidth + scale;
    CGFloat contentWidth = columns * stride - scale + 12.0 * scale;
    if (scrolling && self.scroller) {
        self.scroller.frame = self.bounds;
        self.scroller.contentSize = CGSizeMake(MAX(width, contentWidth), CGRectGetHeight(self.bounds));
    }
    CGFloat buttonHeight = self.rowHeight - 4.0 * scale;
    for (NSUInteger i = 0; i < self.buttons.count; i++) {
        NSUInteger column = scrolling ? i : i % columns;
        NSUInteger row = scrolling ? 0 : i / columns;
        CGFloat x = 6.0 * scale + column * stride;
        CGFloat y = 2.0 * scale + row * (self.rowHeight + 4.0 * scale);
        self.buttons[i].frame = CGRectMake(x, y, buttonWidth, buttonHeight);
        if (i > 0) {
            UIView *separator = self.separators[i - 1];
            separator.hidden = (column == 0);
            separator.frame = CGRectMake(x - scale, y + 10.0 * scale,
                                         scale, MAX(0.0, buttonHeight - 20.0 * scale));
        }
    }
    if (self.layoutColumns != columns && self.userInteractionEnabled) {
        MTCaptureLogInfo(@"selection toolbar layout: arrangement=%@ buttons=%lu columns=%lu rows=%lu",
                  scrolling ? @"swipe" : @"rows", (unsigned long)self.buttons.count,
                  (unsigned long)columns, (unsigned long)((self.buttons.count + columns - 1) / columns));
    }
    self.layoutColumns = columns;
}

@end
