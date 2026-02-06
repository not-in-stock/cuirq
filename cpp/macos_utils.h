#ifndef MACOS_UTILS_H
#define MACOS_UTILS_H

namespace cuirq {
void setMacOSAppName(const char* name);
void setupSidebarVibrancy(void* nativeWindowHandle, int sidebarWidth);
void setupToolbarVibrancy(void* nativeWindowHandle, int sidebarWidth, int toolbarHeight);
void setVibrancyAppearance(const char* mode);
int hideTitlebar(void* nativeWindowHandle);
int getTitlebarHeight(void* nativeWindowHandle);
}

#endif // MACOS_UTILS_H
