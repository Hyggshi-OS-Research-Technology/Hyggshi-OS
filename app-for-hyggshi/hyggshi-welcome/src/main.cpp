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
