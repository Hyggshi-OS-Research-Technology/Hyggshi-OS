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
