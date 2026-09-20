#include "KeyGrabber.h"

#include <QDebug>
#include <QSocketNotifier>

// Include X11 AFTER Qt headers to prevent X11 macros (Status, Bool, None) from corrupting Qt headers
#include <X11/Xlib.h>
#include <X11/XF86keysym.h>

#ifdef Status
#undef Status
#endif
#ifdef Bool
#undef Bool
#endif
#ifdef None
#undef None
#endif
#ifdef CursorShape
#undef CursorShape
#endif

// Các kết hợp modifier phổ biến để không bao giờ bị miss phím khi NumLock/CapsLock bật
static const unsigned int kModifiers[] = {
    0,
    Mod2Mask,                          // NumLock
    LockMask,                          // CapsLock
    Mod2Mask | LockMask,               // NumLock + CapsLock
    Mod3Mask,                          // ScrollLock
    Mod3Mask | Mod2Mask,
    Mod3Mask | LockMask,
    Mod3Mask | Mod2Mask | LockMask,
    AnyModifier                        // Fallback chung
};

// ---------------------------------------------------------------------------
KeyGrabber::KeyGrabber(QObject *parent)
    : QObject(parent)
{
    XInitThreads();
    m_display = XOpenDisplay(nullptr);
    if (!m_display) {
        qWarning() << "[HyggshiSound] KeyGrabber: XOpenDisplay thất bại. Không kết nối được X11.";
        return;
    }

    if (grabKeys()) {
        m_active = true;
        const int fd = ConnectionNumber(m_display);
        m_notifier = new QSocketNotifier(fd, QSocketNotifier::Read, this);
        connect(m_notifier, &QSocketNotifier::activated,
                this, [this]() { onX11Event(); });
        qDebug() << "[HyggshiSound] KeyGrabber: Đang bắt phím XF86Audio* nhạy cao trên X11 fd" << fd;
    } else {
        qWarning() << "[HyggshiSound] KeyGrabber: XGrabKey thất bại — phím tắt có thể bị ứng dụng khác chiếm.";
        XCloseDisplay(m_display);
        m_display = nullptr;
    }
}

KeyGrabber::~KeyGrabber()
{
    if (m_display) {
        ungrabKeys();
        XCloseDisplay(m_display);
    }
}

// ---------------------------------------------------------------------------
bool KeyGrabber::grabKeys()
{
    if (!m_display) return false;
    Window root = DefaultRootWindow(m_display);

    // Lấy keycode tương ứng layout hiện tại
    m_keyRaise   = XKeysymToKeycode(m_display, XF86XK_AudioRaiseVolume);
    m_keyLower   = XKeysymToKeycode(m_display, XF86XK_AudioLowerVolume);
    m_keyMute    = XKeysymToKeycode(m_display, XF86XK_AudioMute);
    m_keyMicMute = XKeysymToKeycode(m_display, XF86XK_AudioMicMute);

    int grabbedCount = 0;
    const unsigned int keys[] = {m_keyRaise, m_keyLower, m_keyMute, m_keyMicMute};

    for (unsigned int key : keys) {
        if (key == 0) continue;
        for (unsigned int mod : kModifiers) {
            XGrabKey(m_display, static_cast<int>(key), mod, root,
                     False, GrabModeAsync, GrabModeAsync);
        }
        ++grabbedCount;
    }

    XFlush(m_display);
    return grabbedCount > 0;
}

void KeyGrabber::ungrabKeys()
{
    if (!m_display) return;
    Window root = DefaultRootWindow(m_display);

    const unsigned int keys[] = {m_keyRaise, m_keyLower, m_keyMute, m_keyMicMute};
    for (unsigned int key : keys) {
        if (key == 0) continue;
        for (unsigned int mod : kModifiers) {
            XUngrabKey(m_display, static_cast<int>(key), mod, root);
        }
    }
    XFlush(m_display);
}

// ---------------------------------------------------------------------------
void KeyGrabber::onX11Event()
{
    while (m_display && XPending(m_display)) {
        XEvent event;
        XNextEvent(m_display, &event);

        // Tự động nhận diện khi người dùng đổi layout bàn phím (ví dụ bộ gõ tiếng Việt)
        if (event.type == MappingNotify) {
            XRefreshKeyboardMapping(&event.xmapping);
            ungrabKeys();
            grabKeys();
            continue;
        }

        if (event.type != KeyPress) continue;

        const unsigned int code = static_cast<unsigned int>(event.xkey.keycode);

        if (code == m_keyRaise && m_keyRaise != 0) {
            emit volumeUp();
        } else if (code == m_keyLower && m_keyLower != 0) {
            emit volumeDown();
        } else if (code == m_keyMute && m_keyMute != 0) {
            emit muteToggle();
        } else if (code == m_keyMicMute && m_keyMicMute != 0) {
            emit micMuteToggle();
        }
    }
}
