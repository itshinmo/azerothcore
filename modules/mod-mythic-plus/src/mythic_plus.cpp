/*
 * Credits: silviu20092
 *
 * Forked from https://github.com/silviu20092/mod-mythic-plus (MIT), commit e2a487d.
 */

#include "Chat.h"
#include "Config.h"
#include "Creature.h"
#include "DBCStores.h"
#include "DatabaseEnv.h"
#include "GameTime.h"
#include "Group.h"
#include "Log.h"
#include "Map.h"
#include "ObjectAccessor.h"
#include "ObjectMgr.h"
#include "SharedDefines.h"
#include "StringConvert.h"
#include "Util.h"
#include "World.h"
#include "mythic_affix.h"
#include "mythic_plus.h"
#include "mythic_plus_database.h"
#include <algorithm>
#include <cmath>
#include <iomanip>
#include <sstream>

namespace
{
    constexpr char const* MYTHIC_MAP_DATA_KEY = "mythicPlusMapData";
    constexpr char const* MYTHIC_CREATURE_DATA_KEY = "mythicPlusCreatureData";
}

MythicPlus::MythicPlus() = default;

MythicPlus* MythicPlus::instance()
{
    static MythicPlus instance;
    return &instance;
}

uint64 MythicPlus::MapData::GetElapsedMs() const
{
    if (!started || startTimeMs == 0)
        return 0;

    uint64 now = Utils::GameTimeMs();
    return now > startTimeMs ? now - startTimeMs : 0;
}

MythicPlus::MapData* MythicPlus::GetMapData(Map* map, bool withDefault) const
{
    if (withDefault)
        return map->CustomData.GetDefault<MapData>(MYTHIC_MAP_DATA_KEY);

    return map->CustomData.Get<MapData>(MYTHIC_MAP_DATA_KEY);
}

MythicPlus::CreatureData* MythicPlus::GetCreatureData(Creature* creature, bool withDefault) const
{
    if (withDefault)
        return creature->CustomData.GetDefault<CreatureData>(MYTHIC_CREATURE_DATA_KEY);

    return creature->CustomData.Get<CreatureData>(MYTHIC_CREATURE_DATA_KEY);
}

/*static*/ void MythicPlus::BroadcastToPlayer(Player const* player, std::string const& message)
{
    if (!player)
        return;

    std::ostringstream oss;
    oss << "|cffa11585[MYTHIC PLUS]|r: ";
    oss << message;
    ChatHandler(player->GetSession()).SendSysMessage(oss.str());
}

/*static*/ void MythicPlus::AnnounceToPlayer(Player const* player, std::string const& message)
{
    if (player)
        ChatHandler(player->GetSession()).SendNotification(message);
}

/*static*/ void MythicPlus::AnnounceToMap(Map const* map, std::string const& message)
{
    if (!map)
        return;

    Map::PlayerList const& playerList = map->GetPlayers();
    for (Map::PlayerList::const_iterator itr = playerList.begin(); itr != playerList.end(); ++itr)
        if (Player* player = itr->GetSource())
            AnnounceToPlayer(player, message);
}

/*static*/ void MythicPlus::BroadcastToMap(Map const* map, std::string const& message)
{
    if (!map)
        return;

    Map::PlayerList const& playerList = map->GetPlayers();
    for (Map::PlayerList::const_iterator itr = playerList.begin(); itr != playerList.end(); ++itr)
        if (Player* player = itr->GetSource())
            BroadcastToPlayer(player, message);
}

/*static*/ void MythicPlus::FallbackTeleport(Player* player)
{
    if (player)
        player->TeleportToEntryPoint();
}

bool MythicPlus::CanMapBeMythicPlus(Map const* map) const
{
    if (!IsEnabled() || !map || !map->GetEntry())
        return false;

    if (!map->IsNonRaidDungeon())
        return false;

    if (map->GetDifficulty() != DUNGEON_DIFFICULTY_NORMAL)
        return false;

    uint32 mapId = map->GetId();
    std::lock_guard<std::mutex> lock(_dataMutex);
    return mythicPlusDungeons.find(mapId) != mythicPlusDungeons.end();
}

bool MythicPlus::CanProcessCreature(Creature* creature) const
{
    if (!creature || !creature->IsInWorld())
        return false;

    Map* map = creature->GetMap();
    if (!map || !map->IsNonRaidDungeon() || !map->ToInstanceMap())
        return false;

    if (creature->GetLevel() < 5)
        return false;

    if ((creature->IsHunterPet() || creature->IsPet() || creature->IsSummon()) && creature->IsControlledByPlayer())
        return false;

    if (creature->IsCritter() || creature->IsTotem() || creature->IsTrigger() || creature->IsCivilian())
        return false;

    if (!creature->IsHostileToPlayers())
        return false;

    if (TempSummon* summon = creature->ToTempSummon())
        if (summon->GetSummoner() && summon->GetSummoner()->ToPlayer())
            return false;

    return true;
}

bool MythicPlus::IsMapInMythicPlus(Map const* map) const
{
    if (!map)
        return false;

    MapData* mapData = GetMapData(const_cast<Map*>(map), false);
    return mapData != nullptr && mapData->mythicLevel != nullptr;
}

uint64 MythicPlus::ScaleKey(uint32 mapId, uint32 keyLevel, bool boss)
{
    return (uint64(mapId) << 32) | (uint64(keyLevel) << 1) | (boss ? 1 : 0);
}

uint64 MythicPlus::ProgressKey(uint32 guid, uint8 era)
{
    return (uint64(era) << 32) | guid;
}

bool MythicPlus::IsBoss(uint32 mapId, uint32 entry) const
{
    uint64 key = (uint64(mapId) << 32) | entry;
    std::lock_guard<std::mutex> lock(_dataMutex);
    return bossEntries.find(key) != bossEntries.end();
}

bool MythicPlus::IsFinalBoss(uint32 mapId, uint32 entry) const
{
    uint64 key = (uint64(mapId) << 32) | entry;
    std::lock_guard<std::mutex> lock(_dataMutex);
    return finalBossEntries.find(key) != finalBossEntries.end();
}

bool MythicPlus::HasActiveRuns() const
{
    std::lock_guard<std::mutex> lock(_dataMutex);
    for (auto const& entry : mythicPlusDungeonInfo)
        if (!entry.second.done)
            return true;

    return false;
}

std::optional<CreatureScale> MythicPlus::GetCreatureScale(uint32 mapId, uint32 keyLevel, bool boss) const
{
    uint64 key = ScaleKey(mapId, keyLevel, boss);
    std::lock_guard<std::mutex> lock(_dataMutex);
    auto itr = creatureScales.find(key);
    if (itr == creatureScales.end())
        return std::nullopt;

    return itr->second;
}

size_t MythicPlus::GetCreatureScaleCount() const
{
    std::lock_guard<std::mutex> lock(_dataMutex);
    return creatureScales.size();
}

size_t MythicPlus::GetCapableDungeonCount() const
{
    std::lock_guard<std::mutex> lock(_dataMutex);
    return mythicPlusDungeons.size();
}

size_t MythicPlus::GetBossCount() const
{
    std::lock_guard<std::mutex> lock(_dataMutex);
    return bossEntries.size();
}

void MythicPlus::LoadFromDB()
{
    ClearRunRows();

    WorldData data;
    if (!LoadWorldData(data))
    {
        LOG_ERROR("module.mythic_plus", "Mythic+ world data is incomplete; runs are disabled");
    }
    else
    {
        std::lock_guard<std::mutex> lock(_dataMutex);
        mythicPlusDungeons = std::move(data.dungeons);
        bossEntries = std::move(data.bosses);
        finalBossEntries = std::move(data.finalBosses);
        creatureScales = std::move(data.scales);
        mythicLevels = std::move(data.levels);
    }

    LoadProgressFromDB();

    std::lock_guard<std::mutex> lock(_dataMutex);
    LOG_INFO("module.mythic_plus", "Loaded {} dungeon(s), {} boss(es), {} scale(s), {} key level(s)",
        mythicPlusDungeons.size(), bossEntries.size(), creatureScales.size(), mythicLevels.size());
}

bool MythicPlus::ReloadTables()
{
    if (HasActiveRuns())
        return false;

    WorldData data;
    if (!LoadWorldData(data))
    {
        LOG_ERROR("module.mythic_plus", "Mythic+ reload failed; keeping the previous tables");
        return false;
    }

    std::lock_guard<std::mutex> lock(_dataMutex);
    for (auto const& entry : mythicPlusDungeonInfo)
        if (!entry.second.done)
            return false;

    mythicPlusDungeons = std::move(data.dungeons);
    bossEntries = std::move(data.bosses);
    finalBossEntries = std::move(data.finalBosses);
    creatureScales = std::move(data.scales);
    mythicLevels = std::move(data.levels);

    LOG_INFO("module.mythic_plus", "Reloaded {} dungeon(s), {} scale(s), {} key level(s)",
        mythicPlusDungeons.size(), creatureScales.size(), mythicLevels.size());
    return true;
}

void MythicPlus::ClearRunRows()
{
    MythicPlusDatabase::ClearRunRows();
}

bool MythicPlus::LoadWorldData(WorldData& data)
{
    data = WorldData();

    if (!LoadCapableDungeonsFromDB(data))
        return false;

    if (!LoadBossesFromDB(data))
        return false;

    if (!LoadCreatureScalesFromDB(data))
        return false;

    if (!LoadLevelsFromDB(data))
        return false;

    for (auto const& dungeon : data.dungeons)
    {
        for (auto const& level : data.levels)
        {
            for (bool boss : { false, true })
            {
                if (data.scales.find(ScaleKey(dungeon.first, level->level, boss)) == data.scales.end())
                {
                    LOG_ERROR("module.mythic_plus",
                        "Missing creature scale for map {} key {} boss {}", dungeon.first, level->level, boss);
                    return false;
                }
            }
        }
    }

    return true;
}

bool MythicPlus::LoadCapableDungeonsFromDB(WorldData& data)
{
    QueryResult result = WorldDatabase.Query(
        "SELECT map, era, mapdifficulty, final_boss_entry FROM mythic_plus_capable_dungeon");
    if (!result)
    {
        LOG_ERROR("module.mythic_plus", "Table mythic_plus_capable_dungeon is empty or unreadable");
        return false;
    }

    do
    {
        Field* fields = result->Fetch();
        uint32 mapId = fields[0].Get<uint32>();
        uint8 era = fields[1].Get<uint8>();
        uint16 difficulty = fields[2].Get<uint16>();
        uint32 finalBossEntry = fields[3].Get<uint32>();

        if (difficulty != DUNGEON_DIFFICULTY_NORMAL)
        {
            LOG_ERROR("module.mythic_plus",
                "Table mythic_plus_capable_dungeon has unsupported difficulty {} for map {}",
                difficulty, mapId);
            continue;
        }

        MapEntry const* mapEntry = sMapStore.LookupEntry(mapId);
        if (!mapEntry || !mapEntry->IsNonRaidDungeon())
        {
            LOG_ERROR("module.mythic_plus", "Map {} is not a non-raid dungeon", mapId);
            continue;
        }

        if (era != MYTHIC_PLUS_ERA_CLASSIC)
        {
            LOG_ERROR("module.mythic_plus", "Map {} has unsupported era {}; only Classic is in slice 1",
                mapId, era);
            continue;
        }

        MythicPlusCapableDungeon dungeon;
        dungeon.map = mapId;
        dungeon.era = era;
        dungeon.finalBossEntry = finalBossEntry;
        data.dungeons[mapId] = dungeon;
    } while (result->NextRow());

    return !data.dungeons.empty();
}

bool MythicPlus::LoadBossesFromDB(WorldData& data)
{
    QueryResult result = WorldDatabase.Query("SELECT map_id, entry, is_final FROM mythic_plus_boss");
    if (!result)
    {
        LOG_ERROR("module.mythic_plus", "Table mythic_plus_boss is empty or unreadable");
        return false;
    }

    do
    {
        Field* fields = result->Fetch();
        uint32 mapId = fields[0].Get<uint32>();
        uint32 entry = fields[1].Get<uint32>();
        bool isFinal = fields[2].Get<bool>();

        if (data.dungeons.find(mapId) == data.dungeons.end())
        {
            LOG_ERROR("module.mythic_plus", "Boss row for map {} has no capable dungeon row", mapId);
            continue;
        }

        if (!sObjectMgr->GetCreatureTemplate(entry))
        {
            LOG_ERROR("module.mythic_plus", "Boss entry {} on map {} has no creature template", entry, mapId);
            continue;
        }

        uint64 key = (uint64(mapId) << 32) | entry;
        data.bosses.insert(key);
        if (isFinal)
            data.finalBosses.insert(key);
    } while (result->NextRow());

    for (auto itr = data.dungeons.begin(); itr != data.dungeons.end();)
    {
        uint64 key = (uint64(itr->first) << 32) | itr->second.finalBossEntry;
        if (data.finalBosses.find(key) == data.finalBosses.end())
        {
            LOG_ERROR("module.mythic_plus", "Map {} has no valid final boss row; disabling it", itr->first);
            itr = data.dungeons.erase(itr);
        }
        else
            ++itr;
    }

    return !data.bosses.empty();
}

bool MythicPlus::LoadCreatureScalesFromDB(WorldData& data)
{
    QueryResult result = WorldDatabase.Query(
        "SELECT map_id, key_level, is_boss, level, health_multiplier, damage_multiplier "
        "FROM mythic_plus_creature_scale");
    if (!result)
    {
        LOG_ERROR("module.mythic_plus", "Table mythic_plus_creature_scale is empty or unreadable");
        return false;
    }

    do
    {
        Field* fields = result->Fetch();
        uint32 mapId = fields[0].Get<uint32>();
        uint32 keyLevel = fields[1].Get<uint32>();
        bool boss = fields[2].Get<bool>();
        uint8 level = fields[3].Get<uint8>();
        float healthMultiplier = fields[4].Get<float>();
        float damageMultiplier = fields[5].Get<float>();

        if (data.dungeons.find(mapId) == data.dungeons.end())
        {
            LOG_ERROR("module.mythic_plus", "Scale row for map {} has no capable dungeon row", mapId);
            continue;
        }

        if (keyLevel < 1 || keyLevel > MAX_KEY_LEVEL || level == 0 || level > 83 ||
            healthMultiplier <= 0.0f || damageMultiplier <= 0.0f)
        {
            LOG_ERROR("module.mythic_plus",
                "Invalid scale row for map {} key {} boss {}: level {} hp {} dmg {}",
                mapId, keyLevel, boss, level, healthMultiplier, damageMultiplier);
            continue;
        }

        CreatureScale scale;
        scale.level = level;
        scale.healthMultiplier = healthMultiplier;
        scale.damageMultiplier = damageMultiplier;
        data.scales[ScaleKey(mapId, keyLevel, boss)] = scale;
    } while (result->NextRow());

    return !data.scales.empty();
}

bool MythicPlus::LoadLevelsFromDB(WorldData& data)
{
    std::unordered_map<uint32, std::vector<DBAffix>> affixes;
    std::unordered_map<uint32, std::vector<DBReward>> rewards;

    if (QueryResult affixResult = WorldDatabase.Query(
            "SELECT lvl, affixtype, val1, val2 FROM mythic_plus_affix"))
    {
        do
        {
            Field* fields = affixResult->Fetch();
            uint32 level = fields[0].Get<uint32>();
            uint16 affixType = fields[1].Get<uint16>();
            if (affixType >= MAX_AFFIX_TYPE)
            {
                LOG_ERROR("module.mythic_plus", "Table mythic_plus_affix has invalid type {} at level {}",
                    affixType, level);
                continue;
            }

            DBAffix affix;
            affix.level = level;
            affix.affixType = affixType;
            affix.val1 = fields[2].Get<float>();
            affix.val2 = fields[3].Get<float>();
            affixes[level].push_back(affix);
        } while (affixResult->NextRow());
    }

    if (QueryResult rewardResult = WorldDatabase.Query(
            "SELECT lvl, rewardtype, val1 FROM mythic_plus_level_rewards"))
    {
        do
        {
            Field* fields = rewardResult->Fetch();
            uint32 level = fields[0].Get<uint32>();
            uint16 rewardType = fields[1].Get<uint16>();
            if (rewardType != 0)
            {
                LOG_ERROR("module.mythic_plus",
                    "Table mythic_plus_level_rewards has unsupported type {} at level {}; only copper is used",
                    rewardType, level);
                continue;
            }

            DBReward reward;
            reward.level = level;
            reward.val1 = fields[2].Get<uint32>();
            rewards[level].push_back(reward);
        } while (rewardResult->NextRow());
    }

    QueryResult result = WorldDatabase.Query(
        "SELECT lvl, timelimit FROM mythic_plus_level WHERE lvl BETWEEN 1 AND 5 ORDER BY lvl");
    if (!result)
    {
        LOG_ERROR("module.mythic_plus", "Table mythic_plus_level has no key levels 1-5");
        return false;
    }

    do
    {
        Field* fields = result->Fetch();
        uint32 levelNumber = fields[0].Get<uint32>();
        uint32 timeLimit = fields[1].Get<uint32>();
        if (timeLimit == 0)
        {
            LOG_ERROR("module.mythic_plus", "Key level {} has no timer", levelNumber);
            continue;
        }

        auto level = std::make_shared<MythicLevel>();
        level->level = levelNumber;
        level->timeLimit = timeLimit;

        if (rewards.find(levelNumber) != rewards.end())
            for (auto const& reward : rewards.at(levelNumber))
                level->reward.money += reward.val1;

        if (affixes.find(levelNumber) != affixes.end())
        {
            for (auto const& entry : affixes.at(levelNumber))
            {
                MythicAffix* affix = MythicAffix::AffixFactory(
                    MythicAffixType(entry.affixType), entry.val1, entry.val2);
                if (affix == nullptr)
                {
                    LOG_ERROR("module.mythic_plus", "Could not create affix type {} for level {}",
                        entry.affixType, levelNumber);
                    continue;
                }
                level->affixes.emplace_back(std::unique_ptr<MythicAffix>(affix));
            }
        }

        if (level->affixes.empty())
        {
            LOG_ERROR("module.mythic_plus", "Key level {} has no affixes", levelNumber);
            continue;
        }

        data.levels.push_back(level);
    } while (result->NextRow());

    return data.levels.size() == MAX_KEY_LEVEL;
}

void MythicPlus::LoadProgressFromDB()
{
    std::unordered_map<uint64, uint8> loaded;
    if (!MythicPlusDatabase::LoadProgress(loaded))
    {
        LOG_ERROR("module.mythic_plus", "Cannot load progression; module database is not ready");
        return;
    }

    for (auto& entry : loaded)
        if (entry.second > MAX_PROGRESSION_KEY)
            entry.second = MAX_PROGRESSION_KEY;

    std::lock_guard<std::mutex> lock(_dataMutex);
    charHighestKeys = std::move(loaded);
}

uint8 MythicPlus::GetEraForMap(uint32 mapId) const
{
    std::lock_guard<std::mutex> lock(_dataMutex);
    auto itr = mythicPlusDungeons.find(mapId);
    return itr == mythicPlusDungeons.end() ? MYTHIC_PLUS_ERA_CLASSIC : itr->second.era;
}

uint8 MythicPlus::GetHighestKey(uint32 guid, uint8 era) const
{
    std::lock_guard<std::mutex> lock(_dataMutex);
    auto itr = charHighestKeys.find(ProgressKey(guid, era));
    return itr == charHighestKeys.end() ? 0 : itr->second;
}

uint8 MythicPlus::GetNextKey(uint32 guid, uint8 era) const
{
    uint8 highest = GetHighestKey(guid, era);
    return uint8(std::min<uint32>(uint32(highest) + 1, MAX_PROGRESSION_KEY));
}

void MythicPlus::SetHighestKey(uint32 guid, uint8 era, uint8 key)
{
    if (guid == 0 || key == 0 || key > MAX_PROGRESSION_KEY)
        return;

    {
        std::lock_guard<std::mutex> lock(_dataMutex);
        uint64 progressKey = ProgressKey(guid, era);
        auto itr = charHighestKeys.find(progressKey);
        if (itr != charHighestKeys.end() && itr->second >= key)
            return;

        charHighestKeys[progressKey] = key;
    }

    MythicPlusDatabase::SaveProgress(guid, era, key);
}

std::shared_ptr<MythicLevel const> MythicPlus::GetMythicLevel(uint32 level) const
{
    std::lock_guard<std::mutex> lock(_dataMutex);
    auto itr = std::find_if(mythicLevels.begin(), mythicLevels.end(),
        [level](std::shared_ptr<MythicLevel> const& mythicLevel) { return mythicLevel->level == level; });
    if (itr == mythicLevels.end())
        return nullptr;

    return *itr;
}

size_t MythicPlus::GetMythicLevelCount() const
{
    std::lock_guard<std::mutex> lock(_dataMutex);
    return mythicLevels.size();
}

bool MythicPlus::CheckGroupForStart(Player const* player) const
{
    if (!player || player->GetLevel() < DEFAULT_MAX_LEVEL)
        return false;

    Group const* group = player->GetGroup();
    if (group == nullptr)
        return true;

    if (group->GetMembersCount() > 5 || group->isRaidGroup())
        return false;

    for (auto const& slot : group->GetMemberSlots())
    {
        Player* member = ObjectAccessor::FindConnectedPlayer(slot.guid);
        if (member == nullptr || !member->IsInWorld())
            return false;

        if (member->GetLevel() < DEFAULT_MAX_LEVEL || member->GetMap() != player->GetMap())
            return false;

        if (member->IsInCombat() || member->IsGameMaster())
            return false;
    }

    return true;
}

bool MythicPlus::StartRun(Player* player, uint32 keyLevel)
{
    if (!player || !player->IsInWorld())
        return false;

    if (player->IsGameMaster())
    {
        BroadcastToPlayer(player, "GM-mode characters cannot start a Mythic+ run.");
        return false;
    }

    if (!MythicPlusDatabase::IsReady())
    {
        BroadcastToPlayer(player, "Mythic+ is unavailable: the module database is not ready.");
        return false;
    }

    Map* map = player->GetMap();
    if (!CanMapBeMythicPlus(map))
    {
        BroadcastToPlayer(player, "This dungeon is not Mythic+ capable.");
        return false;
    }

    MapData* mapData = GetMapData(map);
    if (mapData->mythicLevel != nullptr || mapData->prestartDeadlineMs > 0 || mapData->done)
    {
        BroadcastToPlayer(player, "A Mythic+ run is already active or finished in this instance.");
        return false;
    }

    if (mapData->preCleared)
    {
        BroadcastToPlayer(player, "This instance was cleared without Mythic+. Reset it for a new run.");
        return false;
    }

    if (player->IsInCombat())
    {
        BroadcastToPlayer(player, "You cannot start a Mythic+ run in combat.");
        return false;
    }

    if (player->GetLevel() < DEFAULT_MAX_LEVEL)
    {
        BroadcastToPlayer(player, "You must be level 80 to start a Mythic+ run.");
        return false;
    }

    Group* group = player->GetGroup();
    if (group != nullptr && group->GetLeaderGUID() != player->GetGUID())
    {
        BroadcastToPlayer(player, "Only the group leader can start a Mythic+ run.");
        return false;
    }

    if (!CheckGroupForStart(player))
    {
        BroadcastToPlayer(player,
            "All group members must be online, level 80, out of combat, not in GM mode and inside "
            "this instance. Groups are limited to 5.");
        return false;
    }

    std::shared_ptr<MythicLevel const> level = GetMythicLevel(keyLevel);
    if (level == nullptr)
    {
        BroadcastToPlayer(player, "That Mythic+ key level is not loaded.");
        return false;
    }

    if (keyLevel > MAX_PROGRESSION_KEY)
    {
        BroadcastToPlayer(player, "The maximum key is 20.");
        return false;
    }

    uint8 era = GetEraForMap(map->GetId());

    std::vector<ObjectGuid> members;
    if (group != nullptr)
    {
        for (auto const& slot : group->GetMemberSlots())
            members.push_back(slot.guid);
    }
    else
        members.push_back(player->GetGUID());

    for (ObjectGuid const& guid : members)
    {
        uint8 nextKey = GetNextKey(guid.GetCounter(), era);
        if (keyLevel > nextKey)
        {
            Player* member = ObjectAccessor::FindConnectedPlayer(guid);
            std::string name = member ? member->GetName() : "A group member";
            std::ostringstream oss;
            oss << name << " can start key " << uint32(nextKey) << " at most; key " << keyLevel;
            oss << " needs key " << uint32(keyLevel - 1) << " completed first.";
            BroadcastToPlayer(player, oss.str());
            return false;
        }
    }

    uint32 instanceId = map->GetInstanceId();
    std::optional<MythicPlusDungeonInfo> saved = GetSavedDungeonInfo(instanceId);
    if (saved && saved->mapId != map->GetId())
    {
        RemoveDungeonInfo(instanceId);
        saved.reset();
    }

    if (saved)
    {
        BroadcastToPlayer(player, "This instance already has a Mythic+ run. Reset the instance for a new one.");
        return false;
    }

    mapData->mythicLevel = level;
    mapData->era = era;
    mapData->members = members;
    mapData->leftMembers.clear();
    mapData->prestartDeadlineMs = Utils::GameTimeMs() + PRESTART_TIMEOUT_MS;
    mapData->startTimeMs = 0;
    mapData->timeLimit = level->timeLimit;
    mapData->penaltyOnDeath = penaltyOnDeath.load();
    mapData->deaths = 0;
    mapData->started = false;
    mapData->done = false;
    mapData->receiveLoot = true;
    mapData->preCleared = false;

    Map::PlayerList const& players = map->GetPlayers();
    for (Map::PlayerList::const_iterator itr = players.begin(); itr != players.end(); ++itr)
    {
        Player* other = itr->GetSource();
        if (other && !IsRunMember(mapData, other->GetGUID()))
        {
            BroadcastToPlayer(other, "A Mythic+ run started and you are not a member.");
            FallbackTeleport(other);
        }
    }

    SaveMapInfo(map);
    ApplyRunStart(map);

    std::ostringstream oss;
    oss << "Mythic+ " << level->level << " ready. The timer starts on the first damage. Limit: ";
    oss << secsToTimeString(level->timeLimit);
    BroadcastToMap(map, oss.str());

    LOG_INFO("module.mythic_plus", "Run started: map {} instance {} key {} leader {}",
        map->GetId(), instanceId, level->level, player->GetGUID().GetCounter());

    return true;
}

void MythicPlus::StartTimer(Map* map)
{
    MapData* mapData = GetMapData(map, false);
    if (mapData == nullptr || mapData->mythicLevel == nullptr || mapData->started || mapData->done)
        return;

    uint64 now = Utils::GameTimeMs();
    if (mapData->prestartDeadlineMs > 0 && now > mapData->prestartDeadlineMs)
    {
        AbortRun(map, "prestart timeout");
        return;
    }

    mapData->started = true;
    mapData->startTimeMs = now;
    mapData->prestartDeadlineMs = 0;
    SaveMapInfo(map);

    std::ostringstream oss;
    oss << "Mythic+ timer started. Beat " << secsToTimeString(mapData->timeLimit) << "!";
    BroadcastToMap(map, oss.str());
}

void MythicPlus::CompleteRun(Map* map, Creature* finalBoss)
{
    if (!map || !finalBoss)
        return;

    MapData* mapData = GetMapData(map, false);
    if (mapData == nullptr || mapData->mythicLevel == nullptr || mapData->done)
        return;

    if (!mapData->started)
    {
        StartTimer(map);
        if (!mapData->started || mapData->done)
            return;
    }

    mapData->done = true;
    uint64 elapsedMs = mapData->GetElapsedMs();
    bool timed = mapData->receiveLoot &&
        (elapsedMs / 1000 + mapData->GetPenaltyTime() <= mapData->timeLimit);
    mapData->receiveLoot = timed;
    SaveMapInfo(map);

    std::vector<ObjectGuid> eligible;
    for (ObjectGuid const& guid : mapData->members)
    {
        if (!IsMemberEligible(mapData, guid))
            continue;

        Player* member = ObjectAccessor::FindConnectedPlayer(guid);
        if (member == nullptr || !member->IsInWorld() || member->GetMap() != map)
            continue;

        if (member->IsGameMaster())
            continue;

        eligible.push_back(guid);
        if (timed)
            Reward(member, mapData->mythicLevel->reward);
    }

    if (timed)
        for (ObjectGuid const& guid : eligible)
            SetHighestKey(guid.GetCounter(), mapData->era, uint8(mapData->mythicLevel->level));

    std::ostringstream oss;
    oss << "Mythic+ " << mapData->mythicLevel->level << " complete in ";
    oss << secsToTimeString(elapsedMs / 1000);
    oss << " (penalty " << secsToTimeString(mapData->GetPenaltyTime()) << "). ";
    oss << (timed ? "Timer beaten." : "Timer missed; no reward and no key unlock.");
    oss << " Eligible members: " << eligible.size() << "/" << mapData->members.size() << ".";
    BroadcastToMap(map, oss.str());

    LOG_INFO("module.mythic_plus", "Run complete: map {} instance {} key {} timed {} elapsed {}s eligible {}",
        map->GetId(), map->GetInstanceId(), mapData->mythicLevel->level, timed, elapsedMs / 1000,
        eligible.size());
}

void MythicPlus::AbortRun(Map* map, std::string const& reason)
{
    MapData* mapData = GetMapData(map, false);
    if (mapData == nullptr || mapData->mythicLevel == nullptr || mapData->done)
        return;

    mapData->done = true;
    mapData->receiveLoot = false;
    SaveMapInfo(map);

    BroadcastToMap(map, Utils::RedColored("Mythic+ run aborted: " + reason));
    LOG_INFO("module.mythic_plus", "Run aborted: map {} instance {} reason {}",
        map->GetId(), map->GetInstanceId(), reason);
}

void MythicPlus::BlockPreClearedInstance(Map* map)
{
    if (!map)
        return;

    MapData* mapData = GetMapData(map);
    mapData->preCleared = true;
}

void MythicPlus::MarkMemberLeft(Map* map, ObjectGuid guid)
{
    if (!map)
        return;

    uint32 counter = guid.GetCounter();
    MapData* mapData = GetMapData(map, false);
    if (mapData == nullptr || mapData->mythicLevel == nullptr || mapData->done)
        return;

    mapData->leftMembers.insert(counter);

    std::lock_guard<std::mutex> lock(_dataMutex);
    auto itr = mythicPlusDungeonInfo.find(map->GetInstanceId());
    if (itr != mythicPlusDungeonInfo.end())
        itr->second.leftMembers.insert(counter);
}

bool MythicPlus::IsRunMember(MapData const* mapData, ObjectGuid guid) const
{
    if (!mapData)
        return false;

    return std::find(mapData->members.begin(), mapData->members.end(), guid) != mapData->members.end();
}

bool MythicPlus::IsMemberEligible(MapData const* mapData, ObjectGuid guid) const
{
    if (!IsRunMember(mapData, guid))
        return false;

    return mapData->leftMembers.find(guid.GetCounter()) == mapData->leftMembers.end();
}

std::optional<MythicPlus::MythicPlusDungeonInfo> MythicPlus::GetSavedDungeonInfo(uint32 instanceId) const
{
    std::lock_guard<std::mutex> lock(_dataMutex);
    auto itr = mythicPlusDungeonInfo.find(instanceId);
    if (itr == mythicPlusDungeonInfo.end())
        return std::nullopt;

    return itr->second;
}

void MythicPlus::SaveDungeonInfo(MythicPlusDungeonInfo const& info)
{
    {
        std::lock_guard<std::mutex> lock(_dataMutex);
        mythicPlusDungeonInfo[info.instanceId] = info;
    }

    if (info.done)
    {
        MythicPlusDatabase::DeleteRun(info.instanceId);
        return;
    }

    MythicPlusDatabase::SaveRun(info.instanceId, info.mapId, info.timeLimit, info.startTimeMs,
        info.mythicLevel, info.penaltyOnDeath, info.deaths);
}

void MythicPlus::SaveMapInfo(Map* map)
{
    MapData* mapData = GetMapData(map, false);
    if (mapData == nullptr || mapData->mythicLevel == nullptr)
        return;

    MythicPlusDungeonInfo info;
    info.instanceId = map->GetInstanceId();
    info.mapId = map->GetId();
    info.timeLimit = mapData->timeLimit;
    info.startTimeMs = mapData->startTimeMs;
    info.prestartDeadlineMs = mapData->prestartDeadlineMs;
    info.mythicLevel = mapData->mythicLevel->level;
    info.era = mapData->era;
    info.penaltyOnDeath = mapData->penaltyOnDeath;
    info.deaths = mapData->deaths;
    info.done = mapData->done;
    info.members = mapData->members;
    info.leftMembers = mapData->leftMembers;
    SaveDungeonInfo(info);
}

void MythicPlus::RemoveDungeonInfo(uint32 instanceId)
{
    bool erased = false;
    {
        std::lock_guard<std::mutex> lock(_dataMutex);
        erased = mythicPlusDungeonInfo.erase(instanceId) > 0;
    }

    if (!erased)
        return;

    MythicPlusDatabase::DeleteRun(instanceId);
}

void MythicPlus::RestoreMapData(Map* map, MythicPlusDungeonInfo const& saved)
{
    MapData* mapData = GetMapData(map);
    mapData->mythicLevel = GetMythicLevel(saved.mythicLevel);
    mapData->members = saved.members;
    mapData->leftMembers = saved.leftMembers;
    mapData->prestartDeadlineMs = saved.prestartDeadlineMs;
    mapData->startTimeMs = saved.startTimeMs;
    mapData->era = saved.era;
    mapData->timeLimit = saved.timeLimit;
    mapData->penaltyOnDeath = saved.penaltyOnDeath;
    mapData->deaths = saved.deaths;
    mapData->started = saved.startTimeMs > 0;
    mapData->done = saved.done;
    mapData->receiveLoot = !saved.done;
    mapData->preCleared = false;
}

bool MythicPlus::ScaleCreature(Creature* creature, CreatureScale const& scale) const
{
    if (!creature)
        return false;

    CreatureTemplate const* cInfo = sObjectMgr->GetCreatureTemplate(creature->GetEntry());
    if (!cInfo)
        return false;

    uint8 effectiveLevel = std::max<uint8>(creature->GetLevel(), scale.level);
    CreatureBaseStats const* stats = sObjectMgr->GetCreatureBaseStats(effectiveLevel, cInfo->unit_class);
    if (!stats)
        return false;

    creature->SetLevel(effectiveLevel);

    uint8 expansion = EXPANSION_WRATH_OF_THE_LICH_KING;
    uint32 health = uint32(float(stats->BaseHealth[expansion]) * scale.healthMultiplier *
        HealthMod(int32(cInfo->rank)));
    if (health == 0)
        health = 1;

    creature->SetCreateHealth(health);
    creature->SetMaxHealth(health);
    creature->SetHealth(health);
    creature->SetStatFlatModifier(UNIT_MOD_HEALTH, BASE_VALUE, float(health));
    creature->ResetPlayerDamageReq();

    float manaMultiplier = std::max(1.0f, cInfo->ModMana);
    uint32 mana = uint32(std::ceil(stats->BaseMana * manaMultiplier));
    if (mana > 0)
    {
        creature->SetCreateMana(mana);
        creature->SetMaxPower(POWER_MANA, mana);
        creature->SetPower(POWER_MANA, mana);
        creature->SetStatFlatModifier(UNIT_MOD_MANA, BASE_VALUE, float(mana));
    }

    float armor = std::ceil(stats->BaseArmor * cInfo->ModArmor);
    creature->SetStatFlatModifier(UNIT_MOD_ARMOR, BASE_VALUE, armor);

    float baseDamage = stats->BaseDamage[expansion];
    creature->SetBaseWeaponDamage(BASE_ATTACK, MINDAMAGE, baseDamage);
    creature->SetBaseWeaponDamage(BASE_ATTACK, MAXDAMAGE, baseDamage * 1.5f);
    creature->SetBaseWeaponDamage(OFF_ATTACK, MINDAMAGE, baseDamage);
    creature->SetBaseWeaponDamage(OFF_ATTACK, MAXDAMAGE, baseDamage * 1.5f);
    creature->SetBaseWeaponDamage(RANGED_ATTACK, MINDAMAGE, baseDamage);
    creature->SetBaseWeaponDamage(RANGED_ATTACK, MAXDAMAGE, baseDamage * 1.5f);

    creature->SetStatFlatModifier(UNIT_MOD_ATTACK_POWER, BASE_VALUE, float(stats->AttackPower));
    creature->SetStatFlatModifier(UNIT_MOD_ATTACK_POWER_RANGED, BASE_VALUE, float(stats->RangedAttackPower));

    creature->SetCanModifyStats(true);
    creature->UpdateAllStats();

    CreatureData* creatureData = GetCreatureData(creature);
    creatureData->extraDamageMultiplier = scale.damageMultiplier;
    return true;
}

float MythicPlus::HealthMod(int32 rank) const
{
    switch (rank)
    {
        case CREATURE_ELITE_NORMAL:
            return sWorld->getRate(RATE_CREATURE_NORMAL_HP);
        case CREATURE_ELITE_ELITE:
            return sWorld->getRate(RATE_CREATURE_ELITE_ELITE_HP);
        case CREATURE_ELITE_RAREELITE:
            return sWorld->getRate(RATE_CREATURE_ELITE_RAREELITE_HP);
        case CREATURE_ELITE_WORLDBOSS:
            return sWorld->getRate(RATE_CREATURE_ELITE_WORLDBOSS_HP);
        case CREATURE_ELITE_RARE:
            return sWorld->getRate(RATE_CREATURE_ELITE_RARE_HP);
        default:
            return sWorld->getRate(RATE_CREATURE_ELITE_ELITE_HP);
    }
}

void MythicPlus::ProcessStaticAffixes(std::shared_ptr<MythicLevel const> const& mythicLevel,
    Creature* creature) const
{
    if (!mythicLevel)
        return;

    for (auto const& affix : mythicLevel->affixes)
        affix->HandleStaticEffect(creature);
}

void MythicPlus::ApplyCreature(Map* map, Creature* creature)
{
    if (!map || !creature)
        return;

    MapData* mapData = GetMapData(map, false);
    if (mapData == nullptr || mapData->mythicLevel == nullptr || mapData->done)
        return;

    CreatureData* creatureData = GetCreatureData(creature);
    if (creatureData->processed)
        return;

    if (!CanProcessCreature(creature))
        return;

    bool boss = IsBoss(map->GetId(), creature->GetEntry());
    std::optional<CreatureScale> scale = GetCreatureScale(map->GetId(),
        mapData->mythicLevel->level, boss);
    if (!scale)
    {
        LOG_DEBUG("module.mythic_plus", "No scale for map {} key {} boss {}; creature {} left unscaled",
            map->GetId(), mapData->mythicLevel->level, boss, creature->GetEntry());
        return;
    }

    if (!ScaleCreature(creature, *scale))
        return;

    creatureData->processed = true;
    ProcessStaticAffixes(mapData->mythicLevel, creature);
}

void MythicPlus::ApplyRunStart(Map* map)
{
    if (!map)
        return;

    std::vector<Creature*> creatures;
    for (auto const& entry : map->GetCreatureBySpawnIdStore())
        if (entry.second)
            creatures.push_back(entry.second);

    for (Creature* creature : creatures)
        ApplyCreature(map, creature);
}

void MythicPlus::Reward(Player* player, MythicReward const& reward) const
{
    if (player && reward.money > 0)
        player->ModifyMoney(int32(reward.money));
}

void MythicPlus::ProcessConfig(bool reload)
{
    if (!reload)
        enabled = sConfigMgr->GetOption<bool>("MythicPlus.Enable", true);

    penaltyOnDeath = sConfigMgr->GetOption<uint32>("MythicPlus.Penalty.OnDeath", 5);
}

/*static*/ std::string MythicPlus::Utils::Colored(std::string const& message, std::string const& hexColor)
{
    std::ostringstream oss;
    oss << "|cff" << hexColor << message << "|r";
    return oss.str();
}

/*static*/ std::string MythicPlus::Utils::RedColored(std::string const& message)
{
    return Colored(message, "b50505");
}

/*static*/ std::string MythicPlus::Utils::GreenColored(std::string const& message)
{
    return Colored(message, "0d852d");
}

/*static*/ std::string MythicPlus::Utils::FormatFloat(float val, uint32 decimals)
{
    std::ostringstream oss;
    oss << std::fixed << std::setprecision(decimals) << val;
    return oss.str();
}

/*static*/ bool MythicPlus::Utils::IsGroupLeader(Player const* player)
{
    Group const* group = player ? player->GetGroup() : nullptr;
    if (group == nullptr)
        return false;

    return group->GetLeaderGUID() == player->GetGUID();
}

/*static*/ uint32 MythicPlus::Utils::PlayerGUID(Player const* player)
{
    return player ? player->GetGUID().GetCounter() : 0;
}

/*static*/ uint64 MythicPlus::Utils::GameTimeMs()
{
    return uint64(GameTime::GetGameTimeMS().count());
}
