//
//  KayokoQuickActionPanelViewController.h
//  Kayoko
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^KayokoQuickActionPanelSelectionHandler)(NSDictionary<NSString *, id> *action);

typedef NS_ENUM(NSUInteger, KayokoQuickActionPanelPlacement) {
    KayokoQuickActionPanelPlacementAboveAnchor = 0,
    KayokoQuickActionPanelPlacementScreenUpperCenter,
};

@interface KayokoQuickActionPanelViewController : UIViewController

- (instancetype)initWithActions:(NSArray<NSDictionary<NSString *, id> *> *)actions
              anchoringAboveView:(nullable UIView *)anchorView
                       placement:(KayokoQuickActionPanelPlacement)placement
                selectionHandler:(KayokoQuickActionPanelSelectionHandler)selectionHandler
    NS_DESIGNATED_INITIALIZER;
@property(nonatomic, copy, nullable) dispatch_block_t dismissalHandler;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil
                         bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
