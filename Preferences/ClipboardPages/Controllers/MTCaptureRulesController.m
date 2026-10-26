//
//  MTCaptureRulesController.m
//  Mt
//

#import "MTCaptureRulesController.h"

#import "MTCaptureRuleEngine.h"
#import "MTClipboardActionReferences.h"
#import "MTContextScriptEditorController.h"
#import "MTSharedResourceStore.h"

// 规则顺序即求值顺序，首个命中的规则生效；未命中不执行任何动作。
// 动作引用共享资源动作库 UUID，执行端（MTQuickAction）在执行时再解析并校验，
// 删除动作库条目后规则该位自动失效，不需要在这里做悬挂引用清理。

@class MTCaptureRuleEditorController;
@class MTCaptureRuleActionPickerController;

@interface MTCaptureRuleEditorController : UITableViewController
- (instancetype)initWithRule:(MTCaptureRule *)rule;
@property (nonatomic, copy, nullable) void (^onSaved)(void);
@end

@interface MTCaptureRuleActionPickerController : UITableViewController
+ (instancetype)pickerWithExcludedIDs:(NSArray<NSString *> *)excludedIDs
                           completion:(void (^)(NSString *uuid))completion;
@end

#pragma mark - Rule list

@interface MTCaptureRuleCell : UITableViewCell
@end
@implementation MTCaptureRuleCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    return [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
}
@end

@implementation MTCaptureRulesController {
    UITableView *_table;
    NSArray<MTCaptureRule *> *_rules;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"剪切板规则";
    _table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    _table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _table.delegate = self;
    _table.dataSource = self;
    [self.view addSubview:_table];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"编辑"
        style:UIBarButtonItemStylePlain target:self action:@selector(toggleEditing)];
    [self reloadRules];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadRules];
}

- (void)toggleEditing {
    BOOL editing = !_table.editing;
    [_table setEditing:editing animated:YES];
    [self.navigationItem.rightBarButtonItem setTitle:editing ? @"完成" : @"编辑"];
}

- (void)reloadRules {
    _rules = [MTCaptureRule rulesFromDictionaries:
        [MTClipboardActionReferences ruleDictionariesInDocument:[MTSharedResourceStore readSnapshot]]];
    [_table reloadData];
}

// 读-改-写：以最新快照与 revision 提交，替换/插入/删除/重排同一条路径。
// 提交失败必须让用户看到，不允许静默回退（否则表现为「保存无效」）。
- (BOOL)commitRulesWithMutation:(NSArray<NSDictionary *> *(^)(NSMutableArray<NSDictionary *> *current))mutation {
    NSDictionary *current = [MTSharedResourceStore readSnapshot];
    NSMutableArray<NSDictionary *> *rules =
        [[MTClipboardActionReferences ruleDictionariesInDocument:current] mutableCopy] ?: [NSMutableArray array];
    NSArray<NSDictionary *> *next = mutation(rules) ?: rules;
    NSError *error = nil;
    BOOL saved = [MTSharedResourceStore commitSnapshot:
        [MTClipboardActionReferences document:current settingRuleDictionaries:next]
        expectedRevision:[MTSharedResourceStore currentRevision] error:&error];
    if (!saved) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"保存失败"
            message:error.localizedDescription ?: @"配置已被其他窗口修改，请返回后重试。"
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
    [self reloadRules];
    return saved;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)_rules.count + 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    MTCaptureRuleCell *cell = [tableView dequeueReusableCellWithIdentifier:@"rule"];
    if (!cell) cell = [[MTCaptureRuleCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"rule"];
    NSUInteger index = (NSUInteger)indexPath.row;
    if (index >= _rules.count) {
        cell.textLabel.text = @"添加规则";
        cell.textLabel.textColor = _rules.count < 32 ? UIColor.systemBlueColor : UIColor.secondaryLabelColor;
        cell.detailTextLabel.text = _rules.count < 32 ? @"复制后或双击气泡时，按 JS 条件执行绑定的动作" : nil;
        cell.accessoryType = _rules.count < 32 ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
        cell.editingAccessoryType = UITableViewCellAccessoryNone;
        return cell;
    }
    MTCaptureRule *rule = _rules[index];
    cell.textLabel.text = rule.name.length ? rule.name : [NSString stringWithFormat:@"规则 %lu", (unsigned long)index + 1];
    cell.textLabel.textColor = rule.enabled ? UIColor.labelColor : UIColor.secondaryLabelColor;
    NSMutableString *summary = [NSMutableString string];
    if (rule.autoRun) [summary appendString:@"自动执行 · "];
    [summary appendFormat:@"%lu 个动作", (unsigned long)rule.actions.count];
    if (!rule.enabled) [summary appendString:@" · 已停用"];
    cell.detailTextLabel.text = summary;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.editingAccessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.row < (NSInteger)_rules.count;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.row < (NSInteger)_rules.count;
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath
      toIndexPath:(NSIndexPath *)destinationIndexPath {
    NSString *identifier = _rules[sourceIndexPath.row].identifier;
    [self commitRulesWithMutation:^NSArray<NSDictionary *> *(NSMutableArray<NSDictionary *> *current) {
        NSDictionary *entry = nil;
        for (NSUInteger i = 0; i < current.count; i++) {
            if ([current[i][@"id"] isEqual:identifier]) {
                entry = current[i];
                [current removeObjectAtIndex:i];
                break;
            }
        }
        if (!entry) return current;
        NSUInteger target = MIN((NSUInteger)destinationIndexPath.row, current.count);
        [current insertObject:entry atIndex:target];
        return current;
    }];
}

- (void)tableView:(UITableView *)tableView
    commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
     forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete || indexPath.row >= (NSInteger)_rules.count) return;
    NSString *identifier = _rules[indexPath.row].identifier;
    [self commitRulesWithMutation:^NSArray<NSDictionary *> *(NSMutableArray<NSDictionary *> *current) {
        for (NSUInteger i = 0; i < current.count; i++) {
            if ([current[i][@"id"] isEqual:identifier]) {
                [current removeObjectAtIndex:i--];
            }
        }
        return current;
    }];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row >= (NSInteger)_rules.count) {
        if (_rules.count < 32) [self addRule];
        return;
    }
    MTCaptureRuleEditorController *editor = [[MTCaptureRuleEditorController alloc] initWithRule:_rules[indexPath.row]];
    editor.onSaved = ^{
        [self reloadRules];
    };
    [self.navigationController pushViewController:editor animated:YES];
}

- (void)addRule {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"新规则"
        message:@"规则在双击气泡（及自动执行）时按顺序求值，match(text, meta) 返回真即命中。"
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = @"规则名称（如：打开链接）";
    }];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"创建" style:UIAlertActionStyleDefault handler:^
        __unused (UIAlertAction *action) {
        NSString *name = [alert.textFields.firstObject.text
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
        [weakSelf commitRulesWithMutation:^NSArray<NSDictionary *> *(NSMutableArray<NSDictionary *> *current) {
            [current addObject:@{ @"id": [NSUUID UUID].UUIDString,
                                  @"name": name,
                                  @"enabled": @YES, @"auto": @NO,
                                  @"source": @"function match(text, meta) {\n  return false;\n}",
                                  @"actions": @[] }];
            return current;
        }];
    }];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"按顺序求值，首个命中的规则生效；未命中不执行任何动作。双击采集气泡执行，"
            "「复制后自动执行」需在规则上单独开启。脚本运行在沙盒中：无 Date / Math.random，"
            "超时 50ms，连续报错 3 次的规则自动停用。";
}

@end

#pragma mark - Editor

@interface MTCaptureRuleEditorController ()
@property (nonatomic, copy) NSDictionary *entry;
@end

@implementation MTCaptureRuleEditorController {
    NSArray<NSDictionary *> *_libraryActions;
}

- (instancetype)initWithRule:(MTCaptureRule *)rule {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _entry = rule.dictionaryRepresentation;
        self.title = rule.name.length ? rule.name : @"编辑规则";
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"保存"
        style:UIBarButtonItemStyleDone target:self action:@selector(commit)];
    [self reloadLibrary];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadLibrary];
    [self.tableView reloadData];
}

// 动作库列表：仅列执行端支持的类型（与槽位选择页同一判据）。
- (void)reloadLibrary {
    NSMutableArray *library = [NSMutableArray array];
    for (NSDictionary *resource in [MTSharedResourceStore readSnapshot][@"actions"]) {
        if (![resource isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *entry = [resource[@"entry"] isKindOfClass:NSDictionary.class] ? resource[@"entry"] : @{};
        if (![MTClipboardActionReferences supportsEntry:entry]) continue;
        [library addObject:@{ @"id": resource[@"id"] ?: @"",
                              @"name": entry[@"name"] ?: @"未命名动作",
                              @"type": entry[@"type"] ?: @"urlscheme" }];
    }
    _libraryActions = library;
}

// 每次编辑都整体替换同 id 条目后提交；与列表页共用一次 CAS 写。
- (void)commit {
    NSDictionary *current = [MTSharedResourceStore readSnapshot];
    NSMutableArray<NSDictionary *> *rules =
        [[MTClipboardActionReferences ruleDictionariesInDocument:current] mutableCopy] ?: [NSMutableArray array];
    BOOL replaced = NO;
    for (NSUInteger i = 0; i < rules.count; i++) {
        if ([rules[i][@"id"] isEqual:self.entry[@"id"]]) {
            rules[i] = self.entry;
            replaced = YES;
            break;
        }
    }
    if (!replaced) [rules addObject:self.entry];
    NSError *error = nil;
    BOOL saved = [MTSharedResourceStore commitSnapshot:
        [MTClipboardActionReferences document:current settingRuleDictionaries:rules]
        expectedRevision:[MTSharedResourceStore currentRevision] error:&error];
    if (!saved) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"保存失败"
            message:error.localizedDescription ?: @"配置已被其他窗口修改，请返回后重试。"
            preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    if (self.onSaved) self.onSaved();
}

- (void)replaceEntry:(NSDictionary *)entry {
    self.entry = entry;
    self.title = [entry[@"name"] length] ? entry[@"name"] : @"编辑规则";
}

- (NSString *)nameForActionUUID:(NSString *)uuid {
    for (NSDictionary *action in _libraryActions) {
        if ([action[@"id"] isEqual:uuid]) return action[@"name"];
    }
    return nil;
}

- (void)removeActionAtIndex:(NSUInteger)index {
    NSMutableArray *actions = [self.entry[@"actions"] mutableCopy];
    if (index >= actions.count) return;
    [actions removeObjectAtIndex:index];
    [self replaceEntry:[@{ @"id": self.entry[@"id"], @"name": self.entry[@"name"] ?: @"",
                           @"enabled": self.entry[@"enabled"] ?: @YES, @"auto": self.entry[@"auto"] ?: @NO,
                           @"source": self.entry[@"source"] ?: @"", @"actions": actions } mutableCopy]];
    [self commit];
}

- (void)confirmRemoveActionAtIndex:(NSUInteger)index {
    NSString *name = [self nameForActionUUID:self.entry[@"actions"][index]] ?: @"该动作";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:name
        message:@"从规则中移除该动作？动作库条目不受影响。" preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"移除" style:UIAlertActionStyleDestructive handler:^
        __unused (UIAlertAction *action) {
        [weakSelf removeActionAtIndex:index];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 3;                       // 名称 / 启用 / 自动执行
    if (section == 1) return 1;                       // 匹配脚本
    return (NSInteger)self.entry[@"actions"].count + 1;  // 动作 + 添加
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 1) return @"匹配条件";
    if (section == 2) return @"命中的动作（按序执行）";
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"「复制后自动执行」还需在剪切板设置根页打开总开关（默认关闭）。";
    if (section == 1) return @"meta.kind 为 \"text\"（文本）或 \"image\"（图片）。";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"cell"];
    cell.textLabel.textColor = UIColor.labelColor;
    cell.accessoryView = nil;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.detailTextLabel.text = nil;
    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"名称";
            UITextField *field = [cell.contentView viewWithTag:101];
            if (!field) {
                field = [[UITextField alloc] initWithFrame:CGRectZero];
                field.tag = 101;
                field.placeholder = @"规则名称";
                field.clearButtonMode = UITextFieldViewModeWhileEditing;
                field.autocorrectionType = UITextAutocorrectionTypeNo;
                field.translatesAutoresizingMaskIntoConstraints = NO;
                [field addTarget:self action:@selector(nameChanged:) forControlEvents:UIControlEventEditingChanged];
                [cell.contentView addSubview:field];
                [NSLayoutConstraint activateConstraints:@[
                    [field.leadingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor],
                    [field.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
                    [field.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor],
                    [field.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor] ]];
            }
            field.text = self.entry[@"name"];
        } else {
            // 名称行 cell 可能被复用到开关行，先摘掉残留的输入框。
            [[cell.contentView viewWithTag:101] removeFromSuperview];
            BOOL isAuto = indexPath.row == 2;
            cell.textLabel.text = isAuto ? @"复制后自动执行" : @"启用";
            UISwitch *toggle = [[UISwitch alloc] initWithFrame:CGRectZero];
            toggle.on = [self.entry[isAuto ? @"auto" : @"enabled"] boolValue];
            [toggle addTarget:self action:(isAuto ? @selector(autoChanged:) : @selector(enabledChanged:))
                     forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = toggle;
        }
        return cell;
    }
    if (indexPath.section == 1) {
        NSString *source = self.entry[@"source"] ?: @"";
        cell.textLabel.text = @"编辑匹配脚本";
        cell.detailTextLabel.text = source.length
            ? [NSString stringWithFormat:@"%lu 行", (unsigned long)[source componentsSeparatedByString:@"\n"].count]
            : @"未设置";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    NSArray *actions = self.entry[@"actions"];
    if (indexPath.row >= (NSInteger)actions.count) {
        cell.textLabel.text = @"添加动作";
        cell.textLabel.textColor = actions.count < 8 ? UIColor.systemBlueColor : UIColor.secondaryLabelColor;
        return cell;
    }
    NSString *uuid = actions[indexPath.row];
    NSString *name = [self nameForActionUUID:uuid];
    cell.textLabel.text = name ?: @"已删除的动作";
    cell.textLabel.textColor = name ? UIColor.labelColor : UIColor.secondaryLabelColor;
    cell.accessoryType = UITableViewCellAccessoryDetailButton;
    return cell;
}

- (void)nameChanged:(UITextField *)field {
    NSString *name = [field.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    [self replaceEntry:[@{ @"id": self.entry[@"id"], @"name": name,
                           @"enabled": self.entry[@"enabled"] ?: @YES, @"auto": self.entry[@"auto"] ?: @NO,
                           @"source": self.entry[@"source"] ?: @"", @"actions": self.entry[@"actions"] ?: @[] } mutableCopy]];
}

- (void)enabledChanged:(UISwitch *)toggle {
    [self replaceEntry:[@{ @"id": self.entry[@"id"], @"name": self.entry[@"name"] ?: @"",
                           @"enabled": @(toggle.on), @"auto": self.entry[@"auto"] ?: @NO,
                           @"source": self.entry[@"source"] ?: @"", @"actions": self.entry[@"actions"] ?: @[] } mutableCopy]];
    [self commit];
}

- (void)autoChanged:(UISwitch *)toggle {
    [self replaceEntry:[@{ @"id": self.entry[@"id"], @"name": self.entry[@"name"] ?: @"",
                           @"enabled": self.entry[@"enabled"] ?: @YES, @"auto": @(toggle.on),
                           @"source": self.entry[@"source"] ?: @"", @"actions": self.entry[@"actions"] ?: @[] } mutableCopy]];
    [self commit];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1) {
        MTPContextScriptEditorController *editor = [MTPContextScriptEditorController new];
        editor.source = self.entry[@"source"] ?: @"";
        __weak typeof(self) weakSelf = self;
        editor.completion = ^(NSString *source) {
            [weakSelf replaceEntry:[@{ @"id": weakSelf.entry[@"id"], @"name": weakSelf.entry[@"name"] ?: @"",
                                       @"enabled": weakSelf.entry[@"enabled"] ?: @YES,
                                       @"auto": weakSelf.entry[@"auto"] ?: @NO,
                                       @"source": source ?: @"",
                                       @"actions": weakSelf.entry[@"actions"] ?: @[] } mutableCopy]];
            [weakSelf commit];
        };
        [self.navigationController pushViewController:editor animated:YES];
        return;
    }
    if (indexPath.section != 2) return;
    NSArray *actions = self.entry[@"actions"];
    if (indexPath.row >= (NSInteger)actions.count) {
        if (actions.count >= 8) return;
        MTCaptureRuleActionPickerController *picker =
            [MTCaptureRuleActionPickerController pickerWithExcludedIDs:actions
                                                            completion:^(NSString *uuid) {
            NSMutableArray *next = [weakSelf.entry[@"actions"] mutableCopy] ?: [NSMutableArray array];
            [next addObject:uuid];
            [weakSelf replaceEntry:[@{ @"id": weakSelf.entry[@"id"], @"name": weakSelf.entry[@"name"] ?: @"",
                                       @"enabled": weakSelf.entry[@"enabled"] ?: @YES,
                                       @"auto": weakSelf.entry[@"auto"] ?: @NO,
                                       @"source": weakSelf.entry[@"source"] ?: @"", @"actions": next } mutableCopy]];
            [weakSelf commit];
        }];
        [self.navigationController pushViewController:picker animated:YES];
        return;
    }
    [self confirmRemoveActionAtIndex:(NSUInteger)indexPath.row];
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
    MTCaptureRuleActionPickerController *picker = [self new];
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