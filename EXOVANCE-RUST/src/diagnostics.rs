//! Native, read-only diagnostic report. This module never applies system tweaks.
use crate::{
    host,
    power::{self, PowerCommand},
};
use anyhow::{bail, Context, Result};
use serde_json::{json, Value};
use std::{
    fs::{self, OpenOptions},
    io::Write,
    path::Path,
};

/// Collects diagnostic data without spawning PowerShell or requesting elevation.
/// The power command abstraction only receives `/list` and `/getactivescheme`.
pub fn collect(root: &Path, runner: &mut impl PowerCommand) -> Value {
    let resources = [
        (
            "Exovance power plan",
            &[
                "Resources/POWER-PLAN/EXOVANCE.pow",
                "POWER-PLAN/EXOVANCE.pow",
            ][..],
        ),
        (
            "Device Tweaker v2",
            &["DEVICE-TWEAKER-V2/RUN-EXOVANCE-V2.bat"][..],
        ),
        (
            "NVIDIA Profile Inspector",
            &["Resources/NVIDIA-PROFILE-INSPECTOR/NVPI-R.exe"][..],
        ),
        (
            "Power Scheme Manager",
            &["Resources/POWER-SCHEME-MANAGER/POWER-SCHEME-MANAGER.exe"][..],
        ),
    ]
    .into_iter()
    .map(|(name, paths)| {
        json!({
            "name": name,
            "present": paths.iter().any(|relative| root.join(relative).is_file()),
        })
    })
    .collect::<Vec<_>>();

    let mut errors = Vec::new();
    let schemes = match power::list(runner) {
        Ok(rows) => rows
            .into_iter()
            .map(|row| {
                json!({
                    "guid": row.id.to_string(),
                    "name": row.name,
                    "marked_active": row.active,
                })
            })
            .collect::<Vec<_>>(),
        Err(error) => {
            errors.push(format!("powercfg /list: {error:#}"));
            Vec::new()
        }
    };
    let active_guid = match power::active(runner) {
        Ok(id) => Some(id.to_string()),
        Err(error) => {
            errors.push(format!("powercfg /getactivescheme: {error:#}"));
            None
        }
    };

    json!({
        "schema_version": 1,
        "application": "Exovance Rust",
        "version": env!("CARGO_PKG_VERSION"),
        "collected_at": chrono::Utc::now().to_rfc3339(),
        "windows_x64": cfg!(all(windows, target_pointer_width = "64")),
        "elevated": host::is_admin(),
        "resource_root": root.display().to_string(),
        "resources": resources,
        "power": {
            "active_guid": active_guid,
            "schemes": schemes,
            "errors": errors,
        },
        "note": "Read-only diagnostics. No settings were applied. This is not an FPS, DPC or input-latency benchmark.",
    })
}

/// Never overwrites an existing report. Requires an explicit absolute .json path.
pub fn save_new(path: &Path, content: &str) -> Result<()> {
    if !path.is_absolute()
        || path
            .extension()
            .and_then(|ext| ext.to_str())
            .is_none_or(|ext| !ext.eq_ignore_ascii_case("json"))
    {
        bail!("Укажи абсолютный путь нового .json файла");
    }

    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(path)
        .with_context(|| format!("Не удалось создать отчёт: {}", path.display()))?;
    if let Err(error) = writeln!(file, "{content}") {
        drop(file);
        let _ = fs::remove_file(path);
        return Err(error).context("Не удалось записать диагностический отчёт");
    }
    file.sync_all()
        .context("Не удалось сохранить диагностический отчёт")?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use anyhow::bail;

    const GUID: &str = "8b24b027-1dee-4c65-8f35-5d5d91e51d87";

    struct FakePower {
        calls: Vec<String>,
        fail: bool,
    }

    impl PowerCommand for FakePower {
        fn command(&mut self, args: &[String]) -> Result<String> {
            self.calls.push(args.join(" "));
            if self.fail {
                bail!("simulated read error");
            }
            match args.first().map(String::as_str) {
                Some("/list") | Some("/getactivescheme") => {
                    Ok(format!("Power Scheme GUID: {GUID} (Exovance v2) *"))
                }
                _ => bail!("Unexpected or modifying command"),
            }
        }
    }

    #[test]
    fn reads_only_the_two_allowed_power_commands() {
        let mut runner = FakePower {
            calls: Vec::new(),
            fail: false,
        };
        let report = collect(Path::new("."), &mut runner);
        assert_eq!(runner.calls, ["/list", "/getactivescheme"]);
        assert_eq!(report["power"]["active_guid"], GUID);
        assert_eq!(report["power"]["schemes"][0]["name"], "Exovance v2");
        assert_eq!(report["schema_version"], 1);
        assert!(report["power"]["errors"].as_array().unwrap().is_empty());
    }

    #[test]
    fn read_errors_are_reported_and_never_trigger_writes() {
        let mut runner = FakePower {
            calls: Vec::new(),
            fail: true,
        };
        let report = collect(Path::new("."), &mut runner);
        assert_eq!(runner.calls, ["/list", "/getactivescheme"]);
        assert!(report["power"]["active_guid"].is_null());
        assert_eq!(report["power"]["errors"].as_array().unwrap().len(), 2);
    }

    #[test]
    fn output_is_new_only_and_requires_json_extension() {
        let root =
            std::env::temp_dir().join(format!("exovance-diagnostics-{}", uuid::Uuid::new_v4()));
        fs::create_dir(&root).unwrap();
        let path = root.join("report.json");
        save_new(&path, "{}").unwrap();
        assert!(save_new(&path, "changed").is_err());
        assert_eq!(fs::read_to_string(&path).unwrap(), "{}\n");
        assert!(save_new(&root.join("report.txt"), "{}").is_err());
        fs::remove_dir_all(root).unwrap();
    }
}
