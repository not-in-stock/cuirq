cmake_minimum_required(VERSION 3.16)
if(APPLE)
    project(cuirq LANGUAGES CXX OBJCXX)
else()
    project(cuirq LANGUAGES CXX)
endif()

# Use C++20
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Compiler warnings
add_compile_options(
    -Wall
    -Wextra
    -Wpedantic
    -Werror=return-type
)

# Enable automatic Qt MOC (Meta-Object Compiler)
set(CMAKE_AUTOMOC ON)

# Find Qt6 components
find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 Svg)

# Build shared library (.dylib on macOS, .so on Linux)
set(CUIRQ_SOURCES
    cpp/qt_engine.cpp
    cpp/jvmlistmodel.cpp
    cpp/qmlwatcher.cpp
    cpp/stateobject.cpp
    cpp/panama_api.cpp
)
if(APPLE)
    list(APPEND CUIRQ_SOURCES cpp/macos_utils.mm cpp/fs_watcher_macos.mm)
else()
    list(APPEND CUIRQ_SOURCES cpp/fs_watcher_linux.cpp)
endif()

add_library(qmlbridge SHARED ${CUIRQ_SOURCES})

# Include directories
target_include_directories(qmlbridge PRIVATE
    cpp
)

# Link Qt libraries
target_link_libraries(qmlbridge PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Svg
)

if(APPLE)
    target_link_libraries(qmlbridge PRIVATE "-framework Cocoa" "-framework CoreServices")
endif()

# Output library to predictable location
set_target_properties(qmlbridge PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib
)

# Print build info
message(STATUS "=== cuirq Bridge Build Configuration ===")
message(STATUS "CMake version: ${CMAKE_VERSION}")
message(STATUS "C++ standard: C++${CMAKE_CXX_STANDARD}")
message(STATUS "Qt6 version: ${Qt6_VERSION}")
message(STATUS "Library output: ${CMAKE_BINARY_DIR}/lib")
message(STATUS "========================================")
