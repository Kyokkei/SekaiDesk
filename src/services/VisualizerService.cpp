#include "VisualizerService.h"
#include "MediaService.h"
#include "core/SettingsStore.h"

#include <QDateTime>
#include <QtMath>

#include <algorithm>
#include <cmath>
#include <complex>
#include <cstring>
#include <vector>

#ifdef Q_OS_WIN
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <mmdeviceapi.h>
#include <audioclient.h>
#include <mmreg.h>
#include <objbase.h>
#endif

namespace {
constexpr int kFftSize = 1024;
constexpr int kBandCount = 32;

#ifdef Q_OS_WIN
const CLSID kClsidMMDeviceEnumerator = {
    0xBCDE0395, 0xE52F, 0x467C, {0x8E, 0x3D, 0xC4, 0x57, 0x92, 0x91, 0x69, 0x2E}
};
const IID kIidIMMDeviceEnumerator = {
    0xA95664D2, 0x9614, 0x4F35, {0xA7, 0x46, 0xDE, 0x8D, 0xB6, 0x36, 0x17, 0xE6}
};
const IID kIidIAudioClient = {
    0x1CB9AD4C, 0xDBFA, 0x4C32, {0xB1, 0x78, 0xC2, 0xF5, 0x68, 0xA7, 0x03, 0xB2}
};
const IID kIidIAudioCaptureClient = {
    0xC8ADBD64, 0xE71E, 0x48A0, {0xA4, 0xDE, 0x18, 0x5C, 0x39, 0x5C, 0xD3, 0x17}
};

#ifndef AUDCLNT_E_DEVICE_INVALIDATED
#define AUDCLNT_E_DEVICE_INVALIDATED ((HRESULT)0x88890004L)
#endif
#endif

void fftRadix2(std::array<std::complex<float>, kFftSize>& buf)
{
    int j = 0;
    for (int i = 1; i < kFftSize; ++i) {
        int bit = kFftSize >> 1;
        for (; j & bit; bit >>= 1)
            j ^= bit;
        j ^= bit;
        if (i < j)
            std::swap(buf[i], buf[j]);
    }

    constexpr float kTwoPi = 6.2831853071795864769f;
    for (int len = 2; len <= kFftSize; len <<= 1) {
        const float angle = -kTwoPi / static_cast<float>(len);
        const std::complex<float> wlen(std::cos(angle), std::sin(angle));
        const int half = len >> 1;
        for (int i = 0; i < kFftSize; i += len) {
            std::complex<float> w(1.0f, 0.0f);
            for (int k = 0; k < half; ++k) {
                const std::complex<float> u = buf[i + k];
                const std::complex<float> v = buf[i + k + half] * w;
                buf[i + k] = u + v;
                buf[i + k + half] = u - v;
                w *= wlen;
            }
        }
    }
}

QString sanitizeStyle(const QString& raw)
{
    const QString s = raw.trimmed().toLower();
    if (s == QStringLiteral("tide")
        || s == QStringLiteral("ribbons")
        || s == QStringLiteral("aurora")
        || s == QStringLiteral("pulse")
        || s == QStringLiteral("scope")
        || s == QStringLiteral("mirror")
        || s == QStringLiteral("ring")
        || s == QStringLiteral("dots")
        || s == QStringLiteral("sekai")
        || s == QStringLiteral("bars")
        || s == QStringLiteral("wave")) {
        return s;
    }
    return QStringLiteral("tide");
}
} // namespace

VisualizerService::VisualizerService(SettingsStore* settings, MediaService* media, QObject* parent)
    : QObject(parent)
    , m_settings(settings)
    , m_media(media)
{
    m_bands.reserve(kBandCount);
    for (int i = 0; i < kBandCount; ++i)
        m_bands.append(0.0);

    if (m_settings) {
        m_enabled = m_settings->boolValue(QStringLiteral("visualizer.enabled"), false);
        m_style = sanitizeStyle(m_settings->stringValue(QStringLiteral("visualizer.style"), QStringLiteral("tide")));
        m_sizeIndex = qBound(0, m_settings->intValue(QStringLiteral("visualizer.sizeIndex"), 1), 3);
        m_colorMode = qBound(0, m_settings->intValue(QStringLiteral("visualizer.colorMode"), 0), 2);
        const QVariant sensVar = m_settings->get(QStringLiteral("visualizer.sensitivity"), 1.0);
        m_sensitivity = qBound<qreal>(0.5, sensVar.toDouble(), 2.5);
        m_alwaysListen = m_settings->boolValue(QStringLiteral("visualizer.alwaysListen"), true);
        m_stayWhenPaused = m_settings->boolValue(QStringLiteral("visualizer.stayWhenPaused"), true);
        m_posX = m_settings->get(QStringLiteral("visualizer.posX"), -1.0).toDouble();
        m_posY = m_settings->get(QStringLiteral("visualizer.posY"), -1.0).toDouble();
        const int rawW = m_settings->intValue(QStringLiteral("visualizer.customWidth"), 0);
        const int rawH = m_settings->intValue(QStringLiteral("visualizer.customHeight"), 0);
        m_customWidth = (rawW > 0) ? qBound(160, rawW, 3840) : 0;
        m_customHeight = (rawH > 0) ? qBound(80, rawH, 1440) : 0;
        m_transparentBg = m_settings->boolValue(QStringLiteral("visualizer.transparentBg"), true);
    }
    m_atomicSensitivity.store(static_cast<float>(m_sensitivity), std::memory_order_relaxed);

    m_frameTimer.setInterval(24);
    connect(&m_frameTimer, &QTimer::timeout, this, &VisualizerService::onFrameTimer);

    if (m_media) {
        connect(m_media, &MediaService::mediaChanged, this, &VisualizerService::syncCaptureState);
    }
    syncCaptureState();
}

VisualizerService::~VisualizerService()
{
    stopWorker();
}

void VisualizerService::setEnabled(bool enabled)
{
    if (m_enabled == enabled)
        return;
    m_enabled = enabled;
    if (m_settings)
        m_settings->set(QStringLiteral("visualizer.enabled"), m_enabled);
    emit enabledChanged();
    emit configChanged();
    syncCaptureState();
}

void VisualizerService::setStyle(const QString& style)
{
    const QString next = sanitizeStyle(style);
    if (m_style == next)
        return;
    m_style = next;
    if (m_settings)
        m_settings->set(QStringLiteral("visualizer.style"), m_style);
    emit styleChanged();
    emit configChanged();
}

void VisualizerService::setSizeIndex(int index)
{
    const int clamped = qBound(0, index, 3);
    if (m_sizeIndex == clamped)
        return;
    m_sizeIndex = clamped;
    if (m_settings)
        m_settings->set(QStringLiteral("visualizer.sizeIndex"), m_sizeIndex);
    emit sizeIndexChanged();
    emit configChanged();
}

void VisualizerService::setColorMode(int mode)
{
    const int clamped = qBound(0, mode, 2);
    if (m_colorMode == clamped)
        return;
    m_colorMode = clamped;
    if (m_settings)
        m_settings->set(QStringLiteral("visualizer.colorMode"), m_colorMode);
    emit colorModeChanged();
    emit configChanged();
}

void VisualizerService::setSensitivity(qreal value)
{
    const qreal clamped = qBound<qreal>(0.5, value, 2.5);
    if (qFuzzyCompare(m_sensitivity, clamped))
        return;
    m_sensitivity = clamped;
    m_atomicSensitivity.store(static_cast<float>(m_sensitivity), std::memory_order_relaxed);
    if (m_settings)
        m_settings->set(QStringLiteral("visualizer.sensitivity"), m_sensitivity);
    emit sensitivityChanged();
    emit configChanged();
}

void VisualizerService::setAlwaysListen(bool always)
{
    if (m_alwaysListen == always)
        return;
    m_alwaysListen = always;
    if (m_settings)
        m_settings->set(QStringLiteral("visualizer.alwaysListen"), m_alwaysListen);
    emit alwaysListenChanged();
    emit configChanged();
    syncCaptureState();
}

void VisualizerService::setStayWhenPaused(bool stay)
{
    if (m_stayWhenPaused == stay)
        return;
    m_stayWhenPaused = stay;
    if (m_settings)
        m_settings->set(QStringLiteral("visualizer.stayWhenPaused"), m_stayWhenPaused);
    emit stayWhenPausedChanged();
    emit configChanged();
}

void VisualizerService::setPosX(qreal x)
{
    if (qFuzzyCompare(m_posX, x))
        return;
    m_posX = x;
    if (m_settings)
        m_settings->set(QStringLiteral("visualizer.posX"), m_posX);
    emit positionChanged();
}

void VisualizerService::setPosY(qreal y)
{
    if (qFuzzyCompare(m_posY, y))
        return;
    m_posY = y;
    if (m_settings)
        m_settings->set(QStringLiteral("visualizer.posY"), m_posY);
    emit positionChanged();
}

void VisualizerService::setCustomWidth(int w)
{
    const int clamped = (w > 0) ? qBound(160, w, 3840) : 0;
    if (m_customWidth == clamped)
        return;
    m_customWidth = clamped;
    if (m_settings)
        m_settings->set(QStringLiteral("visualizer.customWidth"), m_customWidth);
    emit customSizeChanged();
    emit configChanged();
}

void VisualizerService::setCustomHeight(int h)
{
    const int clamped = (h > 0) ? qBound(80, h, 1440) : 0;
    if (m_customHeight == clamped)
        return;
    m_customHeight = clamped;
    if (m_settings)
        m_settings->set(QStringLiteral("visualizer.customHeight"), m_customHeight);
    emit customSizeChanged();
    emit configChanged();
}

void VisualizerService::setCustomSize(int w, int h)
{
    const int cw = (w > 0) ? qBound(160, w, 3840) : 0;
    const int ch = (h > 0) ? qBound(80, h, 1440) : 0;
    const bool changed = (m_customWidth != cw || m_customHeight != ch);
    m_customWidth = cw;
    m_customHeight = ch;
    if (m_settings) {
        m_settings->set(QStringLiteral("visualizer.customWidth"), m_customWidth);
        m_settings->set(QStringLiteral("visualizer.customHeight"), m_customHeight);
    }
    if (changed) {
        emit customSizeChanged();
        emit configChanged();
    }
}

void VisualizerService::setTransparentBg(bool transparent)
{
    if (m_transparentBg == transparent)
        return;
    m_transparentBg = transparent;
    if (m_settings)
        m_settings->set(QStringLiteral("visualizer.transparentBg"), m_transparentBg);
    emit transparentBgChanged();
    emit configChanged();
}

void VisualizerService::cycleSize()
{
    if (m_customWidth != 0 || m_customHeight != 0)
        setCustomSize(0, 0);
    setSizeIndex((m_sizeIndex + 1) % 4);
}

void VisualizerService::cycleColorMode()
{
    setColorMode((m_colorMode + 1) % 3);
}

void VisualizerService::setPosition(qreal x, qreal y)
{
    const bool changed = !qFuzzyCompare(m_posX, x) || !qFuzzyCompare(m_posY, y);
    m_posX = x;
    m_posY = y;
    if (m_settings) {
        m_settings->set(QStringLiteral("visualizer.posX"), m_posX);
        m_settings->set(QStringLiteral("visualizer.posY"), m_posY);
    }
    if (changed)
        emit positionChanged();
}

void VisualizerService::resetPosition()
{
    setPosition(-1.0, -1.0);
}

void VisualizerService::syncCaptureState()
{
    const bool mediaPlaying = m_media && m_media->isPlaying();
    const bool shouldRun = m_enabled && (m_alwaysListen || mediaPlaying);
    if (shouldRun) {
        startWorker();
        if (!m_frameTimer.isActive())
            m_frameTimer.start();
    } else {
        stopWorker();
        m_frameTimer.stop();
        {
            std::lock_guard<std::mutex> lock(m_sharedMutex);
            m_sharedBands.fill(0.0f);
            m_sharedLevel = 0.0f;
            m_sharedBass = 0.0f;
            m_lastAudioMs = 0;
        }
        bool changed = (m_level > 0.0 || m_bass > 0.0 || m_audioActive);
        for (int i = 0; i < kBandCount; ++i) {
            if (m_bands.at(i).toDouble() > 0.0) {
                m_bands[i] = 0.0;
                changed = true;
            }
        }
        m_level = 0.0;
        m_bass = 0.0;
        m_audioActive = false;
        if (changed)
            emit frameChanged();
    }
}

void VisualizerService::startWorker()
{
#ifdef Q_OS_WIN
    if (m_worker.joinable())
        return;
    m_stopFlag.store(false, std::memory_order_release);
    m_worker = std::thread(&VisualizerService::workerLoop, this);
#endif
}

void VisualizerService::stopWorker()
{
    m_stopFlag.store(true, std::memory_order_release);
    if (m_worker.joinable())
        m_worker.join();
}

void VisualizerService::onFrameTimer()
{
    std::array<float, kBandCount> snapBands{};
    float snapLevel = 0.0f;
    float snapBass = 0.0f;
    qint64 lastAudioMs = 0;
    {
        std::lock_guard<std::mutex> lock(m_sharedMutex);
        snapBands = m_sharedBands;
        snapLevel = m_sharedLevel;
        snapBass = m_sharedBass;
        lastAudioMs = m_lastAudioMs;
    }

    const qint64 nowMs = QDateTime::currentMSecsSinceEpoch();
    const bool nextActive = (lastAudioMs > 0) && ((nowMs - lastAudioMs) < 900);

    bool anyChanged = (nextActive != m_audioActive)
                      || (std::abs(static_cast<double>(snapLevel) - m_level) > 0.002)
                      || (std::abs(static_cast<double>(snapBass) - m_bass) > 0.002);

    for (int i = 0; i < kBandCount; ++i) {
        const double val = static_cast<double>(snapBands[i]);
        if (std::abs(val - m_bands.at(i).toDouble()) > 0.002) {
            m_bands[i] = val;
            anyChanged = true;
        }
    }

    if (anyChanged || nextActive) {
        m_level = static_cast<qreal>(snapLevel);
        m_bass = static_cast<qreal>(snapBass);
        m_audioActive = nextActive;
        emit frameChanged();
    }
}

void VisualizerService::workerLoop()
{
#ifdef Q_OS_WIN
    const HRESULT hrCo = CoInitializeEx(nullptr, COINIT_MULTITHREADED);

    std::array<float, kFftSize> hann{};
    constexpr float kTwoPi = 6.2831853071795864769f;
    for (int i = 0; i < kFftSize; ++i)
        hann[i] = 0.5f * (1.0f - std::cos(kTwoPi * static_cast<float>(i) / static_cast<float>(kFftSize - 1)));

    std::array<float, kFftSize> ring{};
    int ringPos = 0;
    std::array<float, kBandCount> smoothedBands{};
    float smoothedLevel = 0.0f;
    float smoothedBass = 0.0f;
    std::array<std::complex<float>, kFftSize> fftBuf{};

    while (!m_stopFlag.load(std::memory_order_acquire)) {
        IMMDeviceEnumerator* pEnum = nullptr;
        IMMDevice* pDevice = nullptr;
        IAudioClient* pClient = nullptr;
        IAudioCaptureClient* pCapture = nullptr;
        WAVEFORMATEX* wf = nullptr;
        bool started = false;

        HRESULT hr = CoCreateInstance(kClsidMMDeviceEnumerator, nullptr, CLSCTX_ALL,
                                      kIidIMMDeviceEnumerator, reinterpret_cast<void**>(&pEnum));
        if (SUCCEEDED(hr) && pEnum)
            hr = pEnum->GetDefaultAudioEndpoint(eRender, eConsole, &pDevice);
        if (SUCCEEDED(hr) && pDevice)
            hr = pDevice->Activate(kIidIAudioClient, CLSCTX_ALL, nullptr, reinterpret_cast<void**>(&pClient));
        if (SUCCEEDED(hr) && pClient)
            hr = pClient->GetMixFormat(&wf);
        if (SUCCEEDED(hr) && wf) {
            hr = pClient->Initialize(AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_LOOPBACK,
                                     200000, 0, wf, nullptr);
            if (FAILED(hr)) {
                hr = pClient->Initialize(AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_LOOPBACK,
                                         500000, 0, wf, nullptr);
            }
        }
        if (SUCCEEDED(hr) && pClient)
            hr = pClient->GetService(kIidIAudioCaptureClient, reinterpret_cast<void**>(&pCapture));
        if (SUCCEEDED(hr) && pClient) {
            hr = pClient->Start();
            started = SUCCEEDED(hr);
        }

        if (started && pCapture && wf) {
            const WORD channels = qMax<WORD>(1, wf->nChannels);
            const WORD bits = wf->wBitsPerSample;
            const bool isFloat = (wf->wFormatTag == WAVE_FORMAT_IEEE_FLOAT)
                || (wf->wFormatTag == WAVE_FORMAT_EXTENSIBLE
                    && reinterpret_cast<const WAVEFORMATEXTENSIBLE*>(wf)->SubFormat.Data1 == 3);
            const bool isPcm16 = !isFloat && (bits == 16)
                && (wf->wFormatTag == WAVE_FORMAT_PCM
                    || (wf->wFormatTag == WAVE_FORMAT_EXTENSIBLE
                        && reinterpret_cast<const WAVEFORMATEXTENSIBLE*>(wf)->SubFormat.Data1 == 1));
            const float sampleRate = static_cast<float>(qMax<DWORD>(8000, wf->nSamplesPerSec));

            // Precompute logarithmic bin ranges for 32 bands (28 Hz -> min(16000, Nyquist*0.92)).
            const float minFreq = 28.0f;
            const float maxFreq = std::min(16000.0f, sampleRate * 0.46f);
            const float binHz = sampleRate / static_cast<float>(kFftSize);
            std::array<int, kBandCount> binStart{};
            std::array<int, kBandCount> binEnd{};
            for (int b = 0; b < kBandCount; ++b) {
                const float f0 = minFreq * std::pow(maxFreq / minFreq, static_cast<float>(b) / static_cast<float>(kBandCount));
                const float f1 = minFreq * std::pow(maxFreq / minFreq, static_cast<float>(b + 1) / static_cast<float>(kBandCount));
                int sIdx = std::clamp(static_cast<int>(std::floor(f0 / binHz)), 1, kFftSize / 2 - 1);
                int eIdx = std::clamp(static_cast<int>(std::ceil(f1 / binHz)), sIdx + 1, kFftSize / 2);
                binStart[b] = sIdx;
                binEnd[b] = eIdx;
            }

            while (!m_stopFlag.load(std::memory_order_acquire)) {
                Sleep(12);
                if (m_stopFlag.load(std::memory_order_acquire))
                    break;

                bool invalidated = false;
                UINT32 packetLength = 0;
                while (SUCCEEDED(pCapture->GetNextPacketSize(&packetLength)) && packetLength > 0) {
                    BYTE* pData = nullptr;
                    UINT32 numFrames = 0;
                    DWORD flags = 0;
                    const HRESULT hrBuf = pCapture->GetBuffer(&pData, &numFrames, &flags, nullptr, nullptr);
                    if (hrBuf == AUDCLNT_E_DEVICE_INVALIDATED) {
                        invalidated = true;
                        break;
                    }
                    if (FAILED(hrBuf)) {
                        invalidated = true;
                        break;
                    }

                    const bool silent = (flags & AUDCLNT_BUFFERFLAGS_SILENT) != 0 || !pData;
                    if (silent) {
                        for (UINT32 f = 0; f < numFrames; ++f) {
                            ring[ringPos] = 0.0f;
                            ringPos = (ringPos + 1) % kFftSize;
                        }
                    } else if (isFloat) {
                        const float* fp = reinterpret_cast<const float*>(pData);
                        for (UINT32 f = 0; f < numFrames; ++f) {
                            float mono = 0.0f;
                            for (WORD ch = 0; ch < channels; ++ch)
                                mono += fp[f * channels + ch];
                            ring[ringPos] = mono / static_cast<float>(channels);
                            ringPos = (ringPos + 1) % kFftSize;
                        }
                    } else if (isPcm16) {
                        const qint16* ip = reinterpret_cast<const qint16*>(pData);
                        for (UINT32 f = 0; f < numFrames; ++f) {
                            float mono = 0.0f;
                            for (WORD ch = 0; ch < channels; ++ch)
                                mono += static_cast<float>(ip[f * channels + ch]) / 32768.0f;
                            ring[ringPos] = mono / static_cast<float>(channels);
                            ringPos = (ringPos + 1) % kFftSize;
                        }
                    }

                    pCapture->ReleaseBuffer(numFrames);
                }

                if (invalidated)
                    break;

                float sumSq = 0.0f;
                for (int i = 0; i < kFftSize; ++i) {
                    const float s = ring[(ringPos + i) % kFftSize];
                    sumSq += s * s;
                    fftBuf[i] = std::complex<float>(s * hann[i], 0.0f);
                }
                const float rms = std::sqrt(sumSq / static_cast<float>(kFftSize));
                const float sens = m_atomicSensitivity.load(std::memory_order_relaxed);
                const float rawLevel = std::clamp(std::tanh(rms * 4.2f * sens), 0.0f, 1.0f);

                bool hasSignal = (rms > 0.0012f);
                if (hasSignal) {
                    fftRadix2(fftBuf);

                    std::array<float, kFftSize / 2> mag{};
                    const float invNorm = 2.0f / static_cast<float>(kFftSize);
                    for (int k = 1; k < kFftSize / 2; ++k)
                        mag[k] = std::abs(fftBuf[k]) * invNorm;

                    for (int b = 0; b < kBandCount; ++b) {
                        float peak = 0.0f;
                        float avg = 0.0f;
                        const int sIdx = binStart[b];
                        const int eIdx = binEnd[b];
                        for (int k = sIdx; k < eIdx; ++k) {
                            peak = std::max(peak, mag[k]);
                            avg += mag[k];
                        }
                        avg /= static_cast<float>(std::max(1, eIdx - sIdx));
                        const float energy = 0.65f * peak + 0.35f * avg;
                        // Gentle high-frequency compensation so treble bars remain lively.
                        const float tilt = 1.0f + 0.85f * (static_cast<float>(b) / static_cast<float>(kBandCount - 1));
                        const float scaled = std::pow(std::clamp(energy * 9.5f * sens * tilt, 0.0f, 1.8f), 0.72f);
                        const float target = std::clamp(std::tanh(scaled * 0.95f), 0.0f, 1.0f);
                        const float alpha = (target > smoothedBands[b]) ? 0.62f : 0.22f;
                        smoothedBands[b] += (target - smoothedBands[b]) * alpha;
                    }
                } else {
                    for (int b = 0; b < kBandCount; ++b) {
                        smoothedBands[b] *= 0.80f;
                        if (smoothedBands[b] < 0.002f)
                            smoothedBands[b] = 0.0f;
                    }
                }

                const float levelAlpha = (rawLevel > smoothedLevel) ? 0.55f : 0.20f;
                smoothedLevel += (rawLevel - smoothedLevel) * levelAlpha;
                if (smoothedLevel < 0.002f)
                    smoothedLevel = 0.0f;

                float bassSum = 0.0f;
                for (int b = 0; b < 5; ++b)
                    bassSum += smoothedBands[b];
                const float rawBass = bassSum / 5.0f;
                smoothedBass += (rawBass - smoothedBass) * 0.45f;
                if (smoothedBass < 0.002f)
                    smoothedBass = 0.0f;

                {
                    std::lock_guard<std::mutex> lock(m_sharedMutex);
                    m_sharedBands = smoothedBands;
                    m_sharedLevel = smoothedLevel;
                    m_sharedBass = smoothedBass;
                    if (hasSignal)
                        m_lastAudioMs = QDateTime::currentMSecsSinceEpoch();
                }
            }
        }

        if (started && pClient)
            pClient->Stop();
        if (wf)
            CoTaskMemFree(wf);
        if (pCapture)
            pCapture->Release();
        if (pClient)
            pClient->Release();
        if (pDevice)
            pDevice->Release();
        if (pEnum)
            pEnum->Release();

        if (!m_stopFlag.load(std::memory_order_acquire)) {
            for (int step = 0; step < 8 && !m_stopFlag.load(std::memory_order_acquire); ++step)
                Sleep(50);
        }
    }

    if (SUCCEEDED(hrCo))
        CoUninitialize();
#endif
}
