#pragma once
#include <QObject>
#include <QString>
#include <QStringList>
#include <QTimer>

// ---------------------------------------------------------------------------
// AudioController — điều khiển âm lượng hệ thống với độ phản hồi cực cao (0ms UI latency).
//
// Cơ chế tối ưu độ nhạy:
//   1. Optimistic State Update: Cập nhật ngay bộ nhớ đệm và phát tín hiệu cho UI
//      trong 0ms, không đợi tiến trình backend chạy xong.
//   2. Direct Execution: Chạy trực tiếp binary (wpctl, pactl, amixer) không qua /bin/sh.
//   3. Single-pass Parsing: Truy vấn cả volume và mute trong 1 lần đọc duy nhất.
//   4. Debounced Hardware Sync: Đồng bộ ngầm với phần cứng để tránh lệch trạng thái.
// ---------------------------------------------------------------------------

class AudioController : public QObject {
    Q_OBJECT

public:
    enum class Backend {
        PipeWire,
        PulseAudio,
        Alsa,
        Unknown
    };

    explicit AudioController(QObject *parent = nullptr);

    // Thay đổi âm lượng
    void volumeUp(int stepPercent = 5);
    void volumeDown(int stepPercent = 5);
    void toggleMute();

    // Getter trạng thái hiện tại
    int currentVolume() const { return m_volume; }
    bool isMuted() const { return m_muted; }

    Backend backend() const { return m_backend; }
    QString backendName() const;

signals:
    void stateChanged(int volume, bool muted);

public slots:
    // Đồng bộ lại với phần cứng (chạy ngầm)
    void syncHardwareState();

private:
    Backend m_backend{Backend::Unknown};
    int     m_volume{50};
    bool    m_muted{false};
    QTimer *m_syncTimer{nullptr};

    Backend detectBackend();
    void runDirect(const QString &program, const QStringList &arguments);
    QString queryDirect(const QString &program, const QStringList &arguments) const;

    void applyBackendVolume(int targetVolume);
    void applyBackendMute(bool targetMute);
    void readHardwareVolumeAndMute(int &vol, bool &mute) const;
};
