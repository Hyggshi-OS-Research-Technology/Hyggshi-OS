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
#include <QTimer>
#include <QVector>

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
  QComboBox *m_languageBox = nullptr;
  QComboBox *m_keyboardBox = nullptr;
  QCheckBox *m_dontAskAgainChk = nullptr;
  QCheckBox *m_reducedMotionChk = nullptr;
  QCheckBox *m_highContrastChk = nullptr;
  QCheckBox *m_largeTextChk = nullptr;
  QComboBox *m_installProfileBox = nullptr;

  // Trang Profile (hồ sơ người dùng): tên hiển thị + ảnh đại diện.
  // Tên đăng nhập chỉ để hiển thị — đổi username hệ thống nằm ngoài phạm
  // vi của Welcome. Avatar custom là 1 file ảnh người dùng chọn; khi chưa
  // chọn ảnh, hiển thị "chữ cái đầu" trên nền màu (giống initial avatar
  // của GNOME).
  QLineEdit *m_profileNameEdit = nullptr;
  QLabel *m_profileAvatarPreview = nullptr;
  QLabel *m_profileLoginLabel = nullptr;
  QPushButton *m_profileAvatarBtn = nullptr;
  QPushButton *m_profileAvatarResetBtn = nullptr;

  QCheckBox *m_debianTestingCheck = nullptr;
  // Chọn profile kho apt gốc của hệ thống (khớp [package-debian-test.*]
  // trong iso-config/config/config.ini: full/normal/default/unstable).
  // KHÁC với m_debianTestingCheck ở trên: cái đó chỉ pin riêng các gói
  // phần mềm THÊM được chọn ở trang Software sang Testing; cái này ghi
  // đè toàn bộ /etc/apt/sources.list của hệ thống.
  QComboBox *m_debianTestProfileBox = nullptr;
  QVector<QCheckBox *> m_softwareChecks;
  QLabel *m_softwareStatus = nullptr;
  QLabel *m_networkStatus = nullptr;
  QLabel *m_updateStatus = nullptr;
  QLabel *m_systemStatus = nullptr;
  QPushButton *m_updateCheckBtn = nullptr;

  QString m_selectedLanguage = "vi";
  QString m_selectedKeyboard = "vn-telex";
  QString m_selectedTheme = "auto";
  // Tên GTK theme tuỳ chỉnh khi m_selectedTheme == "custom" (ví dụ theme
  // do người dùng tự cài vào ~/.themes hoặc /usr/share/themes).
  QString m_selectedCustomTheme;
  QString m_selectedWallpaper;
  bool m_reducedMotion = false;
  bool m_highContrast = false;
  bool m_largeText = false;
  QString m_installProfile = "normal";
  bool m_debianTesting = false;
  // Hồ sơ người dùng: tên hiển thị (GECOS/AccountsService) + đường dẫn ảnh
  // avatar do người dùng chọn (rỗng = avatar chữ cái đầu).
  QString m_profileFullName;
  QString m_profileAvatarPath;
  // "off" = giữ nguyên sources.list mặc định của ảnh cài sẵn (hành vi cũ,
  // không đổi gì). Giá trị khác: "full" | "normal" | "default" | "unstable".
  QString m_debianTestProfile = "off";
  QStringList m_selectedSoftware;

  QTimer *m_carouselTimer = nullptr;
  QVector<FeatureSlide> m_features;
  int m_featureIndex = 0;
  QLabel *m_featureIcon = nullptr;
  QLabel *m_featureTitle = nullptr;
  QLabel *m_featureDesc = nullptr;
  QVector<QLabel *> m_featureDots;

  QWidget *buildWelcomePage();
  QWidget *buildProfilePage();
  QWidget *buildLanguagePage();
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
  void applyLanguageAndKeyboard();
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
  void showFeatureSlide(int index);
  void advanceCarousel();
  void saveFirstRunState(bool completed);
};
