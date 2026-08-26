#include <QApplication>
#include <QDir>
#include <QFile>
#include <QIcon>
#include <QStandardPaths>

#include "MainWindow.h"

static QString markerPath() {
  const QString dir = QStandardPaths::writableLocation(
      QStandardPaths::GenericConfigLocation) + "/hyggshi";
  return dir + "/welcome-shown";
}

int main(int argc, char *argv[]) {
  QApplication app(argc, argv);
  QApplication::setApplicationName("Hyggshi Welcome");
  QApplication::setApplicationVersion("1.2.0");
  QApplication::setOrganizationName("Hyggshi OS Foundation");
  QApplication::setDesktopSettingsAware(true);
  // Keep the Hyggshi icon on the running window/taskbar even when the
  // installed icon theme or desktop database is refreshed after Calamares.
  app.setWindowIcon(QIcon(":/icons/logo.png"));

  const QString marker = markerPath();
  const bool force = qEnvironmentVariable("HYGGSHI_WELCOME_FORCE") == "1";
  if (QFile::exists(marker) && !force) {
    return 0;
  }

  app.setStyleSheet(
      "QMainWindow, QWidget { background:#141519; color:#e6e7ea;"
      " font-family:'Noto Sans','Ubuntu','Cantarell',sans-serif; }"
      "QPushButton { background:#22242b; color:#e6e7ea; border:none;"
      " border-radius:6px; padding:7px 14px; }"
      "QPushButton:hover { background:#2b2e36; }"
      "QPushButton:disabled { color:#5c606a; background:#1b1d23; }"
      "QComboBox { background:#1e2027; color:#e6e7ea; border:1px solid #2c2f38;"
      " border-radius:6px; padding:6px 8px; min-height:18px; }"
      "QComboBox QAbstractItemView { background:#1e2027; color:#e6e7ea;"
      " selection-background-color:#2c5f91; }"
      "QToolButton { color:#d8dbe1; padding:5px; }"
      "QToolButton:hover { background:#252832; border-radius:5px; }");

  MainWindow window;
  window.show();
  return app.exec();
}
