#import <UIKit/UIKit.h>
#import "MTPPathTableCell.h"

// Own the labels/accessory instead of relying on Preferences' private labels
// or its treatment of a getter on PSLinkCell/PSButtonCell.
static inline UITableViewCell *MTPGestureActionCell(UITableView *table, NSString *reuse,
    NSString *title, NSString *record, UIImage *icon, UITableViewCellAccessoryType accessory, PSSpecifier *specifier) {
    MTPPathTableCell *cell = (MTPPathTableCell *)[table dequeueReusableCellWithIdentifier:reuse];
    if (!cell) cell = [[MTPPathTableCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuse];
    cell.specifier = specifier;
    cell.textLabel.text = title;
    cell.textLabel.textColor = UIColor.labelColor;
    cell.detailTextLabel.text = record;
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.imageView.image = icon;
    cell.accessoryView = nil;
    cell.accessoryType = accessory;
    cell.accessibilityTraits &= ~UIAccessibilityTraitSelected;
    if (accessory == UITableViewCellAccessoryCheckmark) cell.accessibilityTraits |= UIAccessibilityTraitSelected;
    return cell;
}
