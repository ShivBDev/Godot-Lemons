using Backend.Data;
using Microsoft.EntityFrameworkCore;

namespace Backend.Services;

public class SessionCleanupService : BackgroundService {
  private readonly IServiceScopeFactory _scopeFactory;
  private readonly ILogger<SessionCleanupService> _logger;
  // Wake up once every 24 hours to clear data
  private readonly TimeSpan _cleanupInterval = TimeSpan.FromHours(24);

  public SessionCleanupService(IServiceScopeFactory scopeFactory, ILogger<SessionCleanupService> logger) {
    _scopeFactory = scopeFactory;
    _logger = logger;
  }

  protected override async Task ExecuteAsync(CancellationToken stoppingToken) {
    _logger.LogInformation("Session Cleanup Worker initialized and starting continuous loop.");
    while (!stoppingToken.IsCancellationRequested) {
      try {
        using (var scope = _scopeFactory.CreateScope()) {
          var rightNow = DateTime.UtcNow;
          var context = scope.ServiceProvider.GetRequiredService<AppDbContext>();

          // Remove expired player sessions
          var expiredSessions = await context.PlayerSessions
            .Where(s => s.expiresAt < rightNow)
            .ToListAsync(stoppingToken);
          if (expiredSessions.Count > 0) {
            _logger.LogInformation("Found {Count} expired player sessions. Cleaning rows...", expiredSessions.Count);
            context.PlayerSessions.RemoveRange(expiredSessions);
          }
          // Remove expired OTPs
          var expiredOtps = await context.OtpCodes
            .Where(o => o.expiresAt < rightNow)
            .ToListAsync(stoppingToken);
          if (expiredOtps.Count > 0) {
            _logger.LogInformation("Found {Count} abandoned OTP codes. Cleaning rows...", expiredOtps.Count);
            context.OtpCodes.RemoveRange(expiredOtps);
          }

          if (expiredSessions.Count > 0 || expiredOtps.Count > 0) {
            await context.SaveChangesAsync(stoppingToken);
            _logger.LogInformation("Database optimization complete. Expired records deleted.");
          }
          else {
            _logger.LogInformation("Session cleanup scan executed: 0 expired sessions found.");
          }
        }
      }
      catch (Exception ex) {
          _logger.LogError(ex, "An error occurred while executing the database cleanup routine.");
      }
      await Task.Delay(_cleanupInterval, stoppingToken);
    }
  }

}
