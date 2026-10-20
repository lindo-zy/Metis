#import <UIKit/UIKit.h>

@class MTCollectionView, MTContextDecision;

@interface MTFloatingAppShelfView : UIView <UIGestureRecognizerDelegate>
@property(nonatomic, copy) void (^contentChanged)(void);
@property(nonatomic, readonly) BOOL unlocked;
// 执行上下文动作（选择器类）时需要转交给同一 Dock 的工具栏。
@property(nonatomic, weak) MTCollectionView *actionTarget;
- (void)refresh;
- (instancetype)initForPreview;
- (void)configurePreviewWithPreferences:(NSDictionary *)preferences decision:(MTContextDecision *)decision;
@end
