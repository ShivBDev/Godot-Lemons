using System.Net;
using System.Net.Mail;

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
    var fromAddress = new MailAddress(_smtpUser, "Godot Game Auth Server");
    var toAddress = new MailAddress(targetEmail);

    const string subject = "Your One-Time Passcode";
    string body = $@"
      <h2>Welcome to the Game!</h2>
      <p>Your secure one-time login passcode is:</p>
      <h1 style='color:#4CAF50; letter-spacing: 5px;'>{rawOtpCode}</h1>
      <p>This code is short-lived and will expire in 15 minutes.</p>";
    using var smtp = new SmtpClient {
      Host = "smtp.gmail.com",
      Port = 587,
      EnableSsl = true,
      DeliveryMethod = SmtpDeliveryMethod.Network,
      UseDefaultCredentials = false,
      Credentials = new NetworkCredential(fromAddress.Address, _smtpPass)
    };
    using var message = new MailMessage(fromAddress, toAddress) {
      Subject = subject,
      Body = body,
      IsBodyHtml = true
    };
    await smtp.SendMailAsync(message);
  }

  public async Task SendCustomSystemEmailAsync(string targetEmail, string customSubject, string htmlBody)
  {
    var fromAddress = new MailAddress(_smtpUser, "System Monitoring Engine");
    var toAddress = new MailAddress(targetEmail);
    using var smtp = new SmtpClient
    {
      Host = "smtp.gmail.com",
      Port = 587,
      EnableSsl = true,
      DeliveryMethod = SmtpDeliveryMethod.Network,
      UseDefaultCredentials = false,
      Credentials = new NetworkCredential(fromAddress.Address, _smtpPass)
    };
    using var message = new MailMessage(fromAddress, toAddress)
    {
      Subject = customSubject,
      Body = htmlBody,
      IsBodyHtml = true
    };
    await smtp.SendMailAsync(message);
  }

}
