using System.Security.Cryptography;
using System.Text;

namespace Backend.Utils;

public class SecurityUtils
{
    private readonly string _serverPepper;

    public SecurityUtils(IConfiguration configuration)
    {
        _serverPepper = configuration["SecuritySettings:ServerPepper"] 
            ?? throw new InvalidOperationException("Cryptographic ServerPepper environment variable is missing!");
    }

    // Deterministic hash to allow database indexing and row lookups
    public string HashEmail(string email)
    {
        string normalizedEmail = email.Trim().ToLowerInvariant();
        using var hmac = new HMACSHA256(Encoding.UTF8.GetBytes(_serverPepper));
        byte[] hashBytes = hmac.ComputeHash(Encoding.UTF8.GetBytes(normalizedEmail));
        return Convert.ToHexString(hashBytes);
    }

    // Standard one-way hash for short lived validation data (OTPs and Session Tokens)
    public string ComputeSha256(string input)
    {
        byte[] inputBytes = Encoding.UTF8.GetBytes(input);
        byte[] hashBytes = SHA256.HashData(inputBytes);
        return Convert.ToHexString(hashBytes);
    }
}