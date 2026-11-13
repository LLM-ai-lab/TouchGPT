// Documentation fixture: production AppKit views with synthetic state, no Codex connection.
#define main TouchGPTApplicationMain
#import "../src/main.m"
#undef main
#import <ImageIO/ImageIO.h>

@interface DemoBridge : CTBBridge
@property BOOL demoRunning;
@property NSDictionary *demoApproval;
@property NSString *demoCompletion;
@end
@implementation DemoBridge
- (BOOL)running { return _demoRunning; }
- (NSDictionary *)approval { return _demoApproval; }
- (NSString *)completion { return _demoCompletion; }
- (void)decide:(BOOL)allow expected:(NSDictionary *)approval { }
@end
@interface DemoQuota : CTBQuota
@end
@implementation DemoQuota
- (NSNumber *)remaining { return @72; }
- (NSArray *)details { return @[@"演示额度 · 剩余 72%"] ; }
- (void)refresh { }
@end

static void Capture(NSString *path) {
    NSString *raw = [NSTemporaryDirectory() stringByAppendingPathComponent:
                     [NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"png"]];
    NSTask *task = [NSTask new];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/sbin/screencapture"];
    task.arguments = @[@"-x", @"-b", raw];
    [task launchAndReturnError:nil]; [task waitUntilExit];
    if (task.terminationStatus != 0) { fprintf(stderr, "Touch Bar capture failed\n"); exit(1); }
    // Keep original pixels; crop the unused right side for readable README images.
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:raw], NULL);
    CGImageRef full = source ? CGImageSourceCreateImageAtIndex(source, 0, NULL) : NULL;
    if (!full) { fprintf(stderr, "Cannot read Touch Bar capture\n"); exit(1); }
    CGImageRef crop = CGImageCreateWithImageInRect(full, CGRectMake(0, 0, MIN(1000, CGImageGetWidth(full)), CGImageGetHeight(full)));
    CGImageDestinationRef output = CGImageDestinationCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], CFSTR("public.png"), 1, NULL);
    CGImageDestinationAddImage(output, crop, NULL);
    BOOL saved = CGImageDestinationFinalize(output);
    CFRelease(output); CGImageRelease(crop); CGImageRelease(full); CFRelease(source);
    [NSFileManager.defaultManager removeItemAtPath:raw error:nil];
    if (!saved) { fprintf(stderr, "Cannot save screenshot\n"); exit(1); }
}
static void Pause(void) {
    [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.35]];
}
int main(int argc, const char **argv) { @autoreleasepool {
    if (argc != 2) return 2;
    NSString *directory = @(argv[1]);
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    CTBApp *app = [CTBApp new];
    DemoBridge *bridge = [DemoBridge new];
    [app setValue:bridge forKey:@"bridge"];
    [app setValue:[DemoQuota new] forKey:@"quota"];
    [app setValue:@YES forKey:@"foregroundIsCodex"];
    [app setupTouchBar]; [app update]; Pause();
    Capture([directory stringByAppendingPathComponent:@"foreground.png"]);

    bridge.demoRunning = YES; [app update];
    [[app valueForKey:@"thinkingTimer"] invalidate];
    for (NSUInteger frame = 0; frame < CTBProgressFrameCount; frame++) {
        [app setValue:@(frame) forKey:@"thinkingFrame"];
        [app showThinkingFrame]; Pause();
        Capture([NSTemporaryDirectory() stringByAppendingPathComponent:
                 [NSString stringWithFormat:@"touchgpt-progress-%d-%lu.png", NSProcessInfo.processInfo.processIdentifier, (unsigned long)frame]]);
    }
    bridge.demoRunning = NO;
    bridge.demoCompletion = @"已回复 · README 和安装包已准备好";
    [app update]; Pause();
    Capture([directory stringByAppendingPathComponent:@"reply.png"]);

    bridge.demoCompletion = nil;
    bridge.demoApproval = @{@"id": @"documentation-demo", @"method": @"item/commandExecution/requestApproval",
                            @"params": @{@"command": @"git status --short", @"availableDecisions": @[@"accept", @"decline"]}};
    [app update]; Pause();
    Capture([directory stringByAppendingPathComponent:@"approval.png"]);
    [app applicationWillTerminate:[NSNotification notificationWithName:NSApplicationWillTerminateNotification object:NSApp]];

    NSURL *gif = [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"thinking.gif"]];
    CGImageDestinationRef output = CGImageDestinationCreateWithURL((__bridge CFURLRef)gif, CFSTR("com.compuserve.gif"), CTBProgressFrameCount, NULL);
    CGImageDestinationSetProperties(output, (__bridge CFDictionaryRef)@{(id)kCGImagePropertyGIFDictionary: @{(id)kCGImagePropertyGIFLoopCount:@0}});
    for (NSUInteger frame = 0; frame < CTBProgressFrameCount; frame++) {
        NSURL *path = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
                       [NSString stringWithFormat:@"touchgpt-progress-%d-%lu.png", NSProcessInfo.processInfo.processIdentifier, (unsigned long)frame]]];
        CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)path, NULL);
        CGImageDestinationAddImageFromSource(output, source, 0, (__bridge CFDictionaryRef)@{(id)kCGImagePropertyGIFDictionary: @{(id)kCGImagePropertyGIFDelayTime:@(ProgressInterval)}});
        CFRelease(source);
        [NSFileManager.defaultManager removeItemAtURL:path error:nil];
    }
    BOOL saved = CGImageDestinationFinalize(output); CFRelease(output);
    puts(saved ? "Captured production Touch Bar views with demo data" : "Failed to save GIF");
    return saved ? 0 : 1;
} }
