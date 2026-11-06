use anyhow::{Context, Result};
use serde_json::{json, Value};
use std::{
    fs::{self, File, OpenOptions},
    io::Write,
    path::{Path, PathBuf},
};

pub struct Journal {
    pub directory: PathBuf,
    pub report: PathBuf,
    events: File,
    transcript: File,
    pub errors: usize,
    pub warnings: usize,
    pub tail: Vec<String>,
}
impl Journal {
    pub fn create(root: &Path) -> Result<Self> {
        let directory = root.join("logs").join("rust").join(format!(
            "{}-{}",
            chrono::Local::now().format("%Y%m%d-%H%M%S"),
            uuid::Uuid::new_v4()
        ));
        fs::create_dir_all(&directory)
            .with_context(|| format!("Не удалось создать журнал: {}", directory.display()))?;
        let report = directory.join("report.txt");
        let mut log = Self {
            events: OpenOptions::new()
                .create_new(true)
                .write(true)
                .open(directory.join("events.jsonl"))?,
            transcript: OpenOptions::new()
                .create_new(true)
                .write(true)
                .open(directory.join("output.txt"))?,
            directory,
            report,
            errors: 0,
            warnings: 0,
            tail: Vec::new(),
        };
        log.event(
            "info",
            "session_started",
            "Меню открыто; применение настроек не запускалось.",
            json!({"version":env!("CARGO_PKG_VERSION")}),
        )?;
        Ok(log)
    }
    pub fn event(&mut self, level: &str, code: &str, message: &str, data: Value) -> Result<()> {
        match level {
            "error" => self.errors += 1,
            "warning" => self.warnings += 1,
            _ => (),
        };
        let message = crate::model::clean(message);
        let row = json!({"time":chrono::Local::now().to_rfc3339(),"level":level,"code":code,"message":message,"data":data});
        writeln!(self.events, "{}", serde_json::to_string(&row)?)?;
        self.events.flush()?;
        self.output(&format!("[{level}] {message}"))?;
        fs::write(&self.report,format!("EXOVANCE RUST {}\nСостояние: {}\nОшибок: {}; замечаний: {}\n\n{}\n\nПолный вывод: {}\nСобытия: {}\n\nСводка отражает зарегистрированные события. Нулевой код процесса не подтверждает выполнение каждого твика; проверка задержек не проводилась.\n",env!("CARGO_PKG_VERSION"),if self.errors>0 {"ЕСТЬ ОШИБКИ"}else if self.warnings>0 {"ЕСТЬ ЗАМЕЧАНИЯ"}else {"ЗАРЕГИСТРИРОВАННЫХ ОШИБОК НЕТ"},self.errors,self.warnings,self.tail.join("\n"),self.directory.join("output.txt").display(),self.directory.join("events.jsonl").display()))?;
        Ok(())
    }
    pub fn output(&mut self, text: &str) -> Result<()> {
        let text = crate::model::clean(text);
        writeln!(self.transcript, "{text}")?;
        self.transcript.flush()?;
        self.tail.extend(text.lines().map(str::to_owned));
        if self.tail.len() > 300 {
            self.tail.drain(..self.tail.len() - 300);
        }
        Ok(())
    }
}
