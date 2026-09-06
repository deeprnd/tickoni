cmake_minimum_required(VERSION 3.16)
project(tickoni-terminal LANGUAGES CXX)

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
