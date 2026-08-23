using Microsoft.EntityFrameworkCore;
using Backend.Models;

namespace Backend.Data;

public class AppDbContext : DbContext
{
  public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }
  public DbSet<PlayerProfileObj> Players { get; set; }
  public DbSet<OtpVerification> OtpCodes { get; set; }
  public DbSet<PlayerSession> PlayerSessions { get; set; }

  protected override void OnModelCreating(ModelBuilder modelBuilder)
  {
      // Tell PostgreSQL to use unique player id (pid) as Primary Key table constraint
      modelBuilder.Entity<PlayerProfileObj>().HasKey(p => p.email);
      modelBuilder.Entity<OtpVerification>().HasKey(o => o.email);
      modelBuilder.Entity<PlayerSession>().HasKey(p => p.token);
  }
}