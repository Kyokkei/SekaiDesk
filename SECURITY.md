# Security Policy

## Scope & Architecture Notes

- **SekaiDesk** runs locally as a per-user Windows desktop shell (`C++20` + `Qt 6.8 Quick`).
- It has **no backend server, telemetry, or bundled API keys**.
- External network requests are limited to public unauthenticated endpoints used by optional widgets (`Open-Meteo` for weather forecasts and `LRCLIB` for lyrics lookup).

## Supported Versions

| Version | Supported |
|---|---|
| `0.1.x` / `main` | ✅ Yes |

## Reporting a Vulnerability

If you discover a security issue (such as unsafe privilege handling, arbitrary code execution via crafted config/IPC, or installer/DLL hijacking):

1. Please **do not** open a public issue with exploit details.
2. Use **[GitHub Private Vulnerability Reporting](https://github.com/Kyokkei/SekaiDesk/security/advisories/new)** on this repository to share reproduction steps privately.
3. Expect an initial response as soon as time permits (solo-maintained project).
