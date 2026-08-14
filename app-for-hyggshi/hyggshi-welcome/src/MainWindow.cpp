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
#include <QTextStream>

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
  // Áp GTK theme (light/dark) đã chọn — best-effort, dò đúng cơ chế theo DE
  // đang chạy thay vì hardcode xfconf/XFCE. gsettings dùng chung schema
  // "interface" trên GNOME/Cinnamon/MATE (đều nền GSettings/dconf); XFCE
  // dùng riêng xfconf channel "xsettings".
  const QString xdgDesktop =
      qEnvironmentVariable("XDG_CURRENT_DESKTOP").toLower();
  QString themeName = m_selectedTheme == "dark" ? "Adwaita-dark"
                     : m_selectedTheme == "light" ? "Adwaita"
                     : "Adwaita"; // "auto" tạm map về theme sáng mặc định

  if (xdgDesktop.contains("xfce")) {
    if (QStandardPaths::findExecutable("xfconf-query") != "") {
      QProcess::execute("xfconf-query",
          {"-c", "xsettings", "-p", "/Net/ThemeName", "-s", themeName});
    }
  } else if (QStandardPaths::findExecutable("gsettings") != "") {
    // GNOME/Cinnamon/MATE đều đọc gtk-theme qua gsettings, chỉ khác schema
    // "interface". Best-effort: gọi cả hai nhánh phổ biến nhất, nhánh nào
    // schema không tồn tại thì gsettings tự lặng lẽ trả lỗi (không fail app).
    if (xdgDesktop.contains("cinnamon")) {
      QProcess::execute("gsettings",
          {"set", "org.cinnamon.desktop.interface", "gtk-theme", themeName});
    } else if (xdgDesktop.contains("mate")) {
      QProcess::execute("gsettings",
          {"set", "org.mate.interface", "gtk-theme", themeName});
    } else {
      QProcess::execute("gsettings",
          {"set", "org.gnome.desktop.interface", "gtk-theme", themeName});
    }
  }

  // Ghi lựa chọn (Sáng/Tối/Tự động) vào 2 nơi để KHỚP với cả 2 cơ chế đổi
  // theme tự động đang có trong repo, dùng cơ chế nào tại thời điểm build
  // (WELCOME_WIZARD có thể đi kèm THEME_DAEMON hoặc AUTO_THEME) không quan
  // trọng, welcome không cần biết:
  //  1) xfconf channel "hyggshi" — đọc bởi hyggshi-theme-daemon (C++/xfconf,
  //     scripts/make-theme-daemon.sh), best-effort nếu có xfconf-query.
  //  2) ~/.config/hyggshi/theme.conf (KEY=VALUE, MODE=...) — đọc bởi
  //     hyggshi-auto-theme (bash + systemd timer, scripts/make-auto-theme.sh,
  //     phương án nhẹ mặc định). BUG CŨ: welcome trước đây CHỈ ghi qua
  //     xfconf, nên lựa chọn trong welcome không hề tới được
  //     hyggshi-auto-theme (script đó chỉ source theme.conf, không đọc
  //     xfconf) — chọn "Tối" trong welcome nhưng auto-theme vẫn tự đổi theo
  //     giờ như thể user chưa chọn gì.
  if (QStandardPaths::findExecutable("xfconf-query") != "") {
    QProcess::execute("xfconf-query",
        {"-c", "hyggshi", "-p", "/theme/mode", "-n", "-t", "string",
         "-s", m_selectedTheme});
  }

  const QString userCfgDir = QStandardPaths::writableLocation(
      QStandardPaths::GenericConfigLocation) + "/hyggshi";
  QDir().mkpath(userCfgDir);
  QFile userThemeConf(userCfgDir + "/theme.conf");
  if (userThemeConf.open(QIODevice::WriteOnly | QIODevice::Text)) {
    QTextStream out(&userThemeConf);
    out << "# Ghi tự động bởi hyggshi-welcome — xem /etc/hyggshi/theme.conf"
           " cho mô tả đầy đủ các key.\n";
    out << "MODE=" << m_selectedTheme << "\n";
    userThemeConf.close();
  }

  // LUÔN áp wallpaper MỘT LẦN ngay tại đây, bất kể hyggshi-theme-daemon đã
  // được cài hay chưa. Trước đây chỗ này chỉ gọi applyWallpaper() khi
  // KHÔNG tìm thấy binary daemon trên đĩa (QFile::exists), với giả định
  // "nếu daemon có cài thì tự nó sẽ đổi wallpaper qua property-changed".
  // Vấn đề: daemon chạy qua systemd --user (WantedBy=graphical-session.
  // target), khởi động gần như SONG SONG với autostart của hyggshi-welcome
  // — không có gì đảm bảo nó đã start + kết nối signal xong đúng lúc
  // welcome ghi property, nhất là khi người dùng bấm "Bỏ qua"/"Tiếp tục"
  // rất nhanh để hoàn tất welcome ngay (start nhanh). Nếu daemon chưa kịp
  // chạy tại thời điểm đó, hình nền sẽ KHÔNG đổi ngay như mong đợi — chỉ
  // đổi (nếu có) khi daemon khởi động xong và tự áp state ban đầu, không
  // đáng tin cậy 100% ở mọi thứ tự session/DE.
  //
  // Gọi applyWallpaper() vô điều kiện là an toàn: nếu daemon cũng đang
  // chạy, nó sẽ ghi lại đúng giá trị tương ứng với mode vừa lưu (không
  // xung đột) và tiếp quản việc tự đổi theo giờ cho chế độ "auto" sau đó.
  applyWallpaper(m_selectedWallpaper);

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
  // bằng --install để test riêng app hyggshi-welcome, không có
  // hyggshi-set-wallpaper.sh của branding.sh trong hệ thống): set thẳng
  // property mặc định, KHÔNG hardcode chỉ XFCE — dò theo XDG_CURRENT_DESKTOP
  // giống logic trong hyggshi-set-wallpaper.sh (scripts/branding.sh).
  const QString xdgDesktop =
      qEnvironmentVariable("XDG_CURRENT_DESKTOP").toLower();
  const QString fileUri = "file://" + wallpaperPath;

  if (xdgDesktop.contains("cinnamon") &&
      QStandardPaths::findExecutable("gsettings") != "") {
    QProcess::execute("gsettings",
        {"set", "org.cinnamon.desktop.background", "picture-uri", fileUri});
  } else if (xdgDesktop.contains("mate") &&
             QStandardPaths::findExecutable("gsettings") != "") {
    QProcess::execute("gsettings",
        {"set", "org.mate.background", "picture-filename", wallpaperPath});
  } else if (xdgDesktop.contains("gnome") &&
             QStandardPaths::findExecutable("gsettings") != "") {
    QProcess::execute("gsettings",
        {"set", "org.gnome.desktop.background", "picture-uri", fileUri});
  } else if (xdgDesktop.contains("xfce") &&
             QStandardPaths::findExecutable("xfconf-query") != "") {
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
