//
//  MTTextEditorViewController.h
//  Mt
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class MTTextEditorView;
@class MTTextEditorViewController;
@class MTPasteboardItem;

@protocol MTTextEditorViewControllerDelegate <NSObject>
- (void)textEditorViewControllerDidBeginEditing:(MTTextEditorViewController *)controller;
- (void)textEditorViewControllerDidRequestSave:(MTTextEditorViewController *)controller;
- (void)textEditorViewControllerDidRequestCancel:(MTTextEditorViewController *)controller;
@end

@interface MTTextEditorViewController : UIViewController

@property(nonatomic, weak, nullable) id<MTTextEditorViewControllerDelegate> delegate;
@property(nonatomic, strong, readonly) MTTextEditorView *textEditorView;
@property(nonatomic, strong, nullable, readonly) MTPasteboardItem *item;
@property(nonatomic, copy, nullable, readonly) NSString *sourceHistoryKey;
@property(nonatomic, assign, readonly, getter=isEditing) BOOL editing;
@property(nonatomic, assign, readonly, getter=isSaving) BOOL saving;

- (void)beginEditingItem:(MTPasteboardItem *)item
        sourceHistoryKey:(NSString *)sourceHistoryKey
        replacementRange:(NSRange)replacementRange;
- (NSString *)composedEditedContent;
- (void)finishEditing;
- (void)setSaving:(BOOL)saving;
- (void)reset;

@end

NS_ASSUME_NONNULL_END
