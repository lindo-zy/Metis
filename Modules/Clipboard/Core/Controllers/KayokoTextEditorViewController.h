//
//  KayokoTextEditorViewController.h
//  Kayoko
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class KayokoTextEditorView;
@class KayokoTextEditorViewController;
@class KayokoPasteboardItem;

@protocol KayokoTextEditorViewControllerDelegate <NSObject>
- (void)textEditorViewControllerDidBeginEditing:(KayokoTextEditorViewController *)controller;
- (void)textEditorViewControllerDidRequestSave:(KayokoTextEditorViewController *)controller;
- (void)textEditorViewControllerDidRequestCancel:(KayokoTextEditorViewController *)controller;
@end

@interface KayokoTextEditorViewController : UIViewController

@property(nonatomic, weak, nullable) id<KayokoTextEditorViewControllerDelegate> delegate;
@property(nonatomic, strong, readonly) KayokoTextEditorView *textEditorView;
@property(nonatomic, strong, nullable, readonly) KayokoPasteboardItem *item;
@property(nonatomic, copy, nullable, readonly) NSString *sourceHistoryKey;
@property(nonatomic, assign, readonly, getter=isEditing) BOOL editing;
@property(nonatomic, assign, readonly, getter=isSaving) BOOL saving;

- (void)beginEditingItem:(KayokoPasteboardItem *)item
        sourceHistoryKey:(NSString *)sourceHistoryKey
        replacementRange:(NSRange)replacementRange;
- (NSString *)composedEditedContent;
- (void)finishEditing;
- (void)setSaving:(BOOL)saving;
- (void)reset;

@end

NS_ASSUME_NONNULL_END
