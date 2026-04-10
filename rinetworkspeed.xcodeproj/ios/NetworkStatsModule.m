#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>

@interface RCT_EXTERN_MODULE(NetworkStatsModule, RCTEventEmitter)

RCT_EXTERN_METHOD(getSnapshot:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

RCT_EXTERN_METHOD(startTimer:(nullable NSNumber *)interval)

RCT_EXTERN_METHOD(stopTimer)

@end
