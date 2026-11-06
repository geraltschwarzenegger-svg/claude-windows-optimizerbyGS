use std::{env, fs, path::PathBuf};

fn main() {
    let base = PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").unwrap());
    let cmd = base.join("../Low-Latency-Corp-Menu_v2.cmd");
    let bridge = base.join("bridge/terminal.ps1");
    println!("cargo:rerun-if-changed={}", cmd.display());
    println!("cargo:rerun-if-changed={}", bridge.display());
    let source = fs::read_to_string(cmd)
        .expect("Read the distributed CMD as UTF-8")
        .replace("\r\n", "\n");
    let (_, payload) = source
        .split_once("### POWERSHELL STARTS HERE ###\n")
        .expect("CMD payload marker");
    let admin = "\nif (-not (Test-Admin)) {\n    Clear-ConsoleScreen";
    let start = payload.find(admin).expect("Reviewed legacy entry point");
    let main = "\nwhile ($true) {\n    $mainMenuItems = @(Get-LlcMainMenuItems";
    let menu = payload[start..]
        .find(main)
        .map(|n| n + start)
        .expect("Reviewed main menu");
    // UI overrides run after the function declarations. Do not start TrustedInstaller at startup.
    // Existing per-action permission fallback remains owned by the original action functions.
    let bootstrap = "[Console]::InputEncoding = [Text.UTF8Encoding]::new($false)\n[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)\n$OutputEncoding = [Text.UTF8Encoding]::new($false)\n";
    let legacy_prefix = &payload[..start];
    let trap_start = legacy_prefix
        .find("\ntrap {\n    $err = $_")
        .expect("Legacy UI trap");
    let trap_end = legacy_prefix[trap_start..]
        .find("\nfunction Clear-ConsoleScreen")
        .map(|n| n + trap_start)
        .expect("End of legacy UI trap");
    // A failed backend must report and exit, rather than block on Console.ReadKey in a pipe.
    let fatal_trap = r#"
trap {
    $detail = $_.Exception.ToString() + [Environment]::NewLine + $_.ScriptStackTrace
    [Console]::Out.WriteLine($env:EXOVANCE_WIRE_PREFIX + (ConvertTo-Json -Compress -InputObject @{kind='status';level='error';title=$detail}))
    [Console]::Out.Flush()
    exit 1
}
"#;
    let prefix = format!(
        "{}{}{}",
        &legacy_prefix[..trap_start],
        fatal_trap,
        &legacy_prefix[trap_end..]
    );
    let result = format!(
        "{bootstrap}{}\n{}\n{}",
        prefix,
        fs::read_to_string(bridge)
            .unwrap()
            .trim_start_matches('\u{feff}'),
        &payload[menu..]
    );
    let out = PathBuf::from(env::var_os("OUT_DIR").unwrap()).join("backend.ps1");
    // BOM is required by Windows PowerShell 5.1 for Russian source text.
    fs::write(out, format!("\u{feff}{result}")).unwrap();
}
