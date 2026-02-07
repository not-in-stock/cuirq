#include "macos_utils.h"
#import <Cocoa/Cocoa.h>
#include <iostream>

// All vibrancy views — appearance updates apply to all of them
static NSMutableArray<NSVisualEffectView*> *g_vibrancyViews = nil;

namespace cuirq {

void setMacOSAppName(const char* name) {
    @autoreleasepool {
        NSString *appName = [NSString stringWithUTF8String:name];
        NSMenu *mainMenu = [[NSApplication sharedApplication] mainMenu];
        if (mainMenu && [mainMenu numberOfItems] > 0) {
            NSMenuItem *appMenuItem = [mainMenu itemAtIndex:0];
            [appMenuItem.submenu setTitle:appName];
        }
    }
}

int hideTitlebar(void* nativeWindowHandle) {
    @autoreleasepool {
        NSView *qtView = (__bridge NSView *)nativeWindowHandle;
        NSWindow *window = [qtView window];
        if (!window) {
            std::cerr << "[CPP] hideTitlebar: no NSWindow found" << std::endl;
            return 0;
        }

        window.styleMask |= NSWindowStyleMaskFullSizeContentView;
        window.titlebarSeparatorStyle = NSTitlebarSeparatorStyleNone;
        window.titlebarAppearsTransparent = YES;
        window.titleVisibility = NSWindowTitleHidden;

        int tbHeight = getTitlebarHeight(nativeWindowHandle);
        std::cout << "[CPP] Titlebar hidden (height=" << tbHeight << ")" << std::endl;
        return tbHeight;
    }
}

void setupSidebarVibrancy(void* nativeWindowHandle, int sidebarWidth) {
    @autoreleasepool {
        NSView *qtView = (__bridge NSView *)nativeWindowHandle;
        NSWindow *window = [qtView window];
        if (!window) {
            std::cerr << "[CPP] setupSidebarVibrancy: no NSWindow found" << std::endl;
            return;
        }

        NSView *contentView = [window contentView];
        NSView *themeFrame = [contentView superview];
        if (!themeFrame) {
            std::cerr << "[CPP] setupSidebarVibrancy: no superview for contentView" << std::endl;
            return;
        }

        if (!g_vibrancyViews) g_vibrancyViews = [NSMutableArray new];

        // Sidebar: left edge, full window height (including titlebar)
        // Use themeFrame bounds so vibrancy extends behind the titlebar (like Finder)
        NSVisualEffectView *sidebar = [[NSVisualEffectView alloc]
            initWithFrame:NSMakeRect(0, 0, sidebarWidth, themeFrame.bounds.size.height)];
        sidebar.material = NSVisualEffectMaterialSidebar;
        sidebar.blendingMode = NSVisualEffectBlendingModeBehindWindow;
        sidebar.state = NSVisualEffectStateFollowsWindowActiveState;
        sidebar.autoresizingMask = NSViewHeightSizable;

        [themeFrame addSubview:sidebar positioned:NSWindowBelow relativeTo:contentView];
        [g_vibrancyViews addObject:sidebar];

        std::cout << "[CPP] Sidebar vibrancy installed (width=" << sidebarWidth << ")" << std::endl;
    }
}

void setupToolbarVibrancy(void* nativeWindowHandle, int sidebarWidth, int toolbarHeight) {
    @autoreleasepool {
        NSView *qtView = (__bridge NSView *)nativeWindowHandle;
        NSWindow *window = [qtView window];
        if (!window) return;

        NSView *contentView = [window contentView];
        NSView *themeFrame = [contentView superview];
        if (!themeFrame) return;

        if (!g_vibrancyViews) g_vibrancyViews = [NSMutableArray new];

        // Titlebar height = difference between themeFrame and content layout rect
        CGFloat titlebarHeight = themeFrame.bounds.size.height - window.contentLayoutRect.size.height;
        CGFloat totalHeight = titlebarHeight + toolbarHeight;

        CGFloat tfWidth = themeFrame.bounds.size.width;
        CGFloat tfHeight = themeFrame.bounds.size.height;

        // Toolbar vibrancy: covers titlebar + toolbar area on the right side
        NSVisualEffectView *toolbar = [[NSVisualEffectView alloc]
            initWithFrame:NSMakeRect(sidebarWidth, tfHeight - totalHeight,
                                     tfWidth - sidebarWidth, totalHeight)];
        toolbar.material = NSVisualEffectMaterialHeaderView;
        toolbar.blendingMode = NSVisualEffectBlendingModeBehindWindow;
        toolbar.state = NSVisualEffectStateFollowsWindowActiveState;
        toolbar.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;

        [themeFrame addSubview:toolbar positioned:NSWindowBelow relativeTo:contentView];
        [g_vibrancyViews addObject:toolbar];

        std::cout << "[CPP] Toolbar vibrancy installed (titlebar=" << titlebarHeight
                  << " toolbar=" << toolbarHeight << ")" << std::endl;
    }
}

void setVibrancyAppearance(const char* mode) {
    if (!g_vibrancyViews || g_vibrancyViews.count == 0) return;

    @autoreleasepool {
        NSString *modeStr = [NSString stringWithUTF8String:mode];
        NSAppearance *appearance = nil;

        if ([modeStr isEqualToString:@"light"]) {
            appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
        } else if ([modeStr isEqualToString:@"dark"]) {
            appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        }

        for (NSVisualEffectView *v in g_vibrancyViews) {
            v.appearance = appearance;
        }
        std::cout << "[CPP] Vibrancy appearance: " << mode << std::endl;
    }
}

void setVibrancyAlwaysActive(bool always) {
    if (!g_vibrancyViews || g_vibrancyViews.count == 0) return;

    NSVisualEffectState state = always
        ? NSVisualEffectStateActive
        : NSVisualEffectStateFollowsWindowActiveState;

    for (NSVisualEffectView *v in g_vibrancyViews) {
        v.state = state;
    }
}

int getTitlebarHeight(void* nativeWindowHandle) {
    @autoreleasepool {
        NSView *qtView = (__bridge NSView *)nativeWindowHandle;
        NSWindow *window = [qtView window];
        if (!window) return 0;
        NSView *themeFrame = [[window contentView] superview];
        if (!themeFrame) return 0;
        return (int)(themeFrame.bounds.size.height - window.contentLayoutRect.size.height);
    }
}

} // namespace cuirq
