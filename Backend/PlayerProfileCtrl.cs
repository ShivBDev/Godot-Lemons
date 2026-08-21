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
              isVerified = false
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

      player.isVerified = true;
      _context.OtpCodes.Remove(otpRecord); // Consume code
      await _context.SaveChangesAsync();

      return Ok(player); // Return verified user profile data to Godot
  }

  [HttpPut("sync")]
  public async Task<IActionResult> SyncProfile([FromBody] PlayerSyncRequest request)
  {
    var player = await _context.Players.FirstOrDefaultAsync(p => p.email == request.email);
    if (player == null) { return NotFound(new { message = "Player profile does not exist." }); }
    if (!player.isVerified) { return Forbid(); } // Prevent saving unverified data

    player.name = request.name;
    player.money = request.money;
    await _context.SaveChangesAsync();
    return Ok(player);
  }
}
