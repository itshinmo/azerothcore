/*
 * PvP rulesets for AzerothCore (RFC-006, ADR-033). Slice 1: mode state, the pledge
 * command, the War Mode/High Risk PvP flag and the outdoor experience bonus.
 *
 * The chest, mercenary, Outlaw, guard/reaction seams and the live map feed are later
 * slices and are intentionally absent here.
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Affero General Public License as published by the
 * Free Software Foundation; either version 3 of the License, or (at your
 * option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License for
 * more details.
 */

#include "PvpRulesets.h"

#include "Chat.h"
#include "CommandScript.h"
#include "Config.h"
#include "DatabaseEnv.h"
#include "DatabaseScript.h"
#include "DBCEnums.h"
#include "DBCStores.h"
#include "GameTime.h"
#include "Log.h"
#include "Map.h"
#include "ModuleDatabasePool.h"
#include "MySQLConnection.h"
#include "MySQLPreparedStatement.h"
#include "Player.h"
#include "PlayerScript.h"
#include "PreparedStatement.h"
#include "Realm.h"
#include "World.h"
#include "WorldScript.h"
#include "WorldSession.h"

#include <algorithm>
#include <atomic>
#include <cctype>
#include <mutex>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_map>

using namespace Acore::ChatCommands;

namespace
{
    // "Command: pledge (project)", created and granted to role 199 (Player Commands) by
    // data/sql/custom/db_auth/pvp_rulesets_command.sql.
    constexpr uint32 PLEDGE_PERMISSION = 950151;

    constexpr char const* STATE_TABLE = "mod_pvp_rulesets_state";

    // Module-owned pool against CharacterDatabaseInfo, so the module can use prepared
    // statements without adding statements to the core enum.
    enum PvpRulesetsDatabaseStatements : uint32
    {
        PVP_SEL_STATE = 0,
        PVP_REP_STATE,
        PVP_DEL_STATE,
        PVP_SEL_TABLE,
        PVP_STMT_COUNT,
    };

    class PvpRulesetsDatabaseConnection : public MySQLConnection
    {
    public:
        PvpRulesetsDatabaseConnection(MySQLConnectionInfo& connInfo) : MySQLConnection(connInfo)
        {
            m_stmts.resize(PVP_STMT_COUNT);
        }

        PvpRulesetsDatabaseConnection(ProducerConsumerQueue<SQLOperation*>* queue, MySQLConnectionInfo& connInfo)
            : MySQLConnection(queue, connInfo)
        {
            m_stmts.resize(PVP_STMT_COUNT);
        }

        ~PvpRulesetsDatabaseConnection() override = default;

        void DoPrepareStatements() override
        {
            // MySQLConnection::PrepareStatement indexes m_stmts directly, so the storage must be
            // sized here. A ModuleDatabasePool subclass cannot rely on the core to do it.
            if (m_stmts.size() != PVP_STMT_COUNT)
            {
                LOG_ERROR("module.pvp.rulesets",
                    "PvP rulesets statement storage is not sized ({} != {}).",
                    m_stmts.size(), uint32(PVP_STMT_COUNT));
                m_prepareError = true;
                return;
            }

            PrepareStatement(PVP_SEL_STATE,
                "SELECT `mode`, `last_toggle` FROM `mod_pvp_rulesets_state` WHERE `guid` = ?",
                CONNECTION_ASYNC);
            PrepareStatement(PVP_REP_STATE,
                "INSERT INTO `mod_pvp_rulesets_state` (`guid`, `mode`, `last_toggle`) VALUES (?, ?, ?) "
                "ON DUPLICATE KEY UPDATE `mode` = ?, `last_toggle` = ?",
                CONNECTION_ASYNC);
            PrepareStatement(PVP_DEL_STATE,
                "DELETE FROM `mod_pvp_rulesets_state` WHERE `guid` = ?",
                CONNECTION_ASYNC);
            PrepareStatement(PVP_SEL_TABLE,
                "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() "
                "AND table_name = ?",
                CONNECTION_SYNCH);
        }
    };

    class PvpRulesetsDatabasePool : public ModuleDatabasePool
    {
    protected:
        MySQLConnection* CreateConnection(MySQLConnectionInfo& connInfo) override
        {
            return new PvpRulesetsDatabaseConnection(connInfo);
        }

        MySQLConnection* CreateAsyncConnection(ProducerConsumerQueue<SQLOperation*>* queue,
            MySQLConnectionInfo& connInfo) override
        {
            return new PvpRulesetsDatabaseConnection(queue, connInfo);
        }
    };

    PvpRulesetsDatabasePool PvpDatabase;
    bool DatabaseOpen = false;

    struct PlayerState
    {
        PvpRulesets::Mode Mode = PvpRulesets::Mode::Pve;
        int64 LastToggle = 0;
        bool Loaded = false;  // the row read has returned
        bool Loading = false; // a row read is in flight
    };

    // One lock for the character map. Runtime config and table flags are separate atomics,
    // so hot paths (XP, flag re-asserts) never wait on the map lock. The lock is never held
    // across a database call, a player update or a chat send.
    std::mutex StateMutex;
    std::unordered_map<uint32, PlayerState> States; // character guid counter

    std::atomic<bool> ConfigEnabled{false};
    std::atomic<uint32> WarModeXpPercent{10};
    std::atomic<uint32> HighRiskXpPercent{15};
    std::atomic<uint32> ToggleCooldownMinutes{5};
    std::atomic<bool> TableReady{false};
    std::atomic<bool> RuntimeEnabled{false};

    bool GameTypeSupported()
    {
        return sWorld->getIntConfig(CONFIG_GAME_TYPE) == REALM_TYPE_NORMAL;
    }

    void RecomputeRuntimeEnabled()
    {
        RuntimeEnabled.store(ConfigEnabled.load() && TableReady.load() && GameTypeSupported());
    }

    uint32 ToggleCooldownSeconds()
    {
        return ToggleCooldownMinutes.load() * 60;
    }

    AreaTableEntry const* LookupArea(uint32 areaId)
    {
        return sAreaTableStore.LookupEntry(areaId);
    }

    bool IsCapitalZone(uint32 zoneId)
    {
        AreaTableEntry const* zone = LookupArea(zoneId);
        return zone && (zone->flags & AREA_FLAG_CAPITAL);
    }

    bool IsBattlefieldZone(uint32 zoneId)
    {
        AreaTableEntry const* zone = LookupArea(zoneId);
        return zone && (zone->flags & AREA_FLAG_WINTERGRASP);
    }

    bool TryGetState(uint32 guid, PlayerState& state)
    {
        std::lock_guard<std::mutex> lock(StateMutex);
        auto itr = States.find(guid);
        if (itr == States.end())
            return false;

        state = itr->second;
        return true;
    }

    // Starts one row read unless the state is loaded or already loading. Returns true when
    // the caller must issue the query.
    bool BeginStateLoad(uint32 guid)
    {
        std::lock_guard<std::mutex> lock(StateMutex);
        auto itr = States.find(guid);
        if (itr == States.end())
        {
            PlayerState state;
            state.Loading = true;
            States[guid] = state;
            return true;
        }

        if (itr->second.Loaded || itr->second.Loading)
            return false;

        itr->second.Loading = true;
        return true;
    }

    void LoadState(Player* player, uint32 guid);
    void ApplyModePvpFlag(Player* player);

    void EnsureStateLoaded(Player* player)
    {
        uint32 const guid = player->GetGUID().GetCounter();
        if (BeginStateLoad(guid))
            LoadState(player, guid);
    }

    void PersistState(uint32 guid, PvpRulesets::Mode mode, int64 lastToggle)
    {
        uint32 const stamp = uint32(lastToggle);
        std::string_view const token = PvpRulesets::ModeToken(mode);

        auto* stmt = new PreparedStatement<PvpRulesetsDatabaseConnection>(PVP_REP_STATE, 5);
        stmt->SetArguments(guid, token, stamp, token, stamp);
        PvpDatabase.Execute(stmt);
    }

    void LoadState(Player* player, uint32 guid)
    {
        WorldSession* session = player->GetSession();
        if (!session)
            return;

        auto* stmt = new PreparedStatement<PvpRulesetsDatabaseConnection>(PVP_SEL_STATE, 1);
        stmt->SetArguments(guid);

        session->GetQueryProcessor().AddCallback(
            PvpDatabase.AsyncQuery(stmt).WithPreparedCallback([session, guid](PreparedQueryResult result)
            {
                Player* player = session->GetPlayer();
                if (!player || player->GetGUID().GetCounter() != guid)
                    return;

                PlayerState state;
                state.Loaded = true;
                if (result)
                {
                    Field* fields = result->Fetch();
                    if (std::optional<PvpRulesets::Mode> mode =
                            PvpRulesets::ParseMode(fields[0].Get<std::string>()))
                        state.Mode = *mode;
                    state.LastToggle = int64(fields[1].Get<uint32>());
                }

                {
                    std::lock_guard<std::mutex> lock(StateMutex);
                    auto itr = States.find(guid);
                    if (itr != States.end() && itr->second.LastToggle > 0)
                    {
                        // A pledge accepted while this read was in flight wins.
                        itr->second.Loaded = true;
                        itr->second.Loading = false;
                        return;
                    }

                    States[guid] = state;
                }

                ApplyModePvpFlag(player);
            }));
    }

    // War Mode and High Risk re-assert the flag on login, zone change, resurrection and any
    // unexpected core clear. PvE never calls this path.
    void ApplyModePvpFlag(Player* player)
    {
        if (!RuntimeEnabled.load() || player->IsGameMaster())
            return;

        PlayerState state;
        if (!TryGetState(player->GetGUID().GetCounter(), state))
            return;

        if (!state.Loaded || !PvpRulesets::ModeUsesPvpFlag(state.Mode))
            return;

        if (!player->IsPvP() || !player->HasPlayerFlag(PLAYER_FLAGS_IN_PVP))
        {
            // The unit byte makes the player attackable; the player flag is the persistent
            // native opt-in the client shows and the core's timer respects.
            player->SetPlayerFlag(PLAYER_FLAGS_IN_PVP);
            player->UpdatePvP(true, true);
        }
    }

    // Downgrading to PvE keeps the current PvP flag and starts the core's five-minute
    // out-of-combat timer, so a player cannot escape a fight by changing mode.
    void StartCorePvpCooldown(Player* player, int64 now)
    {
        player->RemovePlayerFlag(PLAYER_FLAGS_IN_PVP);
        if (player->pvpInfo.EndTimer == 0)
            player->pvpInfo.EndTimer = now;
    }

    std::string TrimmedLower(std::string_view text)
    {
        std::string token(text);
        std::size_t const first = token.find_first_not_of(" \t");
        if (first == std::string::npos)
            return {};
        token.erase(0, first);
        token.erase(token.find_last_not_of(" \t") + 1);
        std::transform(token.begin(), token.end(), token.begin(),
            [](unsigned char c) { return char(std::tolower(c)); });
        return token;
    }

    void SendPledgeStatus(ChatHandler* handler, PlayerState const& state)
    {
        uint32 const percent = PvpRulesets::XpBonusPercent(
            state.Mode, WarModeXpPercent.load(), HighRiskXpPercent.load());
        if (percent > 0)
            handler->PSendSysMessage("Pledge status: {} (+{}% outdoor XP).",
                PvpRulesets::ModeDisplayName(state.Mode), percent);
        else
            handler->SendSysMessage("Pledge status: PvE (no mode bonus; /pvp remains available).");

        int64 const remaining = PvpRulesets::CooldownRemainingSeconds(
            GameTime::GetGameTime().count(), state.LastToggle, ToggleCooldownSeconds());
        if (remaining > 0)
            handler->PSendSysMessage("Next pledge change available in {} seconds.", remaining);
    }

    class PledgeCommandScript : public CommandScript
    {
    public:
        PledgeCommandScript() : CommandScript("PledgeCommandScript") { }

        ChatCommandTable GetCommands() const override
        {
            static ChatCommandTable commandTable =
            {
                { "pledge", HandlePledgeCommand, PLEDGE_PERMISSION, Console::No }
            };

            return commandTable;
        }

    private:
        static bool HandlePledgeCommand(ChatHandler* handler, std::string_view args)
        {
            Player* player = handler->GetPlayer();
            if (!player)
                return false;

            std::string const token = TrimmedLower(args);
            if (token.empty())
            {
                handler->SendSysMessage("Usage: .pledge pve|warmode|highrisk|status");
                return true;
            }

            if (!RuntimeEnabled.load())
            {
                handler->SendSysMessage("PvP rulesets are disabled.");
                return true;
            }

            uint32 const guid = player->GetGUID().GetCounter();
            PlayerState state;
            if (!TryGetState(guid, state))
            {
                // The config was enabled after this character logged in.
                EnsureStateLoaded(player);
                handler->SendSysMessage("Your pledge is still loading. Try again in a moment.");
                return true;
            }

            if (!state.Loaded)
            {
                EnsureStateLoaded(player);
                handler->SendSysMessage("Your pledge is still loading. Try again in a moment.");
                return true;
            }

            if (token == "status")
            {
                SendPledgeStatus(handler, state);
                return true;
            }

            std::optional<PvpRulesets::Mode> const requested = PvpRulesets::ParseMode(token);
            if (!requested)
            {
                handler->SendSysMessage("Usage: .pledge pve|warmode|highrisk|status");
                return true;
            }

            if (state.Mode == *requested)
            {
                handler->PSendSysMessage("You are already pledged to {}.",
                    PvpRulesets::ModeDisplayName(*requested));
                return true;
            }

            int64 const now = GameTime::GetGameTime().count();

            PvpRulesets::ToggleContext context;
            context.enabled = true;
            context.gameMaster = player->IsGameMaster();
            context.alive = player->IsAlive();
            context.inCombat = player->IsInCombat();
            context.inInstance = player->GetMap()->IsDungeon();
            context.inBattleground = player->InBattleground();
            context.inArena = player->InArena();
            context.inBattlefield = IsBattlefieldZone(player->GetZoneId());
            context.inCapital = IsCapitalZone(player->GetZoneId());
            context.cooldownRemainingSeconds = PvpRulesets::CooldownRemainingSeconds(
                now, state.LastToggle, ToggleCooldownSeconds());

            PvpRulesets::ToggleResult const result = PvpRulesets::EvaluateToggle(context);
            if (result == PvpRulesets::ToggleResult::Cooldown)
            {
                handler->PSendSysMessage(
                    "You must wait {} more seconds before changing your pledge.",
                    context.cooldownRemainingSeconds);
                return true;
            }

            if (result != PvpRulesets::ToggleResult::Ok)
            {
                handler->SendSysMessage(PvpRulesets::ToggleRefusalMessage(result));
                return true;
            }

            bool accepted = false;
            {
                std::lock_guard<std::mutex> lock(StateMutex);
                auto itr = States.find(guid);
                if (itr != States.end() && itr->second.Loaded)
                {
                    itr->second.Mode = *requested;
                    itr->second.LastToggle = now;
                    accepted = true;
                }
            }

            if (!accepted)
            {
                handler->SendSysMessage("Your pledge is still loading. Try again in a moment.");
                return true;
            }

            PersistState(guid, *requested, now);

            if (PvpRulesets::ModeUsesPvpFlag(*requested))
                ApplyModePvpFlag(player);
            else
                StartCorePvpCooldown(player, now);

            LOG_INFO("module.pvp.rulesets", "Pledge: {} ({}) changed mode {} -> {}.",
                player->GetName(), guid, PvpRulesets::ModeToken(state.Mode),
                PvpRulesets::ModeToken(*requested));

            state.Mode = *requested;
            state.LastToggle = now;
            SendPledgeStatus(handler, state);
            return true;
        }
    };

    void OpenModuleDatabase()
    {
        std::string const info = sConfigMgr->GetOption<std::string>("CharacterDatabaseInfo", "");
        if (info.empty())
        {
            LOG_ERROR("module.pvp.rulesets",
                "CharacterDatabaseInfo is not set; no module database pool. PvP rulesets disabled.");
            return;
        }

        PvpDatabase.SetConnectionInfo(info, 1, 1);
        if (uint32 error = PvpDatabase.Open())
        {
            LOG_ERROR("module.pvp.rulesets",
                "Could not open the module database pool (error {}). PvP rulesets disabled.", error);
            return;
        }

        if (!PvpDatabase.PrepareStatements())
        {
            LOG_ERROR("module.pvp.rulesets",
                "Could not prepare the module database statements. PvP rulesets disabled.");
            PvpDatabase.Close();
            return;
        }

        DatabaseOpen = true;

        auto* stmt = new PreparedStatement<PvpRulesetsDatabaseConnection>(PVP_SEL_TABLE, 1);
        stmt->SetArguments(std::string_view(STATE_TABLE));
        PreparedQueryResult result = PvpDatabase.Query(stmt);
        bool const ready = result && result->Fetch()[0].Get<uint64>() > 0;
        TableReady.store(ready);

        if (!ready)
            LOG_ERROR("module.pvp.rulesets",
                "Table `{}` is missing from the characters database. PvP rulesets disabled.", STATE_TABLE);
    }

    class PvpRulesetsDatabaseScript : public DatabaseScript
    {
    public:
        PvpRulesetsDatabaseScript() : DatabaseScript("PvpRulesetsDatabaseScript", {
            DATABASEHOOK_ON_MODULE_DATABASES_LOADING,
            DATABASEHOOK_ON_MODULE_DATABASES_KEEPALIVE,
            DATABASEHOOK_ON_MODULE_DATABASES_CLOSING,
            DATABASEHOOK_ON_DATABASE_WARN_ABOUT_SYNC_QUERIES
        }) { }

        bool OnModuleDatabasesLoading() override
        {
            OpenModuleDatabase();
            return true; // a broken optional module never aborts the worldserver
        }

        void OnModuleDatabasesKeepAlive() override
        {
            if (DatabaseOpen)
                PvpDatabase.KeepAlive();
        }

        void OnModuleDatabasesClosing() override
        {
            if (!DatabaseOpen)
                return;

            PvpDatabase.Close();
            DatabaseOpen = false;
        }

        void OnDatabaseWarnAboutSyncQueries(bool apply) override
        {
            PvpDatabase.WarnAboutSyncQueries(apply);
        }
    };

    class PvpRulesetsWorldScript : public WorldScript
    {
    public:
        PvpRulesetsWorldScript() : WorldScript("PvpRulesetsWorldScript", {
            WORLDHOOK_ON_AFTER_CONFIG_LOAD,
            WORLDHOOK_ON_STARTUP
        }) { }

        void OnAfterConfigLoad(bool reload) override
        {
            bool const wasEnabled = ConfigEnabled.load();
            ConfigEnabled.store(sConfigMgr->GetOption<bool>("PvpRulesets.Enable", false));
            WarModeXpPercent.store(sConfigMgr->GetOption<uint32>("PvpRulesets.WarMode.XpBonusPercent", 10));
            HighRiskXpPercent.store(sConfigMgr->GetOption<uint32>("PvpRulesets.HighRisk.XpBonusPercent", 15));
            ToggleCooldownMinutes.store(sConfigMgr->GetOption<uint32>("PvpRulesets.ToggleCooldownMinutes", 5));
            RecomputeRuntimeEnabled();

            if (!reload || !ConfigEnabled.load() || wasEnabled)
                return;

            if (RuntimeEnabled.load())
                LOG_INFO("module.pvp.rulesets",
                    "PvP rulesets enabled by the config reload; online characters load their mode at the "
                    "next login or .pledge command.");
            else
                LOG_INFO("module.pvp.rulesets",
                    "PvP rulesets cannot start from a config reload while the module database or table is "
                    "unavailable. Restart the worldserver after fixing it.");
        }

        void OnStartup() override
        {
            if (!ConfigEnabled.load())
            {
                LOG_INFO("module.pvp.rulesets", "PvP rulesets disabled by configuration.");
                return;
            }

            if (!GameTypeSupported())
            {
                LOG_ERROR("module.pvp.rulesets",
                    "PvP rulesets need GameType 0 (PvE); the realm reports {}. Module disabled.",
                    sWorld->getIntConfig(CONFIG_GAME_TYPE));
                return;
            }

            if (!TableReady.load())
            {
                LOG_INFO("module.pvp.rulesets",
                    "PvP rulesets remain disabled: the module database pool or `{}` table is unavailable.",
                    STATE_TABLE);
                return;
            }

            LOG_INFO("module.pvp.rulesets",
                "PvP rulesets enabled: War Mode +{}% XP, High Risk +{}% XP, pledge cooldown {} min.",
                WarModeXpPercent.load(), HighRiskXpPercent.load(), ToggleCooldownMinutes.load());
        }
    };

    class PvpRulesetsPlayerScript : public PlayerScript
    {
    public:
        PvpRulesetsPlayerScript() : PlayerScript("PvpRulesetsPlayerScript", {
            PLAYERHOOK_ON_LOGIN,
            PLAYERHOOK_ON_LOGOUT,
            PLAYERHOOK_ON_UPDATE_ZONE,
            PLAYERHOOK_ON_PLAYER_PVP_FLAG_CHANGE,
            PLAYERHOOK_ON_PLAYER_RESURRECT,
            PLAYERHOOK_ON_GIVE_EXP,
            PLAYERHOOK_ON_DELETE
        }) { }

        void OnPlayerLogin(Player* player) override
        {
            if (RuntimeEnabled.load())
                EnsureStateLoaded(player);
        }

        void OnPlayerLogout(Player* player) override
        {
            std::lock_guard<std::mutex> lock(StateMutex);
            States.erase(player->GetGUID().GetCounter());
        }

        void OnPlayerUpdateZone(Player* player, uint32 /*newZone*/, uint32 /*newArea*/) override
        {
            ApplyModePvpFlag(player);
        }

        void OnPlayerPVPFlagChange(Player* player, bool state) override
        {
            if (!state)
                ApplyModePvpFlag(player);
        }

        void OnPlayerResurrect(Player* player, float /*restorePercent*/, bool& /*applySickness*/) override
        {
            ApplyModePvpFlag(player);
        }

        void OnPlayerGiveXP(Player* player, uint32& amount, Unit* /*victim*/, uint8 /*xpSource*/) override
        {
            if (!RuntimeEnabled.load() || amount == 0 || player->IsGameMaster())
                return;

            PlayerState state;
            if (!TryGetState(player->GetGUID().GetCounter(), state) || !state.Loaded)
                return;

            uint32 const percent = PvpRulesets::XpBonusPercent(
                state.Mode, WarModeXpPercent.load(), HighRiskXpPercent.load());
            if (percent == 0)
                return;

            PvpRulesets::OutdoorXpContext context;
            context.inDungeon = player->GetMap()->IsDungeon();
            context.inBattleground = player->InBattleground();
            context.inArena = player->InArena();
            context.inBattlefield = IsBattlefieldZone(player->GetZoneId());
            context.inNoPvpArea = player->pvpInfo.IsInNoPvPArea;
            context.inSanctuary = player->IsInSanctuary();

            if (!PvpRulesets::IsOutdoorXpEligible(context))
                return;

            amount = PvpRulesets::ApplyXpBonus(amount, percent);
        }

        void OnPlayerDelete(ObjectGuid guid, uint32 /*accountId*/) override
        {
            uint32 const counter = guid.GetCounter();
            {
                std::lock_guard<std::mutex> lock(StateMutex);
                States.erase(counter);
            }

            // Gate on the table probe, not on the module being enabled, so a disabled module
            // still removes the row. Never query a table that was not found.
            if (!TableReady.load())
                return;

            auto* stmt = new PreparedStatement<PvpRulesetsDatabaseConnection>(PVP_DEL_STATE, 1);
            stmt->SetArguments(counter);
            PvpDatabase.Execute(stmt);
        }
    };
}

void Addmod_pvp_rulesetsScripts()
{
    new PledgeCommandScript();
    new PvpRulesetsDatabaseScript();
    new PvpRulesetsWorldScript();
    new PvpRulesetsPlayerScript();
}
