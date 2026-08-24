using System.Security.Cryptography;
using System.Text;

namespace Backend.Utils;

public static class SecurityUtils
{
    // TODO: load from appsettings.json or env var
    private const string ServerPepper = "YourSuperSecretCryptoPepper1234567890!";

    // Deterministic hash to allow database indexing and row lookups
    public static string HashEmail(string email)
    {
        string normalizedEmail = email.Trim().ToLowerInvariant();
        using var hmac = new HMACSHA256(Encoding.UTF8.GetBytes(ServerPepper));
        byte[] hashBytes = hmac.ComputeHash(Encoding.UTF8.GetBytes(normalizedEmail));
        return Convert.ToHexString(hashBytes);
    }

    // Standard one-way hash for short lived validation data (OTPs and Session Tokens)
    public static string ComputeSha256(string input)
    {
        byte[] inputBytes = Encoding.UTF8.GetBytes(input);
        byte[] hashBytes = SHA256.HashData(inputBytes);
        return Convert.ToHexString(hashBytes);
    }
}