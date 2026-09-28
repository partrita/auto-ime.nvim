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

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinIME {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("imm32.dll")] public static extern IntPtr ImmGetDefaultIMEWnd(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr SendMessageA(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

    public static int ToLatin() {
        IntPtr fg = GetForegroundWindow();
        if (fg == IntPtr.Zero) return -1;
        IntPtr ime = ImmGetDefaultIMEWnd(fg);
        if (ime == IntPtr.Zero) return -2;
        SendMessageA(ime, 0x0283, (IntPtr)0x0006, IntPtr.Zero);
        SendMessageA(ime, 0x0283, (IntPtr)0x0002, IntPtr.Zero);
        return 0;
    }
}
"@

$listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, $Port)
try {
    $listener.Start()
} catch {
    Write-Host "Failed to bind to port $Port. It may already be in use: $_" -ForegroundColor Red
    exit 1
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " [auto-ime] SSH Bridge Daemon running on 127.0.0.1:${Port}" -ForegroundColor Green
Write-Host " Connect with: ssh -R ${Port}:127.0.0.1:${Port} user@remote" -ForegroundColor Yellow
Write-Host " Waiting for signals from remote Neovim... (Ctrl+C to stop)" -ForegroundColor Gray
Write-Host "==========================================================" -ForegroundColor Cyan

try {
    while ($true) {
        while (-not $listener.Pending()) {
            Start-Sleep -Milliseconds 100
        }
        $client = $listener.AcceptTcpClient()
        $stream = $client.GetStream()
        
        # Switch IME to Latin on local active window
        $res = [WinIME]::ToLatin()
        
        $time = (Get-Date).ToString("HH:mm:ss.fff")
        Write-Host "[$time] Signal received! Switched local IME to Latin (res=$res)" -ForegroundColor Green

        # Send quick HTTP OK response in case remote uses HTTP/curl
        try {
            $responseBytes = [System.Text.Encoding]::ASCII.GetBytes("HTTP/1.0 200 OK`r`nContent-Length: 2`r`n`r`nOK")
            $stream.Write($responseBytes, 0, $responseBytes.Length)
        } catch { }

        $client.Close()
    }
} finally {
    $listener.Stop()
    Write-Host "`nDaemon stopped." -ForegroundColor Yellow
}
