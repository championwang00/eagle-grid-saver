#import "EagleGridSaverView.h"
#import <AVFoundation/AVFoundation.h>
#import <Cocoa/Cocoa.h>
#import <ImageIO/ImageIO.h>

@interface EagleArtwork : NSObject
@property(nonatomic, copy) NSURL *url;
@property(nonatomic, copy) NSURL *videoURL;
@property(nonatomic, copy) NSString *title;
@property(nonatomic) CGFloat width;
@property(nonatomic) CGFloat height;
@property(nonatomic) BOOL isVideo;
@property(nonatomic) BOOL usesPreparedDisplayImage;
@end

@implementation EagleArtwork
@end

@interface EagleCell : NSObject
@property(nonatomic, strong) EagleArtwork *artwork;
@property(nonatomic, strong) NSImage *image;
@property(nonatomic, strong) CALayer *contentLayer;
@property(nonatomic, strong) AVPlayer *player;
@property(nonatomic, strong) AVPlayerLayer *playerLayer;
@property(nonatomic, strong) AVPlayerItemVideoOutput *videoOutput;
@property(nonatomic, strong) id videoEndObserver;
@property(nonatomic) NSRect frame;
@property(nonatomic) NSInteger column;
@property(nonatomic) NSInteger columnCount;
@property(nonatomic) CGFloat phase;
@property(nonatomic) CFTimeInterval videoStartTime;
@property(nonatomic) BOOL videoLayerReady;
@property(nonatomic) BOOL videoPlaybackFailed;
@end

@implementation EagleCell
@end

@interface EagleGridSaverView ()
@property(nonatomic, strong) NSMutableArray<EagleArtwork *> *artworks;
@property(nonatomic, strong) NSMutableArray<EagleCell *> *cells;
@property(nonatomic, strong) NSCache<NSURL *, NSImage *> *imageCache;
@property(nonatomic, strong) NSMutableSet<NSURL *> *loadingURLs;
@property(nonatomic) dispatch_queue_t imageQueue;
@property(nonatomic) dispatch_queue_t scanQueue;
@property(nonatomic, strong) CALayer *backgroundImageLayer;
@property(nonatomic, strong) CALayer *contentLayerRoot;
@property(nonatomic, strong) CATextLayer *statusTextLayer;
@property(nonatomic, strong) NSWindow *optionsSheet;
@property(nonatomic, strong) NSTextField *configurePathLabel;
@property(nonatomic, strong) NSTextField *configureSpeedLabel;
@property(nonatomic, strong) NSSlider *configureSpeedSlider;
@property(nonatomic, copy) NSString *statusMessage;
@property(nonatomic) NSSize lastLayoutSize;
@property(nonatomic) NSInteger tick;
@property(nonatomic) CGFloat scrollOffset;
@property(nonatomic) BOOL isScanning;
@property(nonatomic) BOOL libraryIsNetworkVolume;
@property(nonatomic) BOOL displayCacheRequiresUpdate;
@end

@implementation EagleGridSaverView

static NSInteger const MaxVisibleCells = 28;
static NSInteger const InitialSynchronousCells = 4;
static NSInteger const NetworkScanAssetLimit = 160;
static CGFloat const HorizontalGap = 0.0;
static CGFloat const VerticalGap = 0.0;
static CGFloat const ScrollSpeed = 0.225;
static CGFloat const MinScrollSpeedMultiplier = 0.25;
static CGFloat const MaxScrollSpeedMultiplier = 10.0;
static CGFloat const TileCornerRadius = 0.0;
static CGFloat const TargetFrameRate = 24.0;
static CGFloat const ImageDecodeMaxPixelSize = 1100.0;
static CGFloat const VideoPosterMaxPixelSize = 900.0;
static CGFloat const VideoStartupTimeout = 3.0;
static BOOL const EnableSyntheticGapTest = NO;
static CGFloat const HorizontalBleed = 0.0;
static CGFloat const VerticalBleed = 2.0;
static NSString * const EagleDisplayCacheVersion = @"4";
static NSString * const EagleScrollSpeedMultiplierKey = @"EagleGridSaver.scrollSpeedMultiplier";

- (instancetype)initWithFrame:(NSRect)frame isPreview:(BOOL)isPreview {
    self = [super initWithFrame:frame isPreview:isPreview];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    self.animationTimeInterval = 1.0 / TargetFrameRate;
    self.wantsLayer = YES;
    self.layer.backgroundColor = NSColor.blackColor.CGColor;
    self.backgroundImageLayer = CALayer.layer;
    self.backgroundImageLayer.frame = self.bounds;
    self.backgroundImageLayer.contentsGravity = kCAGravityResizeAspectFill;
    self.backgroundImageLayer.masksToBounds = YES;
    self.backgroundImageLayer.backgroundColor = NSColor.blackColor.CGColor;
    [self.layer addSublayer:self.backgroundImageLayer];

    self.contentLayerRoot = CALayer.layer;
    self.contentLayerRoot.frame = self.bounds;
    self.contentLayerRoot.masksToBounds = YES;
    self.contentLayerRoot.geometryFlipped = NO;
    [self.layer addSublayer:self.contentLayerRoot];

    self.statusTextLayer = CATextLayer.layer;
    self.statusTextLayer.frame = self.bounds;
    self.statusTextLayer.contentsScale = NSScreen.mainScreen.backingScaleFactor;
    self.statusTextLayer.alignmentMode = kCAAlignmentCenter;
    self.statusTextLayer.foregroundColor = [NSColor colorWithCalibratedWhite:1.0 alpha:0.78].CGColor;
    self.statusTextLayer.fontSize = 22.0;
    self.statusTextLayer.wrapped = YES;
    self.statusTextLayer.hidden = YES;
    [self.layer addSublayer:self.statusTextLayer];

    self.artworks = NSMutableArray.array;
    self.cells = NSMutableArray.array;
    self.imageCache = NSCache.new;
    self.imageCache.countLimit = 160;
    self.loadingURLs = NSMutableSet.set;
    self.imageQueue = dispatch_queue_create("com.chaopi.EagleGridSaver.imageQueue", DISPATCH_QUEUE_CONCURRENT);
    self.scanQueue = dispatch_queue_create("com.chaopi.EagleGridSaver.scanQueue", DISPATCH_QUEUE_SERIAL);
    self.statusMessage = @"Looking for Eagle library images...";
    if (EnableSyntheticGapTest) {
        [self loadSyntheticArtworks];
    } else {
        self.artworks = [[self loadCachedArtworks] mutableCopy];
        if (self.artworks.count == 0) {
            [self loadArtworksAsync];
        }
    }
}

- (BOOL)hasConfigureSheet {
    return YES;
}

- (NSWindow *)configureSheet {
    if (self.optionsSheet != nil) {
        [self refreshConfigurePathLabel];
        [self refreshConfigureSpeedControls];
        return self.optionsSheet;
    }

    NSWindow *sheet = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 560, 310)
                                                 styleMask:(NSWindowStyleMaskTitled)
                                                   backing:NSBackingStoreBuffered
                                                     defer:NO];
    sheet.title = @"Eagle Grid Saver Options";
    NSView *content = sheet.contentView;

    NSTextField *title = [self configureLabel:@"Eagle Grid Saver" font:[NSFont systemFontOfSize:22.0 weight:NSFontWeightSemibold] color:NSColor.labelColor];
    title.frame = NSMakeRect(28, 254, 300, 30);
    [content addSubview:title];

    NSTextField *versionLabel = [self configureLabel:[self versionDisplayString] font:[NSFont monospacedSystemFontOfSize:12.0 weight:NSFontWeightRegular] color:NSColor.secondaryLabelColor];
    versionLabel.frame = NSMakeRect(344, 260, 188, 18);
    versionLabel.alignment = NSTextAlignmentRight;
    [content addSubview:versionLabel];

    NSTextField *description = [self configureLabel:@"Choose the Eagle .library folder here, inside System Settings. This gives the actual screen saver host permission to read your library." font:[NSFont systemFontOfSize:13.0] color:NSColor.secondaryLabelColor];
    description.frame = NSMakeRect(28, 204, 504, 42);
    description.maximumNumberOfLines = 2;
    [content addSubview:description];

    self.configurePathLabel = [self configureLabel:@"" font:[NSFont monospacedSystemFontOfSize:12.0 weight:NSFontWeightRegular] color:NSColor.labelColor];
    self.configurePathLabel.frame = NSMakeRect(28, 156, 504, 34);
    self.configurePathLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    self.configurePathLabel.maximumNumberOfLines = 2;
    [content addSubview:self.configurePathLabel];

    self.configureSpeedLabel = [self configureLabel:@"" font:[NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium] color:NSColor.labelColor];
    self.configureSpeedLabel.frame = NSMakeRect(28, 116, 180, 20);
    [content addSubview:self.configureSpeedLabel];

    self.configureSpeedSlider = NSSlider.new;
    self.configureSpeedSlider.frame = NSMakeRect(208, 112, 324, 24);
    self.configureSpeedSlider.minValue = MinScrollSpeedMultiplier;
    self.configureSpeedSlider.maxValue = MaxScrollSpeedMultiplier;
    self.configureSpeedSlider.numberOfTickMarks = 11;
    self.configureSpeedSlider.allowsTickMarkValuesOnly = NO;
    self.configureSpeedSlider.target = self;
    self.configureSpeedSlider.action = @selector(configureSpeedChanged:);
    [content addSubview:self.configureSpeedSlider];

    NSButton *chooseButton = [NSButton buttonWithTitle:@"Choose Eagle Library..." target:self action:@selector(chooseLibraryFromConfigureSheet:)];
    chooseButton.frame = NSMakeRect(28, 54, 180, 34);
    chooseButton.bezelStyle = NSBezelStyleRounded;
    [content addSubview:chooseButton];

    NSButton *closeButton = [NSButton buttonWithTitle:@"Done" target:self action:@selector(closeConfigureSheet:)];
    closeButton.frame = NSMakeRect(452, 22, 80, 32);
    closeButton.bezelStyle = NSBezelStyleRounded;
    [content addSubview:closeButton];

    self.optionsSheet = sheet;
    [self refreshConfigurePathLabel];
    [self refreshConfigureSpeedControls];
    return sheet;
}

- (NSString *)versionDisplayString {
    NSDictionary *info = [NSBundle bundleForClass:self.class].infoDictionary;
    NSString *version = [info[@"CFBundleShortVersionString"] isKindOfClass:NSString.class] ? info[@"CFBundleShortVersionString"] : @"?";
    NSString *build = [info[@"CFBundleVersion"] isKindOfClass:NSString.class] ? info[@"CFBundleVersion"] : @"?";
    return [NSString stringWithFormat:@"Version %@ (%@)", version, build];
}

- (NSTextField *)configureLabel:(NSString *)string font:(NSFont *)font color:(NSColor *)color {
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

- (void)chooseLibraryFromConfigureSheet:(id)sender {
    NSOpenPanel *panel = NSOpenPanel.openPanel;
    panel.title = @"Choose Eagle Library";
    panel.prompt = @"Choose";
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = NO;
    panel.resolvesAliases = YES;

    if ([panel runModal] != NSModalResponseOK || panel.URL == nil) {
        return;
    }

    NSURL *url = panel.URL;
    if (![url.pathExtension.lowercaseString isEqualToString:@"library"]) {
        NSAlert *alert = NSAlert.new;
        alert.messageText = @"Choose an Eagle .library folder";
        alert.informativeText = @"The selected folder does not look like an Eagle library.";
        [alert runModal];
        return;
    }

    NSError *error = nil;
    NSData *bookmark = [url bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope includingResourceValuesForKeys:nil relativeToURL:nil error:&error];
    if (bookmark == nil) {
        NSAlert *alert = NSAlert.new;
        alert.messageText = @"Could not save folder access";
        alert.informativeText = error.localizedDescription ?: @"macOS did not return a folder access token.";
        [alert runModal];
        return;
    }

    ScreenSaverDefaults *defaults = [ScreenSaverDefaults defaultsForModuleWithName:@"com.chaopi.EagleGridSaver"];
    [defaults setObject:url.path forKey:@"EagleGridSaver.libraryPath"];
    [defaults setObject:bookmark forKey:@"EagleGridSaver.libraryBookmark"];
    [defaults synchronize];
    CFPreferencesSetAppValue((CFStringRef)@"EagleGridSaver.libraryPath", (__bridge CFStringRef)url.path, (CFStringRef)@"com.chaopi.EagleGridSaver");
    CFPreferencesSetAppValue((CFStringRef)@"EagleGridSaver.libraryBookmark", (__bridge CFDataRef)bookmark, (CFStringRef)@"com.chaopi.EagleGridSaver");
    CFPreferencesAppSynchronize((CFStringRef)@"com.chaopi.EagleGridSaver");

    self.displayCacheRequiresUpdate = YES;
    self.statusMessage = @"Library saved. Open Eagle Grid Saver.app and click Update Index before starting the screen saver.";
    [self refreshConfigurePathLabel];
    [self.artworks removeAllObjects];
    [self.cells removeAllObjects];
    [self setNeedsDisplay:YES];
}

- (void)closeConfigureSheet:(id)sender {
    [NSApp endSheet:self.optionsSheet];
}

- (void)refreshConfigurePathLabel {
    NSString *path = [self configuredLibraryURL].path;
    self.configurePathLabel.stringValue = path.length > 0 ? path : @"No Eagle library selected";
}

- (void)refreshConfigureSpeedControls {
    CGFloat multiplier = [self scrollSpeedMultiplier];
    self.configureSpeedLabel.stringValue = [NSString stringWithFormat:@"Scroll Speed %.1fx", multiplier];
    self.configureSpeedSlider.doubleValue = multiplier;
}

- (void)configureSpeedChanged:(NSSlider *)sender {
    [self saveScrollSpeedMultiplier:sender.doubleValue];
    [self refreshConfigureSpeedControls];
}

- (CGFloat)effectiveScrollSpeed {
    return ScrollSpeed * [self scrollSpeedMultiplier];
}

- (CGFloat)scrollSpeedMultiplier {
    NSDictionary *containerPreferences = [NSDictionary dictionaryWithContentsOfFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Preferences/com.chaopi.EagleGridSaver.plist"]];
    id containerValue = containerPreferences[EagleScrollSpeedMultiplierKey];
    if (containerValue != nil) {
        return [self clampedScrollSpeedMultiplier:[containerValue doubleValue]];
    }

    NSArray<NSUserDefaults *> *defaultsList = @[
        [ScreenSaverDefaults defaultsForModuleWithName:@"com.chaopi.EagleGridSaver"],
        NSUserDefaults.standardUserDefaults,
        [[NSUserDefaults alloc] initWithSuiteName:@"com.chaopi.EagleGridSaver"]
    ];

    for (NSUserDefaults *defaults in defaultsList) {
        id value = [defaults objectForKey:EagleScrollSpeedMultiplierKey];
        if (value != nil) {
            return [self clampedScrollSpeedMultiplier:[value doubleValue]];
        }
    }

    id domainValue = CFBridgingRelease(CFPreferencesCopyAppValue((CFStringRef)EagleScrollSpeedMultiplierKey, (CFStringRef)@"com.chaopi.EagleGridSaver"));
    if (domainValue != nil) {
        return [self clampedScrollSpeedMultiplier:[domainValue doubleValue]];
    }

    return 1.0;
}

- (CGFloat)clampedScrollSpeedMultiplier:(CGFloat)value {
    if (!isfinite(value) || value <= 0.0) {
        return 1.0;
    }
    return MIN(MaxScrollSpeedMultiplier, MAX(MinScrollSpeedMultiplier, value));
}

- (void)saveScrollSpeedMultiplier:(CGFloat)multiplier {
    NSNumber *value = @([self clampedScrollSpeedMultiplier:multiplier]);
    NSArray<NSUserDefaults *> *defaultsList = @[
        [ScreenSaverDefaults defaultsForModuleWithName:@"com.chaopi.EagleGridSaver"],
        NSUserDefaults.standardUserDefaults,
        [[NSUserDefaults alloc] initWithSuiteName:@"com.chaopi.EagleGridSaver"]
    ];
    for (NSUserDefaults *defaults in defaultsList) {
        [defaults setObject:value forKey:EagleScrollSpeedMultiplierKey];
        [defaults synchronize];
    }
    CFPreferencesSetAppValue((CFStringRef)EagleScrollSpeedMultiplierKey, (__bridge CFNumberRef)value, (CFStringRef)@"com.chaopi.EagleGridSaver");
    CFPreferencesAppSynchronize((CFStringRef)@"com.chaopi.EagleGridSaver");
}

- (void)startAnimation {
    [super startAnimation];
    if (self.artworks.count == 0) {
        [self loadArtworksAsync];
    } else {
        [self rebuildLayoutIfNeeded];
    }
    [self setNeedsDisplay:YES];
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    [self rebuildLayoutIfNeeded];
}

- (void)setBoundsSize:(NSSize)newSize {
    [super setBoundsSize:newSize];
    [self rebuildLayoutIfNeeded];
}

- (void)stopAnimation {
    [self clearVideoLayers];
    [super stopAnimation];
}

- (void)animateOneFrame {
    self.tick += 1;
    [self rebuildLayoutIfNeeded];
    self.scrollOffset += [self effectiveScrollSpeed];
    self.contentLayerRoot.frame = self.bounds;
    self.contentLayerRoot.bounds = self.bounds;
    self.statusTextLayer.frame = self.bounds;
    [self advanceWaterfallIfNeeded];
    [self updateVideoLayers];
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)rect {
    [NSColor.blackColor setFill];
    NSRectFill(self.bounds);
    self.contentLayerRoot.frame = self.bounds;
    self.contentLayerRoot.bounds = self.bounds;

    [self rebuildLayoutIfNeeded];

    if (self.cells.count == 0) {
        [self drawEmptyState];
        [self updateStatusLayerVisible:YES];
        return;
    }

    BOOL drewAnyCell = NO;
    for (EagleCell *cell in self.cells) {
        drewAnyCell = [self drawFallbackCell:cell] || drewAnyCell;
    }
    if (!drewAnyCell) {
        self.statusMessage = self.isScanning ? @"Loading Eagle library..." : @"Loading artwork...";
    }
    [self updateStatusLayerVisible:!drewAnyCell];
}

- (void)rebuildLayoutIfNeeded {
    if (self.artworks.count == 0 || self.bounds.size.width < 100.0 || self.bounds.size.height < 100.0) {
        return;
    }
    if (!NSEqualSizes(self.bounds.size, self.lastLayoutSize) || self.cells.count == 0) {
        [self rebuildLayout];
    }
}

- (void)loadArtworksIfAvailable {
    NSMutableArray<EagleArtwork *> *fresh = [self scanArtworks];
    if (fresh.count > 0) {
        self.artworks = fresh;
    }
}

- (void)loadArtworks {
    self.artworks = [self scanArtworks];
    [self.cells removeAllObjects];
}

- (void)loadArtworksAsync {
    if (self.isScanning) {
        return;
    }

    self.isScanning = YES;
    self.statusMessage = @"Loading Eagle library...";
    [self updateStatusLayerVisible:YES];
    [self setNeedsDisplay:YES];

    __weak typeof(self) weakSelf = self;
    dispatch_async(self.scanQueue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        NSMutableArray<EagleArtwork *> *fresh = [strongSelf scanArtworks];

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) innerSelf = weakSelf;
            if (innerSelf == nil) {
                return;
            }

            innerSelf.isScanning = NO;
            innerSelf.artworks = fresh;
            if (fresh.count > 0) {
                [innerSelf saveCachedArtworks:fresh];
            }
            [innerSelf.cells removeAllObjects];
            [innerSelf rebuildLayout];
            [innerSelf setNeedsDisplay:YES];
        });
    });
}

- (NSURL *)applicationSupportFolderURL {
    NSURL *supportURL = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *folderURL = [supportURL URLByAppendingPathComponent:@"EagleGridSaver" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:folderURL withIntermediateDirectories:YES attributes:nil error:nil];
    return folderURL;
}

- (NSURL *)assetIndexURL {
    NSURL *folderURL = [self applicationSupportFolderURL];
    return [folderURL URLByAppendingPathComponent:@"asset-index.json"];
}

- (NSURL *)displayCacheManifestURL {
    NSURL *configuredCacheURL = [self configuredDisplayCacheFolderURL];
    NSURL *folderURL = configuredCacheURL ?: [[self applicationSupportFolderURL] URLByAppendingPathComponent:@"DisplayCache" isDirectory:YES];
    return [folderURL URLByAppendingPathComponent:@"manifest.json"];
}

- (NSURL *)configuredDisplayCacheFolderURL {
    NSArray<NSUserDefaults *> *defaultsList = @[
        [ScreenSaverDefaults defaultsForModuleWithName:@"com.chaopi.EagleGridSaver"],
        NSUserDefaults.standardUserDefaults,
        [[NSUserDefaults alloc] initWithSuiteName:@"com.chaopi.EagleGridSaver"]
    ];

    for (NSUserDefaults *defaults in defaultsList) {
        NSString *path = [defaults stringForKey:@"EagleGridSaver.displayCachePath"];
        if (path.length > 0) {
            return [NSURL fileURLWithPath:path isDirectory:YES];
        }
    }

    NSString *domainPath = CFBridgingRelease(CFPreferencesCopyAppValue((CFStringRef)@"EagleGridSaver.displayCachePath", (CFStringRef)@"com.chaopi.EagleGridSaver"));
    if ([domainPath isKindOfClass:NSString.class] && domainPath.length > 0) {
        return [NSURL fileURLWithPath:domainPath isDirectory:YES];
    }

    return nil;
}

- (NSArray<EagleArtwork *> *)loadCachedArtworks {
    NSArray<EagleArtwork *> *displayCache = [self loadDisplayCacheArtworks];
    if (displayCache.count > 0) {
        return displayCache;
    }

    if (!self.displayCacheRequiresUpdate) {
        self.displayCacheRequiresUpdate = YES;
        self.statusMessage = [NSString stringWithFormat:@"No prepared index found.\nOpen Eagle Grid Saver.app and click Update Index.\nCache: %@",
                              self.displayCacheManifestURL.path];
    }
    return @[];
}

- (NSArray<EagleArtwork *> *)loadDisplayCacheArtworks {
    NSData *data = [NSData dataWithContentsOfURL:[self displayCacheManifestURL]];
    if (data == nil) {
        self.statusMessage = [NSString stringWithFormat:@"No prepared index found.\nOpen Eagle Grid Saver.app and click Update Index.\nCache: %@",
                              self.displayCacheManifestURL.path];
        return @[];
    }

    NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![manifest isKindOfClass:NSDictionary.class]) {
        self.statusMessage = [NSString stringWithFormat:@"Index file is invalid.\nOpen Eagle Grid Saver.app and click Update Index.\nCache: %@",
                              self.displayCacheManifestURL.path];
        return @[];
    }

    NSString *version = [manifest[@"version"] description];
    if (![version isEqualToString:EagleDisplayCacheVersion]) {
        self.displayCacheRequiresUpdate = YES;
        self.statusMessage = [NSString stringWithFormat:@"Index version is old (%@). Open Eagle Grid Saver.app and click Update Index.\nCache: %@",
                              version,
                              self.displayCacheManifestURL.path];
        return @[];
    }

    NSString *cachedLibraryPath = [manifest[@"libraryPath"] isKindOfClass:NSString.class] ? manifest[@"libraryPath"] : nil;
    NSArray<NSString *> *currentLibraryPaths = [self configuredLibraryPathCandidates];

    NSArray *items = [manifest[@"items"] isKindOfClass:NSArray.class] ? manifest[@"items"] : nil;
    if (items.count == 0) {
        self.displayCacheRequiresUpdate = YES;
        self.statusMessage = [NSString stringWithFormat:@"Index has no displayable items. Open Eagle Grid Saver.app and click Update Index.\nCache: %@",
                              self.displayCacheManifestURL.path];
        return @[];
    }

    NSURL *cacheRoot = [[self displayCacheManifestURL] URLByDeletingLastPathComponent];
    NSMutableArray<EagleArtwork *> *cached = NSMutableArray.array;
    for (NSDictionary *item in items) {
        if (![item isKindOfClass:NSDictionary.class]) {
            continue;
        }

        NSString *relativePath = [item[@"cachePath"] isKindOfClass:NSString.class] ? item[@"cachePath"] : nil;
        if (relativePath.length == 0) {
            continue;
        }

        NSURL *url = [cacheRoot URLByAppendingPathComponent:relativePath];
        if (![NSFileManager.defaultManager fileExistsAtPath:url.path]) {
            continue;
        }

        EagleArtwork *artwork = EagleArtwork.new;
        artwork.url = url;
        artwork.title = [item[@"title"] isKindOfClass:NSString.class] ? item[@"title"] : url.URLByDeletingPathExtension.lastPathComponent;
        artwork.width = MAX(1.0, [item[@"width"] doubleValue]);
        artwork.height = MAX(1.0, [item[@"height"] doubleValue]);
        artwork.isVideo = [item[@"isVideo"] boolValue];
        artwork.usesPreparedDisplayImage = YES;
        NSString *sourcePath = [item[@"sourcePath"] isKindOfClass:NSString.class] ? item[@"sourcePath"] : nil;
        if (artwork.isVideo && sourcePath.length > 0) {
            artwork.videoURL = [self remappedSourceURLForPath:sourcePath
                                            cachedLibraryPath:cachedLibraryPath
                                          currentLibraryPaths:currentLibraryPaths];
        }
        [cached addObject:artwork];
    }

    if (cached.count > 0) {
        self.libraryIsNetworkVolume = NO;
        self.statusMessage = [NSString stringWithFormat:@"Loaded %lu prepared Eagle items from %@",
                              (unsigned long)cached.count,
                              self.displayCacheManifestURL.path];
    }
    return cached;
}

- (NSURL *)remappedSourceURLForPath:(NSString *)sourcePath cachedLibraryPath:(NSString *)cachedLibraryPath currentLibraryPaths:(NSArray<NSString *> *)currentLibraryPaths {
    if (sourcePath.length == 0) {
        return nil;
    }

    NSFileManager *fileManager = NSFileManager.defaultManager;
    if ([fileManager fileExistsAtPath:sourcePath]) {
        return [NSURL fileURLWithPath:sourcePath];
    }

    if (cachedLibraryPath.length > 0 && [sourcePath hasPrefix:cachedLibraryPath]) {
        NSString *relativePath = [sourcePath substringFromIndex:cachedLibraryPath.length];
        for (NSString *currentLibraryPath in currentLibraryPaths) {
            if (currentLibraryPath.length == 0 || [currentLibraryPath isEqualToString:cachedLibraryPath]) {
                continue;
            }

            NSString *candidatePath = [currentLibraryPath stringByAppendingString:relativePath];
            if ([fileManager fileExistsAtPath:candidatePath]) {
                return [NSURL fileURLWithPath:candidatePath];
            }
        }
    }

    return [NSURL fileURLWithPath:sourcePath];
}

- (NSArray<NSString *> *)configuredLibraryPathCandidates {
    NSMutableArray<NSString *> *paths = NSMutableArray.array;
    NSMutableSet<NSString *> *seen = NSMutableSet.set;

    void (^addPath)(NSString *) = ^(NSString *path) {
        if (path.length == 0 || [seen containsObject:path]) {
            return;
        }
        [seen addObject:path];
        [paths addObject:path];
    };

    NSURL *configuredURL = [self configuredLibraryURL];
    addPath(configuredURL.path);

    NSArray<NSUserDefaults *> *defaultsList = @[
        [ScreenSaverDefaults defaultsForModuleWithName:@"com.chaopi.EagleGridSaver"],
        NSUserDefaults.standardUserDefaults,
        [[NSUserDefaults alloc] initWithSuiteName:@"com.chaopi.EagleGridSaver"]
    ];

    for (NSUserDefaults *defaults in defaultsList) {
        addPath([defaults stringForKey:@"EagleGridSaver.libraryPath"]);
    }

    NSString *domainPath = CFBridgingRelease(CFPreferencesCopyAppValue((CFStringRef)@"EagleGridSaver.libraryPath", (CFStringRef)@"com.chaopi.EagleGridSaver"));
    if ([domainPath isKindOfClass:NSString.class]) {
        addPath(domainPath);
    }

    NSDictionary *preferencePlist = [NSDictionary dictionaryWithContentsOfFile:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Preferences/com.chaopi.EagleGridSaver.plist"]];
    NSString *plistPath = [preferencePlist[@"EagleGridSaver.libraryPath"] isKindOfClass:NSString.class] ? preferencePlist[@"EagleGridSaver.libraryPath"] : nil;
    addPath(plistPath);

    return paths;
}

- (void)saveCachedArtworks:(NSArray<EagleArtwork *> *)artworks {
    NSMutableArray<NSDictionary *> *items = NSMutableArray.array;
    NSUInteger limit = MIN((NSUInteger)500, artworks.count);
    for (NSUInteger index = 0; index < limit; index++) {
        EagleArtwork *artwork = artworks[index];
        [items addObject:@{
            @"path": artwork.url.path ?: @"",
            @"title": artwork.title ?: @"",
            @"width": @(artwork.width),
            @"height": @(artwork.height),
            @"isVideo": @(artwork.isVideo)
        }];
    }

    NSData *data = [NSJSONSerialization dataWithJSONObject:items options:0 error:nil];
    [data writeToURL:[self assetIndexURL] atomically:YES];
}

- (void)loadSyntheticArtworks {
    self.artworks = NSMutableArray.array;
    NSArray<NSString *> *colors = @[@"#f05a5a", @"#42a5f5", @"#66bb6a", @"#ffca28", @"#ab47bc", @"#26c6da", @"#ff7043", @"#9ccc65", @"#7e57c2", @"#ec407a", @"#29b6f6", @"#ffa726", @"#8d6e63", @"#78909c"];
    for (NSUInteger index = 0; index < colors.count; index++) {
        EagleArtwork *artwork = EagleArtwork.new;
        artwork.url = [NSURL URLWithString:[NSString stringWithFormat:@"synthetic://%@", colors[index]]];
        artwork.title = colors[index];
        artwork.width = 16.0;
        artwork.height = 9.0;
        artwork.isVideo = NO;
        artwork.usesPreparedDisplayImage = NO;
        [self.artworks addObject:artwork];
    }
}

- (NSMutableArray<EagleArtwork *> *)scanArtworks {
    NSFileManager *fileManager = NSFileManager.defaultManager;
    NSMutableArray<NSURL *> *libraries = NSMutableArray.array;
    NSMutableArray<NSString *> *scanNotes = NSMutableArray.array;

    NSURL *configuredLibraryURL = [self configuredLibraryURL];
    if (configuredLibraryURL != nil) {
        [libraries addObject:configuredLibraryURL];
        self.libraryIsNetworkVolume = [self isNetworkVolumeURL:configuredLibraryURL];
    }

    NSArray<NSURL *> *parents = @[
        [fileManager.homeDirectoryForCurrentUser URLByAppendingPathComponent:@"Desktop"],
        [fileManager.homeDirectoryForCurrentUser URLByAppendingPathComponent:@"Documents"],
        [fileManager.homeDirectoryForCurrentUser URLByAppendingPathComponent:@"Downloads"]
    ];

    for (NSURL *parent in parents) {
        NSError *parentError = nil;
        NSArray<NSURL *> *children = [fileManager contentsOfDirectoryAtURL:parent includingPropertiesForKeys:@[NSURLIsDirectoryKey] options:NSDirectoryEnumerationSkipsHiddenFiles error:&parentError];
        if (parentError != nil) {
            [scanNotes addObject:[NSString stringWithFormat:@"%@: %@", parent.path, parentError.localizedDescription]];
        }
        for (NSURL *child in children) {
            if ([child.pathExtension isEqualToString:@"library"]) {
                [libraries addObject:child];
            }
        }
    }

    NSMutableArray<EagleArtwork *> *results = NSMutableArray.array;
    NSMutableSet<NSString *> *seenPaths = NSMutableSet.set;
    NSSet<NSString *> *imageExtensions = [NSSet setWithArray:@[@"jpg", @"jpeg", @"png", @"webp", @"heic", @"tif", @"tiff", @"gif"]];
    NSSet<NSString *> *videoExtensions = [NSSet setWithArray:@[@"mov", @"mp4", @"m4v"]];

    for (NSURL *library in libraries) {
        NSURL *imagesURL = [library URLByAppendingPathComponent:@"images" isDirectory:YES];
        BOOL isDirectory = NO;
        if (![fileManager fileExistsAtPath:imagesURL.path isDirectory:&isDirectory] || !isDirectory) {
            [scanNotes addObject:[NSString stringWithFormat:@"%@: images folder not readable", library.path]];
            continue;
        }

        __block NSMutableArray<NSString *> *enumerationNotes = scanNotes;
        NSDirectoryEnumerator<NSURL *> *enumerator = [fileManager enumeratorAtURL:imagesURL includingPropertiesForKeys:@[NSURLIsRegularFileKey] options:NSDirectoryEnumerationSkipsHiddenFiles errorHandler:^BOOL(NSURL *url, NSError *error) {
            [enumerationNotes addObject:[NSString stringWithFormat:@"%@: %@", url.path, error.localizedDescription]];
            return YES;
        }];

        for (NSURL *fileURL in enumerator) {
            NSString *extension = fileURL.pathExtension.lowercaseString;
            BOOL isVideo = [videoExtensions containsObject:extension];
            if (![imageExtensions containsObject:extension] && !isVideo) {
                continue;
            }

            NSString *nameWithoutExtension = fileURL.URLByDeletingPathExtension.lastPathComponent;
            if ([nameWithoutExtension hasSuffix:@"_thumbnail"]) {
                continue;
            }

            NSString *parentName = fileURL.URLByDeletingLastPathComponent.lastPathComponent;
            if (![parentName hasSuffix:@".info"]) {
                continue;
            }

            if ([seenPaths containsObject:fileURL.path]) {
                continue;
            }
            [seenPaths addObject:fileURL.path];

            EagleArtwork *artwork = [self artworkForURL:fileURL isVideo:isVideo];
            if (artwork != nil) {
                [results addObject:artwork];
            }
            if (self.libraryIsNetworkVolume && results.count >= NetworkScanAssetLimit) {
                break;
            }
        }
        if (self.libraryIsNetworkVolume && results.count >= NetworkScanAssetLimit) {
            break;
        }
    }

    [self shuffleArray:results];
    if (results.count > 0) {
        NSUInteger videoCount = 0;
        for (EagleArtwork *artwork in results) {
            if (artwork.isVideo) {
                videoCount += 1;
            }
        }
        self.statusMessage = [NSString stringWithFormat:@"Loaded %lu Eagle items (%lu videos)", (unsigned long)results.count, (unsigned long)videoCount];
    } else if (scanNotes.count > 0) {
        self.statusMessage = [NSString stringWithFormat:@"No images found. %@", scanNotes.firstObject];
    } else {
        self.statusMessage = [NSString stringWithFormat:@"No images found. Checked %lu library path(s).", (unsigned long)libraries.count];
    }
    NSLog(@"EagleGridSaver: %@", self.statusMessage);
    return results;
}

- (NSURL *)configuredLibraryURL {
    NSArray<NSUserDefaults *> *defaultsList = @[
        [ScreenSaverDefaults defaultsForModuleWithName:@"com.chaopi.EagleGridSaver"],
        NSUserDefaults.standardUserDefaults,
        [[NSUserDefaults alloc] initWithSuiteName:@"com.chaopi.EagleGridSaver"]
    ];

    for (NSUserDefaults *defaults in defaultsList) {
        NSData *bookmarkData = [defaults dataForKey:@"EagleGridSaver.libraryBookmark"];
        if (bookmarkData.length == 0) {
            continue;
        }

        BOOL stale = NO;
        NSError *error = nil;
        NSURL *url = [NSURL URLByResolvingBookmarkData:bookmarkData options:NSURLBookmarkResolutionWithSecurityScope relativeToURL:nil bookmarkDataIsStale:&stale error:&error];
        if (url != nil) {
            [url startAccessingSecurityScopedResource];
            return url;
        }
        if (error != nil) {
            NSLog(@"EagleGridSaver: failed to resolve library bookmark: %@", error.localizedDescription);
        }
    }

    NSData *domainBookmarkData = CFBridgingRelease(CFPreferencesCopyAppValue((CFStringRef)@"EagleGridSaver.libraryBookmark", (CFStringRef)@"com.chaopi.EagleGridSaver"));
    if ([domainBookmarkData isKindOfClass:NSData.class] && domainBookmarkData.length > 0) {
        BOOL stale = NO;
        NSError *error = nil;
        NSURL *url = [NSURL URLByResolvingBookmarkData:domainBookmarkData options:NSURLBookmarkResolutionWithSecurityScope relativeToURL:nil bookmarkDataIsStale:&stale error:&error];
        if (url != nil) {
            [url startAccessingSecurityScopedResource];
            return url;
        }
        if (error != nil) {
            NSLog(@"EagleGridSaver: failed to resolve domain library bookmark: %@", error.localizedDescription);
        }
    }

    for (NSUserDefaults *defaults in defaultsList) {
        NSString *configuredPath = [defaults stringForKey:@"EagleGridSaver.libraryPath"];
        if (configuredPath.length > 0) {
            return [NSURL fileURLWithPath:configuredPath];
        }
    }

    NSString *domainPath = CFBridgingRelease(CFPreferencesCopyAppValue((CFStringRef)@"EagleGridSaver.libraryPath", (CFStringRef)@"com.chaopi.EagleGridSaver"));
    if ([domainPath isKindOfClass:NSString.class] && domainPath.length > 0) {
        return [NSURL fileURLWithPath:domainPath];
    }

    return nil;
}

- (BOOL)isNetworkVolumeURL:(NSURL *)url {
    NSNumber *isLocal = nil;
    if ([url getResourceValue:&isLocal forKey:NSURLVolumeIsLocalKey error:nil] && isLocal != nil) {
        return !isLocal.boolValue;
    }

    return [url.path hasPrefix:@"/Volumes/"];
}

- (EagleArtwork *)artworkForURL:(NSURL *)fileURL isVideo:(BOOL)isVideo {
    NSURL *metadataURL = [fileURL.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"metadata.json"];
    NSData *data = [NSData dataWithContentsOfURL:metadataURL];
    NSDictionary *metadata = nil;

    if (data != nil) {
        metadata = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([metadata[@"isDeleted"] boolValue]) {
            return nil;
        }
    }

    CGSize size = CGSizeMake([metadata[@"width"] doubleValue], [metadata[@"height"] doubleValue]);
    if (size.width <= 0 || size.height <= 0) {
        size = isVideo ? CGSizeMake(16.0, 9.0) : [self imageSizeForURL:fileURL];
    }

    EagleArtwork *artwork = EagleArtwork.new;
    artwork.url = fileURL;
    artwork.title = [metadata[@"name"] isKindOfClass:NSString.class] ? metadata[@"name"] : fileURL.URLByDeletingPathExtension.lastPathComponent;
    artwork.width = MAX(1.0, size.width);
    artwork.height = MAX(1.0, size.height);
    artwork.isVideo = isVideo;
    artwork.videoURL = isVideo ? fileURL : nil;
    artwork.usesPreparedDisplayImage = NO;
    return artwork;
}

- (CGSize)imageSizeForURL:(NSURL *)url {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (source == NULL) {
        return CGSizeMake(1.0, 1.0);
    }

    NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
    CFRelease(source);

    CGFloat width = [properties[(NSString *)kCGImagePropertyPixelWidth] doubleValue];
    CGFloat height = [properties[(NSString *)kCGImagePropertyPixelHeight] doubleValue];
    return CGSizeMake(MAX(1.0, width), MAX(1.0, height));
}

- (CGSize)videoSizeForURL:(NSURL *)url {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    AVAssetTrack *track = [[asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
    if (track == nil) {
        return CGSizeMake(1.0, 1.0);
    }

    CGSize naturalSize = track.naturalSize;
    CGSize transformedSize = CGSizeApplyAffineTransform(naturalSize, track.preferredTransform);
    return CGSizeMake(MAX(1.0, fabs(transformedSize.width)), MAX(1.0, fabs(transformedSize.height)));
}

- (void)rebuildLayout {
    [self clearVideoLayers];
    self.lastLayoutSize = self.bounds.size;
    self.scrollOffset = 0.0;
    self.backgroundImageLayer.frame = self.bounds;
    [self.cells removeAllObjects];

    if (self.artworks.count == 0 || self.bounds.size.width < 100.0 || self.bounds.size.height < 100.0) {
        NSLog(@"EagleGridSaver: rebuild skipped artworks=%lu size=%@",
              (unsigned long)self.artworks.count,
              NSStringFromSize(self.bounds.size));
        return;
    }
    NSLog(@"EagleGridSaver: rebuilding layout artworks=%lu size=%@",
          (unsigned long)self.artworks.count,
          NSStringFromSize(self.bounds.size));
    [self prepareBackgroundLayer];

    NSInteger columns = 2;
    NSInteger count = MIN(MaxVisibleCells, self.artworks.count);
    CGFloat baseTileWidth = floor((self.bounds.size.width - HorizontalGap * (CGFloat)(columns - 1)) / (CGFloat)columns);

    NSMutableArray<EagleArtwork *> *initialArtworks = NSMutableArray.array;
    EagleArtwork *firstVideo = nil;
    for (EagleArtwork *artwork in self.artworks) {
        if (artwork.isVideo) {
            firstVideo = artwork;
            break;
        }
    }
    if (firstVideo != nil) {
        [initialArtworks addObject:firstVideo];
    }

    for (EagleArtwork *artwork in self.artworks) {
        if (!artwork.isVideo && ![initialArtworks containsObject:artwork]) {
            [initialArtworks addObject:artwork];
        }
        if (initialArtworks.count >= count) {
            break;
        }
    }
    if (initialArtworks.count < count) {
        for (EagleArtwork *artwork in self.artworks) {
            if (![initialArtworks containsObject:artwork]) {
                [initialArtworks addObject:artwork];
            }
            if (initialArtworks.count >= count) {
                break;
            }
        }
    }

    CGFloat nextY[2] = { self.bounds.size.height + VerticalBleed, self.bounds.size.height + VerticalBleed };
    for (NSInteger index = 0; index < count; index++) {
        NSInteger column = index % columns;
        EagleArtwork *artwork = initialArtworks[index];
        CGFloat tileWidth = [self widthForColumn:column columns:columns baseWidth:baseTileWidth];
        CGFloat tileHeight = [self heightForArtwork:artwork width:tileWidth];

        EagleCell *cell = EagleCell.new;
        cell.artwork = artwork;
        cell.column = column;
        cell.columnCount = columns;
        cell.frame = NSMakeRect(
            [self xForColumn:column columns:columns baseWidth:baseTileWidth],
            nextY[column] - tileHeight,
            tileWidth,
            tileHeight
        );
        cell.phase = 1.0;
        [self createContentLayerForCell:cell];
        [self.cells addObject:cell];
        [self prepareImageForCell:cell synchronously:(index < InitialSynchronousCells)];
        nextY[column] = NSMinY(cell.frame) - VerticalGap;
    }
}

- (void)prepareBackgroundLayer {
    if (self.backgroundImageLayer.contents != nil || self.artworks.count == 0) {
        return;
    }
    if (self.libraryIsNetworkVolume) {
        return;
    }

    EagleArtwork *backgroundArtwork = nil;
    for (EagleArtwork *artwork in self.artworks) {
        if (!artwork.isVideo) {
            backgroundArtwork = artwork;
            break;
        }
    }
    if (backgroundArtwork == nil) {
        backgroundArtwork = self.artworks.firstObject;
    }

    NSImage *image = [self decodedImageForArtwork:backgroundArtwork maxPixelSize:ImageDecodeMaxPixelSize];
    if (image == nil) {
        return;
    }
    CGImageRef imageRef = [image CGImageForProposedRect:NULL context:nil hints:nil];
    if (imageRef == NULL) {
        return;
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.backgroundImageLayer.contents = (__bridge id)imageRef;
    [CATransaction commit];
}

- (void)advanceWaterfallIfNeeded {
    if (self.artworks.count == 0 || self.cells.count == 0) {
        return;
    }

    NSMutableSet<NSURL *> *visibleURLs = NSMutableSet.set;
    for (EagleCell *cell in self.cells) {
        [visibleURLs addObject:cell.artwork.url];
    }

    for (EagleCell *cell in self.cells) {
        cell.frame = NSOffsetRect(cell.frame, 0.0, -[self effectiveScrollSpeed]);
        [self updateLayerFrameForCell:cell];
    }

    for (EagleCell *cell in self.cells) {
        if (NSMaxY(cell.frame) >= -VerticalGap) {
            continue;
        }

        NSInteger column = cell.column;
        CGFloat leadingY = [self leadingTopYForColumn:column excludingCell:cell];
        EagleArtwork *next = [self nextArtworkExcluding:visibleURLs];
        if (next == nil) {
            continue;
        }

        [visibleURLs removeObject:cell.artwork.url];
        [self teardownVideoForCell:cell];
        cell.phase = 1.0;
        CGFloat width = cell.frame.size.width;
        CGFloat height = [self heightForArtwork:next width:width];
        CGFloat x = [self xForColumn:column columns:cell.columnCount baseWidth:floor(self.bounds.size.width / (CGFloat)MAX(1, cell.columnCount))];
        cell.frame = NSMakeRect(x, leadingY + VerticalGap, width, height);
        cell.artwork = next;
        cell.image = nil;
        cell.videoPlaybackFailed = NO;
        cell.contentLayer.contents = nil;
        cell.contentLayer.hidden = YES;
        [self updateLayerFrameForCell:cell];
        [visibleURLs addObject:next.url];
        [self prepareImageForCell:cell];
    }
}

- (void)createContentLayerForCell:(EagleCell *)cell {
    CALayer *layer = CALayer.layer;
    layer.frame = [self layerFrameForViewRect:[self bledRectForCellFrame:cell.frame]];
    layer.backgroundColor = nil;
    layer.contentsGravity = kCAGravityResizeAspectFill;
    layer.masksToBounds = YES;
    layer.cornerRadius = TileCornerRadius;
    layer.drawsAsynchronously = YES;
    layer.contentsScale = NSScreen.mainScreen.backingScaleFactor;
    layer.hidden = YES;
    cell.contentLayer = layer;
    [self.contentLayerRoot addSublayer:layer];
}

- (void)resetContentLayerForCell:(EagleCell *)cell {
    if (cell.contentLayer == nil) {
        [self createContentLayerForCell:cell];
    }
    cell.contentLayer.hidden = NO;
    [self updateLayerFrameForCell:cell];
}

- (void)updateLayerFrameForCell:(EagleCell *)cell {
    if (cell.contentLayer == nil) {
        return;
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    cell.contentLayer.frame = [self layerFrameForViewRect:[self bledRectForCellFrame:cell.frame]];
    [CATransaction commit];
}

- (void)setLayerImage:(NSImage *)image forCell:(EagleCell *)cell {
    if (image == nil) {
        return;
    }
    if (cell.contentLayer == nil) {
        [self createContentLayerForCell:cell];
    }
    CGImageRef imageRef = [image CGImageForProposedRect:NULL context:nil hints:nil];
    if (imageRef == NULL) {
        return;
    }
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    cell.contentLayer.contents = (__bridge id)imageRef;
    cell.contentLayer.hidden = NO;
    [CATransaction commit];
}

- (BOOL)drawFallbackCell:(EagleCell *)cell {
    NSImage *image = cell.image;
    if (image == nil) {
        image = [self.imageCache objectForKey:cell.artwork.url];
    }
    if (image == nil) {
        return NO;
    }

    NSRect frame = [self bledRectForCellFrame:cell.frame];
    [image drawInRect:frame fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0 respectFlipped:YES hints:nil];
    return YES;
}

- (void)updateStatusLayerVisible:(BOOL)visible {
    NSString *message = self.statusMessage.length > 0 ? self.statusMessage : @"No Eagle library images found";
    if ([message hasPrefix:@"No images found"]) {
        message = [message stringByAppendingString:@"\n\nOpen Screen Saver Options and choose your Eagle .library folder there, so the system screen saver host gets permission to read it."];
    }

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.statusTextLayer.string = message;
    self.statusTextLayer.hidden = !visible;
    self.statusTextLayer.frame = NSInsetRect(self.bounds, 80.0, 0.0);
    [CATransaction commit];
}

- (NSInteger)columnForCell:(EagleCell *)cell {
    return cell.column;
}

- (CGFloat)widthForColumn:(NSInteger)column columns:(NSInteger)columns baseWidth:(CGFloat)baseWidth {
    if (column == columns - 1) {
        CGFloat usedBefore = (CGFloat)column * (baseWidth + HorizontalGap);
        return MAX(1.0, self.bounds.size.width - usedBefore);
    }
    return baseWidth;
}

- (CGFloat)xForColumn:(NSInteger)column columns:(NSInteger)columns baseWidth:(CGFloat)baseWidth {
    return (CGFloat)column * (baseWidth + HorizontalGap);
}

- (CGFloat)leadingTopYForColumn:(NSInteger)column excludingCell:(EagleCell *)excludedCell {
    CGFloat leadingY = self.bounds.size.height;
    BOOL found = NO;
    for (EagleCell *cell in self.cells) {
        if (cell == excludedCell || [self columnForCell:cell] != column) {
            continue;
        }
        leadingY = MAX(leadingY, NSMaxY(cell.frame));
        found = YES;
    }
    return found ? leadingY : self.bounds.size.height;
}

- (CGFloat)heightForArtwork:(EagleArtwork *)artwork width:(CGFloat)width {
    CGFloat ratio = artwork.height / MAX(1.0, artwork.width);
    return MAX(1.0, ceil(width * ratio));
}

- (EagleArtwork *)nextArtworkExcluding:(NSSet<NSURL *> *)visibleURLs {
    NSUInteger start = self.artworks.count > 0 ? arc4random_uniform((uint32_t)self.artworks.count) : 0;
    for (NSUInteger offset = 0; offset < self.artworks.count; offset++) {
        EagleArtwork *artwork = self.artworks[(start + offset) % self.artworks.count];
        if (![visibleURLs containsObject:artwork.url]) {
            return artwork;
        }
    }
    return self.artworks.count > 0 ? self.artworks[arc4random_uniform((uint32_t)self.artworks.count)] : nil;
}

- (NSImage *)imageForArtwork:(EagleArtwork *)artwork {
    NSImage *cached = [self.imageCache objectForKey:artwork.url];
    if (cached != nil) {
        return cached;
    }

    NSImage *image = [[NSImage alloc] initWithContentsOfURL:artwork.url];
    if (image == nil && artwork.isVideo) {
        image = [self posterImageForVideoURL:artwork.url];
    }
    if (image != nil) {
        [self.imageCache setObject:image forKey:artwork.url];
    }
    return image;
}

- (void)prepareImageForCell:(EagleCell *)cell {
    [self prepareImageForCell:cell synchronously:NO];
}

- (void)prepareImageForCell:(EagleCell *)cell synchronously:(BOOL)synchronously {
    if (cell == nil || cell.artwork == nil || cell.image != nil) {
        return;
    }

    NSImage *cached = [self.imageCache objectForKey:cell.artwork.url];
    if (cached != nil) {
        cell.image = cached;
        [self setLayerImage:cached forCell:cell];
        return;
    }

    if (synchronously) {
        NSImage *image = [self decodedImageForArtwork:cell.artwork maxPixelSize:ImageDecodeMaxPixelSize];
        if (image != nil) {
            cell.image = image;
            [self.imageCache setObject:image forKey:cell.artwork.url];
            [self setLayerImage:image forCell:cell];
        }
        return;
    }

    @synchronized (self.loadingURLs) {
        if ([self.loadingURLs containsObject:cell.artwork.url]) {
            return;
        }
        [self.loadingURLs addObject:cell.artwork.url];
    }

    EagleArtwork *artwork = cell.artwork;
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.imageQueue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }

        NSImage *image = [strongSelf decodedImageForArtwork:artwork maxPixelSize:ImageDecodeMaxPixelSize];

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) innerSelf = weakSelf;
            if (innerSelf == nil) {
                return;
            }

            @synchronized (innerSelf.loadingURLs) {
                [innerSelf.loadingURLs removeObject:artwork.url];
            }

            if (image == nil) {
                return;
            }

            [innerSelf.imageCache setObject:image forKey:artwork.url];
            for (EagleCell *candidate in innerSelf.cells) {
                if ([candidate.artwork.url isEqual:artwork.url]) {
                    candidate.image = image;
                    [innerSelf setLayerImage:image forCell:candidate];
                }
            }
        });
    });
}

- (NSImage *)decodedImageForArtwork:(EagleArtwork *)artwork maxPixelSize:(CGFloat)maxPixelSize {
    if (artwork.usesPreparedDisplayImage) {
        return [self decodedStillImageForURL:artwork.url maxPixelSize:maxPixelSize];
    }

    if (artwork.isVideo) {
        NSImage *poster = [self posterImageForVideoURL:artwork.url];
        return [self resizedImage:poster maxPixelSize:MIN(maxPixelSize, VideoPosterMaxPixelSize)];
    }

    if ([artwork.url.scheme isEqualToString:@"synthetic"]) {
        return [self syntheticImageForArtwork:artwork size:NSMakeSize(maxPixelSize, maxPixelSize * 9.0 / 16.0)];
    }

    return [self decodedStillImageForURL:artwork.url maxPixelSize:maxPixelSize];
}

- (NSImage *)decodedStillImageForURL:(NSURL *)url maxPixelSize:(CGFloat)maxPixelSize {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (source == NULL) {
        return nil;
    }

    NSDictionary *options = @{
        (NSString *)kCGImageSourceCreateThumbnailFromImageIfAbsent: @YES,
        (NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES,
        (NSString *)kCGImageSourceShouldCacheImmediately: @YES,
        (NSString *)kCGImageSourceThumbnailMaxPixelSize: @(maxPixelSize)
    };
    CGImageRef imageRef = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
    CFRelease(source);

    if (imageRef == NULL) {
        return nil;
    }

    NSImage *image = [[NSImage alloc] initWithCGImage:imageRef size:NSZeroSize];
    CGImageRelease(imageRef);
    return image;
}

- (NSImage *)syntheticImageForArtwork:(EagleArtwork *)artwork size:(NSSize)size {
    NSString *hex = artwork.title;
    unsigned int rgb = 0x6699cc;
    if ([hex hasPrefix:@"#"]) {
        [[NSScanner scannerWithString:[hex substringFromIndex:1]] scanHexInt:&rgb];
    }
    CGFloat red = ((rgb >> 16) & 0xff) / 255.0;
    CGFloat green = ((rgb >> 8) & 0xff) / 255.0;
    CGFloat blue = (rgb & 0xff) / 255.0;
    NSImage *image = [[NSImage alloc] initWithSize:size];
    [image lockFocus];
    [[NSColor colorWithCalibratedRed:red green:green blue:blue alpha:1.0] setFill];
    NSRectFill(NSMakeRect(0, 0, size.width, size.height));
    [image unlockFocus];
    return image;
}

- (NSImage *)resizedImage:(NSImage *)image maxPixelSize:(CGFloat)maxPixelSize {
    if (image == nil || (image.size.width <= maxPixelSize && image.size.height <= maxPixelSize)) {
        return image;
    }

    CGFloat scale = MIN(maxPixelSize / image.size.width, maxPixelSize / image.size.height);
    NSSize newSize = NSMakeSize(floor(image.size.width * scale), floor(image.size.height * scale));
    NSImage *resized = [[NSImage alloc] initWithSize:newSize];
    [resized lockFocus];
    [image drawInRect:NSMakeRect(0, 0, newSize.width, newSize.height) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0];
    [resized unlockFocus];
    return resized;
}

- (NSImage *)posterImageForVideoURL:(NSURL *)url {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    AVAssetImageGenerator *generator = [AVAssetImageGenerator assetImageGeneratorWithAsset:asset];
    generator.appliesPreferredTrackTransform = YES;
    generator.maximumSize = CGSizeMake(VideoPosterMaxPixelSize, VideoPosterMaxPixelSize);

    NSError *error = nil;
    CGImageRef imageRef = [generator copyCGImageAtTime:CMTimeMakeWithSeconds(1.0, 600) actualTime:NULL error:&error];
    if (imageRef == nil) {
        imageRef = [generator copyCGImageAtTime:kCMTimeZero actualTime:NULL error:&error];
    }
    if (imageRef == nil) {
        NSLog(@"EagleGridSaver: failed to create video poster %@: %@", url.path, error.localizedDescription);
        return nil;
    }

    NSImage *image = [[NSImage alloc] initWithCGImage:imageRef size:NSZeroSize];
    CGImageRelease(imageRef);
    return image;
}

- (void)ensureVideoForCell:(EagleCell *)cell {
    if (cell.artwork.videoURL == nil || cell.videoPlaybackFailed || cell.image == nil) {
        [self teardownVideoForCell:cell];
        return;
    }
    if (cell.playerLayer != nil) {
        return;
    }

    NSDictionary *assetOptions = @{ AVURLAssetPreferPreciseDurationAndTimingKey: @NO };
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:cell.artwork.videoURL options:assetOptions];
    AVPlayerItem *item = [AVPlayerItem playerItemWithAsset:asset];
    item.preferredForwardBufferDuration = self.libraryIsNetworkVolume ? 4.0 : 1.0;

    NSDictionary *pixelBufferAttributes = @{
        (NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)
    };
    AVPlayerItemVideoOutput *videoOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:pixelBufferAttributes];
    [item addOutput:videoOutput];

    AVPlayer *player = [AVPlayer playerWithPlayerItem:item];
    player.actionAtItemEnd = AVPlayerActionAtItemEndNone;
    player.muted = YES;
    player.volume = 0.0;
    player.automaticallyWaitsToMinimizeStalling = self.libraryIsNetworkVolume;

    id endObserver = [[NSNotificationCenter defaultCenter] addObserverForName:AVPlayerItemDidPlayToEndTimeNotification object:item queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification * _Nonnull note) {
        [player seekToTime:kCMTimeZero];
        [player play];
    }];

    cell.player = player;
    cell.videoOutput = videoOutput;
    cell.videoEndObserver = endObserver;
    cell.videoStartTime = CACurrentMediaTime();
    cell.videoLayerReady = NO;
    AVPlayerLayer *playerLayer = [AVPlayerLayer playerLayerWithPlayer:player];
    playerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    playerLayer.masksToBounds = YES;
    playerLayer.frame = cell.contentLayer.bounds;
    playerLayer.hidden = YES;
    cell.playerLayer = playerLayer;
    [cell.contentLayer addSublayer:playerLayer];

    __weak EagleCell *weakCell = cell;
    [item addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:(__bridge void *)weakCell];
    [player play];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if (![keyPath isEqualToString:@"status"] || ![object isKindOfClass:AVPlayerItem.class]) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }

    AVPlayerItem *item = (AVPlayerItem *)object;
    for (EagleCell *cell in self.cells) {
        if (cell.player.currentItem != item) {
            continue;
        }
        if (item.status == AVPlayerItemStatusReadyToPlay) {
            [cell.player play];
        } else if (item.status == AVPlayerItemStatusFailed) {
            NSLog(@"EagleGridSaver: video failed %@: %@", cell.artwork.videoURL.path, item.error.localizedDescription);
            cell.videoPlaybackFailed = YES;
            [self teardownVideoForCell:cell];
        }
        return;
    }
}

- (void)teardownVideoForCell:(EagleCell *)cell {
    if (cell.player != nil) {
        @try {
            [cell.player.currentItem removeObserver:self forKeyPath:@"status"];
        } @catch (__unused NSException *exception) {
        }
        [cell.player pause];
        cell.player = nil;
    }
    if (cell.videoEndObserver != nil) {
        [[NSNotificationCenter defaultCenter] removeObserver:cell.videoEndObserver];
        cell.videoEndObserver = nil;
    }
    if (cell.playerLayer != nil) {
        [cell.playerLayer removeFromSuperlayer];
        cell.playerLayer = nil;
    }
    cell.videoOutput = nil;
    cell.videoStartTime = 0.0;
    cell.videoLayerReady = NO;
}

- (void)clearVideoLayers {
    for (EagleCell *cell in self.cells) {
        [self teardownVideoForCell:cell];
        [cell.contentLayer removeFromSuperlayer];
        cell.contentLayer = nil;
    }
    [self.contentLayerRoot.sublayers makeObjectsPerformSelector:@selector(removeFromSuperlayer)];
}

- (void)updateVideoLayers {
    EagleCell *activeVideoCell = nil;
    for (EagleCell *cell in self.cells) {
        if (!cell.artwork.isVideo) {
            [self teardownVideoForCell:cell];
            continue;
        }
        if (activeVideoCell == nil && NSIntersectsRect(cell.frame, self.bounds)) {
            activeVideoCell = cell;
        }
    }

    for (EagleCell *cell in self.cells) {
        if (!cell.artwork.isVideo) {
            continue;
        }
        if (cell == activeVideoCell) {
            [self ensureVideoForCell:cell];
            if (cell.playerLayer != nil) {
                cell.playerLayer.frame = cell.contentLayer.bounds;
                if ([self videoHasRenderableFrameForCell:cell]) {
                    cell.videoLayerReady = YES;
                    cell.playerLayer.hidden = NO;
                } else if (!cell.videoLayerReady) {
                    cell.playerLayer.hidden = YES;
                    if (cell.videoStartTime > 0.0 && CACurrentMediaTime() - cell.videoStartTime > VideoStartupTimeout) {
                        NSLog(@"EagleGridSaver: video startup timed out, keeping poster %@", cell.artwork.videoURL.path);
                        cell.videoPlaybackFailed = YES;
                        [self teardownVideoForCell:cell];
                    }
                }
            }
            if (cell.player != nil && cell.player.rate == 0.0) {
                [cell.player play];
            }
        } else {
            [self teardownVideoForCell:cell];
        }
    }
}

- (BOOL)videoHasRenderableFrameForCell:(EagleCell *)cell {
    if (cell.videoOutput == nil || cell.player == nil) {
        return NO;
    }

    CMTime itemTime = [cell.videoOutput itemTimeForHostTime:CACurrentMediaTime()];
    if (![cell.videoOutput hasNewPixelBufferForItemTime:itemTime]) {
        return cell.videoLayerReady;
    }

    CVPixelBufferRef pixelBuffer = [cell.videoOutput copyPixelBufferForItemTime:itemTime itemTimeForDisplay:NULL];
    if (pixelBuffer == NULL) {
        return cell.videoLayerReady;
    }

    CGFloat brightness = [self averageBrightnessForPixelBuffer:pixelBuffer];
    CVPixelBufferRelease(pixelBuffer);
    return brightness >= 0.025;
}

- (CGFloat)averageBrightnessForPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    if (CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly) != kCVReturnSuccess) {
        return 0.0;
    }

    const size_t width = CVPixelBufferGetWidth(pixelBuffer);
    const size_t height = CVPixelBufferGetHeight(pixelBuffer);
    const size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
    const uint8_t *base = CVPixelBufferGetBaseAddress(pixelBuffer);
    if (width == 0 || height == 0 || base == NULL) {
        CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
        return 0.0;
    }

    const size_t samplesX = MIN((size_t)12, width);
    const size_t samplesY = MIN((size_t)12, height);
    double total = 0.0;
    size_t count = 0;
    for (size_t y = 0; y < samplesY; y++) {
        size_t sampleY = (height * y + height / 2) / samplesY;
        const uint8_t *row = base + sampleY * bytesPerRow;
        for (size_t x = 0; x < samplesX; x++) {
            size_t sampleX = (width * x + width / 2) / samplesX;
            const uint8_t *pixel = row + sampleX * 4;
            total += (0.0722 * pixel[0] + 0.7152 * pixel[1] + 0.2126 * pixel[2]) / 255.0;
            count += 1;
        }
    }

    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    return count > 0 ? (CGFloat)(total / (double)count) : 0.0;
}

- (CGRect)layerFrameForViewRect:(NSRect)viewRect {
    return CGRectMake(viewRect.origin.x, viewRect.origin.y, viewRect.size.width, viewRect.size.height);
}

- (NSRect)bledRectForCellFrame:(NSRect)frame {
    return NSInsetRect(frame, -HorizontalBleed, -VerticalBleed);
}

- (NSRect)fittedImageRectForImageSize:(NSSize)imageSize inFrame:(NSRect)frame {
    if (imageSize.width <= 0.0 || imageSize.height <= 0.0) {
        return frame;
    }

    CGFloat imageRatio = imageSize.width / imageSize.height;
    CGFloat frameRatio = frame.size.width / frame.size.height;

    if (imageRatio > frameRatio) {
        CGFloat width = frame.size.height * imageRatio;
        return NSMakeRect(NSMidX(frame) - width / 2.0, NSMinY(frame), width, frame.size.height);
    }

    CGFloat height = frame.size.width / imageRatio;
    return NSMakeRect(NSMinX(frame), NSMidY(frame) - height / 2.0, frame.size.width, height);
}

- (void)drawEmptyState {
    NSString *message = self.statusMessage.length > 0 ? self.statusMessage : @"No Eagle library images found";
    NSDictionary<NSAttributedStringKey, id> *attributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:24.0 weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:1.0 alpha:0.7]
    };
    NSSize size = [message sizeWithAttributes:attributes];
    [message drawAtPoint:NSMakePoint(NSMidX(self.bounds) - size.width / 2.0, NSMidY(self.bounds) - size.height / 2.0) withAttributes:attributes];
}

- (void)shuffleArray:(NSMutableArray *)array {
    if (array.count < 2) {
        return;
    }

    for (NSUInteger i = array.count - 1; i > 0; i--) {
        NSUInteger j = arc4random_uniform((uint32_t)(i + 1));
        [array exchangeObjectAtIndex:i withObjectAtIndex:j];
    }
}

@end
