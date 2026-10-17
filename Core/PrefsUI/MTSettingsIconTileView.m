#import "MTSettingsIconTileView.h"
#import "MTSettingsStyle.h"

@implementation MTSettingsIconTileView {
    UIImageView *_glyph;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        // 系统设置风格：无瓦片底色，symbol 直接渲染， tint 跟随 label 动态色。
        _glyph = [[UIImageView alloc] init];
        _glyph.contentMode = UIViewContentModeScaleAspectFit;
        _glyph.tintColor = UIColor.labelColor;
        _glyph.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_glyph];
        [NSLayoutConstraint activateConstraints:@[
            [_glyph.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
            [_glyph.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_glyph.widthAnchor constraintEqualToAnchor:self.widthAnchor],
            [_glyph.heightAnchor constraintEqualToAnchor:self.heightAnchor],
        ]];
    }
    return self;
}

- (void)updateWithIconName:(NSString *)iconName {
    UIImage *symbol = iconName.length ? [MTSettingsStyle symbolPreferred:iconName fallback:nil] : nil;
    if (!symbol) {
        // 无符号即无图标：整块隐藏并清掉复用残留。
        self.hidden = YES;
        _glyph.image = nil;
        return;
    }
    self.hidden = NO;
    _glyph.preferredSymbolConfiguration =
        [UIImageSymbolConfiguration configurationWithPointSize:[MTSettingsStyle tileIconPointSize]];
    _glyph.image = [symbol imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

@end
