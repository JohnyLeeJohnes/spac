using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace Spac;

public enum PowerAction { Shutdown, Restart, Hibernate, LogOff }

/// <summary>Tenká obálka nad shutdown.exe.</summary>
public static class Shutdown
{
    public const int NothingScheduled = 1116;
    public const int AlreadyScheduled = 1190;

    [DllImport("powrprof.dll")]
    [return: MarshalAs(UnmanagedType.U1)]
    private static extern bool IsPwrHibernateAllowed();

    [DllImport("kernel32.dll")]
    private static extern int GetOEMCP();

    public static bool CanHibernate => IsPwrHibernateAllowed();

    // /h a /l přepínač /t neznají, takže u nich odpočítává Spáč sám.
    public static bool TimedByWindows(PowerAction action) =>
        action is PowerAction.Shutdown or PowerAction.Restart;

    public static string Arguments(PowerAction action, int seconds, bool force, bool hybrid, bool restoreApps)
    {
        var args = new List<string>();
        switch (action)
        {
            case PowerAction.Shutdown:
                // /sg a /hybrid se navzájem vylučují, shutdown.exe tu kombinaci odmítne.
                args.Add(restoreApps ? "/sg" : "/s");
                if (hybrid && !restoreApps) args.Add("/hybrid");
                break;
            case PowerAction.Restart:
                args.Add(restoreApps ? "/g" : "/r");
                break;
            case PowerAction.Hibernate:
                args.Add("/h");
                break;
            case PowerAction.LogOff:
                args.Add("/l");
                break;
        }

        if (force) args.Add("/f");
        if (TimedByWindows(action)) args.Add("/t " + seconds);
        return string.Join(" ", args);
    }

    public static (int Code, string Message) Run(string arguments)
    {
        var oem = Encoding.GetEncoding(GetOEMCP());
        var info = new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, "shutdown.exe"), arguments)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            StandardOutputEncoding = oem,
            StandardErrorEncoding = oem,
        };

        try
        {
            using var process = Process.Start(info)!;
            string message = process.StandardError.ReadToEnd() + process.StandardOutput.ReadToEnd();
            process.WaitForExit();
            return (process.ExitCode, message.Trim());
        }
        catch (Exception e)
        {
            return (-1, e.Message);
        }
    }
}

/// <summary>Běžící odpočet. U akcí časovaných Windows se ukládá na disk, aby šel po znovuotevření zrušit.</summary>
public sealed class Countdown
{
    public PowerAction Action;
    public int Seconds;
    public string Arguments = "";
    public DateTime Due; // UTC

    public bool TimedByWindows => Shutdown.TimedByWindows(Action);

    private static string StatePath => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Spac", "pending");

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(StatePath)!);
            File.WriteAllText(StatePath, $"{Due.Ticks}|{(int)Action}|{Seconds}|{Arguments}");
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    public static Countdown? Load()
    {
        try
        {
            string[] parts = File.ReadAllText(StatePath).Split(new[] { '|' }, 4);
            var countdown = new Countdown
            {
                Due = new DateTime(long.Parse(parts[0]), DateTimeKind.Utc),
                Action = (PowerAction)int.Parse(parts[1]),
                Seconds = int.Parse(parts[2]),
                Arguments = parts[3],
            };
            // Ukládají se jen odpočty Windows; nic jiného ze souboru nespouštíme.
            if (countdown.TimedByWindows && countdown.Seconds > 0 && countdown.Due > DateTime.UtcNow)
                return countdown;
        }
        catch (Exception)
        {
            // Chybějící nebo poškozený soubor = žádný odpočet.
        }

        Clear();
        return null;
    }

    public static void Clear()
    {
        try { File.Delete(StatePath); }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }
}
