// Controllers/PlayerController.cs
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Backend.Models;
using Backend.Data;
using Backend.Dtos;

namespace Backend.Controllers;

[ApiController]
[Route("api/[controller]")]
public class PlayerController : ControllerBase
{
  private readonly AppDbContext _context;
  public PlayerController(AppDbContext context)
  {
    _context = context;
  }

  [HttpPost("login-or-register")]
  public async Task<IActionResult> LoginOrRegister([FromBody] LoginOrRegisterRequest request)
  {
    if (string.IsNullOrWhiteSpace(request.email)) { return BadRequest(new { message = "Email cannot be empty." }); }

    var player = await _context.Players.FirstOrDefaultAsync(p => p.email == request.email);
    
    if (player == null) { // Register unverified user
      player = new PlayerProfileObj {
        email = request.email,
        name = string.IsNullOrWhiteSpace(request.name) ? "New Player" : request.name,
        money = 100,
      };
      _context.Players.Add(player);
    }
    // Generate MOCK OTP code
    string mockOtp = "123456"; 
    // only let one otp code be valid per email
    var existingOtp = await _context.OtpCodes.FirstOrDefaultAsync(o => o.email == request.email);
    if (existingOtp != null) _context.OtpCodes.Remove(existingOtp);

    _context.OtpCodes.Add(new OtpVerification {
      email = request.email,
      codeHash = mockOtp, // Ideally hash this value in production
      expiresAt = DateTime.UtcNow.AddMinutes(15)
    });

    await _context.SaveChangesAsync();
    
    // TODO: Call an email service provider here to send mockOtp to request.email
    Console.WriteLine($"[EMAIL SENT] OTP to {request.email} is {mockOtp}");

    return Ok(new { message = "OTP generated successfully.", email = player.email });
  }

  [HttpPost("verify-otp")]
  public async Task<IActionResult> VerifyOtp([FromBody] VerifyOtpRequest request)
  {
    var otpRecord = await _context.OtpCodes.FirstOrDefaultAsync(o => o.email == request.email);
    if (otpRecord == null || otpRecord.codeHash != request.code || otpRecord.expiresAt < DateTime.UtcNow) {
        return BadRequest(new { message = "Invalid or expired one-time passcode." });
    }

    var player = await _context.Players.FirstOrDefaultAsync(p => p.email == request.email);
    if (player == null) return NotFound(new { message = "Player profile missing." });

    _context.OtpCodes.Remove(otpRecord); // Consume code
    string sessionToken = Guid.NewGuid().ToString();

    // Save Session
    _context.PlayerSessions.Add(new PlayerSession {
        token = sessionToken,
        email = request.email,
        expiresAt = DateTime.UtcNow.AddDays(30)
    });

    await _context.SaveChangesAsync();

    return Ok(new { token = sessionToken, profile = player }); // Return verified user profile data to Godot
  }

  [HttpPut("sync")]
  public async Task<IActionResult> SyncProfile([FromHeader(Name = "Authorization")] string token, [FromBody] PlayerSyncRequest request)
  {
    if (string.IsNullOrEmpty(token)) return Unauthorized(new { message = "Missing authentication token header." });

    // Validate the session token exists and hasn't expired yet
    var session = await _context.PlayerSessions.FirstOrDefaultAsync(s => s.token == token);
    if (session == null || session.expiresAt < DateTime.UtcNow) {
      if (session != null) {
            _context.PlayerSessions.Remove(session); // Clean up expired row from database
            await _context.SaveChangesAsync();
      }
      return Unauthorized(new { message = "Session expired or invalid. Please sign in again." });
    }
    session.expiresAt = DateTime.UtcNow.AddDays(30); // Refresh session expiry

    var player = await _context.Players.FirstOrDefaultAsync(p => p.email == session.email);
    if (player == null) return NotFound();

    player.name = request.name;
    player.money = request.money;
    await _context.SaveChangesAsync();
    return Ok(player);
  }
}
