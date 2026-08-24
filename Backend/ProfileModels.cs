using System.ComponentModel.DataAnnotations;
namespace Backend.Models;

public class PlayerProfileObj {
  // auto gen play ids
  [Key]
  public string emailHash { get; set; } = string.Empty;
  [Required]
  [MaxLength(50)]
  public string name { get; set; } = string.Empty;
  public int money { get; set; }
}

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