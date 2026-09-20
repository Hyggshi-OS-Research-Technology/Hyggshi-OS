#include "AudioController.h"

#include <QDebug>
#include <QProcess>
#include <QRegularExpression>
#include <QtGlobal>

// ---------------------------------------------------------------------------
AudioController::AudioController(QObject *parent)
    : QObject(parent)
    , m_backend(detectBackend())
{
    qDebug() << "[HyggshiSound] AudioController: backend =" << backendName();

    // Khởi tạo trạng thái ban đầu trực tiếp từ phần cứng
    readHardwareVolumeAndMute(m_volume, m_muted);
    qDebug() << "[HyggshiSound] Initial audio state: volume =" << m_volume << "% | muted =" << m_muted;

    // Timer đồng bộ ngầm (chạy sau khi người dùng ngừng nhấn phím 600ms)
    m_syncTimer = new QTimer(this);
    m_syncTimer->setSingleShot(true);
    connect(m_syncTimer, &QTimer::timeout, this, &AudioController::syncHardwareState);
}

// ---------------------------------------------------------------------------
AudioController::Backend AudioController::detectBackend()
{
    // 1. PipeWire: kiểm tra lệnh wpctl
    if (!queryDirect(QStringLiteral("wpctl"),
                     {QStringLiteral("get-volume"), QStringLiteral("@DEFAULT_AUDIO_SINK@")}).isEmpty()) {
        return Backend::PipeWire;
    }

    // 2. PulseAudio: kiểm tra lệnh pactl
    if (!queryDirect(QStringLiteral("pactl"),
                     {QStringLiteral("get-sink-volume"), QStringLiteral("@DEFAULT_SINK@")}).isEmpty()) {
        return Backend::PulseAudio;
    }

    // 3. ALSA fallback: kiểm tra amixer
    if (!queryDirect(QStringLiteral("amixer"),
                     {QStringLiteral("get"), QStringLiteral("Master")}).isEmpty()) {
        return Backend::Alsa;
    }

    return Backend::Unknown;
}

QString AudioController::backendName() const
{
    switch (m_backend) {
    case Backend::PipeWire:   return QStringLiteral("PipeWire (wpctl - Direct)");
    case Backend::PulseAudio: return QStringLiteral("PulseAudio (pactl - Direct)");
    case Backend::Alsa:       return QStringLiteral("ALSA (amixer - Direct)");
    default:                  return QStringLiteral("Unknown");
    }
}

// ---------------------------------------------------------------------------
// Tối ưu hóa thực thi tiến trình: Chạy thẳng binary không qua /bin/sh
// ---------------------------------------------------------------------------
void AudioController::runDirect(const QString &program, const QStringList &arguments)
{
    QProcess::startDetached(program, arguments);
}

QString AudioController::queryDirect(const QString &program, const QStringList &arguments) const
{
    QProcess p;
    p.start(program, arguments);
    if (!p.waitForFinished(150)) return {};
    return QString::fromUtf8(p.readAllStandardOutput()).trimmed();
}

// ---------------------------------------------------------------------------
// Optimistic UI: Phản hồi UI tức thì trong 0ms, dispatch lệnh backend ngầm
// ---------------------------------------------------------------------------
void AudioController::volumeUp(int stepPercent)
{
    m_volume = qBound(0, m_volume + stepPercent, 100);
    const bool wasMuted = m_muted;
    m_muted = false; // Tăng âm lượng thì tự động bật lại âm thanh

    // Phát tín hiệu UI ngay lập tức
    emit stateChanged(m_volume, m_muted);

    // Gửi lệnh backend
    applyBackendVolume(m_volume);
    if (wasMuted) {
        applyBackendMute(false);
    }

    m_syncTimer->start(600);
}

void AudioController::volumeDown(int stepPercent)
{
    m_volume = qBound(0, m_volume - stepPercent, 100);

    // Phát tín hiệu UI ngay lập tức
    emit stateChanged(m_volume, m_muted);

    // Gửi lệnh backend
    applyBackendVolume(m_volume);

    m_syncTimer->start(600);
}

void AudioController::toggleMute()
{
    m_muted = !m_muted;

    // Phát tín hiệu UI ngay lập tức
    emit stateChanged(m_volume, m_muted);

    // Gửi lệnh backend
    applyBackendMute(m_muted);

    m_syncTimer->start(600);
}

// ---------------------------------------------------------------------------
// Backend Dispatchers (chính xác tuyệt đối, tránh race-condition)
// ---------------------------------------------------------------------------
void AudioController::applyBackendVolume(int targetVolume)
{
    switch (m_backend) {
    case Backend::PipeWire: {
        const double frac = qBound(0.0, targetVolume / 100.0, 1.0);
        runDirect(QStringLiteral("wpctl"),
                  {QStringLiteral("set-volume"), QStringLiteral("-l"), QStringLiteral("1.0"),
                   QStringLiteral("@DEFAULT_AUDIO_SINK@"), QString::number(frac, 'f', 2)});
        break;
    }
    case Backend::PulseAudio: {
        runDirect(QStringLiteral("pactl"),
                  {QStringLiteral("set-sink-volume"), QStringLiteral("@DEFAULT_SINK@"),
                   QString::number(targetVolume) + QStringLiteral("%")});
        break;
    }
    case Backend::Alsa: {
        runDirect(QStringLiteral("amixer"),
                  {QStringLiteral("-q"), QStringLiteral("set"), QStringLiteral("Master"),
                   QString::number(targetVolume) + QStringLiteral("%")});
        break;
    }
    default: break;
    }
}

void AudioController::applyBackendMute(bool targetMute)
{
    switch (m_backend) {
    case Backend::PipeWire: {
        runDirect(QStringLiteral("wpctl"),
                  {QStringLiteral("set-mute"), QStringLiteral("@DEFAULT_AUDIO_SINK@"),
                   targetMute ? QStringLiteral("1") : QStringLiteral("0")});
        break;
    }
    case Backend::PulseAudio: {
        runDirect(QStringLiteral("pactl"),
                  {QStringLiteral("set-sink-mute"), QStringLiteral("@DEFAULT_SINK@"),
                   targetMute ? QStringLiteral("1") : QStringLiteral("0")});
        break;
    }
    case Backend::Alsa: {
        runDirect(QStringLiteral("amixer"),
                  {QStringLiteral("-q"), QStringLiteral("set"), QStringLiteral("Master"),
                   targetMute ? QStringLiteral("mute") : QStringLiteral("unmute")});
        break;
    }
    default: break;
    }
}

// ---------------------------------------------------------------------------
// Single-pass Parsing: Đọc cả Volume và Mute trong 1 lệnh duy nhất
// ---------------------------------------------------------------------------
void AudioController::readHardwareVolumeAndMute(int &vol, bool &mute) const
{
    switch (m_backend) {
    case Backend::PipeWire: {
        const QString out = queryDirect(QStringLiteral("wpctl"),
                                        {QStringLiteral("get-volume"), QStringLiteral("@DEFAULT_AUDIO_SINK@")});
        if (out.isEmpty()) return;
        static const QRegularExpression re(QStringLiteral(R"(Volume:\s*([\d.]+))"));
        const auto m = re.match(out);
        if (m.hasMatch()) {
            vol = qBound(0, qRound(m.captured(1).toDouble() * 100.0), 100);
        }
        mute = out.contains(QStringLiteral("MUTED"), Qt::CaseInsensitive);
        break;
    }
    case Backend::PulseAudio: {
        const QString volOut = queryDirect(QStringLiteral("pactl"),
                                           {QStringLiteral("get-sink-volume"), QStringLiteral("@DEFAULT_SINK@")});
        static const QRegularExpression re(QStringLiteral(R"(/\s*(\d+)%\s*/)"));
        const auto m = re.match(volOut);
        if (m.hasMatch()) {
            vol = qBound(0, m.captured(1).toInt(), 100);
        }
        const QString muteOut = queryDirect(QStringLiteral("pactl"),
                                            {QStringLiteral("get-sink-mute"), QStringLiteral("@DEFAULT_SINK@")});
        mute = muteOut.contains(QStringLiteral("yes"), Qt::CaseInsensitive);
        break;
    }
    case Backend::Alsa: {
        const QString out = queryDirect(QStringLiteral("amixer"),
                                        {QStringLiteral("get"), QStringLiteral("Master")});
        static const QRegularExpression re(QStringLiteral(R"(\[(\d+)%\])"));
        const auto m = re.match(out);
        if (m.hasMatch()) {
            vol = qBound(0, m.captured(1).toInt(), 100);
        }
        mute = out.contains(QStringLiteral("[off]"), Qt::CaseInsensitive);
        break;
    }
    default: break;
    }
}

void AudioController::syncHardwareState()
{
    int hwVol = m_volume;
    bool hwMute = m_muted;
    readHardwareVolumeAndMute(hwVol, hwMute);

    if (hwVol != m_volume || hwMute != m_muted) {
        m_volume = hwVol;
        m_muted = hwMute;
        emit stateChanged(m_volume, m_muted);
    }
}
