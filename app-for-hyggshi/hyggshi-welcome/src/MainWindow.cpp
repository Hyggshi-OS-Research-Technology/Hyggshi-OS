#include "MainWindow.h"

#include <QApplication>
#include <QCheckBox>
#include <QComboBox>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QFont>
#include <QFrame>
#include <QGuiApplication>
#include <QHBoxLayout>
#include <QIcon>
#include <QLabel>
#include <QProcess>
#include <QMessageBox>
#include <QPixmap>
#include <QPushButton>
#include <QRegularExpression>
#include <QScrollArea>
#include <QSignalBlocker>
#include <QScreen>
#include <QSettings>
#include <QStandardPaths>
#include <QSysInfo>
#include <QToolButton>
#include <QUrl>
#include <QVBoxLayout>

namespace {

constexpr int kPageCount = 10;
constexpr int kPreferredWidth = 860;
constexpr int kPreferredHeight = 560;

QLabel *makeDot(bool active) {
  auto *dot = new QLabel;
  dot->setFixedSize(9, 9);
  dot->setStyleSheet(QString("border-radius:4px; background:%1;")
                         .arg(active ? "#5aa9ff" : "#3a3f4b"));
  return dot;
}

QString configDirectory() {
  return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) +
         "/hyggshi";
}

QString preferencesPath() { return configDirectory() + "/welcome.conf"; }

bool hasExecutable(const QString &name) {
  return !QStandardPaths::findExecutable(name).isEmpty();
}

bool isDebianSystem() {
  QFile file("/etc/os-release");
  if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) return false;
  const QString data = QString::fromUtf8(file.readAll());

  // Hyggshi OS intentionally brands /etc/os-release with ID=hyggshios, so
  // checking only ID=debian makes the Debian-only Testing option disappear
  // after branding. Prefer the explicit base-distro marker and keep the
  // native Debian check as a fallback for unbranded systems.
  const auto baseMatch = QRegularExpression(
      "^HYGGSHI_BASE_DISTRO=(?:\"debian\"|debian)$",
      QRegularExpression::MultilineOption).match(data);
  if (baseMatch.hasMatch()) return true;

  return QRegularExpression(
      "^ID=(?:\"debian\"|debian)$",
      QRegularExpression::MultilineOption).match(data).hasMatch();
}

void setGsettings(const QString &schema, const QString &key, const QString &value) {
  if (!hasExecutable("gsettings")) return;
  QProcess::execute("gsettings", {"set", schema, key, value});
}

QStringList commandOutput(const QString &program, const QStringList &args, int timeout = 1400) {
  QProcess process;
  process.start(program, args);
  if (!process.waitForFinished(timeout)) {
    process.kill();
    process.waitForFinished(200);
    return {};
  }
  const QByteArray output = process.readAllStandardOutput();
  return QString::fromLocal8Bit(output).split('\n', Qt::SkipEmptyParts);
}

}  // namespace

MainWindow::MainWindow(QWidget *parent) : QMainWindow(parent) {
  setWindowTitle(tr("Chào mừng đến với Hyggshi OS"));
  setMinimumSize(720, 480);
  resize(kPreferredWidth, kPreferredHeight);

  loadPreferences();

  QFont initialFont = qApp->font();
  initialFont.setPointSize(m_largeText ? 12 : 10);
  qApp->setFont(initialFont);

  auto *central = new QWidget;
  auto *rootLayout = new QVBoxLayout(central);
  rootLayout->setContentsMargins(0, 0, 0, 0);
  rootLayout->setSpacing(0);

  m_stack = new SlideStackedWidget;
  m_stack->addWidget(buildWelcomePage());
  m_stack->addWidget(buildLanguagePage());
  m_stack->addWidget(buildNetworkPage());
  m_stack->addWidget(buildThemePage());
  m_stack->addWidget(buildSoftwarePage());
  m_stack->addWidget(buildAccessibilityPage());
  m_stack->addWidget(buildSystemCheckPage());
  m_stack->addWidget(buildUpdatePage());
  m_stack->addWidget(buildFeaturesPage());
  m_stack->addWidget(buildFinishPage());

  rootLayout->addWidget(m_stack, 1);
  rootLayout->addWidget(buildNavBar(), 0);
  setCentralWidget(central);

  connect(m_stack, &SlideStackedWidget::animationFinished, this,
          &MainWindow::updateNavState);
  updateNavState();
  refreshNetworkStatus();
  refreshSystemStatus();

  if (QScreen *screen = QGuiApplication::primaryScreen()) {
    const QRect available = screen->availableGeometry();
    const int width = qMin(kPreferredWidth, available.width() - 40);
    const int height = qMin(kPreferredHeight, available.height() - 40);
    if (width >= minimumWidth() && height >= minimumHeight()) resize(width, height);
    move(available.center() - rect().center());
  }
}

void MainWindow::loadPreferences() {
  QSettings settings(preferencesPath(), QSettings::IniFormat);
  m_selectedLanguage = settings.value("language", "vi").toString();
  m_selectedKeyboard = settings.value("keyboard", "vn-telex").toString();
  m_selectedTheme = settings.value("theme", "auto").toString();
  m_reducedMotion = settings.value("accessibility/reduced_motion", false).toBool();
  m_highContrast = settings.value("accessibility/high_contrast", false).toBool();
  m_largeText = settings.value("accessibility/large_text", false).toBool();
  m_installProfile = settings.value("software/profile", "normal").toString();
  m_debianTesting = settings.value("software/debian_testing", false).toBool();
  if (m_installProfile != "full" && m_installProfile != "normal" &&
      m_installProfile != "minimal" && m_installProfile != "custom") {
    m_installProfile = "normal";
  }
  m_selectedSoftware = settings.value("software/packages").toStringList();
  m_selectedWallpaper = settings.value(
      "wallpaper", "/usr/share/backgrounds/hyggshi/Verdant-Valley.png").toString();
  if (m_selectedWallpaper != "/usr/share/backgrounds/hyggshi/Verdant-Valley.png" &&
      m_selectedWallpaper != "/usr/share/backgrounds/hyggshi/wallpaper.png") {
    m_selectedWallpaper = "/usr/share/backgrounds/hyggshi/Verdant-Valley.png";
  }
  if (m_selectedSoftware.isEmpty() && m_installProfile == "normal") {
    m_selectedSoftware << "ffmpeg" << "vlc" << "libreoffice";
  }
  if (m_selectedSoftware.isEmpty() && m_installProfile == "full") {
    m_selectedSoftware << "ffmpeg" << "vlc" << "libreoffice"
                       << "unattended-upgrades" << "thunderbird" << "krita"
                       << "virt-manager" << "keepassxc" << "git" << "curl" << "htop"
                       << "com.google.Chrome" << "com.visualstudio.code"
                       << "org.gimp.GIMP" << "org.inkscape.Inkscape"
                       << "com.obsproject.Studio";
  }

  if (m_selectedLanguage.isEmpty()) m_selectedLanguage = "vi";
  if (m_selectedKeyboard.isEmpty()) m_selectedKeyboard = "vn-telex";
  if (m_selectedTheme != "light" && m_selectedTheme != "dark" && m_selectedTheme != "auto") {
    m_selectedTheme = "auto";
  }
}

void MainWindow::savePreferences() const {
  QDir().mkpath(configDirectory());
  QSettings settings(preferencesPath(), QSettings::IniFormat);
  settings.setValue("language", m_selectedLanguage);
  settings.setValue("keyboard", m_selectedKeyboard);
  settings.setValue("theme", m_selectedTheme);
  settings.setValue("accessibility/reduced_motion", m_reducedMotion);
  settings.setValue("accessibility/high_contrast", m_highContrast);
  settings.setValue("accessibility/large_text", m_largeText);
  settings.setValue("software/profile", m_installProfile);
  settings.setValue("software/debian_testing", m_debianTesting);
  settings.setValue("software/packages", m_selectedSoftware);
  settings.setValue("wallpaper", m_selectedWallpaper);
  settings.sync();
}

QWidget *MainWindow::buildWelcomePage() {
  auto *page = new QWidget;
  auto *layout = new QVBoxLayout(page);
  layout->setAlignment(Qt::AlignCenter);
  layout->setSpacing(14);

  auto *logo = new QLabel;
  logo->setPixmap(QPixmap(":/icons/logo.png").scaled(96, 96, Qt::KeepAspectRatio,
                                                        Qt::SmoothTransformation));
  logo->setAlignment(Qt::AlignCenter);

  auto *title = new QLabel(tr("Chào mừng đến với Hyggshi OS"));
  title->setAlignment(Qt::AlignCenter);
  title->setStyleSheet("font-size:24px; font-weight:600; color:#f2f3f5;");

  auto *subtitle = new QLabel(tr("Thiết lập nhanh máy của bạn trong vài bước.\n"
                                "Mọi lựa chọn đều có thể đổi lại trong Cài đặt."));
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

QWidget *MainWindow::buildLanguagePage() {
  auto *page = new QWidget;
  auto *layout = new QVBoxLayout(page);
  layout->setContentsMargins(70, 55, 70, 40);
  layout->setSpacing(16);

  auto *title = new QLabel(tr("Ngôn ngữ & Bàn phím"));
  title->setStyleSheet("font-size:20px; font-weight:600; color:#f2f3f5;");

  auto *langLabel = new QLabel(tr("Ngôn ngữ hiển thị"));
  langLabel->setStyleSheet("color:#c7cad1; font-size:12px;");
  m_languageBox = new QComboBox;
  m_languageBox->addItem(tr("Tiếng Việt"), "vi");
  m_languageBox->addItem(tr("English"), "en");
  m_languageBox->addItem(tr("日本語"), "ja");
  m_languageBox->addItem(tr("한국어"), "ko");
  const int langIndex = m_languageBox->findData(m_selectedLanguage);
  m_languageBox->setCurrentIndex(langIndex >= 0 ? langIndex : 0);
  connect(m_languageBox, QOverload<int>::of(&QComboBox::currentIndexChanged), this,
          [this](int index) {
            if (index >= 0) m_selectedLanguage = m_languageBox->itemData(index).toString();
          });

  auto *kbLabel = new QLabel(tr("Bố cục bàn phím"));
  kbLabel->setStyleSheet("color:#c7cad1; font-size:12px; margin-top:8px;");
  m_keyboardBox = new QComboBox;
  m_keyboardBox->addItem("Vietnamese (TELEX)", "vn-telex");
  m_keyboardBox->addItem("English (US)", "us");
  m_keyboardBox->addItem("English (UK)", "gb");
  const int kbIndex = m_keyboardBox->findData(m_selectedKeyboard);
  m_keyboardBox->setCurrentIndex(kbIndex >= 0 ? kbIndex : 0);
  connect(m_keyboardBox, QOverload<int>::of(&QComboBox::currentIndexChanged), this,
          [this](int index) {
            if (index >= 0) m_selectedKeyboard = m_keyboardBox->itemData(index).toString();
          });

  auto *note = new QLabel(tr("Các lựa chọn được lưu cho tài khoản hiện tại."));
  note->setStyleSheet("color:#6f7480; font-size:11px;");
  note->setWordWrap(true);

  layout->addWidget(title);
  layout->addSpacing(8);
  layout->addWidget(langLabel);
  layout->addWidget(m_languageBox);
  layout->addWidget(kbLabel);
  layout->addWidget(m_keyboardBox);
  layout->addWidget(note);
  layout->addStretch(1);
  return page;
}

QWidget *MainWindow::buildNetworkPage() {
  auto *page = new QWidget;
  auto *layout = new QVBoxLayout(page);
  layout->setContentsMargins(70, 55, 70, 40);
  layout->setSpacing(14);

  auto *title = new QLabel(tr("Kết nối mạng"));
  title->setStyleSheet("font-size:20px; font-weight:600; color:#f2f3f5;");
  auto *desc = new QLabel(tr("Kiểm tra nhanh kết nối hiện tại. Hyggshi Welcome không tự quản lý Wi-Fi, mà mở công cụ hệ thống khi cần."));
  desc->setWordWrap(true);
  desc->setStyleSheet("color:#9aa0ab; font-size:12px;");

  m_networkStatus = new QLabel(tr("Đang kiểm tra..."));
  m_networkStatus->setStyleSheet("font-size:14px; color:#d8dbe1; padding:14px; border:1px solid #2c2f38; border-radius:8px;");
  m_networkStatus->setWordWrap(true);

  auto *row = new QHBoxLayout;
  auto *refresh = new QPushButton(tr("Kiểm tra lại"));
  auto *settings = new QPushButton(tr("Mở Network Settings"));
  refresh->setCursor(Qt::PointingHandCursor);
  settings->setCursor(Qt::PointingHandCursor);
  connect(refresh, &QPushButton::clicked, this, &MainWindow::refreshNetworkStatus);
  connect(settings, &QPushButton::clicked, this, [this]() {
    if (hasExecutable("nm-connection-editor")) QProcess::startDetached("nm-connection-editor");
    else if (hasExecutable("gnome-control-center")) QProcess::startDetached("gnome-control-center", {"network"});
    else if (hasExecutable("systemsettings5")) QProcess::startDetached("systemsettings5");
    else if (hasExecutable("systemsettings")) QProcess::startDetached("systemsettings");
  });
  row->addWidget(refresh);
  row->addWidget(settings);
  row->addStretch(1);

  layout->addWidget(title);
  layout->addWidget(desc);
  layout->addSpacing(8);
  layout->addWidget(m_networkStatus);
  layout->addLayout(row);
  layout->addStretch(1);
  return page;
}

QWidget *MainWindow::buildThemePage() {
  auto *page = new QWidget;
  auto *layout = new QVBoxLayout(page);
  layout->setContentsMargins(70, 55, 70, 40);
  layout->setSpacing(18);

  auto *title = new QLabel(tr("Chọn giao diện"));
  title->setStyleSheet("font-size:20px; font-weight:600; color:#f2f3f5;");

  auto *cardsRow = new QHBoxLayout;
  cardsRow->setSpacing(16);
  m_themeGroup = new QButtonGroup(page);
  m_themeGroup->setExclusive(true);

  const QVector<ThemeOpt> opts = {
      {"light", tr("Sáng"), "/usr/share/backgrounds/hyggshi/car-light.png"},
      {"dark", tr("Tối"), "/usr/share/backgrounds/hyggshi/car-Dark.png"},
      {"auto", tr("Tự động"), "/usr/share/backgrounds/hyggshi/car-light.png"},
  };

  for (int i = 0; i < opts.size(); ++i) {
    const auto opt = opts.at(i);
    auto *card = new QPushButton;
    card->setCheckable(true);
    card->setFixedSize(150, 110);
    card->setCursor(Qt::PointingHandCursor);
    card->setText("\n\n" + opt.label);

    const QString imageName = QString("theme-%1.png").arg(opt.id);
    card->setStyleSheet(QString(
        "QPushButton { border-radius:10px; border:2px solid #2c2f38;"
        " color:#ffffff; font-weight:600;"
        " border-image:url(:/icons/%1) 0 0 0 0 stretch stretch; }"
        "QPushButton:checked { border:2px solid #5aa9ff; }")
        .arg(imageName));

    if (opt.id == m_selectedTheme) {
      card->setChecked(true);
    }

    m_themeGroup->addButton(card, i);
    connect(card, &QPushButton::clicked, this, [this, opt]() {
      m_selectedTheme = opt.id;
      savePreferences();
    });
    cardsRow->addWidget(card);
  }

  if (!m_themeGroup->checkedButton()) {
    if (QAbstractButton *button = m_themeGroup->button(2)) button->setChecked(true);
    m_selectedTheme = "auto";
  }

  auto *wallpaperLabel = new QLabel(tr("Hình nền"));
  wallpaperLabel->setStyleSheet("color:#c7cad1; font-size:12px; margin-top:10px;");
  auto *wallpaperBox = new QComboBox;
  wallpaperBox->addItem(tr("Verdant Valley"), "/usr/share/backgrounds/hyggshi/Verdant-Valley.png");
  wallpaperBox->addItem(tr("Hyggshi Wallpaper"), "/usr/share/backgrounds/hyggshi/wallpaper.png");
  const int wallpaperIndex = wallpaperBox->findData(m_selectedWallpaper);
  wallpaperBox->setCurrentIndex(wallpaperIndex >= 0 ? wallpaperIndex : 0);
  connect(wallpaperBox, QOverload<int>::of(&QComboBox::currentIndexChanged), this,
          [this, wallpaperBox](int index) {
            if (index >= 0) {
              m_selectedWallpaper = wallpaperBox->itemData(index).toString();
              savePreferences();
            }
          });

  auto *note = new QLabel(tr("Tự động sẽ bám theo theme hiện tại của desktop khi hoàn tất thiết lập."));
  note->setWordWrap(true);
  note->setStyleSheet("color:#6f7480; font-size:11px; margin-top:10px;");

  layout->addWidget(title);
  layout->addSpacing(8);
  layout->addLayout(cardsRow);
  layout->addWidget(wallpaperLabel);
  layout->addWidget(wallpaperBox);
  layout->addWidget(note);
  layout->addStretch(1);
  return page;
}

QWidget *MainWindow::buildSoftwarePage() {
  auto *page = new QWidget;
  auto *outer = new QVBoxLayout(page);
  outer->setContentsMargins(55, 35, 55, 30);
  outer->setSpacing(10);

  auto *title = new QLabel(tr("Tùy chỉnh & Phần mềm"));
  title->setStyleSheet("font-size:20px; font-weight:600; color:#f2f3f5;");
  auto *desc = new QLabel(tr("Các lựa chọn trước đây nằm ở Customize và Additional Software nay được thực hiện trong Hyggshi Welcome sau khi đăng nhập. Có LibreOffice, ONLYOFFICE, WPS Office, VLC, Visual Studio Code, Google Chrome và nhiều ứng dụng khác. Chọn một bộ Office phù hợp hoặc dùng Tùy chỉnh."));
  desc->setWordWrap(true);
  desc->setStyleSheet("color:#9aa0ab; font-size:12px;");

  auto *profileLabel = new QLabel(tr("Kiểu cài đặt phần mềm"));
  profileLabel->setStyleSheet("color:#c7cad1; font-size:12px;");
  m_installProfileBox = new QComboBox;
  m_installProfileBox->addItem(tr("Đầy đủ — cài toàn bộ"), "full");
  m_installProfileBox->addItem(tr("Thông thường — bộ cơ bản"), "normal");
  m_installProfileBox->addItem(tr("Tối giản — không cài thêm"), "minimal");
  m_installProfileBox->addItem(tr("Tùy chỉnh — tự chọn"), "custom");
  const int profileIndex = m_installProfileBox->findData(m_installProfile);
  m_installProfileBox->setCurrentIndex(profileIndex >= 0 ? profileIndex : 1);

  auto *testingBox = new QCheckBox(tr("Dùng package Debian Testing"));
  testingBox->setToolTip(tr("Chỉ áp dụng cho Debian. Dùng kho Debian Testing khi cài các phần mềm đã chọn."));
  m_debianTestingCheck = testingBox;
  const bool isDebian = isDebianSystem();
  testingBox->setVisible(isDebian);
  testingBox->setChecked(isDebian && m_debianTesting);
  connect(testingBox, &QCheckBox::toggled, this, [this, testingBox](bool checked) {
    if (!checked) {
      m_debianTesting = false;
      savePreferences();
      return;
    }
    QMessageBox::StandardButton answer = QMessageBox::warning(
        this, tr("Cảnh báo: Debian Testing"),
        tr("Debian Testing là kho phát triển, có thể chứa package chưa ổn định và có thể gây xung đột hoặc làm hệ thống khó nâng cấp.\n\nChỉ bật tùy chọn này nếu bạn hiểu rủi ro và muốn dùng package Testing cho phần mềm đã chọn. Hyggshi OS không khuyến nghị bật trên máy chính.\n\nBạn có muốn tiếp tục không?"),
        QMessageBox::Cancel | QMessageBox::Ok, QMessageBox::Cancel);
    if (answer != QMessageBox::Ok) {
      const QSignalBlocker blocker(testingBox);
      Q_UNUSED(blocker);
      testingBox->setChecked(false);
      m_debianTesting = false;
      savePreferences();
      return;
    }
    m_debianTesting = true;
    savePreferences();
  });
  connect(m_installProfileBox, QOverload<int>::of(&QComboBox::currentIndexChanged), this,
          [this](int index) {
            if (index < 0) return;
            m_installProfile = m_installProfileBox->itemData(index).toString();
            if (m_installProfile == "full" || m_installProfile == "minimal" || m_installProfile == "normal") {
              QStringList desired;
              if (m_installProfile == "full") {
                // Full profile: useful desktop set, but do not install every
                // mutually alternative office/browser package at once.
                desired << "ffmpeg" << "vlc" << "libreoffice"
                        << "unattended-upgrades" << "thunderbird" << "krita"
                        << "virt-manager" << "keepassxc" << "git" << "curl" << "htop"
                        << "com.google.Chrome" << "com.visualstudio.code"
                        << "org.gimp.GIMP" << "org.inkscape.Inkscape"
                        << "com.obsproject.Studio";
              } else if (m_installProfile == "normal") {
                desired << "ffmpeg" << "vlc" << "libreoffice";
              }
              {
                const QSignalBlocker blocker(m_installProfileBox);
                Q_UNUSED(blocker);
                for (QCheckBox *check : m_softwareChecks) {
                  const QSignalBlocker checkBlocker(check);
                  Q_UNUSED(checkBlocker);
                  check->setChecked(desired.contains(check->property("packageName").toString()));
                }
              }
              m_selectedSoftware = desired;
            }
            // Custom leaves the current checkbox selection untouched.
            savePreferences();
          });

  auto *softwareLabel = new QLabel(tr("Phần mềm bổ sung (APT + Flathub)"));
  softwareLabel->setStyleSheet("color:#c7cad1; font-size:12px; margin-top:6px;");

  auto *scroll = new QScrollArea;
  scroll->setWidgetResizable(true);
  scroll->setFrameShape(QFrame::NoFrame);
  auto *list = new QWidget;
  auto *listLayout = new QVBoxLayout(list);
  listLayout->setContentsMargins(4, 2, 4, 2);
  listLayout->setSpacing(5);

  struct SoftwareOpt { const char *id; const char *label; const char *type; const char *group; };
  QVector<SoftwareOpt> options = {
      {"ffmpeg", "Codec đa phương tiện (FFmpeg)", "apt", ""},
      {"vlc", "VLC — trình phát đa phương tiện", "apt", "media"},
      {"libreoffice", "LibreOffice — bộ ứng dụng văn phòng", "apt", "office"},
      {"unattended-upgrades", "Cập nhật tự động (unattended-upgrades)", "apt", ""},
      {"thunderbird", "Thunderbird", "apt", ""},
      {"krita", "Krita", "apt", ""},
      {"virt-manager", "Virtual Machine Manager", "apt", ""},
      {"keepassxc", "KeePassXC", "apt", ""},
      {"git", "Git", "apt", ""},
      {"curl", "cURL", "apt", ""},
      {"htop", "Htop", "apt", ""},
      {"org.libreoffice.LibreOffice", "LibreOffice (Flatpak)", "flatpak", "office"},
      {"org.onlyoffice.desktopeditors", "ONLYOFFICE Desktop Editors", "flatpak", "office"},
      {"com.wps.Office", "WPS Office", "flatpak", "office"},
      {"com.google.Chrome", "Google Chrome", "flatpak", "browser"},
      {"com.visualstudio.code", "Visual Studio Code", "flatpak", ""},
      {"org.videolan.VLC", "VLC (Flatpak)", "flatpak", "media"},
      {"org.gimp.GIMP", "GIMP", "flatpak", ""},
      {"org.inkscape.Inkscape", "Inkscape", "flatpak", ""},
      {"com.obsproject.Studio", "OBS Studio", "flatpak", ""},
  };

  // Debian Testing: mở rộng thêm 2 lựa chọn "nặng" — kernel mới nhất và
  // bản Desktop Environment mới nhất từ kho Testing. Chỉ hiện trên Debian
  // (isDebian) vì "Dùng package Debian Testing" ở trên cũng chỉ áp dụng
  // cho Debian. DE hiển thị ĐÚNG 1 metapackage khớp desktop hiện tại của
  // máy (XDG_CURRENT_DESKTOP) — ISO chỉ cài 1 DE duy nhất nên không có lý
  // do liệt kê cả 6 DE khác không tồn tại trên máy.
  if (isDebian) {
    options.push_back({"linux-image-amd64", "Kernel Linux mới nhất (Debian Testing)", "apt", "kernel"});

    const QString curDesktop = qEnvironmentVariable("XDG_CURRENT_DESKTOP").toLower();
    if (curDesktop.contains("cinnamon")) {
      options.push_back({"cinnamon-desktop-environment", "Cinnamon mới nhất (Debian Testing)", "apt", "de"});
    } else if (curDesktop.contains("xfce")) {
      options.push_back({"task-xfce-desktop", "XFCE mới nhất (Debian Testing)", "apt", "de"});
    } else if (curDesktop.contains("kde") || curDesktop.contains("plasma")) {
      options.push_back({"kde-plasma-desktop", "KDE Plasma mới nhất (Debian Testing)", "apt", "de"});
    } else if (curDesktop.contains("gnome")) {
      options.push_back({"gnome-session", "GNOME mới nhất (Debian Testing)", "apt", "de"});
    } else if (curDesktop.contains("mate")) {
      options.push_back({"mate-desktop-environment", "MATE mới nhất (Debian Testing)", "apt", "de"});
    } else if (curDesktop.contains("lxqt")) {
      options.push_back({"lxqt", "LXQt mới nhất (Debian Testing)", "apt", "de"});
    }
  }

  for (const auto &opt : options) {
    auto *check = new QCheckBox(tr(opt.label));
    check->setProperty("packageName", QString::fromLatin1(opt.id));
    check->setProperty("installType", QString::fromLatin1(opt.type));
    check->setProperty("group", QString::fromLatin1(opt.group));
    check->setCursor(Qt::PointingHandCursor);
    const QString optGroup = QString::fromLatin1(opt.group);
    if (optGroup == "kernel" || optGroup == "de") {
      check->setToolTip(tr("Chỉ được cài khi bật 'Dùng package Debian Testing' ở trên. Sẽ kéo theo nhiều package phụ thuộc cũng được nâng lên bản Testing."));
    }
    check->setChecked(m_selectedSoftware.contains(QString::fromLatin1(opt.id)) ||
                      (m_installProfile == "normal" &&
                       (QString::fromLatin1(opt.id) == "ffmpeg" ||
                        QString::fromLatin1(opt.id) == "vlc" ||
                        QString::fromLatin1(opt.id) == "libreoffice")));
    m_softwareChecks.push_back(check);
    connect(check, &QCheckBox::toggled, this, [this, check](bool checked) {
      if (checked) {
        const QString group = check->property("group").toString();
        if (!group.isEmpty()) {
          for (QCheckBox *other : m_softwareChecks) {
            if (other == check) continue;
            if (other->property("group").toString() == group) {
              const QSignalBlocker blocker(other);
              Q_UNUSED(blocker);
              other->setChecked(false);
            }
          }
        }
      }
      QStringList packages;
      for (QCheckBox *item : m_softwareChecks) {
        if (item->isChecked()) packages << item->property("packageName").toString();
      }
      m_selectedSoftware = packages;
      if (m_installProfile != "custom") {
        m_installProfile = "custom";
        if (m_installProfileBox) {
          const int index = m_installProfileBox->findData("custom");
          if (index >= 0 && m_installProfileBox->currentIndex() != index) {
            const QSignalBlocker blocker(m_installProfileBox);
            Q_UNUSED(blocker);
            m_installProfileBox->setCurrentIndex(index);
          }
        }
      }
      savePreferences();
    });
    listLayout->addWidget(check);
  }
  listLayout->addStretch(1);
  scroll->setWidget(list);

  m_softwareStatus = new QLabel(tr("Các gói sẽ được cài khi bạn bấm 'Bắt đầu sử dụng' ở cuối Welcome."));
  m_softwareStatus->setWordWrap(true);
  m_softwareStatus->setStyleSheet("font-size:11px; color:#6f7480;");

  outer->addWidget(title);
  outer->addWidget(desc);
  outer->addSpacing(4);
  outer->addWidget(profileLabel);
  outer->addWidget(m_installProfileBox);
  outer->addWidget(testingBox);
  outer->addWidget(softwareLabel);
  outer->addWidget(scroll, 1);
  outer->addWidget(m_softwareStatus);
  return page;
}

QWidget *MainWindow::buildAccessibilityPage() {
  auto *page = new QWidget;
  auto *layout = new QVBoxLayout(page);
  layout->setContentsMargins(70, 55, 70, 40);
  layout->setSpacing(12);

  auto *title = new QLabel(tr("Trợ năng"));
  title->setStyleSheet("font-size:20px; font-weight:600; color:#f2f3f5;");
  auto *desc = new QLabel(tr("Các lựa chọn dưới đây được lưu cho tài khoản hiện tại và có thể được thay đổi sau này."));
  desc->setWordWrap(true);
  desc->setStyleSheet("color:#9aa0ab; font-size:12px;");

  m_reducedMotionChk = new QCheckBox(tr("Giảm chuyển động và animation"));
  m_highContrastChk = new QCheckBox(tr("Tăng tương phản giao diện"));
  m_largeTextChk = new QCheckBox(tr("Chữ lớn hơn"));
  m_reducedMotionChk->setChecked(m_reducedMotion);
  m_highContrastChk->setChecked(m_highContrast);
  m_largeTextChk->setChecked(m_largeText);
  for (QCheckBox *check : {m_reducedMotionChk, m_highContrastChk, m_largeTextChk}) {
    check->setCursor(Qt::PointingHandCursor);
  }

  connect(m_reducedMotionChk, &QCheckBox::toggled, this, [this](bool value) { m_reducedMotion = value; savePreferences(); });
  connect(m_highContrastChk, &QCheckBox::toggled, this, [this](bool value) { m_highContrast = value; savePreferences(); });
  connect(m_largeTextChk, &QCheckBox::toggled, this, [this](bool value) { m_largeText = value; savePreferences(); });

  layout->addWidget(title);
  layout->addWidget(desc);
  layout->addSpacing(8);
  layout->addWidget(m_reducedMotionChk);
  layout->addWidget(m_highContrastChk);
  layout->addWidget(m_largeTextChk);
  layout->addStretch(1);
  return page;
}

QWidget *MainWindow::buildSystemCheckPage() {
  auto *page = new QWidget;
  auto *layout = new QVBoxLayout(page);
  layout->setContentsMargins(70, 45, 70, 35);
  layout->setSpacing(12);

  auto *title = new QLabel(tr("Kiểm tra hệ thống"));
  title->setStyleSheet("font-size:20px; font-weight:600; color:#f2f3f5;");

  m_systemStatus = new QLabel;
  m_systemStatus->setWordWrap(true);
  m_systemStatus->setTextFormat(Qt::RichText);
  m_systemStatus->setStyleSheet("font-size:12px; color:#d8dbe1; padding:14px; border:1px solid #2c2f38; border-radius:8px;");

  auto *refresh = new QPushButton(tr("Kiểm tra lại"));
  refresh->setCursor(Qt::PointingHandCursor);
  connect(refresh, &QPushButton::clicked, this, &MainWindow::refreshSystemStatus);

  layout->addWidget(title);
  layout->addWidget(m_systemStatus, 1);
  layout->addWidget(refresh, 0, Qt::AlignLeft);
  return page;
}

QWidget *MainWindow::buildUpdatePage() {
  auto *page = new QWidget;
  auto *layout = new QVBoxLayout(page);
  layout->setContentsMargins(70, 55, 70, 40);
  layout->setSpacing(12);

  auto *title = new QLabel(tr("Cập nhật hệ thống"));
  title->setStyleSheet("font-size:20px; font-weight:600; color:#f2f3f5;");
  auto *desc = new QLabel(tr("Chỉ kiểm tra trạng thái cập nhật; Welcome không tự cài package hay yêu cầu quyền quản trị."));
  desc->setWordWrap(true);
  desc->setStyleSheet("color:#9aa0ab; font-size:12px;");

  m_updateStatus = new QLabel(tr("Chưa kiểm tra."));
  m_updateStatus->setWordWrap(true);
  m_updateStatus->setStyleSheet("font-size:13px; color:#d8dbe1; padding:14px; border:1px solid #2c2f38; border-radius:8px;");

  m_updateCheckBtn = new QPushButton(tr("Kiểm tra cập nhật"));
  m_updateCheckBtn->setCursor(Qt::PointingHandCursor);
  connect(m_updateCheckBtn, &QPushButton::clicked, this, &MainWindow::checkForUpdates);

  auto *open = new QPushButton(tr("Mở System Updater"));
  open->setCursor(Qt::PointingHandCursor);
  connect(open, &QPushButton::clicked, this, []() {
    if (hasExecutable("update-manager")) QProcess::startDetached("update-manager");
    else if (hasExecutable("gnome-software")) QProcess::startDetached("gnome-software");
    else if (hasExecutable("discover")) QProcess::startDetached("discover");
    else if (hasExecutable("software-manager")) QProcess::startDetached("software-manager");
  });

  layout->addWidget(title);
  layout->addWidget(desc);
  layout->addSpacing(8);
  layout->addWidget(m_updateStatus);
  layout->addWidget(m_updateCheckBtn, 0, Qt::AlignLeft);
  layout->addWidget(open, 0, Qt::AlignLeft);
  layout->addStretch(1);
  return page;
}

QWidget *MainWindow::buildFeaturesPage() {
  m_features = {
      {"🚀", tr("Khởi động nhanh"), tr("Hyggshi OS tối ưu trải nghiệm và tài nguyên nền cho sử dụng hằng ngày.")},
      {"🎨", tr("Giao diện tuỳ biến"), tr("Đổi theme, icon và panel dễ dàng ngay trong Cài đặt hệ thống.")},
      {"🧩", tr("Hệ sinh thái riêng"), tr("nexfetch, HOSC và các thành phần Hyggshi được tích hợp theo hướng đồng bộ.")},
      {"🔒", tr("An toàn theo mặc định"), tr("Các thiết lập nền tảng hợp lý được chuẩn bị sẵn để bắt đầu.")},
  };

  auto *page = new QWidget;
  auto *layout = new QVBoxLayout(page);
  layout->setContentsMargins(70, 45, 70, 30);
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
  m_featureDesc->setMaximumWidth(520);

  auto *navRow = new QHBoxLayout;
  navRow->setAlignment(Qt::AlignCenter);
  navRow->setSpacing(6);
  auto *prevArrow = new QToolButton;
  prevArrow->setText("◀");
  auto *dotsRow = new QHBoxLayout;
  dotsRow->setSpacing(6);
  for (int i = 0; i < m_features.size(); ++i) {
    auto *dot = makeDot(i == 0);
    m_featureDots.push_back(dot);
    dotsRow->addWidget(dot);
  }
  auto *nextArrow = new QToolButton;
  nextArrow->setText("▶");

  navRow->addWidget(prevArrow);
  navRow->addLayout(dotsRow);
  navRow->addWidget(nextArrow);
  connect(prevArrow, &QToolButton::clicked, this, [this]() {
    if (m_features.isEmpty()) return;
    m_carouselTimer->stop();
    showFeatureSlide((m_featureIndex - 1 + m_features.size()) % m_features.size());
    m_carouselTimer->start();
  });
  connect(nextArrow, &QToolButton::clicked, this, [this]() {
    if (m_features.isEmpty()) return;
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
  if (m_features.isEmpty() || index < 0 || index >= m_features.size() || !m_featureDesc ||
      !m_featureIcon || !m_featureTitle) return;
  m_featureIndex = index;
  const FeatureSlide &feature = m_features.at(index);
  m_featureIcon->setText(feature.icon);
  m_featureTitle->setText(feature.title);
  m_featureDesc->setText(feature.desc);
  for (int i = 0; i < m_featureDots.size(); ++i) {
    m_featureDots[i]->setStyleSheet(QString("border-radius:4px; background:%1;")
                                        .arg(i == index ? "#5aa9ff" : "#3a3f4b"));
  }
}

void MainWindow::advanceCarousel() {
  if (!m_features.isEmpty()) showFeatureSlide((m_featureIndex + 1) % m_features.size());
}

namespace {

QToolButton *makeSocialButton(const QString &iconPath, const QString &url, const QString &tooltip) {
  auto *btn = new QToolButton;
  btn->setIcon(QIcon(iconPath));
  btn->setIconSize(QSize(28, 28));
  btn->setCursor(Qt::PointingHandCursor);
  btn->setToolTip(tooltip);
  btn->setAutoRaise(true);
  btn->setStyleSheet("QToolButton { border: none; padding: 4px; border-radius: 8px; }"
                      "QToolButton:hover { background: #2a2d35; }");
  QObject::connect(btn, &QToolButton::clicked, [url]() {
    QDesktopServices::openUrl(QUrl(url));
  });
  return btn;
}

}  // namespace

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
  auto *desc = new QLabel(tr("Hyggshi OS đã sẵn sàng. Các lựa chọn của bạn đã được lưu."));
  desc->setAlignment(Qt::AlignCenter);
  desc->setStyleSheet("font-size:13px; color:#9aa0ab;");
  desc->setWordWrap(true);

  auto *communityLabel = new QLabel(tr("Tham gia cộng đồng Hyggshi OS"));
  communityLabel->setAlignment(Qt::AlignCenter);
  communityLabel->setStyleSheet("font-size:12px; color:#9aa0ab;");

  auto *socialRow = new QHBoxLayout;
  socialRow->setAlignment(Qt::AlignCenter);
  socialRow->setSpacing(12);
  socialRow->addWidget(makeSocialButton(":/icons/discord.png",
                                         "https://discord.gg/C2wnU8Vz6U", tr("Discord")));
  socialRow->addWidget(makeSocialButton(":/icons/x.png",
                                         "https://x.com/hyggshios", tr("X (Twitter)")));

  m_dontAskAgainChk = new QCheckBox(tr("Không hỏi lại lần sau"));
  m_dontAskAgainChk->setChecked(true);
  m_dontAskAgainChk->setCursor(Qt::PointingHandCursor);

  layout->addStretch(1);
  layout->addWidget(icon);
  layout->addWidget(title);
  layout->addWidget(desc);
  layout->addSpacing(14);
  layout->addWidget(communityLabel);
  layout->addLayout(socialRow);
  layout->addSpacing(10);
  layout->addWidget(m_dontAskAgainChk, 0, Qt::AlignCenter);
  layout->addStretch(2);
  return page;
}

QWidget *MainWindow::buildNavBar() {
  auto *bar = new QFrame;
  bar->setStyleSheet("background:#1a1c22; border-top:1px solid #2a2d35;");
  bar->setFixedHeight(64);
  auto *layout = new QHBoxLayout(bar);
  layout->setContentsMargins(24, 0, 24, 0);

  m_backBtn = new QPushButton(tr("Quay lại"));
  m_backBtn->setCursor(Qt::PointingHandCursor);
  connect(m_backBtn, &QPushButton::clicked, this, &MainWindow::goBack);

  auto *dotsRow = new QHBoxLayout;
  dotsRow->setSpacing(7);
  dotsRow->setAlignment(Qt::AlignCenter);
  for (int i = 0; i < kPageCount; ++i) {
    auto *dot = makeDot(i == 0);
    m_dots.push_back(dot);
    dotsRow->addWidget(dot);
  }

  m_skipBtn = new QPushButton(tr("Bỏ qua"));
  m_skipBtn->setCursor(Qt::PointingHandCursor);
  connect(m_skipBtn, &QPushButton::clicked, this, &MainWindow::finishSetup);

  m_nextBtn = new QPushButton(tr("Tiếp tục"));
  m_nextBtn->setCursor(Qt::PointingHandCursor);
  m_nextBtn->setStyleSheet("QPushButton { background:#5aa9ff; color:#0d1017; font-weight:600; border-radius:8px; padding:8px 22px; } QPushButton:hover { background:#77b9ff; } QPushButton:disabled { background:#33465b; color:#66717f; }");
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
    m_dots[i]->setStyleSheet(QString("border-radius:4px; background:%1;")
                                  .arg(i == index ? "#5aa9ff" : "#3a3f4b"));
  }
}

void MainWindow::updateNavState() {
  if (!m_stack || !m_backBtn || !m_skipBtn || !m_nextBtn) return;
  const int index = m_stack->currentIndex();
  const bool isLast = index == m_stack->count() - 1;
  const bool busy = m_stack->isAnimating();
  m_backBtn->setEnabled(index > 0 && !busy);
  m_backBtn->setVisible(index > 0);
  m_skipBtn->setVisible(!isLast);
  m_skipBtn->setEnabled(!busy);
  m_nextBtn->setEnabled(!busy);
  m_nextBtn->setText(isLast ? tr("Bắt đầu sử dụng") : tr("Tiếp tục"));
  updateDots(index);

  m_stack->setReducedMotion(m_reducedMotion);
}

void MainWindow::goNext() {
  if (!m_stack || m_stack->isAnimating()) return;
  const int index = m_stack->currentIndex();
  if (index == m_stack->count() - 1) {
    finishSetup();
    return;
  }
  if (index == 2) refreshNetworkStatus();
  if (index == 6) refreshSystemStatus();
  if (index == 7) setUpdateStatus(tr("Bạn có thể kiểm tra cập nhật ngay hoặc tiếp tục."));
  m_stack->slideToIndex(index + 1);
  updateNavState();
}

void MainWindow::goBack() {
  if (!m_stack || m_stack->isAnimating()) return;
  const int index = m_stack->currentIndex();
  if (index <= 0) return;
  m_stack->slideToIndex(index - 1);
  updateNavState();
}

void MainWindow::applyLanguageAndKeyboard() {
  savePreferences();
  const QString desktop = qEnvironmentVariable("XDG_CURRENT_DESKTOP").toLower();
  QString xkbLayout = m_selectedKeyboard;
  if (xkbLayout == "vn-telex") xkbLayout = "vn";
  if (hasExecutable("gsettings")) {
    if (desktop.contains("gnome")) {
      setGsettings("org.gnome.desktop.input-sources", "sources", QString("[( 'xkb', '%1' )]").arg(xkbLayout));
    } else if (desktop.contains("cinnamon")) {
      setGsettings("org.cinnamon.desktop.input-sources", "sources", QString("[( 'xkb', '%1' )]").arg(xkbLayout));
    }
  }
}

void MainWindow::applyAccessibility() {
  savePreferences();
  const QString desktop = qEnvironmentVariable("XDG_CURRENT_DESKTOP").toLower();
  if (m_reducedMotion && hasExecutable("gsettings")) {
    if (desktop.contains("gnome")) setGsettings("org.gnome.desktop.interface", "enable-animations", "false");
    else if (desktop.contains("cinnamon")) setGsettings("org.cinnamon.desktop.interface", "enable-animations", "false");
  }
  if (!m_reducedMotion && hasExecutable("gsettings")) {
    if (desktop.contains("gnome")) setGsettings("org.gnome.desktop.interface", "enable-animations", "true");
    else if (desktop.contains("cinnamon")) setGsettings("org.cinnamon.desktop.interface", "enable-animations", "true");
  }
  if (m_highContrast && hasExecutable("gsettings") && desktop.contains("gnome")) {
    setGsettings("org.gnome.desktop.a11y", "always-show-universal-access-status", "true");
  }

  QFont font = qApp->font();
  font.setPointSize(m_largeText ? 12 : 10);
  qApp->setFont(font);
}

void MainWindow::refreshNetworkStatus() {
  if (!m_networkStatus) return;
  QString text;
  bool connected = false;
  QString interfaceName;
  QString type;

  if (hasExecutable("nmcli")) {
    const QStringList state = commandOutput("nmcli", {"-t", "-f", "general.state", "general"});
    connected = !state.isEmpty() && state.first().toLower().contains("connected");
    const QStringList devices = commandOutput("nmcli", {"-t", "-f", "device,type,state", "device"});
    for (const QString &line : devices) {
      const QStringList p = line.split(':');
      if (p.size() >= 3 && p.at(2).toLower().contains("connected")) {
        interfaceName = p.at(0);
        type = p.at(1);
        break;
      }
    }
    text = connected ? tr("✓ Đang kết nối\nThiết bị: %1%2").arg(interfaceName, type.isEmpty() ? QString() : " (" + type + ")")
                     : tr("⚠ Chưa có kết nối mạng hoạt động.");
  } else {
    const QStringList route = commandOutput("sh", {"-c", "ip route get 1.1.1.1 2>/dev/null"});
    connected = !route.isEmpty();
    text = connected ? tr("✓ Có route mạng đang hoạt động.") : tr("⚠ Không xác định được trạng thái mạng.");
  }
  if (!hasExecutable("nmcli")) text += tr("\nNetworkManager/nmcli chưa có; hãy kiểm tra bằng công cụ desktop.");
  m_networkStatus->setText(text);
}

void MainWindow::refreshSystemStatus() {
  if (!m_systemStatus) return;
  QString cpu = QSysInfo::currentCpuArchitecture();
  QString kernel = QSysInfo::kernelType() + " " + QSysInfo::kernelVersion();
  QString os = QSysInfo::prettyProductName();
  const QString config = configDirectory();
  const bool configWritable = QDir().mkpath(config) && QFileInfo(config).isWritable();
  const bool desktopDetected = !qEnvironmentVariable("XDG_CURRENT_DESKTOP").isEmpty();
  const bool settings = hasExecutable("gsettings") || hasExecutable("xfconf-query");
  const bool wallpaperTools = hasExecutable("gsettings") || hasExecutable("xfconf-query") || QFile::exists("/usr/local/bin/hyggshi-set-wallpaper.sh");

  QString memoryInfo = tr("Không đọc được RAM");
  QFile memFile("/proc/meminfo");
  if (memFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
    const QString data = QString::fromLocal8Bit(memFile.readAll());
    const QRegularExpression re("MemTotal\\s*:\\s*(\\d+)");
    const auto match = re.match(data);
    if (match.hasMatch()) {
      const double gb = match.captured(1).toLongLong() / 1024.0 / 1024.0;
      memoryInfo = tr("%1 GB RAM").arg(QString::number(gb, 'f', 1));
    }
  }

  QString html;
  html += tr("<b>OS:</b> %1<br>").arg(os.toHtmlEscaped());
  html += tr("<b>Kernel:</b> %1<br>").arg(kernel.toHtmlEscaped());
  html += tr("<b>Architecture:</b> %1<br>").arg(cpu.toHtmlEscaped());
  html += tr("<b>Memory:</b> %1<br><br>").arg(memoryInfo.toHtmlEscaped());
  html += tr("%1 Cấu hình người dùng ghi được<br>").arg(configWritable ? "✓" : "✗");
  html += tr("%1 Desktop environment phát hiện được<br>").arg(desktopDetected ? "✓" : "⚠");
  html += tr("%1 Công cụ theme/settings khả dụng<br>").arg(settings ? "✓" : "⚠");
  html += tr("%1 Công cụ wallpaper khả dụng").arg(wallpaperTools ? "✓" : "⚠");
  m_systemStatus->setText(html);
}

void MainWindow::setUpdateStatus(const QString &text) {
  if (m_updateStatus) m_updateStatus->setText(text);
}

void MainWindow::checkForUpdates() {
  if (!m_updateCheckBtn || !m_updateStatus) return;
  m_updateCheckBtn->setEnabled(false);
  setUpdateStatus(tr("Đang kiểm tra..."));

  auto *process = new QProcess(this);
  QString program;
  QStringList args;
  if (hasExecutable("checkupdates")) { program = "checkupdates"; }
  else if (hasExecutable("apt-get")) { program = "apt-get"; args = {"-s", "upgrade"}; }
  else if (hasExecutable("dnf")) { program = "dnf"; args = {"-q", "check-update"}; }
  else if (hasExecutable("zypper")) { program = "zypper"; args = {"--non-interactive", "list-updates"}; }
  else if (hasExecutable("pacman") && hasExecutable("checkupdates")) { program = "checkupdates"; }

  if (program.isEmpty()) {
    setUpdateStatus(tr("Không tìm thấy công cụ kiểm tra cập nhật. Hãy dùng System Updater của desktop."));
    m_updateCheckBtn->setEnabled(true);
    process->deleteLater();
    return;
  }

  connect(process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished), this,
          [this, process](int exitCode, QProcess::ExitStatus status) {
            const QString out = QString::fromLocal8Bit(process->readAllStandardOutput()).trimmed();
            const QString err = QString::fromLocal8Bit(process->readAllStandardError()).trimmed();
            m_updateCheckBtn->setEnabled(true);
            if (status != QProcess::NormalExit) setUpdateStatus(tr("Không thể hoàn tất kiểm tra cập nhật."));
            else if (exitCode == 0) setUpdateStatus(out.isEmpty() ? tr("✓ Không phát hiện package cần cập nhật.") : tr("✓ Công cụ cập nhật đã trả kết quả:\n%1").arg(out.left(1200)));
            else if (exitCode == 100 && err.isEmpty()) setUpdateStatus(tr("Có package cần cập nhật. Hãy mở System Updater để xem chi tiết."));
            else setUpdateStatus(err.isEmpty() ? tr("Không thể xác định trạng thái cập nhật.") : err.left(1200));
            process->deleteLater();
          });
  process->start(program, args);
}

QString MainWindow::resolveAutoWallpaper() const {
  if (QFile::exists(m_selectedWallpaper)) return m_selectedWallpaper;
  if (QFile::exists("/usr/share/backgrounds/hyggshi/Verdant-Valley.png"))
    return "/usr/share/backgrounds/hyggshi/Verdant-Valley.png";
  return "/usr/share/backgrounds/hyggshi/wallpaper.png";
}

void MainWindow::saveFirstRunState(bool completed) {
  QDir().mkpath(configDirectory());
  const QString marker = configDirectory() + "/welcome-shown";
  if (completed) {
    QFile markerFile(marker);
    if (markerFile.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
      markerFile.write("1\n");
      markerFile.close();
    }
  } else {
    QFile::remove(marker);
  }
}

bool MainWindow::installSelectedSoftware() {
  QStringList aptPackages;
  QStringList flatpakApps;
  QSet<QString> seenApt;
  QSet<QString> seenFlatpak;

  auto addApt = [&](const QString &pkg) {
    if (!pkg.isEmpty() && !seenApt.contains(pkg)) {
      seenApt.insert(pkg);
      aptPackages << pkg;
    }
  };
  auto addFlatpak = [&](const QString &app) {
    if (!app.isEmpty() && !seenFlatpak.contains(app)) {
      seenFlatpak.insert(app);
      flatpakApps << app;
    }
  };

  // Profiles are resolved here too, so changing profile and restarting
  // Welcome does not leave an inconsistent package list behind.
  if (m_installProfile == "minimal") {
    // No additional applications.
  } else if (m_installProfile == "normal") {
    addApt("ffmpeg");
    addApt("vlc");
    addApt("libreoffice");
  } else {
    for (const QString &item : m_selectedSoftware) {
      if (item.contains('.') && !item.startsWith("/")) addFlatpak(item);
      else addApt(item);
    }
  }

  if (aptPackages.isEmpty() && flatpakApps.isEmpty()) return true;

  if (!hasExecutable("pkexec")) {
    if (m_softwareStatus) m_softwareStatus->setText(tr("Không tìm thấy pkexec; bỏ qua cài phần mềm bổ sung."));
    return false;
  }

  if (m_softwareStatus) {
    m_softwareStatus->setText(tr("Đang cài phần mềm. Có thể cần nhập mật khẩu quản trị...\n\nGói APT: %1\nỨng dụng Flatpak: %2")
                                  .arg(aptPackages.join(", "), flatpakApps.join(", ")));
    qApp->processEvents();
  }

  // All identifiers originate from the fixed UI list, but quote them anyway
  // before passing the combined command through pkexec/sh.
  auto shellQuote = [](const QString &value) {
    QString out = value;
    out.replace("'", "'\\''");
    return "'" + out + "'";
  };

  // Packages that intentionally pull a large dependency closure when
  // installed from Debian Testing — a newer kernel or a whole desktop
  // environment metapackage. The per-package Testing safety check below
  // (exit 42) blocks ANY package outside the user's exact selection from
  // being upgraded; that's correct for a single app, but wrong for a
  // DE/kernel swap, which is EXPECTED to upgrade dozens of dependent
  // libraries — that's the whole point of the feature, not a mistake to
  // block. Route these through -t testing directly, without the closure
  // check, while every other package keeps the strict protection.
  static const QSet<QString> kHeavyTestingPackages = {
      "linux-image-amd64",
      "cinnamon-desktop-environment",
      "task-xfce-desktop",
      "kde-plasma-desktop",
      "gnome-session",
      "mate-desktop-environment",
      "lxqt",
  };

  QStringList commands;
  if (!aptPackages.isEmpty()) {
    if (m_debianTesting && isDebianSystem()) {
      QStringList strictPackages, heavyPackages;
      for (const QString &pkg : aptPackages) {
        (kHeavyTestingPackages.contains(pkg) ? heavyPackages : strictPackages) << pkg;
      }

      // Debian Testing is opt-in and only used when this Welcome option is enabled.
      // Keep the source explicit and prefer Testing only for the selected packages.
      commands << "printf '%s\n' 'deb http://deb.debian.org/debian testing main contrib non-free non-free-firmware' > /etc/apt/sources.list.d/hyggshi-testing.list";
      commands << "printf '%s\n' 'Package: *' 'Pin: release a=testing' 'Pin-Priority: 100' > /etc/apt/preferences.d/99-hyggshi-testing";
      commands << "apt-get update";

      if (!strictPackages.isEmpty()) {
        QStringList quoted;
        for (const QString &pkg : strictPackages) quoted << shellQuote(pkg);
        // Selective Testing: simulate first and refuse to proceed if an
        // already-installed package outside the user's explicit selection
        // would be upgraded from Stable to Testing. This protects the stable
        // base (systemd, libc, Cinnamon, core libraries, etc.).
        const QString selectedShell = quoted.join(" ");
        commands << "printf '%s\n' " + selectedShell + " > /tmp/hyggshi-testing-selected";
        commands << "if ! SIM=$(apt-get -s -t testing install " + selectedShell + "); then "
                      "echo 'HYGGSHI-TESTING-BLOCK: apt simulation failed; no packages were changed.' >&2; exit 41; fi; "
                      "printf '%s\n' \"$SIM\" | awk '/^Inst / && /\[.*\] \\(/ && /\(testing/ {print $2}' > /tmp/hyggshi-testing-upgrades; "
                      "if grep -Fvx -f /tmp/hyggshi-testing-selected /tmp/hyggshi-testing-upgrades > /tmp/hyggshi-testing-bad; then "
                      "echo 'HYGGSHI-TESTING-BLOCK: Stable package would be upgraded from Testing:' >&2; cat /tmp/hyggshi-testing-bad >&2; "
                      "echo 'HYGGSHI-TESTING-BLOCK: select fewer packages or install them without Debian Testing.' >&2; exit 42; fi";
        commands << "rm -f /tmp/hyggshi-testing-selected /tmp/hyggshi-testing-upgrades /tmp/hyggshi-testing-bad";
        commands << "apt-get install -y -t testing " + selectedShell;
      }

      if (!heavyPackages.isEmpty()) {
        QStringList quoted;
        for (const QString &pkg : heavyPackages) quoted << shellQuote(pkg);
        // No closure check here on purpose (see kHeavyTestingPackages comment).
        commands << "apt-get install -y -t testing " + quoted.join(' ');
      }
    } else {
      QStringList quoted;
      for (const QString &pkg : aptPackages) quoted << shellQuote(pkg);
      commands << "apt-get update && apt-get install -y " + quoted.join(' ');
    }
  }
  if (!flatpakApps.isEmpty()) {
    QStringList quoted;
    for (const QString &app : flatpakApps) quoted << shellQuote(app);
    // Repair stale system refs/cache and ensure FUSE is available before
    // installing runtimes. This avoids the common revokefs-fuse mount error
    // after an interrupted first download on a fresh ISO.
    commands << "modprobe fuse 2>/dev/null || true; flatpak --system repair || true; flatpak --system remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo && flatpak --system install -y flathub " + quoted.join(' ');
  }

  const int rc = QProcess::execute("pkexec", {"sh", "-c", commands.join(" && ")});
  if (rc != 0) {
    if (m_softwareStatus) {
      if (rc == 42) {
        m_softwareStatus->setText(tr("⚠ Debian Testing đã bị chặn: package bạn chọn sẽ làm nâng cấp một package Stable đang có lên Testing. Hệ thống Stable được giữ nguyên. Hãy chọn ít package hơn hoặc tắt Debian Testing."));
      } else if (rc == 41) {
        m_softwareStatus->setText(tr("Không thể kiểm tra trước thay đổi của Debian Testing. Không có package nào được cài."));
      } else {
        m_softwareStatus->setText(tr("Không cài được một hoặc nhiều phần mềm. Kiểm tra Internet và thử lại trong Hyggshi Welcome."));
      }
    }
    return false;
  }
  if (m_softwareStatus) m_softwareStatus->setText(tr("✓ Đã cài xong phần mềm bổ sung."));
  return true;
}

void MainWindow::finishSetup() {
  if (!m_stack || m_stack->isAnimating()) return;

  const QString desktop = qEnvironmentVariable("XDG_CURRENT_DESKTOP").toLower();
  const QString themeName = m_selectedTheme == "dark" ? "Adwaita-dark" : "Adwaita";

  if (m_selectedTheme != "auto" && desktop.contains("xfce")) {
    if (hasExecutable("xfconf-query")) QProcess::execute("xfconf-query", {"-c", "xsettings", "-p", "/Net/ThemeName", "-s", themeName});
  } else if (hasExecutable("gsettings")) {
    // Cinnamon 6.4's Appearance page follows the GNOME color-scheme key.
    // Setting only gtk-theme made the Dark/Light buttons look selectable but
    // did not reliably change the actual application color scheme. Set both
    // the Cinnamon GTK theme and the shared color-scheme key.
    const QString colorScheme = m_selectedTheme == "dark" ? "prefer-dark"
                                : m_selectedTheme == "light" ? "prefer-light"
                                : "default";
    if (desktop.contains("cinnamon")) {
      setGsettings("org.cinnamon.desktop.interface", "gtk-theme", themeName);
      // BUG (root cause of "icon theme reverts to default after Welcome
      // finishes"): this used to hardcode icon-theme to "Adwaita" here,
      // unconditionally overwriting whatever icon theme the ISO was built
      // with (Tela, Papirus, ...) every single time the user finished
      // Welcome. Icon theme is independent from the light/dark GTK theme
      // choice and must not be touched by this dialog — leave the OS
      // build-time default (desktop.sh / dconf) in place. This also fixes
      // the same regression on every other icon-theme choice, not just
      // Tela, across all build variants.
      setGsettings("org.gnome.desktop.interface", "color-scheme", colorScheme);
      setGsettings("org.gnome.desktop.interface", "gtk-theme", themeName);
    } else if (desktop.contains("mate")) {
      setGsettings("org.mate.interface", "gtk-theme", themeName);
      setGsettings("org.gnome.desktop.interface", "color-scheme", colorScheme);
    } else if (desktop.contains("gnome")) {
      setGsettings("org.gnome.desktop.interface", "gtk-theme", themeName);
      setGsettings("org.gnome.desktop.interface", "color-scheme", colorScheme);
    }
  }

  applyLanguageAndKeyboard();
  applyAccessibility();
  savePreferences();
  installSelectedSoftware();
  savePreferences();

  const QString themeCfg = configDirectory() + "/theme.conf";
  QFile userThemeConf(themeCfg);
  if (userThemeConf.open(QIODevice::WriteOnly | QIODevice::Text | QIODevice::Truncate)) {
    userThemeConf.write("# Generated by hyggshi-welcome\n");
    userThemeConf.write("MODE=" + m_selectedTheme.toUtf8() + "\n");
    userThemeConf.close();
  }

  applyWallpaper(m_selectedWallpaper);

  const bool dontAskAgain = m_dontAskAgainChk == nullptr || m_dontAskAgainChk->isChecked();
  saveFirstRunState(dontAskAgain);
  qApp->quit();
}

void MainWindow::applyWallpaper(const QString &wallpaperPath) {
  if (wallpaperPath.isEmpty() || !QFile::exists(wallpaperPath)) return;
  const QString wallScript = "/usr/local/bin/hyggshi-set-wallpaper.sh";
  if (QFile::exists(wallScript)) { QProcess::startDetached(wallScript, {wallpaperPath}); return; }

  const QString desktop = qEnvironmentVariable("XDG_CURRENT_DESKTOP").toLower();
  const QString fileUri = QUrl::fromLocalFile(wallpaperPath).toString();
  if (desktop.contains("cinnamon") && hasExecutable("gsettings")) setGsettings("org.cinnamon.desktop.background", "picture-uri", fileUri);
  else if (desktop.contains("mate") && hasExecutable("gsettings")) setGsettings("org.mate.background", "picture-filename", wallpaperPath);
  else if (desktop.contains("gnome") && hasExecutable("gsettings")) {
    setGsettings("org.gnome.desktop.background", "picture-uri", fileUri);
    setGsettings("org.gnome.desktop.background", "picture-uri-dark", fileUri);
  } else if (desktop.contains("xfce") && hasExecutable("xfconf-query")) {
    QProcess process;
    process.start("xfconf-query", {"-c", "xfce4-desktop", "-l"});
    if (process.waitForFinished(1200)) {
      const QStringList properties = QString::fromLocal8Bit(process.readAllStandardOutput()).split('\n', Qt::SkipEmptyParts);
      bool changed = false;
      for (const QString &property : properties) {
        if (!property.endsWith("/last-image")) continue;
        QProcess::execute("xfconf-query", {"-c", "xfce4-desktop", "-p", property, "-s", wallpaperPath});
        const QString styleProperty = property.left(property.size() - QString("/last-image").size()) + "/image-style";
        QProcess::execute("xfconf-query", {"-c", "xfce4-desktop", "-p", styleProperty, "-n", "-t", "int", "-s", "5"});
        changed = true;
      }
      if (!changed) QProcess::execute("xfconf-query", {"-c", "xfce4-desktop", "-p", "/backdrop/screen0/monitor0/workspace0/last-image", "-s", wallpaperPath});
    }
  }
}
