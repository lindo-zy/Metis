#import "MTCaptureRulesController.h"
#import "MTCaptureRuleEngine.h"
#import "MTClipboardActionReferences.h"
#import "MTSharedResourceStore.h"
#import "MTPContextScriptEditorController.h"
#import "MTPContextScriptDebugController.h"
#import "MTPAIScriptChatController.h"
#import "MTPAIScriptProfile.h"
#import "MTPJavaScriptPreviewCell.h"
#import "MTAIEngine.h"

static void MTCaptureShowError(UIViewController *owner, NSString *message) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"无法保存规则"
        message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [owner presentViewController:alert animated:YES completion:nil];
}

@interface MTCaptureRuleEditorController : UITableViewController
- (instancetype)initWithEntry:(NSDictionary *)entry isNew:(BOOL)isNew;
@property (nonatomic, copy) void (^onSaved)(void);
@end

@interface MTCaptureRuleActionPickerController : UITableViewController
+ (instancetype)pickerWithExcludedIDs:(NSArray<NSString *> *)excludedIDs
                           completion:(void (^)(NSString *uuid))completion;
@end

#pragma mark - Priority list

@interface MTCaptureRulesController () <UITableViewDelegate, UITableViewDataSource, UITableViewDragDelegate, UITableViewDropDelegate>
@end

@implementation MTCaptureRulesController {
    UITableView *_table;
    NSArray<MTCaptureRule *> *_rules;
}

// PSViewController is a navigation adapter. Own exactly one table instead of
// placing a second table over the view managed by Preferences.
- (void)loadView {
    _table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.view = _table;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"剪切板规则";
    _table.delegate = self;
    _table.dataSource = self;
    _table.dragDelegate = self;
    _table.dropDelegate = self;
    _table.dragInteractionEnabled = YES;
    _table.rowHeight = UITableViewAutomaticDimension;
    _table.estimatedRowHeight = 72;
    _table.allowsSelectionDuringEditing = YES;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"编辑"
        style:UIBarButtonItemStylePlain target:self action:@selector(toggleEditing)];
    [self reloadRules];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadRules];
}

- (void)toggleEditing {
    [_table setEditing:!_table.editing animated:YES];
    self.navigationItem.rightBarButtonItem.title = _table.editing ? @"完成" : @"编辑";
}

- (void)reloadRules {
    _rules = [MTCaptureRule rulesFromDictionaries:
        [MTClipboardActionReferences ruleDictionariesInDocument:[MTSharedResourceStore readSnapshot]]];
    self.navigationItem.rightBarButtonItem.enabled = _rules.count > 0;
    if (!_rules.count && _table.editing) [self toggleEditing];
    [_table reloadData];
}

- (BOOL)commitMutation:(void (^)(NSMutableArray<NSDictionary *> *rules))mutation {
    NSError *error = nil;
    NSDictionary *document = [MTSharedResourceStore readSnapshotError:&error];
    if (!document) {
        MTCaptureShowError(self, error.localizedDescription ?: @"读取配置失败，请重试。");
        [self reloadRules];
        return NO;
    }
    NSMutableArray *rules = [[MTClipboardActionReferences ruleDictionariesInDocument:document] mutableCopy];
    mutation(rules);
    BOOL saved = [MTSharedResourceStore commitSnapshot:
        [MTClipboardActionReferences document:document settingRuleDictionaries:rules]
        expectedRevision:[document[@"revision"] unsignedLongLongValue] error:&error];
    if (!saved) MTCaptureShowError(self, error.localizedDescription ?: @"配置已改变，请重试。");
    [self reloadRules];
    return saved;
}

- (void)setRuleID:(NSString *)identifier enabled:(BOOL)enabled {
    [self commitMutation:^(NSMutableArray<NSDictionary *> *rules) {
        for (NSUInteger i = 0; i < rules.count; i++) {
            if (![rules[i][@"id"] isEqual:identifier]) continue;
            NSMutableDictionary *entry = [rules[i] mutableCopy];
            entry[@"enabled"] = @(enabled);
            rules[i] = entry;
            break;
        }
    }];
}

- (BOOL)moveRuleID:(NSString *)identifier toIndex:(NSUInteger)index {
    return [self commitMutation:^(NSMutableArray<NSDictionary *> *rules) {
        NSUInteger source = [rules indexOfObjectPassingTest:^BOOL(NSDictionary *entry, NSUInteger idx, BOOL *stop) {
            return [entry[@"id"] isEqual:identifier];
        }];
        if (source == NSNotFound) return;
        NSDictionary *entry = rules[source];
        [rules removeObjectAtIndex:source];
        [rules insertObject:entry atIndex:MIN(index, rules.count)];
    }];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? _rules.count : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section != 0) return nil;
    NSUInteger enabled = 0;
    for (MTCaptureRule *rule in _rules) if (rule.enabled) enabled++;
    return _rules.count ? [NSString stringWithFormat:@"优先级从上到下 · %lu / %lu 已开启",
        (unsigned long)enabled, (unsigned long)_rules.count] : @"尚未添加规则";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return _rules.count ? @"长按规则拖动排序，或点“编辑”使用排序手柄。首个命中的有效规则执行绑定动作；关闭的规则不参与匹配。" : nil;
    return @"双击采集气泡时按顺序匹配；未命中不执行动作。复制后自动执行由每条规则内的开关独立控制。";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    // Separate identities keep add-row accessories and rule controls independent.
    NSString *reuse = indexPath.section == 0 ? @"rule" : @"add";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuse];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuse];
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.textLabel.adjustsFontForContentSizeCategory = YES;
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
    cell.detailTextLabel.numberOfLines = 0;
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.editingAccessoryType = UITableViewCellAccessoryDisclosureIndicator;
    if (indexPath.section == 1) {
        cell.textLabel.text = @"添加规则";
        cell.textLabel.textColor = _rules.count < 32 ? UIColor.systemBlueColor : UIColor.secondaryLabelColor;
        cell.detailTextLabel.text = _rules.count < 32 ? @"JavaScript 条件 · AI 编写 · 沙盒调试" : @"最多添加 32 条规则";
        cell.imageView.image = [UIImage systemImageNamed:@"plus.circle.fill"];
        cell.imageView.tintColor = UIColor.systemBlueColor;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    MTCaptureRule *rule = _rules[indexPath.row];
    cell.textLabel.text = [NSString stringWithFormat:@"%ld. %@", (long)indexPath.row + 1, rule.name.length ? rule.name : @"未命名规则"];
    cell.textLabel.textColor = rule.enabled ? UIColor.labelColor : UIColor.secondaryLabelColor;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %lu 个动作%@",
        rule.enabled ? @"已开启" : @"已关闭", (unsigned long)rule.actions.count,
        rule.autoRun ? @" · 复制后自动执行" : @""];
    UISwitch *toggle = [UISwitch new];
    toggle.on = rule.enabled;
    toggle.accessibilityLabel = [NSString stringWithFormat:@"启用规则：%@", rule.name];
    __weak typeof(self) weakSelf = self;
    NSString *identifier = rule.identifier;
    [toggle addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
        [weakSelf setRuleID:identifier enabled:((UISwitch *)action.sender).on];
    }] forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = toggle;
    cell.showsReorderControl = YES;
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath { return indexPath.section == 0; }
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath { return indexPath.section == 0; }
- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)source
     toProposedIndexPath:(NSIndexPath *)destination {
    NSInteger row = destination.section == 0 ? destination.row : (NSInteger)_rules.count - 1;
    return [NSIndexPath indexPathForRow:MIN(row, (NSInteger)_rules.count - 1) inSection:0];
}
- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)source toIndexPath:(NSIndexPath *)destination {
    [self moveRuleID:_rules[source.row].identifier toIndex:destination.row];
}
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (style != UITableViewCellEditingStyleDelete || indexPath.section != 0 || indexPath.row >= _rules.count) return;
    NSString *identifier = _rules[indexPath.row].identifier;
    [self commitMutation:^(NSMutableArray<NSDictionary *> *rules) {
        NSIndexSet *indexes = [rules indexesOfObjectsPassingTest:^BOOL(NSDictionary *entry, NSUInteger idx, BOOL *stop) {
            return [entry[@"id"] isEqual:identifier];
        }];
        [rules removeObjectsAtIndexes:indexes];
    }];
}

- (NSArray<UIDragItem *> *)tableView:(UITableView *)tableView itemsForBeginningDragSession:(id<UIDragSession>)session
                       atIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section != 0 || indexPath.row >= _rules.count) return @[];
    UIDragItem *item = [[UIDragItem alloc] initWithItemProvider:[NSItemProvider new]];
    item.localObject = _rules[indexPath.row].identifier;
    return @[item];
}
- (BOOL)tableView:(UITableView *)tableView dragSessionIsRestrictedToDraggingApplication:(id<UIDragSession>)session { return YES; }
- (BOOL)tableView:(UITableView *)tableView canHandleDropSession:(id<UIDropSession>)session {
    return session.localDragSession != nil && [session.items.firstObject.localObject isKindOfClass:NSString.class];
}
- (UITableViewDropProposal *)tableView:(UITableView *)tableView dropSessionDidUpdate:(id<UIDropSession>)session
            withDestinationIndexPath:(NSIndexPath *)indexPath {
    BOOL allowed = session.localDragSession && indexPath.section == 0 && indexPath != nil;
    return [[UITableViewDropProposal alloc] initWithDropOperation:allowed ? UIDropOperationMove : UIDropOperationCancel
        intent:UITableViewDropIntentInsertAtDestinationIndexPath];
}
- (void)tableView:(UITableView *)tableView performDropWithCoordinator:(id<UITableViewDropCoordinator>)coordinator {
    id<UITableViewDropItem> item = coordinator.items.firstObject;
    NSIndexPath *destination = coordinator.destinationIndexPath;
    if (!item.sourceIndexPath || !destination || destination.section != 0 || !_rules.count) return;
    NSUInteger index = MIN((NSUInteger)destination.row, _rules.count - 1);
    NSString *identifier = item.dragItem.localObject;
    if (![self moveRuleID:identifier toIndex:index]) return;
    NSUInteger actual = [_rules indexOfObjectPassingTest:^BOOL(MTCaptureRule *rule, NSUInteger idx, BOOL *stop) {
        return [rule.identifier isEqual:identifier];
    }];
    if (actual != NSNotFound)
        [coordinator dropItem:item.dragItem toRowAtIndexPath:[NSIndexPath indexPathForRow:actual inSection:0]];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    BOOL isNew = indexPath.section == 1;
    if (isNew && _rules.count >= 32) return;
    NSDictionary *entry = isNew ? @{@"id": NSUUID.UUID.UUIDString, @"name": @"新规则", @"enabled": @YES,
        @"auto": @NO, @"source": [MTPAIScriptProfile clipboardProfile].sampleTemplate, @"actions": @[]}
        : _rules[indexPath.row].dictionaryRepresentation;
    MTCaptureRuleEditorController *editor = [[MTCaptureRuleEditorController alloc] initWithEntry:entry isNew:isNew];
    __weak typeof(self) weakSelf = self;
    editor.onSaved = ^{ [weakSelf reloadRules]; };
    [self.navigationController pushViewController:editor animated:YES];
}
@end

#pragma mark - Draft editor

@interface MTCaptureRuleEditorController ()
@property (nonatomic, copy) NSDictionary *entry;
@property (nonatomic, copy) NSDictionary *originalEntry;
@property (nonatomic, assign) BOOL isNew;
@property (nonatomic, copy) NSArray<NSDictionary *> *libraryActions;
@end

@implementation MTCaptureRuleEditorController
- (instancetype)initWithEntry:(NSDictionary *)entry isNew:(BOOL)isNew {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _entry = entry.copy;
        _originalEntry = entry.copy;
        _isNew = isNew;
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.isNew ? @"添加规则" : @"编辑规则";
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 64;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"保存"
        style:UIBarButtonItemStyleDone target:self action:@selector(commit)];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    NSMutableArray *library = [NSMutableArray array];
    for (NSDictionary *resource in [MTSharedResourceStore readSnapshot][@"actions"]) {
        NSDictionary *action = resource[@"entry"];
        if (![MTClipboardActionReferences supportsEntry:action]) continue;
        [library addObject:@{@"id": resource[@"id"], @"name": action[@"name"] ?: @"未命名动作"}];
    }
    self.libraryActions = library;
    [self.tableView reloadData];
}
- (void)setDraftValue:(id)value forKey:(NSString *)key {
    NSMutableDictionary *entry = self.entry.mutableCopy;
    entry[key] = value;
    self.entry = entry;
}
- (void)updateSource:(NSString *)source {
    [self setDraftValue:source ?: @"" forKey:@"source"];
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationNone];
}
- (NSString *)nameForActionUUID:(NSString *)uuid {
    for (NSDictionary *action in self.libraryActions) if ([action[@"id"] isEqual:uuid]) return action[@"name"];
    return @"已删除或不支持的动作";
}
- (void)commit {
    [self.view endEditing:YES];
    NSString *name = [self.entry[@"name"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *validation = name.length == 0 || name.length > 128 ? @"请输入 1–128 字的规则名称。"
        : [[MTPAIScriptProfile clipboardProfile] precheckErrorForScript:self.entry[@"source"]];
    if (validation.length) { MTCaptureShowError(self, validation); return; }
    NSError *error = nil;
    NSDictionary *document = [MTSharedResourceStore readSnapshotError:&error];
    if (!document) { MTCaptureShowError(self, error.localizedDescription ?: @"读取配置失败。"); return; }
    NSMutableArray *rules = [[MTClipboardActionReferences ruleDictionariesInDocument:document] mutableCopy];
    NSUInteger index = [rules indexOfObjectPassingTest:^BOOL(NSDictionary *entry, NSUInteger idx, BOOL *stop) {
        return [entry[@"id"] isEqual:self.entry[@"id"]];
    }];
    if ((self.isNew && (index != NSNotFound || rules.count >= 32)) ||
        (!self.isNew && (index == NSNotFound ||
            ![[MTCaptureRule rulesFromDictionaries:@[rules[index]]].firstObject.dictionaryRepresentation isEqual:self.originalEntry]))) {
        MTCaptureShowError(self, @"这条规则已被修改或删除，或规则数量达到上限。请返回列表后重新编辑。");
        return;
    }
    [self setDraftValue:name forKey:@"name"];
    if (self.isNew) [rules addObject:self.entry]; else rules[index] = self.entry;
    BOOL saved = [MTSharedResourceStore commitSnapshot:
        [MTClipboardActionReferences document:document settingRuleDictionaries:rules]
        expectedRevision:[document[@"revision"] unsignedLongLongValue] error:&error];
    if (!saved) { MTCaptureShowError(self, error.localizedDescription ?: @"配置已改变，请重试。"); return; }
    if (self.onSaved) self.onSaved();
    [self.navigationController popViewControllerAnimated:YES];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 3 : (section == 1 ? 3 : [self.entry[@"actions"] count] + 1);
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[@"基本设置", @"JavaScript 匹配条件", @"命中的动作（按序执行）"][section];
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"打开后，复制内容时会自动执行该规则。修改在点“保存”后生效。";
    if (section == 1) return @"match(text, meta) 返回真值即命中。meta.kind 为 text 或 image。沙盒无网络，最多 8 KB、限时 50 ms；连续失败 3 次会在当前进程暂时跳过，修改规则后重置。";
    return @"引用共享自定义动作，最多 8 个；未绑定动作的规则不参与匹配。左滑可移除引用，动作库条目不受影响。";
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1 && indexPath.row == 0) {
        MTPAIScriptProfile *profile = [MTPAIScriptProfile clipboardProfile];
        NSString *source = self.entry[@"source"];
        return [[MTPJavaScriptPreviewCell alloc] initWithSource:source usage:[profile byteUsageTextForScript:source]
            invalid:[profile precheckErrorForScript:source].length > 0];
    }
    // These rows have distinct content trees. Do not recycle a text-field row as
    // a switch/script/action row; automatic height follows the visible content.
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.textLabel.adjustsFontForContentSizeCategory = YES;
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
    cell.detailTextLabel.numberOfLines = 0;
    if (indexPath.section == 0 && indexPath.row == 0) {
        // Custom stack owns both the label and input, with no overlapping built-in textLabel.
        UILabel *label = [UILabel new];
        label.text = @"名称";
        label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        label.adjustsFontForContentSizeCategory = YES;
        UITextField *field = [UITextField new];
        field.text = self.entry[@"name"];
        field.placeholder = @"规则名称";
        field.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        field.adjustsFontForContentSizeCategory = YES;
        field.clearButtonMode = UITextFieldViewModeWhileEditing;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
        [field addTarget:self action:@selector(nameChanged:) forControlEvents:UIControlEventEditingChanged];
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[label, field]];
        stack.axis = UILayoutConstraintAxisVertical;
        stack.spacing = 8;
        stack.translatesAutoresizingMaskIntoConstraints = NO;
        [cell.contentView addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.leadingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor],
            [stack.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
            [stack.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:12],
            [stack.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-12],
            [field.heightAnchor constraintGreaterThanOrEqualToConstant:32]
        ]];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    if (indexPath.section == 0) {
        BOOL automatic = indexPath.row == 2;
        cell.textLabel.text = automatic ? @"复制后自动执行" : @"启用规则";
        UISwitch *toggle = [UISwitch new];
        toggle.on = [self.entry[automatic ? @"auto" : @"enabled"] boolValue];
        toggle.accessibilityLabel = cell.textLabel.text;
        [toggle addTarget:self action:automatic ? @selector(autoChanged:) : @selector(enabledChanged:)
            forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    if (indexPath.section == 1) {
        BOOL ai = indexPath.row == 1;
        cell.textLabel.text = ai ? @"AI 编写脚本" : @"沙盒调试台";
        cell.imageView.image = [UIImage systemImageNamed:ai ? @"sparkles" : @"play.circle"];
        cell.imageView.tintColor = ai ? UIColor.systemIndigoColor : UIColor.systemGreenColor;
        if (ai) {
            MTAIEngineInfo *engine = [MTAIEngine currentEngine];
            NSString *model = [MTAIEngine selectedModelForEngine:engine];
            BOOL configured = [MTAIEngine apiKeyForEngine:engine].length && model.length;
            cell.textLabel.textColor = UIColor.systemIndigoColor;
            cell.detailTextLabel.text = [NSString stringWithFormat:@"描述条件 · 多轮修改 · 版本回退\n%@ · %@",
                engine.displayName ?: @"—", configured ? model : @"请先配置 AI 引擎和模型"];
            cell.detailTextLabel.textColor = configured ? UIColor.secondaryLabelColor : UIColor.systemRedColor;
        } else cell.detailTextLabel.text = @"文本 / 图片样例 · 命中结果 · 耗时 · console 日志";
        [MTPJavaScriptPreviewCell alignScriptRow:cell];
        return cell;
    }
    NSArray *actions = self.entry[@"actions"];
    if (indexPath.row == actions.count) {
        cell.textLabel.text = @"添加动作";
        cell.textLabel.textColor = actions.count < 8 ? UIColor.systemBlueColor : UIColor.secondaryLabelColor;
        cell.detailTextLabel.text = actions.count < 8 ? @"从共享自定义动作中选择" : @"最多绑定 8 个动作";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        cell.textLabel.text = [NSString stringWithFormat:@"%ld. %@", (long)indexPath.row + 1, [self nameForActionUUID:actions[indexPath.row]]];
    }
    return cell;
}
- (void)nameChanged:(UITextField *)field { [self setDraftValue:field.text ?: @"" forKey:@"name"]; }
- (void)enabledChanged:(UISwitch *)toggle { [self setDraftValue:@(toggle.on) forKey:@"enabled"]; }
- (void)autoChanged:(UISwitch *)toggle { [self setDraftValue:@(toggle.on) forKey:@"auto"]; }
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 2 && indexPath.row < [self.entry[@"actions"] count];
}
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (style != UITableViewCellEditingStyleDelete || ![self tableView:tableView canEditRowAtIndexPath:indexPath]) return;
    NSMutableArray *actions = [self.entry[@"actions"] mutableCopy];
    [actions removeObjectAtIndex:indexPath.row];
    [self setDraftValue:actions forKey:@"actions"];
    [tableView reloadSections:[NSIndexSet indexSetWithIndex:2] withRowAnimation:UITableViewRowAnimationAutomatic];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    [self.view endEditing:YES];
    __weak typeof(self) weakSelf = self;
    if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            MTPContextScriptEditorController *editor = [MTPContextScriptEditorController new];
            editor.title = @"编辑匹配脚本";
            editor.profile = [MTPAIScriptProfile clipboardProfile];
            editor.source = self.entry[@"source"];
            editor.completion = ^(NSString *source) { [weakSelf updateSource:source]; };
            [self.navigationController pushViewController:editor animated:YES];
        } else if (indexPath.row == 1) {
            MTPAIScriptChatController *chat = [MTPAIScriptChatController new];
            chat.profile = [MTPAIScriptProfile clipboardProfile];
            chat.currentScript = self.entry[@"source"];
            chat.completion = ^(NSString *source) { [weakSelf updateSource:source]; };
            [self.navigationController pushViewController:chat animated:YES];
        } else {
            MTPContextScriptDebugController *debug = [MTPContextScriptDebugController new];
            debug.profile = [MTPAIScriptProfile clipboardProfile];
            debug.source = self.entry[@"source"];
            [self.navigationController pushViewController:debug animated:YES];
        }
    } else if (indexPath.section == 2 && indexPath.row == [self.entry[@"actions"] count] && [self.entry[@"actions"] count] < 8) {
        MTCaptureRuleActionPickerController *picker = [MTCaptureRuleActionPickerController pickerWithExcludedIDs:self.entry[@"actions"]
            completion:^(NSString *uuid) {
                typeof(self) owner = weakSelf;
                if (!owner) return;
                NSMutableArray *actions = [owner.entry[@"actions"] mutableCopy];
                if (![actions containsObject:uuid] && actions.count < 8) [actions addObject:uuid];
                [owner setDraftValue:actions forKey:@"actions"];
                [owner.tableView reloadData];
            }];
        [self.navigationController pushViewController:picker animated:YES];
    }
}
@end

#pragma mark - Action picker

@interface MTCaptureRuleActionPickerController ()
@property (nonatomic, copy) NSArray<NSDictionary *> *candidates;
@property (nonatomic, copy) NSArray<NSString *> *excludedIDs;
@property (nonatomic, copy) void (^completion)(NSString *uuid);
@end

@implementation MTCaptureRuleActionPickerController

+ (instancetype)pickerWithExcludedIDs:(NSArray<NSString *> *)excludedIDs
                           completion:(void (^)(NSString *uuid))completion {
    MTCaptureRuleActionPickerController *picker = [[self alloc] initWithStyle:UITableViewStyleInsetGrouped];
    picker.excludedIDs = excludedIDs;
    picker.completion = completion;
    return picker;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"选择动作";
    [self reloadCandidates];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadCandidates];
}

- (void)reloadCandidates {
    NSMutableArray *candidates = [NSMutableArray array];
    for (NSDictionary *resource in [MTSharedResourceStore readSnapshot][@"actions"]) {
        if (![resource isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *entry = [resource[@"entry"] isKindOfClass:NSDictionary.class] ? resource[@"entry"] : @{};
        if (![MTClipboardActionReferences supportsEntry:entry]) continue;
        if ([self.excludedIDs containsObject:resource[@"id"]]) continue;
        [candidates addObject:@{ @"id": resource[@"id"] ?: @"",
                                 @"name": entry[@"name"] ?: @"未命名动作",
                                 @"type": entry[@"type"] ?: @"urlscheme" }];
    }
    _candidates = candidates;
    [self.tableView reloadData];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_candidates.count;
}

- (NSString *)typeLabel:(NSString *)type {
    NSDictionary *labels = @{ @"url": @"网页", @"urlscheme": @"URL Scheme", @"openapp": @"打开应用",
                              @"shortcut": @"快捷指令", @"system": @"系统动作", @"javascript": @"JS 脚本" };
    return labels[type] ?: @"链接";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"action"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"action"];
    NSDictionary *action = _candidates[(NSUInteger)indexPath.row];
    cell.textLabel.text = action[@"name"];
    cell.detailTextLabel.text = [self typeLabel:action[@"type"]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *uuid = _candidates[(NSUInteger)indexPath.row][@"id"];
    void (^completion)(NSString *) = self.completion;
    self.completion = nil;
    [self.navigationController popViewControllerAnimated:YES];
    if (completion) completion(uuid);
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"动作来自共享动作库（键盘/剪贴板各处共用）；在动作库中删除后，规则中的该位自动失效。";
}

@end