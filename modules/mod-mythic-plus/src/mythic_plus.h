/*
 * Credits: silviu20092
 *
 * Forked from https://github.com/silviu20092/mod-mythic-plus (MIT), commit e2a487d.
 */

#ifndef _MYTHIC_PLUS_H_
#define _MYTHIC_PLUS_H_

#include "ObjectGuid.h"
#include "Player.h"
#include <atomic>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

class Creature;
class Map;
class MapEntry;

class MythicAffix;

struct MythicReward
{
    uint32 money = 0;
};

struct MythicLevel
{
    uint32 level = 0;
    uint32 timeLimit = 0;
    MythicReward reward;
    std::vector<std::unique_ptr<MythicAffix>> affixes;
};

struct CreatureScale
{
    uint8 level = 80;
    float healthMultiplier = 1.0f;
    float damageMultiplier = 1.0f;
};

class MythicPlus
{
private:
    MythicPlus();
    ~MythicPlus() = default;

public:
    static constexpr uint8 MYTHIC_PLUS_ERA_CLASSIC = 0;
    static constexpr uint32 MAX_KEY_LEVEL = 5;
    static constexpr uint8 MAX_PROGRESSION_KEY = 20;
    static constexpr uint32 PRESTART_TIMEOUT_MS = 15 * 60 * 1000;

    class MapData : public DataMap::Base
    {
    public:
        std::shared_ptr<MythicLevel const> mythicLevel;
        uint8 era = MYTHIC_PLUS_ERA_CLASSIC;
        std::vector<ObjectGuid> members;
        std::unordered_set<uint32> leftMembers;
        uint64 prestartDeadlineMs = 0;
        uint64 startTimeMs = 0;
        uint32 timeLimit = 0;
        uint32 deaths = 0;
        uint32 penaltyOnDeath = 5;
        bool started = false;
        bool done = false;
        bool receiveLoot = true;
        bool preCleared = false;
        bool spawningCopy = false;

        [[nodiscard]] uint32 GetPenaltyTime() const
        {
            return penaltyOnDeath * deaths;
        }

        [[nodiscard]] uint64 GetElapsedMs() const;
    };

    class CreatureData : public DataMap::Base
    {
    public:
        bool processed = false;
        bool copy = false;
        float extraDamageMultiplier = 1.0f;
    };

    struct MythicPlusDungeonInfo
    {
        uint32 instanceId = 0;
        uint32 mapId = 0;
        uint32 timeLimit = 0;
        uint64 startTimeMs = 0;
        uint64 prestartDeadlineMs = 0;
        uint32 mythicLevel = 0;
        uint32 penaltyOnDeath = 5;
        uint32 deaths = 0;
        uint8 era = MYTHIC_PLUS_ERA_CLASSIC;
        bool done = false;
        std::vector<ObjectGuid> members;
        std::unordered_set<uint32> leftMembers;
    };

    struct MythicPlusCapableDungeon
    {
        uint32 map = 0;
        uint8 era = MYTHIC_PLUS_ERA_CLASSIC;
        uint32 finalBossEntry = 0;
    };

    class Utils
    {
    public:
        static std::string Colored(std::string const& message, std::string const& hexColor);
        static std::string RedColored(std::string const& message);
        static std::string GreenColored(std::string const& message);
        static std::string FormatFloat(float val, uint32 decimals = 2);
        static bool IsGroupLeader(Player const* player);
        static uint32 PlayerGUID(Player const* player);
        static uint64 GameTimeMs();
    };

    static MythicPlus* instance();

    static void BroadcastToPlayer(Player const* player, std::string const& message);
    static void AnnounceToPlayer(Player const* player, std::string const& message);
    static void AnnounceToMap(Map const* map, std::string const& message);
    static void BroadcastToMap(Map const* map, std::string const& message);
    static void FallbackTeleport(Player* player);

    MapData* GetMapData(Map* map, bool withDefault = true) const;
    CreatureData* GetCreatureData(Creature* creature, bool withDefault = true) const;

    [[nodiscard]] bool IsEnabled() const
    {
        return enabled.load();
    }

    [[nodiscard]] bool CanMapBeMythicPlus(Map const* map) const;
    [[nodiscard]] bool CanProcessCreature(Creature* creature) const;
    [[nodiscard]] bool IsMapInMythicPlus(Map const* map) const;
    [[nodiscard]] bool IsBoss(uint32 mapId, uint32 entry) const;
    [[nodiscard]] bool IsFinalBoss(uint32 mapId, uint32 entry) const;
    [[nodiscard]] bool HasActiveRuns() const;

    void LoadFromDB();
    bool ReloadTables();
    void ProcessConfig(bool reload);

    [[nodiscard]] std::shared_ptr<MythicLevel const> GetMythicLevel(uint32 level) const;
    [[nodiscard]] size_t GetMythicLevelCount() const;
    [[nodiscard]] std::optional<CreatureScale> GetCreatureScale(uint32 mapId, uint32 keyLevel, bool boss) const;
    [[nodiscard]] size_t GetCreatureScaleCount() const;
    [[nodiscard]] size_t GetCapableDungeonCount() const;
    [[nodiscard]] size_t GetBossCount() const;

    [[nodiscard]] uint32 GetPenaltyOnDeath() const
    {
        return penaltyOnDeath.load();
    }

    [[nodiscard]] uint8 GetEraForMap(uint32 mapId) const;
    [[nodiscard]] uint8 GetHighestKey(uint32 guid, uint8 era) const;
    [[nodiscard]] uint8 GetNextKey(uint32 guid, uint8 era) const;
    void SetHighestKey(uint32 guid, uint8 era, uint8 key);

    [[nodiscard]] bool CheckGroupForStart(Player const* player) const;
    bool StartRun(Player* player, uint32 keyLevel);
    void StartTimer(Map* map);
    void CompleteRun(Map* map, Creature* finalBoss);
    void AbortRun(Map* map, std::string const& reason);
    void BlockPreClearedInstance(Map* map);
    void MarkMemberLeft(Map* map, ObjectGuid guid);

    bool ScaleCreature(Creature* creature, CreatureScale const& scale) const;
    void ProcessStaticAffixes(std::shared_ptr<MythicLevel const> const& mythicLevel, Creature* creature) const;
    void ApplyCreature(Map* map, Creature* creature);
    void ApplyRunStart(Map* map);

    [[nodiscard]] std::optional<MythicPlusDungeonInfo> GetSavedDungeonInfo(uint32 instanceId) const;
    void SaveDungeonInfo(MythicPlusDungeonInfo const& info);
    void RemoveDungeonInfo(uint32 instanceId);
    void RestoreMapData(Map* map, MythicPlusDungeonInfo const& saved);
    [[nodiscard]] bool IsRunMember(MapData const* mapData, ObjectGuid guid) const;
    [[nodiscard]] bool IsMemberEligible(MapData const* mapData, ObjectGuid guid) const;

private:
    struct DBAffix
    {
        uint32 level = 0;
        uint16 affixType = 0;
        float val1 = 0.0f;
        float val2 = 0.0f;
    };

    struct DBReward
    {
        uint32 level = 0;
        uint32 val1 = 0;
    };

    struct WorldData
    {
        std::unordered_map<uint32, MythicPlusCapableDungeon> dungeons;
        std::unordered_set<uint64> bosses;
        std::unordered_set<uint64> finalBosses;
        std::unordered_map<uint64, CreatureScale> scales;
        std::vector<std::shared_ptr<MythicLevel>> levels;
    };

    void ClearRunRows();
    bool LoadWorldData(WorldData& data);
    bool LoadCapableDungeonsFromDB(WorldData& data);
    bool LoadBossesFromDB(WorldData& data);
    bool LoadCreatureScalesFromDB(WorldData& data);
    bool LoadLevelsFromDB(WorldData& data);
    void LoadProgressFromDB();
    void SaveMapInfo(Map* map);
    void Reward(Player* player, MythicReward const& reward) const;
    [[nodiscard]] float HealthMod(int32 rank) const;
    [[nodiscard]] static uint64 ScaleKey(uint32 mapId, uint32 keyLevel, bool boss);
    [[nodiscard]] static uint64 ProgressKey(uint32 guid, uint8 era);

    // Guards the module-wide data below. Lock only for container access. Never hold it across a
    // database call: copy values under the lock, release it, then read or write the database.
    mutable std::mutex _dataMutex;
    std::unordered_map<uint32, MythicPlusCapableDungeon> mythicPlusDungeons;
    std::unordered_set<uint64> bossEntries;
    std::unordered_set<uint64> finalBossEntries;
    std::unordered_map<uint64, CreatureScale> creatureScales;
    std::vector<std::shared_ptr<MythicLevel>> mythicLevels;
    std::unordered_map<uint32, MythicPlusDungeonInfo> mythicPlusDungeonInfo;
    std::unordered_map<uint64, uint8> charHighestKeys;
    std::atomic<bool> enabled{ true };
    std::atomic<uint32> penaltyOnDeath{ 5 };
};

#define sMythicPlus MythicPlus::instance()

#endif
