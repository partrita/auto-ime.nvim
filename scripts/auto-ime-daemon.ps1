# auto-ime-daemon.ps1
# Lightweight local listener for controlling Windows IME from remote SSH Neovim sessions.
#
# Usage:
#   1. Run this script on your local Windows PC:
#      powershell -ExecutionPolicy Bypass -File .\scripts\auto-ime-daemon.ps1
#
#   2. Connect to your remote server with reverse port forwarding:
#      ssh -R 8989:127.0.0.1:8989 user@remote-server
#
#   3. Use Neovim on the remote server! When leaving Insert/Cmdline mode,
#      the remote Neovim will signal this daemon to switch your local Windows IME to Latin.

param(
    [int]$Port = 8989
)

$prefix = "http://127.0.0.1:$Port/"
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($prefix)

try {
    $listener.Start()
} catch {
    Write-Error "Failed to start listener on $prefix : $_"
    exit 1
}

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinIME {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("imm32.dll")] public static extern IntPtr ImmGetDefaultIMEWnd(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr SendMessageA(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

    public static void ToLatin() {
        IntPtr fg = GetForegroundWindow();
        if (fg == IntPtr.Zero) return;
        IntPtr ime = ImmGetDefaultIMEWnd(fg);
        if (ime == IntPtr.Zero) return;
        SendMessageA(ime, 0x0283, (IntPtr)0x0006, IntPtr.Zero);
        SendMessageA(ime, 0x0283, (IntPtr)0x0002, IntPtr.Zero);
    }
}
"@

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " auto-ime SSH Bridge Daemon running on $prefix" -ForegroundColor Green
Write-Host " Forward with: ssh -R $Port:127.0.0.1:$Port user@remote" -ForegroundColor Yellow
Write-Host " Press Ctrl+C to stop" -ForegroundColor Gray
Write-Host "==========================================================" -ForegroundColor Cyan

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        [WinIME]::ToLatin()
        $context.Response.StatusCode = 200
        $context.Response.Close()
    }
} finally {
    $listener.Stop()
    $listener.Close()
}
