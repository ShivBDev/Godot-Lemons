using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using MimeKit;
using Microsoft.Extensions.Configuration;

namespace Backend.Services;

public class EmailService {
  private const string GoogleTokenEndpoint = "https://oauth2.googleapis.com/token";
  private const string GmailSendEndpoint = "https://gmail.googleapis.com/gmail/v1/users/me/messages/send";

  private static readonly HttpClient HttpClient = new();
  private readonly string _gmailUser;
  private readonly string _clientId;
  private readonly string _clientSecret;
  private readonly string _refreshToken;

  // Gmail access tokens are short-lived, so keep one in memory and refresh it only when needed.
  private readonly SemaphoreSlim _tokenLock = new(1, 1);
  private string? _accessToken;
  private DateTimeOffset _accessTokenExpiresAt = DateTimeOffset.MinValue;

  public EmailService(IConfiguration configuration) {
    _gmailUser = configuration["EmailSettings:GmailUser"]
      ?? throw new InvalidOperationException("Missing GmailUser configuration.");
    _clientId = configuration["GoogleOAuth:ClientId"]
      ?? throw new InvalidOperationException("Missing Google OAuth ClientId configuration.");
    _clientSecret = configuration["GoogleOAuth:ClientSecret"]
      ?? throw new InvalidOperationException("Missing Google OAuth ClientSecret configuration.");
    _refreshToken = configuration["GoogleOAuth:RefreshToken"]
      ?? throw new InvalidOperationException("Missing Google OAuth RefreshToken configuration.");
  }

  public Task SendOtpEmailAsync(string targetEmail, string rawOtpCode) {
    const string subject = "Your One-Time Passcode";
    string htmlBody = $@"
      <h2>Welcome to the Game!</h2>
      <p>Your secure one-time login passcode is:</p>
      <h1 style='color:#4CAF50; letter-spacing: 5px;'>{rawOtpCode}</h1>
      <p>This code is short-lived and will expire in 15 minutes.</p>";

    return SendEmailAsync(
      targetEmail,
      subject,
      htmlBody,
      "Godot Game Auth Server");
  }

  public Task SendCustomSystemEmailAsync(string targetEmail, string customSubject, string htmlBody) {
    return SendEmailAsync(
      targetEmail,
      customSubject,
      htmlBody,
      "System Monitoring Engine");
  }

  private async Task SendEmailAsync(
    string targetEmail,
    string subject,
    string htmlBody,
    string senderDisplayName) {

    if (string.IsNullOrWhiteSpace(targetEmail)) {
      throw new ArgumentException("Target email cannot be empty.", nameof(targetEmail));
    }

    var message = new MimeMessage();
    message.From.Add(new MailboxAddress(senderDisplayName, _gmailUser));
    message.To.Add(new MailboxAddress(string.Empty, targetEmail));
    message.Subject = subject;

    var bodyBuilder = new BodyBuilder {
      HtmlBody = htmlBody,
      TextBody = $"{subject}\n\nPlease view this message in an HTML-capable email client."
    };
    message.Body = bodyBuilder.ToMessageBody();

    using var messageStream = new MemoryStream();
    message.WriteTo(messageStream);

    // Gmail expects the RFC 2822/MIME message as unpadded base64url.
    string encodedMessage = Convert.ToBase64String(messageStream.ToArray())
      .Replace('+', '-')
      .Replace('/', '_')
      .TrimEnd('=');

    string accessToken = await GetAccessTokenAsync();

    using var request = new HttpRequestMessage(HttpMethod.Post, GmailSendEndpoint);
    request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
    request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));
    request.Content = new StringContent(
      JsonSerializer.Serialize(new { raw = encodedMessage }),
      Encoding.UTF8,
      "application/json");

    using HttpResponseMessage response = await HttpClient.SendAsync(request);

    if (!response.IsSuccessStatusCode) {
      string errorBody = await response.Content.ReadAsStringAsync();
      throw new HttpRequestException(
        $"Gmail API send failed with {(int)response.StatusCode} {response.ReasonPhrase}: {errorBody}");
    }
  }

  private async Task<string> GetAccessTokenAsync() {
    if (!string.IsNullOrEmpty(_accessToken) &&
        DateTimeOffset.UtcNow < _accessTokenExpiresAt) {
      return _accessToken;
    }

    await _tokenLock.WaitAsync();
    try {
      // Check again after acquiring the lock so concurrent email requests don't all refresh.
      if (!string.IsNullOrEmpty(_accessToken) &&
          DateTimeOffset.UtcNow < _accessTokenExpiresAt) {
        return _accessToken;
      }

      using var tokenRequest = new HttpRequestMessage(HttpMethod.Post, GoogleTokenEndpoint) {
        Content = new FormUrlEncodedContent(new Dictionary<string, string> {
          ["client_id"] = _clientId,
          ["client_secret"] = _clientSecret,
          ["refresh_token"] = _refreshToken,
          ["grant_type"] = "refresh_token"
        })
      };

      using HttpResponseMessage response = await HttpClient.SendAsync(tokenRequest);
      string responseBody = await response.Content.ReadAsStringAsync();

      if (!response.IsSuccessStatusCode) {
        throw new InvalidOperationException(
          $"Google OAuth token refresh failed with {(int)response.StatusCode} {response.ReasonPhrase}: {responseBody}");
      }

      using JsonDocument json = JsonDocument.Parse(responseBody);
      if (!json.RootElement.TryGetProperty("access_token", out JsonElement accessTokenElement)) {
        throw new InvalidOperationException("Google OAuth token response did not contain an access_token.");
      }

      string accessToken = accessTokenElement.GetString()
        ?? throw new InvalidOperationException("Google OAuth access_token was null.");

      int expiresIn = 3600;
      if (json.RootElement.TryGetProperty("expires_in", out JsonElement expiresInElement) &&
          expiresInElement.TryGetInt32(out int parsedExpiresIn)) {
        expiresIn = parsedExpiresIn;
      }

      _accessToken = accessToken;
      // Refresh one minute early to avoid expiring between the token check and Gmail request.
      _accessTokenExpiresAt = DateTimeOffset.UtcNow.AddSeconds(Math.Max(1, expiresIn - 60));

      return _accessToken;
    }
    finally {
      _tokenLock.Release();
    }
  }
}
