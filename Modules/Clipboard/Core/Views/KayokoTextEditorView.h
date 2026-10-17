//
//  KayokoTextEditorView.h
//  Kayoko
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class KayokoHeaderView;

@interface KayokoTextEditorView : UIView

@property(nonatomic, strong, readonly) KayokoHeaderView *headerView;
@property(nonatomic, strong, readonly) UITextView *textView;
@property(nonatomic, assign) CGFloat keyboardBottomInset;

- (void)setEditorText:(NSString *)text;
- (NSString *)editorText;
- (void)reset;

@end

NS_ASSUME_NONNULL_END
