#pragma once
#include <QObject>
#include <QSocketNotifier>

// Cần X11 raw headers — phải include TRƯỚC bất kỳ Qt header nào dùng None/Bool
// để tránh conflict macro. Xem note ở top của KeyGrabber.cpp.
struct _XDisplay;
typedef struct _XDisplay Display;

// ---------------------------------------------------------------------------
// KeyGrabber — bắt global hotkey âm thanh qua XGrabKey (X11).
//
// Bắt các keysym tiêu chuẩn XF86Audio*. Dùng QSocketNotifier trên X11 fd
// để nhận XKeyEvent không blocking, không tốn CPU khi idle.
//
// Các phím được bắt:
//   XF86AudioRaiseVolume  → signal volumeUp()
//   XF86AudioLowerVolume  → signal volumeDown()
//   XF86AudioMute         → signal muteToggle()
// ---------------------------------------------------------------------------

class KeyGrabber : public QObject {
    Q_OBJECT

public:
    explicit KeyGrabber(QObject *parent = nullptr);
    ~KeyGrabber() override;

    // Trả về true nếu grab thành công ít nhất 1 keysym
    bool isActive() const { return m_active; }

signals:
    void volumeUp();
    void volumeDown();
    void muteToggle();

private slots:
    void onX11Event();

private:
    bool grabKeys();
    void ungrabKeys();

    Display          *m_display{nullptr};
    QSocketNotifier  *m_notifier{nullptr};
    bool              m_active{false};

    // Keycode (platform-specific) — lấy lúc grab
    unsigned int m_keyRaise{0};
    unsigned int m_keyLower{0};
    unsigned int m_keyMute{0};
};
