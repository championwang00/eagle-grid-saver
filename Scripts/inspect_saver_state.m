#import <Cocoa/Cocoa.h>
#import <objc/message.h>
#import <ScreenSaver/ScreenSaver.h>

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        if (argc < 2) {
            fprintf(stderr, "usage: inspect_saver_state <saver-path>\n");
            return 2;
        }

        NSString *saverPath = [NSString stringWithUTF8String:argv[1]];
        NSBundle *bundle = [NSBundle bundleWithPath:saverPath];
        if (bundle == nil || ![bundle load]) {
            fprintf(stderr, "failed to load saver bundle: %s\n", saverPath.UTF8String);
            return 1;
        }

        Class principalClass = bundle.principalClass;
        ScreenSaverView *view = [[principalClass alloc] initWithFrame:NSMakeRect(0, 0, 1440, 900) isPreview:YES];
        if ([view respondsToSelector:NSSelectorFromString(@"configuredLibraryURL")]) {
            NSURL *configuredURL = [view performSelector:NSSelectorFromString(@"configuredLibraryURL")];
            printf("configuredLibraryURL=%s\n", configuredURL.path.UTF8String ?: "(nil)");
        }
        if ([view respondsToSelector:NSSelectorFromString(@"configuredLibraryPathCandidates")]) {
            NSArray *paths = [view performSelector:NSSelectorFromString(@"configuredLibraryPathCandidates")];
            for (NSString *path in paths) {
                printf("candidateLibraryPath=%s\n", path.UTF8String);
            }
        }
        if ([view respondsToSelector:NSSelectorFromString(@"configuredDisplayCacheFolderURL")]) {
            NSURL *cacheURL = [view performSelector:NSSelectorFromString(@"configuredDisplayCacheFolderURL")];
            printf("configuredDisplayCacheFolderURL=%s\n", cacheURL.path.UTF8String ?: "(nil)");
        }
        if ([view respondsToSelector:NSSelectorFromString(@"displayCacheManifestURL")]) {
            NSURL *manifestURL = [view performSelector:NSSelectorFromString(@"displayCacheManifestURL")];
            printf("displayCacheManifestURL=%s exists=%s\n",
                   manifestURL.path.UTF8String ?: "(nil)",
                   (manifestURL != nil && [NSFileManager.defaultManager fileExistsAtPath:manifestURL.path]) ? "yes" : "no");
        }
        if ([view respondsToSelector:NSSelectorFromString(@"scrollSpeedMultiplier")]) {
            double (*sendDouble)(id, SEL) = (double (*)(id, SEL))objc_msgSend;
            double speed = sendDouble(view, NSSelectorFromString(@"scrollSpeedMultiplier"));
            printf("scrollSpeedMultiplier=%.2f\n", speed);
        }
        if ([view respondsToSelector:NSSelectorFromString(@"columnCount")]) {
            NSInteger (*sendInteger)(id, SEL) = (NSInteger (*)(id, SEL))objc_msgSend;
            NSInteger columnCount = sendInteger(view, NSSelectorFromString(@"columnCount"));
            printf("columnCount=%ld\n", (long)columnCount);
        }
        [view startAnimation];
        [view drawRect:view.bounds];
        NSInteger frames = 6;
        NSString *framesValue = NSProcessInfo.processInfo.environment[@"EAGLE_INSPECT_FRAMES"];
        if (framesValue.length > 0) {
            frames = MAX(0, framesValue.integerValue);
        }
        for (NSInteger i = 0; i < frames; i++) {
            [view animateOneFrame];
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
        }

        NSArray *artworks = [view valueForKey:@"artworks"];
        NSArray *cells = [view valueForKey:@"cells"];
        NSMutableSet *visibleColumns = NSMutableSet.set;
        for (id cell in cells) {
            [visibleColumns addObject:[cell valueForKey:@"column"]];
        }
        printf("visibleCellColumns=%lu\n", (unsigned long)visibleColumns.count);
        for (NSNumber *column in visibleColumns) {
            CGFloat minY = CGFLOAT_MAX;
            CGFloat maxY = -CGFLOAT_MAX;
            NSUInteger columnCellCount = 0;
            NSUInteger visibleCellCount = 0;
            NSUInteger hiddenVisibleCellCount = 0;
            NSMutableArray *frames = NSMutableArray.array;
            for (id cell in cells) {
                if (![[cell valueForKey:@"column"] isEqual:column]) {
                    continue;
                }
                NSRect frame = [[cell valueForKey:@"frame"] rectValue];
                [frames addObject:[NSValue valueWithRect:frame]];
                minY = MIN(minY, NSMinY(frame));
                maxY = MAX(maxY, NSMaxY(frame));
                columnCellCount += 1;
                if (NSMaxY(frame) >= 0.0 && NSMinY(frame) <= view.bounds.size.height) {
                    visibleCellCount += 1;
                    CALayer *contentLayer = [cell valueForKey:@"contentLayer"];
                    if (contentLayer == nil ||
                        contentLayer.hidden ||
                        (contentLayer.contents == nil && contentLayer.sublayers.count == 0)) {
                        hiddenVisibleCellCount += 1;
                    }
                }
            }
            printf("column=%ld cells=%lu visible=%lu hiddenVisible=%lu minY=%.2f maxY=%.2f\n",
                   column.integerValue,
                   (unsigned long)columnCellCount,
                   (unsigned long)visibleCellCount,
                   (unsigned long)hiddenVisibleCellCount,
                   minY,
                   maxY);
            [frames sortUsingComparator:^NSComparisonResult(NSValue *a, NSValue *b) {
                CGFloat aMinY = NSMinY(a.rectValue);
                CGFloat bMinY = NSMinY(b.rectValue);
                if (aMinY < bMinY) {
                    return NSOrderedAscending;
                }
                if (aMinY > bMinY) {
                    return NSOrderedDescending;
                }
                return NSOrderedSame;
            }];
            CGFloat coveredUntil = 0.0;
            CGFloat maxGap = 0.0;
            BOOL sawVisibleFrame = NO;
            for (NSValue *frameValue in frames) {
                NSRect frame = frameValue.rectValue;
                if (NSMaxY(frame) < 0.0 || NSMinY(frame) > view.bounds.size.height) {
                    continue;
                }
                sawVisibleFrame = YES;
                CGFloat visibleMinY = MAX(0.0, NSMinY(frame));
                CGFloat visibleMaxY = MIN(view.bounds.size.height, NSMaxY(frame));
                if (visibleMinY > coveredUntil) {
                    maxGap = MAX(maxGap, visibleMinY - coveredUntil);
                }
                coveredUntil = MAX(coveredUntil, visibleMaxY);
            }
            if (!sawVisibleFrame || coveredUntil < view.bounds.size.height) {
                maxGap = MAX(maxGap, view.bounds.size.height - coveredUntil);
            }
            printf("columnSeams=%s column=%ld maxGap=%.2f coveredUntil=%.2f\n",
                   maxGap <= 0.5 ? "ok" : "gap",
                   column.integerValue,
                   maxGap,
                   coveredUntil);
        }
        NSUInteger inspectedArtworkCount = 0;
        NSUInteger videoCount = 0;
        NSUInteger playableVideoCount = 0;
        for (id artwork in artworks) {
            if (inspectedArtworkCount < 6) {
                NSString *title = [artwork valueForKey:@"title"];
                NSURL *url = [artwork valueForKey:@"url"];
                printf("artwork=%s path=%s\n",
                       title.UTF8String ?: "(untitled)",
                       url.path.UTF8String ?: "(nil)");
                inspectedArtworkCount += 1;
            }
            BOOL isVideo = [[artwork valueForKey:@"isVideo"] boolValue];
            if (!isVideo) {
                continue;
            }
            videoCount += 1;
            NSURL *videoURL = [artwork valueForKey:@"videoURL"];
            printf("videoURL=%s exists=%s\n",
                   videoURL.path.UTF8String ?: "(nil)",
                   (videoURL != nil && [NSFileManager.defaultManager fileExistsAtPath:videoURL.path]) ? "yes" : "no");
            if (videoURL != nil && [NSFileManager.defaultManager fileExistsAtPath:videoURL.path]) {
                playableVideoCount += 1;
            }
        }

        printf("artworks=%lu\n", (unsigned long)artworks.count);
        printf("videos=%lu\n", (unsigned long)videoCount);
        printf("playableVideoURLs=%lu\n", (unsigned long)playableVideoCount);
        if (videoCount > 0 && playableVideoCount == 0) {
            return 3;
        }
    }
    return 0;
}
