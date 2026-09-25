# Copilot Key Switcher

Windows 11 lets you remap the Copilot key in Settings, but the list there shows apps that registered as Copilot key providers. Claude and the current ChatGPT app haven't registered, so you can't pick them.

This tool sets the **Set Copilot Hardware Key** policy that Microsoft documents for IT admins. The policy takes any app ID.

## Use it

1. Click **Code > Download ZIP** and unzip it.
2. Double-click `CopilotKeySwitcher.cmd`.
3. Pick an app or paste an app ID, then click **Apply** and approve the admin prompt.
4. Sign out and back in.

The window lists AI apps it finds on your PC: Claude, ChatGPT, Microsoft Copilot, Microsoft 365 Copilot, Perplexity, Gemini, Grok, Codex, Le Chat and DeepSeek. Tick **Show all installed apps** to pick anything in your Start menu. **Reset to Windows default** removes the policy and hands control back to Settings.

## Command line

```powershell
.\CopilotKeySwitcher.ps1 -List                          # current setting and AI apps found
.\CopilotKeySwitcher.ps1 -All                           # every Start menu app with its ID
.\CopilotKeySwitcher.ps1 -App Claude                    # a name from -List or -All
.\CopilotKeySwitcher.ps1 -App 'Publisher.App_abc123!App' # or an app ID
.\CopilotKeySwitcher.ps1 -Reset
```

If PowerShell blocks the script, run it as `powershell -ExecutionPolicy Bypass -File .\CopilotKeySwitcher.ps1 ...`.

## Custom apps

Run `Get-StartApps` in PowerShell to see app IDs. Store and MSIX apps have a `!` in the ID, like `Claude_pzs8sxrjxfjjc!Claude`. Microsoft's docs describe the Copilot key launching packaged, signed apps. The window grays out regular desktop programs because Windows may ignore them and open search.

## Details

- The script writes `SetCopilotHardwareKey` to `HKCU\Software\Policies\Microsoft\Windows\CopilotKey`. Group Policy Editor sets the same value at User Configuration > Administrative Templates > Windows Components > Windows Copilot > Set Copilot Hardware Key.
- Windows lets admins write that key, so **Apply** shows a UAC prompt. The script hands your account's SID to the elevated copy. If you approve with a separate admin account, your own setting still changes.
- Microsoft lists the policy for Windows 11 22H2 and later on Pro, Enterprise and Education. Home may ignore it.
- You can still change the key in Settings after applying. The policy sets the starting choice.

Microsoft docs: [Copilot key providers](https://learn.microsoft.com/en-us/windows/apps/develop/windows-integration/microsoft-copilot-key-provider), [SetCopilotHardwareKey policy](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-windowsai#setcopilothardwarekey).

## License

MIT
