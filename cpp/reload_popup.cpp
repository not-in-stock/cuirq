#include "reload_popup.h"

#include <QQmlEngine>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQuickItem>
#include <QQuickWindow>
#include <QTimer>
#include <QGuiApplication>
#include <QClipboard>
#include <QFileInfo>
#include <QDebug>

// Main app window — popup is injected into its content tree
extern QQuickWindow* g_window;

ReloadPopup::ReloadPopup(QObject* parent)
    : QObject(parent)
{
}

ReloadPopup::~ReloadPopup()
{
    if (m_popupItem)
        m_popupItem->setParentItem(nullptr);
    delete m_engine;
}

void ReloadPopup::ensurePopup()
{
    if (m_popupItem) return;
    if (!g_window) return;

    m_engine = new QQmlEngine(this);
    m_engine->rootContext()->setContextProperty("popup", this);

    // In dev builds, load from disk (editable without rebuild).
    // In production, fall back to qrc.
    QUrl qmlUrl;
#ifdef CUIRQ_SOURCE_DIR
    QString diskPath = QStringLiteral(CUIRQ_SOURCE_DIR) + "/cpp/qml/ReloadPopup.qml";
    if (QFileInfo::exists(diskPath))
        qmlUrl = QUrl::fromLocalFile(diskPath);
    else
#endif
        qmlUrl = QUrl("qrc:/cuirq/qml/ReloadPopup.qml");

    QQmlComponent comp(m_engine, qmlUrl);
    if (!comp.isReady()) {
        qWarning() << "[CPP] ReloadPopup: QML errors:" << comp.errors();
        return;
    }

    auto* obj = comp.create();
    m_popupItem = qobject_cast<QQuickItem*>(obj);
    if (!m_popupItem) {
        qWarning() << "[CPP] ReloadPopup: Root is not an Item";
        delete obj;
        return;
    }

    // Inject into main window content tree (shadow-cljs style)
    m_popupItem->setParentItem(g_window->contentItem());
    m_popupItem->setZ(9999);

    m_hideTimer = new QTimer(this);
    m_hideTimer->setSingleShot(true);
    connect(m_hideTimer, &QTimer::timeout, this, &ReloadPopup::dismiss);
}

void ReloadPopup::showSuccess()
{
    ensurePopup();
    if (!m_popupItem) return;

    m_isError = false;
    m_errorText.clear();
    emit isErrorChanged();
    emit errorTextChanged();
    emit showAnimationRequested();
    m_hideTimer->start(1500);
}

void ReloadPopup::showError(const QString& message)
{
    ensurePopup();
    if (!m_popupItem) return;

    m_isError = true;
    m_errorText = message;
    emit isErrorChanged();
    emit errorTextChanged();

    m_hideTimer->stop();
    emit showAnimationRequested();
}

void ReloadPopup::appendWarning(const QString& message)
{
    if (!m_errorText.isEmpty())
        m_errorText += "\n";
    m_errorText += message;
    emit errorTextChanged();
}

void ReloadPopup::copyToClipboard()
{
    if (!m_errorText.isEmpty())
        QGuiApplication::clipboard()->setText(m_errorText);
}

void ReloadPopup::dismiss()
{
    emit hideAnimationRequested();
}
