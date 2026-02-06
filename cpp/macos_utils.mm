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

        // Sidebar: left edge, full height
        NSVisualEffectView *sidebar = [[NSVisualEffectView alloc]
            initWithFrame:NSMakeRect(0, 0, sidebarWidth, contentView.bounds.size.height)];
        sidebar.material = NSVisualEffectMaterialSidebar;
        sidebar.blendingMode = NSVisualEffectBlendingModeBehindWindow;
        sidebar.state = NSVisualEffectStateActive;
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

        // Toolbar: top-right area (NSView y=0 is bottom, so top = height - toolbarHeight)
        CGFloat cvWidth = contentView.bounds.size.width;
        CGFloat cvHeight = contentView.bounds.size.height;

        NSVisualEffectView *toolbar = [[NSVisualEffectView alloc]
            initWithFrame:NSMakeRect(sidebarWidth, cvHeight - toolbarHeight,
                                     cvWidth - sidebarWidth, toolbarHeight)];
        toolbar.material = NSVisualEffectMaterialHeaderView;
        toolbar.blendingMode = NSVisualEffectBlendingModeBehindWindow;
        toolbar.state = NSVisualEffectStateActive;
        toolbar.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;

        [themeFrame addSubview:toolbar positioned:NSWindowBelow relativeTo:contentView];
        [g_vibrancyViews addObject:toolbar];

        std::cout << "[CPP] Toolbar vibrancy installed (height=" << toolbarHeight << ")" << std::endl;
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

} // namespace cuirq
