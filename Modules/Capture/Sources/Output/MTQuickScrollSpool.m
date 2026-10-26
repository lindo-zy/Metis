#import "MTQuickScrollSpool.h"
#import <zlib.h>
#import <sys/statvfs.h>
#import <unistd.h>
#import <stdio.h>
#import <math.h>
#import <arpa/inet.h>
#import <string.h>
#import <stdlib.h>

static void MTSpoolError(NSError **error, NSString *text) {
    if (error) *error = [NSError errorWithDomain:@"com.lindo.metis.quick.spool" code:1
                                      userInfo:@{NSLocalizedDescriptionKey:text}];
}
static BOOL MTWriteChunk(FILE *file, const char name[4], const void *bytes, uint32_t length) {
    uint32_t size = htonl(length);
    uLong crc = crc32(0, (const Bytef *)name, 4);
    if (length) crc = crc32(crc, bytes, length);
    uint32_t checksum = htonl((uint32_t)crc);
    return fwrite(&size, 4, 1, file) == 1 && fwrite(name, 1, 4, file) == 4 &&
        (!length || fwrite(bytes, 1, length, file) == length) && fwrite(&checksum, 4, 1, file) == 1;
}
@interface MTQuickScrollSpool ()
@property (nonatomic, copy) NSString *path;
@property (nonatomic, strong) MTLongShotCancellation *cancellation;
@property (nonatomic, readwrite) NSInteger height;
@property (nonatomic) NSInteger width;
@end
@implementation MTQuickScrollSpool
- (instancetype)initWithDirectory:(NSString *)directory cancellation:(MTLongShotCancellation *)cancellation {
    if ((self = [super init])) {
        _path = [directory stringByAppendingPathComponent:@"quick_rows.rgb"];
        _cancellation = cancellation;
    }
    return self;
}
- (BOOL)appendImage:(UIImage *)image rect:(CGRect)rect scrubRightColumns:(NSInteger)columns error:(NSError **)error {
    if (self.cancellation.cancelled) return NO;
    if (!image.CGImage || !isfinite(rect.origin.x) || !isfinite(rect.origin.y) ||
        !isfinite(rect.size.width) || !isfinite(rect.size.height) || rect.origin.x < 0 || rect.origin.y < 0 ||
        rect.size.width < 1 || rect.size.height < 1 || rect.size.width > 16384 || rect.size.height > 16384 ||
        CGRectGetMaxX(rect) > CGImageGetWidth(image.CGImage) || CGRectGetMaxY(rect) > CGImageGetHeight(image.CGImage)) {
        MTSpoolError(error, @"长截图条带区域无效"); return NO;
    }
    NSInteger width = (NSInteger)rect.size.width, height = (NSInteger)rect.size.height;
    if ((self.width && self.width != width) || self.height > INT32_MAX - height) {
        MTSpoolError(error, @"长截图尺寸超出图像格式范围"); return NO;
    }
    struct statvfs stats;
    uint64_t required = (uint64_t)width * height * 3;
    if (statvfs(self.path.stringByDeletingLastPathComponent.fileSystemRepresentation, &stats) == 0 &&
        (uint64_t)stats.f_bavail * stats.f_frsize < required + 64ull * 1024 * 1024) {
        MTSpoolError(error, @"存储空间不足，请先保存已截内容"); return NO;
    }
    CGImageRef crop = CGImageCreateWithImageInRect(image.CGImage, rect);
    CGColorSpaceRef color = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = color ? CGBitmapContextCreate(NULL, width, height, 8, 0, color,
        kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst) : NULL;
    if (color) CGColorSpaceRelease(color);
    if (!crop || !context) {
        if (crop) CGImageRelease(crop);
        if (context) CGContextRelease(context);
        MTSpoolError(error, @"长截图条带缓冲区创建失败"); return NO;
    }
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), crop);
    CGImageRelease(crop);
    uint8_t *row = malloc((size_t)width * 3);
    FILE *file = fopen(self.path.fileSystemRepresentation, self.height ? "r+b" : "w+b");
    off_t original = (off_t)self.height * width * 3;
    if (file) setvbuf(file, NULL, _IOFBF, 256 * 1024);
    BOOL ok = row && file && fseeko(file, original, SEEK_SET) == 0;
    size_t stride = CGBitmapContextGetBytesPerRow(context);
    const uint8_t *pixels = CGBitmapContextGetData(context);
    for (NSInteger y = 0; y < height && ok; y++) {
        if (self.cancellation.cancelled) { ok = NO; break; }
        const uint8_t *source = pixels + y * stride;
        for (NSInteger x = 0; x < width; x++) {
            NSInteger donor = columns > 0 && columns < width / 4 && x >= width - columns
                ? width - columns - 1 : x;
            row[x * 3] = source[donor * 4 + 2];
            row[x * 3 + 1] = source[donor * 4 + 1];
            row[x * 3 + 2] = source[donor * 4];
        }
        ok = fwrite(row, 1, width * 3, file) == (size_t)width * 3;
    }
    if (file) {
        if (fflush(file) != 0) ok = NO;
        if (self.cancellation.cancelled) ok = NO;
        if (!ok) ftruncate(fileno(file), original);
        if (fclose(file) != 0) ok = NO;
    }
    free(row); CGContextRelease(context);
    if (!ok) { MTSpoolError(error, @"长截图条带写入失败，可保存已截内容"); return NO; }
    self.width = width; self.height += height;
    return YES;
}
- (BOOL)writePNGToURL:(NSURL *)url error:(NSError **)error {
    if (self.cancellation.cancelled || !self.width || !self.height) return NO;
    NSString *temporary = [url.path stringByAppendingString:@".partial"];
    FILE *input = fopen(self.path.fileSystemRepresentation, "rb");
    FILE *output = fopen(temporary.fileSystemRepresentation, "wb");
    size_t rowSize = (size_t)self.width * 3;
    uint8_t *row = malloc(rowSize + 1), *compressed = malloc(65536);
    z_stream stream = {0};
    BOOL initialized = deflateInit(&stream, Z_BEST_SPEED) == Z_OK;
    BOOL ok = input && output && row && compressed && initialized;
    uint8_t header[13] = {0};
    uint32_t width = htonl((uint32_t)self.width), height = htonl((uint32_t)self.height);
    memcpy(header, &width, 4); memcpy(header + 4, &height, 4); header[8] = 8; header[9] = 2;
    uint8_t intent = 0;
    if (ok) ok = fwrite("\x89PNG\r\n\x1a\n", 1, 8, output) == 8 &&
        MTWriteChunk(output, "IHDR", header, 13) && MTWriteChunk(output, "sRGB", &intent, 1);
    for (NSInteger y = 0; y < self.height && ok; y++) {
        if (self.cancellation.cancelled) { ok = NO; break; }
        if (y % 256 == 0 && self.onProgress) self.onProgress();
        row[0] = 1; // PNG Sub filter, preserving independent row streaming.
        if (fread(row + 1, 1, rowSize, input) != rowSize) { ok = NO; break; }
        for (size_t x = rowSize; x > 3; x--) row[x] = (uint8_t)(row[x] - row[x - 3]);
        stream.next_in = row; stream.avail_in = (uInt)(rowSize + 1);
        do {
            stream.next_out = compressed; stream.avail_out = 65536;
            int status = deflate(&stream, Z_NO_FLUSH);
            if (status != Z_OK) { ok = NO; break; }
            uint32_t count = 65536 - stream.avail_out;
            if (count && !MTWriteChunk(output, "IDAT", compressed, count)) { ok = NO; break; }
        } while (stream.avail_in);
    }
    int status = Z_OK;
    while (ok && status != Z_STREAM_END) {
        stream.next_out = compressed; stream.avail_out = 65536;
        status = deflate(&stream, Z_FINISH);
        if (status != Z_OK && status != Z_STREAM_END) { ok = NO; break; }
        uint32_t count = 65536 - stream.avail_out;
        if (count && !MTWriteChunk(output, "IDAT", compressed, count)) ok = NO;
    }
    if (ok) ok = MTWriteChunk(output, "IEND", NULL, 0);
    if (initialized) deflateEnd(&stream);
    if (input) fclose(input);
    if (output && fclose(output) != 0) ok = NO;
    free(row); free(compressed);
    if (self.cancellation.cancelled) ok = NO;
    if (ok) ok = rename(temporary.fileSystemRepresentation, url.path.fileSystemRepresentation) == 0;
    if (!ok) {
        unlink(temporary.fileSystemRepresentation);
        MTSpoolError(error, @"长截图文件导出失败，已保留原始条带");
    }
    return ok;
}
@end
