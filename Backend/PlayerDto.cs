// data transfer objects for player
namespace Backend.Dtos;

// Standardized RFC 7807 Problem Details object
public record ProblemDetailsResponse(string title, int status, string detail);

public record LoginOrRegisterRequest(string email);
public record VerifyOtpRequest(string email, string code);
public record PlayerSyncRequest(string name, int money); //session token is id