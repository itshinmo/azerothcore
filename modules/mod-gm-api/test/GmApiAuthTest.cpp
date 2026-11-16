#include "GmApiAuth.h"
#include "GmApiBody.h"

#include <gtest/gtest.h>

TEST(GmApiAuthTest, CanonicalString)
{
    EXPECT_EQ(GmApiAuth::Canonical("1700000000", "0123456789abcdef", "GET", "/api/v1/status"),
        "1700000000\n0123456789abcdef\nGET\n/api/v1/status");
}

TEST(GmApiAuthTest, SignatureKnownValue)
{
    std::string const canonical = GmApiAuth::Canonical(
        "1700000000", "0123456789abcdef", "GET", "/api/v1/status");
    EXPECT_EQ(GmApiAuth::Signature("0123456789abcdef0123456789abcdef", canonical),
        "8e0c392080b60b7b31980af50079b3f11da28a36425f5f21f767b1dd46ae66f9");
}

TEST(GmApiAuthTest, CanonicalStringWithActor)
{
    EXPECT_EQ(GmApiAuth::Canonical("1700000000", "0123456789abcdef", "POST",
                  "/api/v1/players/Thrall/kick", "42"),
        "1700000000\n0123456789abcdef\nPOST\n/api/v1/players/Thrall/kick\n42");
}

TEST(GmApiAuthTest, ActorValidation)
{
    EXPECT_FALSE(GmApiAuth::ValidActor(""));
    EXPECT_FALSE(GmApiAuth::ValidActor("0"));
    EXPECT_FALSE(GmApiAuth::ValidActor("12a"));
    EXPECT_FALSE(GmApiAuth::ValidActor("4294967296"));
    EXPECT_TRUE(GmApiAuth::ValidActor("1"));
    EXPECT_TRUE(GmApiAuth::ValidActor("4294967295"));
}

TEST(GmApiAuthTest, PlayerTargetParsing)
{
    std::string action;
    std::string player;

    EXPECT_TRUE(GmApiAuth::ParsePlayerTarget("/api/v1/players/Thrall/kick", action, player));
    EXPECT_EQ(action, "kick");
    EXPECT_EQ(player, "Thrall");

    EXPECT_TRUE(GmApiAuth::ParsePlayerTarget("/api/v1/players/Jaina2/unstuck", action, player));
    EXPECT_EQ(action, "unstuck");
    EXPECT_EQ(player, "Jaina2");

    EXPECT_FALSE(GmApiAuth::ParsePlayerTarget("/api/v1/players//kick", action, player));
    EXPECT_FALSE(GmApiAuth::ParsePlayerTarget("/api/v1/players/Thrall/ban", action, player));
    EXPECT_FALSE(GmApiAuth::ParsePlayerTarget("/api/v1/players/Thrall", action, player));
    EXPECT_FALSE(GmApiAuth::ParsePlayerTarget("/api/v1/players/Th r/all/kick", action, player));
    EXPECT_FALSE(GmApiAuth::ParsePlayerTarget("/api/v1/status", action, player));
}

TEST(GmApiAuthTest, TimestampWindow){
    EXPECT_TRUE(GmApiAuth::TimestampInWindow(1000, 1000, 60));
    EXPECT_TRUE(GmApiAuth::TimestampInWindow(1000, 940, 60));
    EXPECT_TRUE(GmApiAuth::TimestampInWindow(1000, 1060, 60));
    EXPECT_FALSE(GmApiAuth::TimestampInWindow(1000, 939, 60));
    EXPECT_FALSE(GmApiAuth::TimestampInWindow(1000, 1061, 60));
}

TEST(GmApiAuthTest, NonceLength)
{
    EXPECT_FALSE(GmApiAuth::ValidNonce("1234567"));
    EXPECT_TRUE(GmApiAuth::ValidNonce("12345678"));
    EXPECT_TRUE(GmApiAuth::ValidNonce(std::string(128, 'a')));
    EXPECT_FALSE(GmApiAuth::ValidNonce(std::string(129, 'a')));
}

TEST(GmApiAuthTest, LimitParsing)
{
    EXPECT_EQ(GmApiAuth::ParseLimit("/api/v1/audit"), 50);
    EXPECT_EQ(GmApiAuth::ParseLimit("/api/v1/audit?limit=10"), 10);
    EXPECT_EQ(GmApiAuth::ParseLimit("/api/v1/audit?x=1&limit=20"), 20);
    EXPECT_EQ(GmApiAuth::ParseLimit("/api/v1/audit?limit=500"), 200);
    EXPECT_EQ(GmApiAuth::ParseLimit("/api/v1/audit?limit=4294967296"), 200);
    EXPECT_EQ(GmApiAuth::ParseLimit("/api/v1/audit?limit=0"), 50);
    EXPECT_EQ(GmApiAuth::ParseLimit("/api/v1/audit?limit=abc"), 50);
    EXPECT_EQ(GmApiAuth::ParseLimit("/api/v1/audit?notlimit=5"), 50);
}

TEST(GmApiAuthTest, BoundedLimitParsing)
{
    EXPECT_EQ(GmApiAuth::ParseLimit("/api/v1/players/online", 100, 500), 100);
    EXPECT_EQ(GmApiAuth::ParseLimit("/api/v1/players/online?limit=25", 100, 500), 25);
    EXPECT_EQ(GmApiAuth::ParseLimit("/api/v1/players/online?limit=900", 100, 500), 500);
    EXPECT_EQ(GmApiAuth::ParseLimit("/api/v1/instances", 100, 100), 100);
    EXPECT_EQ(GmApiAuth::ParseLimit("/api/v1/instances?limit=1", 100, 100), 1);
    EXPECT_EQ(GmApiAuth::ParseLimit("/api/v1/instances?limit=101", 100, 100), 100);
}

TEST(GmApiAuthTest, TargetPath)
{
    EXPECT_EQ(GmApiAuth::TargetPath("/api/v1/audit?limit=10"), "/api/v1/audit");
    EXPECT_EQ(GmApiAuth::TargetPath("/api/v1/status"), "/api/v1/status");
    EXPECT_EQ(GmApiAuth::TargetPath("/api/v1/players/Thrall/items?x=1"),
        "/api/v1/players/Thrall/items");
}

TEST(GmApiAuthTest, PlayerItemsTargetParsing)
{
    std::string player;

    EXPECT_TRUE(GmApiAuth::ParsePlayerItemsTarget("/api/v1/players/Thrall/items", player));
    EXPECT_EQ(player, "Thrall");

    EXPECT_FALSE(GmApiAuth::ParsePlayerItemsTarget("/api/v1/players/Thrall/items/1", player));
    EXPECT_FALSE(GmApiAuth::ParsePlayerItemsTarget("/api/v1/players//items", player));
    EXPECT_FALSE(GmApiAuth::ParsePlayerItemsTarget("/api/v1/players/Thrall/kick", player));
}

TEST(GmApiAuthTest, AccountActionTargetParsing)
{
    std::string action;
    std::string account;

    EXPECT_TRUE(GmApiAuth::ParseAccountActionTarget("/api/v1/accounts/ADMIN/ban", action, account));
    EXPECT_EQ(action, "ban");
    EXPECT_EQ(account, "ADMIN");

    EXPECT_TRUE(GmApiAuth::ParseAccountActionTarget("/api/v1/accounts/GM_1/permissions", action,
        account));
    EXPECT_EQ(action, "permissions");
    EXPECT_EQ(account, "GM_1");

    EXPECT_FALSE(GmApiAuth::ParseAccountActionTarget("/api/v1/accounts/ADMIN/kick", action, account));
    EXPECT_FALSE(GmApiAuth::ParseAccountActionTarget("/api/v1/accounts//ban", action, account));
    EXPECT_FALSE(GmApiAuth::ParseAccountActionTarget("/api/v1/accounts/ADMIN", action, account));
}

TEST(GmApiAuthTest, AccountReadTargetParsing)
{
    std::string account;

    EXPECT_TRUE(GmApiAuth::ParseAccountReadTarget("/api/v1/accounts/ADMIN", account));
    EXPECT_EQ(account, "ADMIN");

    EXPECT_TRUE(GmApiAuth::ParseAccountReadTarget("/api/v1/accounts/42", account));
    EXPECT_EQ(account, "42");

    EXPECT_FALSE(GmApiAuth::ParseAccountReadTarget("/api/v1/accounts/AD MIN", account));
    EXPECT_FALSE(GmApiAuth::ParseAccountReadTarget("/api/v1/accounts/ADMIN/ban", account));
    EXPECT_FALSE(GmApiAuth::ParseAccountReadTarget("/api/v1/characters/Thrall", account));
}

TEST(GmApiAuthTest, CharacterReadTargetParsing)
{
    std::string name;

    EXPECT_TRUE(GmApiAuth::ParseCharacterTarget("/api/v1/characters/Thrall", name));
    EXPECT_EQ(name, "Thrall");

    EXPECT_FALSE(GmApiAuth::ParseCharacterTarget("/api/v1/characters/Th r", name));
    EXPECT_FALSE(GmApiAuth::ParseCharacterTarget("/api/v1/characters/Thrall/items", name));
    EXPECT_FALSE(GmApiAuth::ParseCharacterTarget("/api/v1/players/Thrall", name));
}

TEST(GmApiBodyTest, ItemGrant)
{
    GmApiBody::ItemGrantRequest request;
    std::string error;

    EXPECT_TRUE(GmApiBody::ParseItemGrant(R"({"itemId":19019,"count":1})", request, error));
    EXPECT_EQ(request.itemId, 19019u);
    EXPECT_EQ(request.count, 1u);
    EXPECT_TRUE(error.empty());

    EXPECT_FALSE(GmApiBody::ParseItemGrant(R"({"itemId":19019,"count":0})", request, error));
    EXPECT_EQ(error, "bad_request");

    EXPECT_FALSE(GmApiBody::ParseItemGrant(R"({"itemId":19019,"count":1001})", request, error));
    EXPECT_EQ(error, "bad_request");

    EXPECT_FALSE(GmApiBody::ParseItemGrant(R"({"itemId":0,"count":1})", request, error));
    EXPECT_EQ(error, "invalid_item");

    EXPECT_FALSE(GmApiBody::ParseItemGrant(R"({"count":1})", request, error));
    EXPECT_FALSE(GmApiBody::ParseItemGrant("not json", request, error));
}

TEST(GmApiBodyTest, MailRequest)
{
    GmApiBody::MailRequest request;
    std::string error;

    EXPECT_TRUE(GmApiBody::ParseMail(
        R"({"recipient":"Thrall","subject":"Welcome","text":"Hello","money":100,)"
        R"("items":[{"itemId":19019,"count":2}]})",
        request, error));
    EXPECT_EQ(request.recipient, "Thrall");
    EXPECT_EQ(request.subject, "Welcome");
    EXPECT_EQ(request.text, "Hello");
    EXPECT_EQ(request.money, 100u);
    ASSERT_EQ(request.items.size(), 1u);
    EXPECT_EQ(request.items[0].itemId, 19019u);
    EXPECT_EQ(request.items[0].count, 2u);

    request = GmApiBody::MailRequest{};
    EXPECT_TRUE(GmApiBody::ParseMail(R"({"recipient":"Thrall"})", request, error));
    EXPECT_EQ(request.money, 0u);
    EXPECT_TRUE(request.items.empty());

    EXPECT_FALSE(GmApiBody::ParseMail(
        R"({"recipient":"Thrall","subject":")" + std::string(65, 'a') + R"("})", request, error));
    EXPECT_FALSE(GmApiBody::ParseMail(
        R"({"recipient":"Thrall","text":")" + std::string(5001, 'a') + R"("})", request, error));
    EXPECT_FALSE(GmApiBody::ParseMail(
        R"({"recipient":"Thrall","money":2147483647})", request, error));
    EXPECT_FALSE(GmApiBody::ParseMail(
        R"({"recipient":"Thrall","items":[{"itemId":0,"count":1}]})", request, error));
    EXPECT_EQ(error, "invalid_item");

    std::string tooMany = R"({"recipient":"Thrall","items":[)";
    for (uint32 i = 0; i < 12; ++i)
    {
        if (i != 0)
            tooMany += ",";
        tooMany += R"({"itemId":19019,"count":1})";
    }
    tooMany += "]}";
    EXPECT_TRUE(GmApiBody::ParseMail(tooMany, request, error));
    EXPECT_EQ(request.items.size(), 12u);

    tooMany.insert(tooMany.size() - 2, R"(,{"itemId":19019,"count":1})");
    EXPECT_FALSE(GmApiBody::ParseMail(tooMany, request, error));
    EXPECT_EQ(error, "too_many_items");

    std::string const sixtyFour = std::string(64, '\xC3') + std::string(64, '\xA9');
    EXPECT_TRUE(GmApiBody::ParseMail(
        R"({"recipient":"Thrall","subject":")" + sixtyFour + R"("})", request, error));

    std::string const sixtyFive = std::string(65, '\xC3') + std::string(65, '\xA9');
    EXPECT_FALSE(GmApiBody::ParseMail(
        R"({"recipient":"Thrall","subject":")" + sixtyFive + R"("})", request, error));
}

TEST(GmApiBodyTest, BanRequest)
{
    GmApiBody::BanRequest request;
    std::string error;

    EXPECT_TRUE(GmApiBody::ParseBan(R"({"durationSeconds":3600,"reason":"Cheating"})",
        request, error));
    EXPECT_EQ(request.durationSeconds, 3600u);
    EXPECT_EQ(request.reason, "Cheating");

    EXPECT_TRUE(GmApiBody::ParseBan(R"({"durationSeconds":0})", request, error));
    EXPECT_EQ(request.durationSeconds, 0u);

    EXPECT_FALSE(GmApiBody::ParseBan(R"({"durationSeconds":315360001})", request, error));
    EXPECT_FALSE(GmApiBody::ParseBan(
        R"({"durationSeconds":1,"reason":")" + std::string(256, 'a') + R"("})", request, error));
    EXPECT_FALSE(GmApiBody::ParseBan(R"({"reason":"Cheating"})", request, error));
}

TEST(GmApiBodyTest, PermissionRequest)
{
    GmApiBody::PermissionRequest request;
    std::string error;

    EXPECT_TRUE(GmApiBody::ParsePermission(R"({"action":"grant","permissionId":488})",
        request, error));
    EXPECT_EQ(request.action, "grant");
    EXPECT_EQ(request.permissionId, 488u);
    EXPECT_EQ(request.realmId, -1);

    EXPECT_TRUE(GmApiBody::ParsePermission(
        R"({"action":"revoke","permissionId":488,"realmId":1})", request, error));
    EXPECT_EQ(request.realmId, 1);

    EXPECT_FALSE(GmApiBody::ParsePermission(R"({"action":"allow","permissionId":488})",
        request, error));
    EXPECT_FALSE(GmApiBody::ParsePermission(R"({"action":"grant","permissionId":0})",
        request, error));
    EXPECT_FALSE(GmApiBody::ParsePermission(
        R"({"action":"grant","permissionId":488,"realmId":0})", request, error));
    EXPECT_FALSE(GmApiBody::ParsePermission(
        R"({"action":"grant","permissionId":488,"realmId":-2})", request, error));
    EXPECT_FALSE(GmApiBody::ParsePermission(
        R"({"action":"grant","permissionId":4294967296})", request, error));
}

TEST(GmApiBodyTest, ServerControlRequest)
{
    GmApiBody::ServerControlRequest request;
    std::string error;

    EXPECT_TRUE(GmApiBody::ParseServerControl(
        R"({"action":"shutdown","delaySeconds":60,"reason":"Maintenance"})", request, error));
    EXPECT_EQ(request.action, "shutdown");
    EXPECT_EQ(request.delaySeconds, 60u);
    EXPECT_EQ(request.reason, "Maintenance");

    EXPECT_TRUE(GmApiBody::ParseServerControl(
        R"({"action":"cancel","delaySeconds":1})", request, error));
    EXPECT_TRUE(GmApiBody::ParseServerControl(
        R"({"action":"cancel"})", request, error));
    EXPECT_EQ(request.delaySeconds, 0u);

    EXPECT_FALSE(GmApiBody::ParseServerControl(
        R"({"action":"stop","delaySeconds":60})", request, error));
    EXPECT_FALSE(GmApiBody::ParseServerControl(
        R"({"action":"shutdown","delaySeconds":0})", request, error));
    EXPECT_FALSE(GmApiBody::ParseServerControl(
        R"({"action":"shutdown","delaySeconds":3601})", request, error));
}
