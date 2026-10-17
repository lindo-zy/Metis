//
//  MTKeyboardShortcutSender.m
//  Mt
//

#import "MTKeyboardShortcutSender.h"

#import <CoreFoundation/CoreFoundation.h>
#import <HBLog.h>
#import <mach/boolean.h>
#import <mach/mach_time.h>
#import <unistd.h>

typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;

extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
extern IOHIDEventRef IOHIDEventCreateKeyboardEvent(CFAllocatorRef allocator, uint64_t timeStamp, uint32_t usagePage,
                                                   uint32_t usage, boolean_t isDown, uint32_t options);
extern void IOHIDEventSetSenderID(IOHIDEventRef event, uint64_t senderID);
extern void IOHIDEventSystemClientDispatchEvent(IOHIDEventSystemClientRef client, IOHIDEventRef event);

static uint32_t const kMTHIDPageKeyboardOrKeypad = 0x07;
static uint32_t const kMTHIDUsageKeyboardV = 0x19;
static uint32_t const kMTHIDUsageKeyboardLeftGUI = 0xE3;
static uint32_t const kMTHIDEventOptionNone = 0;
static uint64_t const kMTHIDEventSenderID = 0x8000000817319371ULL;
static useconds_t const kMTKeyboardShortcutKeyPressDelay = 50000;

@implementation MTKeyboardShortcutSender {
    dispatch_queue_t _eventQueue;
    IOHIDEventSystemClientRef _eventSystemClient;
}

+ (instancetype)sharedSender {
    static MTKeyboardShortcutSender *sender = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      sender = [[self alloc] initPrivate];
    });
    return sender;
}

- (instancetype)initPrivate {
    self = [super init];
    if (self) {
        _eventQueue = dispatch_queue_create("com.lindo.metis.clipboard.queue.keyboard-shortcut",
                                            DISPATCH_QUEUE_SERIAL_WITH_AUTORELEASE_POOL);
        _eventSystemClient = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    }
    return self;
}

- (void)sendCommandV {
    dispatch_async(_eventQueue, ^{
      HBLogDebug(@"Mt: dispatching simulated Cmd+V HID shortcut");
      [self dispatchKeyboardUsage:kMTHIDUsageKeyboardLeftGUI isKeyDown:YES];
      [self dispatchKeyboardUsage:kMTHIDUsageKeyboardV isKeyDown:YES];
      usleep(kMTKeyboardShortcutKeyPressDelay);
      [self dispatchKeyboardUsage:kMTHIDUsageKeyboardV isKeyDown:NO];
      [self dispatchKeyboardUsage:kMTHIDUsageKeyboardLeftGUI isKeyDown:NO];
    });
}

- (void)dispatchKeyboardUsage:(uint32_t)usage isKeyDown:(BOOL)isKeyDown {
    if (!_eventSystemClient) {
        HBLogDebug(@"Mt: simulated shortcut skipped because IOHID event system client is unavailable");
        return;
    }

    IOHIDEventRef event =
        IOHIDEventCreateKeyboardEvent(kCFAllocatorDefault, mach_absolute_time(), kMTHIDPageKeyboardOrKeypad, usage,
                                      isKeyDown, kMTHIDEventOptionNone);
    if (!event) {
        HBLogDebug(@"Mt: simulated shortcut failed to create keyboard event usage=0x%x isKeyDown=%@", usage,
                   isKeyDown ? @"YES" : @"NO");
        return;
    }

    IOHIDEventSetSenderID(event, kMTHIDEventSenderID);
    IOHIDEventSystemClientDispatchEvent(_eventSystemClient, event);
    CFRelease(event);
}

@end
