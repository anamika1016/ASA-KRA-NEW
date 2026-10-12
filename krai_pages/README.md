# ASA KRA mail page for krai

The ASA KRA portal (asakra.asaindia.org) sends all its notification mails through
one krai page, `asakra_notification.aspx`, the same way Apurti uses krai. The KRA
server calls the page with GET parameters, and the page sends one HTML mail to
`to_email`. The `mail_type` parameter tells the page which mail it is.

## Files

| File | What it is |
| --- | --- |
| asakra_notification.aspx | The one page the KRA server calls |
| App_Code/AsakraMail.cs | Builds the HTML mail and sends it |
| web.config.sample | Settings to merge into krai's web.config |

## Setup

1. Copy `asakra_notification.aspx` to the krai site root (next to `nemail.aspx`).
2. Copy `App_Code/AsakraMail.cs` to the site's `App_Code` folder.
   In a Web Application project (not a Web Site), add the file to the project with
   Build Action = Compile and rebuild.
3. Merge `web.config.sample` into krai's `web.config`: the SMTP details, the
   sender, and the `<location>` entry if krai uses a login.
4. Put the KRA server's public IP in `AsakraAllowedIps`, so only the KRA server
   can send mails through the page.
5. Requires .NET Framework 4.0 or newer.

## Parameters

`to_email, to_name, subject, message, link, employee_name, employee_code,
quarter, month, reviewer_role, reviewer_name, action, remarks, mail_type`

- `to_email` is required. The other parameters may be empty.
- `subject` is used as the mail subject. `message` is the main text.
- The other parameters are shown in a details table in the mail; empty ones are left out.
- `link` becomes a button in the mail. It must start with `https://asakra.asaindia.org`.
- All values are HTML-encoded, so text in a parameter cannot change the mail layout.

## mail_type values

| mail_type | Sent to | When | Mail colour |
| --- | --- | --- | --- |
| kra_submitted_to_l1 | L1 manager | Employee with no observers submits a month | Blue |
| kra_submitted_to_observer | Each observer (OB1-OB4) | Employee submits a month | Blue |
| kra_observers_approved_to_l1 | L1 manager | All observers approved the month | Blue |
| employee_observer_approved | Employee | Observer approved | Green |
| employee_observer_returned | Employee | Observer returned | Red |
| employee_l1_approved | Employee | L1 approved | Green |
| employee_l1_returned | Employee | L1 returned | Red |
| employee_l2_approved | Employee | L2 approved | Green |
| employee_l2_returned | Employee | L2 returned | Red |
| employee_pli_approved | Employee | Quarterly PLI approved | Green |
| employee_pli_returned | Employee | Quarterly PLI returned | Red |

An unknown or empty `mail_type` still sends the mail, with a general heading.

## Response

| Result | HTTP | Body |
| --- | --- | --- |
| Mail sent | 200 | `{"success":true,"message":"Email sent"}` |
| to_email missing or invalid | 400 | `{"success":false,...}` |
| Caller IP not allowed | 403 | `{"success":false,...}` |
| SMTP error | 500 | `{"success":false,"message":"Email not sent: ..."}` |

The KRA server treats anything other than 200 with `"success":true` as a
failure and logs it.

## Test

Open this in a browser (put your own email in `to_email`):

```
https://krai.asaindia.org/asakra_notification.aspx?to_email=you%40asaindia.org&to_name=Asha+Devi&subject=Your+KRA+MIS+April+%28Q1+%28APR-JUN%29%29+approved+by+L1+Ramesh+Kumar&message=Dear+Asha+Devi%2C+your+KRA+MIS+for+April+%28Q1+%28APR-JUN%29%29+has+been+approved+by+L1+Ramesh+Kumar.+Remarks%3A+Good+work&link=https%3A%2F%2Fasakra.asaindia.org%2Fuser_details%2Fget_user_detail&employee_name=Asha+Devi&employee_code=E-101&quarter=Q1+%28APR-JUN%29&month=April&reviewer_role=L1&reviewer_name=Ramesh+Kumar&action=approved&remarks=Good+work&mail_type=employee_l1_approved
```

The page should show `{"success":true,"message":"Email sent"}` and the mail
should arrive.

## After the page is live

Tell the KRA team. They set
`KRA_MAIL_RELAY_URL=https://krai.asaindia.org/asakra_notification.aspx` on the
KRA server, and mails start going.
