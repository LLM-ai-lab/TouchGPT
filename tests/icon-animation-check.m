#define main TouchGPTApplicationMain
#import "../src/main.m"
#undef main

@interface AnimationBridge : CTBBridge
@property BOOL testRunning;
@property NSDictionary *testApproval;
@property NSString *testCompletion;
@end
@implementation AnimationBridge
- (BOOL)running { return _testRunning; }
- (NSDictionary *)approval { return _testApproval; }
- (NSString *)completion { return _testCompletion; }
@end

@interface SetupApp : CTBApp
@property BOOL askedForThread;
@end
@implementation SetupApp
- (void)changeThread:(id)sender { _askedForThread = YES; }
@end

static void Check(BOOL ok, NSString *message) {
    if (!ok) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    Check(ThreadFromLink(nil) == nil && ThreadFromLink(@"") == nil &&
          ThreadFromLink(@"not a thread") == nil, @"empty or invalid saved setting is ignored");
    NSString *thread = NSUUID.UUID.UUIDString.lowercaseString;
    NSString *url = [@"codex://threads/" stringByAppendingString:thread];
    Check([ThreadFromLink(thread.uppercaseString) isEqual:thread] &&
          [ThreadFromLink([@"  " stringByAppendingString:url]) isEqual:thread], @"local links and UUIDs are normalized");
    Check(ThreadFromLink([url stringByAppendingString:@"?hostId=remote"]) == nil &&
          ThreadFromLink([url stringByAppendingString:@"/extra"]) == nil, @"remote and malformed links rejected");
    SetupApp *fresh = [SetupApp new];
    [fresh openChat:nil];
    Check(fresh.askedForThread, @"new user icon opens setup instead of an absent chat");
    puts("PASS: first-run setup and saved-link validation");
    CTBApp *app = [CTBApp new];
    AnimationBridge *bridge = [AnimationBridge new];
    NSButton *left = [NSButton new], *tray = [NSButton new], *progress = [NSButton new];
    [app setValue:bridge forKey:@"bridge"];
    [app setValue:[CTBQuota new] forKey:@"quota"];
    [app setValue:left forKey:@"icon"];
    [app setValue:tray forKey:@"trayButton"];
    [app setValue:progress forKey:@"progress"];
    bridge.testRunning = YES;
    [app updateIcon];
    NSTimer *timer = [app valueForKey:@"thinkingTimer"];
    Check(timer.valid, @"background thinking starts animation");
    NSImage *before = tray.image;
    [timer fire];
    Check(tray.image != before, @"tray advances frames");
    [app setValue:@YES forKey:@"panelShown"];
    [app updateIcon];
    Check([app valueForKey:@"thinkingTimer"] == timer, @"switching position reuses timer");
    before = progress.image;
    Check(before != nil && !progress.hidden, @"foreground shows a full progress bar");
    NSImage *hidden = tray.image;
    [timer fire];
    Check(progress.image != before && tray.image == hidden, @"foreground animates the progress bar only");
    NSArray<NSImage *> *frames = [app valueForKey:@"thinkingFrames"];
    Check(![frames[0].TIFFRepresentation isEqual:frames[1].TIFFRepresentation] &&
          ![frames[1].TIFFRepresentation isEqual:frames[2].TIFFRepresentation], @"three distinct rendered frames");
    bridge.testApproval = @{@"id": @1};
    [app updateIcon];
    Check(!timer.valid && [app valueForKey:@"thinkingTimer"] == nil, @"approval stops animation");
    Check(progress.hidden, @"approval takes the progress bar's space");
    bridge.testApproval = nil;
    [app updateIcon];
    timer = [app valueForKey:@"thinkingTimer"];
    Check(timer.valid, @"thinking resumes after approval");
    bridge.testRunning = NO;
    bridge.testCompletion = @"已回复";
    [app updateIcon];
    Check(!timer.valid && !progress.hidden && progress.image == CTBTaskProgressImage(YES, 0),
          @"completed turn replaces animation with the full bar");
    bridge.testCompletion = nil;
    [app updateIcon];
    Check(!timer.valid && [app valueForKey:@"thinkingTimer"] == nil, @"idle has no animation timer");
    Check(progress.hidden, @"dismissing the reply hides the completed bar");
    Check(left.image == tray.image, @"both positions restore idle icon");
    Check(NSEqualSizes(CTBStatusIcon(NO,NO).size, NSMakeSize(20,18)), @"menu icon fits status item");
    puts("PASS: tray/foreground animation, frame rendering, timer reuse, approval/idle stop, menu size");
} }
