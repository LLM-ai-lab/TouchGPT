#import "Bridge.h"
#import <AppKit/AppKit.h>
#import <os/log.h>
#import <sys/socket.h>
#import <sys/stat.h>
#import <sys/un.h>
#import <unistd.h>

static NSDictionary *Dict(id value) {
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

static NSArray *List(id value) {
    return [value isKindOfClass:NSArray.class] ? value : nil;
}

static NSString *Str(id value) {
    return [value isKindOfClass:NSString.class] ? value : nil;
}

static NSNumber *Number(id value) {
    return [value isKindOfClass:NSNumber.class] ? value : nil;
}

static NSString *Snippet(NSString *text) {
    if (!text.length) return nil;
    // Bound the work before normalizing arbitrary message or command text.
    NSUInteger limit = MIN(text.length, 360);
    NSRange range = [text rangeOfComposedCharacterSequencesForRange:NSMakeRange(0, limit)];
    NSArray *parts = [[text substringWithRange:range] componentsSeparatedByCharactersInSet:
                      NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return [[parts filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]]
            componentsJoinedByString:@" "];
}

static NSString *FollowerMethod(NSString *method) {
    if ([method isEqual:@"item/commandExecution/requestApproval"]) return @"thread-follower-command-approval-decision";
    if ([method isEqual:@"item/fileChange/requestApproval"]) return @"thread-follower-file-approval-decision";
    if ([method isEqual:@"item/permissions/requestApproval"]) return @"thread-follower-permissions-request-approval-response";
    return nil;
}

static BOOL ReadBytes(int socketFD, void *buffer, size_t length) {
    char *cursor = buffer;
    while (length > 0) {
        ssize_t count = recv(socketFD, cursor, length, 0);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) return NO;
        cursor += count;
        length -= (size_t)count;
    }
    return YES;
}

static int ConnectToDesktop(void) {
    NSString *home = NSProcessInfo.processInfo.environment[@"CODEX_HOME"] ?: [NSHomeDirectory() stringByAppendingPathComponent:@".codex"];
    NSString *path = [home stringByAppendingPathComponent:@"ipc/ipc.sock"];
    struct stat info;
    if (lstat(path.fileSystemRepresentation, &info) != 0 || !S_ISSOCK(info.st_mode) ||
        info.st_uid != getuid() || (info.st_mode & 0077) != 0) return -1;

    struct sockaddr_un address = {.sun_family = AF_UNIX};
    const char *name = path.fileSystemRepresentation;
    if (strlcpy(address.sun_path, name, sizeof(address.sun_path)) >= sizeof(address.sun_path)) return -1;
    address.sun_len = SUN_LEN(&address);
    int socketFD = socket(AF_UNIX, SOCK_STREAM, 0);
    if (socketFD < 0) return -1;
    struct timeval timeout = {.tv_sec = 1};
    int yes = 1;
    setsockopt(socketFD, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));
    setsockopt(socketFD, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
    if (connect(socketFD, (struct sockaddr *)&address, address.sun_len) != 0) {
        close(socketFD);
        return -1;
    }
    uid_t peerUID;
    gid_t peerGID;
    if (getpeereid(socketFD, &peerUID, &peerGID) != 0 || peerUID != getuid()) {
        close(socketFD);
        return -1;
    }
    return socketFD;
}

@interface CTBBridge ()
@property (nonatomic, readwrite, nullable) NSDictionary *approval;
@property (nonatomic, readwrite, nullable) NSString *completion;
@property (nonatomic, readwrite, nullable) NSString *notice;
@end

@implementation CTBBridge {
    NSString *_thread;
    NSString *_client;
    NSString *_owner;
    NSString *_handshake;
    NSString *_decisionID;
    NSDictionary *_submitted;
    NSMutableArray *_requests;
    NSMutableDictionary<NSString *, NSDictionary *> *_turns;
    NSMutableSet<NSString *> *_activeTurns;
    NSString *_completedTurn;
    NSInteger _revision;
    int _socketFD;
    BOOL _stopped;
    BOOL _connecting;
    BOOL _retryQueued;
    NSUInteger _reconnectDelay;
    dispatch_queue_t _reader;
}

- (instancetype)init {
    if ((self = [super init])) {
        _socketFD = -1;
        _reader = dispatch_queue_create("local.codex-touchbar.reader", DISPATCH_QUEUE_SERIAL);
        _reconnectDelay = 2;
    }
    return self;
}

- (BOOL)connected { return _owner != nil; }
- (BOOL)running { return _activeTurns.count > 0; }
- (BOOL)awaitingDecision { return _decisionID != nil; }

- (void)update {
    if (self.changed) self.changed();
}

- (void)clearCompletion {
    _completedTurn = nil;
    self.completion = nil;
    self.notice = nil;
    [self update];
}

- (BOOL)send:(NSDictionary *)message {
    if (_socketFD < 0) return NO;
    NSData *body = [NSJSONSerialization dataWithJSONObject:message options:0 error:nil];
    if (!body.length || body.length > 1024 * 1024) return NO;
    uint32_t size = CFSwapInt32HostToLittle((uint32_t)body.length);
    NSMutableData *frame = [NSMutableData dataWithBytes:&size length:sizeof(size)];
    [frame appendData:body];
    if (send(_socketFD, frame.bytes, frame.length, 0) == (ssize_t)frame.length) return YES;
    shutdown(_socketFD, SHUT_RDWR);
    return NO;
}

- (void)subscribe:(NSString *)thread following:(BOOL)following {
    if (!_client || !thread) return;
    [self send:@{@"type": @"broadcast", @"method": @"thread-stream-following-changed",
                 @"sourceClientId": _client, @"version": @1,
                 @"params": @{@"conversationId": thread, @"hostId": @"local", @"following": @(following)}}];
}

- (void)resetState {
    _owner = nil;
    _revision = -1;
    _requests = nil;
    _turns = [NSMutableDictionary dictionary];
    _activeTurns = [NSMutableSet set];
    _completedTurn = nil;
    _decisionID = nil;
    _submitted = nil;
    self.approval = nil;
}

- (void)follow:(NSString *)thread {
    if ([_thread isEqual:thread]) return;
    [self subscribe:_thread following:NO];
    _thread = [thread copy];
    [self resetState];
    self.completion = nil;
    self.notice = nil;
    [self subscribe:thread following:YES];
    [self connect];
    [self update];
}

- (void)retry {
    if (_stopped || _retryQueued || !_thread) return;
    _retryQueued = YES;
    NSUInteger delay = _reconnectDelay;
    _reconnectDelay = MIN(delay * 2, 30);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delay * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        self->_retryQueued = NO;
        [self connect];
    });
}

- (void)connect {
    if (_stopped || _connecting || _socketFD >= 0 || !_thread) return;
    _connecting = YES;
    dispatch_async(_reader, ^{
        int socketFD = ConnectToDesktop();
        dispatch_sync(dispatch_get_main_queue(), ^{
            self->_connecting = NO;
            if (socketFD < 0) {
                [self retry];
                return;
            }
            if (self->_stopped) { shutdown(socketFD, SHUT_RDWR); return; }
            self->_socketFD = socketFD;
            self->_handshake = NSUUID.UUID.UUIDString;
            NSString *handshake = self->_handshake;
            [self send:@{@"type": @"request", @"method": @"initialize", @"version": @0,
                         @"requestId": handshake, @"sourceClientId": @"initializing-client",
                         @"params": @{@"clientType": @"codex-touchbar"}}];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                if ([self->_handshake isEqual:handshake] && self->_socketFD == socketFD) {
                    shutdown(socketFD, SHUT_RDWR);
                }
            });
        });
        if (socketFD < 0) return;
        uint32_t header;
        while (ReadBytes(socketFD, &header, sizeof(header))) {
            @autoreleasepool {
                uint32_t length = CFSwapInt32LittleToHost(header);
                if (length == 0 || length > 16 * 1024 * 1024) break;
                NSMutableData *frame = [NSMutableData dataWithLength:length];
                if (!ReadBytes(socketFD, frame.mutableBytes, length)) break;
                NSDictionary *message = Dict([NSJSONSerialization JSONObjectWithData:frame options:0 error:nil]);
                if (!message) break;
                dispatch_sync(dispatch_get_main_queue(), ^{
                    if (self->_socketFD == socketFD) [self receive:message];
                });
            }
        }
        dispatch_sync(dispatch_get_main_queue(), ^{
            if (self->_socketFD == socketFD) {
                self->_socketFD = -1;
                self->_client = nil;
                self->_handshake = nil;
                [self resetState];
                [self update];
                [self retry];
            }
        });
        close(socketFD);
    });
}

- (void)stop {
    _stopped = YES;
    [self subscribe:_thread following:NO];
    if (_socketFD >= 0) shutdown(_socketFD, SHUT_RDWR);
}

- (void)acceptTurn:(NSDictionary *)turn key:(NSString *)key {
    NSString *turnID = Str(turn[@"turnId"]);
    NSString *status = Str(turn[@"status"]);
    if (!turnID || !status) return;
    NSString *preview;
    for (NSDictionary *item in [List(turn[@"items"]) reverseObjectEnumerator]) {
        if (![Dict(item)[@"type"] isEqual:@"agentMessage"]) continue;
        if (![item[@"phase"] isEqual:@"final_answer"]) continue;
        preview = Snippet(Str(item[@"text"]));
        if (preview.length) break;
    }
    _turns[key] = @{@"id": turnID, @"status": status, @"preview": preview ?: @""};
}

- (void)applySnapshot:(NSDictionary *)state {
    _requests = [List(state[@"requests"]) mutableCopy] ?: [NSMutableArray array];
    _turns = [NSMutableDictionary dictionary];
    NSDictionary *entities = Dict(Dict(Dict(state[@"turnHistory"])[@"history"])[@"entitiesByKey"]);
    for (NSString *key in entities) {
        [self acceptTurn:Dict(entities[key]) key:key];
    }
    NSArray *turns = List(state[@"turns"]);
    for (NSUInteger index = 0; index < turns.count; ++index) {
        [self acceptTurn:Dict(turns[index]) key:[@(index) stringValue]];
    }
}

- (BOOL)applyPatch:(NSDictionary *)patch {
    NSArray *path = List(patch[@"path"]);
    NSString *op = Str(patch[@"op"]);
    id value = patch[@"value"];
    if ([path.firstObject isEqual:@"requests"]) {
        if (path.count == 1 && ([op isEqual:@"replace"] || [op isEqual:@"add"]) && List(value)) {
            _requests = [value mutableCopy];
            return YES;
        }
        NSNumber *position = path.count == 2 ? Number(path[1]) : nil;
        if (!position) return NO;
        NSUInteger index = position.unsignedIntegerValue;
        if ([op isEqual:@"add"] && index <= _requests.count && Dict(value)) [_requests insertObject:value atIndex:index];
        else if ([op isEqual:@"replace"] && index < _requests.count && Dict(value)) _requests[index] = value;
        else if ([op isEqual:@"remove"] && index < _requests.count) [_requests removeObjectAtIndex:index];
        else return NO;
        return YES;
    }
    NSUInteger keyIndex;
    if ([path.firstObject isEqual:@"turns"]) {
        keyIndex = 1;
    } else if ([path.firstObject isEqual:@"turnHistory"]) {
        if (path.count <= 3 && ![op isEqual:@"remove"]) {
            if ([path.lastObject isEqual:@"islands"] || [path.lastObject isEqual:@"generation"] || [path.lastObject isEqual:@"isComplete"]) return YES;
            return NO;
        }
        if (path.count < 4 || ![path[2] isEqual:@"entitiesByKey"]) return YES;
        keyIndex = 3;
    } else {
        return YES;
    }
    if (path.count <= keyIndex) return NO;
    NSString *key = Str(path[keyIndex]) ?: [Number(path[keyIndex]) stringValue];
    if (!key) return NO;
    if (path.count == keyIndex + 1) {
        if ([op isEqual:@"remove"]) [_turns removeObjectForKey:key];
        else if (Dict(value)) [self acceptTurn:value key:key];
        return YES;
    }
    NSString *field = path[keyIndex + 1];
    NSMutableDictionary *turn = [_turns[key] mutableCopy];
    if ([field isEqual:@"turnId"]) return NO;
    if (!turn) return ![field isEqual:@"status"];
    if ([field isEqual:@"status"] && path.count == keyIndex + 2 && Str(value)) {
        turn[@"status"] = value;
    } else if ([field isEqual:@"items"] && path.count == keyIndex + 3 &&
               [Dict(value)[@"type"] isEqual:@"agentMessage"] && [value[@"phase"] isEqual:@"final_answer"]) {
        turn[@"preview"] = Snippet(Str(value[@"text"])) ?: @"";
    }
    _turns[key] = turn;
    return YES;
}

- (void)publishTurnState {
    NSString *previousCompletedTurn = _completedTurn;
    NSMutableSet *active = [NSMutableSet set];
    for (NSDictionary *turn in _turns.allValues) {
        NSString *identifier = turn[@"id"];
        if ([turn[@"status"] isEqual:@"inProgress"]) [active addObject:identifier];
        if ([turn[@"status"] isEqual:@"completed"] && [_activeTurns containsObject:identifier]) {
            _completedTurn = identifier;
            self.completion = @"回复已完成";
            // Ask the owner for its final text, including text streamed separately from patches.
            [self subscribe:_thread following:YES];
        }
        if ([_completedTurn isEqual:identifier] && [turn[@"preview"] length]) {
            self.completion = [@"已回复 · " stringByAppendingString:turn[@"preview"]];
        }
    }
    if (![active isSubsetOfSet:_activeTurns] &&
        (!_completedTurn || [_completedTurn isEqual:previousCompletedTurn])) {
        // An earlier reply should not cover the progress of a new turn.
        _completedTurn = nil;
        self.completion = nil;
        self.notice = nil;
    }
    _activeTurns = active;
}

- (void)publishApprovals {
    self.approval = nil;
    for (NSDictionary *request in _requests) {
        NSDictionary *params = Dict(Dict(request)[@"params"]);
        NSString *method = Str(Dict(request)[@"method"]);
        id requestID = Dict(request)[@"id"];
        if (!FollowerMethod(method) || ![params[@"threadId"] isEqual:_thread] ||
            !(Str(requestID) || Number(requestID))) continue;
        if (_submitted && [_submitted isEqual:request]) continue;
        self.approval = request;
        break;
    }
    if (_submitted && ![_requests containsObject:_submitted]) _submitted = nil;
}

- (void)receive:(NSDictionary *)message {
    NSString *requestID = Str(message[@"requestId"]);
    if ([message[@"type"] isEqual:@"client-discovery-request"] && requestID) {
        [self send:@{@"type": @"client-discovery-response", @"requestId": requestID,
                     @"response": @{@"canHandle": @NO}}];
        return;
    }
    if ([message[@"type"] isEqual:@"response"]) {
        if (requestID && [_handshake isEqual:requestID]) {
            _handshake = nil;
            _client = Str(Dict(message[@"result"])[@"clientId"]);
            if (_client) {
                _reconnectDelay = 2;
                [self subscribe:_thread following:YES];
            } else {
                shutdown(_socketFD, SHUT_RDWR);
            }
        } else if (requestID && [_decisionID isEqual:requestID]) {
            _decisionID = nil;
            if (![message[@"resultType"] isEqual:@"success"] || ![message[@"handledByClientId"] isEqual:_owner]) {
                _submitted = nil;
                self.notice = @"审批提交失败 · 请在 Codex 中确认";
            }
            [self subscribe:_thread following:YES];
            [self publishApprovals];
            [self update];
            NSDictionary *submitted = _submitted;
            if (submitted) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 6 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                    if (self->_submitted != submitted) return;
                    self.notice = @"审批状态待确认 · 打开 Codex";
                    [self update];
                });
            }
        }
        return;
    }
    if (!_client || ![message[@"type"] isEqual:@"broadcast"]) return;
    NSDictionary *params = Dict(message[@"params"]);
    NSString *sender = Str(message[@"sourceClientId"]);
    NSString *method = Str(message[@"method"]);
    if ([method isEqual:@"client-status-changed"]) {
        if ([params[@"status"] isEqual:@"connected"] && !_owner) [self subscribe:_thread following:YES];
        if ([params[@"status"] isEqual:@"disconnected"] && [_owner isEqual:sender]) {
            [self resetState];
            [self subscribe:_thread following:YES];
            [self update];
        }
        return;
    }
    if (![method isEqual:@"thread-stream-state-changed"] || ![message[@"version"] isEqual:@11] ||
        ![params[@"conversationId"] isEqual:_thread] || ![params[@"hostId"] isEqual:@"local"] || !sender) return;
    NSDictionary *change = Dict(params[@"change"]);
    NSNumber *revision = Number(change[@"revision"]);
    if (!revision || revision.integerValue < 0) return;
    if ([change[@"type"] isEqual:@"snapshot"]) {
        NSDictionary *state = Dict(change[@"conversationState"]);
        if (![state[@"id"] isEqual:_thread] || (_owner && ![_owner isEqual:sender])) return;
        if (!_owner) os_log(OS_LOG_DEFAULT, "Connected to the selected Codex chat");
        _owner = sender;
        [self applySnapshot:state];
    } else if ([change[@"type"] isEqual:@"patches"] && [_owner isEqual:sender]) {
        if (_revision < 0) return;
        if (![Number(change[@"baseRevision"]) isEqual:@(_revision)] ||
            revision.integerValue <= _revision || !List(change[@"patches"])) {
            [self resync];
            return;
        }
        for (NSDictionary *patch in List(change[@"patches"])) {
            if (!Dict(patch) || ![self applyPatch:patch]) {
                [self resync];
                return;
            }
        }
    } else {
        return;
    }
    _revision = revision.integerValue;
    NSString *oldCompletion = self.completion;
    NSDictionary *oldApproval = self.approval;
    BOOL wasRunning = self.running;
    [self publishTurnState];
    [self publishApprovals];
    if ([change[@"type"] isEqual:@"snapshot"] || wasRunning != self.running ||
        ![oldCompletion ?: @"" isEqual:self.completion ?: @""] ||
        ![oldApproval ?: @{} isEqual:self.approval ?: @{}]) [self update];
}

- (void)resync {
    _revision = -1;
    _requests = nil;
    self.approval = nil;
    [self subscribe:_thread following:YES];
    [self update];
}

- (void)decide:(BOOL)allow expected:(NSDictionary *)approval {
    if (!_owner || _revision < 0 || _decisionID || !approval || ![self.approval isEqual:approval]) return;
    NSString *method = FollowerMethod(Str(approval[@"method"]));
    if (!method) return;
    NSDictionary *details = Dict(approval[@"params"]);
    NSArray *allowed = List(details[@"availableDecisions"]);
    NSString *decision = allow ? @"accept" : @"decline";
    if (allowed && ![allowed containsObject:decision]) {
        self.notice = @"请在 Codex 中处理此审批";
        [self update];
        return;
    }
    NSMutableDictionary *params = [@{@"conversationId": _thread, @"requestId": approval[@"id"]} mutableCopy];
    if ([approval[@"method"] isEqual:@"item/permissions/requestApproval"]) {
        NSDictionary *permissions = Dict(details[@"permissions"]);
        if (allow && !permissions.count) {
            self.notice = @"请在 Codex 中查看所请求的权限";
            [self update];
            return;
        }
        params[@"response"] = @{@"permissions": allow ? permissions : @{}, @"scope": @"turn"};
    } else {
        params[@"decision"] = decision;
    }
    NSString *identifier = NSUUID.UUID.UUIDString;
    if (![self send:@{@"type": @"request", @"sourceClientId": _client, @"requestId": identifier,
                      @"version": @1, @"method": method, @"params": params,
                      @"targetClientId": _owner, @"timeoutMs": @5000}]) return;
    _decisionID = identifier;
    _submitted = approval;
    self.notice = nil;
    [self update];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 6 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (![self->_decisionID isEqual:identifier]) return;
        self->_decisionID = nil;
        self.notice = @"审批状态待确认 · 打开 Codex";
        [self resync];
    });
}
@end

@implementation CTBQuota {
    NSArray *_windows;
    NSDate *_updated;
    BOOL _busy;
}

- (NSNumber *)remaining {
    if (!_updated || [_updated timeIntervalSinceNow] < -1800) return nil;
    NSNumber *minimum = nil;
    for (NSDictionary *window in _windows) {
        NSNumber *reset = Number(window[@"resetsAt"]);
        if (reset && reset.doubleValue <= NSDate.date.timeIntervalSince1970) continue;
        NSNumber *used = Number(window[@"usedPercent"]);
        if (!used) continue;
        NSNumber *remaining = @(MAX(0, MIN(100, 100 - used.integerValue)));
        if (!minimum || remaining.intValue < minimum.intValue) minimum = remaining;
    }
    return minimum;
}

- (NSArray<NSString *> *)details {
    if (!self.remaining) return @[@"额度暂不可用"];
    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *window in _windows) {
        NSNumber *used = Number(window[@"usedPercent"]);
        if (!used) continue;
        NSNumber *reset = Number(window[@"resetsAt"]);
        if (reset && reset.doubleValue <= NSDate.date.timeIntervalSince1970) continue;
        NSInteger mins = [Number(window[@"windowDurationMins"]) integerValue];
        NSString *period = @"额度";
        if (mins > 0 && mins % 1440 == 0) period = [NSString stringWithFormat:@"%ld 天", mins / 1440];
        else if (mins > 0 && mins % 60 == 0) period = [NSString stringWithFormat:@"%ld 小时", mins / 60];
        else if (mins > 0) period = [NSString stringWithFormat:@"%ld 分钟", mins];
        NSString *row = [NSString stringWithFormat:@"%@剩余 %ld%%", period, MAX(0, MIN(100, 100 - used.integerValue))];
        if (reset) {
            NSDate *date = [NSDate dateWithTimeIntervalSince1970:reset.doubleValue];
            NSString *time = [NSDateFormatter localizedStringFromDate:date dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle];
            row = [row stringByAppendingFormat:@" · %@ 重置", time];
        }
        [rows addObject:row];
    }
    return rows;
}

- (void)refresh {
    if (_busy) return;
    _busy = YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSArray *windows = [self fetch];
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_busy = NO;
            if (windows) {
                self->_windows = windows;
                self->_updated = NSDate.date;
                os_log(OS_LOG_DEFAULT, "Updated Codex quota windows: %{public}lu", (unsigned long)windows.count);
            }
            if (self.changed) self.changed();
        });
    });
}

- (NSArray *)fetch {
    NSURL *bundle = [NSWorkspace.sharedWorkspace URLForApplicationWithBundleIdentifier:@"com.openai.codex"];
    NSString *relative = @"Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex";
    NSString *path = [bundle.path stringByAppendingPathComponent:relative];
    if (!path || ![NSFileManager.defaultManager isExecutableFileAtPath:path]) return nil;
    NSTask *task = [NSTask new];
    NSPipe *input = [NSPipe pipe];
    NSPipe *output = [NSPipe pipe];
    task.executableURL = [NSURL fileURLWithPath:path];
    task.arguments = @[@"app-server", @"--listen", @"stdio://"];
    task.standardInput = input;
    task.standardOutput = output;
    task.standardError = NSFileHandle.fileHandleWithNullDevice;
    task.currentDirectoryURL = [NSURL fileURLWithPath:@"/"];
    if (![task launchAndReturnError:nil]) return nil;
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                                     dispatch_get_global_queue(QOS_CLASS_UTILITY, 0));
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 12 * NSEC_PER_SEC), DISPATCH_TIME_FOREVER, NSEC_PER_SEC / 2);
    dispatch_source_set_event_handler(timer, ^{ if (task.running) [task terminate]; });
    dispatch_resume(timer);

    // The server reads the existing Codex sign-in. The app only parses quota responses.
    NSString *wire = @"{\"id\":0,\"method\":\"initialize\",\"params\":{\"clientInfo\":{\"name\":\"touch_gpt\",\"title\":\"Touch GPT\",\"version\":\"1.2.0\"}}}\n";
    [input.fileHandleForWriting writeData:[wire dataUsingEncoding:NSUTF8StringEncoding] error:nil];
    NSMutableData *buffer = [NSMutableData data];
    NSArray *windows = nil;
    BOOL done = NO;
    while (!done && buffer.length < 1024 * 1024) {
        @autoreleasepool {
            NSData *chunk = output.fileHandleForReading.availableData;
            if (!chunk.length) break;
            [buffer appendData:chunk];
            const char *bytes = buffer.bytes;
            const char *newline = memchr(bytes, '\n', buffer.length);
            while (newline && !done) {
                NSUInteger size = (NSUInteger)(newline - bytes);
                NSData *line = [buffer subdataWithRange:NSMakeRange(0, size)];
                NSDictionary *message = Dict([NSJSONSerialization JSONObjectWithData:line options:0 error:nil]);
                NSNumber *identifier = Number(message[@"id"]);
                if ([identifier isEqual:@0] && Dict(message[@"result"])) {
                    NSString *query = @"{\"method\":\"initialized\"}\n{\"id\":1,\"method\":\"account/rateLimits/read\"}\n";
                    [input.fileHandleForWriting writeData:[query dataUsingEncoding:NSUTF8StringEncoding] error:nil];
                } else if ([identifier isEqual:@1]) {
                    NSDictionary *result = Dict(message[@"result"]);
                    NSDictionary *limit = Dict(Dict(result[@"rateLimitsByLimitId"])[@"codex"]) ?: Dict(result[@"rateLimits"]);
                    NSMutableArray *available = [NSMutableArray array];
                    for (NSString *name in @[@"primary", @"secondary"]) {
                        NSDictionary *window = Dict(limit[name]);
                        if (Number(window[@"usedPercent"])) [available addObject:window];
                    }
                    if (result) windows = [available copy];
                    done = YES;
                }
                [buffer replaceBytesInRange:NSMakeRange(0, size + 1) withBytes:NULL length:0];
                bytes = buffer.bytes;
                newline = bytes ? memchr(bytes, '\n', buffer.length) : NULL;
            }
        }
    }
    [input.fileHandleForWriting closeFile];
    if (task.running) [task terminate];
    [task waitUntilExit];
    dispatch_source_cancel(timer);
    return windows;
}
@end
