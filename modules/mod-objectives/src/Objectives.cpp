/*
 * mod-objectives: the shared objective engine, the Adventure Board and the Chronicle.
 *
 * One task table drives both views. Progress is event-driven and lives in memory; dirty character
 * and account rows are written in batches. Reward currencies and the gossip vendor spend path are
 * in this file as well. See specs/objectives.md and specs/rewards.md.
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Affero General Public License as published by the
 * Free Software Foundation; either version 3 of the License, or (at your
 * option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
 * or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public
 * License for more details.
 */

#include "Objectives.h"
#include "ObjectivesMath.h"

#include "Chat.h"
#include "Config.h"
#include "Creature.h"
#include "DBCStores.h"
#include "DatabaseEnv.h"
#include "GameTime.h"
#include "GossipDef.h"
#include "Item.h"
#include "Log.h"
#include "Map.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "QueryResult.h"
#include "Random.h"
#include "ScriptedGossip.h"
#include "SharedDefines.h"
#include "StringFormat.h"
#include "Unit.h"
#include "World.h"
#include "WorldPacket.h"
#include "WorldSession.h"

#include <algorithm>
#include <cstdint>
#include <limits>
#include <mutex>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
#include <utility>
#include <vector>

namespace Objectives
{
    namespace
    {
        constexpr char const* ADDON_PREFIX = "OBJ";
        constexpr char const* LOG_CATEGORY = "module.objectives";

        constexpr uint32 VENDOR_ALLIANCE_ENTRY = 910020;
        constexpr uint32 VENDOR_HORDE_ENTRY = 910021;
        constexpr uint32 VENDOR_TEXT_ID = 950200;
        constexpr uint32 OFFER_ACTION_BASE = 1000;

        constexpr uint8 MAX_DAILY_SLOTS = 7;
        constexpr uint8 MAX_WEEKLY_SLOTS = 1;
        constexpr uint8 MAX_CHRONICLE_SLOTS = 6;

        constexpr std::size_t FLUSH_BATCH = 100;
        constexpr uint32 MAX_FLUSH_BATCHES_PER_TICK = 100;

        enum TaskType : uint8
        {
            TASK_KILL_CREATURE = 1,
            TASK_COMPLETE_QUEST = 2,
            TASK_KILL_BOSS = 3,
            TASK_WIN_BATTLEGROUND = 4
        };

        enum TaskScope : uint8
        {
            SCOPE_DAILY = 1,
            SCOPE_WEEKLY = 2,
            SCOPE_CHRONICLE = 3
        };

        enum Currency : uint8
        {
            CURRENCY_MARKS = 1,
            CURRENCY_COINS = 2,
            CURRENCY_COMMENDATIONS = 3
        };

        struct Config
        {
            bool enabled = true;
            uint32 era = 0;
            uint32 dailySlots = 5;
            uint32 weeklySlots = 1;
            uint32 chronicleSlots = 3;
            uint32 rerollCost = 2000;
            uint32 flushIntervalMs = 20000;
        };

        struct TaskDef
        {
            uint32 id = 0;
            std::string name;
            uint8 type = 0;
            uint8 scope = 0;
            uint8 era = 0;
            uint32 minLevel = 1;
            uint32 maxLevel = 0;
            uint8 faction = 0;
            uint32 zoneId = 0;
            uint32 targetId = 0;
            uint32 required = 0;
            uint32 rewardMarks = 0;
            uint32 rewardCoins = 0;
            uint32 rewardCommendations = 0;
            uint32 weight = 1;
        };

        struct OfferDef
        {
            uint32 id = 0;
            std::string name;
            uint8 category = 0;
            uint8 currency = 0;
            uint32 cost = 0;
            uint32 itemId = 0;
            uint32 itemCount = 1;
            uint32 minLevel = 1;
            uint32 maxLevel = 0;
            uint8 faction = 0;
            uint8 era = 0;
            uint32 sort = 0;
        };

        struct TaskState
        {
            uint32 taskId = 0;
            uint32 progress = 0;
            bool completed = false;
        };

        struct CharacterState
        {
            uint32 guid = 0;
            uint32 accountId = 0;
            uint32 dailyPeriod = 0;
            uint32 weeklyPeriod = 0;
            uint32 focusZone = 0;
            uint32 rerolls = 0;
            bool focusChanged = false;
            std::vector<TaskState> daily;
            std::vector<TaskState> weekly;
            uint32 coins = 0;
            uint32 commendations = 0;
            bool dirty = false;
            float requestTokens = 8.0f;
            uint64 requestMs = 0;
        };

        struct AccountState
        {
            uint32 accountId = 0;
            uint32 period = 0;
            uint32 marks = 0;
            std::vector<TaskState> chronicle;
            bool dirty = false;
        };

        struct Completion
        {
            std::string name;
            uint32 marks = 0;
            uint32 coins = 0;
            uint32 commendations = 0;
        };

        Config sConfig;
        std::mutex sMutex;
        std::mutex sCurrencyWriteMutex;

        std::vector<TaskDef> sTasks;
        std::unordered_map<uint32, std::size_t> sTaskIndex;
        std::vector<OfferDef> sOffers;

        std::unordered_map<uint32, CharacterState> sCharacters;
        std::unordered_map<uint32, AccountState> sAccounts;
        std::unordered_map<uint32, uint32> sAccountRefs;
        std::unordered_set<uint32> sDirtyCharacters;
        std::unordered_set<uint32> sDirtyAccounts;

        bool sSchemaReady = false;
        bool sDefinitionsReady = false;
        uint32 sFlushTimer = 0;

        uint32 DailyReset()
        {
            return uint32(sWorld->GetNextDailyQuestsResetTime().count());
        }

        uint32 WeeklyReset()
        {
            return uint32(sWorld->GetNextWeeklyQuestsResetTime().count());
        }

        bool CharacterTableExists(std::string const& name)
        {
            QueryResult result = CharacterDatabase.Query(Acore::StringFormat(
                "SELECT 1 FROM `information_schema`.`tables` "
                "WHERE `table_schema` = DATABASE() AND `table_name` = '{}' LIMIT 1", name));
            return result && result->GetRowCount() > 0;
        }

        bool WorldTableExists(std::string const& name)
        {
            QueryResult result = WorldDatabase.Query(Acore::StringFormat(
                "SELECT 1 FROM `information_schema`.`tables` "
                "WHERE `table_schema` = DATABASE() AND `table_name` = '{}' LIMIT 1", name));
            return result && result->GetRowCount() > 0;
        }

        std::string Sanitize(std::string_view text, std::size_t limit = 96)
        {
            std::string out;
            out.reserve(std::min<std::size_t>(text.size(), limit));
            for (char c : text)
            {
                if (out.size() >= limit)
                    break;
                if (c == ':' || c == ',' || c == ';' || c == '\n' || c == '\r' || c == '\t')
                    out += ' ';
                else
                    out += c;
            }
            return out;
        }

        std::string SanitizeRequest(std::string_view text)
        {
            std::string out;
            for (char c : text)
            {
                if (c < '0' || c > '9' || out.size() >= 10)
                    break;
                out += c;
            }
            return out.empty() ? "0" : out;
        }

        uint8 FactionOf(Player* player)
        {
            return player->GetTeamId() == TEAM_ALLIANCE ? 1 : 2;
        }

        char const* CurrencyName(uint8 currency)
        {
            switch (currency)
            {
                case CURRENCY_MARKS:
                    return "Adventure Marks";
                case CURRENCY_COINS:
                    return "Mythic Coins";
                case CURRENCY_COMMENDATIONS:
                    return "Raider's Commendations";
                default:
                    return "currency";
            }
        }

        std::string ZoneName(uint32 zoneId)
        {
            if (!zoneId)
                return "Any zone";
            if (AreaTableEntry const* area = sAreaTableStore.LookupEntry(zoneId))
            {
                char const* name = area->area_name[sWorld->GetDefaultDbcLocale()];
                if (name && *name)
                    return Sanitize(name, 48);
            }
            return "Unknown zone";
        }

        TaskDef const* FindTask(uint32 taskId)
        {
            auto itr = sTaskIndex.find(taskId);
            if (itr == sTaskIndex.end())
                return nullptr;
            return &sTasks[itr->second];
        }

        OfferDef const* FindOffer(uint32 offerId)
        {
            for (OfferDef const& offer : sOffers)
                if (offer.id == offerId)
                    return &offer;
            return nullptr;
        }

        void AddClamped(uint32& value, uint32 add)
        {
            uint64 const sum = uint64(value) + uint64(add);
            if (sum > std::numeric_limits<uint32>::max())
            {
                value = std::numeric_limits<uint32>::max();
                LOG_WARN(LOG_CATEGORY, "currency balance saturated at {}", value);
                return;
            }
            value = uint32(sum);
        }

        bool Eligible(TaskDef const& task, uint8 scope, uint32 level, uint8 faction)
        {
            if (task.scope != scope || task.type < TASK_KILL_CREATURE || task.type > TASK_WIN_BATTLEGROUND)
                return false;
            if (task.era > sConfig.era)
                return false;
            if (level < task.minLevel || (task.maxLevel != 0 && level > task.maxLevel))
                return false;
            if (task.faction != 0 && task.faction != faction)
                return false;
            return task.required != 0;
        }

        std::vector<TaskDef const*> BuildPool(uint8 scope, uint32 level, uint8 faction)
        {
            std::vector<TaskDef const*> pool;
            for (TaskDef const& task : sTasks)
                if (Eligible(task, scope, level, faction))
                    pool.push_back(&task);
            return pool;
        }

        // The chronicle is account-wide. It ignores level and faction so a low-level alt cannot seed
        // a weaker weekly pool for the whole account; era and scope are still enforced.
        std::vector<TaskDef const*> BuildChroniclePool()
        {
            std::vector<TaskDef const*> pool;
            for (TaskDef const& task : sTasks)
            {
                if (task.scope != SCOPE_CHRONICLE || task.era > sConfig.era)
                    continue;
                if (task.type < TASK_KILL_CREATURE || task.type > TASK_WIN_BATTLEGROUND)
                    continue;
                if (task.required == 0)
                    continue;
                pool.push_back(&task);
            }
            return pool;
        }

        TaskDef const* PickWeighted(std::vector<TaskDef const*>& pool)
        {
            if (pool.empty())
                return nullptr;

            uint64 total = 0;
            for (TaskDef const* task : pool)
                total += std::max<uint32>(1, task->weight);

            uint64 roll = urand(0, uint32(std::min<uint64>(total, std::numeric_limits<uint32>::max()) - 1));
            for (std::size_t i = 0; i < pool.size(); ++i)
            {
                uint64 const weight = std::max<uint32>(1, pool[i]->weight);
                if (roll < weight)
                {
                    TaskDef const* picked = pool[i];
                    pool.erase(pool.begin() + i);
                    return picked;
                }
                roll -= weight;
            }

            TaskDef const* picked = pool.back();
            pool.pop_back();
            return picked;
        }

        uint32 DefaultFocus(std::vector<TaskDef const*> const& pool, uint32 currentZone)
        {
            if (currentZone)
            {
                for (TaskDef const* task : pool)
                    if (task->zoneId == currentZone)
                        return currentZone;
            }

            std::unordered_map<uint32, uint32> counts;
            for (TaskDef const* task : pool)
                if (task->zoneId)
                    ++counts[task->zoneId];

            uint32 bestZone = 0;
            uint32 bestCount = 0;
            for (auto const& entry : counts)
            {
                if (entry.second > bestCount
                    || (entry.second == bestCount && (bestZone == 0 || entry.first < bestZone)))
                {
                    bestZone = entry.first;
                    bestCount = entry.second;
                }
            }
            return bestZone;
        }

        int FocusPriority(TaskDef const& task, uint32 focusZone)
        {
            if (focusZone != 0 && task.zoneId == focusZone)
                return 0;
            if (task.zoneId == 0)
                return 1;
            return 2;
        }

        TaskDef const* PickForFocus(std::vector<TaskDef const*>& pool, uint32 focusZone)
        {
            int bestPriority = 3;
            for (TaskDef const* task : pool)
                bestPriority = std::min(bestPriority, FocusPriority(*task, focusZone));
            if (bestPriority == 3)
                return nullptr;

            std::vector<TaskDef const*> candidates;
            for (TaskDef const* task : pool)
                if (FocusPriority(*task, focusZone) == bestPriority)
                    candidates.push_back(task);

            TaskDef const* picked = PickWeighted(candidates);
            if (!picked)
                return nullptr;

            for (auto itr = pool.begin(); itr != pool.end(); ++itr)
            {
                if (*itr == picked)
                {
                    pool.erase(itr);
                    break;
                }
            }
            return picked;
        }

        bool IsAssigned(CharacterState const& character, uint32 taskId)
        {
            for (TaskState const& state : character.daily)
                if (state.taskId == taskId)
                    return true;
            for (TaskState const& state : character.weekly)
                if (state.taskId == taskId)
                    return true;
            return false;
        }

        bool PoolHasZone(std::vector<TaskDef const*> const& pool, uint32 zoneId)
        {
            for (TaskDef const* task : pool)
                if (task->zoneId == zoneId)
                    return true;
            return false;
        }

        void GenerateDaily(CharacterState& character, Player* player, uint32 period)
        {
            std::vector<TaskDef const*> pool = BuildPool(SCOPE_DAILY, player->GetLevel(), FactionOf(player));
            character.daily.assign(sConfig.dailySlots, TaskState{});
            character.dailyPeriod = period;
            character.rerolls = 0;
            character.focusChanged = false;
            character.dirty = true;

            if (pool.empty())
            {
                character.focusZone = 0;
                return;
            }

            if (character.focusZone == 0 || !PoolHasZone(pool, character.focusZone))
                character.focusZone = DefaultFocus(pool, player->GetZoneId());

            for (TaskState& state : character.daily)
            {
                TaskDef const* task = PickForFocus(pool, character.focusZone);
                if (!task)
                    break;
                state.taskId = task->id;
            }
        }

        void GenerateWeekly(CharacterState& character, Player* player, uint32 period)
        {
            std::vector<TaskDef const*> pool = BuildPool(SCOPE_WEEKLY, player->GetLevel(), FactionOf(player));
            character.weekly.assign(sConfig.weeklySlots, TaskState{});
            character.weeklyPeriod = period;
            character.dirty = true;

            for (TaskState& state : character.weekly)
            {
                TaskDef const* task = PickWeighted(pool);
                if (!task)
                    break;
                state.taskId = task->id;
            }
        }

        void GenerateChronicle(AccountState& account, uint32 period)
        {
            std::vector<TaskDef const*> pool = BuildChroniclePool();
            account.chronicle.assign(sConfig.chronicleSlots, TaskState{});
            account.period = period;
            account.dirty = true;

            for (TaskState& state : account.chronicle)
            {
                TaskDef const* task = PickWeighted(pool);
                if (!task)
                    break;
                state.taskId = task->id;
            }
        }

        void EnsureCharacterBoard(CharacterState& character, Player* player)
        {
            uint32 const now = uint32(GameTime::GetGameTime().count());
            uint32 const daily = DailyReset();
            uint32 const weekly = WeeklyReset();

            if (Math::ResetDue(character.dailyPeriod, now) || character.dailyPeriod != daily
                || character.daily.size() != sConfig.dailySlots)
                GenerateDaily(character, player, daily);
            if (Math::ResetDue(character.weeklyPeriod, now) || character.weeklyPeriod != weekly
                || character.weekly.size() != sConfig.weeklySlots)
                GenerateWeekly(character, player, weekly);

            if (character.dirty)
                sDirtyCharacters.insert(character.guid);
        }

        void EnsureChronicle(AccountState& account)
        {
            uint32 const now = uint32(GameTime::GetGameTime().count());
            uint32 const weekly = WeeklyReset();
            if (Math::ResetDue(account.period, now) || account.period != weekly
                || account.chronicle.size() != sConfig.chronicleSlots)
            {
                GenerateChronicle(account, weekly);
            }
            else
            {
                bool hasEmpty = false;
                for (TaskState const& state : account.chronicle)
                    if (state.taskId == 0)
                        hasEmpty = true;

                if (hasEmpty)
                {
                    std::vector<TaskDef const*> pool = BuildChroniclePool();
                    for (TaskState const& state : account.chronicle)
                        pool.erase(std::remove_if(pool.begin(), pool.end(),
                            [&state](TaskDef const* task) { return task->id == state.taskId; }),
                            pool.end());

                    bool changed = false;
                    for (TaskState& state : account.chronicle)
                    {
                        if (state.taskId != 0)
                            continue;
                        TaskDef const* task = PickWeighted(pool);
                        if (!task)
                            break;
                        state.taskId = task->id;
                        changed = true;
                    }

                    if (changed)
                        account.dirty = true;
                }
            }

            if (account.dirty)
                sDirtyAccounts.insert(account.accountId);
        }

        bool AdvanceTask(TaskState& state, TaskDef const& task)
        {
            if (state.completed || task.required == 0)
                return false;

            uint32 const next = Math::ApplyProgress(state.progress, 1, task.required);
            if (next == state.progress)
                return false;

            state.progress = next;
            if (Math::IsComplete(state.progress, task.required))
                state.completed = true;
            return true;
        }

        bool PersistCharacterCurrency(uint32 guid)
        {
            std::lock_guard<std::mutex> writeLock(sCurrencyWriteMutex);

            uint32 coins = 0;
            uint32 commendations = 0;
            {
                std::lock_guard<std::mutex> lock(sMutex);
                auto itr = sCharacters.find(guid);
                if (itr == sCharacters.end())
                    return false;
                coins = itr->second.coins;
                commendations = itr->second.commendations;
            }

            if (!CharacterDatabase.DirectExecute(Acore::StringFormat(
                "REPLACE INTO `mod_objectives_character_currency` "
                "(`guid`,`mythic_coins`,`commendations`) VALUES ({},{},{});",
                guid, coins, commendations)))
            {
                LOG_ERROR(LOG_CATEGORY, "currency write failed for character {}", guid);
                return false;
            }
            return true;
        }

        bool PersistAccountCurrency(uint32 accountId)
        {
            std::lock_guard<std::mutex> writeLock(sCurrencyWriteMutex);

            uint32 marks = 0;
            {
                std::lock_guard<std::mutex> lock(sMutex);
                auto itr = sAccounts.find(accountId);
                if (itr == sAccounts.end())
                    return false;
                marks = itr->second.marks;
            }

            if (!CharacterDatabase.DirectExecute(Acore::StringFormat(
                "REPLACE INTO `mod_objectives_account_currency` "
                "(`account_id`,`adventure_marks`) VALUES ({},{});",
                accountId, marks)))
            {
                LOG_ERROR(LOG_CATEGORY, "currency write failed for account {}", accountId);
                return false;
            }
            return true;
        }

        void AwardTask(TaskDef const& task, CharacterState& character, AccountState* account,
            std::vector<Completion>& completions)
        {
            if (account)
                AddClamped(account->marks, task.rewardMarks);
            AddClamped(character.coins, task.rewardCoins);
            AddClamped(character.commendations, task.rewardCommendations);

            LOG_DEBUG(LOG_CATEGORY, "task {} completed by character {}", task.id, character.guid);
            completions.push_back(Completion{ task.name, task.rewardMarks, task.rewardCoins,
                task.rewardCommendations });
        }

        void SendPayload(Player* player, std::string const& payload)
        {
            if (!player || !player->GetSession())
                return;

            std::string const full = std::string(ADDON_PREFIX) + "\t" + payload;
            WorldPacket data;
            ChatHandler::BuildChatPacket(data, CHAT_MSG_WHISPER, LANG_ADDON, player, player, full);
            player->GetSession()->SendPacket(&data);
        }

        void SendError(Player* player, std::string const& request, std::string_view reason)
        {
            SendPayload(player, "ERR:" + request + ":" + std::string(reason));
        }

        void SendCompletionLines(Player* player, std::vector<Completion> const& completions)
        {
            if (!player || !player->GetSession())
                return;

            ChatHandler handler(player->GetSession());
            for (Completion const& completion : completions)
            {
                std::string message = Acore::StringFormat("Objective complete: {}.", completion.name);
                if (completion.marks)
                    message += Acore::StringFormat(" +{} Adventure Marks", completion.marks);
                if (completion.coins)
                    message += Acore::StringFormat(" +{} Mythic Coins", completion.coins);
                if (completion.commendations)
                    message += Acore::StringFormat(" +{} Raider's Commendations", completion.commendations);
                handler.SendSysMessage(message);
            }
        }

        std::string TaskRow(std::string_view prefix, uint32 slot, uint8 scope, TaskState const& state)
        {
            TaskDef const* task = FindTask(state.taskId);
            if (!task)
                return Acore::StringFormat("{}:{},{},0,0,0,0,0,0,0,0,0,Empty slot", prefix, slot, scope);

            return Acore::StringFormat("{}:{},{},{},{},{},{},{},{},{},{},{},{}", prefix, slot, scope,
                task->id, task->type, task->required, state.progress, state.completed ? 1 : 0,
                task->rewardMarks, task->rewardCoins, task->rewardCommendations, task->zoneId,
                Sanitize(task->name));
        }

        // The chronicle row has no board scope field; its shape is slot + task data.
        std::string ChronicleRow(uint32 slot, TaskState const& state)
        {
            TaskDef const* task = FindTask(state.taskId);
            if (!task)
                return Acore::StringFormat("CD:{},0,0,0,0,0,0,0,0,0,Empty slot", slot);

            return Acore::StringFormat("CD:{},{},{},{},{},{},{},{},{},{},{}", slot, task->id, task->type,
                task->required, state.progress, state.completed ? 1 : 0, task->rewardMarks,
                task->rewardCoins, task->rewardCommendations, task->zoneId, Sanitize(task->name));
        }

        void SendBoard(Player* player, std::string const& rawRequest)
        {
            std::string const request = SanitizeRequest(rawRequest);
            std::vector<std::string> messages;
            std::string error;

            {
                std::lock_guard<std::mutex> lock(sMutex);
                auto itr = sCharacters.find(player->GetGUID().GetCounter());
                if (itr == sCharacters.end())
                {
                    error = "not_loaded";
                }
                else
                {
                    CharacterState& character = itr->second;
                    EnsureCharacterBoard(character, player);
                    AccountState* account = nullptr;
                    auto accountItr = sAccounts.find(character.accountId);
                    if (accountItr != sAccounts.end())
                        account = &accountItr->second;

                    uint32 const marks = account ? account->marks : 0;
                    uint64 const nextReroll = Math::RerollCost(sConfig.rerollCost, character.rerolls);
                    messages.push_back(Acore::StringFormat(
                        "BR:{}:{}:{}:{}:{}:{}:{}:{}", request, character.focusZone,
                        ZoneName(character.focusZone), marks, character.coins,
                        character.commendations, nextReroll, sConfig.dailySlots));

                    for (std::size_t i = 0; i < character.daily.size(); ++i)
                        messages.push_back(TaskRow("BD", uint32(i), SCOPE_DAILY, character.daily[i]));
                    for (std::size_t i = 0; i < character.weekly.size(); ++i)
                        messages.push_back(TaskRow("BD", uint32(i), SCOPE_WEEKLY, character.weekly[i]));
                    messages.push_back("BE");
                }
            }

            if (!error.empty())
            {
                SendError(player, request, error);
                return;
            }
            for (std::string const& message : messages)
                SendPayload(player, message);
        }

        void SendChronicle(Player* player, std::string const& rawRequest)
        {
            std::string const request = SanitizeRequest(rawRequest);
            std::vector<std::string> messages;
            std::string error;

            {
                std::lock_guard<std::mutex> lock(sMutex);
                auto itr = sCharacters.find(player->GetGUID().GetCounter());
                if (itr == sCharacters.end())
                {
                    error = "not_loaded";
                }
                else
                {
                    CharacterState& character = itr->second;
                    auto accountItr = sAccounts.find(character.accountId);
                    if (accountItr == sAccounts.end())
                    {
                        error = "not_loaded";
                    }
                    else
                    {
                        AccountState& account = accountItr->second;
                        EnsureChronicle(account);
                        messages.push_back(Acore::StringFormat("CR:{}:{}:{}:{}", request, account.marks,
                            character.coins, character.commendations));
                        for (std::size_t i = 0; i < account.chronicle.size(); ++i)
                            messages.push_back(ChronicleRow(uint32(i), account.chronicle[i]));
                        messages.push_back("CE");
                    }
                }
            }

            if (!error.empty())
            {
                SendError(player, request, error);
                return;
            }
            for (std::string const& message : messages)
                SendPayload(player, message);
        }

        bool ParseUInt(std::string_view text, uint32& value)
        {
            if (text.empty())
                return false;
            uint64 result = 0;
            for (char c : text)
            {
                if (c < '0' || c > '9')
                    return false;
                result = result * 10 + uint64(c - '0');
                if (result > std::numeric_limits<uint32>::max())
                    return false;
            }
            value = uint32(result);
            return true;
        }

        void HandleReroll(Player* player, std::string const& request, std::string_view slotText)
        {
            uint32 slot = 0;
            if (!ParseUInt(slotText, slot))
            {
                SendPayload(player, Acore::StringFormat("RR:{}:err:bad_slot", request));
                return;
            }

            bool ok = false;
            std::string error;
            uint32 cost = 0;

            {
                std::lock_guard<std::mutex> lock(sMutex);
                auto itr = sCharacters.find(player->GetGUID().GetCounter());
                if (itr == sCharacters.end())
                {
                    error = "not_loaded";
                }
                else
                {
                    CharacterState& character = itr->second;
                    EnsureCharacterBoard(character, player);

                    if (slot >= character.daily.size() || character.daily[slot].taskId == 0)
                        error = "empty";
                    else if (character.daily[slot].completed)
                        error = "completed";
                    else
                    {
                        uint64 const rawCost = Math::RerollCost(sConfig.rerollCost, character.rerolls);
                        if (rawCost > std::numeric_limits<int32>::max() || uint64(player->GetMoney()) < rawCost)
                        {
                            error = "gold";
                        }
                        else
                        {
                            std::vector<TaskDef const*> pool =
                                BuildPool(SCOPE_DAILY, player->GetLevel(), FactionOf(player));
                            pool.erase(std::remove_if(pool.begin(), pool.end(),
                                [&character](TaskDef const* task) { return IsAssigned(character, task->id); }),
                                pool.end());

                            TaskDef const* task = PickForFocus(pool, character.focusZone);
                            if (!task)
                                error = "no_task";
                            else if (!player->ModifyMoney(-int32(rawCost)))
                                error = "gold";
                            else
                            {
                                cost = uint32(rawCost);
                                ++character.rerolls;
                                character.daily[slot] = TaskState{ task->id, 0, false };
                                character.dirty = true;
                                sDirtyCharacters.insert(character.guid);
                                ok = true;
                            }
                        }
                    }
                }
            }

            if (!ok)
            {
                SendPayload(player, Acore::StringFormat("RR:{}:err:{}", request, error));
                return;
            }

            SendPayload(player, Acore::StringFormat("RR:{}:ok:{}", request, cost));
            SendBoard(player, request);
        }

        void HandleFocus(Player* player, std::string const& request)
        {
            bool ok = false;
            std::string error;
            uint32 newFocus = 0;

            {
                std::lock_guard<std::mutex> lock(sMutex);
                auto itr = sCharacters.find(player->GetGUID().GetCounter());
                if (itr == sCharacters.end())
                {
                    error = "not_loaded";
                }
                else
                {
                    CharacterState& character = itr->second;
                    EnsureCharacterBoard(character, player);

                    std::vector<TaskDef const*> dailyPool =
                        BuildPool(SCOPE_DAILY, player->GetLevel(), FactionOf(player));
                    std::vector<uint32> zones;
                    for (TaskDef const* task : dailyPool)
                        if (task->zoneId &&
                            std::find(zones.begin(), zones.end(), task->zoneId) == zones.end())
                            zones.push_back(task->zoneId);
                    std::sort(zones.begin(), zones.end());

                    if (character.focusChanged)
                        error = "focus_used";
                    else if (zones.size() < 2)
                        error = "no_focus";
                    else
                    {
                        auto current = std::find(zones.begin(), zones.end(), character.focusZone);
                        std::size_t const nextIndex = current == zones.end()
                            ? 0
                            : (std::size_t(current - zones.begin()) + 1) % zones.size();
                        newFocus = zones[nextIndex];

                        std::vector<TaskDef const*> pool;
                        for (TaskDef const* task : dailyPool)
                            if (task->zoneId == newFocus || task->zoneId == 0)
                                pool.push_back(task);

                        for (TaskState const& state : character.daily)
                            if (state.completed)
                                pool.erase(std::remove_if(pool.begin(), pool.end(),
                                    [&state](TaskDef const* task) { return task->id == state.taskId; }),
                                    pool.end());
                        for (TaskState const& state : character.weekly)
                            pool.erase(std::remove_if(pool.begin(), pool.end(),
                                [&state](TaskDef const* task) { return task->id == state.taskId; }),
                                pool.end());

                        if (pool.empty())
                        {
                            error = "no_task";
                        }
                        else
                        {
                            for (TaskState& state : character.daily)
                            {
                                if (state.completed)
                                    continue;
                                TaskDef const* task = PickForFocus(pool, newFocus);
                                if (!task)
                                {
                                    state = TaskState{};
                                    break;
                                }
                                state = TaskState{ task->id, 0, false };
                            }

                            character.focusZone = newFocus;
                            character.focusChanged = true;
                            character.dirty = true;
                            sDirtyCharacters.insert(character.guid);
                            ok = true;
                        }
                    }
                }
            }

            if (!ok)
            {
                SendPayload(player, Acore::StringFormat("FR:{}:err:{}", request, error));
                return;
            }

            SendPayload(player, Acore::StringFormat("FR:{}:ok:{}", request, ZoneName(newFocus)));
            SendBoard(player, request);
        }

        void HandleAddonMessage(Player* player, std::string_view payload)
        {
            std::size_t const first = payload.find(':');
            std::string const command(payload.substr(0, first));
            std::string rest(first == std::string_view::npos ? std::string_view{} : payload.substr(first + 1));

            std::size_t const second = rest.find(':');
            std::string const request = SanitizeRequest(second == std::string::npos ? rest : rest.substr(0, second));
            std::string const argument = second == std::string::npos ? "" : rest.substr(second + 1);

            if (command == "B")
                SendBoard(player, request);
            else if (command == "C")
                SendChronicle(player, request);
            else if (command == "F")
                HandleFocus(player, request);
            else if (command == "R")
                HandleReroll(player, request, argument);
            else
                SendError(player, request, "unknown");
        }

        bool ConsumeRequest(Player* player)
        {
            std::lock_guard<std::mutex> lock(sMutex);
            auto itr = sCharacters.find(player->GetGUID().GetCounter());
            if (itr == sCharacters.end())
                return true;

            CharacterState& character = itr->second;
            uint64 const now = uint64(GameTime::GetGameTimeMS().count());
            if (character.requestMs == 0)
                character.requestMs = now;
            uint64 const elapsed = now >= character.requestMs ? now - character.requestMs : 0;
            character.requestTokens = std::min(8.0f, character.requestTokens + float(elapsed) / 1000.0f * 4.0f);
            character.requestMs = now;

            if (character.requestTokens < 1.0f)
                return false;
            character.requestTokens -= 1.0f;
            return true;
        }

        void QueueCharacterFlush(CharacterState const& character, std::vector<std::string>& sql)
        {
            sql.push_back(Acore::StringFormat(
                "DELETE FROM `mod_objectives_board` WHERE `guid` = {};", character.guid));

            std::string values;
            auto addRow = [&values, &character](TaskState const& state, uint8 scope, uint32 slot, uint32 period)
            {
                if (!state.taskId)
                    return;
                if (!values.empty())
                    values += ',';
                values += Acore::StringFormat("({},{},{},{},{},{},{})", character.guid, scope, slot,
                    state.taskId, period, state.progress, state.completed ? 1 : 0);
            };

            for (std::size_t i = 0; i < character.daily.size(); ++i)
                addRow(character.daily[i], SCOPE_DAILY, uint32(i), character.dailyPeriod);
            for (std::size_t i = 0; i < character.weekly.size(); ++i)
                addRow(character.weekly[i], SCOPE_WEEKLY, uint32(i), character.weeklyPeriod);

            if (!values.empty())
                sql.push_back("INSERT INTO `mod_objectives_board` "
                    "(`guid`,`scope`,`slot`,`task_id`,`period_key`,`progress`,`completed`) VALUES "
                    + values + ";");

            sql.push_back(Acore::StringFormat(
                "REPLACE INTO `mod_objectives_focus` "
                "(`guid`,`period_key`,`zone_id`,`rerolls`,`focus_changed`) VALUES ({},{},{},{},{});",
                character.guid, character.dailyPeriod, character.focusZone, character.rerolls,
                character.focusChanged ? 1 : 0));
        }

        void QueueAccountFlush(AccountState const& account, std::vector<std::string>& sql)
        {
            sql.push_back(Acore::StringFormat(
                "DELETE FROM `mod_objectives_chronicle` WHERE `account_id` = {};", account.accountId));

            std::string values;
            for (std::size_t i = 0; i < account.chronicle.size(); ++i)
            {
                TaskState const& state = account.chronicle[i];
                if (!state.taskId)
                    continue;
                if (!values.empty())
                    values += ',';
                values += Acore::StringFormat("({},{},{},{},{},{})", account.accountId, i, state.taskId,
                    account.period, state.progress, state.completed ? 1 : 0);
            }

            if (!values.empty())
                sql.push_back("INSERT INTO `mod_objectives_chronicle` "
                    "(`account_id`,`slot`,`task_id`,`period_key`,`progress`,`completed`) VALUES "
                    + values + ";");
        }

        void CommitStatements(std::vector<std::string> const& sql)
        {
            if (sql.empty())
                return;

            CharacterDatabaseTransaction trans = CharacterDatabase.BeginTransaction();
            for (std::string const& statement : sql)
                trans->Append(statement);
            CharacterDatabase.CommitTransaction(trans);
        }

        bool FlushDirtyBatch()
        {
            std::vector<std::string> sql;
            std::size_t charactersWritten = 0;
            std::size_t accountsWritten = 0;
            bool madeProgress = false;

            {
                std::lock_guard<std::mutex> lock(sMutex);

                std::vector<uint32> characters;
                characters.reserve(std::min(FLUSH_BATCH, sDirtyCharacters.size()));
                for (uint32 guid : sDirtyCharacters)
                {
                    characters.push_back(guid);
                    if (characters.size() >= FLUSH_BATCH)
                        break;
                }
                for (uint32 guid : characters)
                {
                    auto itr = sCharacters.find(guid);
                    if (itr != sCharacters.end())
                    {
                        QueueCharacterFlush(itr->second, sql);
                        itr->second.dirty = false;
                        ++charactersWritten;
                    }
                    sDirtyCharacters.erase(guid);
                    madeProgress = true;
                }

                std::vector<uint32> accounts;
                accounts.reserve(std::min(FLUSH_BATCH, sDirtyAccounts.size()));
                for (uint32 accountId : sDirtyAccounts)
                {
                    accounts.push_back(accountId);
                    if (accounts.size() >= FLUSH_BATCH)
                        break;
                }
                for (uint32 accountId : accounts)
                {
                    auto itr = sAccounts.find(accountId);
                    if (itr != sAccounts.end())
                    {
                        QueueAccountFlush(itr->second, sql);
                        itr->second.dirty = false;
                        ++accountsWritten;
                    }
                    sDirtyAccounts.erase(accountId);
                    madeProgress = true;
                }
            }

            if (!sql.empty())
                LOG_DEBUG(LOG_CATEGORY, "flushed {} characters and {} accounts", charactersWritten,
                    accountsWritten);

            CommitStatements(sql);
            return madeProgress;
        }

        void FlushDirty(uint32 maxBatches)
        {
            uint32 batches = 0;
            while (batches < maxBatches && FlushDirtyBatch())
                ++batches;
        }

        void LoadTasks()
        {
            sTasks.clear();
            sTaskIndex.clear();

            if (!WorldTableExists("mod_objectives_task"))
            {
                LOG_ERROR(LOG_CATEGORY, "world table mod_objectives_task is missing; no tasks loaded");
                return;
            }

            QueryResult result = WorldDatabase.Query(
                "SELECT `id`,`name`,`task_type`,`scope`,`era`,`min_level`,`max_level`,`faction`,"
                "`zone_id`,`target_id`,`required_count`,`reward_marks`,`reward_coins`,"
                "`reward_commendations`,`weight` FROM `mod_objectives_task` "
                "WHERE `enabled` = 1 ORDER BY `id`");
            if (!result || result->GetRowCount() == 0)
                return;

            do
            {
                Field* fields = result->Fetch();
                TaskDef task;
                task.id = fields[0].Get<uint32>();
                task.name = fields[1].Get<std::string>();
                task.type = fields[2].Get<uint8>();
                task.scope = fields[3].Get<uint8>();
                task.era = fields[4].Get<uint8>();
                task.minLevel = fields[5].Get<uint32>();
                task.maxLevel = fields[6].Get<uint32>();
                task.faction = fields[7].Get<uint8>();
                task.zoneId = fields[8].Get<uint32>();
                task.targetId = fields[9].Get<uint32>();
                task.required = fields[10].Get<uint32>();
                task.rewardMarks = fields[11].Get<uint32>();
                task.rewardCoins = fields[12].Get<uint32>();
                task.rewardCommendations = fields[13].Get<uint32>();
                task.weight = std::max<uint32>(1, fields[14].Get<uint32>());

                bool valid = task.id != 0 && !task.name.empty() && task.required != 0
                    && task.type >= TASK_KILL_CREATURE && task.type <= TASK_WIN_BATTLEGROUND
                    && task.scope >= SCOPE_DAILY && task.scope <= SCOPE_CHRONICLE
                    && task.era <= 2 && task.faction <= 2 && task.minLevel >= 1
                    && (task.maxLevel == 0 || task.maxLevel >= task.minLevel);

                if (!valid)
                {
                    LOG_ERROR(LOG_CATEGORY, "rejected task {}: invalid type, scope, era, level or count", task.id);
                    continue;
                }

                sTaskIndex[task.id] = sTasks.size();
                sTasks.push_back(std::move(task));
            } while (result->NextRow());
        }

        void LoadOffers()
        {
            sOffers.clear();

            if (!WorldTableExists("mod_objectives_offer"))
            {
                LOG_ERROR(LOG_CATEGORY, "world table mod_objectives_offer is missing; no offers loaded");
                return;
            }

            QueryResult result = WorldDatabase.Query(
                "SELECT `id`,`name`,`category`,`currency`,`cost`,`item_id`,`item_count`,"
                "`min_level`,`max_level`,`faction`,`era`,`sort` FROM `mod_objectives_offer` "
                "WHERE `enabled` = 1 ORDER BY `category`,`sort`,`id`");
            if (!result || result->GetRowCount() == 0)
                return;

            do
            {
                Field* fields = result->Fetch();
                OfferDef offer;
                offer.id = fields[0].Get<uint32>();
                offer.name = fields[1].Get<std::string>();
                offer.category = fields[2].Get<uint8>();
                offer.currency = fields[3].Get<uint8>();
                offer.cost = fields[4].Get<uint32>();
                offer.itemId = fields[5].Get<uint32>();
                offer.itemCount = fields[6].Get<uint32>();
                offer.minLevel = fields[7].Get<uint32>();
                offer.maxLevel = fields[8].Get<uint32>();
                offer.faction = fields[9].Get<uint8>();
                offer.era = fields[10].Get<uint8>();
                offer.sort = fields[11].Get<uint32>();

                bool valid = offer.id != 0 && !offer.name.empty() && offer.cost != 0
                    && offer.itemCount != 0 && offer.currency >= CURRENCY_MARKS
                    && offer.currency <= CURRENCY_COMMENDATIONS && offer.category >= 1
                    && offer.category <= 3 && offer.era <= 2 && offer.faction <= 2
                    && offer.minLevel >= 1 && (offer.maxLevel == 0 || offer.maxLevel >= offer.minLevel)
                    && sObjectMgr->GetItemTemplate(offer.itemId) != nullptr;

                if (!valid)
                {
                    LOG_ERROR(LOG_CATEGORY, "rejected offer {}: invalid data or missing item {}", offer.id,
                        offer.itemId);
                    continue;
                }

                sOffers.push_back(std::move(offer));
            } while (result->NextRow());
        }

        bool LoadAccount(uint32 accountId)
        {
            std::lock_guard<std::mutex> lock(sMutex);
            if (sAccounts.find(accountId) != sAccounts.end())
                return false;

            QueryResult chronicleRows = CharacterDatabase.Query(
                "SELECT `slot`,`task_id`,`period_key`,`progress`,`completed` "
                "FROM `mod_objectives_chronicle` WHERE `account_id` = {} ORDER BY `slot`", accountId);
            QueryResult currencyRows = CharacterDatabase.Query(
                "SELECT `adventure_marks` FROM `mod_objectives_account_currency` "
                "WHERE `account_id` = {}", accountId);

            AccountState account;
            account.accountId = accountId;
            account.chronicle.assign(sConfig.chronicleSlots, TaskState{});
            uint32 const weekly = WeeklyReset();
            account.period = weekly;
            bool valid = false;
            bool invalid = false;

            if (chronicleRows && chronicleRows->GetRowCount() > 0)
            {
                do
                {
                    Field* fields = chronicleRows->Fetch();
                    uint32 const slot = fields[0].Get<uint32>();
                    TaskDef const* task = FindTask(fields[1].Get<uint32>());
                    if (fields[2].Get<uint32>() != weekly || slot >= account.chronicle.size() || !task
                        || task->scope != SCOPE_CHRONICLE)
                    {
                        invalid = true;
                        continue;
                    }
                    account.chronicle[slot].taskId = task->id;
                    account.chronicle[slot].progress = fields[3].Get<uint32>();
                    account.chronicle[slot].completed = fields[4].Get<uint8>() != 0;
                    valid = true;
                } while (chronicleRows->NextRow());
            }

            if (currencyRows && currencyRows->GetRowCount() > 0)
            {
                Field* fields = currencyRows->Fetch();
                account.marks = fields[0].Get<uint32>();
            }

            if (!valid || invalid)
                GenerateChronicle(account, weekly);

            bool const needsWrite = account.dirty;
            sAccounts.emplace(accountId, std::move(account));
            if (needsWrite)
                sDirtyAccounts.insert(accountId);
            return true;
        }

        bool LoadCharacter(Player* player, uint32 guid, uint32 accountId)
        {
            std::lock_guard<std::mutex> lock(sMutex);
            if (sCharacters.find(guid) != sCharacters.end())
                return false;

            QueryResult boardRows = CharacterDatabase.Query(
                "SELECT `scope`,`slot`,`task_id`,`period_key`,`progress`,`completed` "
                "FROM `mod_objectives_board` WHERE `guid` = {} ORDER BY `scope`,`slot`", guid);
            QueryResult focusRows = CharacterDatabase.Query(
                "SELECT `period_key`,`zone_id`,`rerolls`,`focus_changed` "
                "FROM `mod_objectives_focus` WHERE `guid` = {}", guid);
            QueryResult currencyRows = CharacterDatabase.Query(
                "SELECT `mythic_coins`,`commendations` FROM `mod_objectives_character_currency` "
                "WHERE `guid` = {}", guid);

            CharacterState character;
            character.guid = guid;
            character.accountId = accountId;
            character.daily.assign(sConfig.dailySlots, TaskState{});
            character.weekly.assign(sConfig.weeklySlots, TaskState{});
            character.requestMs = uint64(GameTime::GetGameTimeMS().count());

            uint32 const daily = DailyReset();
            uint32 const weekly = WeeklyReset();
            Math::BoardValidation validation;
            validation.dailySizeOk = character.daily.size() == sConfig.dailySlots;
            validation.weeklySizeOk = character.weekly.size() == sConfig.weeklySlots;

            if (boardRows && boardRows->GetRowCount() > 0)
            {
                do
                {
                    Field* fields = boardRows->Fetch();
                    uint8 const scope = fields[0].Get<uint8>();
                    uint32 const slot = fields[1].Get<uint32>();
                    uint32 const taskId = fields[2].Get<uint32>();
                    uint32 const period = fields[3].Get<uint32>();
                    TaskDef const* task = FindTask(taskId);

                    if (!task)
                    {
                        if (scope == SCOPE_DAILY)
                            validation.dailyInvalid = true;
                        else if (scope == SCOPE_WEEKLY)
                            validation.weeklyInvalid = true;
                        else
                        {
                            validation.dailyInvalid = true;
                            validation.weeklyInvalid = true;
                        }
                        continue;
                    }

                    if (scope == SCOPE_DAILY && period == daily && slot < character.daily.size()
                        && task->scope == SCOPE_DAILY)
                    {
                        character.daily[slot].taskId = task->id;
                        character.daily[slot].progress = fields[4].Get<uint32>();
                        character.daily[slot].completed = fields[5].Get<uint8>() != 0;
                        validation.dailyValid = true;
                    }
                    else if (scope == SCOPE_WEEKLY && period == weekly && slot < character.weekly.size()
                        && task->scope == SCOPE_WEEKLY)
                    {
                        character.weekly[slot].taskId = task->id;
                        character.weekly[slot].progress = fields[4].Get<uint32>();
                        character.weekly[slot].completed = fields[5].Get<uint8>() != 0;
                        validation.weeklyValid = true;
                    }
                    else if (scope == SCOPE_DAILY)
                    {
                        validation.dailyInvalid = true;
                    }
                    else if (scope == SCOPE_WEEKLY)
                    {
                        validation.weeklyInvalid = true;
                    }
                    else
                    {
                        validation.dailyInvalid = true;
                        validation.weeklyInvalid = true;
                    }
                } while (boardRows->NextRow());
            }

            if (focusRows && focusRows->GetRowCount() > 0)
            {
                Field* fields = focusRows->Fetch();
                if (fields[0].Get<uint32>() == daily)
                {
                    character.focusZone = fields[1].Get<uint32>();
                    character.rerolls = fields[2].Get<uint32>();
                    character.focusChanged = fields[3].Get<uint8>() != 0;
                }
            }

            if (currencyRows && currencyRows->GetRowCount() > 0)
            {
                Field* fields = currencyRows->Fetch();
                character.coins = fields[0].Get<uint32>();
                character.commendations = fields[1].Get<uint32>();
            }

            if (Math::RebuildDaily(validation))
                GenerateDaily(character, player, daily);
            if (Math::RebuildWeekly(validation))
                GenerateWeekly(character, player, weekly);

            if (character.focusZone == 0)
            {
                std::vector<TaskDef const*> pool = BuildPool(SCOPE_DAILY, player->GetLevel(), FactionOf(player));
                character.focusZone = DefaultFocus(pool, player->GetZoneId());
                character.dirty = true;
            }

            sCharacters.emplace(guid, std::move(character));
            if (sCharacters[guid].dirty)
                sDirtyCharacters.insert(guid);
            return true;
        }

        std::vector<OfferDef const*> OffersFor(Player* player)
        {
            std::vector<OfferDef const*> offers;
            for (OfferDef const& offer : sOffers)
            {
                if (offer.era > sConfig.era)
                    continue;
                if (player->GetLevel() < offer.minLevel)
                    continue;
                if (offer.maxLevel != 0 && player->GetLevel() > offer.maxLevel)
                    continue;
                if (offer.faction != 0 && offer.faction != FactionOf(player))
                    continue;
                offers.push_back(&offer);
            }

            std::sort(offers.begin(), offers.end(), [](OfferDef const* left, OfferDef const* right)
            {
                if (left->category != right->category)
                    return left->category < right->category;
                if (left->sort != right->sort)
                    return left->sort < right->sort;
                return left->id < right->id;
            });
            return offers;
        }

        void BuyOffer(Player* player, uint32 offerId)
        {
            if (!player || !player->GetSession())
                return;

            OfferDef const* offer = FindOffer(offerId);
            if (!offer)
            {
                ChatHandler(player->GetSession()).SendSysMessage("That reward is not available.");
                return;
            }

            if (offer->era > sConfig.era)
            {
                ChatHandler(player->GetSession()).SendSysMessage("That reward is not available in this era.");
                return;
            }

            if (player->GetLevel() < offer->minLevel || (offer->maxLevel != 0 && player->GetLevel() > offer->maxLevel))
            {
                ChatHandler(player->GetSession()).SendSysMessage("You are not the right level for that reward.");
                return;
            }
            if (offer->faction != 0 && offer->faction != FactionOf(player))
            {
                ChatHandler(player->GetSession()).SendSysMessage("That reward is not for your faction.");
                return;
            }

            ItemPosCountVec dest;
            InventoryResult const storeResult = player->CanStoreNewItem(NULL_BAG, NULL_SLOT, dest,
                offer->itemId, offer->itemCount);
            if (storeResult != EQUIP_ERR_OK)
            {
                ChatHandler(player->GetSession()).SendSysMessage(
                    "There is no room for that reward in your bags.");
                return;
            }

            uint32 guid = player->GetGUID().GetCounter();
            uint32 accountId = player->GetSession()->GetAccountId();
            bool const useAccount = offer->currency == CURRENCY_MARKS;
            bool paid = false;
            std::string error;

            {
                std::lock_guard<std::mutex> lock(sMutex);
                auto characterItr = sCharacters.find(guid);
                auto accountItr = sAccounts.find(accountId);
                if (characterItr == sCharacters.end() || accountItr == sAccounts.end())
                {
                    error = "not_loaded";
                }
                else
                {
                    CharacterState& character = characterItr->second;
                    AccountState& account = accountItr->second;
                    uint32* balance = nullptr;
                    if (offer->currency == CURRENCY_MARKS)
                        balance = &account.marks;
                    else if (offer->currency == CURRENCY_COINS)
                        balance = &character.coins;
                    else
                        balance = &character.commendations;

                    if (*balance < offer->cost)
                        error = "currency";
                    else
                    {
                        *balance -= offer->cost;
                        paid = true;
                    }
                }
            }

            auto refund = [&]()
            {
                std::lock_guard<std::mutex> lock(sMutex);
                auto characterItr = sCharacters.find(guid);
                auto accountItr = sAccounts.find(accountId);
                if (useAccount && accountItr != sAccounts.end())
                    AddClamped(accountItr->second.marks, offer->cost);
                else if (!useAccount && characterItr != sCharacters.end())
                {
                    if (offer->currency == CURRENCY_COINS)
                        AddClamped(characterItr->second.coins, offer->cost);
                    else
                        AddClamped(characterItr->second.commendations, offer->cost);
                }
            };

            auto persist = [&]()
            {
                return useAccount ? PersistAccountCurrency(accountId) : PersistCharacterCurrency(guid);
            };

            if (paid && !persist())
            {
                refund();
                persist();
                error = "write";
                paid = false;
            }

            if (!paid)
            {
                ChatHandler(player->GetSession()).SendSysMessage(
                    error == "currency" ? "You do not have enough currency for that reward." :
                    "That purchase could not be completed.");
                LOG_DEBUG(LOG_CATEGORY, "purchase refused offer={} character={} reason={}", offerId, guid, error);
                CloseGossipMenuFor(player);
                SendBoard(player, "0");
                SendChronicle(player, "0");
                return;
            }

            Item* item = player->StoreNewItem(dest, offer->itemId, true);
            if (!item)
            {
                refund();
                persist();
                LOG_ERROR(LOG_CATEGORY,
                    "item store failed after currency charge for offer {} character {}; refunded",
                    offerId, guid);
                ChatHandler(player->GetSession()).SendSysMessage(
                    "The reward could not be stored; your currency was refunded.");
                CloseGossipMenuFor(player);
                SendBoard(player, "0");
                SendChronicle(player, "0");
                return;
            }

            ChatHandler(player->GetSession()).SendSysMessage(Acore::StringFormat(
                "Bought {} for {} {}.", offer->name, offer->cost, CurrencyName(offer->currency)));
            LOG_DEBUG(LOG_CATEGORY, "purchase offer={} character={} currency={} cost={}", offerId, guid,
                uint32(offer->currency), offer->cost);
            CloseGossipMenuFor(player);
            SendBoard(player, "0");
            SendChronicle(player, "0");
        }
    }

    void LoadConfig(bool /*reload*/)
    {
        sConfig.enabled = sConfigMgr->GetOption<bool>("Objectives.Enable", true);
        sConfig.era = std::min<uint32>(sConfigMgr->GetOption<uint32>("Objectives.Era", 0), 2);
        sConfig.dailySlots = Math::ClampSlots(
            std::max<uint32>(1, sConfigMgr->GetOption<uint32>("Objectives.DailySlots", 5)), MAX_DAILY_SLOTS);
        sConfig.weeklySlots = Math::ClampSlots(
            sConfigMgr->GetOption<uint32>("Objectives.WeeklySlots", 1), MAX_WEEKLY_SLOTS);
        sConfig.chronicleSlots = Math::ClampSlots(
            sConfigMgr->GetOption<uint32>("Objectives.ChronicleSlots", 3), MAX_CHRONICLE_SLOTS);
        sConfig.rerollCost = sConfigMgr->GetOption<uint32>("Objectives.RerollCostCopper", 2000);
        sConfig.flushIntervalMs = std::max<uint32>(5000,
            sConfigMgr->GetOption<uint32>("Objectives.FlushIntervalMs", 20000));
    }

    void Startup()
    {
        sSchemaReady = CharacterTableExists("mod_objectives_board")
            && CharacterTableExists("mod_objectives_focus")
            && CharacterTableExists("mod_objectives_chronicle")
            && CharacterTableExists("mod_objectives_character_currency")
            && CharacterTableExists("mod_objectives_account_currency");

        if (!sSchemaReady)
            LOG_WARN(LOG_CATEGORY,
                "objective tables are missing; the feature is disabled until the module SQL is applied");

        LoadTasks();
        LoadOffers();

        sDefinitionsReady = !sTasks.empty();
        if (!sDefinitionsReady)
            LOG_WARN(LOG_CATEGORY, "no task definitions loaded; the board is inert");
        else if (sOffers.empty())
            LOG_WARN(LOG_CATEGORY, "no offer definitions loaded; reward vendors will be empty");

        LOG_INFO(LOG_CATEGORY, "loaded {} tasks and {} offers (era {}, slots {}/{}/{})", sTasks.size(),
            sOffers.size(), sConfig.era, sConfig.dailySlots, sConfig.weeklySlots, sConfig.chronicleSlots);
    }

    void OnUpdate(uint32 diff)
    {
        if (!sSchemaReady)
            return;

        sFlushTimer += diff;
        if (sFlushTimer < sConfig.flushIntervalMs)
            return;
        sFlushTimer = 0;
        FlushDirty(MAX_FLUSH_BATCHES_PER_TICK);
    }

    void OnShutdown()
    {
        if (!sSchemaReady)
            return;

        FlushDirty(std::numeric_limits<uint32>::max());

        std::size_t remaining = 0;
        {
            std::lock_guard<std::mutex> lock(sMutex);
            remaining = sDirtyCharacters.size() + sDirtyAccounts.size();
        }
        if (remaining)
            LOG_WARN(LOG_CATEGORY, "shutdown flush left {} dirty progress rows", remaining);
    }

    void OnLogin(Player* player)
    {
        if (!sConfig.enabled || !sSchemaReady)
            return;

        uint32 const guid = player->GetGUID().GetCounter();
        uint32 const accountId = player->GetSession()->GetAccountId();

        bool loadedAccount = false;
        {
            std::lock_guard<std::mutex> lock(sMutex);
            loadedAccount = sAccounts.find(accountId) != sAccounts.end();
        }
        if (!loadedAccount)
            LoadAccount(accountId);

        bool loadedCharacter = false;
        {
            std::lock_guard<std::mutex> lock(sMutex);
            loadedCharacter = sCharacters.find(guid) != sCharacters.end();
        }
        if (loadedCharacter)
            return;

        if (LoadCharacter(player, guid, accountId))
        {
            std::lock_guard<std::mutex> lock(sMutex);
            ++sAccountRefs[accountId];
        }
    }

    void OnLogout(Player* player)
    {
        if (!sSchemaReady)
            return;

        uint32 const guid = player->GetGUID().GetCounter();
        uint32 const accountId = player->GetSession()->GetAccountId();
        std::vector<std::string> sql;

        {
            std::lock_guard<std::mutex> lock(sMutex);
            auto characterItr = sCharacters.find(guid);
            if (characterItr != sCharacters.end())
            {
                if (characterItr->second.dirty)
                    QueueCharacterFlush(characterItr->second, sql);
                sCharacters.erase(characterItr);
                sDirtyCharacters.erase(guid);
            }

            auto refItr = sAccountRefs.find(accountId);
            if (refItr != sAccountRefs.end())
            {
                if (refItr->second > 0)
                    --refItr->second;
                if (refItr->second == 0)
                {
                    sAccountRefs.erase(refItr);
                    auto accountItr = sAccounts.find(accountId);
                    if (accountItr != sAccounts.end())
                    {
                        if (accountItr->second.dirty)
                            QueueAccountFlush(accountItr->second, sql);
                        sAccounts.erase(accountItr);
                    }
                    sDirtyAccounts.erase(accountId);
                }
            }
        }

        CommitStatements(sql);
    }

    void OnCreatureKill(Player* player, Creature* killed)
    {
        if (!sConfig.enabled || !sSchemaReady || !killed)
            return;

        uint32 const entry = killed->GetEntry();
        uint32 const playerZone = player->GetZoneId();
        bool const boss = killed->GetMap()->IsDungeon()
            && (killed->IsDungeonBoss() || killed->isWorldBoss());
        uint32 const guid = player->GetGUID().GetCounter();
        uint32 const accountId = player->GetSession()->GetAccountId();
        std::vector<Completion> completions;

        {
            std::lock_guard<std::mutex> lock(sMutex);
            auto characterItr = sCharacters.find(guid);
            if (characterItr == sCharacters.end())
                return;

            CharacterState& character = characterItr->second;
            EnsureCharacterBoard(character, player);

            auto accountItr = sAccounts.find(accountId);
            AccountState* account = accountItr == sAccounts.end() ? nullptr : &accountItr->second;
            if (account)
                EnsureChronicle(*account);

            bool changed = false;
            auto apply = [&](TaskState& state)
            {
                TaskDef const* task = FindTask(state.taskId);
                if (!task || state.completed)
                    return;
                if (task->type != TASK_KILL_CREATURE && task->type != TASK_KILL_BOSS)
                    return;
                if (task->type == TASK_KILL_BOSS && !boss)
                    return;
                if (task->targetId != 0 && task->targetId != entry)
                    return;
                if (task->zoneId != 0 && task->zoneId != playerZone)
                    return;
                if (!AdvanceTask(state, *task))
                    return;

                changed = true;
                if (state.completed)
                    AwardTask(*task, character, account, completions);
            };

            for (TaskState& state : character.daily)
                apply(state);
            for (TaskState& state : character.weekly)
                apply(state);
            if (account)
                for (TaskState& state : account->chronicle)
                    apply(state);

            if (changed)
            {
                character.dirty = true;
                sDirtyCharacters.insert(guid);
                if (account)
                {
                    account->dirty = true;
                    sDirtyAccounts.insert(accountId);
                }
            }
        }

        if (!completions.empty())
        {
            PersistCharacterCurrency(guid);
            PersistAccountCurrency(accountId);
        }

        SendCompletionLines(player, completions);
    }

    void OnQuestComplete(Player* player, Quest const* quest)
    {
        if (!sConfig.enabled || !sSchemaReady || !quest)
            return;

        uint32 const questId = quest->GetQuestId();
        int32 const questZone = quest->GetZoneOrSort();
        uint32 const playerZone = player->GetZoneId();
        uint32 const guid = player->GetGUID().GetCounter();
        uint32 const accountId = player->GetSession()->GetAccountId();
        std::vector<Completion> completions;

        {
            std::lock_guard<std::mutex> lock(sMutex);
            auto characterItr = sCharacters.find(guid);
            if (characterItr == sCharacters.end())
                return;

            CharacterState& character = characterItr->second;
            EnsureCharacterBoard(character, player);

            auto accountItr = sAccounts.find(accountId);
            AccountState* account = accountItr == sAccounts.end() ? nullptr : &accountItr->second;
            if (account)
                EnsureChronicle(*account);

            bool changed = false;
            auto apply = [&](TaskState& state)
            {
                TaskDef const* task = FindTask(state.taskId);
                if (!task || state.completed || task->type != TASK_COMPLETE_QUEST)
                    return;
                if (task->targetId != 0 && task->targetId != questId)
                    return;
                if (task->zoneId != 0 && task->zoneId != playerZone
                    && (questZone <= 0 || uint32(questZone) != task->zoneId))
                    return;
                if (!AdvanceTask(state, *task))
                    return;

                changed = true;
                if (state.completed)
                    AwardTask(*task, character, account, completions);
            };

            for (TaskState& state : character.daily)
                apply(state);
            for (TaskState& state : character.weekly)
                apply(state);
            if (account)
                for (TaskState& state : account->chronicle)
                    apply(state);

            if (changed)
            {
                character.dirty = true;
                sDirtyCharacters.insert(guid);
                if (account)
                {
                    account->dirty = true;
                    sDirtyAccounts.insert(accountId);
                }
            }
        }

        if (!completions.empty())
        {
            PersistCharacterCurrency(guid);
            PersistAccountCurrency(accountId);
        }

        SendCompletionLines(player, completions);
    }

    void OnBattlegroundWin(Player* player, uint32 battlegroundTypeId)
    {
        if (!sConfig.enabled || !sSchemaReady)
            return;

        uint32 const guid = player->GetGUID().GetCounter();
        uint32 const accountId = player->GetSession()->GetAccountId();
        std::vector<Completion> completions;

        {
            std::lock_guard<std::mutex> lock(sMutex);
            auto characterItr = sCharacters.find(guid);
            if (characterItr == sCharacters.end())
                return;

            CharacterState& character = characterItr->second;
            EnsureCharacterBoard(character, player);

            auto accountItr = sAccounts.find(accountId);
            AccountState* account = accountItr == sAccounts.end() ? nullptr : &accountItr->second;
            if (account)
                EnsureChronicle(*account);

            bool changed = false;
            auto apply = [&](TaskState& state)
            {
                TaskDef const* task = FindTask(state.taskId);
                if (!task || state.completed || task->type != TASK_WIN_BATTLEGROUND)
                    return;
                if (task->targetId != 0 && task->targetId != battlegroundTypeId)
                    return;
                if (!AdvanceTask(state, *task))
                    return;

                changed = true;
                if (state.completed)
                    AwardTask(*task, character, account, completions);
            };

            for (TaskState& state : character.daily)
                apply(state);
            for (TaskState& state : character.weekly)
                apply(state);
            if (account)
                for (TaskState& state : account->chronicle)
                    apply(state);

            if (changed)
            {
                character.dirty = true;
                sDirtyCharacters.insert(guid);
                if (account)
                {
                    account->dirty = true;
                    sDirtyAccounts.insert(accountId);
                }
            }
        }

        if (!completions.empty())
        {
            PersistCharacterCurrency(guid);
            PersistAccountCurrency(accountId);
        }

        SendCompletionLines(player, completions);
    }

    bool OnAddonChat(Player* player, uint32 language, std::string& message, Player* receiver)
    {
        if (language != LANG_ADDON || !receiver || receiver != player)
            return true;

        std::string const prefix = std::string(ADDON_PREFIX) + "\t";
        if (message.compare(0, prefix.size(), prefix) != 0)
            return true;

        if (!sConfig.enabled)
        {
            SendPayload(player, "ERR:0:disabled");
            return false;
        }
        if (!sSchemaReady || !sDefinitionsReady)
        {
            SendPayload(player, "ERR:0:not_ready");
            return false;
        }

        if (!ConsumeRequest(player))
        {
            SendPayload(player, "ERR:0:busy");
            return false;
        }

        HandleAddonMessage(player, std::string_view(message).substr(prefix.size()));
        return false;
    }

    bool OnVendorGossipHello(Player* player, Creature* creature)
    {
        if (!creature)
            return false;
        uint32 const entry = creature->GetEntry();
        if (entry != VENDOR_ALLIANCE_ENTRY && entry != VENDOR_HORDE_ENTRY)
            return false;

        if (!sConfig.enabled || !sSchemaReady || !sDefinitionsReady)
        {
            ChatHandler(player->GetSession()).SendSysMessage("Objective rewards are not available yet.");
            CloseGossipMenuFor(player);
            return true;
        }

        std::vector<OfferDef const*> offers = OffersFor(player);
        if (offers.empty())
        {
            AddGossipItemFor(player, GOSSIP_ICON_CHAT, "No rewards are available.",
                GOSSIP_SENDER_MAIN, 0);
        }
        else
        {
            for (OfferDef const* offer : offers)
            {
                std::string const text = Acore::StringFormat("{} - {} {} (level {}+)", offer->name,
                    offer->cost, CurrencyName(offer->currency), offer->minLevel);
                AddGossipItemFor(player, GOSSIP_ICON_MONEY_BAG, text, GOSSIP_SENDER_MAIN,
                    OFFER_ACTION_BASE + offer->id);
            }
        }

        SendGossipMenuFor(player, VENDOR_TEXT_ID, creature);
        return true;
    }

    bool OnVendorGossipSelect(Player* player, Creature* creature, uint32 action)
    {
        if (!creature)
            return false;
        uint32 const entry = creature->GetEntry();
        if (entry != VENDOR_ALLIANCE_ENTRY && entry != VENDOR_HORDE_ENTRY)
            return false;

        if (action < OFFER_ACTION_BASE)
        {
            CloseGossipMenuFor(player);
            return true;
        }

        if (!sConfig.enabled || !sSchemaReady || !sDefinitionsReady)
        {
            CloseGossipMenuFor(player);
            return true;
        }

        BuyOffer(player, action - OFFER_ACTION_BASE);
        return true;
    }
}
