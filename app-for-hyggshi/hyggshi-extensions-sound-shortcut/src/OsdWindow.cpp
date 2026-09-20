#include "OsdWindow.h"

#include <QApplication>
#include <QCursor>
#include <QEasingCurve>
#include <QGuiApplication>
#include <QHBoxLayout>
#include <QLabel>
#include <QPainter>
#include <QPainterPath>
#include <QPropertyAnimation>
#include <QScreen>
#include <QTimer>

// ---------------------------------------------------------------------------
// Hằng số thiết kế (dark theme Hyggshi OS)
// ---------------------------------------------------------------------------
static constexpr int kOsdWidth   = 320;
static constexpr int kOsdHeight  = 58;
static constexpr int kMargin     = 28;    // khoảng cách từ góc màn hình
static constexpr int kHideDelay  = 1500;  // ms trước khi bắt đầu ẩn
static constexpr int kFadeInTime = 120;   // ms fade-in (nhạy, mượt)
static constexpr int kFadeOutTime= 180;   // ms fade-out

// ---------------------------------------------------------------------------
OsdWindow::OsdWindow(QWidget *parent)
    : QWidget(parent, Qt::Window
              | Qt::FramelessWindowHint
              | Qt::WindowStaysOnTopHint
              | Qt::Tool)        // không hiện trên taskbar, không lấy focus
{
    // WA_TranslucentBackground cho phép vẽ alpha channel trong paintEvent
    setAttribute(Qt::WA_TranslucentBackground);
    setAttribute(Qt::WA_ShowWithoutActivating);
    setAttribute(Qt::WA_X11NetWmWindowTypeNotification);
    setFixedSize(kOsdWidth, kOsdHeight);

    // ---- Layout ngang ----
    auto *root = new QHBoxLayout(this);
    root->setContentsMargins(16, 0, 16, 0);
    root->setSpacing(12);

    m_iconLabel = new QLabel(this);
    m_iconLabel->setFixedSize(28, 28);
    m_iconLabel->setAlignment(Qt::AlignCenter);
    root->addWidget(m_iconLabel);

    // Khoảng trống co giãn — thanh bar được vẽ trực tiếp trong paintEvent
    root->addStretch(1);

    m_valueLabel = new QLabel(this);
    m_valueLabel->setFixedWidth(48);
    m_valueLabel->setAlignment(Qt::AlignRight | Qt::AlignVCenter);
    m_valueLabel->setStyleSheet(QStringLiteral(
        "color: rgba(230,231,234,255); font-size: 13px; font-weight: 600; "
        "font-family: 'Noto Sans','Ubuntu','Cantarell',sans-serif; "
        "background: transparent;"
    ));
    root->addWidget(m_valueLabel);

    // ---- Animation thanh trượt âm lượng (60ms OutQuad) ----
    m_barAnim = new QPropertyAnimation(this, "displayVolume", this);
    m_barAnim->setDuration(60);
    m_barAnim->setEasingCurve(QEasingCurve::OutQuad);

    // ---- Timer ẩn ----
    m_hideTimer = new QTimer(this);
    m_hideTimer->setSingleShot(true);
    connect(m_hideTimer, &QTimer::timeout, this, &OsdWindow::startHideAnimation);

    // ---- Fade-in: alpha 0 → 1 (OutCubic, 120ms — nhạy ngay) ----
    m_fadeIn = new QPropertyAnimation(this, "alpha", this);
    m_fadeIn->setDuration(kFadeInTime);
    m_fadeIn->setStartValue(0.0);
    m_fadeIn->setEndValue(1.0);
    m_fadeIn->setEasingCurve(QEasingCurve::OutCubic);

    // ---- Fade-out: alpha 1 → 0 (InCubic, 180ms — êm dịu) ----
    m_fadeOut = new QPropertyAnimation(this, "alpha", this);
    m_fadeOut->setDuration(kFadeOutTime);
    m_fadeOut->setStartValue(1.0);
    m_fadeOut->setEndValue(0.0);
    m_fadeOut->setEasingCurve(QEasingCurve::InCubic);
    connect(m_fadeOut, &QPropertyAnimation::finished, this, &QWidget::hide);
}

// ---------------------------------------------------------------------------
void OsdWindow::setAlpha(qreal a)
{
    m_alpha = qBound(0.0, a, 1.0);
    update();  // trigger repaint với alpha mới
}

// ---------------------------------------------------------------------------
void OsdWindow::setDisplayVolume(qreal val)
{
    m_displayVolume = val;
    update();
}

// ---------------------------------------------------------------------------
// paintEvent — tất cả vẽ dùng m_alpha để fade thật sự, không phụ thuộc
// setWindowOpacity() (không hoạt động trên một số xcb compositors).
// ---------------------------------------------------------------------------
void OsdWindow::paintEvent(QPaintEvent *)
{
    if (m_alpha <= 0.0) return;

    QPainter p(this);
    p.setRenderHint(QPainter::Antialiasing);

    // Tỷ lệ alpha áp vào toàn bộ widget qua painter opacity
    p.setOpacity(m_alpha);

    // 1. Nền bo góc tối sang trọng (#141519, border mờ)
    QRectF r = rect().adjusted(0.5, 0.5, -0.5, -0.5);
    QPainterPath path;
    path.addRoundedRect(r, 16, 16);
    p.fillPath(path, QColor(0x14, 0x15, 0x19, 245));
    p.setPen(QPen(QColor(0x36, 0x3b, 0x4d, 200), 1.0));
    p.drawPath(path);

    // 2. Thanh tiến trình âm lượng (pixel-perfect, 0ms lag)
    const qreal barX = 56.0;
    const qreal barW = width() - 56.0 - 66.0;   // trừ icon + số %
    const qreal barH = 8.0;
    const qreal barY = (height() - barH) / 2.0;

    QRectF trackRect(barX, barY, barW, barH);

    // Rãnh nền (#232630)
    p.setPen(Qt::NoPen);
    p.setBrush(QColor(0x23, 0x26, 0x30));
    p.drawRoundedRect(trackRect, 4.0, 4.0);

    // Tiến trình màu tím Hyggshi (#7c6af7)
    if (!m_muted && m_displayVolume > 0.0) {
        qreal fillW = trackRect.width() * (qBound(0.0, m_displayVolume, 100.0) / 100.0);
        if (fillW > 0.0) {
            // Gradient tím → xanh nhẹ cho chiều sâu thị giác
            QLinearGradient grad(barX, barY, barX + fillW, barY);
            grad.setColorAt(0.0, QColor(0x6a, 0x5a, 0xe8));
            grad.setColorAt(1.0, QColor(0x8f, 0x7e, 0xff));
            p.setBrush(grad);
            QRectF fillRect(barX, barY, fillW, barH);
            p.drawRoundedRect(fillRect, 4.0, 4.0);
        }
    }
}

// ---------------------------------------------------------------------------
void OsdWindow::updatePosition()
{
    // Nhận diện màn hình chứa con trỏ chuột (Multi-monitor)
    QScreen *screen = QGuiApplication::screenAt(QCursor::pos());
    if (!screen) screen = QApplication::primaryScreen();
    if (!screen) return;

    // availableGeometry() tự động loại trừ phần panel XFCE
    const QRect geom = screen->availableGeometry();
    move(geom.right()  - kOsdWidth  - kMargin,
         geom.bottom() - kOsdHeight - kMargin);
}

// ---------------------------------------------------------------------------
void OsdWindow::showVolume(int volume, bool muted)
{
    m_targetVolume = volume;
    m_muted = muted;

    // Chọn icon
    const char *iconPath = kIconHigh;
    if (muted)            iconPath = kIconMuted;
    else if (volume < 33) iconPath = kIconLow;

    m_iconLabel->setPixmap(
        QPixmap(QString::fromLatin1(iconPath)).scaled(
            m_iconLabel->size(), Qt::KeepAspectRatio, Qt::SmoothTransformation));

    // Nhãn số %
    m_valueLabel->setText(muted
        ? QStringLiteral("Muted")
        : QStringLiteral("%1%").arg(volume));
    m_valueLabel->setStyleSheet(muted
        ? QStringLiteral("color: rgba(142,146,160,255); font-size: 13px; font-weight: 600; "
                         "font-family: 'Noto Sans','Ubuntu','Cantarell',sans-serif; background: transparent;")
        : QStringLiteral("color: rgba(230,231,234,255); font-size: 13px; font-weight: 600; "
                         "font-family: 'Noto Sans','Ubuntu','Cantarell',sans-serif; background: transparent;"));

    // Animate thanh trượt âm lượng
    if (muted) {
        m_barAnim->stop();
        m_displayVolume = 0.0;
        update();
    } else {
        m_barAnim->stop();
        m_barAnim->setStartValue(m_displayVolume);
        m_barAnim->setEndValue(static_cast<qreal>(volume));
        m_barAnim->start();
    }

    // Dừng fade-out nếu đang ẩn dở
    m_fadeOut->stop();
    m_hideTimer->stop();

    updatePosition();

    // Nếu OSD chưa hiện hoặc gần kín → Fade-in
    if (!isVisible() || m_alpha < 0.1) {
        m_alpha = 0.0;
        show();
        raise();
        m_fadeIn->setStartValue(0.0);
        m_fadeIn->setEndValue(1.0);
        m_fadeIn->start();
    } else {
        // Đang hiển thị (nhấn phím liên tục) → giữ nguyên, không chớp nháy
        m_fadeIn->stop();
        m_alpha = 1.0;
    }

    // Gia hạn 1.5s sau mỗi lần bấm phím
    m_hideTimer->start(kHideDelay);
}

// ---------------------------------------------------------------------------
void OsdWindow::showMuted(bool muted)
{
    showVolume(muted ? 0 : 50, muted);
}

// ---------------------------------------------------------------------------
void OsdWindow::startHideAnimation()
{
    m_fadeIn->stop();
    m_fadeOut->setStartValue(m_alpha);
    m_fadeOut->setEndValue(0.0);
    m_fadeOut->start();
}
