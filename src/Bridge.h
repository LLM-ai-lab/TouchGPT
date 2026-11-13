#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CTBBridge : NSObject
@property (nonatomic, copy, nullable) void (^changed)(void);
@property (nonatomic, readonly) BOOL connected;
@property (nonatomic, readonly) BOOL running;
@property (nonatomic, readonly) BOOL awaitingDecision;
@property (nonatomic, readonly, nullable) NSDictionary *approval;
@property (nonatomic, readonly, nullable) NSString *completion;
@property (nonatomic, readonly, nullable) NSString *notice;
- (void)follow:(NSString *)thread;
- (void)decide:(BOOL)allow expected:(NSDictionary *)approval;
- (void)clearCompletion;
- (void)stop;
@end

@interface CTBQuota : NSObject
@property (nonatomic, copy, nullable) void (^changed)(void);
@property (nonatomic, readonly, nullable) NSNumber *remaining;
@property (nonatomic, readonly) NSArray<NSString *> *details;
- (void)refresh;
@end

NS_ASSUME_NONNULL_END
