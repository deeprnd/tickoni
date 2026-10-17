cmake_minimum_required(VERSION 3.16)
project(tickoni-terminal LANGUAGES CXX)

# Find Qt6 installation; default to ~/Qt/6.11.2/gcc_64 if not overridden
set(_qt_default_prefix "$ENV{HOME}/Qt/6.11.2/gcc_64")
if(NOT DEFINED CMAKE_PREFIX_PATH OR CMAKE_PREFIX_PATH STREQUAL "")
    set(CMAKE_PREFIX_PATH "${_qt_default_prefix}")
endif()
unset(_qt_default_prefix)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Quick)

qt_standard_project_setup()

qt_add_executable(tickoni-terminal
    app/main.cpp
)

qt_add_qml_module(tickoni-terminal
    URI Tickoni
    VERSION 1.0
    QML_FILES
        qml/Tickoni/Main.qml
)

target_link_libraries(tickoni-terminal PRIVATE Qt6::Quick)

install(TARGETS tickoni-terminal RUNTIME DESTINATION bin)
