using System.Security.Cryptography;
using System.Text;

namespace Backend.Utils;

public class SecurityUtils {
  private readonly string _serverPepper;

  public SecurityUtils(IConfiguration configuration) {
    _serverPepper = configuration["SecuritySettings:ServerPepper"] 
      ?? throw new InvalidOperationException("Cryptographic ServerPepper environment variable is missing!");
  }

  // Deterministic hash to allow database indexing and row lookups
  public string HashEmail(string email) {
    string normalizedEmail = email.Trim().ToLowerInvariant();
    using var hmac = new HMACSHA256(Encoding.UTF8.GetBytes(_serverPepper));
    byte[] hashBytes = hmac.ComputeHash(Encoding.UTF8.GetBytes(normalizedEmail));
    return Convert.ToHexString(hashBytes);
  }

  // Standard one-way hash for short lived validation data (OTPs and Session Tokens)
  public string ComputeSha256(string input) {
    byte[] inputBytes = Encoding.UTF8.GetBytes(input);
    byte[] hashBytes = SHA256.HashData(inputBytes);
    return Convert.ToHexString(hashBytes);
  }
}

public class EncryptionUtils {
  private readonly byte[] _encryptionKey;
  public EncryptionUtils(IConfiguration configuration) {
    string rawKey = configuration["SecuritySettings:AesKey"] 
      ?? throw new InvalidOperationException("Missing AesKey configuration string.");
    // AES-256 requires a precise 32-byte (256-bit) key signature length
    _encryptionKey = Encoding.UTF8.GetBytes(rawKey.PadRight(32).Substring(0, 32));
  }

  public string Encrypt(string plainText) {
    if (string.IsNullOrEmpty(plainText)) return string.Empty;

    using var aes = Aes.Create();
    aes.Key = _encryptionKey;
    aes.GenerateIV(); // Unique random signature per entry row

    using var encryptor = aes.CreateEncryptor(aes.Key, aes.IV);
    using var ms = new MemoryStream();
    
    // Write the raw unencrypted IV signature to the front of the stream
    ms.Write(aes.IV, 0, aes.IV.Length);

    using (var cs = new CryptoStream(ms, encryptor, CryptoStreamMode.Write))
    using (var sw = new StreamWriter(cs)) {
      sw.Write(plainText);
    }
    // Return a clean Base64 string safe for text fields in database engines
    return Convert.ToBase64String(ms.ToArray());
  }

  public string Decrypt(string cipherText) {
    if (string.IsNullOrEmpty(cipherText)) return string.Empty;

    try {
      byte[] fullCipher = Convert.FromBase64String(cipherText);
      using var aes = Aes.Create();
      aes.Key = _encryptionKey;

      byte[] iv = new byte[aes.BlockSize / 8];
      byte[] cipherBytes = new byte[fullCipher.Length - iv.Length];

      // Slice apart the IV and encrypted payload data blocks
      Buffer.BlockCopy(fullCipher, 0, iv, 0, iv.Length);
      Buffer.BlockCopy(fullCipher, iv.Length, cipherBytes, 0, cipherBytes.Length);

      using var decryptor = aes.CreateDecryptor(aes.Key, iv);
      using var ms = new MemoryStream(cipherBytes);
      using var cs = new CryptoStream(ms, decryptor, CryptoStreamMode.Read);
      using var sr = new StreamReader(cs);

      return sr.ReadToEnd();
    }
    catch (Exception ex) {
      Console.WriteLine($"[CRYPTO WARNING] Failed to decrypt data row (ERR:{ex.Message}). Treating as plain text string: {cipherText}");
      return cipherText;
    }
  }
}
