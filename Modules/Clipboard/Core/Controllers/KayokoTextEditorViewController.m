//
//  KayokoTextEditorViewController.m
//  Kayoko
//

#import "KayokoTextEditorViewController.h"

#import "KayokoHeaderButtonStyle.h"
#import "KayokoHeaderView.h"
#import "KayokoPasteboardItem.h"
#import "KayokoPasteboardManager.h"
#import "KayokoTextEditorView.h"

static NSString *kayokoEditorTextByTrimmingBoundaryNewlines(NSString *text) {
    return [(text ?: @"") stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
}

@interface KayokoTextEditorViewController ()
@property(nonatomic, strong, readwrite) KayokoTextEditorView *textEditorView;
@property(nonatomic, strong, nullable, readwrite) KayokoPasteboardItem *item;
@property(nonatomic, copy, nullable, readwrite) NSString *sourceHistoryKey;
@property(nonatomic, assign, getter=isEditing, readwrite) BOOL editing;
@property(nonatomic, copy, nullable) NSString *originalFullText;
@property(nonatomic, assign) NSRange replacementRange;
@property(nonatomic, assign, getter=isSaving) BOOL saving;
@end

@implementation KayokoTextEditorViewController

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _textEditorView = [[KayokoTextEditorView alloc] initWithFrame:CGRectZero];
        [self setView:_textEditorView];
        [[[_textEditorView headerView] editButton] addTarget:self
                                                      action:@selector(handleSaveButtonPressed)
                                            forControlEvents:UIControlEventTouchUpInside];
    }
    return self;
}

- (void)configureHeader {
    KayokoHeaderView *headerView = [[self textEditorView] headerView];
    [headerView setHistorySwitcherVisible:NO animated:NO];
    [headerView setTitleText:[[KayokoPasteboardManager localizationBundle] localizedStringForKey:@"Edit"
                                                                                          value:nil
                                                                                          table:@"Tweak"]];
    [headerView updateStyleForButton:[headerView leadingButton]
                       withImageName:@"xmark.circle"
                           imageSize:kKayokoBackButtonImageSize
                           tintColor:[UIColor labelColor]];
    [[headerView leadingButton]
        setAccessibilityLabel:[[KayokoPasteboardManager localizationBundle] localizedStringForKey:@"Cancel"
                                                                                            value:nil
                                                                                            table:@"Tweak"]];
    [headerView updateStyleForButton:[headerView editButton]
                       withImageName:@"checkmark.circle"
                           imageSize:kKayokoBackButtonImageSize
                           tintColor:[UIColor labelColor]];
    [[headerView editButton]
        setAccessibilityLabel:[[KayokoPasteboardManager localizationBundle] localizedStringForKey:@"Save"
                                                                                            value:nil
                                                                                            table:@"Tweak"]];
    [[headerView editButton] setHidden:NO];
    [[headerView editButton] setEnabled:YES];
    [[headerView editButton] setAlpha:1];
    [[headerView shareButton] setHidden:YES];
    [[headerView trailingButton] setHidden:YES];
    [[headerView selectionActionButton] setHidden:YES];
    [[headerView alternateTrailingButton] setHidden:YES];
    [[headerView translationButton] setHidden:YES];
}

- (void)beginEditingItem:(KayokoPasteboardItem *)item
        sourceHistoryKey:(NSString *)sourceHistoryKey
        replacementRange:(NSRange)replacementRange {
    NSString *fullText = kayokoEditorTextByTrimmingBoundaryNewlines([item content]);
    NSUInteger textLength = [fullText length];
    NSRange range = replacementRange;
    BOOL editsFullText = (range.location == NSNotFound || range.length == 0 || range.location > textLength ||
                          range.length >= textLength);
    if (!editsFullText && range.location + range.length > textLength) {
        range.length = textLength - range.location;
        editsFullText = (range.length == 0 || range.length >= textLength);
    }
    if (editsFullText) {
        range = NSMakeRange(0, textLength);
    }

    [self setItem:item];
    [self setSourceHistoryKey:sourceHistoryKey];
    [self setOriginalFullText:fullText];
    [self setReplacementRange:range];
    [self setEditing:YES];
    [self configureHeader];
    [[self textEditorView] setHidden:NO];
    [[self textEditorView] setEditorText:editsFullText ? fullText : [fullText substringWithRange:range]];
    [[self delegate] textEditorViewControllerDidBeginEditing:self];
    [self activateEditorFocus];
}

- (NSString *)composedEditedContent {
    NSString *originalText = [self originalFullText] ?: @"";
    NSString *editedText = [[self textEditorView] editorText] ?: @"";
    NSRange range = [self replacementRange];
    if (range.location == NSNotFound || range.location > [originalText length] ||
        range.location + range.length > [originalText length] || range.length == [originalText length]) {
        return editedText;
    }
    NSString *prefix = [originalText substringToIndex:range.location];
    NSString *suffix = [originalText substringFromIndex:range.location + range.length];
    return [NSString stringWithFormat:@"%@%@%@", prefix, editedText, suffix];
}

- (void)placeCaretAtEndOfTextView:(UITextView *)textView {
    NSUInteger length = [[textView text] length];
    [textView setSelectedRange:NSMakeRange(length, 0)];
    UITextPosition *end = [textView endOfDocument];
    if (end) {
        [textView setSelectedTextRange:[textView textRangeFromPosition:end toPosition:end]];
    }
    if (length > 0) {
        [textView scrollRangeToVisible:NSMakeRange(length - 1, 1)];
    }
}

- (void)activateEditorFocus {
    KayokoTextEditorView *editorView = [self textEditorView];
    [editorView layoutIfNeeded];

    UIWindow *window = [editorView window];
    if (window && ![window isKeyWindow]) {
        [window makeKeyWindow];
    }

    UITextView *textView = [editorView textView];
    [textView becomeFirstResponder];
    [self placeCaretAtEndOfTextView:textView];

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
      __strong typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf || ![strongSelf isEditing] || [editorView isHidden] || ![editorView window]) {
          return;
      }
      if (![textView isFirstResponder]) {
          [[editorView window] makeKeyWindow];
          [textView becomeFirstResponder];
      }
      [strongSelf placeCaretAtEndOfTextView:textView];
    });
}

- (void)setSaving:(BOOL)saving {
    _saving = saving;
    KayokoHeaderView *headerView = [[self textEditorView] headerView];
    [[headerView editButton] setEnabled:!saving];
    [[headerView leadingButton] setEnabled:!saving];
    [[[self textEditorView] textView] setEditable:!saving];
}

- (void)handleSaveButtonPressed {
    if (![self isEditing] || [self isSaving]) {
        return;
    }
    [self setSaving:YES];
    [[self delegate] textEditorViewControllerDidRequestSave:self];
}

- (void)finishEditing {
    [self setEditing:NO];
    [[[self textEditorView] textView] resignFirstResponder];
}

- (void)reset {
    [self setSaving:NO];
    [self finishEditing];
    [[self textEditorView] reset];
    [[self textEditorView] setHidden:YES];
    [self setItem:nil];
    [self setSourceHistoryKey:nil];
    [self setOriginalFullText:nil];
    [self setReplacementRange:NSMakeRange(NSNotFound, 0)];
}

@end
