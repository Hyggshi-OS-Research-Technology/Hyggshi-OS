#!/bin/bash
# make-theme-daemon.sh — sinh project "hyggshi-theme-daemon": daemon C++ nhẹ
# thay cho việc hyggshi-welcome/hyggshi-set-wallpaper.sh fork xfconf-query
# liên tục. Kiến trúc:
#
#  - Link THẲNG libxfconf (không spawn process `xfconf-query` mỗi lần đổi
#    theme) — đọc/ghi property qua xfconf_channel_get_string/set_string.
#
#  - Event-driven, KHÔNG poll: g_signal_connect vào "property-changed" của
#    channel xfconf, xfconf tự bắn signal qua GObject khi có property đổi
#    (kể cả đổi bởi tiến trình khác, vd Appearance settings hoặc
#    hyggshi-welcome) -> daemon chỉ thức dậy đúng lúc cần, ~0% CPU lúc rảnh.
#
#  - Channel riêng "hyggshi" quyết định chế độ:
#      /theme/mode              "light" | "dark" | "auto"   (mặc định "auto")
#      /theme/auto-light-hour   giờ chuyển sang Sáng          (mặc định 6)
#      /theme/auto-dark-hour    giờ chuyển sang Tối           (mặc định 18)
#    Ở mode "auto", daemon KHÔNG polling theo phút/giây — tính chính xác số
#    giây tới mốc chuyển tiếp theo rồi đặt g_timeout_add_seconds() DUY NHẤT,
#    bắn xong tự re-arm cho mốc kế tiếp. Ngoài 2 lần thức mỗi ngày đó, daemon
#    ngồi im trong GMainLoop.
#
#  - Đổi wallpaper: gọi xfconf_channel_set_string() thẳng trên channel
#    "xfce4-desktop" cho MỌI property last-image tìm được dưới /backdrop
#    (đọc qua xfconf_channel_get_properties(), tương đương vòng lặp
#    "xfconf-query -p /backdrop -l" trong hyggshi-set-wallpaper.sh nhưng
#    không fork process con).
#
#  - Chạy như systemd --user service (packaging/hyggshi-theme-daemon.service),
#    WantedBy=graphical-session.target, kèm preset file để tự enable cho
#    user mới mà không cần chạy tay `systemctl --user enable`.
#
# Cách dùng:
#   ./scripts/components/make-theme-daemon.sh            # chỉ sinh source code
#   ./scripts/components/make-theme-daemon.sh --build    # sinh xong rồi cmake build luôn
#   ./scripts/components/make-theme-daemon.sh --install  # sinh + build + cài vào hệ thống
#
# Cần cài (Debian/Ubuntu) để build: libxfconf-0-dev libglib2.0-dev pkg-config
set -e
[ "$DEBUG_MODE" = "true" ] && set -x

MODE="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
APP_DIR="$REPO_ROOT/packages/hyggshi/hyggshi-theme-daemon"

echo "===== Tạo cây thư mục project hyggshi-theme-daemon tại: $APP_DIR ====="
mkdir -p "$APP_DIR/src" "$APP_DIR/packaging"

# ---------------------------------------------------------------------------
# CMakeLists.txt — pkg-config tìm xfconf-0 + glib-2.0/gobject-2.0.
# ---------------------------------------------------------------------------
cat > "$APP_DIR/CMakeLists.txt" <<'CMAKEEOF'
cmake_minimum_required(VERSION 3.16)
project(hyggshi-theme-daemon LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(PkgConfig REQUIRED)
pkg_check_modules(XFCONF REQUIRED IMPORTED_TARGET libxfconf-0)
pkg_check_modules(GLIB REQUIRED IMPORTED_TARGET glib-2.0 gobject-2.0)

add_executable(hyggshi-theme-daemon src/main.cpp)
target_link_libraries(hyggshi-theme-daemon PRIVATE PkgConfig::XFCONF PkgConfig::GLIB)

install(TARGETS hyggshi-theme-daemon RUNTIME DESTINATION bin)

# Absolute path thay vì DESTINATION theo CMAKE_INSTALL_PREFIX — cùng kiểu
# với autostart entry của hyggshi-welcome (xem make-welcome.sh), vì systemd
# --user unit PHẢI nằm đúng /usr/lib/systemd/user để được nhận diện, bất kể
# prefix cài app là gì.
install(FILES packaging/hyggshi-theme-daemon.service
        DESTINATION /usr/lib/systemd/user)
install(FILES packaging/hyggshi-theme-daemon.preset
        DESTINATION /usr/lib/systemd/user-preset
        RENAME 90-hyggshi-theme-daemon.preset)
CMAKEEOF

# ---------------------------------------------------------------------------
# src/main.cpp
# ---------------------------------------------------------------------------
cat > "$APP_DIR/src/main.cpp" <<'CEOF'
// hyggshi-theme-daemon — daemon nhẹ đổi wallpaper theo theme Sáng/Tối/Tự
// động, link thẳng libxfconf (không fork xfconf-query) và event-driven
// (không polling) — xem chú thích kiến trúc đầy đủ trong
// scripts/components/make-theme-daemon.sh.
#include <xfconf/xfconf.h>
#include <glib.h>

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <cstring>
#include <ctime>
#include <string>

namespace {

constexpr const char *kDesktopChannelName = "xfce4-desktop";
constexpr const char *kXsettingsChannelName = "xsettings";
constexpr const char *kHyggshiChannelName = "hyggshi";

constexpr const char *kThemeNameProp = "/Net/ThemeName";
constexpr const char *kModeProp = "/theme/mode";
constexpr const char *kLightHourProp = "/theme/auto-light-hour";
constexpr const char *kDarkHourProp = "/theme/auto-dark-hour";

constexpr const char *kLightWallpaper = "/usr/share/backgrounds/hyggshi/car-light.png";
constexpr const char *kDarkWallpaper = "/usr/share/backgrounds/hyggshi/car-Dark.png";

XfconfChannel *g_desktop_channel = nullptr;
XfconfChannel *g_xsettings_channel = nullptr;
XfconfChannel *g_hyggshi_channel = nullptr;
guint g_auto_timer_id = 0;

std::string get_mode() {
  gchar *mode = xfconf_channel_get_string(g_hyggshi_channel, kModeProp, "auto");
  std::string result = mode ? mode : "auto";
  g_free(mode);
  return result;
}

int get_hour_prop(const char *prop, int fallback) {
  return xfconf_channel_get_int(g_hyggshi_channel, prop, fallback);
}

bool is_dark_theme_name(const std::string &name) {
  std::string lower = name;
  std::transform(lower.begin(), lower.end(), lower.begin(),
                  [](unsigned char c) { return std::tolower(c); });
  return lower.find("dark") != std::string::npos;
}

// Ghi đè MỌI property last-image dưới /backdrop bằng xfconf_channel_set_*
// trực tiếp — tương đương vòng lặp "xfconf-query -p /backdrop -l | grep
// last-image" trong hyggshi-set-wallpaper.sh, nhưng đọc qua API thay vì
// fork process con.
void apply_wallpaper(const char *path) {
  if (!g_desktop_channel || !path) return;
  if (!g_file_test(path, G_FILE_TEST_EXISTS)) {
    g_warning("hyggshi-theme-daemon: khong tim thay wallpaper %s, bo qua", path);
    return;
  }

  GHashTable *props = xfconf_channel_get_properties(g_desktop_channel, "/backdrop");
  bool any = false;
  if (props) {
    GHashTableIter iter;
    gpointer key, value;
    g_hash_table_iter_init(&iter, props);
    while (g_hash_table_iter_next(&iter, &key, &value)) {
      const char *prop = static_cast<const char *>(key);
      if (!g_str_has_suffix(prop, "last-image")) continue;

      xfconf_channel_set_string(g_desktop_channel, prop, path);

      std::string style_prop(prop);
      const std::string suffix = "last-image";
      style_prop.replace(style_prop.size() - suffix.size(), suffix.size(),
                          "image-style");
      xfconf_channel_set_int(g_desktop_channel, style_prop.c_str(), 5);
      any = true;
    }
    g_hash_table_destroy(props);
  }

  // Chưa có property nào (xfdesktop chưa từng tạo cây /backdrop, vd daemon
  // khởi động trước xfdesktop) — fallback monitor0 mặc định, giống
  // hyggshi-set-wallpaper.sh; xfdesktop sẽ tự đọc lại khi nó khởi động.
  if (!any) {
    xfconf_channel_set_string(
        g_desktop_channel,
        "/backdrop/screen0/monitor0/workspace0/last-image", path);
    xfconf_channel_set_int(
        g_desktop_channel,
        "/backdrop/screen0/monitor0/workspace0/image-style", 5);
  }

  g_message("hyggshi-theme-daemon: da ap wallpaper %s", path);
}

void apply_theme(bool dark) {
  apply_wallpaper(dark ? kDarkWallpaper : kLightWallpaper);
}

gboolean on_auto_timer(gpointer user_data);

// Tính số giây tới mốc chuyển theme kế tiếp (auto-light-hour hoặc
// auto-dark-hour, cái nào gần hơn) và đặt DUY NHẤT MỘT g_timeout_add_seconds
// — không lặp lại mỗi giây/phút như polling truyền thống.
void schedule_next_auto_switch() {
  if (g_auto_timer_id != 0) {
    g_source_remove(g_auto_timer_id);
    g_auto_timer_id = 0;
  }
  if (get_mode() != "auto") return;

  const int light_hour = get_hour_prop(kLightHourProp, 6);
  const int dark_hour = get_hour_prop(kDarkHourProp, 18);

  const time_t now = time(nullptr);
  struct tm local_tm;
  localtime_r(&now, &local_tm);

  // Áp đúng theme của giờ hiện tại trước, rồi mới lên lịch mốc kế tiếp.
  const bool currently_dark =
      (light_hour <= dark_hour)
          ? !(local_tm.tm_hour >= light_hour && local_tm.tm_hour < dark_hour)
          : (local_tm.tm_hour >= dark_hour && local_tm.tm_hour < light_hour);
  apply_theme(currently_dark);

  auto seconds_until = [&](int target_hour) -> long {
    struct tm target_tm = local_tm;
    target_tm.tm_hour = target_hour;
    target_tm.tm_min = 0;
    target_tm.tm_sec = 0;
    time_t target = mktime(&target_tm);
    if (target <= now) target += 24 * 3600;  // mốc hôm nay đã qua -> mai
    return static_cast<long>(difftime(target, now));
  };

  long next_in = std::min(seconds_until(light_hour), seconds_until(dark_hour));
  if (next_in < 1) next_in = 1;

  g_auto_timer_id = g_timeout_add_seconds(static_cast<guint>(next_in),
                                           on_auto_timer, nullptr);
  g_message(
      "hyggshi-theme-daemon: mode=auto, theme hien tai=%s, "
      "lan chuyen ke tiep sau %ld giay",
      currently_dark ? "toi" : "sang", next_in);
}

gboolean on_auto_timer(gpointer) {
  schedule_next_auto_switch();  // áp theme mới + tự re-arm mốc kế tiếp
  return G_SOURCE_REMOVE;
}

// property-changed trên channel "xsettings" — bắt lúc /Net/ThemeName đổi
// TAY (Appearance settings, hoặc hyggshi-welcome set lúc setup) để wallpaper
// theo kịp ngay. Bỏ qua khi đang ở mode "auto" để lịch giờ không bị đá nhau
// với thao tác tay tạm thời.
void on_xsettings_changed(XfconfChannel *, const gchar *property,
                           const GValue *value, gpointer) {
  if (g_strcmp0(property, kThemeNameProp) != 0) return;
  if (get_mode() == "auto") return;
  if (!value || !G_VALUE_HOLDS_STRING(value)) return;
  apply_theme(is_dark_theme_name(g_value_get_string(value)));
}

// property-changed trên channel "hyggshi" — user đổi mode (vd từ
// hyggshi-welcome) hoặc đổi giờ auto-light-hour/auto-dark-hour -> áp ngay +
// tính lại lịch, không đợi tới mốc timer cũ.
void on_hyggshi_changed(XfconfChannel *, const gchar *property, const GValue *,
                         gpointer) {
  if (g_strcmp0(property, kModeProp) == 0) {
    const std::string mode = get_mode();
    if (mode == "auto") {
      schedule_next_auto_switch();
    } else {
      if (g_auto_timer_id != 0) {
        g_source_remove(g_auto_timer_id);
        g_auto_timer_id = 0;
      }
      apply_theme(mode == "dark");
    }
  } else if (g_strcmp0(property, kLightHourProp) == 0 ||
             g_strcmp0(property, kDarkHourProp) == 0) {
    if (get_mode() == "auto") schedule_next_auto_switch();
  }
}

}  // namespace

int main(int, char **) {
  GError *error = nullptr;
  if (!xfconf_init(&error)) {
    g_printerr("hyggshi-theme-daemon: xfconf_init that bai: %s\n",
               error ? error->message : "khong ro loi");
    if (error) g_error_free(error);
    return 1;
  }

  g_desktop_channel = xfconf_channel_get(kDesktopChannelName);
  g_xsettings_channel = xfconf_channel_get(kXsettingsChannelName);
  g_hyggshi_channel = xfconf_channel_get(kHyggshiChannelName);

  g_signal_connect(g_xsettings_channel, "property-changed",
                    G_CALLBACK(on_xsettings_changed), nullptr);
  g_signal_connect(g_hyggshi_channel, "property-changed",
                    G_CALLBACK(on_hyggshi_changed), nullptr);

  // Áp trạng thái ban đầu ngay lúc daemon khởi động (login/systemd start),
  // không đợi property-changed đầu tiên.
  const std::string mode = get_mode();
  if (mode == "auto") {
    schedule_next_auto_switch();
  } else {
    apply_theme(mode == "dark");
  }

  GMainLoop *loop = g_main_loop_new(nullptr, FALSE);
  g_main_loop_run(loop);  // event-driven, khong ton CPU luc ranh

  g_main_loop_unref(loop);
  xfconf_shutdown();
  return 0;
}
CEOF

# ---------------------------------------------------------------------------
# packaging/hyggshi-theme-daemon.service — systemd --user unit.
# ---------------------------------------------------------------------------
cat > "$APP_DIR/packaging/hyggshi-theme-daemon.service" <<'SVCEOF'
[Unit]
Description=Hyggshi theme/wallpaper auto-switch daemon
After=graphical-session-pre.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/bin/hyggshi-theme-daemon
Restart=on-failure
RestartSec=5
# Daemon rất nhẹ (event-driven, không polling) — giới hạn tài nguyên chỉ để
# chặn leak bất thường, không phải vì tốn tài nguyên bình thường.
MemoryMax=32M
CPUQuota=5%

[Install]
WantedBy=graphical-session.target
SVCEOF

# ---------------------------------------------------------------------------
# packaging/hyggshi-theme-daemon.preset — tự enable cho user mới mà không
# cần chạy tay `systemctl --user enable hyggshi-theme-daemon.service`.
# ---------------------------------------------------------------------------
cat > "$APP_DIR/packaging/hyggshi-theme-daemon.preset" <<'PRESETEOF'
enable hyggshi-theme-daemon.service
PRESETEOF

cat > "$APP_DIR/README.md" <<'MDEOF'
# hyggshi-theme-daemon

Daemon C++ nhẹ, thay cho việc hyggshi-welcome / hyggshi-set-wallpaper.sh
fork `xfconf-query` liên tục để đổi wallpaper. Link thẳng `libxfconf`,
event-driven qua GObject signal (không polling), và có thể tự chuyển
Sáng/Tối theo giờ.

## Điều khiển qua xfconf (channel "hyggshi")

```bash
# Chế độ: light | dark | auto (mặc định auto)
xfconf-query -c hyggshi -p /theme/mode -n -t string -s auto

# Giờ chuyển sang Sáng / Tối khi ở mode "auto" (mặc định 6 / 18)
xfconf-query -c hyggshi -p /theme/auto-light-hour -n -t int -s 6
xfconf-query -c hyggshi -p /theme/auto-dark-hour  -n -t int -s 18
```

Daemon lắng nghe property-changed trên channel này (và trên
`xsettings` /Net/ThemeName) nên áp dụng ngay lập tức, không cần restart.

## Build tay

```bash
cmake -B build -S .
cmake --build build -j
./build/hyggshi-theme-daemon
```

Cần: `libxfconf-0-dev`, `libglib2.0-dev`, `pkg-config`
(`apt-get install libxfconf-0-dev libglib2.0-dev pkg-config`).

## Cài + chạy như systemd --user service

```bash
sudo cmake --install build
systemctl --user daemon-reload
systemctl --user enable --now hyggshi-theme-daemon.service
journalctl --user -u hyggshi-theme-daemon.service -f
```

(File preset `90-hyggshi-theme-daemon.preset` đã tự enable service này cho
user mới tạo trên ISO đã build — không cần chạy `enable` tay trong trường
hợp đó.)
MDEOF

echo "===== Đã sinh xong source code tại $APP_DIR ====="

# ---------------------------------------------------------------------------
# --build / --install: cấu hình + build thật bằng cmake.
# ---------------------------------------------------------------------------
if [ "$MODE" = "--build" ] || [ "$MODE" = "--install" ]; then
  if ! command -v cmake > /dev/null 2>&1; then
    echo "LỖI: cần cmake để build. Cài: sudo apt-get install -y cmake build-essential libxfconf-0-dev libglib2.0-dev pkg-config" >&2
    exit 1
  fi
  if ! pkg-config --exists libxfconf-0 glib-2.0 gobject-2.0 2>/dev/null; then
    echo "LỖI: thiếu dev headers. Cài: sudo apt-get install -y libxfconf-0-dev libglib2.0-dev pkg-config" >&2
    exit 1
  fi
  echo "===== cmake configure + build (Release) ====="
  cmake -S "$APP_DIR" -B "$APP_DIR/build" -DCMAKE_BUILD_TYPE=Release
  cmake --build "$APP_DIR/build" -j"$(nproc)"
  echo "===== Build xong: $APP_DIR/build/hyggshi-theme-daemon ====="
fi

if [ "$MODE" = "--install" ]; then
  echo "===== Cài vào hệ thống (cần sudo) ====="
  sudo cmake --install "$APP_DIR/build"
  sudo systemctl daemon-reload 2>/dev/null || true
  echo "Đã cài hyggshi-theme-daemon + systemd --user unit + preset."
  echo "Chạy ngay (user hiện tại): systemctl --user enable --now hyggshi-theme-daemon.service"
fi
