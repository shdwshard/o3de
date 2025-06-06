/*
 * Copyright (c) Contributors to the Open 3D Engine Project.
 * For complete copyright and license terms please see the LICENSE at the root of this distribution.
 *
 * SPDX-License-Identifier: Apache-2.0 OR MIT
 *
 */

#include <CoreFoundation/CoreFoundation.h>
#include <AppKit/AppKit.h>
#include <AvailabilityMacros.h>

#include <QImage>
#include <QPixmap>
#include <QtMac>

#include <AzQtComponents/Components/Widgets/Eyedropper.h>
#include <AzQtComponents/Utilities/ScreenGrabber.h>

// Check if we're on macOS 12.3 or later
#if defined(MAC_OS_X_VERSION_12_3) && __MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_12_3
#include <ScreenCaptureKit/ScreenCaptureKit.h>
#include <CoreMedia/CoreMedia.h>
#include <CoreImage/CoreImage.h>
#endif

namespace AzQtComponents
{

    class ScreenGrabber::Internal
    {};

    ScreenGrabber::ScreenGrabber(const QSize size, Eyedropper* parent /* = nullptr */)
        : QObject(parent)
        , m_size(size)
        , m_owner(parent)
    {
    }

    ScreenGrabber::~ScreenGrabber()
    {
    }

    QImage ScreenGrabber::grab(const QPoint& point) const
    {
        WId magnifier = m_owner->effectiveWinId();

        NSView* view = reinterpret_cast<NSView*>(magnifier);
        CGWindowID windowId = (CGWindowID)[[view window] windowNumber];

        // The part of the screen we want to scale up
        QRect region({}, m_size);
        region.moveCenter(point);
        CGRect bounds = CGRectMake(region.x(), region.y(), region.width(), region.height());

        QImage result;

#if defined(MAC_OS_X_VERSION_12_3) && __MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_12_3
        // Check at runtime if we're on macOS 12.3 or later
        if (@available(macOS 12.3, *)) {
            // Use ScreenCaptureKit for macOS 12.3+
            dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
            __block CGImageRef capturedImage = nil;
            __block BOOL captureError = NO;

            // Create a configuration for screen capture
            SCContentFilter* filter = nil;

            // Get the display containing the point
            CGDirectDisplayID displayID = CGMainDisplayID();

            // Create a content filter that excludes the current window
            SCDisplay* display = [[SCDisplay alloc] initWithDisplayID:displayID];
            NSArray<SCDisplay *>* displays = @[display];

            SCContentFilter* contentFilter = [[SCContentFilter alloc] initWithDisplay:display excludingWindows:@[
                [NSNumber numberWithUnsignedInt:windowId]
            ]];

            // Create a stream configuration
            SCStreamConfiguration* config = [[SCStreamConfiguration alloc] init];
            config.width = bounds.size.width;
            config.height = bounds.size.height;
            config.minimumFrameInterval = CMTimeMake(1, 60); // 60 fps
            config.pixelFormat = kCVPixelFormatType_32BGRA;

            // Create the capture stream
            NSError* error = nil;
            SCStream* stream = [[SCStream alloc] initWithFilter:contentFilter configuration:config delegate:nil error:&error];
            if (error) {
                NSLog(@"Error creating screen capture stream: %@", error);
                captureError = YES;
            } else {
                // Add a stream output handler
                [stream addStreamOutput:[[SCStreamOutput alloc] initWithQueue:dispatch_get_main_queue() 
                                                            pixelBufferHandler:^(SCStream *stream, CMSampleBufferRef sampleBuffer) {
                    // Get the pixel buffer from the sample buffer
                    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
                    if (pixelBuffer) {
                        // Create a CGImage from the pixel buffer
                        CIImage* ciImage = [CIImage imageWithCVPixelBuffer:pixelBuffer];
                        CIContext* context = [CIContext contextWithOptions:nil];
                        capturedImage = [context createCGImage:ciImage fromRect:CGRectMake(
                            bounds.origin.x - (int)bounds.origin.x, 
                            bounds.origin.y - (int)bounds.origin.y, 
                            bounds.size.width, 
                            bounds.size.height
                        )];

                        // Signal that we've captured the image
                        dispatch_semaphore_signal(semaphore);

                        // Stop the stream after capturing one frame
                        [stream stopCaptureWithCompletionHandler:^(NSError * _Nullable error) {
                            if (error) {
                                NSLog(@"Error stopping capture: %@", error);
                            }
                        }];
                    }
                }]];

                // Start the capture
                [stream startCaptureWithCompletionHandler:^(NSError * _Nullable error) {
                    if (error) {
                        NSLog(@"Error starting capture: %@", error);
                        captureError = YES;
                        dispatch_semaphore_signal(semaphore);
                    }
                }];

                // Wait for the capture to complete (with a timeout)
                if (dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC)) == 0) {
                    if (capturedImage) {
                        result = QtMac::fromCGImageRef(capturedImage).toImage();
                        CGImageRelease(capturedImage);
                        return result;
                    } else {
                        captureError = YES;
                    }
                } else {
                    captureError = YES;
                    NSLog(@"Timeout waiting for screen capture");
                }
            }

            // If we reach here, something went wrong with ScreenCaptureKit
            // On macOS 15+, we have no fallback, so return an empty image
#if defined(MAC_OS_VERSION_15_0) && __MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_VERSION_15_0
            if (@available(macOS 15.0, *)) {
                NSLog(@"Error: Failed to capture screen on macOS 15+");
                return QImage();
            }
#endif
            // On older macOS versions, fall back to legacy API
            goto useLegacyAPI;
        }
useLegacyAPI:
#endif
#if defined(MAC_OS_VERSION_15_0) && __MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_VERSION_15_0
        // On macOS 15+, CGWindowListCreateImageFromArray is completely deprecated
        // We should never reach here on macOS 15+ as the ScreenCaptureKit path should have succeeded
        NSLog(@"Error: Failed to capture screen on macOS 15+");
        return QImage();
#else
        // Use deprecated CGWindowListCreateImageFromArray for older macOS versions
        CFArrayRef allWindows = CGWindowListCreate(kCGWindowListOptionAll | kCGWindowListOptionOnScreenOnly, kCGNullWindowID);
        CFMutableArrayRef windows = CFArrayCreateMutableCopy(nullptr, 0, allWindows);
        for (int i = 0; i < CFArrayGetCount(windows); i++)
        {
            CGWindowID window = static_cast<CGWindowID>(reinterpret_cast<uint64_t>(CFArrayGetValueAtIndex(windows, i)));
            if (window == windowId)
            {
                CFArrayRemoveValueAtIndex(windows, i);
                break;
            }
        }
        CFRelease(allWindows);

        #if defined(MAC_OS_VERSION_15_0) && __MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_VERSION_15_0
        // This code should never be reached on macOS 15+ due to the check above,
        // but we add this extra check to ensure the deprecated function is never compiled on macOS 15+
        if (@available(macOS 15.0, *)) {
            return QImage();
        } else
        #endif
        {
            CGImageRef cgImage = CGWindowListCreateImageFromArray(bounds, windows, kCGWindowImageNominalResolution);
            CFRelease(windows);

            result = QtMac::fromCGImageRef(cgImage).toImage();
            CGImageRelease(cgImage);
        }
#endif

        return result;
    }

} // namespace AzQtComponents

#include "Utilities/moc_ScreenGrabber.cpp"
