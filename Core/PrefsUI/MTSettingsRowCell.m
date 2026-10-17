#import "MTSettingsRowCell.h"
#import "MTSettingsIconTileView.h"
#import "MTSettingsStyle.h"

@implementation MTSettingsRowCell {
    MTSettingsIconTileView *_tile;
    UILabel *_titleLabel;
    UILabel *_subtitleLabel;
    UIStackView *_textStack;
    MTSettingsRow *_currentRow;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:reuseIdentifier]) {
        self.preservesSuperviewLayoutMargins = NO;
        self.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
        self.selectionStyle = UITableViewCellSelectionStyleDefault;

        _tile = [[MTSettingsIconTileView alloc] initWithFrame:CGRectMake(0, 0, [MTSettingsStyle tileSide], [MTSettingsStyle tileSide])];
        _tile.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_tile];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
        _titleLabel.adjustsFontForContentSizeCategory = YES;

        _subtitleLabel = [[UILabel alloc] init];
        _subtitleLabel.font = [UIFont systemFontOfSize:13.0];
        _subtitleLabel.textColor = UIColor.secondaryLabelColor;
        _subtitleLabel.numberOfLines = 2;
        _subtitleLabel.adjustsFontForContentSizeCategory = YES;

        _textStack = [[UIStackView alloc] initWithArrangedSubviews:@[_titleLabel, _subtitleLabel]];
        _textStack.axis = UILayoutConstraintAxisVertical;
        _textStack.spacing = 2.0;
        _textStack.translatesAutoresizingMaskIntoConstraints = NO;
        [self.contentView addSubview:_textStack];

        [NSLayoutConstraint activateConstraints:@[
            [_tile.leadingAnchor constraintEqualToAnchor:self.contentView.layoutMarginsGuide.leadingAnchor],
            [_tile.centerYAnchor constraintEqualToAnchor:self.contentView.centerYAnchor],
            [_tile.widthAnchor constraintEqualToConstant:[MTSettingsStyle tileSide]],
            [_tile.heightAnchor constraintEqualToConstant:[MTSettingsStyle tileSide]],
            [_textStack.leadingAnchor constraintEqualToAnchor:_tile.trailingAnchor constant:12.0],
            [_textStack.trailingAnchor constraintLessThanOrEqualToAnchor:self.contentView.layoutMarginsGuide.trailingAnchor],
            [_textStack.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:8.0],
            [_textStack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-8.0],
        ]];
    }
    return self;
}

- (void)configureWithRow:(MTSettingsRow *)row {
    [self prepareForReuse];
    _currentRow = row;
    _titleLabel.text = row.title;
    _subtitleLabel.text = row.subtitle;
    _subtitleLabel.hidden = (row.subtitle.length == 0);
    [_tile updateWithIconName:row.iconName colorName:row.colorName];

    // 分隔线随行内边距走：有瓦片时与标题对齐，无瓦片时用标准边距。
    BOOL hasTile = !(_tile.hidden);
    self.layoutMargins = hasTile ? UIEdgeInsetsMake(0, 16.0 + [MTSettingsStyle tileSide] + 12.0, 0, 16.0)
                                 : UIEdgeInsetsMake(0, 16.0, 0, 16.0);
    self.separatorInset = self.layoutMargins;

    switch (row.kind) {
        case MTSettingsRowKindToggle: {
            UISwitch *toggle = [[UISwitch alloc] init];
            // 初始状态由模型层经 userInfo（NSNumber）提供；缺省按关处理。
            toggle.on = [row.userInfo respondsToSelector:@selector(boolValue)]
                ? [row.userInfo boolValue] : NO;
            // UISwitch 无 block API：target 指回 cell，按配置时的行查 handler。
            [toggle addTarget:self action:@selector(mtSwitchChanged:)
                     forControlEvents:UIControlEventValueChanged];
            self.accessoryView = toggle;
            self.accessoryType = UITableViewCellAccessoryNone;
            self.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
        }
        case MTSettingsRowKindInfo:
            self.accessoryView = nil;
            self.accessoryType = UITableViewCellAccessoryNone;
            self.selectionStyle = UITableViewCellSelectionStyleNone;
            break;
        case MTSettingsRowKindLink:
        default:
            self.accessoryView = nil;
            self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            self.selectionStyle = UITableViewCellSelectionStyleDefault;
            break;
    }

    // VoiceOver（02 §8）：link/info 行标题+摘要合并朗读并带按钮特征；
    // toggle 行让 VoiceOver 直接聚焦开关本身。
    if (row.kind == MTSettingsRowKindToggle) {
        self.isAccessibilityElement = NO;
        self.accessibilityElements = self.accessoryView ? @[self.accessoryView] : nil;
    } else {
        self.isAccessibilityElement = YES;
        self.accessibilityLabel = row.subtitle.length
            ? [NSString stringWithFormat:@"%@，%@", row.title, row.subtitle] : row.title;
        self.accessibilityTraits = UIAccessibilityTraitButton;
        self.accessibilityElements = nil;
    }
}

- (void)prepareForReuse {
    [super prepareForReuse];
    _currentRow = nil;
    self.accessoryView = nil;
    self.accessoryType = UITableViewCellAccessoryNone;
    self.selectionStyle = UITableViewCellSelectionStyleDefault;
    self.accessibilityLabel = nil;
    self.accessibilityElements = nil;
    self.isAccessibilityElement = NO;
    self.accessibilityTraits = UIAccessibilityTraitNone;
}

- (void)mtSwitchChanged:(UISwitch *)sender {
    if (_currentRow.toggleHandler) _currentRow.toggleHandler(sender.on);
}

@end
