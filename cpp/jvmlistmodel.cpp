#include "jvmlistmodel.h"
#include <QDebug>

JvmListModel::JvmListModel(QObject *parent)
  : QAbstractListModel(parent)
  , m_nextRoleId(Qt::UserRole + 1)
{
  qDebug() << "[CPP] JvmListModel created";
}

JvmListModel::~JvmListModel()
{
  qDebug() << "[CPP] JvmListModel destroyed";
}

int JvmListModel::rowCount(const QModelIndex &parent) const
{
  if (parent.isValid())
    return 0;
  return m_items.size();
}

QVariant JvmListModel::data(const QModelIndex &index, int role) const
{
  if (!index.isValid() || index.row() >= m_items.size())
    return QVariant();

  const QVariantMap& item = m_items.at(index.row());

  // Find role name for this role ID
  QByteArray roleName = m_roleNames.value(role);
  if (roleName.isEmpty())
    return QVariant();

  return item.value(QString::fromUtf8(roleName));
}

QHash<int, QByteArray> JvmListModel::roleNames() const
{
  return m_roleNames;
}

void JvmListModel::setJsonData(const QString& jsonData)
{
  qDebug() << "[CPP] JvmListModel::setJsonData called";
  qDebug() << "[CPP] JSON data length:" << jsonData.length();

  // Parse JSON
  QJsonDocument doc = QJsonDocument::fromJson(jsonData.toUtf8());
  if (!doc.isArray()) {
    qWarning() << "[CPP] ERROR: JSON data is not an array";
    return;
  }

  QJsonArray jsonArray = doc.array();
  qDebug() << "[CPP] Parsed" << jsonArray.size() << "items";

  // Convert to QVariantMap vector
  QVector<QVariantMap> newItems;
  newItems.reserve(jsonArray.size());

  for (const QJsonValue& value : jsonArray) {
    if (!value.isObject()) {
      qWarning() << "[CPP] WARNING: Skipping non-object item";
      continue;
    }

    QJsonObject obj = value.toObject();
    QVariantMap item;

    for (auto it = obj.begin(); it != obj.end(); ++it) {
      item.insert(it.key(), it.value().toVariant());
    }

    // Update role names based on keys in this item
    updateRoleNames(item);

    newItems.append(item);
  }

  // Replace entire model (Approach A: Full Replacement)
  beginResetModel();
  m_items = std::move(newItems);
  endResetModel();

  qDebug() << "[CPP] Model updated with" << m_items.size() << "items";
  qDebug() << "[CPP] Roles:" << m_roleNames;
}

void JvmListModel::updateJsonData(const QString& jsonData, const QString& keyField)
{
    QJsonDocument doc = QJsonDocument::fromJson(jsonData.toUtf8());
    if (!doc.isArray()) {
        qWarning() << "[CPP] ERROR: JSON data is not an array";
        return;
    }

    QJsonArray jsonArray = doc.array();

    // Parse new items
    QVector<QVariantMap> newItems;
    newItems.reserve(jsonArray.size());
    for (const QJsonValue& value : jsonArray) {
        if (!value.isObject()) continue;
        QJsonObject obj = value.toObject();
        QVariantMap item;
        for (auto it = obj.begin(); it != obj.end(); ++it) {
            item.insert(it.key(), it.value().toVariant());
        }
        updateRoleNames(item);
        newItems.append(item);
    }

    // Build set of new keys
    QSet<QString> newKeys;
    for (const auto& item : newItems) {
        newKeys.insert(item.value(keyField).toString());
    }

    // 1. Remove old items not in new set (walk backwards)
    for (int i = m_items.size() - 1; i >= 0; --i) {
        QString key = m_items[i].value(keyField).toString();
        if (!newKeys.contains(key)) {
            beginRemoveRows(QModelIndex(), i, i);
            m_items.removeAt(i);
            endRemoveRows();
        }
    }

    // 2. Build set of surviving keys
    QSet<QString> survivingKeys;
    for (const auto& item : m_items) {
        survivingKeys.insert(item.value(keyField).toString());
    }

    // 3. Insert new items at correct positions
    for (int i = 0; i < newItems.size(); ++i) {
        QString key = newItems[i].value(keyField).toString();
        if (!survivingKeys.contains(key)) {
            beginInsertRows(QModelIndex(), i, i);
            m_items.insert(i, newItems[i]);
            endInsertRows();
            survivingKeys.insert(key);
        }
    }

    // 4. Update data for surviving items and fix order
    // At this point m_items has the right set of keys but possibly wrong order/data.
    // Walk through newItems and ensure m_items matches.
    for (int newIdx = 0; newIdx < newItems.size(); ++newIdx) {
        if (newIdx >= m_items.size()) break;
        QString newKey = newItems[newIdx].value(keyField).toString();
        QString oldKey = m_items[newIdx].value(keyField).toString();
        if (oldKey == newKey) {
            // Same position — check if data changed
            if (m_items[newIdx] != newItems[newIdx]) {
                m_items[newIdx] = newItems[newIdx];
                QModelIndex idx = index(newIdx);
                emit dataChanged(idx, idx);
            }
        }
    }
}

void JvmListModel::clear()
{
  qDebug() << "[CPP] JvmListModel::clear called";
  beginResetModel();
  m_items.clear();
  endResetModel();
}

void JvmListModel::updateRoleNames(const QVariantMap& item)
{
  for (auto it = item.begin(); it != item.end(); ++it) {
    QByteArray roleName = it.key().toUtf8();

    // Check if this role already exists
    if (!m_roleIds.contains(roleName)) {
      int roleId = m_nextRoleId++;
      m_roleIds.insert(roleName, roleId);
      m_roleNames.insert(roleId, roleName);
      qDebug() << "[CPP] Registered role:" << roleName << "with ID:" << roleId;
    }
  }
}

int JvmListModel::getRoleId(const QByteArray& roleName)
{
  if (m_roleIds.contains(roleName)) {
    return m_roleIds.value(roleName);
  }

  // Auto-register new role
  int roleId = m_nextRoleId++;
  m_roleIds.insert(roleName, roleId);
  m_roleNames.insert(roleId, roleName);
  qDebug() << "[CPP] Auto-registered role:" << roleName << "with ID:" << roleId;
  return roleId;
}
