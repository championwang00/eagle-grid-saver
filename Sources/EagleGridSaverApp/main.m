#import <Cocoa/Cocoa.h>
#import <AVFoundation/AVFoundation.h>
#import <ImageIO/ImageIO.h>
#import <ScreenSaver/ScreenSaver.h>
#import "../EagleGridSaverObjC/EagleGridSaverView.h"

static NSString * const EagleDefaultsDomain = @"com.chaopi.EagleGridSaver";
static NSString * const EagleLibraryPathKey = @"EagleGridSaver.libraryPath";
static NSString * const EagleLibraryBookmarkKey = @"EagleGridSaver.libraryBookmark";
static NSString * const EagleDisplayCacheVersion = @"2";

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) NSWindow *previewWindow;
@property(nonatomic, strong) EagleGridSaverView *previewView;
@property(nonatomic, strong) NSTextField *pathLabel;
@property(nonatomic, strong) NSTextField *statusLabel;
@property(nonatomic, strong) NSButton *updateIndexButton;
@property(nonatomic, strong) NSProgressIndicator *progressIndicator;
@property(nonatomic) dispatch_queue_t indexQueue;
@property(nonatomic) BOOL isPreparingIndex;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.indexQueue = dispatch_queue_create("com.chaopi.EagleGridSaver.indexQueue", DISPATCH_QUEUE_SERIAL);
    [self buildWindow];
    [self refreshPathLabel];
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (void)buildWindow {
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 620, 340)
                                             styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable)
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
    self.window.title = @"Eagle Grid Saver";
    self.window.releasedWhenClosed = NO;

    NSView *content = self.window.contentView;

    NSTextField *title = [self labelWithString:@"Eagle Grid Saver" font:[NSFont systemFontOfSize:26 weight:NSFontWeightSemibold] color:NSColor.labelColor];
    title.frame = NSMakeRect(32, 276, 556, 36);
    [content addSubview:title];

    NSTextField *description = [self labelWithString:@"Choose an Eagle .library folder. The app prepares a local display cache so the screen saver starts quickly and avoids black tiles." font:[NSFont systemFontOfSize:14 weight:NSFontWeightRegular] color:NSColor.secondaryLabelColor];
    description.frame = NSMakeRect(32, 224, 556, 44);
    description.maximumNumberOfLines = 2;
    [content addSubview:description];

    self.pathLabel = [self labelWithString:@"" font:[NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular] color:NSColor.labelColor];
    self.pathLabel.frame = NSMakeRect(32, 170, 556, 38);
    self.pathLabel.maximumNumberOfLines = 2;
    self.pathLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [content addSubview:self.pathLabel];

    NSButton *chooseButton = [NSButton buttonWithTitle:@"Choose Eagle Library..." target:self action:@selector(chooseLibrary:)];
    chooseButton.frame = NSMakeRect(32, 118, 172, 34);
    chooseButton.bezelStyle = NSBezelStyleRounded;
    [content addSubview:chooseButton];

    self.updateIndexButton = [NSButton buttonWithTitle:@"Update Index" target:self action:@selector(updateIndex:)];
    self.updateIndexButton.frame = NSMakeRect(216, 118, 116, 34);
    self.updateIndexButton.bezelStyle = NSBezelStyleRounded;
    [content addSubview:self.updateIndexButton];

    NSButton *settingsButton = [NSButton buttonWithTitle:@"Settings" target:self action:@selector(openScreenSaverSettings:)];
    settingsButton.frame = NSMakeRect(344, 118, 92, 34);
    settingsButton.bezelStyle = NSBezelStyleRounded;
    [content addSubview:settingsButton];

    NSButton *startButton = [NSButton buttonWithTitle:@"Start Screen Saver" target:self action:@selector(startScreenSaver:)];
    startButton.frame = NSMakeRect(448, 118, 150, 34);
    startButton.bezelStyle = NSBezelStyleRounded;
    [content addSubview:startButton];

    self.progressIndicator = NSProgressIndicator.new;
    self.progressIndicator.frame = NSMakeRect(32, 82, 480, 16);
    self.progressIndicator.indeterminate = NO;
    self.progressIndicator.minValue = 0;
    self.progressIndicator.maxValue = 1;
    self.progressIndicator.doubleValue = 0;
    self.progressIndicator.hidden = YES;
    [content addSubview:self.progressIndicator];

    self.statusLabel = [self labelWithString:@"" font:[NSFont systemFontOfSize:12 weight:NSFontWeightRegular] color:NSColor.secondaryLabelColor];
    self.statusLabel.frame = NSMakeRect(32, 34, 556, 34);
    self.statusLabel.maximumNumberOfLines = 2;
    [content addSubview:self.statusLabel];
}

- (NSTextField *)labelWithString:(NSString *)string font:(NSFont *)font color:(NSColor *)color {
    NSTextField *label = NSTextField.new;
    label.stringValue = string;
    label.font = font;
    label.textColor = color;
    label.editable = NO;
    label.selectable = YES;
    label.bordered = NO;
    label.bezeled = NO;
    label.drawsBackground = NO;
    return label;
}

- (void)chooseLibrary:(id)sender {
    NSOpenPanel *panel = NSOpenPanel.openPanel;
    panel.title = @"Choose Eagle Library";
    panel.prompt = @"Choose";
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = NO;
    panel.resolvesAliases = YES;
    panel.directoryURL = NSFileManager.defaultManager.homeDirectoryForCurrentUser;

    if ([panel runModal] != NSModalResponseOK || panel.URL == nil) {
        return;
    }

    NSURL *url = panel.URL;
    if (![url.pathExtension.lowercaseString isEqualToString:@"library"]) {
        NSAlert *alert = NSAlert.new;
        alert.messageText = @"Choose an Eagle .library folder";
        alert.informativeText = @"The selected folder does not look like an Eagle library. You can find it in Eagle: Library Settings -> Library Location.";
        [alert runModal];
        return;
    }

    NSError *error = nil;
    NSData *bookmark = [url bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope
                     includingResourceValuesForKeys:nil
                                      relativeToURL:nil
                                              error:&error];
    if (bookmark == nil) {
        NSAlert *alert = NSAlert.new;
        alert.messageText = @"Could not save folder access";
        alert.informativeText = error.localizedDescription ?: @"macOS did not return a folder access token.";
        [alert runModal];
        return;
    }

    [self saveValue:url.path bookmark:bookmark toDefaults:NSUserDefaults.standardUserDefaults];
    ScreenSaverDefaults *screenSaverDefaults = [ScreenSaverDefaults defaultsForModuleWithName:EagleDefaultsDomain];
    [self saveValue:url.path bookmark:bookmark toDefaults:screenSaverDefaults];
    CFPreferencesSetAppValue((CFStringRef)EagleLibraryPathKey, (__bridge CFStringRef)url.path, (CFStringRef)EagleDefaultsDomain);
    CFPreferencesSetAppValue((CFStringRef)EagleLibraryBookmarkKey, (__bridge CFDataRef)bookmark, (CFStringRef)EagleDefaultsDomain);
    CFPreferencesAppSynchronize((CFStringRef)EagleDefaultsDomain);

    self.statusLabel.stringValue = @"Preparing library. Please wait...";
    [self refreshPathLabel];
    [self prepareIndexForLibrary:url];
}

- (void)updateIndex:(id)sender {
    NSURL *libraryURL = [self configuredLibraryURL];
    if (libraryURL == nil) {
        self.statusLabel.stringValue = @"Choose an Eagle library first.";
        return;
    }
    [self prepareIndexForLibrary:libraryURL];
}

- (void)openPreview:(id)sender {
    if (self.previewWindow == nil) {
        NSRect frame = NSMakeRect(0, 0, 960, 600);
        self.previewWindow = [[NSWindow alloc] initWithContentRect:frame
                                                         styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
                                                           backing:NSBackingStoreBuffered
                                                             defer:NO];
        self.previewWindow.title = @"Eagle Grid Saver Preview";
        self.previewWindow.releasedWhenClosed = NO;
        self.previewWindow.contentMinSize = NSMakeSize(640, 400);
        self.previewView = [[EagleGridSaverView alloc] initWithFrame:self.previewWindow.contentView.bounds isPreview:YES];
        self.previewView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [self.previewWindow.contentView addSubview:self.previewView];
        [self.previewWindow center];
    }

    [self.previewView startAnimation];
    [self.previewWindow makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)startScreenSaver:(id)sender {
    NSURL *engineURL = [NSURL fileURLWithPath:@"/System/Library/CoreServices/ScreenSaverEngine.app"];
    NSError *error = nil;
    if (![NSWorkspace.sharedWorkspace openURL:engineURL]) {
        self.statusLabel.stringValue = @"Could not start ScreenSaverEngine.";
        NSLog(@"EagleGridSaverApp: failed to open %@: %@", engineURL.path, error.localizedDescription);
    }
}

- (void)saveValue:(NSString *)path bookmark:(NSData *)bookmark toDefaults:(NSUserDefaults *)defaults {
    [defaults setObject:path forKey:EagleLibraryPathKey];
    [defaults setObject:bookmark forKey:EagleLibraryBookmarkKey];
    [defaults synchronize];
}

- (void)refreshPathLabel {
    NSString *path = [self configuredLibraryURL].path;

    if (path.length > 0) {
        self.pathLabel.stringValue = path;
        if (!self.isPreparingIndex) {
            self.statusLabel.stringValue = @"Ready. You can close this app. Use Update Index after adding or changing Eagle assets.";
        }
    } else {
        self.pathLabel.stringValue = @"No Eagle library selected";
        self.statusLabel.stringValue = @"Choose an Eagle library to prepare the display cache.";
    }
}

- (NSURL *)configuredLibraryURL {
    NSArray<NSUserDefaults *> *defaultsList = @[
        NSUserDefaults.standardUserDefaults,
        [ScreenSaverDefaults defaultsForModuleWithName:EagleDefaultsDomain]
    ];

    for (NSUserDefaults *defaults in defaultsList) {
        NSData *bookmarkData = [defaults dataForKey:EagleLibraryBookmarkKey];
        NSURL *url = [self URLFromBookmarkData:bookmarkData];
        if (url != nil) {
            return url;
        }
    }

    NSData *domainBookmarkData = CFBridgingRelease(CFPreferencesCopyAppValue((CFStringRef)EagleLibraryBookmarkKey, (CFStringRef)EagleDefaultsDomain));
    NSURL *domainURL = [self URLFromBookmarkData:domainBookmarkData];
    if (domainURL != nil) {
        return domainURL;
    }

    for (NSUserDefaults *defaults in defaultsList) {
        NSString *path = [defaults stringForKey:EagleLibraryPathKey];
        if (path.length > 0) {
            return [NSURL fileURLWithPath:path];
        }
    }

    NSString *domainPath = CFBridgingRelease(CFPreferencesCopyAppValue((CFStringRef)EagleLibraryPathKey, (CFStringRef)EagleDefaultsDomain));
    if ([domainPath isKindOfClass:NSString.class] && domainPath.length > 0) {
        return [NSURL fileURLWithPath:domainPath];
    }

    return nil;
}

- (NSURL *)URLFromBookmarkData:(NSData *)bookmarkData {
    if (bookmarkData.length == 0) {
        return nil;
    }

    BOOL stale = NO;
    NSError *error = nil;
    NSURL *url = [NSURL URLByResolvingBookmarkData:bookmarkData
                                           options:NSURLBookmarkResolutionWithSecurityScope
                                     relativeToURL:nil
                               bookmarkDataIsStale:&stale
                                             error:&error];
    if (url != nil) {
        [url startAccessingSecurityScopedResource];
        return url;
    }
    if (error != nil) {
        NSLog(@"EagleGridSaverApp: failed to resolve library bookmark: %@", error.localizedDescription);
    }
    return nil;
}

- (NSURL *)applicationSupportFolderURL {
    NSURL *supportURL = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *folderURL = [supportURL URLByAppendingPathComponent:@"EagleGridSaver" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:folderURL withIntermediateDirectories:YES attributes:nil error:nil];
    return folderURL;
}

- (NSURL *)displayCacheFolderURL {
    NSURL *folderURL = [[self applicationSupportFolderURL] URLByAppendingPathComponent:@"DisplayCache" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:folderURL withIntermediateDirectories:YES attributes:nil error:nil];
    return folderURL;
}

- (void)prepareIndexForLibrary:(NSURL *)libraryURL {
    if (self.isPreparingIndex) {
        return;
    }

    self.isPreparingIndex = YES;
    self.updateIndexButton.enabled = NO;
    self.progressIndicator.hidden = NO;
    self.progressIndicator.doubleValue = 0;
    self.statusLabel.stringValue = @"Building index. Please wait...";

    __weak typeof(self) weakSelf = self;
    dispatch_async(self.indexQueue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        BOOL prepared = [strongSelf buildDisplayCacheForLibrary:libraryURL];

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) innerSelf = weakSelf;
            if (innerSelf == nil) {
                return;
            }
            innerSelf.isPreparingIndex = NO;
            innerSelf.updateIndexButton.enabled = YES;
            if (prepared) {
                innerSelf.progressIndicator.doubleValue = 1;
            }
            innerSelf.progressIndicator.hidden = YES;
        });
    });
}

- (BOOL)buildDisplayCacheForLibrary:(NSURL *)libraryURL {
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSURL *imagesURL = [libraryURL URLByAppendingPathComponent:@"images" isDirectory:YES];
    NSURL *cacheURL = [self displayCacheFolderURL];
    NSMutableArray<NSURL *> *mediaFiles = NSMutableArray.array;
    NSSet<NSString *> *imageExtensions = [NSSet setWithArray:@[@"jpg", @"jpeg", @"png", @"webp", @"heic", @"tif", @"tiff", @"gif"]];
    NSSet<NSString *> *videoExtensions = [NSSet setWithArray:@[@"mov", @"mp4", @"m4v"]];

    BOOL isDirectory = NO;
    if (![fileManager fileExistsAtPath:imagesURL.path isDirectory:&isDirectory] || !isDirectory) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.statusLabel.stringValue = @"Could not read the Eagle library images folder. Choose the library again and grant access if macOS asks.";
            self.progressIndicator.doubleValue = 0;
            self.progressIndicator.hidden = YES;
        });
        return NO;
    }

    NSDirectoryEnumerator<NSURL *> *enumerator = [fileManager enumeratorAtURL:imagesURL includingPropertiesForKeys:@[NSURLIsRegularFileKey] options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:^BOOL(NSURL *url, NSError *error) {
        NSLog(@"EagleGridSaverApp: cache scan error %@: %@", url.path, error.localizedDescription);
        return YES;
    }];

    for (NSURL *fileURL in enumerator) {
        NSString *extension = fileURL.pathExtension.lowercaseString;
        BOOL isVideo = [videoExtensions containsObject:extension];
        if (![imageExtensions containsObject:extension] && !isVideo) {
            continue;
        }
        if ([fileURL.URLByDeletingPathExtension.lastPathComponent hasSuffix:@"_thumbnail"]) {
            continue;
        }
        if (![fileURL.URLByDeletingLastPathComponent.lastPathComponent hasSuffix:@".info"]) {
            continue;
        }
        [mediaFiles addObject:fileURL];
    }

    NSMutableArray<NSDictionary *> *items = NSMutableArray.array;
    NSUInteger total = MAX((NSUInteger)1, mediaFiles.count);
    __block NSUInteger processed = 0;
    __block NSUInteger succeeded = 0;
    __block NSUInteger failed = 0;

    if (mediaFiles.count == 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.statusLabel.stringValue = @"No supported Eagle assets found in this library.";
            self.progressIndicator.doubleValue = 0;
            self.progressIndicator.hidden = YES;
        });
        return NO;
    }

    for (NSURL *fileURL in mediaFiles) {
        @autoreleasepool {
            NSString *extension = fileURL.pathExtension.lowercaseString;
            BOOL isVideo = [videoExtensions containsObject:extension];
            NSDictionary *metadata = [self metadataForInfoFolder:fileURL.URLByDeletingLastPathComponent];
            if ([metadata[@"isDeleted"] boolValue]) {
                processed += 1;
                continue;
            }

            NSString *cacheName = [self cacheFilenameForSourceURL:fileURL];
            NSURL *outputURL = [cacheURL URLByAppendingPathComponent:cacheName];
            CGSize outputSize = CGSizeZero;
            BOOL ok = NO;

            if ([fileManager fileExistsAtPath:outputURL.path]) {
                outputSize = [self imageSizeForURL:outputURL];
                ok = outputSize.width > 0 && outputSize.height > 0;
            }

            if (!ok) {
                ok = [self writeDisplayImageForSourceURL:fileURL isVideo:isVideo toURL:outputURL outputSize:&outputSize];
            }

            if (ok) {
                succeeded += 1;
                NSString *title = [metadata[@"name"] isKindOfClass:NSString.class] ? metadata[@"name"] : fileURL.URLByDeletingPathExtension.lastPathComponent;
                [items addObject:@{
                    @"cachePath": cacheName,
                    @"sourcePath": fileURL.path ?: @"",
                    @"title": title ?: @"",
                    @"width": @(MAX(1.0, outputSize.width)),
                    @"height": @(MAX(1.0, outputSize.height)),
                    @"isVideo": @(isVideo)
                }];
            } else {
                failed += 1;
            }

            processed += 1;
            if (processed % 10 == 0 || processed == mediaFiles.count) {
                double progress = MIN(1.0, (double)processed / (double)total);
                NSString *status = [NSString stringWithFormat:@"Building index. Please wait... %lu / %lu, prepared %lu, skipped %lu",
                                    (unsigned long)processed,
                                    (unsigned long)mediaFiles.count,
                                    (unsigned long)succeeded,
                                    (unsigned long)failed];
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.progressIndicator.doubleValue = progress;
                    self.statusLabel.stringValue = status;
                });
            }
        }
    }

    [self removeStaleCacheFilesInFolder:cacheURL keepingItems:items];

    NSDictionary *manifest = @{
        @"version": EagleDisplayCacheVersion,
        @"libraryPath": libraryURL.path ?: @"",
        @"generatedAt": @((NSInteger)NSDate.date.timeIntervalSince1970),
        @"items": items
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:manifest options:0 error:nil];
    [data writeToURL:[cacheURL URLByAppendingPathComponent:@"manifest.json"] atomically:YES];

    dispatch_async(dispatch_get_main_queue(), ^{
        self.statusLabel.stringValue = [NSString stringWithFormat:@"Ready. Prepared %lu items, skipped %lu. You can close this app.",
                                        (unsigned long)succeeded,
                                        (unsigned long)failed];
    });
    return succeeded > 0;
}

- (void)removeStaleCacheFilesInFolder:(NSURL *)cacheURL keepingItems:(NSArray<NSDictionary *> *)items {
    NSMutableSet<NSString *> *keepNames = NSMutableSet.set;
    [keepNames addObject:@"manifest.json"];
    for (NSDictionary *item in items) {
        NSString *cachePath = [item[@"cachePath"] isKindOfClass:NSString.class] ? item[@"cachePath"] : nil;
        if (cachePath.length > 0) {
            [keepNames addObject:cachePath.lastPathComponent];
        }
    }

    NSArray<NSURL *> *children = [NSFileManager.defaultManager contentsOfDirectoryAtURL:cacheURL includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
    for (NSURL *child in children) {
        if (![keepNames containsObject:child.lastPathComponent]) {
            [NSFileManager.defaultManager removeItemAtURL:child error:nil];
        }
    }
}

- (NSDictionary *)metadataForInfoFolder:(NSURL *)infoURL {
    NSData *data = [NSData dataWithContentsOfURL:[infoURL URLByAppendingPathComponent:@"metadata.json"]];
    if (data == nil) {
        return @{};
    }
    NSDictionary *metadata = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [metadata isKindOfClass:NSDictionary.class] ? metadata : @{};
}

- (NSString *)cacheFilenameForSourceURL:(NSURL *)sourceURL {
    NSString *key = sourceURL.path;
    NSUInteger hash = key.hash;
    NSString *base = sourceURL.URLByDeletingPathExtension.lastPathComponent;
    NSCharacterSet *allowed = NSCharacterSet.alphanumericCharacterSet;
    NSMutableString *safe = NSMutableString.string;
    for (NSUInteger index = 0; index < MIN((NSUInteger)36, base.length); index++) {
        unichar ch = [base characterAtIndex:index];
        [safe appendString:[allowed characterIsMember:ch] ? [NSString stringWithCharacters:&ch length:1] : @"-"];
    }
    if (safe.length == 0) {
        [safe appendString:@"asset"];
    }
    return [NSString stringWithFormat:@"%lu-%@.jpg", (unsigned long)hash, safe];
}

- (BOOL)writeDisplayImageForSourceURL:(NSURL *)sourceURL isVideo:(BOOL)isVideo toURL:(NSURL *)outputURL outputSize:(CGSize *)outputSize {
    CGImageRef imageRef = NULL;
    if (isVideo) {
        imageRef = [self posterImageRefForVideoURL:sourceURL];
        if (imageRef == NULL) {
            NSURL *thumbnailURL = [self thumbnailURLForSourceURL:sourceURL];
            if (thumbnailURL != nil) {
                imageRef = [self thumbnailImageRefForImageURL:thumbnailURL maxPixelSize:1800];
            }
        }
    } else {
        imageRef = [self thumbnailImageRefForImageURL:sourceURL maxPixelSize:1800];
        if (imageRef == NULL) {
            NSURL *thumbnailURL = [self thumbnailURLForSourceURL:sourceURL];
            if (thumbnailURL != nil) {
                imageRef = [self thumbnailImageRefForImageURL:thumbnailURL maxPixelSize:1800];
            }
        }
    }

    if (imageRef == NULL) {
        return NO;
    }

    BOOL written = [self writeJPEGImageRef:imageRef toURL:outputURL];
    if (written && outputSize != NULL) {
        *outputSize = CGSizeMake(CGImageGetWidth(imageRef), CGImageGetHeight(imageRef));
    }
    CGImageRelease(imageRef);
    return written;
}

- (CGImageRef)thumbnailImageRefForImageURL:(NSURL *)url maxPixelSize:(CGFloat)maxPixelSize {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (source == NULL) {
        return NULL;
    }
    NSDictionary *options = @{
        (NSString *)kCGImageSourceCreateThumbnailFromImageIfAbsent: @YES,
        (NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES,
        (NSString *)kCGImageSourceShouldCacheImmediately: @YES,
        (NSString *)kCGImageSourceThumbnailMaxPixelSize: @(maxPixelSize)
    };
    CGImageRef imageRef = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
    CFRelease(source);
    return imageRef;
}

- (CGImageRef)posterImageRefForVideoURL:(NSURL *)url {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
    generator.appliesPreferredTrackTransform = YES;
    generator.maximumSize = CGSizeMake(1800, 1800);
    CGImageRef imageRef = [generator copyCGImageAtTime:CMTimeMakeWithSeconds(1.0, 600) actualTime:NULL error:nil];
    if (imageRef == NULL) {
        imageRef = [generator copyCGImageAtTime:kCMTimeZero actualTime:NULL error:nil];
    }
    return imageRef;
}

- (NSURL *)thumbnailURLForSourceURL:(NSURL *)sourceURL {
    NSURL *folderURL = sourceURL.URLByDeletingLastPathComponent;
    NSString *base = sourceURL.URLByDeletingPathExtension.lastPathComponent;
    NSArray<NSString *> *extensions = @[@"jpg", @"jpeg", @"png", @"webp"];
    for (NSString *extension in extensions) {
        NSURL *candidate = [folderURL URLByAppendingPathComponent:[NSString stringWithFormat:@"%@_thumbnail.%@", base, extension]];
        if ([NSFileManager.defaultManager fileExistsAtPath:candidate.path]) {
            return candidate;
        }
    }
    return nil;
}

- (BOOL)writeJPEGImageRef:(CGImageRef)imageRef toURL:(NSURL *)url {
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)url, CFSTR("public.jpeg"), 1, NULL);
    if (destination == NULL) {
        return NO;
    }
    NSDictionary *properties = @{
        (NSString *)kCGImageDestinationLossyCompressionQuality: @(0.86)
    };
    CGImageDestinationAddImage(destination, imageRef, (__bridge CFDictionaryRef)properties);
    BOOL ok = CGImageDestinationFinalize(destination);
    CFRelease(destination);
    return ok;
}

- (CGSize)imageSizeForURL:(NSURL *)url {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (source == NULL) {
        return CGSizeZero;
    }
    NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
    CFRelease(source);
    return CGSizeMake([properties[(NSString *)kCGImagePropertyPixelWidth] doubleValue],
                      [properties[(NSString *)kCGImagePropertyPixelHeight] doubleValue]);
}

- (void)openScreenSaverSettings:(id)sender {
    NSURL *url = [NSURL URLWithString:@"x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension"];
    [NSWorkspace.sharedWorkspace openURL:url];
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        AppDelegate *delegate = AppDelegate.new;
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
