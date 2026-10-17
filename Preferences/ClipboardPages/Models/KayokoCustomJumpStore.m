//
//  KayokoCustomJumpStore.m
//  Kayoko
//

#import "KayokoCustomJumpStore.h"
#import "KayokoCustomJump.h"

#import <roothide.h>

NSString *const kKayokoCustomJumpStoreErrorDomain = @"com.lindo.kayoko.custom-jump-store";

static NSString *const kKayokoCustomJumpStoreDataDirectoryPath = @"/var/mobile/Library/com.lindo.kayoko";
static NSString *const kKayokoCustomJumpStoreFileName = @"custom-jumps-v1.plist";
static NSString *const kKayokoImageActionStoreFileName = @"image-actions-v1.plist";

@interface KayokoCustomJumpStore ()
@property(nonatomic, copy, readwrite) NSString *jumpsPath;
@end

@implementation KayokoCustomJumpStore

+ (NSString *)defaultJumpsPath {
    return [jbroot(kKayokoCustomJumpStoreDataDirectoryPath) stringByAppendingPathComponent:kKayokoCustomJumpStoreFileName];
}

+ (NSString *)defaultImageActionsPath {
    return [jbroot(kKayokoCustomJumpStoreDataDirectoryPath) stringByAppendingPathComponent:kKayokoImageActionStoreFileName];
}

- (instancetype)initWithJumpsPath:(NSString *)jumpsPath {
    self = [super init];
    if (self) {
        _jumpsPath = [jumpsPath copy];
    }
    return self;
}

- (NSMutableArray<KayokoCustomJump *> *)loadJumpsWithError:(NSError **)error {
    if (![[NSFileManager defaultManager] fileExistsAtPath:[self jumpsPath]]) {
        return [[NSMutableArray alloc] init];
    }

    NSData *plistData = [NSData dataWithContentsOfFile:[self jumpsPath] options:0 error:error];
    if (!plistData) {
        return nil;
    }

    NSPropertyListFormat format = NSPropertyListXMLFormat_v1_0;
    id propertyList = [NSPropertyListSerialization propertyListWithData:plistData
                                                                  options:NSPropertyListImmutable
                                                                   format:&format
                                                                    error:error];
    if (![propertyList isKindOfClass:[NSArray class]]) {
        [self populateError:error code:1 message:@"Kayoko custom jump plist root must be an array"];
        return nil;
    }

    NSMutableArray<KayokoCustomJump *> *jumps = [[NSMutableArray alloc] init];
    for (id item in (NSArray *)propertyList) {
        if (![item isKindOfClass:[NSDictionary class]]) {
            [self populateError:error code:2 message:@"Kayoko custom jump plist contains a non-dictionary item"];
            return nil;
        }

        KayokoCustomJump *jump = [KayokoCustomJump jumpWithDictionary:item];
        if (!jump) {
            [self populateError:error code:3 message:@"Kayoko custom jump plist contains an invalid jump"];
            return nil;
        }
        [jumps addObject:jump];
    }
    return jumps;
}

- (BOOL)saveJumps:(NSArray<KayokoCustomJump *> *)jumps error:(NSError **)error {
    NSString *directoryPath = [[self jumpsPath] stringByDeletingLastPathComponent];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:directoryPath] &&
        ![fileManager createDirectoryAtPath:directoryPath withIntermediateDirectories:YES attributes:nil error:error]) {
        return NO;
    }

    NSMutableArray<NSDictionary<NSString *, id> *> *propertyList = [[NSMutableArray alloc] initWithCapacity:[jumps count]];
    for (KayokoCustomJump *jump in jumps) {
        [propertyList addObject:[jump dictionaryRepresentation]];
    }

    NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:propertyList
                                                                     format:NSPropertyListXMLFormat_v1_0
                                                                    options:0
                                                                      error:error];
    if (!plistData) {
        return NO;
    }
    return [plistData writeToFile:[self jumpsPath] options:NSDataWritingAtomic error:error];
}

- (void)populateError:(NSError **)error code:(NSInteger)code message:(NSString *)message {
    if (!error) {
        return;
    }
    *error = [NSError errorWithDomain:kKayokoCustomJumpStoreErrorDomain
                                 code:code
                             userInfo:@{NSLocalizedDescriptionKey : message ?: @"Kayoko custom jump store error"}];
}

@end
