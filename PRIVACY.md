# Toolpath Privacy Policy

_Last updated: 12 October 2026 · Web version: https://yakupad.github.io/toolpath-apple/privacy/_

Toolpath is built so that your data stays yours.

**No account.** Toolpath has no sign-up and no login.

**Your data stays on your devices and in your iCloud.** G-code files,
machines, tools, recipes, job history and stock are stored on your device.
If iCloud is enabled, they sync through your own private iCloud database,
which only you can access. The developer cannot see it.

**Analysis happens on your device.** G-code parsing, safety checks,
feeds and speeds and all calculators run locally, with no network access.

**Assistant.** Where Apple Intelligence is available, the assistant runs on
your device. Elsewhere it can use a cloud model: only then are your question,
up to the last six messages and the matching built-in workshop notes sent to
the Toolpath server (Cloudflare) and on to Anthropic's Claude to write the
answer. The server does not store them; Anthropic does not train on them and
may keep them for a limited time for safety monitoring. G-code files and
library data are never sent.

**Random account identifier.** A random id kept in your iCloud counts cloud
questions and delivers purchases to your devices. The server stores only that
id with your plan, monthly question count and question packs.

**Live machine monitor.** If you use the optional live monitor, Toolpath
connects to the controller address you enter on your local network and only
reads its status. Nothing from that connection is sent anywhere else.

**Purchases** are handled by Apple. The developer receives no payment
details; Apple's signed transaction record is checked by the Toolpath server
to unlock Pro and question packs.

**Analytics and tracking.** Toolpath does not track you and does not
share data with advertisers or data brokers. Apple may provide the
developer with aggregated, anonymous crash and usage statistics if you
opted in to sharing them with app developers in iOS settings.

**Questions:** open an issue at https://github.com/yakupad/toolpath-apple/issues
