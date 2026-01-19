#ifndef JVMLISTMODEL_H
#define JVMLISTMODEL_H

#include <QAbstractListModel>
#include <QVariantMap>
#include <QVector>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QString>

/**
 * JvmListModel - QAbstractListModel for JVM data
 *
 * Receives JSON data from JVM and exposes it to QML ListView/GridView.
 * Supports dynamic roles based on JSON keys.
 */
class JvmListModel : public QAbstractListModel
{
    Q_OBJECT

public:
    explicit JvmListModel(QObject *parent = nullptr);
    ~JvmListModel() override;

    // QAbstractListModel interface
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    // Data management
    Q_INVOKABLE void setJsonData(const QString& jsonData);
    Q_INVOKABLE void clear();
    Q_INVOKABLE int count() const { return m_items.size(); }

private:
    QVector<QVariantMap> m_items;
    QHash<int, QByteArray> m_roleNames;
    QHash<QByteArray, int> m_roleIds;
    int m_nextRoleId;

    void updateRoleNames(const QVariantMap& item);
    int getRoleId(const QByteArray& roleName);
};

#endif // JVMLISTMODEL_H
