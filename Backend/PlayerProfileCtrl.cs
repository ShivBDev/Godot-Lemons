// Controllers/PlayerController.cs
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using System.Security.Cryptography;
using Microsoft.AspNetCore.RateLimiting;
using Backend.Models;
using Backend.Data;
using Backend.Dtos;
using Backend.Utils;
using Backend.Services; 

namespace Backend.Controllers;

[ApiController]
[Route("api/[controller]")]
public class PlayerController : ControllerBase {
  private readonly AppDbContext _context;
  private readonly SecurityUtils _securityUtils;
  private readonly EmailService _emailService;
  private readonly EncryptionUtils _encryptionUtils;

  public PlayerController(AppDbContext context, SecurityUtils securityUtils, EmailService emailService, EncryptionUtils encryptionUtils) {
     _context = context;
     _securityUtils = securityUtils;
     _emailService = emailService;
     _encryptionUtils = encryptionUtils;
  }

  [EnableRateLimiting("StrictOtpLimit")]
  [HttpPost("login-or-register")]
  public async Task<IActionResult> LoginOrRegister([FromBody] LoginOrRegisterRequest request) {
    if (string.IsNullOrWhiteSpace(request.email)) { 
      return BadRequest(new ProblemDetailsResponse("Bad Request", 400, "Email cannot be empty."));
    }

    string emailHash = _securityUtils.HashEmail(request.email);
    var player = await _context.Players.FirstOrDefaultAsync(p => p.emailHash == emailHash);
    // Register unverified user
    if (player == null) { 
      player = new PlayerProfileObj {
        emailHash = emailHash,
        name = _encryptionUtils.Encrypt("New Player")
      };
      _context.Players.Add(player);
    }
    //Generate Otp
    string secureRawOtp = RandomNumberGenerator.GetInt32(100000, 1000000).ToString();
    string otpHash = _securityUtils.ComputeSha256(secureRawOtp);
    // only let one otp code be valid per email
    var existingOtp = await _context.OtpCodes.FirstOrDefaultAsync(o => o.emailHash == emailHash);
    if (existingOtp != null) _context.OtpCodes.Remove(existingOtp);

    _context.OtpCodes.Add(new OtpVerification {
      emailHash = emailHash,
      codeHash = otpHash, // Ideally hash this value in production
      expiresAt = DateTime.UtcNow.AddMinutes(15)
    });

    await _context.SaveChangesAsync();
    
    try {
      await _emailService.SendOtpEmailAsync(request.email, secureRawOtp);
      Console.WriteLine($"[EMAIL SENT] Secure OTP dispatched to inbox.");
      return Ok(new { message = "OTP generated successfully.", email = request.email });
    }
    catch (Exception ex) {
      Console.WriteLine($"[EMAIL CRASH] SMTP failed to deliver: {ex.Message}");
      return StatusCode(500, new ProblemDetailsResponse("Internal Server Error", 500, "Failed to dispatch system verification email."));
    }
  }

  [HttpPost("verify-otp")]
  public async Task<IActionResult> VerifyOtp([FromBody] VerifyOtpRequest request) {
    string emailHash = _securityUtils.HashEmail(request.email);
    string targetOtpHash = _securityUtils.ComputeSha256(request.code);

    var otpRecord = await _context.OtpCodes.FirstOrDefaultAsync(o => o.emailHash == emailHash);
    if (otpRecord == null || otpRecord.codeHash != targetOtpHash || otpRecord.expiresAt < DateTime.UtcNow) {
        return BadRequest(new ProblemDetailsResponse("Unauthorized Access", 400, "Invalid or expired one-time passcode."));
    }
    var player = await _context.Players.FirstOrDefaultAsync(p => p.emailHash == emailHash);
    if (player == null) return NotFound(new ProblemDetailsResponse("Not Found", 404, "Player profile missing."));

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
          profile = player.ToResponsePayload(_encryptionUtils) 
      });
  }

  [HttpGet("profile")]
  public async Task<IActionResult> GetProfileFromToken([FromHeader(Name = "Authorization")] string token) {
    if (string.IsNullOrEmpty(token)) {
      return Unauthorized(new ProblemDetailsResponse("Unauthorized", 401, "Missing token."));
    }

    string tokenHash = _securityUtils.ComputeSha256(token);
    var session = await _context.PlayerSessions.FirstOrDefaultAsync(s => s.tokenHash == tokenHash);
    if (session == null || session.expiresAt < DateTime.UtcNow) {
      return Unauthorized(new ProblemDetailsResponse("Unauthorized", 401, "Session expired or invalid."));
    }
    // Slide expiration window since they are active
    session.expiresAt = DateTime.UtcNow.AddDays(30);
    var player = await _context.Players.FirstOrDefaultAsync(p => p.emailHash == session.emailHash);
    if (player == null) return NotFound(new ProblemDetailsResponse("Not Found", 404, "Player profile missing."));

    await _context.SaveChangesAsync();
    return Ok(new {
      email = "Protected",
      profile = player.ToResponsePayload(_encryptionUtils)
    });
  }

  [HttpPut("sync")]
  public async Task<IActionResult> SyncProfile([FromHeader(Name = "Authorization")] string token, [FromBody] PlayerSyncRequest request) {
    if (string.IsNullOrEmpty(token)) {
      return Unauthorized(new ProblemDetailsResponse("Unauthorized", 401, "Missing authentication token header."));
    }

    // Validate the session token exists and hasn't expired yet
    string tokenHash = _securityUtils.ComputeSha256(token);
    var session = await _context.PlayerSessions.FirstOrDefaultAsync(s => s.tokenHash == tokenHash);
    if (session == null || session.expiresAt < DateTime.UtcNow) {
      if (session != null) {
        _context.PlayerSessions.Remove(session); // Clean up expired row from database
        await _context.SaveChangesAsync();
      }
      return Unauthorized(new ProblemDetailsResponse("Unauthorized", 401, "Session expired or invalid. Please sign in again."));
    }
    session.expiresAt = DateTime.UtcNow.AddDays(30); // Refresh session expiry

    var player = await _context.Players.FirstOrDefaultAsync(p => p.emailHash == session.emailHash);
    if (player == null) {
      return NotFound(new ProblemDetailsResponse("Not Found", 404, "Player profile missing."));
    }
    player.ApplySyncUpdate(request, _encryptionUtils);
    await _context.SaveChangesAsync();
    return Ok(player);
  }

  [HttpPost("logout")]
  public async Task<IActionResult> Logout([FromHeader(Name = "Authorization")] string token) {
    string tokenHash = _securityUtils.ComputeSha256(token);
    var session = await _context.PlayerSessions.FirstOrDefaultAsync(s => s.tokenHash == tokenHash);
    if (session != null) {
      _context.PlayerSessions.Remove(session);
      await _context.SaveChangesAsync();
    }
    return Ok(new { message = "Logged out successfully." });
  }
}
