cmake_minimum_required(VERSION 3.16)
project(cuirq LANGUAGES CXX)

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
find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Quick)

# Find JNI (Java Native Interface)
find_package(JNI REQUIRED)

# Build shared library (.dylib on macOS, .so on Linux)
add_library(qmlbridge SHARED
    cpp/qmlbridge.cpp
    cpp/signalforwarder.cpp
    cpp/jvmlistmodel.cpp
    cpp/qmlwatcher.cpp
    cpp/stateobject.cpp
)

# Include directories for JNI headers
target_include_directories(qmlbridge PRIVATE
    ${JNI_INCLUDE_DIRS}
    cpp
)

# Link Qt and JNI libraries
target_link_libraries(qmlbridge PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
)

# Output library to predictable location
set_target_properties(qmlbridge PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib
)

# Print build info
message(STATUS "=== cuirq Bridge Build Configuration ===")
message(STATUS "CMake version: ${CMAKE_VERSION}")
message(STATUS "C++ standard: C++${CMAKE_CXX_STANDARD}")
message(STATUS "Qt6 version: ${Qt6_VERSION}")
message(STATUS "JNI include dirs: ${JNI_INCLUDE_DIRS}")
message(STATUS "Library output: ${CMAKE_BINARY_DIR}/lib")
message(STATUS "========================================")

