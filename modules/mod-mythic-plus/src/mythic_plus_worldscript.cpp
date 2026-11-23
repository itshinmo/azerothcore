/*
 * Credits: silviu20092
 */

#include "ScriptMgr.h"
#include "mythic_plus.h"

class mythic_plus_worldscript : public WorldScript
{
public:
    mythic_plus_worldscript() : WorldScript("mythic_plus_worldscript",
        {
            WORLDHOOK_ON_BEFORE_WORLD_INITIALIZED,
            WORLDHOOK_ON_AFTER_CONFIG_LOAD
        })
    {
    }

    void OnBeforeWorldInitialized() override
    {
        sMythicPlus->LoadFromDB();
    }

    void OnAfterConfigLoad(bool reload) override
    {
        sMythicPlus->ProcessConfig(reload);
    }
};

void AddSC_mythic_plus_worldscript()
{
    new mythic_plus_worldscript();
}
