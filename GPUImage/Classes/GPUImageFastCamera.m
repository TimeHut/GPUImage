//
//  GPUImageFastCamera.m
//  Bebememo
//
//  Created by TracyYih on 2020/10/15.
//

#import "GPUImageFastCamera.h"

inline void stillImageDataReleaseCallback(void *releaseRefCon, const void *baseAddress)
{
    free((void *)baseAddress);
}

inline void GPUImageCreateResizedSampleBuffer(CVPixelBufferRef cameraFrame, CGSize finalSize, CMSampleBufferRef *sampleBuffer)
{
    // CVPixelBufferCreateWithPlanarBytes for YUV input
    
    CGSize originalSize = CGSizeMake(CVPixelBufferGetWidth(cameraFrame), CVPixelBufferGetHeight(cameraFrame));

    CVPixelBufferLockBaseAddress(cameraFrame, 0);
    GLubyte *sourceImageBytes =  CVPixelBufferGetBaseAddress(cameraFrame);
    CGDataProviderRef dataProvider = CGDataProviderCreateWithData(NULL, sourceImageBytes, CVPixelBufferGetBytesPerRow(cameraFrame) * originalSize.height, NULL);
    CGColorSpaceRef genericRGBColorspace = CGColorSpaceCreateDeviceRGB();
    CGImageRef cgImageFromBytes = CGImageCreate((int)originalSize.width, (int)originalSize.height, 8, 32, CVPixelBufferGetBytesPerRow(cameraFrame), genericRGBColorspace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst, dataProvider, NULL, NO, kCGRenderingIntentDefault);
    
    GLubyte *imageData = (GLubyte *) calloc(1, (int)finalSize.width * (int)finalSize.height * 4);
    
    CGContextRef imageContext = CGBitmapContextCreate(imageData, (int)finalSize.width, (int)finalSize.height, 8, (int)finalSize.width * 4, genericRGBColorspace,  kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGContextDrawImage(imageContext, CGRectMake(0.0, 0.0, finalSize.width, finalSize.height), cgImageFromBytes);
    CGImageRelease(cgImageFromBytes);
    CGContextRelease(imageContext);
    CGColorSpaceRelease(genericRGBColorspace);
    CGDataProviderRelease(dataProvider);
    
    CVPixelBufferRef pixel_buffer = NULL;
    CVPixelBufferCreateWithBytes(kCFAllocatorDefault, finalSize.width, finalSize.height, kCVPixelFormatType_32BGRA, imageData, finalSize.width * 4, stillImageDataReleaseCallback, NULL, NULL, &pixel_buffer);
    CMVideoFormatDescriptionRef videoInfo = NULL;
    CMVideoFormatDescriptionCreateForImageBuffer(NULL, pixel_buffer, &videoInfo);
    
    CMTime frameTime = CMTimeMake(1, 30);
    CMSampleTimingInfo timing = {frameTime, frameTime, kCMTimeInvalid};
    
    CMSampleBufferCreateForImageBuffer(kCFAllocatorDefault, pixel_buffer, YES, NULL, NULL, videoInfo, &timing, sampleBuffer);
    CVPixelBufferUnlockBaseAddress(cameraFrame, 0);
    CFRelease(videoInfo);
    CVPixelBufferRelease(pixel_buffer);
}

@interface GPUImageFastCamera ()<AVCapturePhotoCaptureDelegate>

@property (nonatomic, strong) AVCapturePhotoOutput *photoOutput;
@property (nonatomic, assign) OSType pixelFormatType;
@property (nonatomic, assign) BOOL isCapturingPhoto;

@property (nonatomic, strong) GPUImageOutput<GPUImageInput> *finalFilterInChain;
@property (nonatomic, copy) void(^captureCompletionHandler)(NSError *error);

- (void)capturePhotoProcessedUpToFilter:(GPUImageOutput<GPUImageInput> *)finalFilterInChain withImageOnGPUHandler:(void(^)(NSError *error))block;

@end

@implementation GPUImageFastCamera

- (id)initWithSessionPreset:(NSString *)sessionPreset cameraPosition:(AVCaptureDevicePosition)cameraPosition {
    self = [super initWithSessionPreset:sessionPreset cameraPosition:cameraPosition];
    if (self) {
        [self.captureSession beginConfiguration];

        self.photoOutput = [[AVCapturePhotoOutput alloc] init];
        if (@available(iOS 13.0, *)) {
            self.photoOutput.maxPhotoQualityPrioritization = AVCapturePhotoQualityPrioritizationSpeed;
        }
        
        [self.captureSession addOutput:self.photoOutput];
        if (captureAsYUV && [GPUImageContext deviceSupportsRedTextures]) {
            BOOL supportsFullYUVRange = NO;
            NSArray *supportedPixelFormats = self.photoOutput.availablePhotoPixelFormatTypes;
            for (NSNumber *format in supportedPixelFormats) {
                if ([format intValue] == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
                    supportsFullYUVRange = YES;
                    break;
                }
            }
            self.pixelFormatType = supportsFullYUVRange ? kCVPixelFormatType_420YpCbCr8BiPlanarFullRange : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
        } else {
            captureAsYUV = NO;
            self.pixelFormatType = kCVPixelFormatType_32BGRA;
            [videoOutput setVideoSettings:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_32BGRA] forKey:(id)kCVPixelBufferPixelFormatTypeKey]];
        }
        
        [self.captureSession commitConfiguration];
        self.jpegCompressionQuality = 0.8;
    }
    return self;
}

- (id)init;
{
    if (!(self = [self initWithSessionPreset:AVCaptureSessionPresetPhoto cameraPosition:AVCaptureDevicePositionBack]))
    {
        return nil;
    }
    return self;
}

- (void)removeInputsAndOutputs;
{
    [self.captureSession removeOutput:self.photoOutput];
    [super removeInputsAndOutputs];
}

#pragma mark -
#pragma mark Photography controls

- (void)capturePhotoAsImageProcessedUpToFilter:(GPUImageOutput<GPUImageInput> *)finalFilterInChain withCompletionHandler:(void (^)(UIImage *processedImage, NSError *error))block {
    [self capturePhotoProcessedUpToFilter:finalFilterInChain withImageOnGPUHandler:^(NSError *error) {
        UIImage *filteredPhoto = nil;

        if(!error){
            filteredPhoto = [finalFilterInChain imageFromCurrentFramebuffer];
        }
        dispatch_semaphore_signal(frameRenderingSemaphore);

        block(filteredPhoto, error);
    }];
}

- (void)capturePhotoAsImageProcessedUpToFilter:(GPUImageOutput<GPUImageInput> *)finalFilterInChain withOrientation:(UIImageOrientation)orientation withCompletionHandler:(void (^)(UIImage *processedImage, NSError *error))block {
    [self capturePhotoProcessedUpToFilter:finalFilterInChain withImageOnGPUHandler:^(NSError *error) {
        UIImage *filteredPhoto = nil;
        
        if(!error) {
            filteredPhoto = [finalFilterInChain imageFromCurrentFramebufferWithOrientation:orientation];
        }
        dispatch_semaphore_signal(frameRenderingSemaphore);
        
        block(filteredPhoto, error);
    }];
}

- (void)capturePhotoAsJPEGProcessedUpToFilter:(GPUImageOutput<GPUImageInput> *)finalFilterInChain withCompletionHandler:(void (^)(NSData *processedJPEG, NSError *error))block {
    [self capturePhotoProcessedUpToFilter:finalFilterInChain withImageOnGPUHandler:^(NSError *error) {
        NSData *dataForJPEGFile = nil;

        if(!error){
            @autoreleasepool {
                UIImage *filteredPhoto = [finalFilterInChain imageFromCurrentFramebuffer];
                dispatch_semaphore_signal(frameRenderingSemaphore);
                dataForJPEGFile = UIImageJPEGRepresentation(filteredPhoto,self.jpegCompressionQuality);
            }
        }else{
            dispatch_semaphore_signal(frameRenderingSemaphore);
        }

        block(dataForJPEGFile, error);
    }];
}

- (void)capturePhotoAsJPEGProcessedUpToFilter:(GPUImageOutput<GPUImageInput> *)finalFilterInChain withOrientation:(UIImageOrientation)orientation withCompletionHandler:(void (^)(NSData *processedImage, NSError *error))block {
    [self capturePhotoProcessedUpToFilter:finalFilterInChain withImageOnGPUHandler:^(NSError *error) {
        NSData *dataForJPEGFile = nil;
        
        if(!error) {
            @autoreleasepool {
                UIImage *filteredPhoto = [finalFilterInChain imageFromCurrentFramebufferWithOrientation:orientation];
                dispatch_semaphore_signal(frameRenderingSemaphore);
                
                dataForJPEGFile = UIImageJPEGRepresentation(filteredPhoto, self.jpegCompressionQuality);
            }
        } else {
            dispatch_semaphore_signal(frameRenderingSemaphore);
        }
        
        block(dataForJPEGFile, error);
    }];
}

- (void)capturePhotoAsPNGProcessedUpToFilter:(GPUImageOutput<GPUImageInput> *)finalFilterInChain withCompletionHandler:(void (^)(NSData *processedPNG, NSError *error))block {
    [self capturePhotoProcessedUpToFilter:finalFilterInChain withImageOnGPUHandler:^(NSError *error) {
        NSData *dataForPNGFile = nil;

        if(!error){
            @autoreleasepool {
                UIImage *filteredPhoto = [finalFilterInChain imageFromCurrentFramebuffer];
                dispatch_semaphore_signal(frameRenderingSemaphore);
                dataForPNGFile = UIImagePNGRepresentation(filteredPhoto);
            }
        }else{
            dispatch_semaphore_signal(frameRenderingSemaphore);
        }
        
        block(dataForPNGFile, error);
    }];
    
    return;
}

- (void)capturePhotoAsPNGProcessedUpToFilter:(GPUImageOutput<GPUImageInput> *)finalFilterInChain withOrientation:(UIImageOrientation)orientation withCompletionHandler:(void (^)(NSData *processedPNG, NSError *error))block {
    [self capturePhotoProcessedUpToFilter:finalFilterInChain withImageOnGPUHandler:^(NSError *error) {
        NSData *dataForPNGFile = nil;
        
        if(!error){
            @autoreleasepool {
                UIImage *filteredPhoto = [finalFilterInChain imageFromCurrentFramebufferWithOrientation:orientation];
                dispatch_semaphore_signal(frameRenderingSemaphore);
                dataForPNGFile = UIImagePNGRepresentation(filteredPhoto);
            }
        }else{
            dispatch_semaphore_signal(frameRenderingSemaphore);
        }
        
        block(dataForPNGFile, error);
    }];
    
    return;
}

#pragma mark - Private Methods

- (void)capturePhotoProcessedUpToFilter:(GPUImageOutput<GPUImageInput> *)finalFilterInChain withImageOnGPUHandler:(void(^)(NSError *error))block {
    dispatch_semaphore_wait(frameRenderingSemaphore, DISPATCH_TIME_FOREVER);
    
    if (self.isCapturingPhoto) {
        block([NSError errorWithDomain:AVFoundationErrorDomain code:AVErrorMaximumStillImageCaptureRequestsExceeded userInfo:nil]);
        return;
    }
    
    self.finalFilterInChain = finalFilterInChain;
    self.captureCompletionHandler = block;
    
    AVCapturePhotoSettings *settings = [AVCapturePhotoSettings photoSettingsWithFormat:@{ (NSString*)kCVPixelBufferPixelFormatTypeKey : @(self.pixelFormatType) }];
    if (@available(iOS 13.0, *)) {
        settings.photoQualityPrioritization = AVCapturePhotoQualityPrioritizationSpeed;
    }
    [self.photoOutput capturePhotoWithSettings:settings delegate:self];
}

#pragma mark - AVCapturePhotoCaptureDelegate

- (void)captureOutput:(AVCapturePhotoOutput *)output didFinishProcessingPhotoSampleBuffer:(nullable CMSampleBufferRef)photoSampleBuffer previewPhotoSampleBuffer:(nullable CMSampleBufferRef)previewPhotoSampleBuffer resolvedSettings:(AVCaptureResolvedPhotoSettings *)resolvedSettings bracketSettings:(nullable AVCaptureBracketedStillImageSettings *)bracketSettings error:(nullable NSError *)error {
    
    if (photoSampleBuffer == NULL) {
        self.captureCompletionHandler(error);
        return;
    }
    
    CVImageBufferRef cameraFrame = CMSampleBufferGetImageBuffer(photoSampleBuffer);
    CGSize photoSize = CGSizeMake(CVPixelBufferGetWidth(cameraFrame), CVPixelBufferGetHeight(cameraFrame));
    CGSize photoSizeInGPU = [GPUImageContext sizeThatFitsWithinATextureForSize:photoSize];
    if (!CGSizeEqualToSize(photoSize, photoSizeInGPU)) {
        CMSampleBufferRef sampleBuffer = NULL;
        if (CVPixelBufferGetPlaneCount(cameraFrame) > 0) {
            NSAssert(NO, @"Error: no downsampling for YUV input in the framework yet");
        } else {
            GPUImageCreateResizedSampleBuffer(cameraFrame, photoSizeInGPU, &sampleBuffer);
        }
        
        dispatch_semaphore_signal(frameRenderingSemaphore);
        [self.finalFilterInChain useNextFrameForImageCapture];
        [self captureOutput:self.photoOutput didOutputSampleBuffer:sampleBuffer fromConnection:[[self.photoOutput connections] objectAtIndex:0]];
        dispatch_semaphore_wait(frameRenderingSemaphore, DISPATCH_TIME_FOREVER);
        if (sampleBuffer != NULL)
            CFRelease(sampleBuffer);
    } else {
        AVCaptureDevicePosition currentCameraPosition = [[videoInput device] position];
        if ( (currentCameraPosition != AVCaptureDevicePositionFront) || (![GPUImageContext supportsFastTextureUpload]))
        {
            dispatch_semaphore_signal(frameRenderingSemaphore);
            [self.finalFilterInChain useNextFrameForImageCapture];
            [self captureOutput:self.photoOutput didOutputSampleBuffer:photoSampleBuffer fromConnection:[[self.photoOutput connections] objectAtIndex:0]];
            dispatch_semaphore_wait(frameRenderingSemaphore, DISPATCH_TIME_FOREVER);
        }
    }
    self.captureCompletionHandler(nil);
}

@end
