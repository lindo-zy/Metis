//
//  MTImageDoubleTapActionViewController.m
//  Mt
//

#import "MTImageDoubleTapActionViewController.h"

#import "MTNotificationKeys.h"
#import "MTPreferenceKeys.h"

@interface MTImageDoubleTapActionViewController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate>
@property(nonatomic, strong) UITableView *tableView;
@property(nonatomic, strong) UITextField *urlTextField;
@property(nonatomic, assign) BOOL didFocusURLTextFieldInitially;
@end

@implementation MTImageDoubleTapActionViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [[self view] setBackgroundColor:[UIColor systemGroupedBackgroundColor]];
    [self setTitle:[self localizedStringForKey:@"Image Double-Tap Action"]];

    _urlTextField = [[UITextField alloc] init];
    [_urlTextField setText:[self storedURLScheme]];
    [_urlTextField setPlaceholder:[self localizedStringForKey:@"URL Scheme"]];
    [_urlTextField setKeyboardType:UIKeyboardTypeURL];
    [_urlTextField setAutocapitalizationType:UITextAutocapitalizationTypeNone];
    [_urlTextField setAutocorrectionType:UITextAutocorrectionTypeNo];
    [_urlTextField setReturnKeyType:UIReturnKeyDone];
    [_urlTextField setDelegate:self];
    [_urlTextField setTextAlignment:NSTextAlignmentRight];

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    [_tableView setTranslatesAutoresizingMaskIntoConstraints:NO];
    [_tableView setDataSource:self];
    [_tableView setDelegate:self];
    [_tableView setKeyboardDismissMode:UIScrollViewKeyboardDismissModeInteractive];
    [[self view] addSubview:_tableView];
    [NSLayoutConstraint activateConstraints:@[
        [[_tableView topAnchor] constraintEqualToAnchor:[[self view] topAnchor]],
        [[_tableView leadingAnchor] constraintEqualToAnchor:[[self view] leadingAnchor]],
        [[_tableView trailingAnchor] constraintEqualToAnchor:[[self view] trailingAnchor]],
        [[_tableView bottomAnchor] constraintEqualToAnchor:[[self view] bottomAnchor]]
    ]];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if ([self didFocusURLTextFieldInitially]) {
        return;
    }
    [self setDidFocusURLTextFieldInitially:YES];
    [[self urlTextField] becomeFirstResponder];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self saveURLScheme];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    [self saveURLScheme];
    return YES;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    (void)section;
    return [self localizedStringForKey:@"Fill URL Scheme"];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *const reuseIdentifier = @"MTImageDoubleTapActionCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseIdentifier];
        [cell setSelectionStyle:UITableViewCellSelectionStyleNone];
    }

    [[cell textLabel] setText:[self localizedStringForKey:@"URL"]];
    [[self urlTextField] setFrame:CGRectMake(0.0, 0.0, 240.0, 36.0)];
    [cell setAccessoryView:[self urlTextField]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    (void)indexPath;
    [[self urlTextField] becomeFirstResponder];
}

- (NSString *)storedURLScheme {
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:kMTClipboardPreferencesIdentifier];
    NSString *value = [defaults stringForKey:kMTPreferenceKeyImageDoubleTapActionURL];
    return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
}

- (void)saveURLScheme {
    NSString *value = [[[self urlTextField] text]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:kMTClipboardPreferencesIdentifier];
    [defaults setObject:value ?: @"" forKey:kMTPreferenceKeyImageDoubleTapActionURL];
    [defaults synchronize];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (CFStringRef)kMTNotificationKeyPreferencesReload, nil, nil, YES);
}

- (NSString *)localizedStringForKey:(NSString *)key {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    return [bundle localizedStringForKey:key value:key table:@"CustomJumps"] ?: key;
}

@end
