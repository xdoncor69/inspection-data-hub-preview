# Inspection Data Hub for Windows

Portable Windows x64 executable, built with Electron. No installation or Python runtime required. The portable launcher extracts its runtime into a temporary folder; login and pending submissions persist in the Windows user profile under InspectionDataHub.

Run `npm ci` and `npm run build:win` from this directory to package the current repository HTML. Output: `dist/InspectionDataHub-Portable-1.0.1-x64.exe`.

The catalog remains online in Supabase. Sessions are device-specific. This build is unsigned; removing unknown-publisher warnings requires a trusted code-signing identity. SmartScreen also evaluates reputation, so signing alone cannot guarantee no warning.
