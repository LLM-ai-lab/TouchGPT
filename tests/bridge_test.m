#import "Bridge.h"
#import <Foundation/Foundation.h>

int main(int argc, const char **argv) {
    @autoreleasepool {
        CTBBridge *bridge = [CTBBridge new];
        if (argc != 3) return 2;
        NSString *thread = @(argv[1]);
        BOOL allow = [@(argv[2]) isEqual:@"allow"];
        __block BOOL asked = NO;
        __block BOOL completed = NO;
        __block BOOL tested = NO;
        __weak CTBBridge *weakBridge = bridge;
        bridge.changed = ^{
            CTBBridge *current = weakBridge;
            if (current.approval && !asked) {
                asked = YES;
                [current decide:allow expected:@{@"id": @"different"}];
                [current decide:allow expected:current.approval];
            }
            if (asked && !current.awaitingDecision && !current.approval &&
                [current.completion containsString:@"已验证"]) {
                completed = YES;
            }
            if (completed && current.running && !current.completion) tested = YES;
        };
        [bridge follow:thread];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:8];
        while (!tested && deadline.timeIntervalSinceNow > 0) {
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        }
        [bridge stop];
        puts(tested ? "PASS: approval, stale input, completion excerpt, and next turn" : "FAIL: bridge timeout");
        return tested ? 0 : 1;
    }
}
