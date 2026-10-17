#include <UIKit/UIKit.h>

@interface DXCell : UICollectionViewCell
@property (strong, nonatomic) UIButton *btn;
@property (strong, nonatomic) NSString *identifier;

// The button is centered inside the cell and spans a fraction of its width:
// 1.0 fills the whole slot (the historical layout), smaller values shrink the
// button around the center so "button size" leaves symmetric gaps.
- (void)applyButtonWidthMultiplier:(CGFloat)multiplier;
@end
