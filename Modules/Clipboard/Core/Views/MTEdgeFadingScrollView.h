//
//  MTEdgeFadingScrollView.h
//  Mt
//

#import <UIKit/UIKit.h>

#import "MTEdgeFadeMaskController.h"

NS_ASSUME_NONNULL_BEGIN

@interface MTEdgeFadingScrollView : UIScrollView
@property(nonatomic, assign) CGFloat edgeFadeWidth;
@property(nonatomic, assign) UIEdgeInsets edgeFadeInsets;
@property(nonatomic, assign) MTEdgeFadeAxis edgeFadeAxis;
@property(nonatomic, assign, getter=isEdgeFadeEnabled) BOOL edgeFadeEnabled;
- (void)updateEdgeFadeMask;
@end

NS_ASSUME_NONNULL_END
