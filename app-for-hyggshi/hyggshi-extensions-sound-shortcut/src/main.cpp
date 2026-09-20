// main.cpp — hyggshi-extensions-sound-shortcut
//
// Daemon C++ chạy nền cho XFCE:
//   - Bắt phím XF86Audio* toàn cục qua XGrabKey
//   - Điều khiển âm lượng qua PipeWire/PulseAudio/ALSA (auto-detect)
//   - Hiện OSD popup Qt khi bấm phím
//
// Single-instance guard: flock trên /tmp/.hyggshi-sound-shortcut.lock —
// lần thứ 2 chạy sẽ thoát ngay, không mở thêm daemon.

#include <QApplication>
#include <QIcon>
#include <QDebug>

#include "AudioController.h"
#include "KeyGrabber.h"
#include "OsdWindow.h"

// Single-instance lock
#include <fcntl.h>
#include <unistd.h>
#include <sys/file.h>

static constexpr const char *kLockPath = "/tmp/.hyggshi-sound-shortcut.lock";

static bool acquireLock()
{
    int fd = open(kLockPath, O_CREAT | O_RDWR, 0600);
    if (fd < 0) return true; // Không tạo được lock → chạy bình thường
    if (flock(fd, LOCK_EX | LOCK_NB) != 0) {
        // Daemon khác đang giữ lock → thoát ngay
        close(fd);
        return false;
    }
    // Giữ fd mở suốt vòng đời process (lock tự nhả khi process kết thúc)
    return true;
}

int main(int argc, char *argv[])
{
    // Kiểm tra chế độ test / preview trước khi acquireLock()
    bool isPreview  = false;
    bool isSimulate = false;
    for (int i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "--preview")  == 0) { isPreview  = true; break; }
        if (strcmp(argv[i], "--simulate") == 0) { isSimulate = true; break; }
    }

    // Single-instance guard (chỉ áp dụng khi chạy daemon thật)
    if (!isPreview && !isSimulate && !acquireLock()) {
        qDebug() << "[HyggshiSound] Daemon đã đang chạy — thoát.";
        return 0;
    }

    // QApplication với gui=true (cần để vẽ OSD) nhưng ẩn khỏi taskbar
    QApplication app(argc, argv);
    QApplication::setApplicationName(QStringLiteral("Hyggshi Sound Shortcut"));
    QApplication::setApplicationVersion(QStringLiteral("1.0.0"));
    QApplication::setOrganizationName(QStringLiteral("Hyggshi OS Foundation"));
    QApplication::setQuitOnLastWindowClosed(false); // không thoát khi OSD đóng

    app.setWindowIcon(QIcon(QStringLiteral(":/icons/volume-high.png")));

    // Dark stylesheet đồng nhất với Hyggshi OS
    app.setStyleSheet(
        "QWidget { background: #141519; color: #e6e7ea; "
        "  font-family: 'Noto Sans','Ubuntu','Cantarell',sans-serif; }"
    );

    // Xử lý chế độ preview độc lập
    if (isPreview) {
        int vol = 65;
        bool muted = false;
        QString outPath;
        for (int i = 1; i < argc; ++i) {
            if (strcmp(argv[i], "--preview") == 0) {
                if (i + 1 < argc && argv[i + 1][0] != '-') {
                    vol = atoi(argv[++i]);
                }
                if (i + 1 < argc && argv[i + 1][0] != '-') {
                    QString nextArg = QString::fromUtf8(argv[++i]);
                    if (nextArg == QStringLiteral("muted") || nextArg == QStringLiteral("1")) {
                        muted = true;
                    } else if (nextArg != QStringLiteral("normal")) {
                        outPath = nextArg;
                    }
                }
                if (i + 1 < argc && argv[i + 1][0] != '-' && outPath.isEmpty()) {
                    outPath = QString::fromUtf8(argv[++i]);
                }
            }
        }
        auto *osd = new OsdWindow;
        osd->showVolume(vol, muted);

        if (!outPath.isEmpty()) {
            QTimer::singleShot(250, [osd, &app, outPath]() {
                QPixmap pix = osd->grab();
                pix.save(outPath);
                qDebug() << "[HyggshiSound] Saved preview to" << outPath;
                app.quit();
            });
        } else {
            // Tự thoát sau 3 giây khi preview xong trên màn hình
            QTimer::singleShot(3000, &app, &QApplication::quit);
        }
        return app.exec();
    }

    // -----------------------------------------------------------------------
    // Chế độ --simulate: mô phỏng tăng/giảm âm lượng và mute để xem OSD
    // -----------------------------------------------------------------------
    if (isSimulate) {
        auto *osd = new OsdWindow;

        // Kịch bản mô phỏng: (volume, muted, delay_ms_from_start)
        struct Step { int vol; bool muted; int delay; };
        const QList<Step> steps = {
            // Đang ở 30% → tăng từng bước
            {30, false,    0},
            {40, false,  700},
            {50, false, 1400},
            {65, false, 2100},
            {80, false, 2800},
            {95, false, 3500},
            // Giữ ở 95% → bấm mute
            {95, true,  4800},
            // Unmute, quay về 60%
            {60, false, 6200},
            // Giảm âm lượng
            {45, false, 6900},
            {25, false, 7600},
            {10, false, 8300},
        };

        for (const auto &s : steps) {
            QTimer::singleShot(s.delay, osd, [osd, s]() {
                osd->showVolume(s.vol, s.muted);
            });
        }

        // Tự thoát sau khi chuỗi hoàn tất + 2.5s buffer để OSD fade out
        QTimer::singleShot(11000, &app, &QApplication::quit);
        qDebug() << "[HyggshiSound] Simulate mode — sẽ tự thoát sau 11 giây.";
        return app.exec();
    }

    // Khởi tạo các thành phần daemon
    AudioController audio;
    KeyGrabber      grabber;
    OsdWindow       osd;

    if (!grabber.isActive()) {
        qWarning() << "[HyggshiSound] CẢNH BÁO: KeyGrabber không hoạt động."
                   << "Phím tắt âm thanh sẽ không phản hồi.";
        // Vẫn chạy để không crash — OSD vẫn có thể test thủ công
    }

    // Kết nối phản hồi tức thì (0ms latency): AudioController phát stateChanged -> OSD hiện ngay
    QObject::connect(&audio, &AudioController::stateChanged,
                     &osd, &OsdWindow::showVolume);

    QObject::connect(&grabber, &KeyGrabber::volumeUp, [&audio]() {
        audio.volumeUp(5);
    });

    QObject::connect(&grabber, &KeyGrabber::volumeDown, [&audio]() {
        audio.volumeDown(5);
    });

    QObject::connect(&grabber, &KeyGrabber::muteToggle, [&audio]() {
        audio.toggleMute();
    });

    QObject::connect(&grabber, &KeyGrabber::micMuteToggle, [&audio]() {
        audio.toggleMute();
    });

    qDebug() << "[HyggshiSound] Daemon đang chạy."
             << "Backend:" << audio.backendName()
             << "| X11 grab:" << (grabber.isActive() ? "OK" : "FAIL");

    return app.exec();
}
