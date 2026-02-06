#include "macos_utils.h"
#import <Cocoa/Cocoa.h>

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

} // namespace cuirq
