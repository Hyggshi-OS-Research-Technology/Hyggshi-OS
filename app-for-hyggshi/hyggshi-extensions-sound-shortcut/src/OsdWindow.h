#pragma once
#include <QWidget>
#include <QTimer>
#include <QPropertyAnimation>

class QLabel;

// ---------------------------------------------------------------------------
// OsdWindow — popup OSD hiển thị icon + thanh âm lượng khi bấm phím tắt.
//
// Tối ưu độ nhạy & trải nghiệm:
//   - Thanh tiến trình vẽ trực tiếp bằng QPainter (0ms CSS overhead, 60/144 FPS).
//   - QPropertyAnimation trên displayVolume lướt mượt mà giữa các mức âm lượng.
//   - Fade in/out qua custom alpha field (hoạt động kể cả khi xcb plugin không
//     hỗ trợ setWindowOpacity) — alpha 0..1 được apply trực tiếp trong paintEvent.
//   - Nhận diện màn hình theo chuột (Multi-monitor) + trừ diện tích panel XFCE.
//   - Chống chớp nháy (flicker-free) khi nhấn phím nhanh.
// ---------------------------------------------------------------------------

class OsdWindow : public QWidget {
    Q_OBJECT
    // Custom alpha [0.0 .. 1.0] — dùng thay windowOpacity() để tương thích xcb
    Q_PROPERTY(qreal alpha READ alpha WRITE setAlpha)
    Q_PROPERTY(qreal displayVolume READ displayVolume WRITE setDisplayVolume)

public:
    explicit OsdWindow(QWidget *parent = nullptr);

    // Hiển thị OSD với volume [0..100]; muted = true thì dùng icon muted
    void showVolume(int volume, bool muted);

    // Hiển thị OSD mute riêng
    void showMuted(bool muted);

    qreal displayVolume() const { return m_displayVolume; }
    void  setDisplayVolume(qreal val);

    qreal alpha() const { return m_alpha; }
    void  setAlpha(qreal a);

private slots:
    void startHideAnimation();

protected:
    void paintEvent(QPaintEvent *event) override;

private:
    void updatePosition();

    QLabel *m_iconLabel {nullptr};
    QLabel *m_valueLabel{nullptr};
    QTimer *m_hideTimer {nullptr};

    QPropertyAnimation *m_fadeIn {nullptr};
    QPropertyAnimation *m_fadeOut{nullptr};
    QPropertyAnimation *m_barAnim{nullptr};

    qreal m_alpha        {0.0};   // alpha hiện tại [0..1]
    qreal m_displayVolume{50.0};
    int   m_targetVolume {50};
    bool  m_muted        {false};

    // Icon paths (cũng khai báo trong .cpp nhưng giữ đây để các hàm inline dùng)
    static constexpr const char *kIconHigh  = ":/icons/volume-high.png";
    static constexpr const char *kIconLow   = ":/icons/volume-low.png";
    static constexpr const char *kIconMuted = ":/icons/volume-muted.png";
};
