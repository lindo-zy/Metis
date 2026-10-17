#import "MTPSpongebobOptions.h"
#import "MTHelper.h"
#import "common.h"


static NSBundle *mtpLocalBundle;

@implementation MTPSpongebobOptions

- (NSArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *snippetEntrySpecifiers = [[NSMutableArray alloc] init];
        
        PSSpecifier *spongebobTextSpecGroup = [PSSpecifier preferenceSpecifierNamed:LOCALIZED(@"SPONGEBOB_ENTROPY") target:nil set:nil get:nil detail:nil cell:PSGroupCell edit:nil];
        [spongebobTextSpecGroup setProperty:LOCALIZED(@"FOOTER_SPONGEBOB_ENTROPY") forKey:@"footerText"];
        [snippetEntrySpecifiers addObject:spongebobTextSpecGroup];
        
        
        PSSpecifier *spongebobEntropyTypeSpec = [PSSpecifier preferenceSpecifierNamed:LOCALIZED(@"SPONGEBOB_ENTROPY") target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSegmentCell edit:nil];
        [spongebobEntropyTypeSpec setValues:@[@(MTStudlyCapsTypeRandom), @(MTStudlyCapsTypeAlternate), @(MTStudlyCapsTypeVowel), @(MTStudlyCapsTypeConsonent)] titles:@[LOCALIZED(@"SPONGEBOB_RANDOM"), LOCALIZED(@"SPONGEBOB_ALTERNATE"), LOCALIZED(@"SPONGEBOB_VOWEL"), LOCALIZED(@"SPONGEBOB_CONSONENT")]];
        [spongebobEntropyTypeSpec setProperty:@(MTStudlyCapsTypeRandom) forKey:@"default"];
        [spongebobEntropyTypeSpec setProperty:kSpongebobEntropyKey forKey:@"key"];
        [spongebobEntropyTypeSpec setProperty:kIdentifier forKey:@"defaults"];
        [spongebobEntropyTypeSpec setProperty:kPrefsChangedIdentifier forKey:@"PostNotification"];
        [snippetEntrySpecifiers addObject:spongebobEntropyTypeSpec];
        
        _specifiers = snippetEntrySpecifiers;
        
    }
    
    return _specifiers;
}

- (void)viewDidLoad {
    mtpLocalBundle = [NSBundle bundleWithPath:bundlePath];
    [mtpLocalBundle load];
    [super viewDidLoad];
}

@end
