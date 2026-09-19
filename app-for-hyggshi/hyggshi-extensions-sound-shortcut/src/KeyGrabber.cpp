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

// ---------------------------------------------------------------------------
KeyGrabber::KeyGrabber(QObject *parent)
    : QObject(parent)
{
    XInitThreads();
    m_display = XOpenDisplay(nullptr);
    if (!m_display) {
        qWarning() << "[HyggshiSound] KeyGrabber: XOpenDisplay thất bại."
                   << "Daemon sẽ chạy nhưng không bắt được phím tắt.";
        return;
    }

    if (grabKeys()) {
        m_active = true;
        const int fd = ConnectionNumber(m_display);
        m_notifier = new QSocketNotifier(fd, QSocketNotifier::Read, this);
        connect(m_notifier, &QSocketNotifier::activated,
                this, [this]() { onX11Event(); });
        qDebug() << "[HyggshiSound] KeyGrabber: đang bắt phím XF86Audio* trên X11 fd" << fd;
    } else {
        qWarning() << "[HyggshiSound] KeyGrabber: XGrabKey thất bại — phím tắt sẽ không hoạt động.";
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
    Window root = DefaultRootWindow(m_display);

    // Map keysym → keycode (phụ thuộc layout bàn phím hiện tại)
    m_keyRaise = XKeysymToKeycode(m_display, XF86XK_AudioRaiseVolume);
    m_keyLower = XKeysymToKeycode(m_display, XF86XK_AudioLowerVolume);
    m_keyMute  = XKeysymToKeycode(m_display, XF86XK_AudioMute);

    int grabbed = 0;
    // Bắt với AnyModifier để không bị block bởi CapsLock/NumLock
    // (đây là pattern chuẩn cho media key global grab)
    for (unsigned int key : {m_keyRaise, m_keyLower, m_keyMute}) {
        if (key == 0) continue;
        XGrabKey(m_display, static_cast<int>(key), AnyModifier, root,
                 False, GrabModeAsync, GrabModeAsync);
        ++grabbed;
    }

    XFlush(m_display);
    return grabbed > 0;
}

void KeyGrabber::ungrabKeys()
{
    if (!m_display) return;
    Window root = DefaultRootWindow(m_display);
    for (unsigned int key : {m_keyRaise, m_keyLower, m_keyMute}) {
        if (key == 0) continue;
        XUngrabKey(m_display, static_cast<int>(key), AnyModifier, root);
    }
    XFlush(m_display);
}

// ---------------------------------------------------------------------------
void KeyGrabber::onX11Event()
{
    while (XPending(m_display)) {
        XEvent event;
        XNextEvent(m_display, &event);

        if (event.type != KeyPress) continue;

        const unsigned int code = static_cast<unsigned int>(event.xkey.keycode);

        if (code == m_keyRaise && m_keyRaise != 0) {
            emit volumeUp();
        } else if (code == m_keyLower && m_keyLower != 0) {
            emit volumeDown();
        } else if (code == m_keyMute && m_keyMute != 0) {
            emit muteToggle();
        }
    }
}
