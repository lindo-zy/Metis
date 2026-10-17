//
//  MTWordSelectionViewController.h
//  Mt
//

#import <UIKit/UIKit.h>

@class MTWordSelectionView;
@class MTWordSelectionViewController;
@class MTPasteboardItem;

NS_ASSUME_NONNULL_BEGIN

@protocol MTWordSelectionViewControllerDelegate <NSObject>

- (void)wordSelectionViewController:(MTWordSelectionViewController *)controller
    didRequestHideContainerAfterDirectPaste:(BOOL)directPaste;
- (void)wordSelectionViewController:(MTWordSelectionViewController *)controller
     triggerHapticFeedbackWithStyle:(UIImpactFeedbackStyle)style;
- (void)wordSelectionViewControllerDidRequestEdit:(MTWordSelectionViewController *)controller;

@end

@interface MTWordSelectionViewController : UIViewController

@property(nonatomic, weak, nullable) id<MTWordSelectionViewControllerDelegate> delegate;
@property(nonatomic, strong, readonly) MTWordSelectionView *wordSelectionView;
@property(nonatomic, copy, readonly) NSString *name;
@property(nonatomic, copy, nullable, readonly) NSString *sourceHistoryKey;
@property(nonatomic, strong, nullable, readonly) MTPasteboardItem *sourceItem;
@property(nonatomic, copy, readonly) NSString *selectedText;
@property(nonatomic, assign, readonly) NSRange selectedTextRangeInOriginalText;
@property(nonatomic, assign, readonly, getter=isShowingWordSelection) BOOL showingWordSelection;
@property(nonatomic, assign, readonly) BOOL hasSelectedText;
@property(nonatomic, copy, nullable) void (^selectionChangedHandler)(void);

- (instancetype)initWithName:(NSString *)name NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil
                         bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (BOOL)canShowText:(NSString *)text;
- (void)showWordSelectionWithItem:(MTPasteboardItem *)item
                 sourceHistoryKey:(NSString *)sourceHistoryKey
               automaticallyPaste:(BOOL)automaticallyPaste;
- (void)hideWordSelection;
- (void)handleActionButtonWithAutomaticallyPaste:(BOOL)automaticallyPaste;
- (void)setEditButtonEnabled:(BOOL)enabled;
- (void)resetWordSelectionState;
- (void)updateActionButtonState;
- (void)handleTextActionButtonPressed;
- (void)scrollToTopAnimated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END
