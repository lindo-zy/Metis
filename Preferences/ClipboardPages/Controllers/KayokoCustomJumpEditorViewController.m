//
//  KayokoCustomJumpEditorViewController.m
//  Kayoko
//

#import "KayokoCustomJumpEditorViewController.h"

#import "KayokoAppPickerController.h"
#import "KayokoAppInfo.h"
#import "KayokoCustomJump.h"
#import "KayokoKeyboardAvoidanceCoordinator.h"
#import "KayokoShortcutPickerController.h"

// Typed rows. 类型/名称/图标 are shared by every type; the payload row depends
// on the entry's type. The URL Scheme payload moves below the icon row as a
// full-width multi-line text box (a second section), 打开应用 / 快捷方式 render
// picker rows instead of free-text fields. Entries stored before typed
// actions existed carry no type and keep the legacy 名称/图标/跳转链接 layout.
static NSInteger const kKayokoActionRowType = 0;
static NSInteger const kKayokoActionRowName = 1;
static NSInteger const kKayokoActionRowIcon = 2;
static NSInteger const kKayokoActionRowPayload = 3;

static NSInteger const kKayokoLegacyRowName = 0;
static NSInteger const kKayokoLegacyRowIcon = 1;
static NSInteger const kKayokoLegacyRowLink = 2;

@interface KayokoCustomJumpEditorViewController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate,
                                                    UITextViewDelegate>
@property(nonatomic, strong) KayokoCustomJump *jump;
@property(nonatomic, strong) NSBundle *localizationBundle;
@property(nonatomic, assign, getter=isImageAction) BOOL imageAction;
@property(nonatomic, strong) UITableView *tableView;
@property(nonatomic, strong) UITextField *titleTextField;
@property(nonatomic, strong) UITextField *linkTextField;
@property(nonatomic, strong) UITextField *iconTextField;
@property(nonatomic, strong) UITextView *payloadTextView;
@property(nonatomic, strong) UILabel *payloadPlaceholderLabel;
@property(nonatomic, strong) UITableViewCell *payloadBoxCell;
@property(nonatomic, strong) UIView *iconPreviewContainer;
@property(nonatomic, strong) UIImageView *iconPreviewImageView;
@property(nonatomic, strong) KayokoKeyboardAvoidanceCoordinator *keyboardAvoidanceCoordinator;
@property(nonatomic, assign) BOOL didFocusTitleTextFieldInitially;
// The type is fixed for the life of the entry (chosen in the add flow's type
// chooser); the 类型 row only displays it. nil keeps the legacy editor.
@property(nonatomic, copy, nullable) NSString *displayedType;
// Pending picker result for the shortcut payload; committed to the jump on
// save together with the rest of the entry.
@property(nonatomic, copy, nullable) NSString *pendingShortcutType;
// Picked payload link for the picker types (bundle identifier).
@property(nonatomic, copy, nullable) NSString *pickedLink;
@end

@implementation KayokoCustomJumpEditorViewController

#pragma mark - Lifecycle

- (instancetype)initWithJump:(KayokoCustomJump *)jump localizationBundle:(NSBundle *)localizationBundle {
    return [self initWithJump:jump localizationBundle:localizationBundle isImageAction:NO];
}

- (instancetype)initWithJump:(KayokoCustomJump *)jump
            localizationBundle:(NSBundle *)localizationBundle
                isImageAction:(BOOL)isImageAction {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _jump = [jump copy];
        _localizationBundle = localizationBundle ?: [NSBundle mainBundle];
        _imageAction = isImageAction;
        _displayedType = [[jump type] length] > 0 ? [jump type] : nil;
        _pendingShortcutType = [[jump shortcutType] length] > 0 ? [jump shortcutType] : nil;
        _pickedLink = [[jump link] length] > 0 ? [jump link] : nil;
        [self setModalPresentationStyle:UIModalPresentationPageSheet];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [[self view] setBackgroundColor:[UIColor systemGroupedBackgroundColor]];

    [[self navigationItem] setLeftBarButtonItem:[[UIBarButtonItem alloc] initWithTitle:[self localizedStringForKey:@"Cancel"]
                                                                                   style:UIBarButtonItemStylePlain
                                                                                  target:self
                                                                                  action:@selector(cancelEditing)]];
    [[self navigationItem] setRightBarButtonItem:[[UIBarButtonItem alloc] initWithTitle:[self localizedStringForKey:@"Done"]
                                                                                    style:UIBarButtonItemStyleDone
                                                                                   target:self
                                                                                   action:@selector(finishEditing)]];
    // Every type shares the same generic page title.
    [self setTitle:[self localizedStringForKey:@"Action"]];

    [self configureFields];
    [self configureTableView];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[self keyboardAvoidanceCoordinator] startObserving];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if ([self didFocusTitleTextFieldInitially]) {
        return;
    }
    [self setDidFocusTitleTextFieldInitially:YES];
    [[self titleTextField] becomeFirstResponder];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[self keyboardAvoidanceCoordinator] stopObservingAndRestoreInsets];
}

#pragma mark - Setup

- (NSString *)defaultIconName {
    return kKayokoCustomJumpDefaultIconName;
}

- (UITextField *)newFieldWithText:(NSString *)text placeholder:(NSString *)placeholder {
    UITextField *field = [[UITextField alloc] initWithFrame:CGRectMake(0.0, 0.0, 220.0, 36.0)];
    [field setText:text];
    [field setPlaceholder:placeholder];
    [field setTextAlignment:NSTextAlignmentRight];
    [field setClearButtonMode:UITextFieldViewModeWhileEditing];
    [field setAutocorrectionType:UITextAutocorrectionTypeNo];
    [field setAutocapitalizationType:UITextAutocapitalizationTypeNone];
    [field setDelegate:self];
    return field;
}

- (void)configureFields {
    _titleTextField = [self newFieldWithText:[[self jump] title] placeholder:[self localizedStringForKey:@"Untitled"]];
    [_titleTextField setReturnKeyType:UIReturnKeyNext];

    _iconTextField = [self newFieldWithText:[[self jump] icon] placeholder:[self defaultIconName]];
    [_iconTextField setKeyboardType:UIKeyboardTypeASCIICapable];
    [_iconTextField setReturnKeyType:[self usesLargePayloadBox] ? UIReturnKeyNext : UIReturnKeyDone];

    // Legacy entries keep the right-aligned 跳转链接 field.
    _linkTextField = [self newFieldWithText:[[self jump] link] placeholder:@"example://open"];
    [_linkTextField setKeyboardType:UIKeyboardTypeURL];
    [_linkTextField setReturnKeyType:UIReturnKeyDone];

    // The URL Scheme payload lives in the full-width multi-line box.
    _payloadTextView = [[UITextView alloc] init];
    [_payloadTextView setFont:[UIFont systemFontOfSize:17.0]];
    [_payloadTextView setBackgroundColor:[UIColor clearColor]];
    [[_payloadTextView textContainer] setLineFragmentPadding:0.0];
    [_payloadTextView setTextContainerInset:UIEdgeInsetsZero];
    [_payloadTextView setAutocorrectionType:UITextAutocorrectionTypeNo];
    [_payloadTextView setAutocapitalizationType:UITextAutocapitalizationTypeNone];
    [_payloadTextView setKeyboardType:UIKeyboardTypeURL];
    [_payloadTextView setDelegate:self];
    [_payloadTextView setText:[[self jump] link] ?: @""];

    _payloadPlaceholderLabel = [[UILabel alloc] init];
    [_payloadPlaceholderLabel setFont:[[self payloadTextView] font]];
    [_payloadPlaceholderLabel setTextColor:[UIColor placeholderTextColor]];
    [_payloadPlaceholderLabel setText:@"example://open"];
    [_payloadPlaceholderLabel setHidden:[[[self payloadTextView] text] length] > 0];
}

- (void)configureTableView {
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    [_tableView setTranslatesAutoresizingMaskIntoConstraints:NO];
    [_tableView setDataSource:self];
    [_tableView setDelegate:self];
    [_tableView setKeyboardDismissMode:UIScrollViewKeyboardDismissModeInteractive];
    [_tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"KayokoCustomJumpEditorCell"];
    [_tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"KayokoCustomJumpEditorValueCell"];
    [[self view] addSubview:_tableView];
    [NSLayoutConstraint activateConstraints:@[
        [[_tableView topAnchor] constraintEqualToAnchor:[[self view] topAnchor]],
        [[_tableView leadingAnchor] constraintEqualToAnchor:[[self view] leadingAnchor]],
        [[_tableView trailingAnchor] constraintEqualToAnchor:[[self view] trailingAnchor]],
        [[_tableView bottomAnchor] constraintEqualToAnchor:[[self view] bottomAnchor]]
    ]];
    _keyboardAvoidanceCoordinator = [[KayokoKeyboardAvoidanceCoordinator alloc] initWithView:[self view]
                                                                                       scrollView:_tableView];
}

#pragma mark - Type helpers

- (BOOL)hasDisplayedType {
    return [[self displayedType] length] > 0;
}

- (BOOL)isDisplayedTypeOpenApp {
    return [[self displayedType] isEqualToString:kKayokoCustomJumpTypeOpenApp];
}

- (BOOL)isDisplayedTypeShortcut {
    return [[self displayedType] isEqualToString:kKayokoCustomJumpTypeShortcut];
}

// The URL Scheme payload uses the full-width multi-line text box in its own
// section; legacy and picker types use single-section layouts.
- (BOOL)usesLargePayloadBox {
    return [self hasDisplayedType] && ![self isDisplayedTypeOpenApp] && ![self isDisplayedTypeShortcut];
}

- (NSString *)displayedTypeName {
    if ([self isDisplayedTypeOpenApp]) {
        return [self localizedStringForKey:@"Open App"];
    }
    if ([self isDisplayedTypeShortcut]) {
        return [self localizedStringForKey:@"Shortcut"];
    }
    return [self localizedStringForKey:@"URL Scheme"];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    (void)tableView;
    return [self usesLargePayloadBox] ? 2 : 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    if ([self usesLargePayloadBox]) {
        return section == 0 ? kKayokoActionRowPayload : 1;
    }
    if ([self hasDisplayedType]) {
        return kKayokoActionRowPayload + 1;
    }
    return kKayokoLegacyRowLink + 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return ([self usesLargePayloadBox] && section == 1) ? [self localizedStringForKey:@"URL Scheme"] : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    (void)tableView;
    if ([self usesLargePayloadBox]) {
        return section == 1 ? [self localizedStringForKey:@"URL Scheme Footer"] : nil;
    }
    if ([self hasDisplayedType]) {
        if (section != 0) {
            return nil;
        }
        if ([self isDisplayedTypeOpenApp]) {
            return [self localizedStringForKey:@"Open App Footer"];
        }
        if ([self isDisplayedTypeShortcut]) {
            return [self localizedStringForKey:@"Shortcut Footer"];
        }
        return nil;
    }
    return section == 0 ? [self localizedStringForKey:@"Icon Footer"] : nil;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if ([self usesLargePayloadBox] && [indexPath section] == 1) {
        return 120.0;
    }
    return UITableViewAutomaticDimension;
}

- (NSString *)labelForRow:(NSInteger)row {
    if (![self hasDisplayedType]) {
        if (row == kKayokoLegacyRowName) return [self localizedStringForKey:@"Title"];
        if (row == kKayokoLegacyRowIcon) return [self localizedStringForKey:@"Icon"];
        return [self localizedStringForKey:@"Jump Link"];
    }
    if (row == kKayokoActionRowType) return [self localizedStringForKey:@"Type"];
    if (row == kKayokoActionRowName) return [self localizedStringForKey:@"Title"];
    if (row == kKayokoActionRowIcon) return [self localizedStringForKey:@"Icon"];
    if (row == kKayokoActionRowPayload) {
        return [self isDisplayedTypeOpenApp] ? [self localizedStringForKey:@"Open App"]
                                             : [self localizedStringForKey:@"Shortcut"];
    }
    return @"";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if ([self usesLargePayloadBox] && [indexPath section] == 1) {
        return [self payloadBoxCellForRowAtIndexPath:indexPath];
    }
    if ([self hasDisplayedType] && [indexPath row] == kKayokoActionRowType) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"KayokoCustomJumpEditorValueCell"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                          reuseIdentifier:@"KayokoCustomJumpEditorValueCell"];
        }
        [cell setSelectionStyle:UITableViewCellSelectionStyleNone];
        [[cell textLabel] setText:[self labelForRow:[indexPath row]]];
        [[cell detailTextLabel] setText:[self displayedTypeName]];
        [[cell detailTextLabel] setTextColor:[UIColor secondaryLabelColor]];
        [cell setAccessoryView:nil];
        [cell setAccessoryType:UITableViewCellAccessoryNone];
        return cell;
    }
    if ([self hasDisplayedType] && [indexPath row] == kKayokoActionRowPayload) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"KayokoCustomJumpEditorValueCell"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                          reuseIdentifier:@"KayokoCustomJumpEditorValueCell"];
        }
        [cell setSelectionStyle:UITableViewCellSelectionStyleDefault];
        [[cell textLabel] setText:[self labelForRow:[indexPath row]]];
        NSString *detail = [self isDisplayedTypeShortcut] ? [self pendingShortcutType] : [self pickedLink];
        [[cell detailTextLabel] setText:[detail length] > 0 ? detail : [self localizedStringForKey:@"Not Selected"]];
        [[cell detailTextLabel] setTextColor:[detail length] > 0 ? [UIColor labelColor] : [UIColor tertiaryLabelColor]];
        [[cell detailTextLabel] setLineBreakMode:NSLineBreakByTruncatingMiddle];
        [cell setAccessoryView:nil];
        [cell setAccessoryType:UITableViewCellAccessoryDisclosureIndicator];
        return cell;
    }

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"KayokoCustomJumpEditorCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"KayokoCustomJumpEditorCell"];
    }
    [cell setSelectionStyle:UITableViewCellSelectionStyleNone];
    [[cell textLabel] setText:[self labelForRow:[indexPath row]]];
    [cell setAccessoryView:nil];

    NSInteger row = [indexPath row];
    UITextField *field = nil;
    if (row == kKayokoLegacyRowName || row == kKayokoActionRowName) {
        field = [self titleTextField];
    } else if (row == kKayokoLegacyRowIcon || row == kKayokoActionRowIcon) {
        [cell setAccessoryView:[self iconAccessoryView]];
        return cell;
    } else if (row == kKayokoLegacyRowLink) {
        field = [self linkTextField];
    }
    [field setFrame:CGRectMake(0.0, 0.0, 220.0, 36.0)];
    [cell setAccessoryView:field];
    return cell;
}

// The 图标 row's accessory is a preview thumbnail followed by the edit field;
// the thumbnail mirrors what the entry will actually render (SF Symbol name or
// app bundle identifier) and refreshes on every keystroke.
- (UIView *)iconAccessoryView {
    if (![self iconPreviewContainer]) {
        UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, 267.0, 36.0)];
        UIImageView *preview = [[UIImageView alloc] initWithFrame:CGRectMake(0.0, 3.5, 29.0, 29.0)];
        [preview setContentMode:UIViewContentModeScaleAspectFit];
        [preview setTintColor:[UIColor labelColor]];
        [container addSubview:preview];
        [[self iconTextField] setFrame:CGRectMake(38.0, 0.0, 220.0, 36.0)];
        [container addSubview:[self iconTextField]];
        [[self iconTextField] addTarget:self
                                 action:@selector(refreshIconPreview)
                       forControlEvents:UIControlEventEditingChanged];
        [self setIconPreviewImageView:preview];
        [self setIconPreviewContainer:container];
        [self refreshIconPreview];
    }
    return [self iconPreviewContainer];
}

- (void)refreshIconPreview {
    [[self iconPreviewImageView] setImage:[self previewImageForIconText:[[self iconTextField] text]]];
}

- (UIImage *)previewImageForIconText:(NSString *)text {
    NSString *name = [self trimmedValue:text];
    if ([name length] > 0 && [KayokoAppInfo isValidBundleIdentifier:name]) {
        UIImage *appIcon = [KayokoAppInfo iconForBundleID:name];
        if (appIcon) {
            return appIcon;
        }
    }
    NSString *symbolName = name;
    if ([symbolName length] == 0 || ![UIImage systemImageNamed:symbolName]) {
        symbolName = [self defaultIconName];
    }
    return [UIImage systemImageNamed:symbolName];
}

// The payload box is a single fixed cell kept in a property: its text view
// survives table reloads, and the placeholder tracks the text.
- (UITableViewCell *)payloadBoxCellForRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)indexPath;
    if (![self payloadBoxCell]) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                                       reuseIdentifier:@"KayokoCustomJumpEditorPayloadCell"];
        [cell setSelectionStyle:UITableViewCellSelectionStyleNone];
        [[cell contentView] addSubview:[self payloadTextView]];
        [[cell contentView] addSubview:[self payloadPlaceholderLabel]];
        UILayoutGuide *margins = [[cell contentView] layoutMarginsGuide];
        UITextView *textView = [self payloadTextView];
        UILabel *placeholderLabel = [self payloadPlaceholderLabel];
        // The mask must stay off or the implicit frame constraints fight the
        // edge pins and the text view collapses to a zero-sized, untappable
        // box.
        [textView setTranslatesAutoresizingMaskIntoConstraints:NO];
        [placeholderLabel setTranslatesAutoresizingMaskIntoConstraints:NO];
        [NSLayoutConstraint activateConstraints:@[
            [[textView topAnchor] constraintEqualToAnchor:[[cell contentView] topAnchor] constant:12.0],
            [[textView bottomAnchor] constraintEqualToAnchor:[[cell contentView] bottomAnchor] constant:-12.0],
            [[textView leadingAnchor] constraintEqualToAnchor:[margins leadingAnchor]],
            [[textView trailingAnchor] constraintEqualToAnchor:[margins trailingAnchor]],
            [[placeholderLabel topAnchor] constraintEqualToAnchor:[textView topAnchor]],
            [[placeholderLabel leadingAnchor] constraintEqualToAnchor:[textView leadingAnchor]],
            [[placeholderLabel trailingAnchor] constraintEqualToAnchor:[textView trailingAnchor]]
        ]];
        [self setPayloadBoxCell:cell];
    }
    return [self payloadBoxCell];
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if ([self usesLargePayloadBox]) {
        if ([indexPath section] == 1) {
            [[self payloadTextView] becomeFirstResponder];
        } else if ([indexPath row] == kKayokoActionRowName) {
            [[self titleTextField] becomeFirstResponder];
        } else if ([indexPath row] == kKayokoActionRowIcon) {
            [[self iconTextField] becomeFirstResponder];
        }
        return;
    }

    if (![self hasDisplayedType]) {
        if ([indexPath row] == kKayokoLegacyRowName) {
            [[self titleTextField] becomeFirstResponder];
        } else if ([indexPath row] == kKayokoLegacyRowIcon) {
            [[self iconTextField] becomeFirstResponder];
        } else {
            [[self linkTextField] becomeFirstResponder];
        }
        return;
    }

    if ([indexPath row] != kKayokoActionRowPayload) {
        if ([indexPath row] == kKayokoActionRowName) {
            [[self titleTextField] becomeFirstResponder];
        } else if ([indexPath row] == kKayokoActionRowIcon) {
            [[self iconTextField] becomeFirstResponder];
        }
        return;
    }

    [self.view endEditing:YES];
    if ([self isDisplayedTypeOpenApp]) {
        [self openAppPicker];
    } else if ([self isDisplayedTypeShortcut]) {
        [self openShortcutPicker];
    }
}

- (void)openAppPicker {
    KayokoAppPickerController *picker = [[KayokoAppPickerController alloc] init];
    [picker setCurrentBundleID:[self isDisplayedTypeOpenApp] ? [self pickedLink] : nil];
    __weak typeof(self) weakSelf = self;
    [picker setCompletionHandler:^(NSString *name, NSString *bundleID) {
      __strong typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf) return;
      [strongSelf setPickedLink:bundleID];
      // Fill the title and icon with the app's identity, matching the
      // reference behavior; the user can still override either.
      [[strongSelf titleTextField] setText:name];
      [[strongSelf iconTextField] setText:bundleID];
      [strongSelf refreshIconPreview];
      [strongSelf.tableView reloadRowsAtIndexPaths:@[ [NSIndexPath indexPathForRow:kKayokoActionRowPayload
                                                                         inSection:0] ]
                                  withRowAnimation:UITableViewRowAnimationNone];
    }];
    [[self navigationController] pushViewController:picker animated:YES];
}

- (void)openShortcutPicker {
    KayokoShortcutPickerController *picker = [[KayokoShortcutPickerController alloc] init];
    [picker setCurrentBundleID:[self pickedLink]];
    [picker setCurrentType:[self pendingShortcutType]];
    __weak typeof(self) weakSelf = self;
    [picker setCompletionHandler:^(NSString *title, NSString *bundleID, NSString *type) {
      __strong typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf) return;
      [strongSelf setPickedLink:bundleID];
      [strongSelf setPendingShortcutType:type];
      [[strongSelf iconTextField] setText:bundleID];
      [strongSelf refreshIconPreview];
      // A freshly added action takes the menu item's own title as its label
      // until the user types one; re-picking never clobbers a custom name.
      NSString *currentTitle = [[[strongSelf titleTextField] text]
          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
      if ([currentTitle length] == 0 || [currentTitle isEqualToString:[strongSelf localizedStringForKey:@"Untitled"]] ||
          [currentTitle isEqualToString:[strongSelf localizedStringForKey:@"Action"]]) {
          [[strongSelf titleTextField] setText:title];
      }
      [strongSelf.tableView reloadRowsAtIndexPaths:@[ [NSIndexPath indexPathForRow:kKayokoActionRowPayload
                                                                         inSection:0] ]
                                  withRowAnimation:UITableViewRowAnimationNone];
    }];
    [[self navigationController] pushViewController:picker animated:YES];
}

#pragma mark - Text fields / text view

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == [self titleTextField]) {
        if ([self hasDisplayedType]) {
            [[self iconTextField] becomeFirstResponder];
        } else {
            [[self linkTextField] becomeFirstResponder];
        }
    } else if (textField == [self linkTextField]) {
        [[self iconTextField] becomeFirstResponder];
    } else if (textField == [self iconTextField]) {
        if ([self usesLargePayloadBox]) {
            [[self payloadTextView] becomeFirstResponder];
        } else {
            [textField resignFirstResponder];
        }
    } else {
        [textField resignFirstResponder];
    }
    return YES;
}

- (void)textFieldDidBeginEditing:(UITextField *)textField {
    // Program-filled fields would otherwise start with the caret at the very
    // beginning of the text.
    UITextPosition *end = [textField endOfDocument];
    [textField setSelectedTextRange:[textField textRangeFromPosition:end toPosition:end]];
}

- (void)textViewDidBeginEditing:(UITextView *)textView {
    UITextPosition *end = [textView endOfDocument];
    [textView setSelectedTextRange:[textView textRangeFromPosition:end toPosition:end]];
}

- (void)textViewDidChange:(UITextView *)textView {
    [[self payloadPlaceholderLabel] setHidden:[[textView text] length] > 0];
}

#pragma mark - Save / cancel

- (void)cancelEditing {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSString *)trimmedValue:(NSString *)value {
    return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
}

- (void)finishEditing {
    NSString *title = [self trimmedValue:[[self titleTextField] text]];
    NSString *icon = [self trimmedValue:[[self iconTextField] text]];
    if ([title length] == 0) {
        title = [self localizedStringForKey:@"Untitled"];
    }

    NSString *link = nil;
    NSString *shortcutType = nil;
    if ([self usesLargePayloadBox]) {
        link = [self trimmedValue:[[self payloadTextView] text]];
    } else if ([self hasDisplayedType]) {
        link = [self trimmedValue:[self pickedLink]];
        if ([self isDisplayedTypeShortcut]) {
            shortcutType = [self pendingShortcutType];
        }
    } else {
        link = [self trimmedValue:[[self linkTextField] text]];
    }

    // SF Symbol names and app bundle identifiers are both accepted; anything
    // else falls back to the type's default icon.
    if ([icon length] == 0) {
        icon = [self defaultIconName];
    } else if (![self isValidIconName:icon]) {
        icon = [self defaultIconName];
    }

    KayokoCustomJump *updatedJump = [[KayokoCustomJump alloc] initWithUUID:[[self jump] uuid]
                                                                     title:title
                                                                      link:link
                                                                      icon:icon
                                                                      type:[self displayedType]
                                                              shortcutType:shortcutType];
    void (^completionHandler)(KayokoCustomJump *) = [self completionHandler];
    [self dismissViewControllerAnimated:YES
                             completion:^{
                               if (completionHandler) {
                                   completionHandler(updatedJump);
                               }
                             }];
}

- (BOOL)isValidIconName:(NSString *)icon {
    if ([UIImage systemImageNamed:icon]) {
        return YES;
    }
    return [KayokoAppInfo isValidBundleIdentifier:icon];
}

- (NSString *)localizedStringForKey:(NSString *)key {
    return [[self localizationBundle] localizedStringForKey:key value:key table:@"CustomJumps"] ?: key;
}

@end
