#import "DXCell.h"

@interface DXCell ()
@property (strong, nonatomic) NSLayoutConstraint *btnWidthConstraint;
@end

@implementation DXCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {

        self.contentView.backgroundColor = [UIColor clearColor];
        //self.backgroundColor = [UIColor clearColor];

        //_btn = [[UIButton alloc] initWithFrame:CGRectZero];
        _btn = [UIButton buttonWithType:UIButtonTypeSystem];

        //[_btn setTitle:_btn.title];
        _btn.translatesAutoresizingMaskIntoConstraints = NO;
        //[self.contentView addSubview:_btn];
        [self.contentView addSubview:_btn];

        [NSLayoutConstraint activateConstraints: @[
            [_btn.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [_btn.bottomAnchor constraintEqualToAnchor: self.contentView.bottomAnchor],
            [_btn.centerXAnchor constraintEqualToAnchor: self.contentView.centerXAnchor]
        ]];
        [self applyButtonWidthMultiplier:1.0];
    }
    return self;
}

- (void)applyButtonWidthMultiplier:(CGFloat)multiplier {
    if (multiplier <= 0) multiplier = 1.0;
    if (self.btnWidthConstraint) {
        [NSLayoutConstraint deactivateConstraints:@[self.btnWidthConstraint]];
    }
    self.btnWidthConstraint = [self.btn.widthAnchor constraintEqualToAnchor:self.contentView.widthAnchor
                                                                 multiplier:multiplier];
    [NSLayoutConstraint activateConstraints:@[self.btnWidthConstraint]];
}

@end
