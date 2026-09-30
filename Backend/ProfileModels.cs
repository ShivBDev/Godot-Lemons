using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
using System.Text.Json;
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
  public int cupStock { get; set; } = 0;
  //// Recipe Data
  public int recipeLemons { get; set; } = 1;
  public int recipeSugar { get; set; } = 1;
  public int recipeIce { get; set; } = 0;
  public float salePrice { get; set; } = 0.50f;
  // Game State Data
  [Column(TypeName = "jsonb")] public JsonDocument weather { get; set; } = JsonDocument.Parse("{}");
  [Column(TypeName = "jsonb")] public JsonDocument forecast { get; set; } = JsonDocument.Parse("{}");
  [Column(TypeName = "jsonb")] public JsonDocument lemonLots { get; set; } = JsonDocument.Parse("[]");
  [Column(TypeName = "jsonb")] public JsonDocument upgradeLevels { get; set; } = JsonDocument.Parse("{}");
  public string currentArea { get; set; } = "";
  [Column(TypeName = "jsonb")] public JsonDocument popularity { get; set; } = JsonDocument.Parse("{}");
  [Column(TypeName = "jsonb")] public JsonDocument hiredStaff { get; set; } = JsonDocument.Parse("{}");
  public string newsId { get; set; } = "";
  [Column(TypeName = "jsonb")] public JsonDocument stats { get; set; } = JsonDocument.Parse("{}");

  public object ToResponsePayload(EncryptionUtils encryptionUtils) {
    // Decrypt the player username securely on demand
    string decryptedName = encryptionUtils.Decrypt(name);
    return new {
      name = decryptedName,
      money, dayCount,
      lemonStock, sugarStock, iceStock, cupStock,
      recipeLemons, recipeSugar, recipeIce,
      salePrice,
      weather = weather.RootElement, 
      forecast = forecast.RootElement,
      lemonLots = lemonLots.RootElement,
      upgradeLevels = upgradeLevels.RootElement,
      currentArea,
      popularity = popularity.RootElement,
      hiredStaff = hiredStaff.RootElement,
      newsId,
      stats = stats.RootElement
    };
  }

  public void ApplySyncUpdate(PlayerSyncRequest request, EncryptionUtils encryptionUtils) {
    name = encryptionUtils.Encrypt(request.name);
    money = request.state.money;
    dayCount = request.state.dayCount;
    lemonStock = request.state.lemonStock;
    sugarStock = request.state.sugarStock;
    iceStock = request.state.iceStock;
    cupStock = request.state.cupStock;
    recipeLemons = request.state.recipeLemons;
    recipeSugar = request.state.recipeSugar;
    recipeIce = request.state.recipeIce;
    salePrice = request.state.salePrice;
    weather = JsonDocument.Parse(JsonSerializer.Serialize(request.state.weather));
    forecast = JsonDocument.Parse(JsonSerializer.Serialize(request.state.forecast));
    lemonLots = JsonDocument.Parse(JsonSerializer.Serialize(request.state.lemonLots));
    upgradeLevels = JsonDocument.Parse(JsonSerializer.Serialize(request.state.upgradeLevels));
    currentArea = request.state.currentArea;
    popularity = JsonDocument.Parse(JsonSerializer.Serialize(request.state.popularity));
    hiredStaff = JsonDocument.Parse(JsonSerializer.Serialize(request.state.hiredStaff));
    newsId = request.state.newsId;
    stats = JsonDocument.Parse(JsonSerializer.Serialize(request.state.stats));
  }
}