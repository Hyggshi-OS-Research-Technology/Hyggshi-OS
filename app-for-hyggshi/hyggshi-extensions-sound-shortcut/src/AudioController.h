#pragma once
#include <QString>

// ---------------------------------------------------------------------------
// AudioController — điều khiển âm lượng hệ thống với auto-detect backend.
//
// Thứ tự ưu tiên:
//   1. PipeWire  — dùng `wpctl`
//   2. PulseAudio — dùng `pactl`
//   3. ALSA      — dùng `amixer`
//
// Backend được phát hiện một lần lúc khởi tạo và giữ nguyên suốt vòng đời
// của đối tượng.
// ---------------------------------------------------------------------------

class AudioController {
public:
    enum class Backend {
        PipeWire,
        PulseAudio,
        Alsa,
        Unknown
    };

    AudioController();

    // Tăng âm lượng lên stepPercent% (mặc định 5)
    void volumeUp(int stepPercent = 5);

    // Giảm âm lượng xuống stepPercent%
    void volumeDown(int stepPercent = 5);

    // Bật/tắt mute (toggle)
    void toggleMute();

    // Trả về âm lượng hiện tại [0..100], -1 nếu không query được
    int currentVolume() const;

    // Trả về trạng thái mute
    bool isMuted() const;

    Backend backend() const { return m_backend; }
    QString backendName() const;

private:
    Backend m_backend{Backend::Unknown};

    Backend detectBackend() const;
    void runCmd(const QString &cmd) const;
    QString queryCmd(const QString &cmd) const;

    // Helpers per-backend
    void pwVolumeUp(int step) const;
    void pwVolumeDown(int step) const;
    void pwToggleMute() const;
    int  pwVolume() const;
    bool pwMuted() const;

    void paVolumeUp(int step) const;
    void paVolumeDown(int step) const;
    void paToggleMute() const;
    int  paVolume() const;
    bool paMuted() const;

    void alsaVolumeUp(int step) const;
    void alsaVolumeDown(int step) const;
    void alsaToggleMute() const;
    int  alsaVolume() const;
    bool alsaMuted() const;
};
