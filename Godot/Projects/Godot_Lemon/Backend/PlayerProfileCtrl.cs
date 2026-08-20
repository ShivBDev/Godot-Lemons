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

  [HttpGet("profile/{pid:int}")] // GET: /api/player/profile/1
  public async Task<IActionResult> GetProfile([FromRoute] int pid)
  {
    PlayerProfileObj? player = await _context.Players.FirstOrDefaultAsync(p => p.pid == pid);
    if (player == null) { return NotFound(new { message = "Player profile not found in database." }); }
    return Ok(player);
  }

  [HttpPost("register")] // POST: api/player/register
  public async Task<IActionResult> RegisterPlayer([FromBody] PlayerRegistrationRequest request)
  {
      if (string.IsNullOrWhiteSpace(request.name)) { return BadRequest(new { message = "Player name cannot be empty." }); }

      PlayerProfileObj newPlayer = new PlayerProfileObj
      {
          name = request.name,
          money = 100
      };

      _context.Players.Add(newPlayer);
      await _context.SaveChangesAsync(); // Writes the new row directly to PostgreSQL

      return CreatedAtAction(nameof(GetProfile), new { pid = newPlayer.pid }, newPlayer);
  }

  [HttpPut("sync")] // POST: api/player/sync
  public async Task<IActionResult> SyncProfile([FromBody] PlayerSyncRequest request)
  {
    PlayerProfileObj? player = await _context.Players.FirstOrDefaultAsync(p => p.pid == request.pid);
    if (player == null) { return NotFound(new { message = "Player profile does not exist." }); }

    // pid can never be updated, only update player name and money
    player.name = request.name;
    player.money = request.money;
    await _context.SaveChangesAsync();
    return Ok(player);
  }
}
