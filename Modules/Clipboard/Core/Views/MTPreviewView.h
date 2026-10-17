//
//  MTPreviewView.h
//  Mt
//
//  Created by Alexandra Aurora Göttlicher
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class MTHeaderView;

@interface MTPreviewView : UIView

@property(nonatomic, strong, readonly) MTHeaderView *headerView;
@property(nonatomic, strong, readonly) UIView *transitionContentView;
@property(nonatomic, strong) UITextView *textView;
@property(nonatomic, strong) UIImageView *imageView;
@property(nonatomic, copy) NSString *name;
@property(nonatomic, assign) CGFloat keyboardBottomInset;

- (instancetype)initWithName:(NSString *)name;
- (void)showText:(NSString *)text;
- (void)showImage:(nullable UIImage *)image;
- (void)reset;
- (void)scrollToTopAnimated:(BOOL)animated;
- (BOOL)canBeginEdgeBackGesture;
- (void)requireImagePanGestureRecognizerToFailGestureRecognizer:(UIGestureRecognizer *)gestureRecognizer;

@end

NS_ASSUME_NONNULL_END
