#include "OsdWindow.h"

#include <QApplication>
#include <QHBoxLayout>
#include <QLabel>
#include <QPainter>
#include <QPainterPath>
#include <QProgressBar>
#include <QPropertyAnimation>
#include <QScreen>
#include <QTimer>

// ---------------------------------------------------------------------------
// Hằng số thiết kế (dark theme Hyggshi OS)
// ---------------------------------------------------------------------------
static constexpr int   kOsdWidth      = 320;
static constexpr int   kOsdHeight     = 58;
static constexpr int   kMargin        = 28;      // khoảng cách từ góc màn hình
static constexpr int   kHideDelay     = 1500;    // ms trước khi bắt đầu ẩn
static constexpr int   kFadeDuration  = 160;     // ms cho mỗi animation

static constexpr const char *kBarBg         = "#232630";
static constexpr const char *kBarFill       = "#7c6af7";   // tím Hyggshi
static constexpr const char *kBarFillMuted  = "#4a4d5a";
static constexpr const char *kTextColor     = "#e6e7ea";

// ---------------------------------------------------------------------------
OsdWindow::OsdWindow(QWidget *parent)
    : QWidget(parent, Qt::Window
              | Qt::FramelessWindowHint
              | Qt::WindowStaysOnTopHint
              | Qt::Tool)             // không hiện trên taskbar, không lấy focus
{
    setAttribute(Qt::WA_TranslucentBackground);
    setAttribute(Qt::WA_ShowWithoutActivating);
    setAttribute(Qt::WA_X11NetWmWindowTypeNotification);
    setFixedSize(kOsdWidth, kOsdHeight);

    // ---- Layout ngang đồng bộ ----
    auto *root = new QHBoxLayout(this);
    root->setContentsMargins(16, 0, 16, 0);
    root->setSpacing(12);

    m_iconLabel = new QLabel(this);
    m_iconLabel->setFixedSize(28, 28);
    m_iconLabel->setAlignment(Qt::AlignCenter);
    root->addWidget(m_iconLabel);

    m_bar = new QProgressBar(this);
    m_bar->setRange(0, 100);
    m_bar->setFixedHeight(8);
    m_bar->setTextVisible(false);
    root->addWidget(m_bar, 1);

    m_valueLabel = new QLabel(this);
    m_valueLabel->setFixedWidth(46);
    m_valueLabel->setAlignment(Qt::AlignRight | Qt::AlignVCenter);
    root->addWidget(m_valueLabel);

    applyStyle();

    // ---- Timer ẩn ----
    m_hideTimer = new QTimer(this);
    m_hideTimer->setSingleShot(true);
    connect(m_hideTimer, &QTimer::timeout, this, &OsdWindow::startHideAnimation);

    // ---- Fade-in ----
    m_fadeIn = new QPropertyAnimation(this, "windowOpacity", this);
    m_fadeIn->setDuration(kFadeDuration);
    m_fadeIn->setStartValue(0.0);
    m_fadeIn->setEndValue(0.95);

    // ---- Fade-out ----
    m_fadeOut = new QPropertyAnimation(this, "windowOpacity", this);
    m_fadeOut->setDuration(kFadeDuration);
    m_fadeOut->setStartValue(0.95);
    m_fadeOut->setEndValue(0.0);
    connect(m_fadeOut, &QPropertyAnimation::finished, this, &QWidget::hide);
}

// ---------------------------------------------------------------------------
void OsdWindow::paintEvent(QPaintEvent *)
{
    QPainter p(this);
    p.setRenderHint(QPainter::Antialiasing);

    QRectF r = rect();
    r.adjust(0.5, 0.5, -0.5, -0.5);

    QPainterPath path;
    path.addRoundedRect(r, 16, 16);

    // Nền tối thanh lịch Hyggshi OS
    p.fillPath(path, QColor(0x14, 0x15, 0x19, 245));

    // Viền tinh tế
    p.setPen(QPen(QColor(0x32, 0x36, 0x46, 220), 1.0));
    p.drawPath(path);
}

// ---------------------------------------------------------------------------
void OsdWindow::applyStyle()
{
    setStyleSheet(QStringLiteral(
        "QLabel {"
        "  background: transparent;"
        "  color: %1;"
        "  font-size: 13px;"
        "  font-weight: 600;"
        "  font-family: 'Noto Sans','Ubuntu','Cantarell',sans-serif;"
        "}"
        "QProgressBar {"
        "  background: %2;"
        "  border: none;"
        "  border-radius: 4px;"
        "}"
        "QProgressBar::chunk {"
        "  background: %3;"
        "  border-radius: 4px;"
        "}"
    ).arg(kTextColor, kBarBg, kBarFill));
}

#include <QCursor>
#include <QGuiApplication>

// ---------------------------------------------------------------------------
void OsdWindow::updatePosition()
{
    // Tự động nhận diện màn hình có con trỏ chuột đang hoạt động (Multi-monitor)
    QScreen *screen = QGuiApplication::screenAt(QCursor::pos());
    if (!screen) {
        screen = QApplication::primaryScreen();
    }
    if (!screen) return;

    // availableGeometry() tự động loại trừ phần panel/taskbar của XFCE (tránh bị che khuất)
    const QRect geom = screen->availableGeometry();
    move(geom.right()  - kOsdWidth  - kMargin,
         geom.bottom() - kOsdHeight - kMargin);
}

// ---------------------------------------------------------------------------
void OsdWindow::showVolume(int volume, bool muted)
{
    // Chọn icon
    const char *iconPath = kIconHigh;
    if (muted)            iconPath = kIconMuted;
    else if (volume < 33) iconPath = kIconLow;
    else                  iconPath = kIconHigh;

    m_iconLabel->setPixmap(
        QPixmap(QString::fromLatin1(iconPath)).scaled(
            m_iconLabel->size(), Qt::KeepAspectRatio, Qt::SmoothTransformation));

    // Bar + label
    m_bar->setValue(muted ? 0 : volume);

    // Đổi màu bar nếu muted
    QString barFill = muted ? QString::fromLatin1(kBarFillMuted)
                            : QString::fromLatin1(kBarFill);
    m_bar->setStyleSheet(QStringLiteral(
        "QProgressBar { background: %1; border: none; border-radius:4px; }"
        "QProgressBar::chunk { background: %2; border-radius:4px; }"
    ).arg(kBarBg, barFill));

    m_valueLabel->setText(muted
        ? QStringLiteral("Muted")
        : QStringLiteral("%1%").arg(volume));

    // Dừng fade-out nếu đang ẩn dở
    m_fadeOut->stop();
    m_hideTimer->stop();

    updatePosition();

    // Nếu OSD chưa hiện hoặc đang ẩn -> Fade-in mượt mà
    if (!isVisible() || windowOpacity() < 0.1) {
        setWindowOpacity(0.0);
        show();
        raise();
        m_fadeIn->start();
    } else {
        // Đã đang hiển thị (khi người dùng nhấn phím liên tục) -> giữ nguyên hiển thị không chớp nháy
        m_fadeIn->stop();
        setWindowOpacity(0.95);
        show();
        raise();
    }

    // Luôn gia hạn thêm 1.5 giây sau mỗi lần bấm phím
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
    m_fadeOut->start();
}
