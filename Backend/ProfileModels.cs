using System.ComponentModel.DataAnnotations;
using Backend.Utils;
using Backend.Dtos;
namespace Backend.Models;

public class OtpVerification {
  [Key] public string emailHash { get; set; } = string.Empty;
  [Required] public string codeHash { get; set; } = string.Empty;
  public DateTime expiresAt { get; set; }
}

public class PlayerSession {
  [Key]
  public string tokenHash { get; set; } = string.Empty; // Random Secure Guid string
  [Required]
  public string emailHash { get; set; } = string.Empty;
  public DateTime expiresAt { get; set; }
}

public class PlayerProfileObj {
  // player identification
  [Key]
  public string emailHash { get; set; } = string.Empty;
  [Required]
  [MaxLength(50)]
  public string name { get; set; } = string.Empty;

  // Game Data
  //// General Player Data
  public float money { get; set; } = 100.0f;
  public int dayCount { get; set; } = 1;
  //// Day Inventory
  public int lemonStock { get; set; } = 0;
  public int sugarStock { get; set; } = 0;
  public int iceStock { get; set; } = 0;
  //// Recipe Data
  public int recipeLemons { get; set; } = 0;
  public int recipeSugar { get; set; } = 0;
  public int recipeIce { get; set; } = 0;
  public float salePrice { get; set; } = 0.50f;

  public object ToResponsePayload(EncryptionUtils encryptionUtils) {
    // Decrypt the player username securely on demand
    string decryptedName = encryptionUtils.Decrypt(name);
    return new {
      name = decryptedName,
      money, dayCount,
      lemonStock, sugarStock, iceStock,
      recipeLemons, recipeSugar, recipeIce,
      salePrice
    };
  }

  public void ApplySyncUpdate(PlayerSyncRequest request, EncryptionUtils encryptionUtils) {
    name = encryptionUtils.Encrypt(request.name);
    money = request.state.money;
    dayCount = request.state.dayCount;
    lemonStock = request.state.lemonStock;
    sugarStock = request.state.sugarStock;
    iceStock = request.state.iceStock;
    recipeLemons = request.state.recipeLemons;
    recipeSugar = request.state.recipeSugar;
    recipeIce = request.state.recipeIce;
    salePrice = request.state.salePrice;
  }
}