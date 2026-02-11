#ifndef RELOAD_POPUP_H
#define RELOAD_POPUP_H

#include <QObject>
#include <QString>

class QQmlEngine;
class QQuickItem;
class QTimer;

/**
 * ReloadPopup — shows reload status (success toast or error overlay).
 *
 * Uses its own separate QQmlEngine so it survives main engine destruction.
 * The popup is injected as a QQuickItem into g_window->contentItem()
 * (shadow-cljs style), so it has no system borders or shadow.
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

    QString errorText() const { return m_errorText; }
    bool isError() const { return m_isError; }

    Q_INVOKABLE void copyToClipboard();

signals:
    void errorTextChanged();
    void isErrorChanged();
    void showAnimationRequested();
    void hideAnimationRequested();

private:
    void ensurePopup();
    void dismiss();

    QQmlEngine* m_engine = nullptr;
    QQuickItem* m_popupItem = nullptr;
    QTimer* m_hideTimer = nullptr;
    QString m_errorText;
    bool m_isError = false;
};

#endif // RELOAD_POPUP_H
