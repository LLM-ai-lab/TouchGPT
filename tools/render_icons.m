#import "QuotaIcon.h"
int main(int argc, const char **argv) { @autoreleasepool {
    if (argc != 2) return 2;
    [NSApplication sharedApplication];
    NSImage *image = [NSImage imageWithSize:NSMakeSize(780, 226) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [[NSColor colorWithWhite:.045 alpha:1] setFill];
        NSRectFill(rect);
        NSArray *quotas = @[@100,@65,@35,@20,@0,@60];
        NSDictionary *style = @{NSFontAttributeName:[NSFont monospacedDigitSystemFontOfSize:14 weight:NSFontWeightMedium],
                                NSForegroundColorAttributeName:[NSColor colorWithWhite:.84 alpha:1]};
        for (NSUInteger i=0; i<7; i++) {
            CGFloat left=25+i*109;
            NSImage *icon = i==6 ? CTBStatusIcon(NO,NO) : CTBQuotaIcon(quotas[i],i==5,1);
            CGFloat largeHeight = 74 * icon.size.height / icon.size.width;
            [icon drawInRect:NSMakeRect(left,116+(74-largeHeight)/2,74,largeHeight)];
            NSString *label = i==6 ? @"菜单栏" : i==5 ? @"思考中" : [NSString stringWithFormat:@"%@%%",quotas[i]];
            NSSize size=[label sizeWithAttributes:style];
            [label drawAtPoint:NSMakePoint(left+(74-size.width)/2,87) withAttributes:style];
            [icon drawInRect:NSMakeRect(left+(74-icon.size.width)/2,37,icon.size.width,icon.size.height)];
        }
        NSDictionary *small = @{NSFontAttributeName:[NSFont systemFontOfSize:10], NSForegroundColorAttributeName:[NSColor colorWithWhite:.45 alpha:1]};
        [@"上排放大预览 · 下排实际尺寸" drawAtPoint:NSMakePoint(25,13) withAttributes:small];
        return YES;
    }];
    NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:image.TIFFRepresentation];
    [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[@(argv[1]) stringByAppendingPathComponent:@"quota-states.png"] atomically:YES];
    NSImage *badges = [NSImage imageWithSize:NSMakeSize(260,90) flipped:NO drawingHandler:^BOOL(NSRect rect) {
        [[NSColor colorWithWhite:.1 alpha:1] setFill]; NSRectFill(rect);
        for (NSUInteger i=0;i<3;i++) [CTBStatusIcon(i==1,i==2) drawInRect:NSMakeRect(10+i*85,18,60,54)];
        return YES;
    }];
    rep = [NSBitmapImageRep imageRepWithData:badges.TIFFRepresentation];
    [[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:[@(argv[1]) stringByAppendingPathComponent:@"menu.png"] atomically:YES];
} }
