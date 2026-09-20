#pragma once
#include <QObject>
#include <QSocketNotifier>

struct _XDisplay;
typedef struct _XDisplay Display;

// ---------------------------------------------------------------------------
// KeyGrabber — bắt global hotkey âm thanh qua XGrabKey (X11) với độ nhạy tối đa.
//
// Tính năng nâng cao:
//   - Hỗ trợ đầy đủ các mặt nạ Modifier (NumLock, CapsLock, ScrollLock)
//     đảm bảo không bị nuốt phím khi bật đèn phím số.
//   - Tự động cập nhật keycode khi thay đổi layout bàn phím (MappingNotify).
//   - Bắt các phím:
//       XF86AudioRaiseVolume  → signal volumeUp()
//       XF86AudioLowerVolume  → signal volumeDown()
//       XF86AudioMute         → signal muteToggle()
//       XF86AudioMicMute      → signal micMuteToggle()
// ---------------------------------------------------------------------------

class KeyGrabber : public QObject {
    Q_OBJECT

public:
    explicit KeyGrabber(QObject *parent = nullptr);
    ~KeyGrabber() override;

    bool isActive() const { return m_active; }

signals:
    void volumeUp();
    void volumeDown();
    void muteToggle();
    void micMuteToggle();

private slots:
    void onX11Event();

private:
    bool grabKeys();
    void ungrabKeys();

    Display          *m_display{nullptr};
    QSocketNotifier  *m_notifier{nullptr};
    bool              m_active{false};

    unsigned int m_keyRaise{0};
    unsigned int m_keyLower{0};
    unsigned int m_keyMute{0};
    unsigned int m_keyMicMute{0};
};
