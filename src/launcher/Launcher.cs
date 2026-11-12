using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;
[assembly: AssemblyTitle("Scenario Installer")]
[assembly: AssemblyDescription("Scenario Installer")]
[assembly: AssemblyProduct("Scenario Installer")]
[assembly: AssemblyCompany("Scenario Installer")]
[assembly: AssemblyVersion("1.0.7.0")]
[assembly: AssemblyFileVersion("1.0.7.0")]
static class Program {
    [STAThread]
    static int Main(string[] args) {
        try {
            string dir = Path.Combine(Path.GetTempPath(), "ScenarioInstaller");
            Directory.CreateDirectory(dir);
            string ps1 = Path.Combine(dir, "Install-Scenario.ps1");
            using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("Install-Scenario.ps1"))
            using (FileStream f = new FileStream(ps1, FileMode.Create, FileAccess.Write)) { s.CopyTo(f); }
            string win = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
            // prefer 64-bit PowerShell even if this exe was started as 32-bit
            string ps = Path.Combine(win, @"Sysnative\WindowsPowerShell\v1.0\powershell.exe");
            if (!File.Exists(ps)) ps = Path.Combine(win, @"System32\WindowsPowerShell\v1.0\powershell.exe");
            if (!File.Exists(ps)) ps = "powershell.exe";
            string extra = "";
            foreach (string a in args) extra += " \"" + a.Replace("\"", "\\\"") + "\"";
            bool console = Array.Exists(args, a => a.Equals("-NoGui", StringComparison.OrdinalIgnoreCase) || a.Equals("-ListOnly", StringComparison.OrdinalIgnoreCase));
            ProcessStartInfo psi = new ProcessStartInfo(ps,
                "-NoProfile -ExecutionPolicy Bypass -STA " + (console ? "" : "-WindowStyle Hidden ") + "-File \"" + ps1 + "\"" + extra);
            psi.UseShellExecute = false;
            // lets the script find installer.json next to this exe (the script itself runs from %TEMP%)
            psi.EnvironmentVariables["SCENARIO_INSTALLER_DIR"] = AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\');
            psi.CreateNoWindow = !console;
            Process p = Process.Start(psi);
            p.WaitForExit();
            return p.ExitCode;
        } catch (Exception ex) {
            MessageBox.Show("Could not start the installer:\n\n" + ex.Message +
                "\n\nYou can run Install-Scenario.bat instead.", "Scenario Installer",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
