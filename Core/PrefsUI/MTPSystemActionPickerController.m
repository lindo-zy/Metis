#import "MTPSystemActionPickerController.h"
#import "MTSystemActionCatalog.h"
#import "common.h"
#import "MTCaptureIntegration.h"

static NSBundle *mtpLocalBundle;

@interface MTPSystemActionPickerController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, copy) NSArray<NSArray<NSDictionary *> *> *groups;
@end

@implementation MTPSystemActionPickerController
- (void)viewDidLoad {
    [super viewDidLoad];
    mtpLocalBundle = [NSBundle bundleWithPath:bundlePath];
    self.title = LOCALIZED(@"SELECT_SYSTEM_ACTION");
    UITableView *table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    table.dataSource = self;
    table.delegate = self;
    self.view = table;
}
- (void)reloadActions {
    NSMutableArray *groups = [NSMutableArray array];
    NSArray *catalog = MTVisibleSystemActionCatalog(MTCaptureInstalledAtPath(MT_ROOT_PATH_NS(MTCaptureDylibPath)));
    for (NSString *group in @[@"media", @"device", @"control", @"pixpin"]) {
        NSMutableArray *rows = [NSMutableArray array];
        for (NSDictionary *action in catalog)
            if ([action[@"group"] isEqual:group]) [rows addObject:action];
        if (rows.count) [groups addObject:rows];
    }
    self.groups = groups;
    [(UITableView *)self.view reloadData];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadActions];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { return self.groups.count; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return self.groups[section].count; }
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section {
    NSString *key = @[@"SYSTEM_GROUP_MEDIA", @"SYSTEM_GROUP_DEVICE", @"SYSTEM_GROUP_CONTROL", @"SYSTEM_GROUP_PIXPIN"][section];
    return LOCALIZED(key);
}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    return section == 1 ? LOCALIZED(@"SYSTEM_DEVICE_FOOTER") : section == 2 ? LOCALIZED(@"SYSTEM_RECORDING_FOOTER") : nil;
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [table dequeueReusableCellWithIdentifier:@"SystemAction"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"SystemAction"];
    NSDictionary *action = self.groups[path.section][path.row];
    cell.textLabel.text = LOCALIZED(action[@"title"]);
    cell.imageView.image = [UIImage systemImageNamed:action[@"icon"]];
    cell.accessoryType = [self.selectedIdentifier isEqual:action[@"id"]] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES];
    NSDictionary *action = self.groups[path.section][path.row];
    if (action[@"captureNotification"] && !MTCaptureInstalledAtPath(MT_ROOT_PATH_NS(MTCaptureDylibPath))) {
        [self reloadActions];
        return;
    }
    if (self.completion) self.completion(action);
    [self.navigationController popViewControllerAnimated:YES];
}
@end
