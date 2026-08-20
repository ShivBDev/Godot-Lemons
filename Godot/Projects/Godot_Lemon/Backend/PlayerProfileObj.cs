using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;
namespace Backend.Models;

public class PlayerProfileObj
{
  // auto gen play ids
  [Key]
  [DatabaseGenerated(DatabaseGeneratedOption.Identity)]
  public int pid { get; set; }
  [Required]
  [MaxLength(50)]
  public string name { get; set; } = string.Empty;
  public int money { get; set; }
}