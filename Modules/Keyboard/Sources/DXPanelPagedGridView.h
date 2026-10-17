#import <UIKit/UIKit.h>

// Shared action surface; the containing panel keeps controls/short-screen
// overflow in its vertical scroll view. This view scrolls horizontally only.
@interface DXPanelPagedGridView : UIScrollView <UIScrollViewDelegate>
@property(nonatomic, copy) void (^blankAction)(void);
@property(nonatomic, copy) NSString *diagnosticName;
@property(nonatomic, readonly) NSUInteger pageCount;
@property(nonatomic, readonly) NSUInteger currentPage;
- (void)configureWithItems:(NSArray<UIView *> *)items columns:(NSInteger)columns scale:(CGFloat)scale;
- (CGFloat)preferredHeightForWidth:(CGFloat)width;
@end
