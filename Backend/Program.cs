using Microsoft.EntityFrameworkCore;
using System.Threading.RateLimiting;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Backend.Data;
using Backend.Services;
using Backend.Utils;
using Backend.Infrastructure;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
builder.Services.AddControllers();
builder.Services.AddDbContext<AppDbContext>(options =>
  options.UseNpgsql(builder.Configuration.GetConnectionString("DefaultConnection")));
// Health Checks
builder.Services.AddHealthChecks()
  .AddNpgSql(builder.Configuration.GetConnectionString("DefaultConnection")!, name: "PostgreSQL-Cluster");
builder.Services.AddSingleton<IHealthCheckPublisher, DbAlertPublisher>();
builder.Services.Configure<HealthCheckPublisherOptions>(_configureHealthChecks());
// Additional Services
builder.Services.AddSingleton<SecurityUtils>();
builder.Services.AddSingleton<EmailService>();
builder.Services.AddSingleton<EncryptionUtils>();
builder.Services.AddHostedService<SessionCleanupService>();
builder.Services.AddCors(_configureCors());
builder.Services.AddRateLimiter(_configureRateLimiting()); 

var app = builder.Build();
app.UseRateLimiter();
//app.UseHttpsRedirection();
app.UseCors("AllowGodot");
app.UseAuthorization();
app.MapHealthChecks("/health");
app.MapControllers();
_applyMigrations(app);
app.Run();

// Add Healthchecks for Db
Action<HealthCheckPublisherOptions> _configureHealthChecks() {
  return options => {
    options.Delay = TimeSpan.FromSeconds(10);     // Run the first check 10 seconds after boot
    options.Period = TimeSpan.FromSeconds(30);    // Scan database health continuously every 30 seconds
    options.Timeout = TimeSpan.FromSeconds(5);    // Crash check if database takes longer than 5 seconds to reply
  };
}

// Allow local applications (like Godot) to read API data safely
Action<Microsoft.AspNetCore.Cors.Infrastructure.CorsOptions> _configureCors() {
  return options => {
    options.AddPolicy("AllowGodot", policy => {
      policy.AllowAnyOrigin()
            .AllowAnyMethod()
            .AllowAnyHeader();
    });
  };
}

// Add rate limiting services
Action<Microsoft.AspNetCore.RateLimiting.RateLimiterOptions> _configureRateLimiting() {
  return options => {
    options.AddPolicy("StrictOtpLimit", context => {
      // Get IP address, anonymous handle as fallback
      string ipAddress = context.Connection.RemoteIpAddress?.ToString() ?? "anonymous";
      // Create rate limit window specifically for this IP
      return RateLimitPartition.GetFixedWindowLimiter(
        partitionKey: ipAddress,
        factory: _ => new FixedWindowRateLimiterOptions {
          PermitLimit = 3,                       // Max 3 requests allowed
          Window = TimeSpan.FromMinutes(1),      // Per 1-minute rolling frame
          QueueLimit = 0                         // Reject overflow clicks instantly
        });
    });
    options.OnRejected = async (context, cancellationToken) => {
      context.HttpContext.Response.StatusCode = StatusCodes.Status429TooManyRequests;
      context.HttpContext.Response.ContentType = "application/json";
      await context.HttpContext.Response.WriteAsync(
        "{\"title\": \"Too Many Requests\", \"status\": 429, \"detail\": \"Too many login attempts. Please wait 1 minute before trying again.\"}", 
        cancellationToken);
    };
  };
}

// Apply pending migrations on startup
void _applyMigrations(WebApplication? app) {
  if (app == null) throw new ArgumentNullException(nameof(app));
  using (var scope = app.Services.CreateScope())
  {
    var services = scope.ServiceProvider;
    var context = services.GetRequiredService<AppDbContext>();
    var logger = services.GetRequiredService<ILogger<Program>>();
    int retryCount = 6;
    int delaySeconds = 5;
    while(retryCount > 0)
    {
      try {
        if (context.Database.GetPendingMigrations().Any()) {
            Console.WriteLine("Applying pending database migrations...");
            context.Database.Migrate();
        }
        else {
            Console.WriteLine("No pending database migrations found.");
            break;
        }
      }
      catch (Exception ex) {
        retryCount--;
        logger.LogWarning("PostgreSQL container is initializing. Retrying link in {Delay} seconds... ({Count} attempts remaining)", delaySeconds, retryCount);
        if (retryCount == 0) {
            logger.LogError(ex, "Critical failure: Could not establish a connection to the database container cluster.");
            throw; // Fail safely if the maximum retry threshold is crossed
        }
        System.Threading.Thread.Sleep(delaySeconds * 1000); // Sleep thread safely before next loop execution
      }
    }
  }
}