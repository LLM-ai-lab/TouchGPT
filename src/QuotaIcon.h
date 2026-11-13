#import <AppKit/AppKit.h>

enum { CTBProgressFrameCount = 12 };

NSImage *CTBQuotaIcon(NSNumber *remaining, BOOL thinking, NSUInteger frame);
NSImage *CTBStatusIcon(BOOL approval, BOOL complete);
NSImage *CTBTaskProgressImage(BOOL complete, NSUInteger frame);
