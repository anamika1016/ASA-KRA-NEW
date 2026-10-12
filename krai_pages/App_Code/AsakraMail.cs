using System;
using System.Collections.Generic;
using System.Configuration;
using System.Linq;
using System.Net;
using System.Net.Mail;
using System.Text;
using System.Web;
using System.Web.UI;

// Sends the ASA KRA portal's notification mails. The KRA server (asakra.asaindia.org)
// calls asakra_notification.aspx with GET parameters:
//
//   to_email, to_name, subject, message, link, employee_name, employee_code,
//   quarter, month, reviewer_role, reviewer_name, action, remarks, mail_type
//
// krai has one page for all of them, asakra_notification.aspx, which calls
// HandleAny(): the heading, colour and button text are picked by mail_type.
// The page answers JSON: 200 {"success":true} when the mail went, otherwise
// 4xx/5xx {"success":false,"message":"..."} so the KRA server logs the failure.
//
// Settings (web.config <appSettings>), all optional:
//   AsakraSmtpHost, AsakraSmtpPort, AsakraSmtpUser, AsakraSmtpPassword, AsakraSmtpEnableSsl
//       - leave AsakraSmtpHost empty to use <system.net><mailSettings> of the site
//   AsakraMailFrom, AsakraMailFromName - sender address and name
//   AsakraAllowedIps  - comma separated IPs allowed to call the pages (the KRA server);
//                       empty = anyone
//   AsakraLinkBase    - links in the mail must start with this (default https://asakra.asaindia.org)
public static class AsakraMail
{
    private const string DefaultLinkBase = "https://asakra.asaindia.org";
    private const string Blue = "#1d4ed8";
    private const string Green = "#15803d";
    private const string Red = "#b91c1c";

    // mail_type => heading, colour, button text
    private static readonly Dictionary<string, string[]> MailTypes = new Dictionary<string, string[]>
    {
        { "kra_submitted_to_l1", new[] { "KRA MIS submitted for your review", Blue, "Review in KRA portal" } },
        { "kra_submitted_to_observer", new[] { "KRA MIS submitted for observer review", Blue, "Review in KRA portal" } },
        { "kra_observers_approved_to_l1", new[] { "KRA MIS ready for your L1 review", Blue, "Review in KRA portal" } },
        { "kra_updated_to_l1", new[] { "KRA MIS updated - please review", Blue, "Review in KRA portal" } },
        { "kra_updated_to_observer", new[] { "KRA MIS updated - please review", Blue, "Review in KRA portal" } },
        { "employee_observer_approved", new[] { "Your KRA MIS was approved by the observer", Green, "Open KRA portal" } },
        { "employee_observer_returned", new[] { "Your KRA MIS was returned by the observer", Red, "Check and resubmit" } },
        { "employee_l1_approved", new[] { "Your KRA MIS was approved by L1", Green, "Open KRA portal" } },
        { "employee_l1_returned", new[] { "Your KRA MIS was returned by L1", Red, "Check and resubmit" } },
        { "employee_l2_approved", new[] { "Your KRA MIS was approved by L2", Green, "Open KRA portal" } },
        { "employee_l2_returned", new[] { "Your KRA MIS was returned by L2", Red, "Check and resubmit" } },
        { "employee_pli_approved", new[] { "Your Quarterly PLI was approved", Green, "Open KRA portal" } },
        { "employee_pli_returned", new[] { "Your Quarterly PLI was returned", Red, "Open KRA portal" } }
    };

    // The one page for every KRA mail: heading, colour and button come from mail_type.
    public static void HandleAny(Page page)
    {
        string[] style;
        if (!MailTypes.TryGetValue(Param(page.Request, "mail_type"), out style))
        {
            style = new[] { "ASA KRA Portal notification", Blue, "Open KRA portal" };
        }
        Handle(page, style[0], style[1], style[2]);
    }

    public static void Handle(Page page, string heading, string accentColor, string buttonText)
    {
        HttpRequest request = page.Request;

        try
        {
            if (!CallerAllowed(request))
            {
                Answer(page, 403, false, "Caller not allowed");
                return;
            }

            string toEmail = Param(request, "to_email");
            if (!ValidEmail(toEmail))
            {
                Answer(page, 400, false, "to_email is missing or invalid");
                return;
            }

            string subject = OneLine(Param(request, "subject"));
            if (subject.Length == 0) subject = heading;

            using (MailMessage mail = new MailMessage())
            {
                mail.From = new MailAddress(Setting("AsakraMailFrom", "noreply@asaindia.org"),
                                            Setting("AsakraMailFromName", "ASA KRA Portal"));
                mail.To.Add(new MailAddress(toEmail, OneLine(Param(request, "to_name"))));
                mail.Subject = subject;
                mail.SubjectEncoding = Encoding.UTF8;
                mail.BodyEncoding = Encoding.UTF8;
                mail.IsBodyHtml = true;
                mail.Body = BuildBody(request, heading, accentColor, buttonText);

                using (SmtpClient smtp = BuildSmtpClient())
                {
                    smtp.Send(mail);
                }
            }

            Answer(page, 200, true, "Email sent");
        }
        catch (Exception error)
        {
            Answer(page, 500, false, "Email not sent: " + error.Message);
        }
    }

    private static string BuildBody(HttpRequest request, string heading, string accentColor, string buttonText)
    {
        string toName = Param(request, "to_name");
        string message = Param(request, "message");
        string link = SafeLink(Param(request, "link"));

        List<KeyValuePair<string, string>> rows = new List<KeyValuePair<string, string>>
        {
            new KeyValuePair<string, string>("Employee", Param(request, "employee_name")),
            new KeyValuePair<string, string>("Employee Code", Param(request, "employee_code")),
            new KeyValuePair<string, string>("Quarter", Param(request, "quarter")),
            new KeyValuePair<string, string>("Month", Param(request, "month")),
            new KeyValuePair<string, string>("Reviewer", ReviewerText(request)),
            new KeyValuePair<string, string>("Status", Capitalize(Param(request, "action"))),
            new KeyValuePair<string, string>("Remarks", Param(request, "remarks"))
        };

        StringBuilder html = new StringBuilder();
        html.Append("<!DOCTYPE html><html><body style=\"margin:0;padding:0;background:#f3f4f6;font-family:Arial,Helvetica,sans-serif;color:#111827;\">");
        html.Append("<table role=\"presentation\" width=\"100%\" cellpadding=\"0\" cellspacing=\"0\" style=\"background:#f3f4f6;padding:24px 0;\"><tr><td align=\"center\">");
        html.Append("<table role=\"presentation\" width=\"600\" cellpadding=\"0\" cellspacing=\"0\" style=\"max-width:600px;width:100%;background:#ffffff;border-radius:8px;overflow:hidden;\">");

        html.Append("<tr><td style=\"background:").Append(Enc(accentColor)).Append(";padding:18px 24px;color:#ffffff;\">");
        html.Append("<div style=\"font-size:13px;opacity:0.9;\">Action For Social Advancement (ASA) &middot; KRA Portal</div>");
        html.Append("<div style=\"font-size:20px;font-weight:bold;margin-top:4px;\">").Append(Enc(heading)).Append("</div>");
        html.Append("</td></tr>");

        html.Append("<tr><td style=\"padding:24px;font-size:15px;line-height:1.5;\">");
        html.Append("<p style=\"margin:0 0 12px;\">Dear ").Append(Enc(toName.Length > 0 ? toName : "Sir/Madam")).Append(",</p>");
        if (message.Length > 0)
        {
            html.Append("<p style=\"margin:0 0 16px;\">").Append(Enc(message)).Append("</p>");
        }

        html.Append("<table role=\"presentation\" cellpadding=\"0\" cellspacing=\"0\" style=\"width:100%;border-collapse:collapse;font-size:14px;margin:0 0 20px;\">");
        foreach (KeyValuePair<string, string> row in rows.Where(r => r.Value.Length > 0))
        {
            html.Append("<tr><td style=\"padding:8px 10px;border:1px solid #e5e7eb;background:#f9fafb;width:35%;font-weight:bold;\">")
                .Append(Enc(row.Key))
                .Append("</td><td style=\"padding:8px 10px;border:1px solid #e5e7eb;\">")
                .Append(Enc(row.Value))
                .Append("</td></tr>");
        }
        html.Append("</table>");

        if (link.Length > 0)
        {
            html.Append("<p style=\"margin:0 0 8px;\"><a href=\"").Append(Enc(link))
                .Append("\" style=\"display:inline-block;background:").Append(Enc(accentColor))
                .Append(";color:#ffffff;text-decoration:none;padding:10px 18px;border-radius:6px;font-weight:bold;\">")
                .Append(Enc(buttonText)).Append("</a></p>");
            html.Append("<p style=\"margin:0;font-size:12px;color:#6b7280;\">Or open: ").Append(Enc(link)).Append("</p>");
        }

        html.Append("</td></tr>");
        html.Append("<tr><td style=\"padding:14px 24px;background:#f9fafb;font-size:12px;color:#6b7280;\">This is an automatic mail from the ASA KRA portal. Please do not reply.</td></tr>");
        html.Append("</table></td></tr></table></body></html>");
        return html.ToString();
    }

    private static string ReviewerText(HttpRequest request)
    {
        string role = Param(request, "reviewer_role");
        string name = Param(request, "reviewer_name");
        if (name.Length == 0) return "";
        if (role.Length == 0 || role == "PLI") return name;
        return role + " - " + name;
    }

    private static SmtpClient BuildSmtpClient()
    {
        string host = Setting("AsakraSmtpHost", "");
        if (host.Length == 0)
        {
            // Uses <system.net><mailSettings><smtp> from web.config.
            return new SmtpClient();
        }

        int port;
        if (!int.TryParse(Setting("AsakraSmtpPort", "587"), out port)) port = 587;

        SmtpClient smtp = new SmtpClient(host, port);
        smtp.DeliveryMethod = SmtpDeliveryMethod.Network;
        smtp.EnableSsl = Setting("AsakraSmtpEnableSsl", "true").Equals("true", StringComparison.OrdinalIgnoreCase);
        smtp.Timeout = 20000;

        string user = Setting("AsakraSmtpUser", "");
        if (user.Length > 0)
        {
            smtp.UseDefaultCredentials = false;
            smtp.Credentials = new NetworkCredential(user, Setting("AsakraSmtpPassword", ""));
        }
        return smtp;
    }

    private static bool CallerAllowed(HttpRequest request)
    {
        string allowed = Setting("AsakraAllowedIps", "");
        if (allowed.Length == 0) return true;

        string caller = request.UserHostAddress ?? "";
        return allowed.Split(',').Select(ip => ip.Trim()).Any(ip => ip.Length > 0 && ip == caller);
    }

    // Only links into the KRA portal go in the mail, so the page cannot be used
    // to send people somewhere else.
    private static string SafeLink(string link)
    {
        string linkBase = Setting("AsakraLinkBase", DefaultLinkBase).TrimEnd('/');
        if (link.Length == 0) return linkBase;
        if (link.Equals(linkBase, StringComparison.OrdinalIgnoreCase) ||
            link.StartsWith(linkBase + "/", StringComparison.OrdinalIgnoreCase))
        {
            return link;
        }
        return linkBase;
    }

    private static bool ValidEmail(string email)
    {
        if (email.Length == 0 || email.Length > 254 || email.IndexOf('@') <= 0) return false;
        try
        {
            return new MailAddress(email).Address == email;
        }
        catch (FormatException)
        {
            return false;
        }
    }

    private static void Answer(Page page, int status, bool success, string message)
    {
        HttpResponse response = page.Response;
        response.Clear();
        response.StatusCode = status;
        response.ContentType = "application/json";
        response.ContentEncoding = Encoding.UTF8;
        response.Write("{\"success\":" + (success ? "true" : "false") + ",\"message\":\"" + HttpUtility.JavaScriptStringEncode(message) + "\"}");
        response.Flush();
        response.SuppressContent = true;
        HttpContext.Current.ApplicationInstance.CompleteRequest();
    }

    private static string Param(HttpRequest request, string name)
    {
        return (request.QueryString[name] ?? "").Trim();
    }

    private static string OneLine(string value)
    {
        return value.Replace("\r", " ").Replace("\n", " ").Trim();
    }

    private static string Capitalize(string value)
    {
        return value.Length == 0 ? value : char.ToUpperInvariant(value[0]) + value.Substring(1);
    }

    private static string Enc(string value)
    {
        return HttpUtility.HtmlEncode(value ?? "");
    }

    private static string Setting(string key, string fallback)
    {
        string value = ConfigurationManager.AppSettings[key];
        return string.IsNullOrWhiteSpace(value) ? fallback : value.Trim();
    }
}
