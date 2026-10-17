//
//  MTQuickActionPanelViewController.h
//  Mt
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^MTQuickActionPanelSelectionHandler)(NSDictionary<NSString *, id> *action);

typedef NS_ENUM(NSUInteger, MTQuickActionPanelPlacement) {
    MTQuickActionPanelPlacementAboveAnchor = 0,
    MTQuickActionPanelPlacementScreenUpperCenter,
};

@interface MTQuickActionPanelViewController : UIViewController

- (instancetype)initWithActions:(NSArray<NSDictionary<NSString *, id> *> *)actions
              anchoringAboveView:(nullable UIView *)anchorView
                       placement:(MTQuickActionPanelPlacement)placement
                selectionHandler:(MTQuickActionPanelSelectionHandler)selectionHandler
    NS_DESIGNATED_INITIALIZER;
@property(nonatomic, copy, nullable) dispatch_block_t dismissalHandler;
- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil
                         bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
