#import <Foundation/Foundation.h>

enum { MTFloatingShelfCapacity = 6 };
FOUNDATION_EXPORT BOOL MTFloatingShelfIdentifierValid(id identifier);
FOUNDATION_EXPORT BOOL MTFloatingShelfSnapshotValid(id snapshot);

// Main-queue registry; it owns metadata only, never a process, Scene or lease.
@interface MTFloatingAppShelfState : NSObject
@property(nonatomic, copy, readonly) NSArray<NSDictionary *> *items;
@property(nonatomic, copy, readonly) NSString *activeIdentifier;
- (BOOL)contains:(NSString *)identifier;
- (BOOL)activate:(NSString *)identifier title:(NSString *)title;
- (BOOL)park:(NSString *)identifier;
- (void)releaseActive;
- (void)remove:(NSString *)identifier;
- (NSDictionary *)snapshot;
@end
