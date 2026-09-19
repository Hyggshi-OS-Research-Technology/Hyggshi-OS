#pragma once
#include <QWidget>
#include <QTimer>
#include <QPropertyAnimation>

class QLabel;
class QProgressBar;

// ---------------------------------------------------------------------------
// OsdWindow — popup OSD hiển thị icon + thanh âm lượng khi bấm phím tắt.
//
// Đặc điểm:
//   - Không có titlebar, luôn on-top, không lấy focus chuột/bàn phím
//   - Tự ẩn sau 1.5 giây (reset timer nếu nhấn phím liên tiếp)
//   - Fade-in khi hiện, fade-out khi ẩn (QPropertyAnimation trên windowOpacity)
//   - Vị trí: góc phải dưới, cách viền 24px
//   - Màu: dark theme đồng nhất với Hyggshi OS (#141519)
// ---------------------------------------------------------------------------

class OsdWindow : public QWidget {
    Q_OBJECT
    Q_PROPERTY(qreal windowOpacity READ windowOpacity WRITE setWindowOpacity)

public:
    explicit OsdWindow(QWidget *parent = nullptr);

    // Hiển thị OSD với volume [0..100]; muted = true thì dùng icon muted
    void showVolume(int volume, bool muted);

    // Hiển thị OSD mute riêng (khi muted, không biết chính xác %)
    void showMuted(bool muted);

private slots:
    void startHideAnimation();

protected:
    void paintEvent(QPaintEvent *event) override;

private:
    void updatePosition();
    void applyStyle();

    QLabel       *m_iconLabel{nullptr};
    QProgressBar *m_bar{nullptr};
    QLabel       *m_valueLabel{nullptr};
    QTimer       *m_hideTimer{nullptr};

    QPropertyAnimation *m_fadeIn{nullptr};
    QPropertyAnimation *m_fadeOut{nullptr};

    // Pixel map embedded via QRC
    static constexpr const char *kIconHigh   = ":/icons/volume-high.png";
    static constexpr const char *kIconLow    = ":/icons/volume-low.png";
    static constexpr const char *kIconMuted  = ":/icons/volume-muted.png";
};
