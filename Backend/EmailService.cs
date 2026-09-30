using MimeKit;
using MailKit.Net.Smtp;
using MailKit.Security;
using Microsoft.Extensions.Configuration;

namespace Backend.Services;

public class EmailService {
  private readonly string _smtpUser;
  private readonly string _smtpPass;

  public EmailService(IConfiguration configuration) {
    _smtpUser = configuration["EmailSettings:SmtpUser"] 
      ?? throw new InvalidOperationException("Missing SmtpUser Configuration.");
    _smtpPass = configuration["EmailSettings:SmtpPass"] 
      ?? throw new InvalidOperationException("Missing SmtpPass Configuration.");
  }

  public async Task SendOtpEmailAsync(string targetEmail, string rawOtpCode) {
    var message = new MimeMessage();
    message.From.Add(new MailboxAddress("Godot Game Auth Server", _smtpUser));
    message.To.Add(new MailboxAddress("", targetEmail));
    message.Subject = "Your One-Time Passcode";
    var bodyBuilder = new BodyBuilder {
        HtmlBody = $@"
          <h2>Welcome to the Game!</h2>
          <p>Your secure one-time login passcode is:</p>
          <h1 style='color:#4CAF50; letter-spacing: 5px;'>{rawOtpCode}</h1>
          <p>This code is short-lived and will expire in 15 minutes.</p>"
    };
    message.Body = bodyBuilder.ToMessageBody();
    
    using var client = new SmtpClient();
    try {
        await client.ConnectAsync("smtp.gmail.com", 587, SecureSocketOptions.StartTls);
        await client.AuthenticateAsync(_smtpUser, _smtpPass);
        await client.SendAsync(message);
    }
    finally {
        await client.DisconnectAsync(true);
    }
  }

  public async Task SendCustomSystemEmailAsync(string targetEmail, string customSubject, string htmlBody) {
    var message = new MimeMessage();
    message.From.Add(new MailboxAddress("System Monitoring Engine", _smtpUser));
    message.To.Add(new MailboxAddress("", targetEmail));
    message.Subject = customSubject;
    var bodyBuilder = new BodyBuilder { HtmlBody = htmlBody };
    message.Body = bodyBuilder.ToMessageBody();

    using var client = new SmtpClient();
    try {
        await client.ConnectAsync("smtp.gmail.com", 587, SecureSocketOptions.StartTls);
        await client.AuthenticateAsync(_smtpUser, _smtpPass);
        await client.SendAsync(message);
    }
    finally {
        await client.DisconnectAsync(true);
    }
  }

}
