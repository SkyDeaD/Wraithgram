#import <WGCallFrameBridge/WGCallFrameBridge.h>

#import <os/lock.h>

static os_unfair_lock wgCallFrameLock = OS_UNFAIR_LOCK_INIT;
static WGCallFrameProcessorBlock wgCallFrameProcessor = nil;

@implementation WGCallFrameBridge

+ (void)setProcessor:(WGCallFrameProcessorBlock _Nullable)processor {
    WGCallFrameProcessorBlock copied = [processor copy];
    os_unfair_lock_lock(&wgCallFrameLock);
    wgCallFrameProcessor = copied;
    os_unfair_lock_unlock(&wgCallFrameLock);
}

+ (BOOL)hasProcessor {
    os_unfair_lock_lock(&wgCallFrameLock);
    BOOL result = wgCallFrameProcessor != nil;
    os_unfair_lock_unlock(&wgCallFrameLock);
    return result;
}

+ (CVPixelBufferRef _Nullable)copyProcessedPixelBuffer:(CVPixelBufferRef)pixelBuffer isFrontCamera:(BOOL)isFrontCamera rotation:(int)rotation {
    os_unfair_lock_lock(&wgCallFrameLock);
    WGCallFrameProcessorBlock processor = wgCallFrameProcessor;
    os_unfair_lock_unlock(&wgCallFrameLock);
    if (processor == nil) {
        return NULL;
    }
    CVPixelBufferRef result = processor(pixelBuffer, isFrontCamera, rotation);
    if (result == NULL) {
        return NULL;
    }
    if (CVPixelBufferGetWidth(result) != CVPixelBufferGetWidth(pixelBuffer) || CVPixelBufferGetHeight(result) != CVPixelBufferGetHeight(pixelBuffer) || CVPixelBufferGetPixelFormatType(result) != CVPixelBufferGetPixelFormatType(pixelBuffer)) {
        CVPixelBufferRelease(result);
        return NULL;
    }
    return result;
}

@end
