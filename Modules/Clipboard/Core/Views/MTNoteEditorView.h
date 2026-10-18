//
//  MTNoteEditorView.h
//  Mt
//

#import <UIKit/UIKit.h>

@class MTTableViewCell;

NS_ASSUME_NONNULL_BEGIN

@interface MTNoteEditorView : UIView

@property(nonatomic, strong, readonly) UIView *inputRowView;
@property(nonatomic, strong, readonly) UITextField *textField;
@property(nonatomic, strong, readonly) UIButton *saveButton;
@property(nonatomic, strong, readonly) UIButton *cancelButton;
@property(nonatomic, strong, readonly, nullable) MTTableViewCell *previewCell;
@property(nonatomic, assign) CGFloat previewCellHeight;
@property(nonatomic, assign) CGFloat keyboardBottomInset;
@property(nonatomic, assign) BOOL automaticallyPositionsPreviewCell;
@property(nonatomic, assign) BOOL anchorsEditingContentToTop;
@property(nonatomic, assign, getter=usesCompactLayout) BOOL compactLayout;
@property(nonatomic, assign, readonly) CGFloat editingContentHeight;

- (void)setPreviewCell:(nullable MTTableViewCell *)previewCell;
- (CGRect)targetPreviewCellFrame;

@end

NS_ASSUME_NONNULL_END
