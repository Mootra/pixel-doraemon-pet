using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Windows.Forms;

internal static class PixelDoraemonCompanionLauncher
{
    [STAThread]
    private static void Main()
    {
        try
        {
            string pluginRoot = FindPluginRoot();
            if (pluginRoot == null)
            {
                throw new InvalidOperationException(
                    "Pixel Doraemon Companion is not installed. Install the pixel-doraemon marketplace plugin first.");
            }

            string startScript = Path.Combine(pluginRoot, "scripts", "start-companion.ps1");
            string powershell = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.System),
                "WindowsPowerShell",
                "v1.0",
                "powershell.exe");

            ProcessStartInfo startInfo = new ProcessStartInfo();
            startInfo.FileName = powershell;
            startInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + startScript + "\"";
            startInfo.WorkingDirectory = pluginRoot;
            startInfo.UseShellExecute = false;
            startInfo.CreateNoWindow = true;
            startInfo.WindowStyle = ProcessWindowStyle.Hidden;
            Process.Start(startInfo);
        }
        catch (Exception error)
        {
            Application.EnableVisualStyles();
            MessageBox.Show(
                error.Message,
                "Pixel Doraemon Companion",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
        }
    }

    private static string FindPluginRoot()
    {
        string codexHome = Environment.GetEnvironmentVariable("CODEX_HOME");
        if (String.IsNullOrWhiteSpace(codexHome))
        {
            codexHome = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                ".codex");
        }

        string cacheRoot = Path.Combine(codexHome, "plugins", "cache");
        string preferredPlugin = Path.Combine(
            cacheRoot,
            "pixel-doraemon",
            "pixel-doraemon-companion");
        string preferred = FindNewestValidVersion(preferredPlugin);
        if (preferred != null)
        {
            return preferred;
        }

        if (!Directory.Exists(cacheRoot))
        {
            return null;
        }

        return Directory.GetDirectories(cacheRoot)
            .Select(path => Path.Combine(path, "pixel-doraemon-companion"))
            .Select(FindNewestValidVersion)
            .Where(path => path != null)
            .OrderByDescending(GetManifestWriteTimeUtc)
            .FirstOrDefault();
    }

    private static string FindNewestValidVersion(string pluginDirectory)
    {
        if (!Directory.Exists(pluginDirectory))
        {
            return null;
        }

        return Directory.GetDirectories(pluginDirectory)
            .Where(IsValidPluginRoot)
            .OrderByDescending(GetManifestWriteTimeUtc)
            .FirstOrDefault();
    }

    private static bool IsValidPluginRoot(string path)
    {
        return File.Exists(Path.Combine(path, ".codex-plugin", "plugin.json")) &&
               File.Exists(Path.Combine(path, "scripts", "start-companion.ps1"));
    }

    private static DateTime GetManifestWriteTimeUtc(string path)
    {
        string manifest = Path.Combine(path, ".codex-plugin", "plugin.json");
        return File.Exists(manifest) ? File.GetLastWriteTimeUtc(manifest) : DateTime.MinValue;
    }
}
