#include "AudioController.h"

#include <QDebug>
#include <QProcess>
#include <QRegularExpression>

// ---------------------------------------------------------------------------
AudioController::AudioController()
    : m_backend(detectBackend())
{
    qDebug() << "[HyggshiSound] AudioController: backend =" << backendName();
}

// ---------------------------------------------------------------------------
AudioController::Backend AudioController::detectBackend() const
{
    // 1. PipeWire: wpctl phải có VÀ trả về thông tin sink hợp lệ
    if (!queryCmd("wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null").isEmpty())
        return Backend::PipeWire;

    // 2. PulseAudio: pactl phải có và daemon đang chạy
    if (!queryCmd("pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null").isEmpty())
        return Backend::PulseAudio;

    // 3. ALSA fallback
    if (!queryCmd("amixer get Master 2>/dev/null").isEmpty())
        return Backend::Alsa;

    return Backend::Unknown;
}

QString AudioController::backendName() const
{
    switch (m_backend) {
    case Backend::PipeWire:   return QStringLiteral("PipeWire (wpctl)");
    case Backend::PulseAudio: return QStringLiteral("PulseAudio (pactl)");
    case Backend::Alsa:       return QStringLiteral("ALSA (amixer)");
    default:                  return QStringLiteral("Unknown");
    }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------
void AudioController::volumeUp(int step)
{
    switch (m_backend) {
    case Backend::PipeWire:   pwVolumeUp(step); break;
    case Backend::PulseAudio: paVolumeUp(step); break;
    case Backend::Alsa:       alsaVolumeUp(step); break;
    default: break;
    }
}

void AudioController::volumeDown(int step)
{
    switch (m_backend) {
    case Backend::PipeWire:   pwVolumeDown(step); break;
    case Backend::PulseAudio: paVolumeDown(step); break;
    case Backend::Alsa:       alsaVolumeDown(step); break;
    default: break;
    }
}

void AudioController::toggleMute()
{
    switch (m_backend) {
    case Backend::PipeWire:   pwToggleMute(); break;
    case Backend::PulseAudio: paToggleMute(); break;
    case Backend::Alsa:       alsaToggleMute(); break;
    default: break;
    }
}

int AudioController::currentVolume() const
{
    switch (m_backend) {
    case Backend::PipeWire:   return pwVolume();
    case Backend::PulseAudio: return paVolume();
    case Backend::Alsa:       return alsaVolume();
    default:                  return -1;
    }
}

bool AudioController::isMuted() const
{
    switch (m_backend) {
    case Backend::PipeWire:   return pwMuted();
    case Backend::PulseAudio: return paMuted();
    case Backend::Alsa:       return alsaMuted();
    default:                  return false;
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
void AudioController::runCmd(const QString &cmd) const
{
    QProcess::startDetached(QStringLiteral("/bin/sh"),
                            {QStringLiteral("-c"), cmd});
}

QString AudioController::queryCmd(const QString &cmd) const
{
    QProcess p;
    p.start(QStringLiteral("/bin/sh"), {QStringLiteral("-c"), cmd});
    if (!p.waitForFinished(2000)) return {};
    return QString::fromUtf8(p.readAllStandardOutput()).trimmed();
}

// ---------------------------------------------------------------------------
// PipeWire (wpctl)
// ---------------------------------------------------------------------------
void AudioController::pwVolumeUp(int step) const
{
    runCmd(QStringLiteral("wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ %1%+").arg(step));
}
void AudioController::pwVolumeDown(int step) const
{
    runCmd(QStringLiteral("wpctl set-volume @DEFAULT_AUDIO_SINK@ %1%-").arg(step));
}
void AudioController::pwToggleMute() const
{
    runCmd(QStringLiteral("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"));
}
int AudioController::pwVolume() const
{
    // wpctl get-volume @DEFAULT_AUDIO_SINK@ → "Volume: 0.65 [MUTED]" hoặc "Volume: 0.65"
    const QString out = queryCmd(QStringLiteral("wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null"));
    if (out.isEmpty()) return -1;
    static const QRegularExpression re(QStringLiteral(R"(Volume:\s*([\d.]+))"));
    const auto m = re.match(out);
    if (!m.hasMatch()) return -1;
    return qRound(m.captured(1).toDouble() * 100.0);
}
bool AudioController::pwMuted() const
{
    const QString out = queryCmd(QStringLiteral("wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null"));
    return out.contains(QStringLiteral("MUTED"), Qt::CaseInsensitive);
}

// ---------------------------------------------------------------------------
// PulseAudio (pactl)
// ---------------------------------------------------------------------------
void AudioController::paVolumeUp(int step) const
{
    runCmd(QStringLiteral("pactl set-sink-volume @DEFAULT_SINK@ +%1%").arg(step));
}
void AudioController::paVolumeDown(int step) const
{
    runCmd(QStringLiteral("pactl set-sink-volume @DEFAULT_SINK@ -%1%").arg(step));
}
void AudioController::paToggleMute() const
{
    runCmd(QStringLiteral("pactl set-sink-mute @DEFAULT_SINK@ toggle"));
}
int AudioController::paVolume() const
{
    // pactl get-sink-volume → "Volume: front-left: 42597 /  65% / -11.46 dB, ..."
    const QString out = queryCmd(QStringLiteral("pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null"));
    if (out.isEmpty()) return -1;
    static const QRegularExpression re(QStringLiteral(R"(/\s*(\d+)%\s*/)"));
    const auto m = re.match(out);
    if (!m.hasMatch()) return -1;
    return m.captured(1).toInt();
}
bool AudioController::paMuted() const
{
    const QString out = queryCmd(QStringLiteral("pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null"));
    return out.contains(QStringLiteral("yes"), Qt::CaseInsensitive);
}

// ---------------------------------------------------------------------------
// ALSA (amixer)
// ---------------------------------------------------------------------------
void AudioController::alsaVolumeUp(int step) const
{
    runCmd(QStringLiteral("amixer -q set Master %1%%+").arg(step));
}
void AudioController::alsaVolumeDown(int step) const
{
    runCmd(QStringLiteral("amixer -q set Master %1%%-").arg(step));
}
void AudioController::alsaToggleMute() const
{
    runCmd(QStringLiteral("amixer -q set Master toggle"));
}
int AudioController::alsaVolume() const
{
    // amixer get Master → "  Playback 65536 [100%] [on]"
    const QString out = queryCmd(QStringLiteral("amixer get Master 2>/dev/null"));
    if (out.isEmpty()) return -1;
    static const QRegularExpression re(QStringLiteral(R"(\[(\d+)%\])"));
    const auto m = re.match(out);
    if (!m.hasMatch()) return -1;
    return m.captured(1).toInt();
}
bool AudioController::alsaMuted() const
{
    const QString out = queryCmd(QStringLiteral("amixer get Master 2>/dev/null"));
    return out.contains(QStringLiteral("[off]"), Qt::CaseInsensitive);
}
