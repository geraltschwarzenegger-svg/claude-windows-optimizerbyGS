use crate::{
    host,
    model::{Reply, Request},
};
use anyhow::{bail, Context, Result};
use std::{
    fs,
    io::{BufRead, BufReader, Write},
    path::Path,
    process::{Child, ChildStdin, Command, Stdio},
    sync::mpsc::{self, Receiver, SyncSender},
    thread,
};

pub const PAYLOAD: &str = include_str!(concat!(env!("OUT_DIR"), "/backend.ps1"));
pub enum Event {
    Output(String),
    Request(Request),
    PipeError(String),
}
pub fn parse_line(line: &str, prefix: &str) -> Result<Event> {
    if let Some(json) = line.strip_prefix(prefix) {
        if json.len() > 2_000_000 {
            bail!("Слишком большой запрос интерфейса");
        }
        let request: Request = serde_json::from_str(json).context("Неверный JSON от движка")?;
        if !matches!(request.kind.as_str(), "menu" | "input" | "pause" | "status") {
            bail!("Неизвестный тип запроса интерфейса");
        }
        Ok(Event::Request(request))
    } else {
        Ok(Event::Output(crate::model::clean(line)))
    }
}
fn read_pipe(reader: impl std::io::Read + Send + 'static, prefix: String, tx: SyncSender<Event>) {
    thread::spawn(move || {
        for line in BufReader::new(reader).lines() {
            let event = match line {
                Ok(line) => match parse_line(&line, &prefix) {
                    Ok(event) => event,
                    Err(e) => Event::PipeError(e.to_string()),
                },
                Err(e) => Event::PipeError(e.to_string()),
            };
            if tx.send(event).is_err() {
                break;
            }
        }
    });
}
pub struct Backend {
    pub child: Child,
    stdin: ChildStdin,
    pub events: Receiver<Event>,
}
impl Backend {
    pub fn start(root: &Path, directory: &Path, route: &str) -> Result<Self> {
        host::require_windows()?;
        let valid = crate::model::catalog()
            .iter()
            .any(|e| e.selectable && e.value.as_str() == Some(route));
        if !valid {
            bail!("Неизвестный раздел: {route}");
        }
        let path = directory.join("backend.ps1");
        fs::write(&path, PAYLOAD)?;
        let prefix = format!("EXOVANCE-{} ", uuid::Uuid::new_v4());
        let mut child = Command::new(host::powershell()?)
            .args([
                "-NoLogo",
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
            ])
            .arg(path)
            .env("THIS", root.join("Exovance.exe"))
            .env("EXOVANCE_ROUTE", route)
            .env("EXOVANCE_WIRE_PREFIX", &prefix)
            .env("LLC_MENU_DEBUG_LOG", directory.join("powershell.txt"))
            .env_remove("LLC_RUN_CHECK")
            .env_remove("LLC_MENU_DEMO")
            .env_remove("LLC_MENU_SNAPSHOT")
            .current_dir(root)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()?;
        let stdin = child.stdin.take().context("Нет stdin движка")?;
        let (tx, events) = mpsc::sync_channel(256);
        read_pipe(
            child.stdout.take().context("Нет stdout движка")?,
            prefix.clone(),
            tx.clone(),
        );
        read_pipe(
            child.stderr.take().context("Нет stderr движка")?,
            prefix,
            tx,
        );
        Ok(Self {
            child,
            stdin,
            events,
        })
    }
    pub fn reply(&mut self, reply: &Reply) -> Result<()> {
        serde_json::to_writer(&mut self.stdin, reply)?;
        self.stdin.write_all(b"\n")?;
        self.stdin.flush()?;
        Ok(())
    }
}
impl Drop for Backend {
    fn drop(&mut self) {
        if matches!(self.child.try_wait(), Ok(None)) {
            let _ = self.child.kill();
        }
        let _ = self.child.wait();
    }
}
pub fn check(root: &Path) -> Result<i32> {
    host::require_windows()?;
    let directory = std::env::temp_dir().join(format!("Exovance-check-{}", uuid::Uuid::new_v4()));
    fs::create_dir(&directory)?;
    let result = (|| {
        let path = directory.join("backend.ps1");
        fs::write(&path, PAYLOAD)?;
        let output = Command::new(host::powershell()?)
            .args([
                "-NoLogo",
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
            ])
            .arg(path)
            .env("THIS", root.join("Exovance.exe"))
            .env("LLC_RUN_CHECK", "1")
            .env_remove("LLC_MENU_DEMO")
            .env_remove("LLC_MENU_SNAPSHOT")
            .output()?;
        print!("{}", host::output_text(&output));
        Ok(output.status.code().unwrap_or(1))
    })();
    let _ = fs::remove_dir_all(directory);
    result
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn only_authenticated_prefix_can_open_a_menu() {
        let event = parse_line("EXOVANCE-fake {\"kind\":\"menu\"}", "EXOVANCE-real ").unwrap();
        assert!(matches!(event, Event::Output(_)));
    }
    #[test]
    fn malformed_protocol_and_unknown_requests_fail_closed() {
        assert!(parse_line("p not json", "p ").is_err());
        assert!(parse_line("p {\"kind\":\"execute\",\"title\":\"whoami\"}", "p ").is_err());
    }
    #[test]
    fn menu_reply_serializes_original_index_not_an_expression() {
        let text = serde_json::to_string(&Reply {
            id: 42,
            index: 8,
            ..Default::default()
        })
        .unwrap();
        assert!(text.contains("\"index\":8"));
        assert!(!text.contains("command"));
    }
    #[test]
    fn embedded_payload_retains_presets_but_not_startup_service_initialization() {
        assert!(PAYLOAD.starts_with('\u{feff}'));
        assert!(PAYLOAD.contains("function Invoke-AutoRegistryTweaks"));
        assert!(PAYLOAD.contains("function Set-AutostartItemStatus"));
        assert!(PAYLOAD.contains("function Invoke-AutostartFullListMenu"));
        assert!(!PAYLOAD.contains("try {\n    Initialize-TrustedInstallerToken\n}"));
    }
}
