#ifndef MACOS_UTILS_H
#define MACOS_UTILS_H

namespace cuirq {
void setMacOSAppName(const char* name);
void setupSidebarVibrancy(void* nativeWindowHandle, int sidebarWidth);
void setSidebarVibrancyAppearance(const char* mode);
}

#endif // MACOS_UTILS_H
