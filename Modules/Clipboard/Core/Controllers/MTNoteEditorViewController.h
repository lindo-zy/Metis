//
//  MTNoteEditorViewController.h
//  Mt
//

#import <UIKit/UIKit.h>

@class MTNoteEditorView;
@class MTNoteEditorViewController;
@class MTPasteboardItem;
@class MTTableViewCell;

NS_ASSUME_NONNULL_BEGIN

@protocol MTNoteEditorViewControllerDelegate <NSObject>

- (void)noteEditorViewController:(MTNoteEditorViewController *)controller
              didRequestSaveNote:(nullable NSString *)note;
- (void)noteEditorViewControllerDidRequestCancel:(MTNoteEditorViewController *)controller;
- (void)noteEditorViewController:(MTNoteEditorViewController *)controller
    didUpdateKeyboardBottomInset:(CGFloat)keyboardBottomInset
               animationDuration:(NSTimeInterval)animationDuration
                         options:(UIViewAnimationOptions)options;

@end

@interface MTNoteEditorViewController : UIViewController

@property(nonatomic, weak, nullable) id<MTNoteEditorViewControllerDelegate> delegate;
@property(nonatomic, strong, readonly) MTNoteEditorView *noteEditorView;
@property(nonatomic, strong, readonly, nullable) MTPasteboardItem *item;

- (void)prepareForItem:(MTPasteboardItem *)item
    presentationCell:(MTTableViewCell *)presentationCell
             cellHeight:(CGFloat)cellHeight
    keyboardBottomInset:(CGFloat)keyboardBottomInset;
// Returns the current on-screen keyboard overlap. It deliberately does not retain a previous
// value: a stale height would move the editor before the next keyboard presentation starts.
- (CGFloat)visibleKeyboardBottomInset;
- (void)beginEditing;
- (void)resignEditing;
- (void)restorePreviewToSavedState;
- (void)setSaving:(BOOL)saving;
- (void)reset;

@end

NS_ASSUME_NONNULL_END
