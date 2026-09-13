#include "MainWindow.h"

#include <algorithm>

#include <QApplication>
#include <QCheckBox>
#include <QColor>
#include <QComboBox>
#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileDialog>
#include <QFileInfo>
#include <QFont>
#include <QFrame>
#include <QGuiApplication>
#include <QHBoxLayout>
#include <QIcon>
#include <QLabel>
#include <QPainter>
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

#include <pwd.h>
#include <unistd.h>

namespace {

// Page order of the wizard. ALL page-position logic (the hooks in
// goNext(), the navigation dots...) must use these constants instead of
// hardcoded numbers — inserting/removing a page would otherwise shift every
// index.
//
// The "Language & Keyboard" page was removed intentionally: language/keyboard
// are SYSTEM settings, following the systematic flow rather than a
// dedicated wizard page:
//   - locale + keyboard layout are set by Calamares at install time (the
//     "locale"/"keyboard" modules in settings.conf's sequence),
//   - afterwards the user changes them in the desktop's Region & Language /
//     Input Sources.
// Welcome therefore has NO language selector and must not overwrite the
// system's input sources (the old version always forced a single xkb
// layout from that page's 4 choices, overriding the system configuration).
enum WizardPage {
  kPageWelcome = 0,
  kPageProfile,
  kPageNetwork,
  kPageTheme,
  kPageSoftware,
  kPageAccessibility,
  kPageSystemCheck,
  kPageUpdates,
  kPageFeatures,
  kPageFinish,
  kPageCount
};

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

QString shellQuoteArg(const QString &value) {
  QString out = value;
  out.replace("'", "'\\''");
  return "'" + out + "'";
}

// The 3 deb lines for each profile — MUST match exactly with
// [package-debian-test.<profile>] in iso-config/config/config.ini
// (each add-repositoryN = fileaddtext(target=..., content=...)). This is
// a C++-side copy because Welcome runs AFTER installation, on the user's
// machine — the build repo's config.ini/hcl_parser.py isn't available to
// read back. If you change the repo in config.ini, remember to update it
// here too.
QStringList debianTestRepoLines(const QString &profile) {
  if (profile == "full") {
    return {
        "deb http://deb.debian.org/debian testing main contrib non-free non-free-firmware",
        "deb http://deb.debian.org/debian testing-updates main contrib non-free non-free-firmware",
        "deb http://security.debian.org/debian-security testing-security main contrib non-free non-free-firmware",
    };
  }
  if (profile == "normal") {
    return {
        "deb http://deb.debian.org/debian testing main contrib non-free non-free-firmware",
        "deb http://deb.debian.org/debian testing-updates main contrib non-free non-free-firmware",
        "deb http://security.debian.org/debian-security stable-security main contrib non-free non-free-firmware",
    };
  }
  if (profile == "unstable") {
    return {
        "deb http://deb.debian.org/debian testing main contrib non-free non-free-firmware",
        "deb http://deb.debian.org/debian unstable-updates main contrib non-free non-free-firmware",
        "deb http://security.debian.org/debian-security testing-security main contrib non-free non-free-firmware",
    };
  }
  // "default" (and any other unrecognized value) -> Stable, the safest option.
  return {
      "deb http://deb.debian.org/debian stable main contrib non-free non-free-firmware",
      "deb http://deb.debian.org/debian stable-updates main contrib non-free non-free-firmware",
      "deb http://security.debian.org/debian-security stable-security main contrib non-free non-free-firmware",
  };
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
  setWindowTitle(tr("Welcome to Hyggshi OS"));
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
  m_stack->addWidget(buildProfilePage());
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
  m_selectedTheme = settings.value("theme", "auto").toString();
  m_selectedCustomTheme = settings.value("theme_custom_name", "").toString();
  m_reducedMotion = settings.value("accessibility/reduced_motion", false).toBool();
  m_highContrast = settings.value("accessibility/high_contrast", false).toBool();
  m_largeText = settings.value("accessibility/large_text", false).toBool();
  m_installProfile = settings.value("software/profile", "normal").toString();
  m_debianTesting = settings.value("software/debian_testing", false).toBool();
  // Profile: if the user has never saved a name (the key doesn't exist in
  // the file yet), pre-fill from the current GECOS in /etc/passwd so
  // Welcome doesn't make the user retype the name they set during install.
  const QVariant storedFullName = settings.value("profile/full_name");
  m_profileFullName = storedFullName.isNull() ? loginGecos() : storedFullName.toString();
  m_profileAvatarPath = settings.value("profile/avatar").toString();
  if (!m_profileAvatarPath.isEmpty() && !QFile::exists(m_profileAvatarPath)) {
    m_profileAvatarPath.clear();
  }
  if (m_installProfile != "full" && m_installProfile != "normal" &&
      m_installProfile != "minimal" && m_installProfile != "custom") {
    m_installProfile = "normal";
  }
  m_debianTestProfile = settings.value("software/debian_test_profile", "off").toString();
  if (m_debianTestProfile != "off" && m_debianTestProfile != "full" &&
      m_debianTestProfile != "normal" && m_debianTestProfile != "default" &&
      m_debianTestProfile != "unstable") {
    m_debianTestProfile = "off";
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

  if (m_selectedTheme != "light" && m_selectedTheme != "dark" &&
      m_selectedTheme != "auto" && m_selectedTheme != "custom") {
    m_selectedTheme = "auto";
  }
  if (m_selectedTheme == "custom" && m_selectedCustomTheme.isEmpty()) {
    // No custom theme was ever saved (or the saved theme no longer exists
    // on the machine) -> fall back to "auto" to avoid applying an empty theme.
    m_selectedTheme = "auto";
  }
}

void MainWindow::savePreferences() const {
  QDir().mkpath(configDirectory());
  QSettings settings(preferencesPath(), QSettings::IniFormat);
  settings.setValue("theme", m_selectedTheme);
  settings.setValue("theme_custom_name", m_selectedCustomTheme);
  settings.setValue("accessibility/reduced_motion", m_reducedMotion);
  settings.setValue("accessibility/high_contrast", m_highContrast);
  settings.setValue("accessibility/large_text", m_largeText);
  settings.setValue("software/profile", m_installProfile);
  settings.setValue("software/debian_testing", m_debianTesting);
  settings.setValue("software/debian_test_profile", m_debianTestProfile);
  settings.setValue("software/packages", m_selectedSoftware);
  settings.setValue("wallpaper", m_selectedWallpaper);
  settings.setValue("profile/full_name", m_profileFullName);
  settings.setValue("profile/avatar", m_profileAvatarPath);
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

  auto *title = new QLabel(tr("Welcome to Hyggshi OS"));
  title->setAlignment(Qt::AlignCenter);
  title->setStyleSheet("font-size:24px; font-weight:600; color:#f2f3f5;");

  auto *subtitle = new QLabel(tr("Quickly set up your machine in a few steps.\n"
                                "Every choice can be changed later in Settings."));
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

QString MainWindow::loginUserName() {
  if (const passwd *pw = getpwuid(getuid())) return QString::fromLocal8Bit(pw->pw_name);
  return qEnvironmentVariable("USER", "user");
}

QString MainWindow::loginGecos() {
  QString gecos;
  if (const passwd *pw = getpwuid(getuid())) gecos = QString::fromLocal8Bit(pw->pw_gecos);
  // The GECOS field looks like "Full Name,,," — only take the name part.
  gecos = gecos.section(',', 0, 0).trimmed();
  // The installer usually leaves GECOS the same as the login name; treat
  // that as "no display name set" so Welcome leaves the field blank instead
  // of showing the username again.
  if (gecos.isEmpty() || gecos == loginUserName()) return {};
  return gecos;
}

QPixmap MainWindow::renderProfileAvatarPixmap(int size) const {
  QPixmap out(size, size);
  out.fill(Qt::transparent);

  QPainter p(&out);
  p.setRenderHint(QPainter::Antialiasing, true);
  p.setRenderHint(QPainter::SmoothPixmapTransform, true);

  if (!m_profileAvatarPath.isEmpty()) {
    const QPixmap src(m_profileAvatarPath);
    if (!src.isNull()) {
      // Square center-crop then round it off — most DEs also mask avatars
      // into a circle, so rounding it here keeps the preview close to the
      // real result.
      const int side = qMax(1, qMin(src.width(), src.height()));
      const QRect crop((src.width() - side) / 2, (src.height() - side) / 2, side, side);
      p.drawPixmap(0, 0, src.copy(crop).scaled(size, size, Qt::IgnoreAspectRatio,
                                                Qt::SmoothTransformation));
      p.setCompositionMode(QPainter::CompositionMode_DestinationIn);
      QPixmap mask(size, size);
      mask.fill(Qt::transparent);
      QPainter mp(&mask);
      mp.setRenderHint(QPainter::Antialiasing, true);
      mp.setPen(Qt::NoPen);
      mp.setBrush(Qt::white);
      mp.drawRoundedRect(mask.rect(), qreal(size) / 2.0, qreal(size) / 2.0);
      mp.end();
      p.drawPixmap(0, 0, mask);
      p.end();
      return out;
    }
    // An image was picked but couldn't be read -> fall back to the letter
    // avatar instead of leaving the preview blank.
  }

  const QString name = m_profileFullName.trimmed();
  const QString key = name.isEmpty() ? loginUserName() : name;
  QChar letter('~');
  for (const QChar ch : key) {
    if (ch.isLetter()) {
      letter = ch.toUpper();
      break;
    }
  }

  // Minimal pastel palette — color picked via qHash(name) so each person's
  // avatar stays stable across different runs of Welcome.
  static const char *kAvatarColors[] = {
      "#5aa9ff", "#f28b82", "#81c995", "#fbbc5a",
      "#c58af9", "#78d9ec", "#ff8bcb", "#9aa0ab",
  };
  const uint colorIndex = qHash(key) % (sizeof(kAvatarColors) / sizeof(kAvatarColors[0]));
  p.setPen(QColor(0, 0, 0, 40));
  p.setBrush(QColor(QLatin1String(kAvatarColors[colorIndex])));
  p.drawEllipse(1, 1, size - 2, size - 2);

  QFont avatarFont = p.font();
  avatarFont.setPixelSize(qMax(10, int(size * 0.42)));
  avatarFont.setBold(true);
  p.setFont(avatarFont);
  p.setPen(Qt::white);
  p.drawText(out.rect(), Qt::AlignCenter, QString(letter));
  p.end();
  return out;
}

void MainWindow::updateProfileAvatarPreview() {
  if (m_profileAvatarPreview) m_profileAvatarPreview->setPixmap(renderProfileAvatarPixmap(96));
}

void MainWindow::pickProfileAvatar() {
  const QString picturesDir = QDir::homePath() + "/Pictures";
  const QString startDir = QDir(picturesDir).exists() ? picturesDir : QDir::homePath();
  const QString file = QFileDialog::getOpenFileName(
      this, tr("Choose profile picture"), startDir,
      tr("Images (*.png *.jpg *.jpeg *.bmp *.webp *.gif)"));
  if (file.isEmpty()) return;
  if (QPixmap(file).isNull()) {
    QMessageBox::warning(this, tr("Invalid image"),
                         tr("This file couldn't be read as an image. Please choose a different PNG/JPG file."));
    return;
  }
  m_profileAvatarPath = file;
  updateProfileAvatarPreview();
  savePreferences();
}

QWidget *MainWindow::buildProfilePage() {
  auto *page = new QWidget;
  auto *layout = new QVBoxLayout(page);
  layout->setContentsMargins(70, 45, 70, 35);
  layout->setSpacing(14);

  auto *title = new QLabel(tr("Your profile"));
  title->setStyleSheet("font-size:20px; font-weight:600; color:#f2f3f5;");
  auto *desc = new QLabel(tr("Set a display name and profile picture for the account. They appear on "
                             "the login screen, the user menu, and Settings."));
  desc->setWordWrap(true);
  desc->setStyleSheet("color:#9aa0ab; font-size:12px;");

  auto *row = new QHBoxLayout;
  row->setSpacing(22);

  m_profileAvatarPreview = new QLabel;
  m_profileAvatarPreview->setFixedSize(96, 96);
  m_profileAvatarPreview->setAlignment(Qt::AlignCenter);
  m_profileAvatarPreview->setToolTip(tr("Profile picture — choose your own photo or keep the letter avatar"));
  updateProfileAvatarPreview();

  auto *fieldCol = new QVBoxLayout;
  fieldCol->setSpacing(8);

  auto *nameLabel = new QLabel(tr("Display name"));
  nameLabel->setStyleSheet("color:#c7cad1; font-size:12px;");
  m_profileNameEdit = new QLineEdit(m_profileFullName);
  m_profileNameEdit->setPlaceholderText(loginUserName());
  m_profileNameEdit->setMaxLength(64);
  m_profileNameEdit->setClearButtonEnabled(true);
  m_profileNameEdit->setStyleSheet(
      "QLineEdit { background:#1e2027; color:#e6e7ea; border:1px solid #2c2f38;"
      " border-radius:6px; padding:7px 10px; }"
      "QLineEdit:focus { border:1px solid #5aa9ff; }");

  m_profileLoginLabel = new QLabel(
      tr("Login name: <b>%1</b> — cannot be changed after the system is installed.")
          .arg(loginUserName().toHtmlEscaped()));
  m_profileLoginLabel->setTextFormat(Qt::RichText);
  m_profileLoginLabel->setStyleSheet("color:#6f7480; font-size:11px;");

  m_profileAvatarBtn = new QPushButton(tr("Choose picture..."));
  m_profileAvatarResetBtn = new QPushButton(tr("Use letter avatar"));
  for (QPushButton *btn : {m_profileAvatarBtn, m_profileAvatarResetBtn}) {
    btn->setCursor(Qt::PointingHandCursor);
    btn->setStyleSheet("QPushButton { padding:6px 12px; font-size:12px; }");
  }
  auto *avatarBtnRow = new QHBoxLayout;
  avatarBtnRow->setSpacing(10);
  avatarBtnRow->addWidget(m_profileAvatarBtn);
  avatarBtnRow->addWidget(m_profileAvatarResetBtn);
  avatarBtnRow->addStretch(1);

  fieldCol->addWidget(nameLabel);
  fieldCol->addWidget(m_profileNameEdit);
  fieldCol->addSpacing(4);
  fieldCol->addLayout(avatarBtnRow);
  fieldCol->addWidget(m_profileLoginLabel);
  fieldCol->addStretch(1);

  row->addWidget(m_profileAvatarPreview, 0, Qt::AlignTop);
  row->addLayout(fieldCol, 1);

  auto *note = new QLabel(tr(
      "The display name and avatar are saved to the account profile (GECOS + "
      "~/.face + AccountsService). When syncing with the system, you may be "
      "prompted for an administrator password — it's fine to skip it, your "
      "choices are still saved in welcome.conf."));
  note->setWordWrap(true);
  note->setStyleSheet("color:#6f7480; font-size:11px;");

  layout->addWidget(title);
  layout->addSpacing(6);
  layout->addWidget(desc);
  layout->addLayout(row, 1);
  layout->addWidget(note);

  connect(m_profileNameEdit, &QLineEdit::textChanged, this, [this](const QString &text) {
    m_profileFullName = text.trimmed();
    // The letter avatar updates as you type; the chosen picture stays unchanged.
    if (m_profileAvatarPath.isEmpty()) updateProfileAvatarPreview();
  });
  connect(m_profileNameEdit, &QLineEdit::editingFinished, this, [this]() {
    m_profileFullName = m_profileNameEdit->text().trimmed();
    savePreferences();
  });
  connect(m_profileAvatarBtn, &QPushButton::clicked, this, &MainWindow::pickProfileAvatar);
  connect(m_profileAvatarResetBtn, &QPushButton::clicked, this, [this]() {
    m_profileAvatarPath.clear();
    updateProfileAvatarPreview();
    savePreferences();
  });
  return page;
}

QWidget *MainWindow::buildNetworkPage() {
  auto *page = new QWidget;
  auto *layout = new QVBoxLayout(page);
  layout->setContentsMargins(70, 55, 70, 40);
  layout->setSpacing(14);

  auto *title = new QLabel(tr("Network connection"));
  title->setStyleSheet("font-size:20px; font-weight:600; color:#f2f3f5;");
  auto *desc = new QLabel(tr("Quick check of the current connection. Hyggshi Welcome doesn't manage Wi-Fi itself — it opens the system tool when needed."));
  desc->setWordWrap(true);
  desc->setStyleSheet("color:#9aa0ab; font-size:12px;");

  m_networkStatus = new QLabel(tr("Checking..."));
  m_networkStatus->setStyleSheet("font-size:14px; color:#d8dbe1; padding:14px; border:1px solid #2c2f38; border-radius:8px;");
  m_networkStatus->setWordWrap(true);

  auto *row = new QHBoxLayout;
  auto *refresh = new QPushButton(tr("Check again"));
  auto *settings = new QPushButton(tr("Open Network Settings"));
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

  auto *title = new QLabel(tr("Choose an appearance"));
  title->setStyleSheet("font-size:20px; font-weight:600; color:#f2f3f5;");

  auto *cardsRow = new QHBoxLayout;
  cardsRow->setSpacing(16);
  m_themeGroup = new QButtonGroup(page);
  m_themeGroup->setExclusive(true);

  const QVector<ThemeOpt> opts = {
      {"light", tr("Light"), "/usr/share/backgrounds/hyggshi/car-light.png"},
      {"dark", tr("Dark"), "/usr/share/backgrounds/hyggshi/car-Dark.png"},
      {"auto", tr("Auto"), "/usr/share/backgrounds/hyggshi/car-light.png"},
      {"custom", tr("Custom"), "/usr/share/backgrounds/hyggshi/car-light.png"},
  };

  for (int i = 0; i < opts.size(); ++i) {
    const auto opt = opts.at(i);
    auto *card = new QPushButton;
    card->setCheckable(true);
    card->setFixedSize(150, 110);
    card->setCursor(Qt::PointingHandCursor);
    card->setText("\n\n" + opt.label);

    // "custom" shares the theme-auto.png background image since this theme
    // is user-chosen and has no fixed illustration.
    const QString imageName =
        QString("theme-%1.png").arg(opt.id == "custom" ? "auto" : opt.id);
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
      updateCustomThemeVisibility();
      savePreferences();
    });
    cardsRow->addWidget(card);
  }

  if (!m_themeGroup->checkedButton()) {
    if (QAbstractButton *button = m_themeGroup->button(2)) button->setChecked(true);
    m_selectedTheme = "auto";
  }

  m_customThemeLabel = new QLabel(tr("Custom GTK theme"));
  m_customThemeLabel->setStyleSheet("color:#c7cad1; font-size:12px; margin-top:10px;");
  m_customThemeBox = new QComboBox;
  const QStringList installedThemes = listInstalledThemes();
  if (installedThemes.isEmpty()) {
    m_customThemeBox->addItem(tr("No themes found in ~/.themes"), QString());
    m_customThemeBox->setEnabled(false);
  } else {
    for (const QString &themeName : installedThemes) {
      m_customThemeBox->addItem(themeName, themeName);
    }
    const int customIndex = m_customThemeBox->findData(m_selectedCustomTheme);
    if (customIndex >= 0) {
      m_customThemeBox->setCurrentIndex(customIndex);
    } else if (!installedThemes.isEmpty()) {
      m_selectedCustomTheme = installedThemes.first();
    }
  }
  connect(m_customThemeBox, QOverload<int>::of(&QComboBox::currentIndexChanged), this,
          [this](int index) {
            if (index < 0) return;
            const QString value = m_customThemeBox->itemData(index).toString();
            if (value.isEmpty()) return;
            m_selectedCustomTheme = value;
            savePreferences();
          });
  updateCustomThemeVisibility();

  auto *wallpaperLabel = new QLabel(tr("Wallpaper"));
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

  auto *note = new QLabel(tr("Auto will follow the desktop's current theme once setup is complete."));
  note->setWordWrap(true);
  note->setStyleSheet("color:#6f7480; font-size:11px; margin-top:10px;");

  layout->addWidget(title);
  layout->addSpacing(8);
  layout->addLayout(cardsRow);
  layout->addWidget(m_customThemeLabel);
  layout->addWidget(m_customThemeBox);
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

  auto *title = new QLabel(tr("Customize & Software"));
  title->setStyleSheet("font-size:20px; font-weight:600; color:#f2f3f5;");
  auto *desc = new QLabel(tr("The choices that used to live in Customize and Additional Software are now done in Hyggshi Welcome after login. LibreOffice, ONLYOFFICE, WPS Office, VLC, Visual Studio Code, Google Chrome and many other apps are available. Pick a suitable Office bundle or use Customize."));
  desc->setWordWrap(true);
  desc->setStyleSheet("color:#9aa0ab; font-size:12px;");

  auto *profileLabel = new QLabel(tr("Software install profile"));
  profileLabel->setStyleSheet("color:#c7cad1; font-size:12px;");
  m_installProfileBox = new QComboBox;
  m_installProfileBox->addItem(tr("Full — install everything"), "full");
  m_installProfileBox->addItem(tr("Normal — basic set"), "normal");
  m_installProfileBox->addItem(tr("Minimal — no extras"), "minimal");
  m_installProfileBox->addItem(tr("Custom — pick your own"), "custom");
  const int profileIndex = m_installProfileBox->findData(m_installProfile);
  m_installProfileBox->setCurrentIndex(profileIndex >= 0 ? profileIndex : 1);

  auto *testingBox = new QCheckBox(tr("Use Debian Testing packages"));
  testingBox->setToolTip(tr("Only applies to Debian. Uses the Debian Testing repository when installing the selected software."));
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
        this, tr("Warning: Debian Testing"),
        tr("Debian Testing is a development repository that may contain unstable packages and could cause conflicts or make the system harder to upgrade.\n\nOnly enable this option if you understand the risk and want Testing packages for the software you've selected. Hyggshi OS doesn't recommend enabling it on your main machine.\n\nDo you want to continue?"),
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

  auto *testProfileLabel = new QLabel(tr("System's root apt repository (Debian)"));
  testProfileLabel->setStyleSheet("color:#c7cad1; font-size:12px;");
  testProfileLabel->setVisible(isDebian);
  m_debianTestProfileBox = new QComboBox;
  m_debianTestProfileBox->setVisible(isDebian);
  m_debianTestProfileBox->setToolTip(tr(
      "Only applies to Debian. Overwrites /etc/apt/sources.list according to "
      "the selected profile — different from the 'Use Debian Testing packages' "
      "checkbox above (that one only affects the packages you select below)."));
  m_debianTestProfileBox->addItem(tr("Keep as-is (no change)"), "off");
  m_debianTestProfileBox->addItem(tr("full — Testing, most up-to-date packages"), "full");
  m_debianTestProfileBox->addItem(tr("normal — Testing, recommended"), "normal");
  m_debianTestProfileBox->addItem(tr("default — Stable, most stable"), "default");
  m_debianTestProfileBox->addItem(tr("unstable — Sid, testing only"), "unstable");
  {
    const int idx = m_debianTestProfileBox->findData(m_debianTestProfile);
    m_debianTestProfileBox->setCurrentIndex(idx >= 0 ? idx : 0);
  }
  connect(m_debianTestProfileBox, QOverload<int>::of(&QComboBox::currentIndexChanged), this,
          [this](int index) {
            if (index < 0 || !m_debianTestProfileBox) return;
            const QString chosen = m_debianTestProfileBox->itemData(index).toString();
            const QString previous = m_debianTestProfile;

            if (chosen != "off" && chosen != "default") {
              QMessageBox::StandardButton answer = QMessageBox::warning(
                  this, tr("Warning: changing the root apt repository"),
                  tr("You're about to overwrite the whole system's /etc/apt/sources.list "
                     "with profile '%1'. Testing/Unstable profiles may contain "
                     "unstable packages, affecting EVERY package on the machine (not just "
                     "the software you install yourself). Hyggshi OS doesn't recommend using "
                     "this on your main machine.\n\nAre you sure you want to continue?")
                      .arg(chosen),
                  QMessageBox::Cancel | QMessageBox::Ok, QMessageBox::Cancel);
              if (answer != QMessageBox::Ok) {
                const QSignalBlocker blocker(m_debianTestProfileBox);
                Q_UNUSED(blocker);
                const int prevIdx = m_debianTestProfileBox->findData(previous);
                m_debianTestProfileBox->setCurrentIndex(prevIdx >= 0 ? prevIdx : 0);
                return;
              }
            }

            m_debianTestProfile = chosen;
            savePreferences();
            if (chosen != "off") {
              applyDebianTestProfile(chosen);
            }
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

  auto *softwareLabel = new QLabel(tr("Additional software (APT + Flathub)"));
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
      {"ffmpeg", "Multimedia codecs (FFmpeg)", "apt", ""},
      {"vlc", "VLC — media player", "apt", "media"},
      {"libreoffice", "LibreOffice — office suite", "apt", "office"},
      {"unattended-upgrades", "Automatic updates (unattended-upgrades)", "apt", ""},
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

  // Debian Testing: adds 2 extra "heavy" options — the latest kernel and
  // the latest Desktop Environment from the Testing repo. Only shown on
  // Debian (isDebian) since "Use Debian Testing packages" above also only
  // applies to Debian. The DE shows EXACTLY 1 metapackage matching the
  // machine's current desktop (XDG_CURRENT_DESKTOP) — the ISO only installs
  // a single DE, so there's no reason to list all 6 other DEs that don't
  // exist on the machine.
  if (isDebian) {
    options.push_back({"linux-image-amd64", "Latest Linux kernel (Debian Testing)", "apt", "kernel"});

    const QString curDesktop = qEnvironmentVariable("XDG_CURRENT_DESKTOP").toLower();
    if (curDesktop.contains("cinnamon")) {
      options.push_back({"cinnamon-desktop-environment", "Latest Cinnamon (Debian Testing)", "apt", "de"});
    } else if (curDesktop.contains("xfce")) {
      options.push_back({"task-xfce-desktop", "Latest XFCE (Debian Testing)", "apt", "de"});
    } else if (curDesktop.contains("kde") || curDesktop.contains("plasma")) {
      options.push_back({"kde-plasma-desktop", "Latest KDE Plasma (Debian Testing)", "apt", "de"});
    } else if (curDesktop.contains("gnome")) {
      options.push_back({"gnome-session", "Latest GNOME (Debian Testing)", "apt", "de"});
    } else if (curDesktop.contains("mate")) {
      options.push_back({"mate-desktop-environment", "Latest MATE (Debian Testing)", "apt", "de"});
    } else if (curDesktop.contains("lxqt")) {
      options.push_back({"lxqt", "Latest LXQt (Debian Testing)", "apt", "de"});
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
      check->setToolTip(tr("Can only be installed when 'Use Debian Testing packages' is enabled above. Will pull in many dependent packages that also get upgraded to the Testing version."));
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

  m_softwareStatus = new QLabel(tr("Packages will be installed when you click 'Get started' at the end of Welcome."));
  m_softwareStatus->setWordWrap(true);
  m_softwareStatus->setStyleSheet("font-size:11px; color:#6f7480;");

  outer->addWidget(title);
  outer->addWidget(desc);
  outer->addSpacing(4);
  outer->addWidget(profileLabel);
  outer->addWidget(m_installProfileBox);
  outer->addWidget(testingBox);
  outer->addSpacing(4);
  outer->addWidget(testProfileLabel);
  outer->addWidget(m_debianTestProfileBox);
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

  auto *title = new QLabel(tr("Accessibility"));
  title->setStyleSheet("font-size:20px; font-weight:600; color:#f2f3f5;");
  auto *desc = new QLabel(tr("The options below are saved for the current account and can be changed later."));
  desc->setWordWrap(true);
  desc->setStyleSheet("color:#9aa0ab; font-size:12px;");

  m_reducedMotionChk = new QCheckBox(tr("Reduce motion and animation"));
  m_highContrastChk = new QCheckBox(tr("Increase interface contrast"));
  m_largeTextChk = new QCheckBox(tr("Larger text"));
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

  auto *title = new QLabel(tr("System check"));
  title->setStyleSheet("font-size:20px; font-weight:600; color:#f2f3f5;");

  m_systemStatus = new QLabel;
  m_systemStatus->setWordWrap(true);
  m_systemStatus->setTextFormat(Qt::RichText);
  m_systemStatus->setStyleSheet("font-size:12px; color:#d8dbe1; padding:14px; border:1px solid #2c2f38; border-radius:8px;");

  auto *refresh = new QPushButton(tr("Check again"));
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

  auto *title = new QLabel(tr("System updates"));
  title->setStyleSheet("font-size:20px; font-weight:600; color:#f2f3f5;");
  auto *desc = new QLabel(tr("Only checks the update status; Welcome doesn't install packages itself or request admin rights."));
  desc->setWordWrap(true);
  desc->setStyleSheet("color:#9aa0ab; font-size:12px;");

  m_updateStatus = new QLabel(tr("Not checked yet."));
  m_updateStatus->setWordWrap(true);
  m_updateStatus->setStyleSheet("font-size:13px; color:#d8dbe1; padding:14px; border:1px solid #2c2f38; border-radius:8px;");

  m_updateCheckBtn = new QPushButton(tr("Check for updates"));
  m_updateCheckBtn->setCursor(Qt::PointingHandCursor);
  connect(m_updateCheckBtn, &QPushButton::clicked, this, &MainWindow::checkForUpdates);

  auto *open = new QPushButton(tr("Open System Updater"));
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
      {"🚀", tr("Fast startup"), tr("Hyggshi OS optimizes background resources and experience for everyday use.")},
      {"🎨", tr("Customizable interface"), tr("Change theme, icons and panel easily right from System Settings.")},
      {"🧩", tr("Its own ecosystem"), tr("nexfetch, HOSC and other Hyggshi components are integrated in a cohesive way.")},
      {"🔒", tr("Secure by default"), tr("Sensible baseline settings are prepared ahead of time to get you started.")},
  };

  auto *page = new QWidget;
  auto *layout = new QVBoxLayout(page);
  layout->setContentsMargins(70, 45, 70, 30);
  layout->setSpacing(10);
  layout->setAlignment(Qt::AlignCenter);

  auto *title = new QLabel(tr("Highlighted features"));
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
  auto *title = new QLabel(tr("All set!"));
  title->setAlignment(Qt::AlignCenter);
  title->setStyleSheet("font-size:22px; font-weight:600; color:#f2f3f5;");
  auto *desc = new QLabel(tr("Hyggshi OS is ready. Your choices have been saved."));
  desc->setAlignment(Qt::AlignCenter);
  desc->setStyleSheet("font-size:13px; color:#9aa0ab;");
  desc->setWordWrap(true);

  auto *communityLabel = new QLabel(tr("Join the Hyggshi OS community"));
  communityLabel->setAlignment(Qt::AlignCenter);
  communityLabel->setStyleSheet("font-size:12px; color:#9aa0ab;");

  auto *socialRow = new QHBoxLayout;
  socialRow->setAlignment(Qt::AlignCenter);
  socialRow->setSpacing(12);
  socialRow->addWidget(makeSocialButton(":/icons/discord.png",
                                         "https://discord.gg/C2wnU8Vz6U", tr("Discord")));
  socialRow->addWidget(makeSocialButton(":/icons/x.png",
                                         "https://x.com/hyggshios", tr("X (Twitter)")));

  m_dontAskAgainChk = new QCheckBox(tr("Don't ask again next time"));
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

  m_backBtn = new QPushButton(tr("Back"));
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

  m_skipBtn = new QPushButton(tr("Skip"));
  m_skipBtn->setCursor(Qt::PointingHandCursor);
  connect(m_skipBtn, &QPushButton::clicked, this, &MainWindow::finishSetup);

  m_nextBtn = new QPushButton(tr("Continue"));
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
  m_nextBtn->setText(isLast ? tr("Get started") : tr("Continue"));
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
  if (index == kPageProfile) {
    // editingFinished doesn't necessarily fire when the user clicks "Continue"
    // right after typing — commit the name + save once before leaving the page.
    if (m_profileNameEdit) m_profileFullName = m_profileNameEdit->text().trimmed();
    savePreferences();
  }
  if (index == kPageNetwork) refreshNetworkStatus();
  if (index == kPageSystemCheck) refreshSystemStatus();
  if (index == kPageUpdates) setUpdateStatus(tr("You can check for updates now or continue."));
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

// Syncs the profile chosen on the Profile page into the system when
// clicking "Get started". Three parts, each independent and best-effort:
//   1) ~/.face (+ ~/.face.icon) — 192px square center-crop image. GDM,
//      LightDM, Cinnamon, KDE... all read this standard location, so the
//      avatar works even without root privileges.
//   2) chfn -f <name> — updates GECOS so the login screen shows the
//      display name. Needs root, so it runs via pkexec; if pkexec is
//      missing, this part is skipped (the value is already in
//      welcome.conf, and other system tools can still change it later).
//   3) /var/lib/AccountsService/users/<user> — the [User] section stores
//      Icon= and SystemAccount=false. Does NOT overwrite the whole file
//      (other keys like XSession/Language keep their values): the old
//      Icon/SystemAccount lines are removed then the new keys are
//      appended — this file always has exactly one [User] section, so
//      the append still lands in the right section.
void MainWindow::applyProfileChanges() {
  const QString userName = loginUserName();
  const QString home = QDir::homePath();

  bool faceWritten = false;
  if (!m_profileAvatarPath.isEmpty() && QFile::exists(m_profileAvatarPath)) {
    const QPixmap src(m_profileAvatarPath);
    if (!src.isNull()) {
      const int kAvatarSize = 192;
      const int side = qMax(1, qMin(src.width(), src.height()));
      const QPixmap square = src.copy((src.width() - side) / 2, (src.height() - side) / 2,
                                      side, side)
                                 .scaled(kAvatarSize, kAvatarSize, Qt::IgnoreAspectRatio,
                                         Qt::SmoothTransformation);
      faceWritten = square.save(home + "/.face", "PNG");
      if (faceWritten) {
        // Some DEs (KDE Plasma) use the convention ~/.face.icon instead of ~/.face.
        QFile::remove(home + "/.face.icon");
        QFile::copy(home + "/.face", home + "/.face.icon");
      }
    }
  }

  QString desiredName = m_profileFullName.trimmed();
  if (desiredName.size() > 64) desiredName = desiredName.left(64);
  const bool nameChanged = !desiredName.isEmpty() && desiredName != loginGecos();
  if (!nameChanged && !faceWritten) return;

  // Root (live ISO session) runs sh directly; a regular user goes through
  // pkexec. No pkexec -> skip the system part, ~/.face above still takes effect.
  const bool asRoot = (geteuid() == 0);
  if (!asRoot && !hasExecutable("pkexec")) return;

  QStringList script;
  if (nameChanged) {
    script << QString("if command -v chfn >/dev/null 2>&1; then chfn -f %1 %2 || true; fi")
                  .arg(shellQuoteArg(desiredName), shellQuoteArg(userName));
  }
  if (faceWritten) {
    const QString faceFile = home + "/.face";
    const QString usersFile = "/var/lib/AccountsService/users/" + userName;
    // Join commands one at a time with ';' (avoids the &&/|| precedence
    // pitfall in sh) and pass the path through a variable + printf '%s'
    // (a path containing '%' won't be misread by printf as a format specifier).
    const QStringList asScript = {
        QString("F=%1").arg(shellQuoteArg(usersFile)),
        QString("FACE=%1").arg(shellQuoteArg(faceFile)),
        "mkdir -p /var/lib/AccountsService/users",
        "if [ ! -f \"$F\" ]; then printf '[User]\\n' > \"$F\"; fi",
        "grep -vE '^(Icon|SystemAccount)=' \"$F\" > \"$F.hyggshi-new\" 2>/dev/null || : > \"$F.hyggshi-new\"",
        "cat \"$F.hyggshi-new\" > \"$F\"",
        "rm -f \"$F.hyggshi-new\"",
        "grep -q '^\\[User\\]' \"$F\" || sed -i '1i [User]' \"$F\"",
        "printf '%s\\n' \"Icon=$FACE\" 'SystemAccount=false' >> \"$F\"",
    };
    script << asScript.join("; ");
  }
  if (script.isEmpty()) return;

  const QString joined = script.join("; ");
  if (asRoot) QProcess::execute("sh", {"-c", joined});
  else QProcess::execute("pkexec", {"sh", "-c", joined});
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
    text = connected ? tr("✓ Connected\nDevice: %1%2").arg(interfaceName, type.isEmpty() ? QString() : " (" + type + ")")
                     : tr("⚠ No active network connection.");
  } else {
    const QStringList route = commandOutput("sh", {"-c", "ip route get 1.1.1.1 2>/dev/null"});
    connected = !route.isEmpty();
    text = connected ? tr("✓ An active network route was found.") : tr("⚠ Could not determine network status.");
  }
  if (!hasExecutable("nmcli")) text += "\n" + tr("NetworkManager/nmcli is not available; please check with the desktop's tool.");
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

  QString memoryInfo = tr("Couldn't read RAM");
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
  html += tr("%1 User configuration writable<br>").arg(configWritable ? "✓" : "✗");
  html += tr("%1 Desktop environment detected<br>").arg(desktopDetected ? "✓" : "⚠");
  html += tr("%1 Theme/settings tool available<br>").arg(settings ? "✓" : "⚠");
  html += tr("%1 Wallpaper tool available").arg(wallpaperTools ? "✓" : "⚠");
  m_systemStatus->setText(html);
}

void MainWindow::setUpdateStatus(const QString &text) {
  if (m_updateStatus) m_updateStatus->setText(text);
}

void MainWindow::checkForUpdates() {
  if (!m_updateCheckBtn || !m_updateStatus) return;
  m_updateCheckBtn->setEnabled(false);
  setUpdateStatus(tr("Checking..."));

  auto *process = new QProcess(this);
  QString program;
  QStringList args;
  if (hasExecutable("checkupdates")) { program = "checkupdates"; }
  else if (hasExecutable("apt-get")) { program = "apt-get"; args = {"-s", "upgrade"}; }
  else if (hasExecutable("dnf")) { program = "dnf"; args = {"-q", "check-update"}; }
  else if (hasExecutable("zypper")) { program = "zypper"; args = {"--non-interactive", "list-updates"}; }
  else if (hasExecutable("pacman") && hasExecutable("checkupdates")) { program = "checkupdates"; }

  if (program.isEmpty()) {
    setUpdateStatus(tr("No update-checking tool found. Please use the desktop's System Updater."));
    m_updateCheckBtn->setEnabled(true);
    process->deleteLater();
    return;
  }

  connect(process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished), this,
          [this, process](int exitCode, QProcess::ExitStatus status) {
            const QString out = QString::fromLocal8Bit(process->readAllStandardOutput()).trimmed();
            const QString err = QString::fromLocal8Bit(process->readAllStandardError()).trimmed();
            m_updateCheckBtn->setEnabled(true);
            if (status != QProcess::NormalExit) setUpdateStatus(tr("Couldn't complete the update check."));
            else if (exitCode == 0) setUpdateStatus(out.isEmpty() ? tr("✓ No packages need updating.") : tr("✓ The update tool returned:\n%1").arg(out.left(1200)));
            else if (exitCode == 100 && err.isEmpty()) setUpdateStatus(tr("Packages need updating. Open System Updater for details."));
            else setUpdateStatus(err.isEmpty() ? tr("Couldn't determine the update status.") : err.left(1200));
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

// Scans the standard GTK theme directories (system + user) and returns
// the names of valid themes (containing index.theme or a gtk-3.0/gtk-4.0
// folder), for the user to pick as the "Custom" theme in Welcome.
QStringList MainWindow::listInstalledThemes() const {
  QStringList dirs = {
      "/usr/share/themes",
      "/usr/local/share/themes",
      QDir::homePath() + "/.themes",
      QDir::homePath() + "/.local/share/themes",
  };

  QSet<QString> found;
  for (const QString &dirPath : dirs) {
    QDir dir(dirPath);
    if (!dir.exists()) continue;
    const QFileInfoList entries =
        dir.entryInfoList(QDir::Dirs | QDir::NoDotAndDotDot, QDir::Name);
    for (const QFileInfo &entry : entries) {
      const QString themeDir = entry.absoluteFilePath();
      const bool looksLikeGtkTheme =
          QFile::exists(themeDir + "/index.theme") ||
          QDir(themeDir + "/gtk-3.0").exists() ||
          QDir(themeDir + "/gtk-4.0").exists();
      if (looksLikeGtkTheme) found.insert(entry.fileName());
    }
  }

  QStringList result = found.values();
  std::sort(result.begin(), result.end(), [](const QString &a, const QString &b) {
    return a.compare(b, Qt::CaseInsensitive) < 0;
  });
  return result;
}

void MainWindow::updateCustomThemeVisibility() {
  if (!m_customThemeBox || !m_customThemeLabel) return;
  const bool isCustom = m_selectedTheme == "custom";
  m_customThemeBox->setVisible(isCustom);
  m_customThemeLabel->setVisible(isCustom);
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

void MainWindow::applyDebianTestProfile(const QString &profile) {
  if (!isDebianSystem()) return;
  if (!hasExecutable("pkexec")) {
    if (m_softwareStatus) {
      m_softwareStatus->setText(
          tr("pkexec not found; can't switch the root apt repository to profile '%1'.").arg(profile));
    }
    return;
  }

  const QStringList lines = debianTestRepoLines(profile);
  QStringList printfArgs;
  printfArgs << "printf" << "'%s\\n'";
  for (const QString &line : lines) printfArgs << shellQuoteArg(line);

  // Overwrites /etc/apt/sources.list (matches target="/etc/apt/sources.list"
  // in [package-debian-test.<profile>] of config.ini) then runs apt-get
  // update right away so the user sees any error (bad mirror, no network...)
  // while still in Welcome, instead of only discovering it at the next
  // system update.
  const QString command = printfArgs.join(' ') + " > /etc/apt/sources.list && apt-get update";

  if (m_softwareStatus) {
    m_softwareStatus->setText(
        tr("Switching the root apt repository to profile '%1'. An admin password may be required...").arg(profile));
    qApp->processEvents();
  }

  const int rc = QProcess::execute("pkexec", {"sh", "-c", command});
  if (m_softwareStatus) {
    if (rc == 0) {
      m_softwareStatus->setText(
          tr("OK: /etc/apt/sources.list switched to profile '%1' and the package list was updated.").arg(profile));
    } else {
      m_softwareStatus->setText(
          tr("⚠ Switching the root apt repository to '%1' failed (rc=%2). sources.list may not have changed, or apt-get update failed — check your network/mirror.")
              .arg(profile)
              .arg(rc));
    }
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
    if (m_softwareStatus) m_softwareStatus->setText(tr("pkexec not found; skipping installation of additional software."));
    return false;
  }

  if (m_softwareStatus) {
    m_softwareStatus->setText(tr("Installing software. An admin password may be required...\n\nAPT packages: %1\nFlatpak apps: %2")
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
        m_softwareStatus->setText(tr("⚠ Debian Testing was blocked: the package you selected would upgrade an existing Stable package to Testing. The Stable system was left unchanged. Please select fewer packages or turn off Debian Testing."));
      } else if (rc == 41) {
        m_softwareStatus->setText(tr("Couldn't pre-check the Debian Testing change. No packages were installed."));
      } else {
        m_softwareStatus->setText(tr("One or more software packages couldn't be installed. Check your Internet connection and try again in Hyggshi Welcome."));
      }
    }
    return false;
  }
  if (m_softwareStatus) m_softwareStatus->setText(tr("✓ Additional software installed successfully."));
  return true;
}

void MainWindow::finishSetup() {
  if (!m_stack || m_stack->isAnimating()) return;

  const QString desktop = qEnvironmentVariable("XDG_CURRENT_DESKTOP").toLower();
  const bool useCustomTheme =
      m_selectedTheme == "custom" && !m_selectedCustomTheme.isEmpty();

  // BUGFIX ("finishing Welcome reverts Applications to Adwaita instead of
  // Hyggshi-Light"): previously light/auto hardcoded "Adwaita", dark used
  // "Adwaita-dark". Meanwhile the Hyggshi OS ISO (Cinnamon) installs its own
  // GTK themes Hyggshi-Light/Hyggshi-Dark into /usr/share/themes, and the
  // build's default dconf (scripts/desktop.sh, theme-light-enabled/
  // theme-dark-enabled in config.ini) ALREADY sets that theme as the
  // default — so every time Finish Welcome ran with the default selection,
  // it overwrote the user's Hyggshi theme back to the DE's default theme.
  // Solution: prefer the Hyggshi theme if it exists on the system, falling
  // back to generic Adwaita (fallback for DE build variants that don't ship
  // a Hyggshi theme, e.g. XFCE).
  auto resolveBuiltinTheme = [this](bool dark) {
    const QString preferred = dark ? QStringLiteral("Hyggshi-Dark")
                                   : QStringLiteral("Hyggshi-Light");
    for (const QString &t : listInstalledThemes()) {
      if (t.compare(preferred, Qt::CaseInsensitive) == 0) return preferred;
    }
    return dark ? QStringLiteral("Adwaita-dark") : QStringLiteral("Adwaita");
  };
  const QString themeName =
      useCustomTheme ? m_selectedCustomTheme
                     : resolveBuiltinTheme(m_selectedTheme == "dark");

  // "auto" = follow the desktop's CURRENT theme, exactly as promised in the
  // note on the Appearance page — writes NO theme/color-scheme key at all.
  // Previously the guard m_selectedTheme != "auto" only blocked the XFCE
  // branch, while on Cinnamon/GNOME/MATE auto mode (the default choice!)
  // still wrote Adwaita as usual.
  // Light/dark-by-time-of-day in auto mode is handled by theme.conf
  // (MODE=auto) + the Hyggshi theme daemon.
  if (m_selectedTheme != "auto") {
    if (desktop.contains("xfce")) {
      if (hasExecutable("xfconf-query")) QProcess::execute("xfconf-query", {"-c", "xsettings", "-p", "/Net/ThemeName", "-s", themeName});
    } else if (hasExecutable("gsettings")) {
      // Cinnamon 6.4's Appearance page follows the GNOME color-scheme key.
      // Setting only gtk-theme made the Dark/Light buttons look selectable but
      // did not reliably change the actual application color scheme. Set both
      // the Cinnamon GTK theme and the shared color-scheme key.
      // For a "custom" theme it's unclear whether it's light or dark, so
      // guess based on the theme name (contains "dark") instead of always
      // forcing "default".
      const QString colorScheme = m_selectedTheme == "dark" ? "prefer-dark"
                                  : m_selectedTheme == "light" ? "prefer-light"
                                  : (themeName.contains("dark", Qt::CaseInsensitive)
                                         ? "prefer-dark"
                                         : "prefer-light");
      if (desktop.contains("cinnamon")) {
        setGsettings("org.cinnamon.desktop.interface", "gtk-theme", themeName);
        // The build's dconf (01-hyggshi-theme in scripts/desktop.sh) sets a
        // SET OF THREE keys: interface/gtk-theme + wm/preferences/theme +
        // cinnamon/theme name. Welcome must change all three together — if
        // only gtk-theme is changed, the titlebar (wm) and Desktop row
        // (cinnamon theme) keep their old values, and the system looks
        // half-changed (Hyggshi-Dark apps but the Desktop still
        // Hyggshi-Light).
        setGsettings("org.cinnamon.desktop.wm.preferences", "theme", themeName);
        setGsettings("org.cinnamon.theme", "name", themeName);
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
  }

  // No more applyLanguageAndKeyboard(): language/keyboard belong to the
  // system (Calamares sets locale+keyboard at install time, the desktop's
  // Settings changes them afterwards) — see the note on the WizardPage enum.
  applyAccessibility();
  savePreferences();
  applyProfileChanges();
  installSelectedSoftware();
  savePreferences();

  const QString themeCfg = configDirectory() + "/theme.conf";
  QFile userThemeConf(themeCfg);
  if (userThemeConf.open(QIODevice::WriteOnly | QIODevice::Text | QIODevice::Truncate)) {
    userThemeConf.write("# Generated by hyggshi-welcome\n");
    userThemeConf.write("MODE=" + m_selectedTheme.toUtf8() + "\n");
    if (useCustomTheme) {
      userThemeConf.write("CUSTOM_NAME=" + m_selectedCustomTheme.toUtf8() + "\n");
    }
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
