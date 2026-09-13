#pragma once

#include <QButtonGroup>
#include <QCheckBox>
#include <QComboBox>
#include <QLabel>
#include <QLineEdit>
#include <QMainWindow>
#include <QPixmap>
#include <QPushButton>
#include <QSet>
#include <QVector>

#include "SlideStackedWidget.h"

class MainWindow : public QMainWindow {
  Q_OBJECT

 public:
  explicit MainWindow(QWidget *parent = nullptr);

 private:
  struct ThemeOpt {
    QString id;
    QString label;
    QString wallpaper;
  };

  SlideStackedWidget *m_stack = nullptr;
  QVector<QLabel *> m_dots;
  QPushButton *m_backBtn = nullptr;
  QPushButton *m_skipBtn = nullptr;
  QPushButton *m_nextBtn = nullptr;

  QButtonGroup *m_themeGroup = nullptr;
  QComboBox *m_customThemeBox = nullptr;
  QLabel *m_customThemeLabel = nullptr;
  QCheckBox *m_dontAskAgainChk = nullptr;
  QCheckBox *m_reducedMotionChk = nullptr;
  QCheckBox *m_highContrastChk = nullptr;
  QCheckBox *m_largeTextChk = nullptr;
  QComboBox *m_installProfileBox = nullptr;

  // Profile page (user profile): display name + avatar picture. The login
  // name is shown for reference only — changing the system username is
  // outside Welcome's scope. The custom avatar is a single image file the
  // user picks; when no image is picked, an "initial letter" avatar on a
  // colored background is shown instead (similar to GNOME's initial avatar).
  QLineEdit *m_profileNameEdit = nullptr;
  QLabel *m_profileAvatarPreview = nullptr;
  QLabel *m_profileLoginLabel = nullptr;
  QPushButton *m_profileAvatarBtn = nullptr;
  QPushButton *m_profileAvatarResetBtn = nullptr;

  QCheckBox *m_debianTestingCheck = nullptr;
  // Selects the system's root apt-repository profile (matches
  // [package-debian-test.*] in iso-config/config/config.ini:
  // full/normal/default/unstable). DIFFERENT from m_debianTestingCheck
  // above: that one only pins the extra software packages chosen on the
  // Software page to Testing; this one overwrites the whole system's
  // /etc/apt/sources.list.
  QComboBox *m_debianTestProfileBox = nullptr;
  QVector<QCheckBox *> m_softwareChecks;
  QLabel *m_softwareStatus = nullptr;
  QLabel *m_networkStatus = nullptr;
  QLabel *m_updateStatus = nullptr;
  QLabel *m_systemStatus = nullptr;
  QPushButton *m_updateCheckBtn = nullptr;

  // The "Language & Keyboard" page was removed: language/keyboard now
  // follow the system flow (Calamares locale/keyboard at install time, the
  // desktop's Region & Language afterwards) — Welcome no longer keeps
  // state for this or overwrites input sources.
  QString m_selectedTheme = "auto";
  // Custom GTK theme name when m_selectedTheme == "custom" (e.g. a theme
  // the user installed themselves into ~/.themes or /usr/share/themes).
  QString m_selectedCustomTheme;
  QString m_selectedWallpaper;
  bool m_reducedMotion = false;
  bool m_highContrast = false;
  bool m_largeText = false;
  QString m_installProfile = "normal";
  bool m_debianTesting = false;
  // User profile: display name (GECOS/AccountsService) + path to the
  // avatar image the user picked (empty = initial-letter avatar).
  QString m_profileFullName;
  QString m_profileAvatarPath;
  // "off" = keep the pre-installed image's default sources.list unchanged
  // (old behavior, no change). Other values: "full" | "normal" | "default" | "unstable".
  QString m_debianTestProfile = "off";
  QStringList m_selectedSoftware;

  QWidget *buildWelcomePage();
  QWidget *buildProfilePage();
  QWidget *buildNetworkPage();
  QWidget *buildThemePage();
  QWidget *buildSoftwarePage();
  QWidget *buildAccessibilityPage();
  QWidget *buildSystemCheckPage();
  QWidget *buildUpdatePage();
  QWidget *buildFeaturesPage();
  QWidget *buildFinishPage();
  QWidget *buildNavBar();

  void loadPreferences();
  void savePreferences() const;
  void applyAccessibility();
  void applyProfileChanges();
  void pickProfileAvatar();
  void updateProfileAvatarPreview();
  QPixmap renderProfileAvatarPixmap(int size) const;
  static QString loginUserName();
  static QString loginGecos();
  bool installSelectedSoftware();
  void applyDebianTestProfile(const QString &profile);
  void refreshNetworkStatus();
  void refreshSystemStatus();
  void checkForUpdates();
  void setUpdateStatus(const QString &text);

  void updateNavState();
  void updateDots(int index);
  void goNext();
  void goBack();
  void finishSetup();
  void applyWallpaper(const QString &wallpaperPath);
  QString resolveAutoWallpaper() const;
  QStringList listInstalledThemes() const;
  void updateCustomThemeVisibility();
  void saveFirstRunState(bool completed);
};
