// data transfer objects for player
namespace Backend.Dtos;

public record PlayerRegistrationRequest(string name);
public record PlayerSyncRequest(int pid, string name, int money);