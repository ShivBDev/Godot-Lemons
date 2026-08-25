using Microsoft.EntityFrameworkCore;
using Backend.Data;
using Backend.Services;
using Backend.Utils;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
builder.Services.AddControllers();
builder.Services.AddDbContext<AppDbContext>(options =>
  options.UseNpgsql(builder.Configuration.GetConnectionString("DefaultConnection")));

builder.Services.AddSingleton<SecurityUtils>();
builder.Services.AddSingleton<EmailService>();
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


var app = builder.Build();

// setup https redir 
app.UseHttpsRedirection();
// setup cors
app.UseCors("AllowGodot");

app.UseAuthorization();
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