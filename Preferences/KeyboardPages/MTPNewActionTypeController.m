#import "MTPNewActionTypeController.h"
#import "MTPLinkActionEditorController.h"
#import "common.h"

@interface MTPNewActionTypeController ()
@end

@implementation MTPNewActionTypeController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"新建动作";
    self.model = [self mtBuildModel];
    [self render];
}

// 行元组（设计稿第三屏）：[类型, 摘要, SF Symbol, 色token]；标题用
// MTPLinkActionEditorController 的本地化显示名，顺序即 02 §3 固定顺序。
- (MTSettingsPageModel *)mtBuildModel {
    NSArray *configs = @[
        @[@"urlscheme",  @"链接协议与参数",   @"link", @"blue"],
        @[@"text",       @"保存片段，一键插入", @"doc.text.fill", @"purple"],
        @[@"openapp",    @"选择目标应用",     @"square.and.arrow.up", @"green"],
        @[@"shortcut",   @"选择应用快捷操作", @"square.grid.2x2.fill", @"orange"],
        @[@"system",     @"选择系统操作",     @"gearshape.fill", @"gray"],
        // AI 动作放在系统动作之后、JS脚本之前：前六项都是「打开/跳转」类，
        // 后两项是「内容处理」类，脚本始终垫底。
        @[@"ai",         @"选人设与模型，直接提问", @"sparkles", @"indigo"],
        @[@"javascript", @"编写与调试 JS",    @"chevron.left.forwardslash.chevron.right", @"yellow"],
    ];
    NSMutableArray<MTSettingsRow *> *rows = [NSMutableArray array];
    for (NSArray *config in configs) {
        MTSettingsRow *row = [MTSettingsRow linkRowWithIdentifier:config[0]
                                                            title:[MTPLinkActionEditorController displayNameForType:config[0]]];
        row.subtitle = config[1];
        row.iconName = config[2];
        row.colorName = config[3];
        [rows addObject:row];
    }
    MTSettingsSection *section = [MTSettingsSection sectionWithRows:rows];
    MTSettingsPageModel *model = [[MTSettingsPageModel alloc] init];
    // 设计稿：「选择动作类型」是大标题下的灰色副标题，卡片行无分区头。
    model.introSubtitle = @"选择动作类型";
    model.sections = @[section];
    model.footerText = @"动作可加入面板，也可直接绑定到按钮或手势";
    return model;
}

- (void)settingsRowSelected:(MTSettingsRow *)row {
    if (self.selectionHandler && row.identifier.length) self.selectionHandler(row.identifier);
}

@end
