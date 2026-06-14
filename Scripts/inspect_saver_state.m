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
        for (NSInteger i = 0; i < 6; i++) {
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
