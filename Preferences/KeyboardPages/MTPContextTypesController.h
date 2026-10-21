#import <Preferences/PSViewController.h>
#import "MTContextTypes.h"
FOUNDATION_EXPORT NSString *MTPCTX(NSString *key);
FOUNDATION_EXPORT NSString *MTPCTXTypeName(MTContextType *type);
FOUNDATION_EXPORT void MTPCTXSaveTypes(NSString *group, NSArray<MTContextType *> *types);
@interface MTPContextTypesController : PSViewController <UITableViewDelegate, UITableViewDataSource>
@property(nonatomic, copy) NSString *groupKey;
@end
@interface MTPContextTypeActionsController : PSViewController <UITableViewDelegate, UITableViewDataSource>
@property(nonatomic, copy) NSString *groupKey;
@property(nonatomic, copy) NSString *typeID;
@property(nonatomic, strong) UITableView *table;
@property(nonatomic, strong) MTContextType *type;
@property(nonatomic, assign) NSUInteger slots;
- (void)reloadType;
- (void)saveType;
- (void)addAction;
- (UITableViewCell *)actionCellAtIndex:(NSUInteger)index;
- (void)pushPage:(UIViewController *)page;
@end
