#include "reload_popup.h"

#include <QQmlEngine>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQuickWindow>
#include <QTimer>
#include <QGuiApplication>
#include <QScreen>
#include <QDebug>

ReloadPopup::ReloadPopup(QObject* parent)
    : QObject(parent)
{
}

ReloadPopup::~ReloadPopup()
{
    delete m_window;
    delete m_engine;
}

void ReloadPopup::ensurePopup()
{
    if (m_engine) return;

    m_engine = new QQmlEngine(this);
    m_engine->rootContext()->setContextProperty("popup", this);

    QQmlComponent comp(m_engine, QUrl("qrc:/cuirq/qml/ReloadPopup.qml"));
    if (!comp.isReady()) {
        qWarning() << "[CPP] ReloadPopup: QML errors:" << comp.errors();
        return;
    }

    auto* obj = comp.create();
    m_window = qobject_cast<QQuickWindow*>(obj);
    if (!m_window) {
        qWarning() << "[CPP] ReloadPopup: Root is not a Window";
        delete obj;
        return;
    }

    m_hideTimer = new QTimer(this);
    m_hideTimer->setSingleShot(true);
    connect(m_hideTimer, &QTimer::timeout, this, &ReloadPopup::hide);
}

void ReloadPopup::showSuccess()
{
    ensurePopup();
    if (!m_window) return;

    m_isError = false;
    m_errorText.clear();
    emit isErrorChanged();
    emit errorTextChanged();

    // Position in top-right of primary screen
    if (auto* screen = QGuiApplication::primaryScreen()) {
        auto geom = screen->availableGeometry();
        m_window->setX(geom.right() - m_window->width() - 20);
        m_window->setY(geom.top() + 40);
    }

    m_window->show();
    m_window->raise();
    m_hideTimer->start(1500);
}

void ReloadPopup::showError(const QString& message)
{
    ensurePopup();
    if (!m_window) return;

    m_isError = true;
    m_errorText = message;
    emit isErrorChanged();
    emit errorTextChanged();

    m_hideTimer->stop();

    if (auto* screen = QGuiApplication::primaryScreen()) {
        auto geom = screen->availableGeometry();
        m_window->setX(geom.right() - m_window->width() - 20);
        m_window->setY(geom.top() + 40);
    }

    m_window->show();
    m_window->raise();
}

void ReloadPopup::appendWarning(const QString& message)
{
    if (!m_errorText.isEmpty())
        m_errorText += "\n";
    m_errorText += message;
    emit errorTextChanged();
}

void ReloadPopup::hide()
{
    if (m_window) m_window->hide();
}
