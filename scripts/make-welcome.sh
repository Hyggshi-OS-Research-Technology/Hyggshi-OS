#!/bin/bash
# make-welcome.sh — sinh project "Hyggshi Welcome": app chào mừng đầu tiên
# khi user login lần đầu, viết bằng C++ + Qt (Widgets), có animation trượt
# trang (slide) giữa các bước config nhanh, tương tự GNOME Initial Setup
# (Fedora) / gnome-initial-setup + Ubuntu "Welcome"/"Getting Started".
#
# Script này KHÔNG build app trong lúc ISO build (không phụ thuộc mạng/apt
# ở đây) — nó chỉ ghi ra source code C++/Qt + CMakeLists + packaging vào
# app-for-hyggshi/hyggshi-welcome/. Việc build thật (cmake + qt6) do
# desktop.sh / build-*.sh gọi sau, hoặc chạy tay bằng cờ --build bên dưới.
#
# Cách dùng:
#   ./scripts/make-welcome.sh            # chỉ sinh source code
#   ./scripts/make-welcome.sh --build    # sinh xong rồi cmake build luôn
#   ./scripts/make-welcome.sh --install  # sinh + build + cài vào hệ thống
set -e
[ "$DEBUG_MODE" = "true" ] && set -x

MODE="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$REPO_ROOT/app-for-hyggshi/hyggshi-welcome"

echo "===== Tạo cây thư mục project hyggshi-welcome tại: $APP_DIR ====="
mkdir -p "$APP_DIR/src" "$APP_DIR/resources/icons" "$APP_DIR/packaging"

# ---------------------------------------------------------------------------
# CMakeLists.txt — ưu tiên Qt6, fallback Qt5 (vì build-alpine/build-arch có
# thể chỉ có Qt5 tuỳ thời điểm), AUTOMOC/AUTORCC bật sẵn cho Q_OBJECT + .qrc.
# ---------------------------------------------------------------------------
cat > "$APP_DIR/CMakeLists.txt" <<'CMAKEEOF'
cmake_minimum_required(VERSION 3.16)
project(hyggshi-welcome LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

# Ưu tiên Qt6, fallback Qt5 để build được trên các base distro chưa có Qt6
# (Alpine/Arch có thể lệch phiên bản tuỳ thời điểm build).
find_package(Qt6 QUIET COMPONENTS Widgets)
if(Qt6_FOUND)
  set(QT_VERSION_MAJOR 6)
  set(QT_LIBS Qt6::Widgets)
else()
  find_package(Qt5 REQUIRED COMPONENTS Widgets)
  set(QT_VERSION_MAJOR 5)
  set(QT_LIBS Qt5::Widgets)
endif()

file(GLOB APP_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/src/*.cpp")
file(GLOB APP_HEADERS "${CMAKE_CURRENT_SOURCE_DIR}/src/*.h")

add_executable(hyggshi-welcome ${APP_SOURCES} ${APP_HEADERS} resources/hyggshi-welcome.qrc)

target_link_libraries(hyggshi-welcome PRIVATE ${QT_LIBS})
target_include_directories(hyggshi-welcome PRIVATE src)

install(TARGETS hyggshi-welcome RUNTIME DESTINATION bin)
install(FILES packaging/hyggshi-welcome.desktop DESTINATION share/applications)
install(FILES packaging/hyggshi-welcome-autostart.desktop
        DESTINATION /etc/xdg/autostart
        RENAME hyggshi-welcome.desktop)

# Wallpaper thật cho 2 theme Sáng/Tối — cài vào cùng thư mục
# /usr/share/backgrounds/hyggshi mà branding.sh dùng, để finishSetup() trong
# MainWindow.cpp trỏ tới đường dẫn cố định này lúc runtime (không cần đọc
# lại từ resource .qrc, vì xfconf-query cần path thật trên đĩa).
install(FILES resources/icons/theme-light.png
        DESTINATION /usr/share/backgrounds/hyggshi
        RENAME car-light.png)
install(FILES resources/icons/theme-dark.png
        DESTINATION /usr/share/backgrounds/hyggshi
        RENAME car-Dark.png)
CMAKEEOF

# ---------------------------------------------------------------------------
# resources/hyggshi-welcome.qrc — nhúng logo/wallpaper từ iso-config/branding
# (copy sẵn vào resources/icons để .qrc không phải trỏ ra ngoài project).
#
# car-light.png / car-Dark.png là ảnh preview cho 2 thẻ "Sáng"/"Tối" ở trang
# Chọn giao diện — dùng làm border-image của thẻ (thay swatch màu phẳng) và
# cũng là wallpaper thật sẽ được áp tự động khi người dùng chọn theme đó
# (xem buildThemePage() + finishSetup() bên dưới).
# ---------------------------------------------------------------------------
if [ -f "$REPO_ROOT/iso-config/branding/Logo.png" ]; then
  cp "$REPO_ROOT/iso-config/branding/Logo.png" "$APP_DIR/resources/icons/logo.png"
else
  echo "⚠️  Không thấy iso-config/branding/Logo.png — tạo icon placeholder trống."
  : > "$APP_DIR/resources/icons/logo.png"
fi

if [ -f "$REPO_ROOT/iso-config/branding/car-light.png" ]; then
  cp "$REPO_ROOT/iso-config/branding/car-light.png" "$APP_DIR/resources/icons/theme-light.png"
else
  echo "⚠️  Không thấy iso-config/branding/car-light.png — thẻ 'Sáng' sẽ dùng swatch màu phẳng."
  : > "$APP_DIR/resources/icons/theme-light.png"
fi

if [ -f "$REPO_ROOT/iso-config/branding/car-Dark.png" ]; then
  cp "$REPO_ROOT/iso-config/branding/car-Dark.png" "$APP_DIR/resources/icons/theme-dark.png"
else
  echo "⚠️  Không thấy iso-config/branding/car-Dark.png — thẻ 'Tối' sẽ dùng swatch màu phẳng."
  : > "$APP_DIR/resources/icons/theme-dark.png"
fi

if [ -f "$REPO_ROOT/iso-config/branding/car-auto.png" ]; then
  cp "$REPO_ROOT/iso-config/branding/car-auto.png" "$APP_DIR/resources/icons/theme-auto.png"
else
  echo "⚠️  Không thấy iso-config/branding/car-auto.png — thẻ 'Tự động' sẽ dùng swatch gradient."
  : > "$APP_DIR/resources/icons/theme-auto.png"
fi

cat > "$APP_DIR/resources/hyggshi-welcome.qrc" <<'QRCEOF'
<RCC>
  <qresource prefix="/">
    <file>icons/logo.png</file>
    <file>icons/theme-light.png</file>
    <file>icons/theme-dark.png</file>
    <file>icons/theme-auto.png</file>
  </qresource>
</RCC>
QRCEOF

# ---------------------------------------------------------------------------
# src/SlideStackedWidget.h/.cpp — QStackedWidget tự viết, animate trượt
# ngang + fade khi đổi trang (pattern kinh điển kiểu "SlidingStackedWidget"),
# đây là phần tạo cảm giác "next config nhanh" giống Fedora/Ubuntu.
# ---------------------------------------------------------------------------
cat > "$APP_DIR/src/SlideStackedWidget.h" <<'HEOF'
#pragma once
#include <QStackedWidget>

// QStackedWidget có animation trượt ngang khi chuyển trang bằng slideToIndex().
// forward=true => trang mới trượt vào từ bên phải (Next),
// forward=false => trang mới trượt vào từ bên trái (Back).
class SlideStackedWidget : public QStackedWidget {
  Q_OBJECT
 public:
  explicit SlideStackedWidget(QWidget *parent = nullptr);
  void slideToIndex(int index);
  bool isAnimating() const { return m_animating; }

 signals:
  void animationFinished();

 private:
  bool m_animating = false;
  int m_durationMs = 380;
};
HEOF

cat > "$APP_DIR/src/SlideStackedWidget.cpp" <<'CEOF'
#include "SlideStackedWidget.h"
#include <QPropertyAnimation>
#include <QParallelAnimationGroup>
#include <QEasingCurve>
#include <QGraphicsOpacityEffect>

SlideStackedWidget::SlideStackedWidget(QWidget *parent)
    : QStackedWidget(parent) {}

void SlideStackedWidget::slideToIndex(int index) {
  if (m_animating || index == currentIndex() || index < 0 || index >= count()) {
    return;
  }

  const bool forward = index > currentIndex();
  QWidget *current = currentWidget();
  QWidget *next = widget(index);
  if (!current || !next) return;

  const int w = width();
  const QPoint startPos(forward ? w : -w, 0);
  const QPoint endPosCurrent(forward ? -w : w, 0);

  next->setGeometry(0, 0, w, height());
  next->move(startPos);
  next->show();
  next->raise();

  // Fade nhẹ trên trang mới để chuyển động mềm hơn, không chỉ trượt cứng.
  auto *fx = new QGraphicsOpacityEffect(next);
  next->setGraphicsEffect(fx);
  auto *fadeAnim = new QPropertyAnimation(fx, "opacity", this);
  fadeAnim->setDuration(m_durationMs);
  fadeAnim->setStartValue(0.35);
  fadeAnim->setEndValue(1.0);
  fadeAnim->setEasingCurve(QEasingCurve::OutCubic);

  auto *slideNext = new QPropertyAnimation(next, "pos", this);
  slideNext->setDuration(m_durationMs);
  slideNext->setEasingCurve(QEasingCurve::OutCubic);
  slideNext->setStartValue(startPos);
  slideNext->setEndValue(QPoint(0, 0));

  auto *slideCurrent = new QPropertyAnimation(current, "pos", this);
  slideCurrent->setDuration(m_durationMs);
  slideCurrent->setEasingCurve(QEasingCurve::OutCubic);
  slideCurrent->setStartValue(QPoint(0, 0));
  slideCurrent->setEndValue(endPosCurrent);

  m_animating = true;
  auto *group = new QParallelAnimationGroup(this);
  group->addAnimation(fadeAnim);
  group->addAnimation(slideNext);
  group->addAnimation(slideCurrent);

  connect(group, &QParallelAnimationGroup::finished, this,
          [this, index, current, next]() {
            next->setGraphicsEffect(nullptr);
            setCurrentIndex(index);
            current->move(0, 0);
            m_animating = false;
            emit animationFinished();
          });
  group->start(QAbstractAnimation::DeleteWhenStopped);
}
CEOF

# ---------------------------------------------------------------------------
# src/MainWindow.h/.cpp — wizard chính: dot progress + Back/Skip/Next,
# 5 trang: Welcome, Ngôn ngữ, Giao diện, Tính năng nổi bật (carousel), Xong.
# ---------------------------------------------------------------------------
cat > "$APP_DIR/src/MainWindow.h" <<'HEOF'
#pragma once
#include <QMainWindow>
#include <QVector>
#include <QLabel>
#include <QPushButton>
#include <QButtonGroup>
#include <QCheckBox>
#include <QTimer>
#include "SlideStackedWidget.h"

class MainWindow : public QMainWindow {
  Q_OBJECT
 public:
  explicit MainWindow(QWidget *parent = nullptr);

 private:
  struct FeatureSlide {
    QString icon;
    QString title;
    QString desc;
  };

  SlideStackedWidget *m_stack = nullptr;
  QVector<QLabel *> m_dots;
  QPushButton *m_backBtn = nullptr;
  QPushButton *m_skipBtn = nullptr;
  QPushButton *m_nextBtn = nullptr;
  QButtonGroup *m_themeGroup = nullptr;
  QString m_selectedTheme = "auto";
  // Đường dẫn wallpaper thật (đã cài ở /usr/share/backgrounds/hyggshi/) ứng
  // với theme đang chọn — rỗng nếu theme đó không có wallpaper riêng.
  QString m_selectedWallpaper = "/usr/share/backgrounds/hyggshi/car-light.png";
  QCheckBox *m_dontAskAgainChk = nullptr;

  QTimer *m_carouselTimer = nullptr;
  QVector<FeatureSlide> m_features;
  int m_featureIndex = 0;
  QLabel *m_featureIcon = nullptr;
  QLabel *m_featureTitle = nullptr;
  QLabel *m_featureDesc = nullptr;
  QVector<QLabel *> m_featureDots;

  QWidget *buildWelcomePage();
  QWidget *buildLanguagePage();
  QWidget *buildThemePage();
  QWidget *buildFeaturesPage();
  QWidget *buildFinishPage();
  QWidget *buildNavBar();

  void updateNavState();
  void updateDots(int index);
  void goNext();
  void goBack();
  void finishSetup();
  void applyWallpaper(const QString &wallpaperPath);
  void showFeatureSlide(int index);
  void advanceCarousel();
};
HEOF

cat > "$APP_DIR/src/MainWindow.cpp" <<'CEOF'
#include "MainWindow.h"
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QFrame>
#include <QComboBox>
#include <QRadioButton>
#include <QGraphicsOpacityEffect>
#include <QPropertyAnimation>
#include <QApplication>
#include <QScreen>
#include <QDir>
#include <QFile>
#include <QStandardPaths>
#include <QProcess>
#include <QToolButton>

static QLabel *makeDot(bool active) {
  auto *dot = new QLabel;
  dot->setFixedSize(9, 9);
  dot->setStyleSheet(QString(
      "border-radius:4px; background:%1;")
      .arg(active ? "#5aa9ff" : "#3a3f4b"));
  return dot;
}

MainWindow::MainWindow(QWidget *parent) : QMainWindow(parent) {
  setWindowTitle(tr("Chào mừng đến với Hyggshi OS"));
  setFixedSize(860, 560);

  auto *central = new QWidget;
  auto *rootLayout = new QVBoxLayout(central);
  rootLayout->setContentsMargins(0, 0, 0, 0);
  rootLayout->setSpacing(0);

  m_stack = new SlideStackedWidget;
  m_stack->addWidget(buildWelcomePage());
  m_stack->addWidget(buildLanguagePage());
  m_stack->addWidget(buildThemePage());
  m_stack->addWidget(buildFeaturesPage());
  m_stack->addWidget(buildFinishPage());

  rootLayout->addWidget(m_stack, 1);
  rootLayout->addWidget(buildNavBar(), 0);

  setCentralWidget(central);
  updateNavState();

  if (QScreen *scr = QGuiApplication::primaryScreen()) {
    const QRect r = scr->availableGeometry();
    move(r.center() - rect().center());
  }
}

// ---- Trang 1: Welcome ------------------------------------------------------
QWidget *MainWindow::buildWelcomePage() {
  auto *page = new QWidget;
  auto *layout = new QVBoxLayout(page);
  layout->setAlignment(Qt::AlignCenter);
  layout->setSpacing(14);

  auto *logo = new QLabel;
  logo->setPixmap(QPixmap(":/icons/logo.png").scaled(
      96, 96, Qt::KeepAspectRatio, Qt::SmoothTransformation));
  logo->setAlignment(Qt::AlignCenter);

  auto *title = new QLabel(tr("Chào mừng đến với Hyggshi OS"));
  title->setAlignment(Qt::AlignCenter);
  title->setStyleSheet("font-size:24px; font-weight:600; color:#f2f3f5;");

  auto *subtitle = new QLabel(
      tr("Chỉ mất vài bước để cấu hình nhanh máy của bạn.\n"
         "Bạn có thể đổi lại bất cứ lúc nào trong Cài đặt."));
  subtitle->setAlignment(Qt::AlignCenter);
  subtitle->setStyleSheet("font-size:13px; color:#9aa0ab;");
  subtitle->setWordWrap(true);

  layout->addStretch(1);
  layout->addWidget(logo);
  layout->addWidget(title);
  layout->addWidget(subtitle);
  layout->addStretch(2);
  return page;
}

// ---- Trang 2: Ngôn ngữ & Bàn phím ------------------------------------------
QWidget *MainWindow::buildLanguagePage() {
  auto *page = new QWidget;
  auto *layout = new QVBoxLayout(page);
  layout->setContentsMargins(70, 60, 70, 40);
  layout->setSpacing(18);

  auto *title = new QLabel(tr("Ngôn ngữ & Bàn phím"));
  title->setStyleSheet("font-size:20px; font-weight:600; color:#f2f3f5;");

  auto *langLabel = new QLabel(tr("Ngôn ngữ hiển thị"));
  langLabel->setStyleSheet("color:#c7cad1; font-size:12px;");
  auto *langBox = new QComboBox;
  langBox->addItems({tr("Tiếng Việt"), tr("English"), tr("日本語"), tr("한국어")});

  auto *kbLabel = new QLabel(tr("Bố cục bàn phím"));
  kbLabel->setStyleSheet("color:#c7cad1; font-size:12px; margin-top:10px;");
  auto *kbBox = new QComboBox;
  kbBox->addItems({"Vietnamese (TELEX)", "English (US)", "English (UK)"});

  auto *note = new QLabel(
      tr("Có thể đổi lại trong Cài đặt hệ thống > Vùng & Ngôn ngữ."));
  note->setStyleSheet("color:#6f7480; font-size:11px; margin-top:14px;");
  note->setWordWrap(true);

  layout->addWidget(title);
  layout->addSpacing(8);
  layout->addWidget(langLabel);
  layout->addWidget(langBox);
  layout->addWidget(kbLabel);
  layout->addWidget(kbBox);
  layout->addWidget(note);
  layout->addStretch(1);
  return page;
}

// ---- Trang 3: Giao diện (Light/Dark/Auto) ----------------------------------
QWidget *MainWindow::buildThemePage() {
  auto *page = new QWidget;
  auto *layout = new QVBoxLayout(page);
  layout->setContentsMargins(70, 60, 70, 40);
  layout->setSpacing(18);

  auto *title = new QLabel(tr("Chọn giao diện"));
  title->setStyleSheet("font-size:20px; font-weight:600; color:#f2f3f5;");

  auto *cardsRow = new QHBoxLayout;
  cardsRow->setSpacing(16);
  m_themeGroup = new QButtonGroup(page);

  // "background" dùng khi ảnh preview không nhúng được lúc build (file rỗng
  // placeholder — xem phần copy resource phía trên) — fallback về swatch
  // màu phẳng để card không bị vỡ layout.
  // "wallpaper" là đường dẫn THẬT trên đĩa (được CMake install() vào
  // /usr/share/backgrounds/hyggshi/) — dùng làm fallback áp 1 lần lúc
  // finishSetup() khi hyggshi-theme-daemon CHƯA được cài (xem finishSetup()
  // + scripts/make-theme-daemon.sh); khi daemon có sẵn, việc áp wallpaper
  // theo giờ (cho "auto") hay theo theme (cho "light"/"dark") do daemon lo,
  // welcome chỉ cần ghi lựa chọn vào xfconf channel "hyggshi".
  struct ThemeOpt { QString id, label, background, wallpaper; };
  const QVector<ThemeOpt> opts = {
      {"light", tr("Sáng"), "#f4f5f7",
       "/usr/share/backgrounds/hyggshi/car-light.png"},
      {"dark", tr("Tối"), "#1b1d23",
       "/usr/share/backgrounds/hyggshi/car-Dark.png"},
      {"auto", tr("Tự động"),
       "qlineargradient(x1:0,y1:0,x2:1,y2:0, stop:0 #f4f5f7, stop:1 #1b1d23)",
       "/usr/share/backgrounds/hyggshi/car-light.png"},
  };

  for (int i = 0; i < opts.size(); ++i) {
    const auto &opt = opts[i];
    auto *card = new QPushButton;
    card->setCheckable(true);
    card->setChecked(opt.id == "auto");
    card->setFixedSize(150, 110);
    card->setCursor(Qt::PointingHandCursor);
    card->setText("\n\n" + opt.label);

    // Cả 3 thẻ đều hiện thumbnail wallpaper thật (car-light/car-Dark/car-auto)
    // làm nền qua border-image, chữ trắng cho dễ đọc trên ảnh.
    const QString bodyStyle =
        QString("border-image: url(:/icons/theme-%1.png) 0 0 0 0 stretch stretch;"
                 " color:#ffffff;").arg(opt.id);

    card->setStyleSheet(QString(
        "QPushButton { border-radius:10px; border:2px solid #2c2f38;"
        " font-weight:600; %1 }"
        "QPushButton:checked { border:2px solid #5aa9ff; }")
        .arg(bodyStyle));
    m_themeGroup->addButton(card, i);
    connect(card, &QPushButton::clicked, this, [this, opt]() {
      m_selectedTheme = opt.id;
      m_selectedWallpaper = opt.wallpaper;
    });
    cardsRow->addWidget(card);
  }

  auto *note = new QLabel(
      tr("Áp dụng cho toàn hệ thống sau khi hoàn tất — hình nền sẽ tự đổi theo giao diện bạn chọn."
         " Chế độ Tự động chuyển Sáng/Tối theo giờ (mặc định 6:00 và 18:00)."));
  note->setWordWrap(true);
  note->setStyleSheet("color:#6f7480; font-size:11px; margin-top:10px;");

  layout->addWidget(title);
  layout->addSpacing(8);
  layout->addLayout(cardsRow);
  layout->addWidget(note);
  layout->addStretch(1);
  return page;
}

// ---- Trang 4: Tính năng nổi bật (carousel tự chạy) -------------------------
QWidget *MainWindow::buildFeaturesPage() {
  m_features = {
      {"🚀", tr("Khởi động nhanh"), tr("Hyggshi OS tối ưu boot time và tài nguyên nền cho trải nghiệm mượt mà.")},
      {"🎨", tr("Giao diện tuỳ biến"), tr("Đổi theme, icon, panel dễ dàng ngay trong Cài đặt hệ thống.")},
      {"🧩", tr("Hệ sinh thái riêng"), tr("nexfetch, HOSC, HyggshiDE — được xây dựng riêng cho Hyggshi OS.")},
      {"🔒", tr("An toàn theo mặc định"), tr("Cấu hình bảo mật hợp lý sẵn có, không cần chỉnh tay.")},
  };

  auto *page = new QWidget;
  auto *layout = new QVBoxLayout(page);
  layout->setContentsMargins(70, 50, 70, 30);
  layout->setSpacing(10);
  layout->setAlignment(Qt::AlignCenter);

  auto *title = new QLabel(tr("Tính năng nổi bật"));
  title->setStyleSheet("font-size:20px; font-weight:600; color:#f2f3f5;");
  title->setAlignment(Qt::AlignHCenter);

  m_featureIcon = new QLabel;
  m_featureIcon->setAlignment(Qt::AlignCenter);
  m_featureIcon->setStyleSheet("font-size:46px;");

  m_featureTitle = new QLabel;
  m_featureTitle->setAlignment(Qt::AlignCenter);
  m_featureTitle->setStyleSheet("font-size:16px; font-weight:600; color:#f2f3f5;");

  m_featureDesc = new QLabel;
  m_featureDesc->setAlignment(Qt::AlignCenter);
  m_featureDesc->setWordWrap(true);
  m_featureDesc->setStyleSheet("font-size:12px; color:#9aa0ab;");
  m_featureDesc->setFixedWidth(420);

  auto *navRow = new QHBoxLayout;
  navRow->setAlignment(Qt::AlignCenter);
  navRow->setSpacing(6);
  auto *prevArrow = new QToolButton;
  prevArrow->setText("◀");
  prevArrow->setAutoRaise(true);
  auto *dotsRow = new QHBoxLayout;
  dotsRow->setSpacing(6);
  for (int i = 0; i < m_features.size(); ++i) {
    auto *dot = makeDot(i == 0);
    m_featureDots.push_back(dot);
    dotsRow->addWidget(dot);
  }
  auto *nextArrow = new QToolButton;
  nextArrow->setText("▶");
  nextArrow->setAutoRaise(true);

  navRow->addWidget(prevArrow);
  navRow->addLayout(dotsRow);
  navRow->addWidget(nextArrow);

  connect(prevArrow, &QToolButton::clicked, this, [this]() {
    m_carouselTimer->stop();
    showFeatureSlide((m_featureIndex - 1 + m_features.size()) % m_features.size());
    m_carouselTimer->start();
  });
  connect(nextArrow, &QToolButton::clicked, this, [this]() {
    m_carouselTimer->stop();
    showFeatureSlide((m_featureIndex + 1) % m_features.size());
    m_carouselTimer->start();
  });

  layout->addWidget(title);
  layout->addSpacing(6);
  layout->addWidget(m_featureIcon);
  layout->addWidget(m_featureTitle);
  layout->addWidget(m_featureDesc, 0, Qt::AlignHCenter);
  layout->addSpacing(10);
  layout->addLayout(navRow);

  showFeatureSlide(0);

  m_carouselTimer = new QTimer(this);
  m_carouselTimer->setInterval(3800);
  connect(m_carouselTimer, &QTimer::timeout, this, &MainWindow::advanceCarousel);
  m_carouselTimer->start();

  return page;
}

void MainWindow::showFeatureSlide(int index) {
  m_featureIndex = index;
  const auto &f = m_features[index];

  // Crossfade nội dung slide bằng QGraphicsOpacityEffect thay vì đổi đột ngột.
  auto *fx = new QGraphicsOpacityEffect(m_featureDesc);
  m_featureDesc->setGraphicsEffect(fx);
  m_featureIcon->setText(f.icon);
  m_featureTitle->setText(f.title);
  m_featureDesc->setText(f.desc);

  auto *anim = new QPropertyAnimation(fx, "opacity", this);
  anim->setDuration(300);
  anim->setStartValue(0.0);
  anim->setEndValue(1.0);
  anim->setEasingCurve(QEasingCurve::OutCubic);
  anim->start(QAbstractAnimation::DeleteWhenStopped);

  for (int i = 0; i < m_featureDots.size(); ++i) {
    m_featureDots[i]->setStyleSheet(QString(
        "border-radius:4px; background:%1;")
        .arg(i == index ? "#5aa9ff" : "#3a3f4b"));
  }
}

void MainWindow::advanceCarousel() {
  showFeatureSlide((m_featureIndex + 1) % m_features.size());
}

// ---- Trang 5: Hoàn tất ------------------------------------------------------
QWidget *MainWindow::buildFinishPage() {
  auto *page = new QWidget;
  auto *layout = new QVBoxLayout(page);
  layout->setAlignment(Qt::AlignCenter);
  layout->setSpacing(14);

  auto *icon = new QLabel("🎉");
  icon->setAlignment(Qt::AlignCenter);
  icon->setStyleSheet("font-size:48px;");

  auto *title = new QLabel(tr("Đã sẵn sàng!"));
  title->setAlignment(Qt::AlignCenter);
  title->setStyleSheet("font-size:22px; font-weight:600; color:#f2f3f5;");

  auto *desc = new QLabel(tr("Cấu hình ban đầu đã xong. Chúc bạn dùng Hyggshi OS vui vẻ."));
  desc->setAlignment(Qt::AlignCenter);
  desc->setStyleSheet("font-size:13px; color:#9aa0ab;");
  desc->setWordWrap(true);

  m_dontAskAgainChk = new QCheckBox(tr("Không hỏi lại lần sau"));
  m_dontAskAgainChk->setChecked(true);
  m_dontAskAgainChk->setCursor(Qt::PointingHandCursor);
  m_dontAskAgainChk->setStyleSheet(
      "QCheckBox { color:#9aa0ab; font-size:12px; spacing:8px; }"
      "QCheckBox::indicator { width:16px; height:16px; border-radius:4px;"
      " border:1px solid #3a3f4b; background:#1e2027; }"
      "QCheckBox::indicator:checked { background:#5aa9ff; border:1px solid #5aa9ff; }");

  layout->addStretch(1);
  layout->addWidget(icon);
  layout->addWidget(title);
  layout->addWidget(desc);
  layout->addSpacing(10);
  layout->addWidget(m_dontAskAgainChk, 0, Qt::AlignCenter);
  layout->addStretch(2);
  return page;
}

// ---- Thanh điều hướng dưới cùng ---------------------------------------------
QWidget *MainWindow::buildNavBar() {
  auto *bar = new QFrame;
  bar->setStyleSheet("background:#1a1c22; border-top:1px solid #2a2d35;");
  bar->setFixedHeight(64);

  auto *layout = new QHBoxLayout(bar);
  layout->setContentsMargins(24, 0, 24, 0);

  m_backBtn = new QPushButton(tr("Quay lại"));
  m_backBtn->setFlat(true);
  m_backBtn->setCursor(Qt::PointingHandCursor);
  connect(m_backBtn, &QPushButton::clicked, this, &MainWindow::goBack);

  auto *dotsRow = new QHBoxLayout;
  dotsRow->setSpacing(7);
  dotsRow->setAlignment(Qt::AlignCenter);
  for (int i = 0; i < 5; ++i) {
    auto *dot = makeDot(i == 0);
    m_dots.push_back(dot);
    dotsRow->addWidget(dot);
  }

  m_skipBtn = new QPushButton(tr("Bỏ qua"));
  m_skipBtn->setFlat(true);
  m_skipBtn->setCursor(Qt::PointingHandCursor);
  connect(m_skipBtn, &QPushButton::clicked, this, &MainWindow::finishSetup);

  m_nextBtn = new QPushButton(tr("Tiếp tục"));
  m_nextBtn->setCursor(Qt::PointingHandCursor);
  m_nextBtn->setStyleSheet(
      "QPushButton { background:#5aa9ff; color:#0d1017; font-weight:600;"
      " border-radius:8px; padding:8px 22px; }"
      "QPushButton:hover { background:#77b9ff; }");
  connect(m_nextBtn, &QPushButton::clicked, this, &MainWindow::goNext);

  layout->addWidget(m_backBtn);
  layout->addStretch(1);
  layout->addLayout(dotsRow);
  layout->addStretch(1);
  layout->addWidget(m_skipBtn);
  layout->addWidget(m_nextBtn);
  return bar;
}

void MainWindow::updateDots(int index) {
  for (int i = 0; i < m_dots.size(); ++i) {
    m_dots[i]->setStyleSheet(QString(
        "border-radius:4px; background:%1;")
        .arg(i == index ? "#5aa9ff" : "#3a3f4b"));
  }
}

void MainWindow::updateNavState() {
  const int index = m_stack->currentIndex();
  const bool isLast = index == m_stack->count() - 1;
  m_backBtn->setEnabled(index > 0);
  m_backBtn->setVisible(index > 0);
  m_skipBtn->setVisible(!isLast);
  m_nextBtn->setText(isLast ? tr("Bắt đầu sử dụng") : tr("Tiếp tục"));
  updateDots(index);
}

void MainWindow::goNext() {
  const int index = m_stack->currentIndex();
  if (index == m_stack->count() - 1) {
    finishSetup();
    return;
  }
  m_stack->slideToIndex(index + 1);
  QTimer::singleShot(0, this, &MainWindow::updateNavState);
}

void MainWindow::goBack() {
  const int index = m_stack->currentIndex();
  if (index == 0) return;
  m_stack->slideToIndex(index - 1);
  QTimer::singleShot(0, this, &MainWindow::updateNavState);
}

void MainWindow::finishSetup() {
  // Áp theme đã chọn — best-effort, không fail nếu xfconf-query không có
  // sẵn (app có thể chạy trên DE khác XFCE trong tương lai).
  if (QStandardPaths::findExecutable("xfconf-query") != "") {
    QString themeName = m_selectedTheme == "dark" ? "Adwaita-dark"
                       : m_selectedTheme == "light" ? "Adwaita"
                       : "Adwaita"; // "auto" tạm map về theme sáng mặc định
    QProcess::execute("xfconf-query",
        {"-c", "xsettings", "-p", "/Net/ThemeName", "-s", themeName});
  }

  // Ghi lựa chọn (Sáng/Tối/Tự động) vào channel xfconf riêng "hyggshi" —
  // nếu hyggshi-theme-daemon (scripts/make-theme-daemon.sh) đang chạy, nó
  // lắng nghe property-changed trên channel này và tự áp lại wallpaper
  // ngay lập tức (đúng theo giờ hiện tại nếu là "auto"), không cần gọi gì
  // thêm ở đây — xem README của hyggshi-theme-daemon để biết chi tiết.
  if (QStandardPaths::findExecutable("xfconf-query") != "") {
    QProcess::execute("xfconf-query",
        {"-c", "hyggshi", "-p", "/theme/mode", "-n", "-t", "string",
         "-s", m_selectedTheme});
  }

  // Daemon chưa được cài (vd. ISO chưa chạy make-theme-daemon.sh, hoặc bị
  // gỡ) — fallback về cách cũ: tự áp wallpaper MỘT LẦN ngay tại đây. "auto"
  // sẽ tạm hiện đúng wallpaper Sáng cho tới khi có daemon lo phần đổi theo
  // giờ, thay vì không đổi gì cả.
  const bool daemonInstalled =
      QFile::exists("/usr/bin/hyggshi-theme-daemon") ||
      QFile::exists("/usr/local/bin/hyggshi-theme-daemon");
  if (!daemonInstalled) {
    applyWallpaper(m_selectedWallpaper);
  }

  // Đánh dấu đã hoàn tất welcome để autostart không hiện lại lần sau —
  // CHỈ khi người dùng đã tick "Không hỏi lại lần sau" ở trang Xong.
  // Nếu m_dontAskAgainChk == nullptr (người dùng bấm "Bỏ qua" trước khi
  // vào tới trang Xong) thì coi như đồng ý mặc định, giống hành vi cũ.
  const bool dontAskAgain =
      m_dontAskAgainChk == nullptr || m_dontAskAgainChk->isChecked();

  const QString cfgDir = QStandardPaths::writableLocation(
      QStandardPaths::GenericConfigLocation) + "/hyggshi";
  QDir().mkpath(cfgDir);
  QFile marker(cfgDir + "/welcome-shown");
  if (dontAskAgain) {
    if (marker.open(QIODevice::WriteOnly)) {
      marker.write("1");
      marker.close();
    }
  } else if (marker.exists()) {
    // Người dùng bỏ tick -> xoá marker cũ (nếu có) để welcome hiện lại
    // ở lần đăng nhập kế tiếp.
    marker.remove();
  }

  qApp->quit();
}

// Áp wallpaper theo theme đã chọn — best-effort, không fail nếu thiếu file
// hoặc thiếu xfconf-query, giống style của finishSetup() ở trên.
//
// Ưu tiên gọi lại /usr/local/bin/hyggshi-set-wallpaper.sh (do branding.sh
// cài lúc build ISO) thay vì tự dò tên monitor trong C++, vì script đó đã
// xử lý sẵn race condition lúc login + dò đúng tên monitor thật qua xrandr
// (monitor0 không đúng trên mọi máy/VM, xem ghi chú trong branding.sh).
// Script nhận tham số đường dẫn wallpaper tuỳ chọn, mặc định vẫn là
// wallpaper.png nếu gọi không kèm tham số (không phá hành vi cũ ở lúc login).
void MainWindow::applyWallpaper(const QString &wallpaperPath) {
  if (wallpaperPath.isEmpty() || !QFile::exists(wallpaperPath)) {
    return;
  }

  const QString wallScript = "/usr/local/bin/hyggshi-set-wallpaper.sh";
  if (QFile::exists(wallScript)) {
    QProcess::startDetached(wallScript, {wallpaperPath});
    return;
  }

  // Fallback tối giản khi chạy ngoài ISO đã build đầy đủ (vd. build tay
  // bằng --install để test riêng app hyggshi-welcome): set thẳng property
  // monitor0 mặc định, không dò monitor thật như script trên.
  if (QStandardPaths::findExecutable("xfconf-query") != "") {
    QProcess::execute("xfconf-query",
        {"-c", "xfce4-desktop", "-p",
         "/backdrop/screen0/monitor0/workspace0/last-image",
         "-n", "-t", "string", "-s", wallpaperPath});
    QProcess::execute("xfconf-query",
        {"-c", "xfce4-desktop", "-p",
         "/backdrop/screen0/monitor0/workspace0/image-style",
         "-n", "-t", "int", "-s", "5"});
  }
}
CEOF

# ---------------------------------------------------------------------------
# src/main.cpp — entry point + stylesheet nền tối phẳng (đồng bộ style
# "flat colors" đã dùng ở Cloudar Browser trong hệ sinh thái Hyggshi).
# ---------------------------------------------------------------------------
cat > "$APP_DIR/src/main.cpp" <<'CEOF'
#include <QApplication>
#include <QFile>
#include <QStandardPaths>
#include "MainWindow.h"

int main(int argc, char *argv[]) {
  QApplication app(argc, argv);
  QApplication::setApplicationName("Hyggshi Welcome");
  QApplication::setOrganizationName("Hyggshi OS Foundation");

  // Nếu đã chạy welcome rồi (marker file tồn tại) thì thoát ngay — để
  // autostart entry có thể để nguyên trong /etc/xdg/autostart mà không
  // hiện lại app ở các lần login sau.
  const QString marker = QStandardPaths::writableLocation(
      QStandardPaths::GenericConfigLocation) + "/hyggshi/welcome-shown";
  if (QFile::exists(marker) &&
      qgetenv("HYGGSHI_WELCOME_FORCE") != "1") {
    return 0;
  }

  app.setStyleSheet(
      "QMainWindow, QWidget { background:#141519; color:#e6e7ea;"
      " font-family:'Noto Sans','Ubuntu','Cantarell',sans-serif; }"
      "QPushButton { background:#22242b; color:#e6e7ea; border:none;"
      " border-radius:6px; padding:7px 14px; }"
      "QPushButton:hover { background:#2b2e36; }"
      "QComboBox { background:#1e2027; border:1px solid #2c2f38;"
      " border-radius:6px; padding:5px 8px; }");

  MainWindow window;
  window.show();
  return app.exec();
}
CEOF

# ---------------------------------------------------------------------------
# packaging/*.desktop
# ---------------------------------------------------------------------------
cat > "$APP_DIR/packaging/hyggshi-welcome.desktop" <<'DEOF'
[Desktop Entry]
Type=Application
Name=Hyggshi Welcome
Name[vi]=Chào mừng Hyggshi
Comment=Cấu hình nhanh Hyggshi OS lần đầu sử dụng
Exec=hyggshi-welcome
Icon=hyggshi-welcome
Terminal=false
Categories=System;Settings;
DEOF

cat > "$APP_DIR/packaging/hyggshi-welcome-autostart.desktop" <<'DEOF'
[Desktop Entry]
Type=Application
Name=Hyggshi Welcome
Exec=hyggshi-welcome
Icon=hyggshi-welcome
Terminal=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Comment=Hiện wizard chào mừng ở lần đăng nhập đầu tiên (tự thoát nếu đã chạy rồi)
DEOF

cat > "$APP_DIR/README.md" <<'MDEOF'
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
MDEOF

echo "===== Đã sinh xong source code tại $APP_DIR ====="

# ---------------------------------------------------------------------------
# --build / --install: cấu hình + build thật bằng cmake, cần Qt dev sẵn trên
# máy build. Không phải phần bắt buộc của ISO build nên để opt-in qua cờ.
# ---------------------------------------------------------------------------
if [ "$MODE" = "--build" ] || [ "$MODE" = "--install" ]; then
  if ! command -v cmake > /dev/null 2>&1; then
    echo "LỖI: cần cmake để build. Cài: sudo apt-get install -y cmake build-essential qt6-base-dev" >&2
    exit 1
  fi
  echo "===== cmake configure + build (Release) ====="
  cmake -S "$APP_DIR" -B "$APP_DIR/build" -DCMAKE_BUILD_TYPE=Release
  cmake --build "$APP_DIR/build" -j"$(nproc)"
  echo "===== Build xong: $APP_DIR/build/hyggshi-welcome ====="
fi

if [ "$MODE" = "--install" ]; then
  echo "===== Cài vào hệ thống (cần sudo) ====="
  sudo cmake --install "$APP_DIR/build"
  echo "Đã cài hyggshi-welcome + desktop entry + autostart."
fi
