//
//  MTTextEditorView.h
//  Mt
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class MTHeaderView;

@interface MTTextEditorView : UIView

@property(nonatomic, strong, readonly) MTHeaderView *headerView;
@property(nonatomic, strong, readonly) UITextView *textView;
@property(nonatomic, assign) CGFloat keyboardBottomInset;

- (void)setEditorText:(NSString *)text;
- (NSString *)editorText;
- (void)reset;

@end

NS_ASSUME_NONNULL_END
