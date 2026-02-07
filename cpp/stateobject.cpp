#include "stateobject.h"
#include <QDebug>
#include <QThread>

StateObject::StateObject(StateNotifier* notifier, QObject *parent)
    : QQmlPropertyMap(this, parent)
    , m_notifier(notifier)
{
    qDebug() << "[CPP] StateObject created (QQmlPropertyMap)";
}

StateObject::~StateObject()
{
    qDebug() << "[CPP] StateObject destroyed";
}

void StateObject::setProp(const QString& name, const QVariant& value)
{
    // Must run on Qt main thread for QML bindings to update
    if (QThread::currentThread() != thread()) {
        QMetaObject::invokeMethod(this, [this, name, value]() {
            setProp(name, value);
        }, Qt::QueuedConnection);
        return;
    }

    insert(name, value);
    if (m_notifier) {
        emit m_notifier->propChanged(name, value);
    }
    qDebug() << "[CPP] StateObject: Property" << name << "=" << value;
}

QVariant StateObject::getProp(const QString& name) const
{
    return value(name);
}

bool StateObject::hasProp(const QString& name) const
{
    return contains(name);
}

void StateObject::reemitAll()
{
    if (!m_notifier) return;
    for (const QString& key : keys()) {
        emit m_notifier->propChanged(key, value(key));
    }
    qDebug() << "[CPP] StateObject: Re-emitted" << keys().size() << "properties";
}
