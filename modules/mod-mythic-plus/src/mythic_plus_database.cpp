/*
 * Credits: silviu20092
 */

#include "mythic_plus_database.h"

#include "Config.h"
#include "DatabaseEnv.h"
#include "DatabaseScript.h"
#include "Log.h"
#include "ModuleDatabasePool.h"
#include "MySQLConnection.h"
#include "MySQLPreparedStatement.h"
#include "PCQueue.h"
#include "PreparedStatement.h"
#include <atomic>
#include <string>
#include <string_view>

namespace
{
    constexpr char const* PROGRESS_TABLE = "mod_mythic_plus_progress";
    constexpr char const* RUN_TABLE = "mythic_plus_dungeon";

    enum MythicPlusDatabaseStatements : uint32
    {
        MYTHIC_SEL_PROGRESS = 0,
        MYTHIC_REP_PROGRESS,
        MYTHIC_REP_RUN,
        MYTHIC_DEL_RUN,
        MYTHIC_DEL_RUNS,
        MYTHIC_SEL_TABLE,
        MYTHIC_STMT_COUNT,
    };

    class MythicPlusDatabaseConnection : public MySQLConnection
    {
    public:
        MythicPlusDatabaseConnection(MySQLConnectionInfo& connInfo) : MySQLConnection(connInfo)
        {
            m_stmts.resize(MYTHIC_STMT_COUNT);
        }

        MythicPlusDatabaseConnection(ProducerConsumerQueue<SQLOperation*>* queue, MySQLConnectionInfo& connInfo)
            : MySQLConnection(queue, connInfo)
        {
            m_stmts.resize(MYTHIC_STMT_COUNT);
        }

        ~MythicPlusDatabaseConnection() override = default;

        void DoPrepareStatements() override
        {
            // MySQLConnection::PrepareStatement indexes m_stmts directly. Both constructors must size
            // the storage, and a wrong size must fail closed instead of touching an empty vector.
            if (m_stmts.size() != MYTHIC_STMT_COUNT)
            {
                LOG_ERROR("module.mythic_plus",
                    "Mythic+ statement storage is not sized ({} != {}).",
                    m_stmts.size(), uint32(MYTHIC_STMT_COUNT));
                m_prepareError = true;
                return;
            }

            PrepareStatement(MYTHIC_SEL_PROGRESS,
                "SELECT `guid`, `era`, `highest_key` FROM `mod_mythic_plus_progress`",
                CONNECTION_SYNCH);
            PrepareStatement(MYTHIC_REP_PROGRESS,
                "INSERT INTO `mod_mythic_plus_progress` (`guid`, `era`, `highest_key`) VALUES (?, ?, ?) "
                "ON DUPLICATE KEY UPDATE `highest_key` = GREATEST(`highest_key`, VALUES(`highest_key`))",
                CONNECTION_BOTH);
            PrepareStatement(MYTHIC_REP_RUN,
                "REPLACE INTO `mythic_plus_dungeon` (`id`, `map`, `timelimit`, `starttime`, "
                "`mythiclevel`, `done`, `penalty_on_death`, `deaths`) "
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
                CONNECTION_BOTH);
            PrepareStatement(MYTHIC_DEL_RUN,
                "DELETE FROM `mythic_plus_dungeon` WHERE `id` = ?",
                CONNECTION_BOTH);
            PrepareStatement(MYTHIC_DEL_RUNS,
                "DELETE FROM `mythic_plus_dungeon`",
                CONNECTION_BOTH);
            PrepareStatement(MYTHIC_SEL_TABLE,
                "SELECT COUNT(*) FROM information_schema.tables "
                "WHERE table_schema = DATABASE() AND table_name = ?",
                CONNECTION_SYNCH);
        }
    };

    class MythicPlusDatabasePool : public ModuleDatabasePool
    {
    protected:
        MySQLConnection* CreateConnection(MySQLConnectionInfo& connInfo) override
        {
            return new MythicPlusDatabaseConnection(connInfo);
        }

        MySQLConnection* CreateAsyncConnection(ProducerConsumerQueue<SQLOperation*>* queue,
            MySQLConnectionInfo& connInfo) override
        {
            return new MythicPlusDatabaseConnection(queue, connInfo);
        }
    };

    MythicPlusDatabasePool MythicDatabase;
    std::atomic<bool> DatabaseOpen{ false };
    std::atomic<bool> TablesReady{ false };

    bool ProbeTable(std::string_view table)
    {
        auto* stmt = new PreparedStatement<MythicPlusDatabaseConnection>(MYTHIC_SEL_TABLE, 1);
        stmt->SetArguments(table);
        PreparedQueryResult result = MythicDatabase.Query(stmt);
        return result && result->Fetch()[0].Get<uint64>() > 0;
    }
}

namespace MythicPlusDatabase
{
    bool IsReady()
    {
        return DatabaseOpen.load() && TablesReady.load();
    }

    void Open()
    {
        if (DatabaseOpen.load())
            return;

        std::string const info = sConfigMgr->GetOption<std::string>("CharacterDatabaseInfo", "");
        if (info.empty())
        {
            LOG_ERROR("module.mythic_plus",
                "CharacterDatabaseInfo is not set; no module database pool. Mythic+ disabled.");
            return;
        }

        MythicDatabase.SetConnectionInfo(info, 1, 1);
        if (uint32 error = MythicDatabase.Open())
        {
            LOG_ERROR("module.mythic_plus",
                "Could not open the module database pool (error {}). Mythic+ disabled.", error);
            return;
        }

        if (!MythicDatabase.PrepareStatements())
        {
            LOG_ERROR("module.mythic_plus",
                "Could not prepare the module database statements. Mythic+ disabled.");
            MythicDatabase.Close();
            return;
        }

        DatabaseOpen.store(true);

        bool ready = true;
        if (!ProbeTable(PROGRESS_TABLE))
        {
            LOG_ERROR("module.mythic_plus",
                "Table `{}` is missing from the characters database. Mythic+ disabled.", PROGRESS_TABLE);
            ready = false;
        }

        if (!ProbeTable(RUN_TABLE))
        {
            LOG_ERROR("module.mythic_plus",
                "Table `{}` is missing from the characters database. Mythic+ disabled.", RUN_TABLE);
            ready = false;
        }

        TablesReady.store(ready);
    }

    void Close()
    {
        if (!DatabaseOpen.load())
            return;

        MythicDatabase.Close();
        DatabaseOpen.store(false);
        TablesReady.store(false);
    }

    void ClearRunRows()
    {
        if (!IsReady())
            return;

        auto* stmt = new PreparedStatement<MythicPlusDatabaseConnection>(MYTHIC_DEL_RUNS, 0);
        MythicDatabase.DirectExecute(stmt);
    }

    void SaveRun(uint32 instanceId, uint32 mapId, uint32 timeLimit, uint64 startTimeMs,
        uint32 keyLevel, uint32 penaltyOnDeath, uint32 deaths)
    {
        if (!IsReady())
        {
            LOG_ERROR("module.mythic_plus", "Cannot save run for instance {}; database is not ready", instanceId);
            return;
        }

        auto* stmt = new PreparedStatement<MythicPlusDatabaseConnection>(MYTHIC_REP_RUN, 8);
        stmt->SetArguments(instanceId, mapId, timeLimit, startTimeMs, keyLevel, uint8(0),
            penaltyOnDeath, deaths);
        MythicDatabase.DirectExecute(stmt);
    }

    void DeleteRun(uint32 instanceId)
    {
        if (!IsReady())
            return;

        auto* stmt = new PreparedStatement<MythicPlusDatabaseConnection>(MYTHIC_DEL_RUN, 1);
        stmt->SetArguments(instanceId);
        MythicDatabase.DirectExecute(stmt);
    }

    bool LoadProgress(std::unordered_map<uint64, uint8>& progress)
    {
        progress.clear();
        if (!IsReady())
            return false;

        auto* stmt = new PreparedStatement<MythicPlusDatabaseConnection>(MYTHIC_SEL_PROGRESS, 0);
        PreparedQueryResult result = MythicDatabase.Query(stmt);
        if (result)
        {
            do
            {
                Field* fields = result->Fetch();
                uint32 guid = fields[0].Get<uint32>();
                uint8 era = fields[1].Get<uint8>();
                uint8 highest = fields[2].Get<uint8>();
                progress[(uint64(era) << 32) | guid] = highest;
            } while (result->NextRow());
        }

        return true;
    }

    void SaveProgress(uint32 guid, uint8 era, uint8 highestKey)
    {
        if (!IsReady())
        {
            LOG_ERROR("module.mythic_plus", "Cannot save progress for character {}; database is not ready", guid);
            return;
        }

        auto* stmt = new PreparedStatement<MythicPlusDatabaseConnection>(MYTHIC_REP_PROGRESS, 3);
        stmt->SetArguments(guid, era, highestKey);
        MythicDatabase.Execute(stmt);
    }
}

class MythicPlusDatabaseScript : public DatabaseScript
{
public:
    MythicPlusDatabaseScript() : DatabaseScript("MythicPlusDatabaseScript", {
        DATABASEHOOK_ON_MODULE_DATABASES_LOADING,
        DATABASEHOOK_ON_MODULE_DATABASES_KEEPALIVE,
        DATABASEHOOK_ON_MODULE_DATABASES_CLOSING,
        DATABASEHOOK_ON_DATABASE_WARN_ABOUT_SYNC_QUERIES
    }) { }

    bool OnModuleDatabasesLoading() override
    {
        MythicPlusDatabase::Open();
        return true;
    }

    void OnModuleDatabasesKeepAlive() override
    {
        if (DatabaseOpen.load())
            MythicDatabase.KeepAlive();
    }

    void OnModuleDatabasesClosing() override
    {
        MythicPlusDatabase::Close();
    }

    void OnDatabaseWarnAboutSyncQueries(bool apply) override
    {
        MythicDatabase.WarnAboutSyncQueries(apply);
    }
};

void AddSC_mythic_plus_database()
{
    new MythicPlusDatabaseScript();
}
