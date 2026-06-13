#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <ScreenSaver/ScreenSaver.h>

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        if (argc < 3) {
            fprintf(stderr, "usage: render_preview <saver-path> <output-png>\n");
            return 2;
        }

        NSString *saverPath = [NSString stringWithUTF8String:argv[1]];
        NSString *outputPath = [NSString stringWithUTF8String:argv[2]];
        NSBundle *bundle = [NSBundle bundleWithPath:saverPath];
        if (bundle == nil || ![bundle load]) {
            fprintf(stderr, "failed to load saver bundle: %s\n", saverPath.UTF8String);
            return 1;
        }

        Class principalClass = bundle.principalClass;
        if (principalClass == Nil) {
            fprintf(stderr, "missing principal class\n");
            return 1;
        }

        NSRect frame = NSMakeRect(0, 0, 1440, 900);
        ScreenSaverView *view = [[principalClass alloc] initWithFrame:frame isPreview:YES];
        if (view == nil) {
            fprintf(stderr, "failed to create saver view\n");
            return 1;
        }

        [view startAnimation];
        [view drawRect:frame];
        NSInteger frameCount = argc >= 4 ? [[NSString stringWithUTF8String:argv[3]] integerValue] : 24;
        for (NSInteger i = 0; i < frameCount; i++) {
            [view animateOneFrame];
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
        }
        [view setNeedsDisplay:YES];

        NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc]
            initWithBitmapDataPlanes:NULL
            pixelsWide:(NSInteger)frame.size.width
            pixelsHigh:(NSInteger)frame.size.height
            bitsPerSample:8
            samplesPerPixel:4
            hasAlpha:YES
            isPlanar:NO
            colorSpaceName:NSCalibratedRGBColorSpace
            bytesPerRow:0
            bitsPerPixel:0
        ];

        [NSGraphicsContext saveGraphicsState];
        NSGraphicsContext.currentContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:bitmap];
        [view drawRect:frame];
        CGContextRef context = NSGraphicsContext.currentContext.CGContext;
        CGContextSaveGState(context);
        CGContextTranslateCTM(context, 0, frame.size.height);
        CGContextScaleCTM(context, 1, -1);
        [view.layer renderInContext:context];
        CGContextRestoreGState(context);
        [NSGraphicsContext restoreGraphicsState];

        NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        if (![png writeToFile:outputPath atomically:YES]) {
            fprintf(stderr, "failed to write png: %s\n", outputPath.UTF8String);
            return 1;
        }
    }
    return 0;
}
