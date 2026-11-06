use crate::{host, journal::Journal};
use anyhow::{bail, Context, Result};
use serde_json::json;
use std::path::{Path, PathBuf};
use uuid::Uuid;

pub const EXOVANCE_GUID: &str = "8b24b027-1dee-4c65-8f35-5d5d91e51d87";
pub const NAME: &str = "Exovance v2";
pub const DESCRIPTION: &str = "Made by Exovance";
#[derive(Debug, Clone)]
pub struct Scheme {
    pub id: Uuid,
    pub name: String,
    pub active: bool,
}

pub fn parse_schemes(text: &str) -> Vec<Scheme> {
    text.lines()
        .filter_map(|line| {
            let (offset, id) = line
                .char_indices()
                .filter(|(_, c)| c.is_ascii_hexdigit())
                .find_map(|(offset, _)| {
                    let token = line.get(offset..offset + 36)?;
                    Uuid::parse_str(token).ok().map(|id| (offset, id))
                })?;
            let tail = line.get(offset + 36..)?.trim();
            let name = tail
                .find('(')
                .zip(tail.rfind(')'))
                .map(|(a, b)| tail[a + 1..b].trim())
                .unwrap_or(tail.trim_end_matches('*').trim());
            Some(Scheme {
                id,
                name: crate::model::clean(name),
                active: tail.ends_with('*'),
            })
        })
        .collect()
}
pub trait PowerCommand {
    fn command(&mut self, args: &[String]) -> Result<String>;
}
pub struct WindowsPower;
impl PowerCommand for WindowsPower {
    fn command(&mut self, args: &[String]) -> Result<String> {
        host::run("powercfg.exe", args)
    }
}
fn args(words: &[&str]) -> Vec<String> {
    words.iter().map(|s| s.to_string()).collect()
}
pub fn list(runner: &mut impl PowerCommand) -> Result<Vec<Scheme>> {
    let list = parse_schemes(&runner.command(&args(&["/list"]))?);
    if list.is_empty() {
        bail!("Не удалось прочитать список схем; записи не выполнялись.");
    }
    Ok(list)
}
pub fn active(runner: &mut impl PowerCommand) -> Result<Uuid> {
    parse_schemes(&runner.command(&args(&["/getactivescheme"]))?)
        .first()
        .map(|s| s.id)
        .context("Windows не сообщила GUID активной схемы")
}
pub fn activation_plan(existing: bool, source: &Path, id: Uuid) -> Vec<Vec<String>> {
    let mut commands = Vec::new();
    if !existing {
        commands.push(vec![
            "/import".into(),
            source.to_string_lossy().into_owned(),
            id.to_string(),
        ]);
    }
    commands.push(vec![
        "/changename".into(),
        id.to_string(),
        NAME.into(),
        DESCRIPTION.into(),
    ]);
    commands.push(vec!["/setactive".into(), id.to_string()]);
    commands
}
pub fn activate_exovance(
    runner: &mut impl PowerCommand,
    source: &Path,
    log: &mut Journal,
) -> Result<()> {
    let id = Uuid::parse_str(EXOVANCE_GUID)?;
    let schemes = list(runner)?;
    let before = active(runner)?;
    let backup = log
        .directory
        .join(format!("power-before-{}.pow", Uuid::new_v4()));
    let export = vec![
        "/export".into(),
        backup.to_string_lossy().into_owned(),
        before.to_string(),
    ];
    log.event(
        "info",
        "power_backup_requested",
        "Сохранение прежней активной схемы",
        json!({"guid":before,"path":backup.display().to_string()}),
    )?;
    runner.command(&export)?;
    if !backup.is_file() || backup.metadata()?.len() == 0 {
        bail!("Резервная копия схемы не создана; импорт и активация отменены.");
    }
    for command in activation_plan(schemes.iter().any(|s| s.id == id), source, id) {
        log.event(
            "info",
            "power_command_requested",
            "Выполняется powercfg",
            json!({"arguments":command}),
        )?;
        let text = runner.command(&command)?;
        log.output(&text)?;
    }
    let after = active(runner)?;
    if after != id {
        bail!("Запрос выполнен, но Windows сообщила другую активную схему: {after}");
    }
    log.event(
        "info",
        "power_active_verified",
        "Windows подтвердила активную схему Exovance v2",
        json!({"before":before,"after":after,"backup":backup.display().to_string()}),
    )?;
    Ok(())
}
pub fn source(root: &Path) -> Result<PathBuf> {
    host::resolve_resource(
        root,
        "Resources/POWER-PLAN/EXOVANCE.pow",
        Some("POWER-PLAN/EXOVANCE.pow"),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn localized_schemes_and_nested_parentheses_are_preserved() {
        let rows=parse_schemes("Схема электропитания: 8b24b027-1dee-4c65-8f35-5d5d91e51d87 (Exovance (мой ПК)) *\nHeading without a GUID");
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].name, "Exovance (мой ПК)");
        assert!(rows[0].active);
    }
    #[test]
    fn existing_scheme_updates_description_without_reimporting_settings() {
        let plan = activation_plan(
            true,
            Path::new("test.pow"),
            Uuid::parse_str(EXOVANCE_GUID).unwrap(),
        );
        assert_eq!(plan.len(), 2);
        assert_eq!(plan[0][0], "/changename");
        assert_eq!(plan[0][3], DESCRIPTION);
    }
    #[test]
    fn path_with_spaces_and_shell_metacharacters_is_a_single_argument() {
        let source = Path::new("C:/Мой каталог/a & b.pow");
        let plan = activation_plan(false, source, Uuid::parse_str(EXOVANCE_GUID).unwrap());
        assert_eq!(
            plan[0],
            vec!["/import", source.to_str().unwrap(), EXOVANCE_GUID]
        );
    }
    #[test]
    fn failed_backup_never_reaches_import_or_activation() {
        struct FailBackup {
            writes: usize,
        }
        impl PowerCommand for FailBackup {
            fn command(&mut self, args: &[String]) -> Result<String> {
                match args[0].as_str() {
                    "/list" | "/getactivescheme" => {
                        Ok(format!("GUID: {EXOVANCE_GUID} (Exovance) *"))
                    }
                    "/export" => bail!("Simulated disk failure"),
                    _ => {
                        self.writes += 1;
                        Ok(String::new())
                    }
                }
            }
        }
        let root = std::env::temp_dir().join(format!("exovance-test-{}", Uuid::new_v4()));
        let mut log = Journal::create(&root).unwrap();
        let mut runner = FailBackup { writes: 0 };
        assert!(activate_exovance(&mut runner, Path::new("fake.pow"), &mut log).is_err());
        assert_eq!(runner.writes, 0);
        drop(log);
        std::fs::remove_dir_all(root).unwrap();
    }
}
