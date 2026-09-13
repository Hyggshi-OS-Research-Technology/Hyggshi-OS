#include <QApplication>
#include <QDir>
#include <QFile>
#include <QIcon>
#include <QStandardPaths>
#include <QTranslator>

#include "MainWindow.h"

static QString markerPath() {
  const QString dir = QStandardPaths::writableLocation(
      QStandardPaths::GenericConfigLocation) + "/hyggshi";
  return dir + "/welcome-shown";
}

// GUI-text language for the app: the tr() sources in MainWindow.cpp are
// now English, so Welcome shows English on every system locale by
// default — no translator needs to be installed for that.
// A Vietnamese translation (translations/hyggshi-welcome_vi.ts compiled to
// .qm at build time, installed under share/hyggshi/welcome/i18n) can be
// opted into explicitly with:
//   HYGGSHI_WELCOME_LANG=vi
// System settings (Calamares locale module, desktop Region & Language)
// remain the single source of truth for the SYSTEM language; the wizard
// no longer overrides its own GUI language from that.
static void installPreferredTranslator(QApplication &app) {
  const QString lang = qEnvironmentVariable("HYGGSHI_WELCOME_LANG");
  // English (default) needs no translator; only an explicit "vi" opts into
  // the Vietnamese translation catalog.
  if (lang.compare("vi", Qt::CaseInsensitive) != 0) return;

  auto *translator = new QTranslator(&app);
  const QString base = QStringLiteral("hyggshi-welcome_vi");
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
  // .qm absent (no Vietnamese translation catalog was built) -> English,
  // which is the source language anyway.
  delete translator;
}

int main(int argc, char *argv[]) {
  QApplication app(argc, argv);
  QApplication::setApplicationName("Hyggshi Welcome");
  QApplication::setApplicationVersion("1.4.1");
  QApplication::setOrganizationName("Hyggshi OS Foundation");
  QApplication::setDesktopSettingsAware(true);
  installPreferredTranslator(app);
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
