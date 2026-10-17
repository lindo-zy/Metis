#import "MTSettingsIconTileView.h"
#import "MTSettingsStyle.h"

@implementation MTSettingsIconTileView {
    UIImageView *_glyph;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.layer.cornerRadius = [MTSettingsStyle tileCornerRadius];
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.masksToBounds = YES;
        _glyph = [[UIImageView alloc] init];
        _glyph.contentMode = UIViewContentModeScaleAspectFit;
        _glyph.tintColor = UIColor.whiteColor;
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

- (void)updateWithIconName:(NSString *)iconName colorName:(NSString *)colorName {
    UIImage *symbol = iconName.length ? [MTSettingsStyle symbolPreferred:iconName fallback:nil] : nil;
    if (!symbol) {
        // 无符号即无瓦片：整块隐藏并清掉复用残留（底色/旧图）。
        self.hidden = YES;
        _glyph.image = nil;
        self.backgroundColor = nil;
        return;
    }
    self.hidden = NO;
    self.backgroundColor = [MTSettingsStyle tileColorForName:colorName];
    _glyph.preferredSymbolConfiguration =
        [UIImageSymbolConfiguration configurationWithPointSize:[MTSettingsStyle tileIconPointSize]];
    _glyph.image = [symbol imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

@end
