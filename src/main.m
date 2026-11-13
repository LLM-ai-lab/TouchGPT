#import <AppKit/AppKit.h>
#import <ServiceManagement/ServiceManagement.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <signal.h>
#import <os/log.h>
#import "Bridge.h"
#import "QuotaIcon.h"
#import "TouchBarProbe.h"

static NSString *const CodexBundle = @"com.openai.codex";
static NSString *const TrayIdentifier = @"local.codex-touchbar.tray";
static NSString *const BarIdentifier = @"local.codex-touchbar.controls";
static const NSTimeInterval ProgressInterval = .15;

static NSString *ThreadFromLink(NSString *input) {
    if (![input isKindOfClass:NSString.class]) return nil;
    NSString *text = [input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!text.length) return nil;
    if ([[NSUUID alloc] initWithUUIDString:text]) return text.lowercaseString;
    NSURLComponents *url = [NSURLComponents componentsWithString:text];
    NSString *identifier = url.path.lastPathComponent;
    if (![url.scheme isEqual:@"codex"] || ![url.host isEqual:@"threads"] ||
        ![[NSUUID alloc] initWithUUIDString:identifier] ||
        ![url.path isEqual:[@"/" stringByAppendingString:identifier ?: @""]]) return nil;
    for (NSURLQueryItem *query in url.queryItems) {
        if ([query.name isEqual:@"hostId"] && ![query.value isEqual:@"local"]) return nil;
    }
    return identifier.lowercaseString;
}

@interface CTBButton : NSButton
@property (nonatomic) NSDictionary *request;
@end
@implementation CTBButton
@end

@interface CTBApp : NSObject <NSApplicationDelegate>
@end

@implementation CTBApp {
    CTBBridge *_bridge;
    CTBQuota *_quota;
    NSString *_thread;
    NSStatusItem *_status;
    NSTouchBar *_bar;
    NSCustomTouchBarItem *_trayItem;
    NSStackView *_row;
    NSButton *_trayButton;
    NSButton *_icon;
    NSButton *_progress;
    NSButton *_preview;
    NSButton *_reply;
    CTBButton *_allow;
    CTBButton *_reject;
    NSDictionary *_shownApproval;
    NSTimer *_quotaTimer;
    NSTimer *_layoutTimer;
    NSTimer *_thinkingTimer;
    NSArray<NSImage *> *_thinkingFrames;
    NSImage *_idleIcon;
    NSNumber *_renderedQuota;
    NSUInteger _thinkingFrame;
    NSUInteger _layoutGeneration;
    BOOL _panelAvailable;
    BOOL _panelShown;
    BOOL _foregroundIsCodex;
    BOOL _foregroundControlsEmpty;
    void *_touchBarFramework;
    BOOL _demo;
    BOOL _demoPending;
    void (*_setStripPresence)(NSString *, BOOL);
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    _thread = ThreadFromLink([NSUserDefaults.standardUserDefaults stringForKey:@"Thread"]);
    _bridge = [CTBBridge new];
    _quota = [CTBQuota new];
    __weak CTBApp *weakSelf = self;
    _bridge.changed = ^{ [weakSelf update]; };
    _quota.changed = ^{ [weakSelf update]; };

    _status = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
    _status.button.image = CTBStatusIcon(NO, NO);

    [self setupTouchBar];
    if (_thread) [_bridge follow:_thread];
    [_quota refresh];
    _quotaTimer = [NSTimer scheduledTimerWithTimeInterval:300 repeats:YES block:^(NSTimer *timer) {
        [weakSelf refreshQuota:nil];
    }];
    _quotaTimer.tolerance = 30;
    NSNotificationCenter *workspaceEvents = NSWorkspace.sharedWorkspace.notificationCenter;
    [workspaceEvents addObserver:self selector:@selector(woke:) name:NSWorkspaceDidWakeNotification object:nil];
    [workspaceEvents addObserver:self selector:@selector(frontmostAppChanged:)
                            name:NSWorkspaceDidActivateApplicationNotification object:nil];
    [workspaceEvents addObserver:self selector:@selector(frontmostAppChanged:)
                            name:NSWorkspaceSessionDidBecomeActiveNotification object:nil];
    [workspaceEvents addObserver:self selector:@selector(frontmostAppChanged:)
                            name:NSWorkspaceDidTerminateApplicationNotification object:nil];
    [workspaceEvents addObserver:self selector:@selector(frontmostAppChanged:)
                            name:NSWorkspaceDidLaunchApplicationNotification object:nil];
    [self frontmostAppChanged:nil];
    NSArray *arguments = NSProcessInfo.processInfo.arguments;
    if ([arguments containsObject:@"--demo"]) [self toggleDemo:nil];
    else [self update];
    if ([arguments containsObject:@"--open-chat"]) [self openChat:nil];
}

- (NSButton *)button:(NSString *)title width:(CGFloat)width action:(SEL)action {
    NSButton *button = [NSButton buttonWithTitle:title target:self action:action];
    button.bezelStyle = NSBezelStyleRounded;
    [button.widthAnchor constraintEqualToConstant:width].active = YES;
    return button;
}

- (NSStackView *)barRow:(NSArray<NSView *> *)views {
    NSStackView *row = [NSStackView stackViewWithViews:views];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.spacing = 6;
    row.alignment = NSLayoutAttributeCenterY;
    return row;
}

- (void)setupTouchBar {
    _icon = [self button:@"" width:40 action:@selector(openChat:)];
    _icon.imagePosition = NSImageOnly;
    _icon.bordered = NO;
    _progress = [self button:@"" width:172 action:@selector(openChat:)];
    _progress.imagePosition = NSImageOnly;
    _progress.hidden = YES;
    _preview = [self button:@"" width:226 action:@selector(acknowledge:)];
    _preview.alignment = NSTextAlignmentLeft;
    _preview.lineBreakMode = NSLineBreakByTruncatingTail;
    _reply = [self button:@"" width:144 action:@selector(dismissReply:)];
    _reply.alignment = NSTextAlignmentLeft;
    _reply.lineBreakMode = NSLineBreakByTruncatingTail;
    _row = [self barRow:@[_icon, _progress, _reply, _preview]];
    _reply.hidden = YES;
    _preview.hidden = YES;

    _bar = [NSTouchBar new];
    NSCustomTouchBarItem *item = [[NSCustomTouchBarItem alloc] initWithIdentifier:BarIdentifier];
    item.view = _row;
    _bar.templateItems = [NSSet setWithObject:item];
    _bar.defaultItemIdentifiers = @[BarIdentifier, NSTouchBarItemIdentifierFlexibleSpace];
    // Private AppKit entry points are resolved at runtime so menu controls remain available if they change.
    _touchBarFramework = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/Versions/A/DFRFoundation", RTLD_LAZY | RTLD_LOCAL);
    if (!_touchBarFramework) return;
    _setStripPresence = dlsym(_touchBarFramework, "DFRElementSetControlStripPresenceForIdentifier");
    SEL addTray = NSSelectorFromString(@"addSystemTrayItem:");
    _panelAvailable = [NSTouchBar respondsToSelector:NSSelectorFromString(@"presentSystemModalTouchBar:systemTrayItemIdentifier:")] &&
                      [NSTouchBar respondsToSelector:NSSelectorFromString(@"minimizeSystemModalTouchBar:")];
    if (_setStripPresence && [NSTouchBarItem respondsToSelector:addTray]) {
        _trayButton = [NSButton buttonWithImage:CTBQuotaIcon(nil, NO, 0) target:self action:@selector(openChat:)];
        _trayButton.imagePosition = NSImageOnly;
        _trayItem = [[NSCustomTouchBarItem alloc] initWithIdentifier:TrayIdentifier];
        _trayItem.view = _trayButton;
        ((void (*)(id, SEL, id))objc_msgSend)(NSTouchBarItem.class, addTray, _trayItem);
        _setStripPresence(TrayIdentifier, YES);
    }
}

- (void)showPanel {
    if (!_panelAvailable || _panelShown) return;
    _panelShown = YES;
    ((void (*)(id, SEL, id, id))objc_msgSend)(NSTouchBar.class,
        NSSelectorFromString(@"presentSystemModalTouchBar:systemTrayItemIdentifier:"), _bar,
        _trayItem ? TrayIdentifier : nil);
    os_log(OS_LOG_DEFAULT, "Touch Bar: showed Codex panel");
}

- (void)minimizeBar {
    SEL selector = NSSelectorFromString(@"minimizeSystemModalTouchBar:");
    if (_panelAvailable && _panelShown) {
        _panelShown = NO;
        ((void (*)(id, SEL, id))objc_msgSend)(NSTouchBar.class, selector, _bar);
        if (_trayItem) _setStripPresence(TrayIdentifier, YES);
        os_log(OS_LOG_DEFAULT, "Touch Bar: returned to Control Strip");
    }
}

- (BOOL)hasAlert {
    if (_demo) return YES;
    return _bridge.completion.length || _bridge.approval || _bridge.notice.length;
}

- (BOOL)shouldShowPanel {
    if ([self hasAlert] && !_bridge.awaitingDecision) return YES;
    return _foregroundIsCodex || _foregroundControlsEmpty;
}

- (void)applyLayout {
    if ([self shouldShowPanel]) [self showPanel];
    else if (_panelShown) {
        [self minimizeBar];
        [self scheduleForegroundProbe];
    }
}

- (void)acknowledge:(id)sender {
    if (_demo) {
        [self toggleDemo:nil];
    } else if (_bridge.approval) {
        [self openChat:nil];
    } else {
        [_bridge clearCompletion];
    }
}

- (void)dismissReply:(id)sender {
    [_bridge clearCompletion];
}

- (NSString *)approvalPreview:(NSDictionary *)request {
    NSDictionary *params = request[@"params"];
    NSString *kind = @"权限";
    if ([request[@"method"] isEqual:@"item/commandExecution/requestApproval"]) kind = @"命令";
    if ([request[@"method"] isEqual:@"item/fileChange/requestApproval"]) kind = @"文件";
    id detail = params[@"command"];
    if (![detail isKindOfClass:NSString.class] || ![detail length]) detail = params[@"reason"];
    if (![detail isKindOfClass:NSString.class] || ![detail length]) return [@"审批 · " stringByAppendingString:kind];
    NSRange range = [detail rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, MIN([detail length], 140))];
    NSString *line = [[detail substringWithRange:range] stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    return [NSString stringWithFormat:@"%@ · %@", kind, line];
}

- (CTBButton *)decisionButton:(BOOL)allow approval:(NSDictionary *)request {
    CTBButton *button = [[CTBButton alloc] initWithFrame:NSZeroRect];
    button.title = allow ? @"Allow" : @"Reject";
    button.bezelStyle = NSBezelStyleRounded;
    button.target = self;
    button.action = allow ? @selector(allow:) : @selector(reject:);
    button.request = request;
    [button.widthAnchor constraintEqualToConstant:67].active = YES;
    return button;
}

- (NSDictionary *)demoApproval {
    return @{@"id": @"preview", @"method": @"item/commandExecution/requestApproval",
             @"params": @{@"command": @"git status --short"}};
}

- (void)showThinkingFrame {
    if (_panelShown) _progress.image = CTBTaskProgressImage(NO, _thinkingFrame);
    else _trayButton.image = _thinkingFrames[_thinkingFrame];
}

- (void)updateThinkingFrame:(NSTimer *)timer {
    _thinkingFrame = (_thinkingFrame + 1) % CTBProgressFrameCount;
    [self showThinkingFrame];
}

- (void)updateIcon {
    NSNumber *remaining = _quota.remaining;
    if (!_idleIcon || ![_renderedQuota ?: @(-1) isEqual:remaining ?: @(-1)]) {
        _renderedQuota = remaining;
        _idleIcon = CTBQuotaIcon(remaining, NO, 0);
        _thinkingFrames = nil;
    }
    BOOL thinking = _bridge.running && ![self hasAlert] && !_bridge.awaitingDecision;
    BOOL complete = _demo ? !_demoPending :
        (_bridge.completion.length && !_bridge.approval && !_bridge.notice.length && !_bridge.awaitingDecision);
    _progress.hidden = !thinking && !complete;
    _progress.accessibilityLabel = complete ? @"已完成" : @"处理中";
    _progress.image = complete ? CTBTaskProgressImage(YES, 0) : nil;
    _icon.image = _idleIcon;
    if (thinking && !_thinkingFrames) {
        NSMutableArray<NSImage *> *frames = [NSMutableArray arrayWithCapacity:CTBProgressFrameCount];
        for (NSUInteger frame = 0; frame < CTBProgressFrameCount; frame++) {
            [frames addObject:CTBQuotaIcon(remaining, YES, frame)];
        }
        _thinkingFrames = frames;
    }
    if (thinking && (_panelShown || _trayButton)) {
        if (!_thinkingTimer) {
            _thinkingFrame = 0;
            _thinkingTimer = [NSTimer timerWithTimeInterval:ProgressInterval target:self
                              selector:@selector(updateThinkingFrame:) userInfo:nil repeats:YES];
            _thinkingTimer.tolerance = .025;
            [NSRunLoop.mainRunLoop addTimer:_thinkingTimer forMode:NSRunLoopCommonModes];
        }
        [self showThinkingFrame];
    } else {
        [_thinkingTimer invalidate];
        _thinkingTimer = nil;
        _trayButton.image = _idleIcon;
    }
    NSString *badge = remaining ? [NSString stringWithFormat:@"Touch GPT · 剩余 %@%%", remaining] : @"Touch GPT · 额度暂不可用";
    if (thinking) badge = [badge stringByAppendingString:@" · 处理中"];
    if (!_thread) badge = [badge stringByAppendingString:@" · 请先选择对话"];
    [_icon setAccessibilityLabel:badge];
    [_trayButton setAccessibilityLabel:badge];
    _status.button.toolTip = badge;
}

- (void)update {
    NSDictionary *approval = _demo ? (_demoPending ? [self demoApproval] : nil) : _bridge.approval;
    NSString *text = _demo ? (approval ? [self approvalPreview:approval] : @"已回复 · 触控条通知演示") :
        (approval ? [self approvalPreview:approval] : (_bridge.notice ?: _bridge.completion));
    BOOL showText = text.length > 0 || _bridge.awaitingDecision;
    _preview.title = _bridge.awaitingDecision && !_demo ? @"正在提交审批…" : (text ?: @"");
    _preview.hidden = !showText;
    _reply.hidden = _demo || !approval || !_bridge.completion.length;
    _reply.title = _reply.hidden ? @"" : _bridge.completion;

    if (approval != _shownApproval && ![_shownApproval isEqual:approval]) {
        [_allow removeFromSuperview];
        [_reject removeFromSuperview];
        _shownApproval = approval;
        _allow = nil;
        _reject = nil;
        if (approval) {
            _allow = [self decisionButton:YES approval:approval];
            _reject = [self decisionButton:NO approval:approval];
            [_row addArrangedSubview:_allow];
            [_row addArrangedSubview:_reject];
        }
    }
    NSArray *decisions = approval[@"params"][@"availableDecisions"];
    _allow.enabled = !_bridge.awaitingDecision && (![decisions isKindOfClass:NSArray.class] || [decisions containsObject:@"accept"]);
    _reject.enabled = !_bridge.awaitingDecision && (![decisions isKindOfClass:NSArray.class] || [decisions containsObject:@"decline"]);

    [self applyLayout];
    [self updateIcon];
    _status.button.image = CTBStatusIcon(approval != nil, _bridge.completion != nil);
    [self updateMenu];
}

- (NSMenuItem *)item:(NSString *)title action:(SEL)selector menu:(NSMenu *)menu {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:selector keyEquivalent:@""];
    item.target = self;
    item.enabled = selector != NULL;
    [menu addItem:item];
    return item;
}

- (void)updateMenu {
    NSMenu *menu = [NSMenu new];
    menu.autoenablesItems = NO;
    [self item:(_thread ? @"打开关注的 Codex 对话" : @"设置关注的对话…") action:@selector(openChat:) menu:menu];
    if (_thread) [self item:@"更换关注的对话…" action:@selector(changeThread:) menu:menu];
    NSString *connection = !_thread ? @"对话状态 · 尚未选择对话" :
                           !_bridge.connected ? @"对话状态 · 等待 Codex 连接" :
                           _bridge.running ? @"对话状态 · 处理中" : @"对话状态 · 已连接";
    [self item:connection action:NULL menu:menu];
    if (_bridge.completion) [self item:@"查看已完成的回复" action:@selector(openChat:) menu:menu];
    if (_bridge.approval) [self item:@"在 Codex 中查看待审批请求" action:@selector(openChat:) menu:menu];
    if (_bridge.notice) [self item:_bridge.notice action:@selector(openChat:) menu:menu];
    [menu addItem:NSMenuItem.separatorItem];
    for (NSString *detail in _quota.details) [self item:detail action:NULL menu:menu];
    [self item:@"刷新额度" action:@selector(refreshQuota:) menu:menu];
    [menu addItem:NSMenuItem.separatorItem];
    if (_demo) {
        [self item:@"退出触控条演示" action:@selector(toggleDemo:) menu:menu];
    } else {
        [self item:@"演示回复通知" action:@selector(demoReply:) menu:menu];
        [self item:@"演示审批" action:@selector(toggleDemo:) menu:menu];
    }
    if (@available(macOS 13, *)) {
        NSMenuItem *login = [self item:@"登录时启动" action:@selector(toggleLogin:) menu:menu];
        login.state = SMAppService.mainAppService.status == SMAppServiceStatusEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    }
    [menu addItem:NSMenuItem.separatorItem];
    [self item:@"退出 Touch GPT" action:@selector(quit:) menu:menu];
    _status.menu = menu;
}

- (void)openChat:(id)sender {
    if (_demo) [self toggleDemo:nil];
    if (!_thread) { [self changeThread:sender]; return; }
    NSURL *url = [NSURL URLWithString:[@"codex://threads/" stringByAppendingString:_thread]];
    NSWorkspace *workspace = NSWorkspace.sharedWorkspace;
    NSURL *app = [workspace URLForApplicationWithBundleIdentifier:CodexBundle];
    if (!app) return;
    NSString *openingThread = _thread;
    NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
    configuration.activates = YES;
    [workspace openURLs:@[url] withApplicationAtURL:app configuration:configuration
      completionHandler:^(NSRunningApplication *application, NSError *error) {
        if (!error) dispatch_async(dispatch_get_main_queue(), ^{
            os_log(OS_LOG_DEFAULT, "Opened Codex chat URL in the desktop app");
            if ([openingThread isEqual:self->_thread]) {
                [self->_bridge clearCompletion];
                [self frontmostAppChanged:nil];
            }
        });
    }];
}

- (void)changeThread:(id)sender {
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"关注一个 Codex 对话";
    alert.informativeText = @"粘贴 Codex 对话链接或对话 ID。";
    [alert addButtonWithTitle:@"保存"];
    [alert addButtonWithTitle:@"取消"];
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 380, 25)];
    field.stringValue = _thread ? [@"codex://threads/" stringByAppendingString:_thread] : @"";
    field.placeholderString = @"codex://threads/…";
    alert.accessoryView = field;
    alert.window.initialFirstResponder = field;
    if (@available(macOS 14, *)) [NSApp activate];
    else [NSApp activateIgnoringOtherApps:YES];
    while ([alert runModal] == NSAlertFirstButtonReturn) {
        NSString *thread = ThreadFromLink(field.stringValue);
        if (!thread) {
            alert.informativeText = @"请输入有效的本机 Codex 对话链接或对话 ID。";
            continue;
        }
        _thread = thread;
        [NSUserDefaults.standardUserDefaults setObject:thread forKey:@"Thread"];
        [_bridge follow:thread];
        [self openChat:nil];
        break;
    }
}

- (void)toggleLogin:(id)sender API_AVAILABLE(macos(13.0)) {
    NSError *error;
    SMAppService *service = SMAppService.mainAppService;
    BOOL success = service.status == SMAppServiceStatusEnabled ? [service unregisterAndReturnError:&error] : [service registerAndReturnError:&error];
    if (!success && error) {
        NSAlert *alert = [NSAlert alertWithError:error];
        if (@available(macOS 14, *)) [NSApp activate];
        else [NSApp activateIgnoringOtherApps:YES];
        [alert runModal];
    }
    [self updateMenu];
}

- (void)toggleDemo:(id)sender {
    _demo = !_demo;
    _demoPending = _demo;
    [self update];
}

- (void)demoReply:(id)sender {
    _demo = YES;
    _demoPending = NO;
    [self update];
}

- (void)allow:(CTBButton *)sender { [self decide:YES sender:sender]; }
- (void)reject:(CTBButton *)sender { [self decide:NO sender:sender]; }
- (void)decide:(BOOL)allow sender:(CTBButton *)sender {
    if (sender != _allow && sender != _reject) return;
    if (_demo) {
        if (!_demoPending || ![sender.request[@"id"] isEqual:@"preview"]) return;
        [self toggleDemo:nil];
    } else {
        [_bridge decide:allow expected:sender.request];
        if (_bridge.awaitingDecision) [_bridge clearCompletion];
    }
}

- (void)refreshQuota:(id)sender { [_quota refresh]; }

- (void)frontmostAppChanged:(NSNotification *)notification {
    NSRunningApplication *changed = notification.userInfo[NSWorkspaceApplicationKey];
    if (([notification.name isEqual:NSWorkspaceDidTerminateApplicationNotification] ||
         [notification.name isEqual:NSWorkspaceDidLaunchApplicationNotification]) &&
        ![changed.bundleIdentifier isEqual:CodexBundle]) return;

    _layoutGeneration++;
    _foregroundIsCodex = [NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier isEqual:CodexBundle];
    _foregroundControlsEmpty = NO;
    if (_panelShown) [self minimizeBar];
    [self applyLayout];
    [self updateIcon];
    [self scheduleForegroundProbe];
}

- (void)scheduleForegroundProbe {
    [_layoutTimer invalidate];
    _layoutTimer = nil;
    if (!_panelAvailable || _foregroundIsCodex || _panelShown ||
        [NSRunningApplication runningApplicationsWithBundleIdentifier:CodexBundle].count == 0) return;
    // Let the foreground app publish its own controls before inspecting the Touch Bar.
    _layoutTimer = [NSTimer timerWithTimeInterval:.22 target:self selector:@selector(probeForegroundControls:)
                                        userInfo:nil repeats:NO];
    [NSRunLoop.mainRunLoop addTimer:_layoutTimer forMode:NSRunLoopCommonModes];
}

- (void)probeForegroundControls:(NSTimer *)timer {
    _layoutTimer = nil;
    if (_foregroundIsCodex || _panelShown) return;
    NSUInteger generation = _layoutGeneration;
    CTBProbeTouchBar(_touchBarFramework, ^(BOOL empty) {
        if (generation != self->_layoutGeneration || self->_panelShown) return;
        self->_foregroundControlsEmpty = empty;
        [self applyLayout];
        [self updateIcon];
    });
}

- (void)woke:(NSNotification *)notification {
    [self refreshQuota:nil];
    [self frontmostAppChanged:notification];
}

- (void)quit:(id)sender { [NSApp terminate:nil]; }
- (void)applicationWillTerminate:(NSNotification *)notification {
    [_bridge stop];
    [_quotaTimer invalidate];
    [_layoutTimer invalidate];
    [_thinkingTimer invalidate];
    [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:self];
    [self minimizeBar];
    if (_trayItem && _setStripPresence) _setStripPresence(TrayIdentifier, NO);
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        signal(SIGPIPE, SIG_IGN);
        NSApplication *app = NSApplication.sharedApplication;
        CTBApp *delegate = [CTBApp new];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [app run];
    }
    return 0;
}
