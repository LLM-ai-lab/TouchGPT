#import "TouchBarProbe.h"
#import <CoreGraphics/CoreGraphics.h>
#import <IOSurface/IOSurface.h>
#import <dlfcn.h>

static BOOL AppControlsAreEmpty(IOSurfaceRef surface, CGFloat stripStart) {
    if (!surface || IOSurfaceGetPixelFormat(surface) != 'BGRA' ||
        IOSurfaceLock(surface, kIOSurfaceLockReadOnly, NULL) != kIOReturnSuccess) return NO;
    size_t width = IOSurfaceGetWidth(surface);
    size_t height = IOSurfaceGetHeight(surface);
    size_t strip = (size_t)(width * stripStart);
    size_t pitch = IOSurfaceGetBytesPerRow(surface);
    const uint8_t *pixels = IOSurfaceGetBaseAddress(surface);
    BOOL appHasControls = NO;
    BOOL stripIsLit = NO;
    if (pixels && pitch >= width * 4 && height >= 12) {
        for (size_t y = 3; y + 3 < height && !appHasControls; y += 3) {
            const uint8_t *row = pixels + y * pitch;
            for (size_t x = 0; x < width; x += 3) {
                const uint8_t *pixel = row + x * 4;
                if (pixel[0] < 28 && pixel[1] < 28 && pixel[2] < 28) continue;
                if (x < strip) {
                    appHasControls = YES;
                    break;
                }
                stripIsLit = YES;
            }
        }
    }
    IOSurfaceUnlock(surface, kIOSurfaceLockReadOnly, NULL);
    return stripIsLit && !appHasControls;
}

void CTBProbeTouchBar(void *framework, CTBTouchBarProbeResult result) {
    if (!framework) { result(NO); return; }
    id (*mainBar)(void) = dlsym(framework, "DFRTouchBarGetMain");
    CGRect (*placementRect)(NSInteger) = dlsym(framework, "DFRGetScreenRectForPlacement");
    CGDisplayStreamRef (*createStream)(id, CFDictionaryRef, dispatch_queue_t, CGDisplayStreamFrameAvailableHandler) =
        dlsym(framework, "DFRTouchBarCreateDisplayStream");
    CGError (*startStream)(CGDisplayStreamRef) = dlsym(RTLD_DEFAULT, "CGDisplayStreamStart");
    CGError (*stopStream)(CGDisplayStreamRef) = dlsym(RTLD_DEFAULT, "CGDisplayStreamStop");
    if (!mainBar || !placementRect || !createStream || !startStream || !stopStream) { result(NO); return; }

    // The system reports the app-controls and Control Strip boundaries in points.
    CGRect controls = placementRect(0);
    CGRect strip = placementRect(1);
    CGFloat right = CGRectGetMaxX(strip);
    CGFloat left = CGRectGetMinX(strip);
    id bar = mainBar();
    if (!bar || right <= left || left <= 0 || fabs(CGRectGetMaxX(controls) - left) > 1) {
        result(NO);
        return;
    }

    __block BOOL sawEmptyControls = NO;
    __block BOOL sawAppControls = NO;
    CGDisplayStreamRef stream = createStream(bar, NULL, dispatch_get_main_queue(),
        ^(CGDisplayStreamFrameStatus status, uint64_t time, IOSurfaceRef surface, CGDisplayStreamUpdateRef update) {
            if (status != kCGDisplayStreamFrameStatusFrameComplete || !surface) return;
            BOOL empty = AppControlsAreEmpty(surface, left / right);
            sawEmptyControls |= empty;
            sawAppControls |= !empty;
        });
    if (!stream) { result(NO); return; }
    if (startStream(stream) != kCGErrorSuccess) {
        CFRelease(stream);
        result(NO);
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 180 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        stopStream(stream);
        CFRelease(stream);
        result(sawEmptyControls && !sawAppControls);
    });
}
