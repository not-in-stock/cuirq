#pragma once

#include <QHash>
#include <QString>
#include <QByteArray>
#include <QDateTime>
#include <QFile>
#include <memory>
#include <private/qabstractfileengine_p.h>

class QmlMemoryFileEngine : public QAbstractFileEngine {
public:
    QmlMemoryFileEngine(const QString& path, const QByteArray& contents)
        : m_path(path), m_contents(contents), m_pos(0) {}

    bool open(QIODevice::OpenMode, std::optional<QFile::Permissions>) override {
        m_pos = 0;
        return true;
    }

    bool close() override {
        m_pos = 0;
        return true;
    }

    qint64 read(char* data, qint64 maxlen) override {
        qint64 remaining = m_contents.size() - m_pos;
        qint64 toRead = qMin(maxlen, remaining);
        if (toRead <= 0) return 0;
        memcpy(data, m_contents.constData() + m_pos, toRead);
        m_pos += toRead;
        return toRead;
    }

    qint64 size() const override {
        return m_contents.size();
    }

    qint64 pos() const override {
        return m_pos;
    }

    bool seek(qint64 pos) override {
        if (pos < 0 || pos > m_contents.size()) return false;
        m_pos = pos;
        return true;
    }

    bool isSequential() const override {
        return false;
    }

    FileFlags fileFlags(FileFlags type) const override {
        FileFlags flags;
        if (type & ExistsFlag) flags |= ExistsFlag;
        if (type & ReadOtherPerm) flags |= ReadOtherPerm;
        if (type & FileType) flags |= FileType;
        return flags;
    }

    QString fileName(FileName file) const override {
        switch (file) {
        case DefaultName:
        case AbsoluteName:
        case CanonicalName:
            return m_path;
        default:
            return {};
        }
    }

    QDateTime fileTime(QFile::FileTime time) const override {
        if (time == QFile::FileModificationTime) {
            // Report as "future" so QML engine skips .qmlc cache
            return QDateTime::currentDateTime().addYears(1);
        }
        return QDateTime::currentDateTime();
    }

private:
    QString m_path;
    QByteArray m_contents;
    qint64 m_pos;
};

class QmlFileOverride : public QAbstractFileEngineHandler {
public:
    std::unique_ptr<QAbstractFileEngine> create(const QString& fileName) const override {
        if (m_overrides.contains(fileName)) {
            return std::make_unique<QmlMemoryFileEngine>(fileName, m_overrides[fileName]);
        }
        return nullptr;
    }

    void updateFile(const QString& path) {
        QFile f(path);
        // Temporarily remove override so we read actual disk
        m_overrides.remove(path);
        if (f.open(QIODevice::ReadOnly)) {
            m_overrides.insert(path, f.readAll());
            f.close();
            qDebug() << "Override updated:" << path << "(" << m_overrides[path].size() << "bytes)";
        }
    }

    void clear() {
        m_overrides.clear();
    }

private:
    QHash<QString, QByteArray> m_overrides;
};
