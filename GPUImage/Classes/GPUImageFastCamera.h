//
//  GPUImageFastCamera.h
//  Bebememo
//
//  Created by TracyYih on 2020/10/15.
//

#import "GPUImageVideoCamera.h"

NS_ASSUME_NONNULL_BEGIN

@interface GPUImageFastCamera : GPUImageVideoCamera

@property (nonatomic, assign) CGFloat jpegCompressionQuality;

// Photography controls
- (void)capturePhotoAsImageProcessedUpToFilter:(GPUImageOutput<GPUImageInput> *)finalFilterInChain withCompletionHandler:(void (^)(UIImage *processedImage, NSError *error))block;
- (void)capturePhotoAsImageProcessedUpToFilter:(GPUImageOutput<GPUImageInput> *)finalFilterInChain withOrientation:(UIImageOrientation)orientation withCompletionHandler:(void (^)(UIImage *processedImage, NSError *error))block;
- (void)capturePhotoAsJPEGProcessedUpToFilter:(GPUImageOutput<GPUImageInput> *)finalFilterInChain withCompletionHandler:(void (^)(NSData *processedJPEG, NSError *error))block;
- (void)capturePhotoAsJPEGProcessedUpToFilter:(GPUImageOutput<GPUImageInput> *)finalFilterInChain withOrientation:(UIImageOrientation)orientation withCompletionHandler:(void (^)(NSData *processedJPEG, NSError *error))block;
- (void)capturePhotoAsPNGProcessedUpToFilter:(GPUImageOutput<GPUImageInput> *)finalFilterInChain withCompletionHandler:(void (^)(NSData *processedPNG, NSError *error))block;
- (void)capturePhotoAsPNGProcessedUpToFilter:(GPUImageOutput<GPUImageInput> *)finalFilterInChain withOrientation:(UIImageOrientation)orientation withCompletionHandler:(void (^)(NSData *processedPNG, NSError *error))block;

@end

NS_ASSUME_NONNULL_END
