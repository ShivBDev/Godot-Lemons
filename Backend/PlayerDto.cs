// data transfer objects for player
namespace Backend.Dtos;

public record LoginOrRegisterRequest(string email, string name);
public record VerifyOtpRequest(string email, string code);
public record PlayerSyncRequest(string email, string name, int money);