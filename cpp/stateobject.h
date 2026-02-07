#ifndef STATEOBJECT_H
#define STATEOBJECT_H

#include <QObject>
#include <QQmlPropertyMap>
#include <QString>
#include <QVariant>

// Plain QObject notifier — QML can always see signals on plain QObjects.
// QQmlPropertyMap subclasses have dynamic meta-objects that hide custom signals in Qt 6.10.
class StateNotifier : public QObject
{
    Q_OBJECT

public:
    explicit StateNotifier(QObject *parent = nullptr) : QObject(parent) {}

signals:
    void propChanged(const QString& key, const QVariant& value);
};

class StateObject : public QQmlPropertyMap
{
    Q_OBJECT

public:
    explicit StateObject(StateNotifier* notifier, QObject *parent = nullptr);
    ~StateObject() override;

    Q_INVOKABLE void setProp(const QString& name, const QVariant& value);
    Q_INVOKABLE QVariant getProp(const QString& name) const;
    Q_INVOKABLE bool hasProp(const QString& name) const;
    void reemitAll();

private:
    StateNotifier* m_notifier;
};

#endif // STATEOBJECT_H
