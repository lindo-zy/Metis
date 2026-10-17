#import "MTFloatingAppShelfState.h"

FOUNDATION_EXPORT const char *MTFloatingShelfChangedName;
// SpringBoard alone publishes. Two pinned banks and a commit word prevent torn reads.
FOUNDATION_EXPORT BOOL MTPublishFloatingShelf(NSDictionary *snapshot);
FOUNDATION_EXPORT NSDictionary *MTReadFloatingShelf(void);
