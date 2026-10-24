#import <Foundation/Foundation.h>
#include <math.h>
#include <stdint.h>

static NSString * const MTFloatInputSessionName = @"com.lindo.metis.keyboard.floating-input.session-v1";
static NSString * const MTFloatInputBaseName = @"com.lindo.metis.keyboard.floating-input.base-v1";
// v2: floating-app activity means a recognized content scroll, never touch-down.
// Reject touch notifications from app processes still running the previous code.
static NSString * const MTFloatInputActivityName = @"com.lindo.metis.keyboard.floating-input.activity-v2";
static NSString * const MTFloatInputFocusName = @"com.lindo.metis.keyboard.floating-input.focus-v1";
static inline NSString *MTFloatInputName(uint32_t pid) {
    return [NSString stringWithFormat:@"com.lindo.metis.keyboard.floating-input.pinch-v1.%u", pid];
}
static inline NSString *MTFloatInputSceneName(uint32_t pid) {
    return [NSString stringWithFormat:@"com.lindo.metis.keyboard.floating-input.scene-v1.%u", pid];
}
static inline uint64_t MTFloatInputSceneHash(NSString *identifier) {
    if (![identifier isKindOfClass:NSString.class] || !identifier.length) return 0;
    const char *bytes = identifier.UTF8String;
    if (!bytes) return 0;
    uint64_t hash = 14695981039346656037ULL;
    for (const unsigned char *p = (const unsigned char *)bytes; *p; p++) {
        hash ^= *p; hash *= 1099511628211ULL;
    }
    return hash ?: 1;
}
typedef NS_ENUM(uint32_t, MTFloatPinchPhase) {
    MTFloatPinchBegan, MTFloatPinchChanged, MTFloatPinchEnded, MTFloatPinchCancelled
};
static inline uint64_t MTFloatInputSessionWord(uint32_t pid, uint32_t nonce) {
    return ((uint64_t)nonce << 32) | pid;
}
static inline BOOL MTFloatInputActivityMatches(uint64_t word, uint32_t nonce, uint32_t targetPID, uint32_t basePID) {
    uint32_t pid = (uint32_t)word;
    return nonce && targetPID > 1 && (uint32_t)(word >> 32) == nonce &&
        (pid == targetPID || (basePID > 1 && pid == basePID));
}
static inline uint64_t MTFloatPinchWord(uint32_t nonce, uint8_t gesture, MTFloatPinchPhase phase, double scale) {
    if (!nonce || !gesture || phase > MTFloatPinchCancelled || !isfinite(scale) || scale <= 0) return 0;
    uint32_t quantized = (uint32_t)lround(fmin(16, fmax(.001, scale)) * 1000);
    return ((uint64_t)nonce << 32) | ((uint32_t)phase << 24) | ((uint32_t)gesture << 16) | quantized;
}
static inline BOOL MTFloatDecodePinch(uint64_t word, uint32_t nonce, uint8_t *gesture,
                                     MTFloatPinchPhase *phase, double *scale) {
    uint32_t quantized = word & 0xffff;
    uint8_t serial = (word >> 16) & 0xff;
    if (!nonce || (uint32_t)(word >> 32) != nonce || (word & 0xfc000000ULL) ||
        !serial || !quantized || quantized > 16000) return NO;
    *gesture = serial; *phase = (MTFloatPinchPhase)((word >> 24) & 3); *scale = quantized / 1000.0;
    return YES;
}
FOUNDATION_EXPORT void MTStartFloatingAppInputClient(void);
