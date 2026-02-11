#ifndef RELOAD_POPUP_H
#define RELOAD_POPUP_H

#include <QObject>
#include <QString>
#include <QStringList>

class QQmlEngine;
class QQuickWindow;
class QTimer;

/**
 * ReloadPopup — shows reload status (success toast or error overlay).
 *
 * Uses its own separate QQmlEngine so it survives main engine destruction.
 * Lazily creates the engine on first use from a qrc-embedded QML file.
 *
 * Compile-time excluded in production builds (CUIRQ_DEV_RELOAD).
 */
class ReloadPopup : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString errorText READ errorText NOTIFY errorTextChanged)
    Q_PROPERTY(bool isError READ isError NOTIFY isErrorChanged)

public:
    explicit ReloadPopup(QObject* parent = nullptr);
    ~ReloadPopup() override;

    void showSuccess();
    void showError(const QString& message);
    void appendWarning(const QString& message);
    void hide();

    QString errorText() const { return m_errorText; }
    bool isError() const { return m_isError; }

signals:
    void errorTextChanged();
    void isErrorChanged();

private:
    void ensurePopup();

    QQmlEngine* m_engine = nullptr;
    QQuickWindow* m_window = nullptr;
    QTimer* m_hideTimer = nullptr;
    QString m_errorText;
    bool m_isError = false;
};

#endif // RELOAD_POPUP_H
