// data transfer objects for player
namespace Backend.Dtos;

public record LoginOrRegisterRequest(string email);
public record VerifyOtpRequest(string email, string code);
public record PlayerSyncRequest(string name, int money); //session token is id