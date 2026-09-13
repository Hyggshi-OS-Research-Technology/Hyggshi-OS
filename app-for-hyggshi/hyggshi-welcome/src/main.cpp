#include <QApplication>
#include <QDir>
#include <QFile>
#include <QIcon>
#include <QLocale>
#include <QStandardPaths>
#include <QTranslator>

#include "MainWindow.h"

static QString markerPath() {
  const QString dir = QStandardPaths::writableLocation(
      QStandardPaths::GenericConfigLocation) + "/hyggshi";
  return dir + "/welcome-shown";
}

// UI language follows the SYSTEM locale — the wizard is not the place that
// decides language (that is the installer's locale module / the desktop's
// Region & Language settings). Vietnamese is the source language, so:
//   * vi system  -> no translator needed, strings shown as authored;
//   * anything else -> load the English catalog compiled at build time
//     (translations/hyggshi-welcome_en.ts -> hyggshi-welcome_en.qm,
//     installed under share/hyggshi/welcome/i18n). If the .qm was not
//     built (LinguistTools missing on an old base image) the app keeps
//     Vietnamese rather than breaking the ISO build.
// Override for testing/screenshots: HYGGSHI_WELCOME_LANG=vi|en.
static void installSystemTranslator(QApplication &app) {
  QString lang = qEnvironmentVariable("HYGGSHI_WELCOME_LANG");
  if (lang.isEmpty()) lang = QLocale::system().name().left(2);
  if (lang.compare("vi", Qt::CaseInsensitive) == 0) return;

  auto *translator = new QTranslator(&app);
  const QString base = QStringLiteral("hyggshi-welcome_en");
  const QStringList dirs = {
      QCoreApplication::applicationDirPath() + "/../share/hyggshi/welcome/i18n",
      QStringLiteral("/usr/share/hyggshi/welcome/i18n"),
      QStringLiteral("/usr/local/share/hyggshi/welcome/i18n"),
  };
  for (const QString &dir : dirs) {
    if (translator->load(base, dir)) {
      app.installTranslator(translator);
      return;
    }
  }
  delete translator;
}

int main(int argc, char *argv[]) {
  QApplication app(argc, argv);
  QApplication::setApplicationName("Hyggshi Welcome");
  QApplication::setApplicationVersion("1.4.0");
  QApplication::setOrganizationName("Hyggshi OS Foundation");
  QApplication::setDesktopSettingsAware(true);
  installSystemTranslator(app);
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
