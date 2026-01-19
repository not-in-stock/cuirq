#include "stateobject.h"
#include <QDebug>

StateObject::StateObject(QObject *parent)
    : QQmlPropertyMap(this, parent)
{
    qDebug() << "[CPP] StateObject created (QQmlPropertyMap)";
}

StateObject::~StateObject()
{
    qDebug() << "[CPP] StateObject destroyed";
}

void StateObject::setProp(const QString& name, const QVariant& value)
{
    // QQmlPropertyMap::insert() automatically emits valueChanged signal
    // which QML will detect and update bindings
    insert(name, value);
    qDebug() << "[CPP] StateObject: Property" << name << "=" << value << "(signal emitted)";
}

QVariant StateObject::getProp(const QString& name) const
{
    return value(name);
}

bool StateObject::hasProp(const QString& name) const
{
    return contains(name);
}
