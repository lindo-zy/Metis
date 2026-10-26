#import "MTPJavaScriptPreviewCell.h"
#import "MTPJavaScriptCodeStyle.h"
#import "MTSettingsStyle.h"
#import "common.h"

static NSString *MTPJSPreviewLabel(NSString *key) {
    return NSLocalizedStringFromTableInBundle(key, nil, [NSBundle bundleWithPath:bundlePath], nil);
}

@implementation MTPJavaScriptPreviewCell

- (instancetype)initWithSource:(NSString *)source usage:(NSString *)usage invalid:(BOOL)invalid {
    self = [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    if (!self) return nil;
    NSArray<NSString *> *lines = [source componentsSeparatedByString:@"\n"];
    NSUInteger limit = 7;
    NSString *snippet = [[lines subarrayWithRange:NSMakeRange(0, MIN(limit, lines.count))]
        componentsJoinedByString:@"\n"];
    if (lines.count > limit) snippet = [snippet stringByAppendingString:@"\n…"];
    if (!snippet.length) snippet = MTPJSPreviewLabel(@"CTX_SCRIPT_EMPTY");
    self.textLabel.numberOfLines = 0;
    self.textLabel.attributedText = [MTPJavaScriptCodeStyle attributedStringForSource:snippet];
    self.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    self.detailTextLabel.text = [usage stringByAppendingFormat:@" · %@",
        MTPJSPreviewLabel(invalid ? @"CTX_SCRIPT_FAIL" : @"CTX_EDIT_SCRIPT")];
    self.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
    self.detailTextLabel.textColor = invalid ? UIColor.systemRedColor : UIColor.secondaryLabelColor;
    [self.class alignScriptRow:self];
    return self;
}

+ (void)alignScriptRow:(UITableViewCell *)cell {
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.editingAccessoryType = UITableViewCellAccessoryDisclosureIndicator;
    CGFloat inset = [MTSettingsStyle contentInset];
    cell.separatorInset = UIEdgeInsetsMake(0, inset, 0, inset);
}

@end
