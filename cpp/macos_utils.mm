#include "macos_utils.h"
#import <Cocoa/Cocoa.h>
#include <iostream>

// Stored reference so we can update appearance later
static NSVisualEffectView* g_sidebarVibrancy = nil;

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

        // Qt renders directly into contentView's layer.
        // Any subview of contentView sits ON TOP of Qt's render.
        // To place vibrancy BEHIND Qt, insert it as a sibling of contentView
        // (into contentView's superview, i.e. NSThemeFrame), positioned below.
        NSView *contentView = [window contentView];
        NSView *themeFrame = [contentView superview];
        if (!themeFrame) {
            std::cerr << "[CPP] setupSidebarVibrancy: no superview for contentView" << std::endl;
            return;
        }

        NSVisualEffectView *vibrancy = [[NSVisualEffectView alloc]
            initWithFrame:NSMakeRect(0, 0, sidebarWidth, contentView.bounds.size.height)];
        vibrancy.material = NSVisualEffectMaterialSidebar;
        vibrancy.blendingMode = NSVisualEffectBlendingModeBehindWindow;
        vibrancy.state = NSVisualEffectStateActive;
        vibrancy.autoresizingMask = NSViewHeightSizable;

        [themeFrame addSubview:vibrancy positioned:NSWindowBelow relativeTo:contentView];

        g_sidebarVibrancy = vibrancy;

        std::cout << "[CPP] Sidebar vibrancy installed (width=" << sidebarWidth << ")" << std::endl;
    }
}

void setSidebarVibrancyAppearance(const char* mode) {
    if (!g_sidebarVibrancy) return;

    @autoreleasepool {
        NSString *modeStr = [NSString stringWithUTF8String:mode];
        NSAppearance *appearance = nil;

        if ([modeStr isEqualToString:@"light"]) {
            appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
        } else if ([modeStr isEqualToString:@"dark"]) {
            appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
        }
        // "system" → nil → follows system appearance

        g_sidebarVibrancy.appearance = appearance;
        std::cout << "[CPP] Sidebar vibrancy appearance: " << mode << std::endl;
    }
}

} // namespace cuirq
