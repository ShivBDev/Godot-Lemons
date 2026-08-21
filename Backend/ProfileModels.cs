using System.ComponentModel.DataAnnotations;
namespace Backend.Models;

public class PlayerProfileObj {
  // auto gen play ids
  [Key]
  public string email { get; set; } = string.Empty;
  [Required]
  [MaxLength(50)]
  public string name { get; set; } = string.Empty;
  public int money { get; set; }
  public bool isVerified { get; set; } = false;
}

public class OtpVerification {
  [Key] public string email { get; set; } = string.Empty;
  [Required] public string codeHash { get; set; } = string.Empty;
  public DateTime expiresAt { get; set; }
}