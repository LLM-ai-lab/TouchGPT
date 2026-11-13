#import "QuotaIcon.h"

static NSImage *TouchGlyph(void);

static void DrawProgressTrack(NSRect track, BOOL complete, NSUInteger frame) {
    NSBezierPath *outline = [NSBezierPath bezierPathWithRoundedRect:track
                                                          xRadius:NSHeight(track) / 2
                                                          yRadius:NSHeight(track) / 2];
    [[NSColor colorWithWhite:1 alpha:.20] setFill];
    [outline fill];
    [NSGraphicsContext saveGraphicsState];
    [outline addClip];
    if (complete) {
        [[NSColor colorWithSRGBRed:.41 green:.89 blue:.63 alpha:1] setFill];
        NSRectFill(track);
    } else {
        CGFloat segment = NSWidth(track) * .36;
        CGFloat phase = (frame % CTBProgressFrameCount) / (CGFloat)(CTBProgressFrameCount - 1);
        track.origin.x += (NSWidth(track) - segment) * (1 - fabs(2 * phase - 1));
        track.size.width = segment;
        [[NSColor colorWithSRGBRed:.39 green:.83 blue:1 alpha:1] setFill];
        [[NSBezierPath bezierPathWithRoundedRect:track xRadius:NSHeight(track) / 2
                                                yRadius:NSHeight(track) / 2] fill];
    }
    [NSGraphicsContext restoreGraphicsState];
}

NSImage *CTBTaskProgressImage(BOOL complete, NSUInteger frame) {
    static NSImage *images[CTBProgressFrameCount + 1];
    NSUInteger index = complete ? CTBProgressFrameCount : frame % CTBProgressFrameCount;
    if (!images[index]) {
        images[index] = [NSImage imageWithSize:NSMakeSize(150, 24) flipped:NO drawingHandler:^BOOL(NSRect rect) {
            NSString *label = complete ? @"已完成" : @"处理中…";
            [label drawAtPoint:NSMakePoint(3, 4) withAttributes:@{
                NSFontAttributeName: [NSFont systemFontOfSize:12 weight:NSFontWeightMedium],
                NSForegroundColorAttributeName: NSColor.whiteColor,
            }];
            DrawProgressTrack(NSMakeRect(57, 9, 90, 6), complete, frame);
            return YES;
        }];
    }
    return images[index];
}

NSImage *CTBQuotaIcon(NSNumber *remaining, BOOL thinking, NSUInteger frame) {
    NSImage *mark = TouchGlyph();
    return [NSImage imageWithSize:NSMakeSize(29, 29) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        CGContextRef ctx = NSGraphicsContext.currentContext.CGContext;
        CGContextSaveGState(ctx);
        CGContextTranslateCTM(ctx, NSMinX(rect), NSMinY(rect));
        CGContextScaleCTM(ctx, NSWidth(rect) / 29, NSHeight(rect) / 29);
        CGContextSetLineCap(ctx, kCGLineCapRound);

        CGFloat energy = remaining ? fmax(0, fmin(1, remaining.doubleValue / 100)) : .5;
        BOOL low = remaining && energy <= .2;
        CGContextSetRGBStrokeColor(ctx, low ? .40 : .31, low ? .12 : .31, low ? .14 : .31, 1);
        CGContextSetLineWidth(ctx, 1.4);
        CGContextStrokeEllipseInRect(ctx, CGRectMake(1.25, 1.25, 26.5, 26.5));
        if (remaining && energy > 0) {
            CGContextSetRGBStrokeColor(ctx, low ? 1 : .85, low ? .31 : .85, low ? .36 : .85, 1);
            CGContextSetLineWidth(ctx, 1.75);
            CGContextAddArc(ctx, 14.5, 14.5, 13.25, M_PI_2, M_PI_2 - energy * M_PI * 2, YES);
            CGContextStrokePath(ctx);
        }

        [mark drawInRect:thinking ? NSMakeRect(5.5, 4.3, 18, 16.2) : NSMakeRect(4.5, 5.5, 20, 18)];
        if (thinking) {
            DrawProgressTrack(NSMakeRect(7.5, 21.9, 14, 2.8), NO, frame);
        }
        CGContextRestoreGState(ctx);
        return YES;
    }];
}

// Clear a narrow margin so the hand reads separately from the Touch Bar.
static void DrawTouchHand(CGContextRef ctx) {
    CGMutablePathRef hand = CGPathCreateMutable();
    CGPathMoveToPoint(hand, NULL, 12.6, 1.0);
    CGPathAddLineToPoint(hand, NULL, 17.5, 1.0);
    CGPathAddCurveToPoint(hand, NULL, 18.1, 2.6, 19.0, 4.8, 18.8, 6.4);
    CGPathAddCurveToPoint(hand, NULL, 18.7, 7.4, 17.6, 7.9, 16.7, 7.6);
    CGPathAddCurveToPoint(hand, NULL, 16.3, 8.6, 15.0, 8.9, 14.2, 8.4);
    CGPathAddLineToPoint(hand, NULL, 14.2, 12.4);
    CGPathAddCurveToPoint(hand, NULL, 14.2, 14.0, 12.0, 14.0, 12.0, 12.4);
    CGPathAddLineToPoint(hand, NULL, 12.0, 5.8);
    CGPathAddLineToPoint(hand, NULL, 10.6, 7.0);
    CGPathAddCurveToPoint(hand, NULL, 9.4, 8.0, 8.2, 6.5, 9.3, 5.3);
    CGPathAddLineToPoint(hand, NULL, 12.6, 1.0);
    CGPathCloseSubpath(hand);
    CGContextSaveGState(ctx);
    CGContextSetLineJoin(ctx, kCGLineJoinRound);
    CGContextSetBlendMode(ctx, kCGBlendModeClear);
    CGContextSetLineWidth(ctx, 2.6);
    CGContextAddPath(ctx, hand);
    CGContextDrawPath(ctx, kCGPathFillStroke);
    CGContextSetBlendMode(ctx, kCGBlendModeNormal);
    CGContextSetRGBStrokeColor(ctx, 1, 1, 1, 1);
    CGContextSetLineWidth(ctx, 1.15);
    CGContextAddPath(ctx, hand);
    CGContextStrokePath(ctx);
    CGContextRestoreGState(ctx);
    CGPathRelease(hand);
}

// Shared artwork for the menu, the Touch Bar and the Finder icon renderer.
static void DrawTouchGlyph(CGContextRef ctx) {
    CGContextSaveGState(ctx);
    CGContextSetRGBStrokeColor(ctx, 1, 1, 1, 1);
    CGContextSetRGBFillColor(ctx, 1, 1, 1, 1);
    CGContextSetLineWidth(ctx, 1.15);
    CGContextSetLineCap(ctx, kCGLineCapRound);
    CGPathRef strip = CGPathCreateWithRoundedRect(CGRectMake(1, 9.8, 16.7, 6.4), 2.2, 2.2, NULL);
    CGContextAddPath(ctx, strip);
    CGContextStrokePath(ctx);
    CGPathRelease(strip);
    CGContextFillEllipseInRect(ctx, CGRectMake(3.8, 12.25, 1.5, 1.5));
    CGContextMoveToPoint(ctx, 7.4, 13);
    CGContextAddLineToPoint(ctx, 9, 13);
    CGContextStrokePath(ctx);
    DrawTouchHand(ctx);
    CGContextRestoreGState(ctx);
}

static NSImage *TouchGlyph(void) {
    static NSImage *mark;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        mark = [NSImage imageWithSize:NSMakeSize(20, 18) flipped:NO drawingHandler:^BOOL(NSRect rect) {
            DrawTouchGlyph(NSGraphicsContext.currentContext.CGContext);
            return YES;
        }];
    });
    return mark;
}

NSImage *CTBStatusIcon(BOOL approval, BOOL complete) {
    static NSArray<NSImage *> *icons;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *images = [NSMutableArray arrayWithCapacity:3];
        for (NSUInteger state = 0; state < 3; state++) {
            NSImage *icon = [NSImage imageWithSize:NSMakeSize(20, 18) flipped:NO drawingHandler:^BOOL(NSRect rect) {
                CGContextRef ctx = NSGraphicsContext.currentContext.CGContext;
                DrawTouchGlyph(ctx);
                if (state) {
                    // Put the status mark inside the palm.
                    CGContextSaveGState(ctx);
                    CGContextSetRGBStrokeColor(ctx, 1, 1, 1, 1);
                    CGContextSetRGBFillColor(ctx, 1, 1, 1, 1);
                    CGContextSetLineWidth(ctx, .8);
                    CGContextSetLineCap(ctx, kCGLineCapRound);
                    if (state == 1) {
                        CGContextMoveToPoint(ctx, 15, 6.2);
                        CGContextAddLineToPoint(ctx, 15, 4.8);
                        CGContextStrokePath(ctx);
                        CGContextFillEllipseInRect(ctx, CGRectMake(14.6, 3.3, .8, .8));
                    } else {
                        CGContextMoveToPoint(ctx, 13.4, 4.7);
                        CGContextAddLineToPoint(ctx, 14.5, 3.6);
                        CGContextAddLineToPoint(ctx, 16.5, 5.8);
                        CGContextStrokePath(ctx);
                    }
                    CGContextRestoreGState(ctx);
                }
                return YES;
            }];
            icon.template = YES;
            icon.accessibilityDescription = state == 1 ? @"Touch GPT：等待确认" :
                                            state == 2 ? @"Touch GPT：回复完成" : @"Touch GPT";
            [images addObject:icon];
        }
        icons = [images copy];
    });
    return icons[approval ? 1 : complete ? 2 : 0];
}
