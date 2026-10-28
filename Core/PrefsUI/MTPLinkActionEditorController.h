#import <Preferences/PSListController.h>

// Edits one user-defined custom action. Entries carry a "type" field (see
// common.h): the editor renders type-specific configuration below the shared
// 名称/图标 rows. Entries without a type keep the legacy auto-detecting
// 动作链接 layout. The caller owns persistence and receives a normalized
// entry when Save is tapped.
@interface MTPLinkActionEditorController : PSViewController <UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate, UITextViewDelegate>
@property (nonatomic, strong) NSMutableDictionary *entry;
@property (nonatomic, copy) void (^completion)(NSDictionary *entry);
@property (nonatomic, copy) NSArray<NSString *> *pendingGroupNames;

// Type chooser shared with the custom-actions management page: an alert
// listing every action type. Sub-action-only types are annotated; the order
// places URL Scheme first because it is the default for new actions.
+ (void)presentTypeChooserFromController:(UIViewController *)controller
                             currentType:(NSString *)currentType
                              completion:(void (^)(NSString *type))completion;
// 无输入框宿主（Dock/状态栏/边缘与弧形手势/快速面板/剪切板）就地新建用的
// 受限类型选择 alert：只有不依赖输入框、免会话执行的类型。
+ (void)presentGloballyExecutableTypeChooserFromController:(UIViewController *)controller
                                                   message:(NSString *)message
                                                completion:(void (^)(NSString *type))completion;
// 新建流程唯一权威的类型集与草稿构造：各入口不得再各自硬编码默认
// 名称/图标/附加键。draftEntryForType 对未知类型返回 nil，调用方判空。
+ (NSArray<NSString *> *)globallyExecutableCreatableTypes;
+ (NSMutableDictionary *)draftEntryForType:(NSString *)type;
+ (NSString *)displayNameForType:(NSString *)type;
+ (NSString *)defaultIconForType:(NSString *)type;
@end
