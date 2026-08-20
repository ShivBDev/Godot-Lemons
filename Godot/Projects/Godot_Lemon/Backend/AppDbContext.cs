using Microsoft.EntityFrameworkCore;
using Backend.Models;

namespace Backend.Data;

public class AppDbContext : DbContext
{
  public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

  // Mapping our Player object to PostgreSQL table named "Players"
  public DbSet<PlayerProfileObj> Players { get; set; }

  protected override void OnModelCreating(ModelBuilder modelBuilder)
  {
      // Tell PostgreSQL to use unique player id (pid) as Primary Key table constraint
      modelBuilder.Entity<PlayerProfileObj>().HasKey(p => p.pid);
  }
}