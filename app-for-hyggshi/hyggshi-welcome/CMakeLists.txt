cmake_minimum_required(VERSION 3.16)
project(hyggshi-welcome LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

# Ưu tiên Qt6, fallback Qt5 để build được trên các base distro chưa có Qt6
# (Alpine/Arch có thể lệch phiên bản tuỳ thời điểm build).
find_package(Qt6 QUIET COMPONENTS Widgets)
if(Qt6_FOUND)
  set(QT_VERSION_MAJOR 6)
  set(QT_LIBS Qt6::Widgets)
else()
  find_package(Qt5 REQUIRED COMPONENTS Widgets)
  set(QT_VERSION_MAJOR 5)
  set(QT_LIBS Qt5::Widgets)
endif()

file(GLOB APP_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/src/*.cpp")
file(GLOB APP_HEADERS "${CMAKE_CURRENT_SOURCE_DIR}/src/*.h")

add_executable(hyggshi-welcome ${APP_SOURCES} ${APP_HEADERS} resources/hyggshi-welcome.qrc)

target_link_libraries(hyggshi-welcome PRIVATE ${QT_LIBS})
target_include_directories(hyggshi-welcome PRIVATE src)

install(TARGETS hyggshi-welcome RUNTIME DESTINATION bin)
install(FILES packaging/hyggshi-welcome.desktop DESTINATION share/applications)
install(FILES packaging/hyggshi-welcome-autostart.desktop
        DESTINATION /etc/xdg/autostart
        RENAME hyggshi-welcome.desktop)

# Wallpaper thật cho 2 theme Sáng/Tối — cài vào cùng thư mục
# /usr/share/backgrounds/hyggshi mà branding.sh dùng, để finishSetup() trong
# MainWindow.cpp trỏ tới đường dẫn cố định này lúc runtime (không cần đọc
# lại từ resource .qrc, vì xfconf-query cần path thật trên đĩa).
install(FILES resources/icons/theme-light.png
        DESTINATION /usr/share/backgrounds/hyggshi
        RENAME car-light.png)
install(FILES resources/icons/theme-dark.png
        DESTINATION /usr/share/backgrounds/hyggshi
        RENAME car-Dark.png)
