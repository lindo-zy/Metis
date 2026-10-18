#import "MTCustomJumpManagementViewController.h"
#import "MTClipboardActionReferences.h"
#import "MTSharedResourceStore.h"
#import "MTPrefsManager.h"
#import "MTPreferenceKeys.h"
#import <roothide.h>

@interface MTCustomJumpManagementViewController () <UITableViewDataSource, UITableViewDelegate>
@property(nonatomic, strong) UITableView *tableView;
@property(nonatomic, copy) NSDictionary *snapshot;
@property(nonatomic, copy) NSArray<NSDictionary *> *availableActions;
@property(nonatomic, strong) NSMutableArray<NSString *> *selectedIDs;
@end

@implementation MTCustomJumpManagementViewController

+ (BOOL)isImageActionManagement { return NO; }
+ (NSString *)referenceSlot { return [self isImageActionManagement] ? @"image" : @"text"; }

+ (BOOL)prepareSharedActionsWithError:(NSError **)error {
    // Settings owns migration and all writes; runtime only resolves published bindings.
    [MTPrefsManager.sharedInstance readPrefs];
    NSDictionary *snapshot = [MTSharedResourceStore readSnapshotError:error];
    if (!snapshot) return NO;
    if ([snapshot[@"migration"][@"clipboardActionReferencesV1"] boolValue]) return YES;
    NSMutableArray *legacy = [NSMutableArray array];
    for (NSString *name in @[@"custom-jumps-v1.plist", @"image-actions-v1.plist"]) {
        NSString *path = [jbroot(@"/var/mobile/Library/com.lindo.metis.clipboard") stringByAppendingPathComponent:name];
        NSArray *items = @[];
        if ([NSFileManager.defaultManager fileExistsAtPath:path]) {
            NSData *data = [NSData dataWithContentsOfFile:path options:0 error:error];
            if (!data) return NO;
            id plist = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:error];
            if (![plist isKindOfClass:NSArray.class]) {
                if (error && !*error) *error = [NSError errorWithDomain:@"MetisClipboardMigration" code:1
                    userInfo:@{NSLocalizedDescriptionKey: @"旧动作文件无法读取，已保留原文件。"}];
                return NO;
            }
            items = plist;
        }
        [legacy addObject:items];
    }
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:kMTClipboardPreferencesIdentifier];
    NSDictionary *next = [MTClipboardActionReferences document:snapshot importingText:legacy[0] image:legacy[1]
        doubleTapURL:[defaults stringForKey:kMTPreferenceKeyImageDoubleTapActionURL] ?: @""];
    return [MTSharedResourceStore commitSnapshot:next expectedRevision:[snapshot[@"revision"] unsignedLongLongValue] error:error];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    NSString *slot = [self.class referenceSlot];
    self.title = [slot isEqual:@"image-double-tap"] ? @"图片双击动作" :
        ([self.class isImageActionManagement] ? @"图片动作" : @"文字动作");
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"排序"
        style:UIBarButtonItemStylePlain target:self action:@selector(toggleOrdering)];
    if ([slot isEqual:@"image-double-tap"]) self.navigationItem.rightBarButtonItem = nil;
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 60;
    [self.view addSubview:self.tableView];
    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]
    ]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setToolbarHidden:YES animated:animated];
    NSError *error = nil;
    if (![self.class prepareSharedActionsWithError:&error]) {
        [self showError:error];
    }
    [self reloadReferences];
}

- (void)reloadReferences {
    self.snapshot = [MTSharedResourceStore readSnapshot];
    NSMutableArray *available = [NSMutableArray array];
    for (NSDictionary *action in self.snapshot[@"actions"]) {
        if ([MTClipboardActionReferences supportsEntry:action[@"entry"]]) [available addObject:action];
    }
    self.availableActions = available;
    self.selectedIDs = [NSMutableArray array];
    for (NSDictionary *entry in [MTClipboardActionReferences actionsInDocument:self.snapshot slot:[self.class referenceSlot]]) {
        [self.selectedIDs addObject:entry[@"id"]];
    }
    [self.tableView reloadData];
}

- (void)toggleOrdering {
    self.tableView.editing = !self.tableView.editing;
    self.navigationItem.rightBarButtonItem.title = self.tableView.editing ? @"完成" : @"排序";
}

- (BOOL)saveReferences {
    NSError *error = nil;
    BOOL saved = [MTClipboardActionReferences setActionIDs:self.selectedIDs slot:[self.class referenceSlot]
        expectedRevision:[self.snapshot[@"revision"] unsignedLongLongValue] error:&error];
    if (!saved) [self showError:error];
    [self reloadReferences];
    return saved;
}

- (void)showError:(NSError *)error {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"动作引用未保存"
        message:error.localizedDescription ?: @"全局动作暂不可用，请返回后重试。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? self.selectedIDs.count : self.availableActions.count;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"已引用动作" : @"从全局动作选择";
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return self.selectedIDs.count ? @"轻点可取消引用。" : @"尚未引用动作。";
    return @"动作统一在“全局 → 自定义动作”中创建和编辑；此处只保存引用。文本插入需要输入框；JavaScript 需使用剪切板输入和复制输出。";
}
- (NSDictionary *)actionAtIndexPath:(NSIndexPath *)path {
    if (path.section == 1) return self.availableActions[path.row];
    NSString *uuid = self.selectedIDs[path.row];
    for (NSDictionary *action in self.availableActions) if ([action[@"id"] isEqual:uuid]) return action;
    return nil;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SharedClipboardAction"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"SharedClipboardAction"];
    NSDictionary *action = [self actionAtIndexPath:path];
    NSDictionary *entry = action[@"entry"];
    cell.textLabel.text = entry[@"name"] ?: @"未命名动作";
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.text = entry[@"type"] ?: @"URL Scheme";
    cell.imageView.image = [UIImage systemImageNamed:entry[@"icon"] ?: @"link"] ?: [UIImage systemImageNamed:@"link"];
    cell.accessoryType = [self.selectedIDs containsObject:action[@"id"]] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    NSString *uuid = [self actionAtIndexPath:path][@"id"];
    if (!uuid) return;
    if ([self.selectedIDs containsObject:uuid]) [self.selectedIDs removeObject:uuid];
    else {
        if ([[self.class referenceSlot] isEqual:@"image-double-tap"]) [self.selectedIDs removeAllObjects];
        [self.selectedIDs addObject:uuid];
    }
    [self saveReferences];
}
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)path { return path.section == 0; }
- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)path {
    return UITableViewCellEditingStyleNone;
}
- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)path { return NO; }
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)path { return path.section == 0; }
- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)source
    toProposedIndexPath:(NSIndexPath *)target { return target.section == 0 ? target : source; }
- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)source toIndexPath:(NSIndexPath *)target {
    NSString *uuid = self.selectedIDs[source.row];
    [self.selectedIDs removeObjectAtIndex:source.row];
    [self.selectedIDs insertObject:uuid atIndex:target.row];
    [self saveReferences];
}
@end
