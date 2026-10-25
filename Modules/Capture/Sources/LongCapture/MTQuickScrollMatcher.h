#pragma once
#include <stdint.h>

// Horizontal grayscale samples, retaining every original vertical pixel.
// Pure C so the same matcher and coverage accounting can be replayed on the host.
enum { MTQuickScrollSignatureWidth = 128 };
typedef enum {
    MTQuickScrollUncertain, MTQuickScrollStill, MTQuickScrollMoved
} MTQuickScrollMatchKind;
typedef struct {
    MTQuickScrollMatchKind kind;
    int delta;                 // Positive: content moved upwards.
    int votes;
    int bodyTop, bodyBottom;   // Top-origin native pixel rows.
    float error;
} MTQuickScrollMatch;

MTQuickScrollMatch MTQuickScrollMatchFrames(const uint8_t *previous, const uint8_t *current,
                                           int rows, int predictedDelta);

typedef struct { int64_t position, frontier; } MTQuickScrollCoverage;
// Tracking includes backwards motion. Only extending the frontier adds pixels.
// Returns -1 if the unrecorded span no longer fits inside the current body.
int MTQuickScrollAdvance(MTQuickScrollCoverage *coverage, int delta, int bodyRows,
                         int minimumAppend, int commit);
