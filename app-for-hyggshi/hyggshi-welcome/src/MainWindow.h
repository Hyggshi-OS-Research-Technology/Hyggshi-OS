#pragma once

#include <QButtonGroup>
#include <QCheckBox>
#include <QComboBox>
#include <QLabel>
#include <QMainWindow>
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
  QComboBox *m_languageBox = nullptr;
  QComboBox *m_keyboardBox = nullptr;
  QCheckBox *m_dontAskAgainChk = nullptr;
  QCheckBox *m_reducedMotionChk = nullptr;
  QCheckBox *m_highContrastChk = nullptr;
  QCheckBox *m_largeTextChk = nullptr;
  QComboBox *m_installProfileBox = nullptr;
  QCheckBox *m_debianTestingCheck = nullptr;
  QVector<QCheckBox *> m_softwareChecks;
  QLabel *m_softwareStatus = nullptr;
  QLabel *m_networkStatus = nullptr;
  QLabel *m_updateStatus = nullptr;
  QLabel *m_systemStatus = nullptr;
  QPushButton *m_updateCheckBtn = nullptr;

  QString m_selectedLanguage = "vi";
  QString m_selectedKeyboard = "vn-telex";
  QString m_selectedTheme = "auto";
  QString m_selectedWallpaper;
  bool m_reducedMotion = false;
  bool m_highContrast = false;
  bool m_largeText = false;
  QString m_installProfile = "normal";
  bool m_debianTesting = false;
  QStringList m_selectedSoftware;

  QTimer *m_carouselTimer = nullptr;
  QVector<FeatureSlide> m_features;
  int m_featureIndex = 0;
  QLabel *m_featureIcon = nullptr;
  QLabel *m_featureTitle = nullptr;
  QLabel *m_featureDesc = nullptr;
  QVector<QLabel *> m_featureDots;

  QWidget *buildWelcomePage();
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
  bool installSelectedSoftware();
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
  void showFeatureSlide(int index);
  void advanceCarousel();
  void saveFirstRunState(bool completed);
};
