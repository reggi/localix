# Localix

A small macOS menu bar app that uses Apple's on-device Speech framework and types dictated text continuously into the currently focused app.

## Privacy

The app sets `requiresOnDeviceRecognition` to `true`. If local recognition is unavailable for the current language, dictation stops instead of allowing server-based recognition. It never writes transcript content to system logs. Session history stores timestamps, word counts, stop reasons, and destination application names, not transcript text or audio. Transcript text is held in memory while dictating. The app has no networking code or third-party dependencies.

## Build and run

```sh
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open "dist/Localix.app"
```

The build uses `CODE_SIGN_IDENTITY` when supplied. Otherwise it uses a stable local ad hoc requirement so development rebuilds retain macOS permissions.

On first use, macOS asks for Accessibility, Speech Recognition, and Microphone access. Focus a text field or terminal, click the menu bar text bubble, and speak. You can also use Right Option or Right Shift, or choose `Record New Shortcut…` and type a custom modifier and key combination. Custom shortcuts require Input Monitoring permission so Localix can observe the selected keys while another app remains focused. Shortcut behavior can be set to `Hold to Record` or `Press to Start or Stop`. Recognized words are typed as they arrive, including in VS Code and terminal inputs. The app follows the currently focused app. While recording, the icon becomes a white text bubble on a solid red background so it remains distinct from macOS's microphone privacy indicator. Click the red icon to release the microphone. Right-click the icon to see the app and, when macOS provides it, the control that will receive text, choose a microphone, use the system default input, configure the shortcut, or quit. Localix shows `Types into: Not found` only when it cannot identify a destination app.

The shortcut recorder opens in a compact native macOS dialog that follows the system appearance. Type a modifier and key combination into the shortcut field to see individual keycaps, then click `Save` or press Return. Save becomes the default accent-colored button when the shortcut is valid. Invalid input shows a short explanation beneath the field. The optional `Show Keyboard` disclosure reveals a smaller keyboard without widening the dialog. Dismiss the dialog with `Cancel` or Escape.

The right-click menu also shows recent sessions with destination app names and word counts. Sessions that type into more than one app retain each app name. `Auto Stop After` limits total recording time and defaults to 10 minutes. `Silence Timeout` stops an unattended recording after no recognized speech and defaults to 1 minute. Stopping releases the microphone without changing text already typed into the destination app. Empty sessions are saved as `0 words` in history without showing an alert.

## Package a release locally

Release versions use semantic versioning.

```sh
./scripts/package-release.sh 0.1.0
```

This creates a universal Apple Silicon and Intel zip plus a SHA-256 checksum in `dist/`. The same script is used by GitHub Actions.

The checksum references only the archive filename, so both files can be moved or shared together. Verify them from the directory containing the downloaded files:

```sh
shasum -a 256 -c Localix-0.1.0-macOS-universal.zip.sha256
```

## GitHub releases

Release Please reads Conventional Commits on `main` and maintains a release pull request. Merging that pull request creates the semantic version tag and GitHub Release. The tag triggers `.github/workflows/release.yml`, which builds and uploads the universal app archive and checksum.

Use Conventional Commits locally:

```text
feat: add configurable activation shortcut
fix: preserve partial transcript spacing
```

Release versions follow semantic versioning.

The downloadable app is ad hoc signed, not completely unsigned, but it is not Developer ID signed or notarized. On first launch, macOS may block it because it came from the internet. Try to open the app once, then use **System Settings > Privacy & Security > Open Anyway** and confirm the launch. Older macOS versions may also allow the right-click **Open** method. A newly downloaded update may require this approval again. This is expected for a build made without an Apple Developer account.
