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
builder.Services.Configure<HealthCheckPublisherOptions>(options =>
{
    options.Delay = TimeSpan.FromSeconds(10);     // Run the first check 10 seconds after boot
    options.Period = TimeSpan.FromSeconds(30);    // Scan database health continuously every 30 seconds
    options.Timeout = TimeSpan.FromSeconds(5);    // Crash check if database takes longer than 5 seconds to reply
});

builder.Services.AddSingleton<SecurityUtils>();
builder.Services.AddSingleton<EmailService>();
builder.Services.AddSingleton<EncryptionUtils>();
builder.Services.AddHostedService<SessionCleanupService>();
// enable Cors: Allow local applications (like Godot) to read API data safely
builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowGodot", policy =>
    {
        policy.AllowAnyOrigin()
              .AllowAnyMethod()
              .AllowAnyHeader();
    });
});
// Add rate limiting services
builder.Services.AddRateLimiter(options => {
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
});

var app = builder.Build();
app.UseRateLimiter();
// setup https redir 
//app.UseHttpsRedirection();
// setup cors
app.UseCors("AllowGodot");

app.UseAuthorization();
app.MapHealthChecks("/health");
app.MapControllers();

// Apply pending migrations on startup
using (var scope = app.Services.CreateScope())
{
  var services = scope.ServiceProvider;
  try
  {
    var context = services.GetRequiredService<AppDbContext>();
    if (context.Database.GetPendingMigrations().Any())
    {
        Console.WriteLine("Applying pending database migrations...");
        context.Database.Migrate();
    }
  }
  catch (Exception ex)
  {
    var logger = services.GetRequiredService<ILogger<Program>>();
    logger.LogError(ex, "An error occurred while migrating the database.");
  }
}
app.Run();