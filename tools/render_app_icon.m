#import "QuotaIcon.h"

static BOOL WriteIcon(NSString *path, NSInteger pixels) {
    NSBitmapImageRep *canvas = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:NULL pixelsWide:pixels pixelsHigh:pixels bitsPerSample:8
        samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSCalibratedRGBColorSpace
        bytesPerRow:0 bitsPerPixel:0];
    NSGraphicsContext *graphics = [NSGraphicsContext graphicsContextWithBitmapImageRep:canvas];
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext.currentContext = graphics;
    CGContextRef ctx = graphics.CGContext;
    CGContextScaleCTM(ctx, pixels / 100.0, pixels / 100.0);
    NSBezierPath *tile = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(6, 6, 88, 88) xRadius:22 yRadius:22];
    [[NSColor colorWithSRGBRed:.065 green:.23 blue:.28 alpha:1] setFill];
    [tile fill];
    [[NSColor colorWithWhite:1 alpha:.18] setStroke];
    tile.lineWidth = .55;
    [tile stroke];
    [CTBStatusIcon(NO, NO) drawInRect:NSMakeRect(16, 20.5, 68, 61.2)];
    [NSGraphicsContext restoreGraphicsState];
    return [[canvas representationUsingType:NSBitmapImageFileTypePNG properties:@{}]
        writeToFile:path atomically:YES];
}

int main(int argc, const char *argv[]) { @autoreleasepool {
    if (argc != 2) return 2;
    [NSApplication sharedApplication];
    NSString *directory = @(argv[1]);
    for (NSNumber *size in @[@16, @32, @128, @256, @512]) {
        for (NSInteger scale = 1; scale <= 2; scale++) {
            NSString *filename = [NSString stringWithFormat:@"icon_%@x%@%@.png",
                                  size, size, scale == 2 ? @"@2x" : @""];
            if (!WriteIcon([directory stringByAppendingPathComponent:filename], size.integerValue * scale)) return 1;
        }
    }
    return 0;
} }
