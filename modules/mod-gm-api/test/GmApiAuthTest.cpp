#include "GmApiAuth.h"

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

TEST(GmApiAuthTest, TimestampWindow)
{
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
