//
//  MTTagStore.m
//  Mt
//

#import "MTTagStore.h"
#import "MTTag.h"

#import <roothide.h>

NSString *const kMTTagStoreErrorDomain = @"com.lindo.kayoko.tag-store";

static NSString *const kMTTagStoreDataDirectoryPath = @"/var/mobile/Library/com.lindo.kayoko";
static NSString *const kMTTagStoreFileName = @"tags-v4.plist";

@interface MTTagStore ()
@property(nonatomic, copy, readwrite) NSString *tagsPath;
@property(nonatomic, strong, readwrite) NSBundle *localizationBundle;
@end

@implementation MTTagStore

+ (NSString *)defaultTagsPath {
    return [jbroot(kMTTagStoreDataDirectoryPath) stringByAppendingPathComponent:kMTTagStoreFileName];
}

- (instancetype)initWithTagsPath:(NSString *)tagsPath localizationBundle:(NSBundle *)localizationBundle {
    self = [super init];
    if (self) {
        _tagsPath = [tagsPath copy];
        _localizationBundle = localizationBundle ?: [NSBundle mainBundle];
    }
    return self;
}

- (NSMutableArray<MTTag *> *)loadTagsWithError:(NSError **)error {
    if (![self ensureDefaultTagsFileExistsWithError:error]) {
        return nil;
    }

    return [self readTagsWithError:error];
}

- (NSMutableArray<MTTag *> *)readTagsWithError:(NSError **)error {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:[self tagsPath]]) {
        return [[NSMutableArray alloc] init];
    }

    NSData *plistData = [NSData dataWithContentsOfFile:[self tagsPath] options:0 error:error];
    if (!plistData) {
        return nil;
    }

    NSPropertyListFormat format = NSPropertyListXMLFormat_v1_0;
    id propertyList = [NSPropertyListSerialization propertyListWithData:plistData
                                                                options:NSPropertyListImmutable
                                                                 format:&format
                                                                  error:error];
    if (![propertyList isKindOfClass:[NSArray class]]) {
        [self populateError:error code:1 message:@"Mt tag plist root must be an array"];
        return nil;
    }

    NSMutableArray<MTTag *> *tags = [[NSMutableArray alloc] init];
    for (id item in (NSArray *)propertyList) {
        if (![item isKindOfClass:[NSDictionary class]]) {
            [self populateError:error code:2 message:@"Mt tag plist contains a non-dictionary item"];
            return nil;
        }

        MTTag *tag = [MTTag tagWithDictionary:item];
        if (!tag) {
            [self populateError:error code:3 message:@"Mt tag plist contains an invalid tag"];
            return nil;
        }
        [tags addObject:tag];
    }

    return tags;
}

- (BOOL)ensureDefaultTagsFileExistsWithError:(NSError **)error {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:[self tagsPath]]) {
        return YES;
    }

    return [self saveTags:[self defaultTags] error:error];
}

- (BOOL)saveTags:(NSArray<MTTag *> *)tags error:(NSError **)error {
    if (![self prepareDataDirectoryWithError:error]) {
        return NO;
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *propertyList =
        [[NSMutableArray alloc] initWithCapacity:[tags count]];
    for (MTTag *tag in tags) {
        [propertyList addObject:[tag dictionaryRepresentation]];
    }

    NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:propertyList
                                                                   format:NSPropertyListXMLFormat_v1_0
                                                                  options:0
                                                                    error:error];
    if (!plistData) {
        return NO;
    }

    return [plistData writeToFile:[self tagsPath] options:NSDataWritingAtomic error:error];
}

- (BOOL)restoreDefaultTagsWithError:(NSError **)error {
    return [self saveTags:[self defaultTags] error:error];
}

#pragma mark - Private

- (NSArray<MTTag *> *)defaultTags {
    return @[
        [MTTag tagWithTitle:[self localizedStringForKey:@"Red"] hexColor:@"#EF7571FF"],
        [MTTag tagWithTitle:[self localizedStringForKey:@"Orange"] hexColor:@"#F3AC6DFF"],
        [MTTag tagWithTitle:[self localizedStringForKey:@"Yellow"] hexColor:@"#FAE06DFF"],
        [MTTag tagWithTitle:[self localizedStringForKey:@"Green"] hexColor:@"#86D885FF"],
        [MTTag tagWithTitle:[self localizedStringForKey:@"Blue"] hexColor:@"#66A5F9FF"],
        [MTTag tagWithTitle:[self localizedStringForKey:@"Purple"] hexColor:@"#D469EEFF"],
        [MTTag tagWithTitle:[self localizedStringForKey:@"Gray"] hexColor:@"#ADADB0FF"]
    ];
}

- (NSString *)localizedStringForKey:(NSString *)key {
    return [[self localizationBundle] localizedStringForKey:key value:key table:@"Tags"] ?: key;
}

- (BOOL)prepareDataDirectoryWithError:(NSError **)error {
    NSString *directoryPath = [[self tagsPath] stringByDeletingLastPathComponent];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:directoryPath]) {
        return YES;
    }

    return [fileManager createDirectoryAtPath:directoryPath withIntermediateDirectories:YES attributes:nil error:error];
}

- (void)populateError:(NSError **)error code:(NSInteger)code message:(NSString *)message {
    if (!error) {
        return;
    }

    *error = [NSError errorWithDomain:kMTTagStoreErrorDomain
                                 code:code
                             userInfo:@{NSLocalizedDescriptionKey : message ?: @"Mt tag store error"}];
}

@end
