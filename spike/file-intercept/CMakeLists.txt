cmake_minimum_required(VERSION 3.20)
project(file-intercept-spike LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2)
find_package(Qt6CorePrivate REQUIRED)

qt_add_executable(file-intercept-spike main.cpp)

target_link_libraries(file-intercept-spike PRIVATE
    Qt6::Core
    Qt6::CorePrivate
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
)
