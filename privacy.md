# Privacy Policy for IconCraft

**Last Updated: August 16, 2026**

This Privacy Policy describes how IconCraft (“the app”), developed by Jiaqiang Song (“we”, “us”, or “our”), handles information when you use the IconCraft macOS application.

IconCraft is a local developer tool for generating and replacing iOS app icon catalogs on your Mac.

### 1. No Personal Data Collection

IconCraft does not collect, transmit, or share personally identifiable information, usage metrics, analytics, crash reports, or telemetry.

We do not create user accounts, and we do not require you to provide a name, email address, or other personal details to use the app.

### 2. Local File Processing

All image resizing, pixel-difference comparison, and `.appiconset` catalog writes run entirely on your Mac. Source images and generated icon files are never uploaded to us or to any third-party service.

Files you work with remain on your device:

- **Source images and Xcode projects** are accessed only after you choose them in the system file picker (`NSOpenPanel`). Access is limited to those security-scoped locations.
- **Download** writes a generated `AppIcon.appiconset` to your macOS Downloads folder. That folder is used only to save the catalog you asked to export.
- **Replace AppIcon** writes generated icon files into the `.appiconset` you selected.

IconCraft operates inside the macOS App Sandbox and does not scan unrelated files on your Mac.

### 3. Network and Third-Party Services

IconCraft does not connect to the internet, does not use our servers, and does not include advertising, analytics, or tracking SDKs.

Any network activity related to installing or updating the app is performed by Apple through the Mac App Store, not by IconCraft.

### 4. Children

IconCraft is a developer tool and is not directed at children under 13. Because the app does not collect personal data, we do not knowingly collect personal information from children.

### 5. Changes to This Policy

We may update this Privacy Policy from time to time. Changes will be posted on this page with a revised “Last Updated” date.

### 6. Contact

If you have questions about this Privacy Policy, contact us through:

- **GitHub Issues:** https://github.com/SongJiaqiang/IconCraft/issues
