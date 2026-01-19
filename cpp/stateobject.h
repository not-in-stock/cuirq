#ifndef STATEOBJECT_H
#define STATEOBJECT_H

#include <QQmlPropertyMap>
#include <QString>
#include <QVariant>

/**
 * StateObject - Reactive state container for QML.
 *
 * Uses QQmlPropertyMap which provides automatic property change notifications.
 * This is the proper Qt way to do reactive data binding with dynamic properties.
 */
class StateObject : public QQmlPropertyMap
{
    Q_OBJECT

public:
    explicit StateObject(QObject *parent = nullptr);
    ~StateObject() override;

    // Set a property value (emits valueChanged signal automatically)
    Q_INVOKABLE void setProp(const QString& name, const QVariant& value);

    // Get a property value
    Q_INVOKABLE QVariant getProp(const QString& name) const;

    // Check if property exists
    Q_INVOKABLE bool hasProp(const QString& name) const;
};

#endif // STATEOBJECT_H
