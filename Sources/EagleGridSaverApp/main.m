#import <Cocoa/Cocoa.h>
#import <ScreenSaver/ScreenSaver.h>
#import "../EagleGridSaverObjC/EagleGridSaverView.h"

static NSString * const EagleDefaultsDomain = @"com.chaopi.EagleGridSaver";
static NSString * const EagleLibraryPathKey = @"EagleGridSaver.libraryPath";
static NSString * const EagleLibraryBookmarkKey = @"EagleGridSaver.libraryBookmark";

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) NSWindow *previewWindow;
@property(nonatomic, strong) EagleGridSaverView *previewView;
@property(nonatomic, strong) NSTextField *pathLabel;
@property(nonatomic, strong) NSTextField *statusLabel;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
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
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 560, 300)
                                             styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable)
                                               backing:NSBackingStoreBuffered
                                                 defer:NO];
    self.window.title = @"Eagle Grid Saver";
    self.window.releasedWhenClosed = NO;

    NSView *content = self.window.contentView;

    NSTextField *title = [self labelWithString:@"Eagle Grid Saver" font:[NSFont systemFontOfSize:26 weight:NSFontWeightSemibold] color:NSColor.labelColor];
    title.frame = NSMakeRect(32, 236, 496, 36);
    [content addSubview:title];

    NSTextField *description = [self labelWithString:@"Choose an Eagle .library folder. The screen saver reads media in place and does not copy your images or videos into the app." font:[NSFont systemFontOfSize:14 weight:NSFontWeightRegular] color:NSColor.secondaryLabelColor];
    description.frame = NSMakeRect(32, 184, 496, 44);
    description.maximumNumberOfLines = 2;
    [content addSubview:description];

    self.pathLabel = [self labelWithString:@"" font:[NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular] color:NSColor.labelColor];
    self.pathLabel.frame = NSMakeRect(32, 128, 496, 38);
    self.pathLabel.maximumNumberOfLines = 2;
    self.pathLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    [content addSubview:self.pathLabel];

    NSButton *chooseButton = [NSButton buttonWithTitle:@"Choose Eagle Library..." target:self action:@selector(chooseLibrary:)];
    chooseButton.frame = NSMakeRect(32, 78, 172, 34);
    chooseButton.bezelStyle = NSBezelStyleRounded;
    [content addSubview:chooseButton];

    NSButton *previewButton = [NSButton buttonWithTitle:@"Preview" target:self action:@selector(openPreview:)];
    previewButton.frame = NSMakeRect(216, 78, 92, 34);
    previewButton.bezelStyle = NSBezelStyleRounded;
    [content addSubview:previewButton];

    NSButton *startButton = [NSButton buttonWithTitle:@"Start Screen Saver" target:self action:@selector(startScreenSaver:)];
    startButton.frame = NSMakeRect(320, 78, 150, 34);
    startButton.bezelStyle = NSBezelStyleRounded;
    [content addSubview:startButton];

    NSButton *openSettingsButton = [NSButton buttonWithTitle:@"Settings" target:self action:@selector(openScreenSaverSettings:)];
    openSettingsButton.frame = NSMakeRect(480, 78, 72, 34);
    openSettingsButton.bezelStyle = NSBezelStyleRounded;
    [content addSubview:openSettingsButton];

    self.statusLabel = [self labelWithString:@"" font:[NSFont systemFontOfSize:12 weight:NSFontWeightRegular] color:NSColor.secondaryLabelColor];
    self.statusLabel.frame = NSMakeRect(32, 34, 496, 24);
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

    self.statusLabel.stringValue = @"Saved. Reopen the screen saver preview if it is already running.";
    [self refreshPathLabel];
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
    NSString *path = [NSUserDefaults.standardUserDefaults stringForKey:EagleLibraryPathKey];
    if (path.length == 0) {
        ScreenSaverDefaults *screenSaverDefaults = [ScreenSaverDefaults defaultsForModuleWithName:EagleDefaultsDomain];
        path = [screenSaverDefaults stringForKey:EagleLibraryPathKey];
    }

    if (path.length > 0) {
        self.pathLabel.stringValue = path;
        self.statusLabel.stringValue = @"The screen saver will read original media directly from this library.";
    } else {
        self.pathLabel.stringValue = @"No Eagle library selected";
        self.statusLabel.stringValue = @"The screen saver can still auto-detect .library folders on Desktop, Documents, and Downloads.";
    }
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
