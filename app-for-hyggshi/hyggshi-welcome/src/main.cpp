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

// GUI-text language priority for the app itself: Vietnamese > English
// (product decision — Hyggshi OS is a Vietnamese distribution). All tr()
// sources ARE Vietnamese, so the first-priority language is always
// available and the app renders Vietnamese on EVERY system locale,
// including English ones — the wizard must not look foreign to its
// primary audience just because LANG=*.
// The second language in the chain (English, translations/hyggshi-
// welcome_en.ts compiled to .qm at build time, installed under
// share/hyggshi/welcome/i18n) is used only when explicitly requested:
//   HYGGSHI_WELCOME_LANG=en
// System settings (Calamares locale module, desktop Region & Language)
// remain the single source of truth for the SYSTEM language; the wizard
// simply no longer overrides its own GUI language from that.
static void installPreferredTranslator(QApplication &app) {
  const QString lang = qEnvironmentVariable("HYGGSHI_WELCOME_LANG");
  // vi (default) needs no translator; only an explicit "en" opts into the
  // second language of the Vi > en chain.
  if (lang.compare("en", Qt::CaseInsensitive) != 0) return;

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
  // .qm absent (LinguistTools was missing at build time) -> Vietnamese,
  // which is the head of the priority chain anyway.
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
