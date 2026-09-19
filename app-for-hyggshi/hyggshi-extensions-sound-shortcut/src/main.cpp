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
    bool isPreview = false;
    for (int i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "--preview") == 0) {
            isPreview = true;
            break;
        }
    }

    // Single-instance guard (chỉ áp dụng khi chạy daemon thật)
    if (!isPreview && !acquireLock()) {
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

    // Khởi tạo các thành phần daemon
    AudioController audio;
    KeyGrabber      grabber;
    OsdWindow       osd;

    if (!grabber.isActive()) {
        qWarning() << "[HyggshiSound] CẢNH BÁO: KeyGrabber không hoạt động."
                   << "Phím tắt âm thanh sẽ không phản hồi.";
        // Vẫn chạy để không crash — OSD vẫn có thể test thủ công
    }

    // Kết nối tín hiệu phím → hành động âm lượng → hiện OSD
    QObject::connect(&grabber, &KeyGrabber::volumeUp, [&]() {
        audio.volumeUp();
        const int vol = audio.currentVolume();
        const bool muted = audio.isMuted();
        qDebug() << "[HyggshiSound] Volume Up →" << vol << "%" << (muted ? "[MUTED]" : "");
        osd.showVolume(qMax(0, vol), muted);
    });

    QObject::connect(&grabber, &KeyGrabber::volumeDown, [&]() {
        audio.volumeDown();
        const int vol = audio.currentVolume();
        const bool muted = audio.isMuted();
        qDebug() << "[HyggshiSound] Volume Down →" << vol << "%" << (muted ? "[MUTED]" : "");
        osd.showVolume(qMax(0, vol), muted);
    });

    QObject::connect(&grabber, &KeyGrabber::muteToggle, [&]() {
        audio.toggleMute();
        const bool muted = audio.isMuted();
        const int vol = audio.currentVolume();
        qDebug() << "[HyggshiSound] Mute Toggle → muted=" << muted;
        osd.showVolume(qMax(0, vol), muted);
    });

    qDebug() << "[HyggshiSound] Daemon đang chạy."
             << "Backend:" << audio.backendName()
             << "| X11 grab:" << (grabber.isActive() ? "OK" : "FAIL");

    return app.exec();
}
