using Backend.Services;
using Microsoft.Extensions.Diagnostics.HealthChecks;

namespace Backend.Infrastructure;

public class DbAlertPublisher : IHealthCheckPublisher
{
    private readonly EmailService _emailService;
    private readonly string _adminEmail;
    private readonly ILogger<DbAlertPublisher> _logger;
    private static bool _databaseCurrentlyDown = false;

    public DbAlertPublisher(EmailService emailService, IConfiguration configuration, ILogger<DbAlertPublisher> logger)
    {
        _emailService = emailService;
        _logger = logger;
        _adminEmail = configuration["EmailSettings:AdminAlertEmail"] 
            ?? throw new InvalidOperationException("Missing AdminAlertEmail configuration variable.");
    }

    public async Task PublishAsync(HealthReport report, CancellationToken cancellationToken)
    {
        var postgresCheck = report.Entries.FirstOrDefault(e => e.Key == "PostgreSQL-Cluster").Value;

        // Condition A: The database just dropped offline
        if (postgresCheck.Status == HealthStatus.Unhealthy && !_databaseCurrentlyDown)
        {
            _databaseCurrentlyDown = true;
            _logger.LogError("CRITICAL INFRASTRUCTURE ALERT: PostgreSQL database container has dropped offline!");
            string alertBody = $@"
                <h2 style='color:#D32F2F;'>🚨 Critical Infrastructure Alert</h2>
                <p>The backend application monitoring gateway has detected a database disconnection outage.</p>
                <p><b>Timestamp:</b> {DateTime.UtcNow} UTC</p>
                <p><b>Error Details:</b> {postgresCheck.Exception?.Message ?? "Connection timeout or socket rejection."}</p>";
            //_ = Task.Run(async () => {
                try
                {
                    await _emailService.SendCustomSystemEmailAsync(_adminEmail, "CRITICAL: Database Infrastructure is DOWN", alertBody);
                    _logger.LogInformation("Outage alert notification successfully dispatched to admin inbox.");
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Failed to dispatch infrastructure crash alert email via SMTP connection path.");
                }
            //});
        }
        // Condition B: The database has successfully recovered and booted back up
        else if (postgresCheck.Status == HealthStatus.Healthy && _databaseCurrentlyDown)
        {
            _databaseCurrentlyDown = false;
            _logger.LogInformation("INFRASTRUCTURE RECOVERY: PostgreSQL connection re-established.");
            string recoveryBody = $@"
                <h2 style='color:#388E3C;'>✅ Infrastructure Recovery Confirmed</h2>
                <p>The backend application monitoring gateway has successfully verified database socket reconnection.</p>
                <p><b>Timestamp:</b> {DateTime.UtcNow} UTC</p>";
            //_ = Task.Run(async () => {
                try
                {
                    await _emailService.SendCustomSystemEmailAsync(_adminEmail, "RESOLVED: Database Infrastructure is HEALTHY", recoveryBody);
                    _logger.LogInformation("Recovery notification successfully dispatched to admin inbox.");
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Failed to dispatch infrastructure recovery email notification.");
                }
            //});
        }
    }
}
