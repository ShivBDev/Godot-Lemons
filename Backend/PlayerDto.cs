// data transfer objects for player
namespace Backend.Dtos;

// Standardized RFC 7807 Problem Details object
public record ProblemDetailsResponse(string title, int status, string detail);

public record LoginOrRegisterRequest(string email);
public record VerifyOtpRequest(string email, string code);
public record PlayerSyncRequest(string name, GameStateData state); //session token is id

public record GameStateData(
    float money, 
    int dayCount,
    int lemonStock,
    int sugarStock,
    int iceStock,
    int recipeLemons,
    int recipeSugar,
    int recipeIce,
    float salePrice
);