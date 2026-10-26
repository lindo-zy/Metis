#import "MTPContextAppGroupsController.h"
#import "MTPContextAppGroupEditorController.h"
#import "MTPContextTypesController.h"
#import "MTSettingsNavigation.h"
#import "MTPrefsManager.h"
#import "MTPAppInfo.h"
#import "MTContextTypes.h"
#import "MTContextGroupPreferences.h"

static const NSUInteger MTPAppGroupsLimit = 20;

@interface MTPContextAppGroupsController () <UITableViewDelegate, UITableViewDataSource>
@property(nonatomic, strong) UITableView *table;
@property(nonatomic, strong) NSMutableArray<MTContextAppGroup *> *groups;
@end

@implementation MTPContextAppGroupsController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = MTPCTX(@"CTXAPP_TITLE");
    self.groups = [NSMutableArray array];
    self.table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.table.delegate = self;
    self.table.dataSource = self;
    [self.view addSubview:self.table];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                                                          target:self
                                                                                          action:@selector(addGroup)];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reload];
}

- (void)reload {
    self.groups = [[MTContextAppGroup groupsFromPreferences:[MTPrefsManager.sharedInstance readPrefs]] mutableCopy];
    [self.table reloadData];
}

- (void)save {
    NSMutableArray *items = [NSMutableArray array];
    for (MTContextAppGroup *group in self.groups) [items addObject:group.dictionaryRepresentation];
    [MTPrefsManager.sharedInstance setValue:items forKey:kContextAppGroupsKey];
    [self reload];
}

#pragma mark - 数据展示

// 组名缺失时退到绑定的第一个 App：新建组还没起名时列表不该出现空白行。
- (NSString *)titleForGroup:(MTContextAppGroup *)group {
    if (group.name.length) return group.name;
    if (group.bundleIDs.count) return [MTPAppInfo displayNameForBundleID:group.bundleIDs.firstObject] ?: group.bundleIDs.firstObject;
    return MTPCTX(@"CTXAPP_UNNAMED");
}

- (NSString *)detailForGroup:(MTContextAppGroup *)group {
    NSMutableArray *names = [NSMutableArray array];
    for (NSString *bundleID in group.bundleIDs) {
        [names addObject:[MTPAppInfo displayNameForBundleID:bundleID] ?: bundleID];
        if (names.count == 3) break;
    }
    NSString *apps = names.count ? [names componentsJoinedByString:@"、"] : MTPCTX(@"CTXAPP_UNBOUND");
    if (group.bundleIDs.count > 3) apps = [apps stringByAppendingString:@"…"];
    return [NSString stringWithFormat:MTPCTX(@"CTXAPP_SUMMARY"), apps, (unsigned long)group.actions.count];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.groups.count + 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return MTPCTX(@"CTXAPP_SECTION_GROUPS");
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return MTPCTX(@"CTXAPP_FOOTER");
}

- (UIView *)accessoryViewForGroup:(MTContextAppGroup *)group row:(NSInteger)row {
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 68, 31)];
    UISwitch *toggle = [[UISwitch alloc] initWithFrame:CGRectMake(0, 0, 51, 31)];
    toggle.on = group.enabled;
    toggle.tag = row;
    [toggle addTarget:self action:@selector(toggleGroup:) forControlEvents:UIControlEventValueChanged];
    [container addSubview:toggle];
    UILabel *chevron = [[UILabel alloc] initWithFrame:CGRectMake(53, 0, 14, 31)];
    chevron.text = @"›";
    chevron.font = [UIFont systemFontOfSize:17];
    chevron.textColor = UIColor.tertiaryLabelColor;
    chevron.userInteractionEnabled = NO;
    [container addSubview:chevron];
    return container;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    if (path.row >= (NSInteger)self.groups.count) {
        BOOL room = self.groups.count < MTPAppGroupsLimit;
        cell.textLabel.text = room ? MTPCTX(@"CTXAPP_ADD") : MTPCTX(@"CTXAPP_ADD_LIMIT");
        cell.textLabel.textColor = room ? UIColor.systemBlueColor : UIColor.secondaryLabelColor;
        cell.selectionStyle = room ? UITableViewCellSelectionStyleDefault : UITableViewCellSelectionStyleNone;
        return cell;
    }
    MTContextAppGroup *group = self.groups[path.row];
    cell.textLabel.text = [self titleForGroup:group];
    cell.detailTextLabel.text = [self detailForGroup:group];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessoryView = [self accessoryViewForGroup:group row:path.row];
    return cell;
}

#pragma mark - 编辑

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)path {
    return path.row < (NSInteger)self.groups.count;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)path {
    return path.row < (NSInteger)self.groups.count ? UITableViewCellEditingStyleDelete : UITableViewCellEditingStyleNone;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)path {
    if (style != UITableViewCellEditingStyleDelete || path.row >= (NSInteger)self.groups.count) return;
    [self.groups removeObjectAtIndex:path.row];
    [self save];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (path.row >= (NSInteger)self.groups.count) { [self addGroup]; return; }
    [self pushEditor:self.groups[path.row].identifier];
}

- (void)toggleGroup:(UISwitch *)sender {
    if (sender.tag < 0 || sender.tag >= (NSInteger)self.groups.count) return;
    self.groups[sender.tag].enabled = sender.on;
    [self save];
}

- (void)addGroup {
    if (self.groups.count >= MTPAppGroupsLimit) return;
    MTContextAppGroup *group = [MTContextAppGroup new];
    group.identifier = NSUUID.UUID.UUIDString;
    group.name = @"";
    group.bundleIDs = @[];
    group.actions = @[];
    group.enabled = YES;
    [self.groups addObject:group];
    [self save];
    [self pushEditor:group.identifier];
}

- (void)pushEditor:(NSString *)identifier {
    if (!identifier.length) return;
    MTPContextAppGroupEditorController *editor = [[MTPContextAppGroupEditorController alloc] initWithGroupIdentifier:identifier];
    MTSettingsPushController(self, editor, nil, YES);
}

@end
