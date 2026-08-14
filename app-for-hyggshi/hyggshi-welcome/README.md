# hyggshi-welcome

App chào mừng đầu tiên cho Hyggshi OS — C++/Qt Widgets, có animation trượt
trang (slide + fade) giữa các bước cấu hình nhanh, phong cách giống GNOME
Initial Setup (Fedora) / Ubuntu Welcome.

Build tay:

```bash
cmake -B build -S .
cmake --build build -j
./build/hyggshi-welcome
```

Sinh lại app cùng lần chạy tiếp theo dù đã đánh dấu "đã xem" (marker file
`~/.config/hyggshi/welcome-shown`):

```bash
HYGGSHI_WELCOME_FORCE=1 ./build/hyggshi-welcome
```
