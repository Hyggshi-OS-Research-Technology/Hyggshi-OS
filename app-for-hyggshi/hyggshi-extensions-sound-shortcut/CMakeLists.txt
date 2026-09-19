cmake_minimum_required(VERSION 3.16)

project(hyggshi-extensions-sound-shortcut VERSION 1.0.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

include(GNUInstallDirs)

# ---------------------------------------------------------------------------
# Qt: prefer Qt6, fall back to Qt5 (same pattern as hyggshi-welcome)
# ---------------------------------------------------------------------------
find_package(Qt6 QUIET COMPONENTS Widgets)
if(Qt6_FOUND)
  set(QT_LIBS Qt6::Widgets)
  message(STATUS "hyggshi-sound-shortcut: using Qt6")
else()
  find_package(Qt5 REQUIRED COMPONENTS Widgets)
  set(QT_LIBS Qt5::Widgets)
  message(STATUS "hyggshi-sound-shortcut: using Qt5 (Qt6 not found)")
endif()

# ---------------------------------------------------------------------------
# X11 (for XGrabKey global hotkey interception)
# ---------------------------------------------------------------------------
find_package(X11 REQUIRED)

# ---------------------------------------------------------------------------
# Sources
# ---------------------------------------------------------------------------
file(GLOB APP_SOURCES CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/src/*.cpp")
file(GLOB APP_HEADERS CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/src/*.h")

add_executable(hyggshi-sound-shortcut
  ${APP_SOURCES}
  ${APP_HEADERS}
  resources/hyggshi-sound-shortcut.qrc
)

target_link_libraries(hyggshi-sound-shortcut PRIVATE
  ${QT_LIBS}
  ${X11_LIBRARIES}
)

target_include_directories(hyggshi-sound-shortcut PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/src"
  ${X11_INCLUDE_DIR}
)

target_compile_options(hyggshi-sound-shortcut PRIVATE
  $<$<COMPILE_LANG_AND_ID:CXX,GNU,Clang>:-Wall>
  $<$<COMPILE_LANG_AND_ID:CXX,GNU,Clang>:-Wextra>
  $<$<COMPILE_LANG_AND_ID:CXX,GNU,Clang>:-Wpedantic>
)

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------
install(TARGETS hyggshi-sound-shortcut
  RUNTIME DESTINATION "${CMAKE_INSTALL_BINDIR}"
)

install(FILES packaging/hyggshi-sound-shortcut-autostart.desktop
  DESTINATION "${CMAKE_INSTALL_SYSCONFDIR}/xdg/autostart"
  RENAME hyggshi-sound-shortcut.desktop
)

install(FILES packaging/hyggshi-sound-shortcut-app.desktop
  DESTINATION "${CMAKE_INSTALL_DATADIR}/applications"
)

foreach(ICON_SIZE 48 64 128 256)
  install(FILES resources/icons/volume-high.png
    DESTINATION "${CMAKE_INSTALL_DATADIR}/icons/hicolor/${ICON_SIZE}x${ICON_SIZE}/apps"
    RENAME hyggshi-sound-shortcut.png
  )
endforeach()
