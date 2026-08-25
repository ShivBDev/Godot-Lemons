// Controllers/PlayerController.cs
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Backend.Models;
using Backend.Data;
using Backend.Dtos;
using Backend.Utils;

namespace Backend.Controllers;

[ApiController]
[Route("api/[controller]")]
public class PlayerController : ControllerBase
{
  private readonly AppDbContext _context;
  private readonly SecurityUtils _securityUtils;

  public PlayerController(AppDbContext context, SecurityUtils securityUtils) {
     _context = context;
     _securityUtils = securityUtils;
  }

  [HttpPost("login-or-register")]
  public async Task<IActionResult> LoginOrRegister([FromBody] LoginOrRegisterRequest request)
  {
    if (string.IsNullOrWhiteSpace(request.email)) { return BadRequest(new { message = "Email cannot be empty." }); }

    string emailHash = _securityUtils.HashEmail(request.email);
    var player = await _context.Players.FirstOrDefaultAsync(p => p.emailHash == emailHash);

    if (player == null) { // Register unverified user
      player = new PlayerProfileObj {
        emailHash = emailHash,
        name = "New Player",
        money = 100,
      };
      _context.Players.Add(player);
    }
    // Generate MOCK OTP code
    string mockOtp = "123456";
    string otpHash = _securityUtils.ComputeSha256(mockOtp);
    // only let one otp code be valid per email
    var existingOtp = await _context.OtpCodes.FirstOrDefaultAsync(o => o.emailHash == emailHash);
    if (existingOtp != null) _context.OtpCodes.Remove(existingOtp);

    _context.OtpCodes.Add(new OtpVerification {
      emailHash = emailHash,
      codeHash = otpHash, // Ideally hash this value in production
      expiresAt = DateTime.UtcNow.AddMinutes(15)
    });

    await _context.SaveChangesAsync();
    
    // TODO: Call an email service provider here to send mockOtp to request.email
    Console.WriteLine($"[EMAIL SENT] OTP to {request.email} is {mockOtp}");

    return Ok(new { message = "OTP generated successfully.", email = request.email });
  }

  [HttpPost("verify-otp")]
  public async Task<IActionResult> VerifyOtp([FromBody] VerifyOtpRequest request)
  {
    string emailHash = _securityUtils.HashEmail(request.email);
    string targetOtpHash = _securityUtils.ComputeSha256(request.code);

    var otpRecord = await _context.OtpCodes.FirstOrDefaultAsync(o => o.emailHash == emailHash);
    if (otpRecord == null || otpRecord.codeHash != targetOtpHash || otpRecord.expiresAt < DateTime.UtcNow) {
        return BadRequest(new { message = "Invalid or expired one-time passcode." });
    }
    var player = await _context.Players.FirstOrDefaultAsync(p => p.emailHash == emailHash);
    if (player == null) return NotFound(new { message = "Player profile missing." });

    _context.OtpCodes.Remove(otpRecord); // Consume code

    string rawSessionToken = Guid.NewGuid().ToString();
    string sessionToken = _securityUtils.ComputeSha256(rawSessionToken); // Hash the token for storage

    // Save Session
    _context.PlayerSessions.Add(new PlayerSession {
        tokenHash = sessionToken,
        emailHash = emailHash,
        expiresAt = DateTime.UtcNow.AddDays(30)
    });
    await _context.SaveChangesAsync();
    return Ok(new { 
          token = rawSessionToken, 
          profile = new { email = request.email, name = player.name, money = player.money } 
      });
  }

  [HttpGet("profile")]
  public async Task<IActionResult> GetProfileFromToken([FromHeader(Name = "Authorization")] string token)
  {
    if (string.IsNullOrEmpty(token)) return Unauthorized(new { message = "Missing token." });

    string tokenHash = _securityUtils.ComputeSha256(token);
    var session = await _context.PlayerSessions.FirstOrDefaultAsync(s => s.tokenHash == tokenHash);
    if (session == null || session.expiresAt < DateTime.UtcNow) {
      return Unauthorized(new { message = "Session expired or invalid." });
    }
    // Slide expiration window since they are active
    session.expiresAt = DateTime.UtcNow.AddDays(30);
    var player = await _context.Players.FirstOrDefaultAsync(p => p.emailHash == session.emailHash);
    if (player == null) return NotFound();

    await _context.SaveChangesAsync();
    return Ok(new { email = "Protected", name = player.name, money = player.money });
  }

  [HttpPut("sync")]
  public async Task<IActionResult> SyncProfile([FromHeader(Name = "Authorization")] string token, [FromBody] PlayerSyncRequest request)
  {
    if (string.IsNullOrEmpty(token)) return Unauthorized(new { message = "Missing authentication token header." });

    // Validate the session token exists and hasn't expired yet
    string tokenHash = _securityUtils.ComputeSha256(token);
    var session = await _context.PlayerSessions.FirstOrDefaultAsync(s => s.tokenHash == tokenHash);
    if (session == null || session.expiresAt < DateTime.UtcNow) {
      if (session != null) {
        _context.PlayerSessions.Remove(session); // Clean up expired row from database
        await _context.SaveChangesAsync();
      }
      return Unauthorized(new { message = "Session expired or invalid. Please sign in again." });
    }
    session.expiresAt = DateTime.UtcNow.AddDays(30); // Refresh session expiry

    var player = await _context.Players.FirstOrDefaultAsync(p => p.emailHash == session.emailHash);
    if (player == null) return NotFound();
    player.name = request.name;
    player.money = request.money;
    await _context.SaveChangesAsync();
    return Ok(player);
  }

  [HttpPost("logout")]
  public async Task<IActionResult> Logout([FromHeader(Name = "Authorization")] string token)
  {
    string tokenHash = _securityUtils.ComputeSha256(token);
    var session = await _context.PlayerSessions.FirstOrDefaultAsync(s => s.tokenHash == tokenHash);
    if (session != null) {
      _context.PlayerSessions.Remove(session);
      await _context.SaveChangesAsync();
    }
    return Ok(new { message = "Logged out successfully." });
  }
}
