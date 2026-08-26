cmake_minimum_required(VERSION 3.16)

project(hyggshi-welcome VERSION 1.2.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

include(GNUInstallDirs)

# Prefer Qt6, but keep Qt5 compatibility for older Hyggshi OS base images.
find_package(Qt6 QUIET COMPONENTS Widgets)
if(Qt6_FOUND)
  set(QT_LIBS Qt6::Widgets)
else()
  find_package(Qt5 REQUIRED COMPONENTS Widgets)
  set(QT_LIBS Qt5::Widgets)
endif()

file(GLOB APP_SOURCES CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/src/*.cpp")
file(GLOB APP_HEADERS CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/src/*.h")

add_executable(hyggshi-welcome
  ${APP_SOURCES}
  ${APP_HEADERS}
  resources/hyggshi-welcome.qrc
)

target_link_libraries(hyggshi-welcome PRIVATE ${QT_LIBS})
target_include_directories(hyggshi-welcome PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/src")

target_compile_options(hyggshi-welcome PRIVATE
  $<$<COMPILE_LANG_AND_ID:CXX,GNU,Clang>:-Wall>
  $<$<COMPILE_LANG_AND_ID:CXX,GNU,Clang>:-Wextra>
  $<$<COMPILE_LANG_AND_ID:CXX,GNU,Clang>:-Wpedantic>
)

install(TARGETS hyggshi-welcome
  RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}"
)

install(FILES packaging/hyggshi-welcome.desktop
  DESTINATION "${CMAKE_INSTALL_DATADIR}/applications"
)

install(FILES packaging/hyggshi-welcome-autostart.desktop
  DESTINATION "${CMAKE_INSTALL_SYSCONFDIR}/xdg/autostart"
  RENAME hyggshi-welcome.desktop
)

# Desktop icon: the .desktop entry refers to this name.
# Install the Hyggshi Welcome icon in several standard hicolor sizes so
# Cinnamon/other desktops do not fall back to a generic application icon
# after the installed system rebuilds its icon cache.
foreach(ICON_SIZE 48 64 128 192 256)
  install(FILES resources/icons/logo.png
    DESTINATION "${CMAKE_INSTALL_DATADIR}/icons/hicolor/${ICON_SIZE}x${ICON_SIZE}/apps"
    RENAME hyggshi-welcome.png
  )
endforeach()

# Wallpapers used by the welcome wizard / theme helpers.
install(FILES resources/icons/theme-light.png
  DESTINATION /usr/share/backgrounds/hyggshi
  RENAME car-light.png
)
install(FILES resources/icons/theme-dark.png
  DESTINATION /usr/share/backgrounds/hyggshi
  RENAME car-Dark.png
)
