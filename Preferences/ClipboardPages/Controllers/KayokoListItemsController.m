//
//  KayokoListItemsController.m
//  Kayoko
//

#import "KayokoListItemsController.h"
#import "KayokoNotificationKeys.h"
#import "KayokoPreferenceKeys.h"

#import <Preferences/PSSpecifier.h>

@implementation KayokoListItemsController {
    NSMutableSet<NSNumber *> *_selectedIndices;
    ActivationMethod _currentOptions;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    if (!_selectedIndices) {
        _selectedIndices = [NSMutableSet set];
    }

    // Read current configuration value
    id value = [self readPreferenceValue:self.specifier];
    _currentOptions = [value integerValue];
    if (_currentOptions == 0) {
        _currentOptions = kKayokoPreferenceKeyActivationMethodDefaultValue;
    }

    // Initialize selected indices
    [_selectedIndices removeAllObjects];
    NSArray<NSNumber *> *validValues = [self.specifier propertyForKey:@"validValues"];
    for (NSUInteger i = 0; i < validValues.count; i++) {
        NSNumber *value = validValues[i];
        if (_currentOptions & [value integerValue]) {
            [_selectedIndices addObject:@(i)];
        }
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    NSUInteger selectedIndex = indexPath.row;
    NSNumber *indexNumber = @(selectedIndex);
    if ([_selectedIndices containsObject:indexNumber]) {
        if (_selectedIndices.count > 1) {
            [_selectedIndices removeObject:indexNumber];
        } else {            [tableView reloadData];
            return;
        }
    } else {
        [_selectedIndices addObject:indexNumber];
    }
    ActivationMethod newOptions = 0;
    NSArray<NSNumber *> *validValues = [self.specifier propertyForKey:@"validValues"];
    for (NSNumber *index in _selectedIndices) {
        NSNumber *value = validValues[[index integerValue]];
        newOptions |= [value integerValue];
    }

    _currentOptions = newOptions;
    [self setPreferenceValue:@(newOptions) specifier:self.specifier];
    [(PSListController *)self.parentController reloadSpecifiers];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (CFStringRef)kKayokoNotificationKeyPreferencesReload, nil, nil, YES);

    [tableView reloadData];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    if ([_selectedIndices containsObject:@(indexPath.row)]) {
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
    } else {
        cell.accessoryType = UITableViewCellAccessoryNone;
    }

    return cell;
}

@end
